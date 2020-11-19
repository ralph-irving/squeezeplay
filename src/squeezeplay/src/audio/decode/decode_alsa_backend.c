/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"

#ifdef HAVE_SYSLOG
#include <syslog.h>
#endif

#include "audio/fifo.h"
#include "audio/fixed_math.h"
#include "audio/mqueue.h"
#include "audio/streambuf.h"
#include "audio/decode/decode.h"
#include "audio/decode/decode_priv.h"


#ifdef HAVE_LIBASOUND

#include <alsa/asoundlib.h>

/* for real-time behaviour */
#include <malloc.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/resource.h>


/* COMPAT */
#undef LOG_DEBUG
#undef LOG_INFO
#undef LOG_WARN
#undef LOG_ERROR
#undef IS_LOG_PRIORITY

static int is_debug = 0;

static __inline void log_printf(int level, const char *format, ...) {
	char buf[255];
	va_list va;

	va_start(va, format);
	vsnprintf(buf, sizeof(buf), format, va);
	va_end(va);

	if (is_debug) {
		char *lstr;
		struct timeval t;
		struct tm tm;

		gettimeofday(&t, NULL);
		gmtime_r(&t.tv_sec, &tm);

		switch (level) {
		case LOG_PRIORITY_ERROR:
			lstr = "ERROR";
			break;
		case LOG_PRIORITY_WARN:
			lstr = "WARN";
			break;
		case LOG_PRIORITY_INFO:
			lstr = "INFO";
			break;
		default:
		case LOG_PRIORITY_DEBUG:
			lstr = "DEBUG";
			break;
		}

		printf("%04d%02d%02d %02d:%02d:%02d.%03ld %-6s %s\n",
		       tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		       tm.tm_hour, tm.tm_min, tm.tm_sec,
		       (long)(t.tv_usec / 1000),
		       lstr, buf);
	}

#ifdef HAVE_SYSLOG
	syslog(level, "%s", buf);
#endif
}

#define LOG_DEBUG(FMT, ...) { if (is_debug) log_printf(LOG_PRIORITY_DEBUG, "%s:%d " FMT, __func__, __LINE__, ##__VA_ARGS__); }
#define LOG_INFO(FMT, ...) log_printf(LOG_PRIORITY_INFO, "%s:%d " FMT, __func__, __LINE__, ##__VA_ARGS__)
#define LOG_WARN(FMT, ...) log_printf(LOG_PRIORITY_WARN, "%s:%d " FMT, __func__, __LINE__, ##__VA_ARGS__)
#define LOG_ERROR(FMT, ...) log_printf(LOG_PRIORITY_ERROR, "%s:%d " FMT, __func__, __LINE__, ##__VA_ARGS__)
#define IS_LOG_PRIORITY(LEVEL) ((LEVEL==LOG_PRIORITY_DEBUG)?is_debug:1)


/* debug switches */
#define TEST_LATENCY 0
#define DEBUG_PAGEFAULTS 0


u8_t *decode_fifo_buf;
u8_t *effect_fifo_buf;
struct decode_audio *decode_audio;

#define FLAG_STREAM_PLAYBACK 0x01
#define FLAG_STREAM_EFFECTS  0x02
#define FLAG_STREAM_NOISE    0x04
#define FLAG_STREAM_LOOPBACK 0x08
#define FLAG_NOMMAP          0x10

#define PCM_WAIT_TIMEOUT     500

/* format list to try in order when opening device - each requires explicit support in playback callback */
static snd_pcm_format_t fmts[] = { SND_PCM_FORMAT_S32_LE, SND_PCM_FORMAT_S24_LE, SND_PCM_FORMAT_S24_3LE, SND_PCM_FORMAT_S16_LE, SND_PCM_FORMAT_UNKNOWN };

struct decode_alsa {
	/* device configuration */
	const char *playback_device;
	const char *capture_device;
	u32_t flags;
	unsigned int buffer_time;
	unsigned int period_count;
	snd_pcm_format_t output_format;

	/* alsa pcm state */
	snd_pcm_t *pcm;
	snd_pcm_t *capture_pcm;
	snd_pcm_format_t format;
	snd_pcm_sframes_t period_size;
	snd_pcm_sframes_t buffer_size;

	/* alsa control state */
	snd_hctl_t *hctl;
	snd_hctl_elem_t *iec958_elem;

	/* playback state */
	u32_t pcm_sample_rate;

	/* capture buffer */
	void *cbuf;
	ssize_t cbuf_size;

	/* parent */
	pid_t parent_pid;

	/* MMAP output available? */
	int has_mmap;

	u32_t pcm_wait_timeout;
};

#define PCM_FRAMES_TO_BYTES(frames) (snd_pcm_frames_to_bytes(state->pcm, (frames)))
#define PCM_BYTES_TO_FRAMES(frames) (snd_pcm_bytes_to_frames(state->pcm, (frames)))
#define PCM_SAMPLE_WIDTH() (snd_pcm_format_width(state->format))


/* alsa debugging */
static snd_output_t *output;

/* player state */
static struct decode_alsa state;

static int randomise_cpu = 0;

#define	timerspecsub(a, b, result) \
do { \
	(result)->tv_sec = (a)->tv_sec - (b)->tv_sec; \
	(result)->tv_nsec = (a)->tv_nsec - (b)->tv_nsec; \
	if ((result)->tv_nsec < 0) { \
		--(result)->tv_sec; \
		(result)->tv_nsec += 1000000000; \
	} \
} while (0)


#if TEST_LATENCY
#define TIMER_INIT(TOUT)			\
		struct timespec _t1, _t2, _td;	\
		float _tf, _tout = TOUT;	\
		clock_gettime(CLOCK_MONOTONIC, &_t1);

#define TIMER_CHECK(NAME) {						\
		clock_gettime(CLOCK_MONOTONIC, &_t2);			\
		timerspecsub(&_t2, &_t1, &_td);				\
		_tf = _td.tv_sec * 1000 + _td.tv_nsec / 1000000.0;	\
		if (_tf > _tout) {					\
			LOG_WARN(NAME " took too long %.3f ms limit %0.3f", _tf, _tout); \
			LOG_WARN(NAME " %d.%d %d.%d\n", _t1.tv_sec, _t1.tv_nsec, _t2.tv_sec, _t2.tv_nsec); \
		}							\
		memcpy(&_t1, &_t2, sizeof(struct timeval));		\
	}
#else
#define TIMER_INIT(TOUT)
#define TIMER_CHECK(NAME)
#endif

#if DEBUG_PAGEFAULTS
static void debug_pagefaults()
{
 	static struct rusage last_usage;
   	struct rusage usage;
	long majflt, minflt;
   
   	getrusage(RUSAGE_SELF, &usage);

	majflt = usage.ru_majflt - last_usage.ru_majflt;
	minflt = usage.ru_minflt - last_usage.ru_minflt;
	if (majflt > 0 || minflt > 0) {
		LOG_WARN("Pagefaults, Major:%ld Minor:%ld", majflt, minflt);
	}

	memcpy(&last_usage, &usage, sizeof(struct rusage));
}
#endif


/* noise source for testing */
static void generate_noise(void *outputBuffer,
			   unsigned long framesPerBuffer)
{
	sample_t val, *output_ptr = (sample_t *)outputBuffer;

	while (framesPerBuffer--) {
		val = rand() % 256 - 127;
		*output_ptr++ += val << 15;
		output_ptr++;
	}
}

static void decode_alsa_copyright(struct decode_alsa *state,
				  bool_t copyright)
{
	snd_ctl_elem_value_t *control;
	snd_aes_iec958_t iec958;
	int err;

	if (!state->iec958_elem) {
		/* not supported */
		return;
	}

	/* dies with warning on GCC 4.2:
	 * snd_ctl_elem_value_alloca(&control);
	 */
	control = (snd_ctl_elem_value_t *) alloca(snd_ctl_elem_value_sizeof());
	memset(control, 0, snd_ctl_elem_value_sizeof());

	if ((err = snd_hctl_elem_read(state->iec958_elem, control)) < 0) {
		LOG_ERROR("snd_hctl_elem_read error: %s", snd_strerror(err));
		return;
	}

	snd_ctl_elem_value_get_iec958(control, &iec958);

	/* bit 2, 0 = copyright, 1 = not copyright */
	if (copyright) {
		iec958.status[0] &= ~(1<<2);
	}
	else {
		iec958.status[0] |= (1<<2);
	}

	/* bit 3:5, 2 audio channels without pre-emphasis */
	iec958.status[0] &= ~(7<<3);

	snd_ctl_elem_value_set_iec958(control, &iec958);

	LOG_DEBUG("iec958 status: %02x %02x %02x %02x",
		  iec958.status[0], iec958.status[1], iec958.status[2], iec958.status[3]);

	if ((err = snd_hctl_elem_write(state->iec958_elem, control)) < 0) {
		LOG_ERROR("snd_hctl_elem_write error: %s", snd_strerror(err));
		return;
	}
}


/*
 * This function is called by to copy samples from the output buffer to
 * the alsa buffer.
 *
 * Called with fifo-lock held.
 */
static void playback_callback(struct decode_alsa *state,
			      void *output_buf,
			      size_t output_frames) {
	size_t decode_frames, skip_frames = 0;
	int add_silence_ms;
	bool_t reached_start_point;
	u8_t *output_buffer = (u8_t *)output_buf;

	ASSERT_AUDIO_LOCKED();

	decode_frames = BYTES_TO_SAMPLES(fifo_bytes_used(&decode_audio->fifo));

	/* Should we start the audio now based on having enough decoded data?
	   - override output_thresh for 176/192k and wait for 1 sec of data before starting */
	/* Supplementary note: this 1 sec  override is required for 352/384k to prevent stalls.
	   Refer note against 'DECODE_FIFO_SIZE' in 'decode_priv.h'. */
	if (decode_audio->state & DECODE_STATE_AUTOSTART
			&& decode_frames > (output_frames * (3 + state->period_count))
			&& decode_frames > (state->pcm_sample_rate <= 96000 ? (decode_audio->output_threshold * state->pcm_sample_rate / 10) :
								state->pcm_sample_rate)
		)
	{
		u32_t now = jive_jiffies();

		if (decode_audio->start_at_jiffies > now && now > decode_audio->start_at_jiffies - 5000)
			/* This does not consider any delay in the ALSA output chain - usually 1 period which is 10ms by default */
			decode_audio->add_silence_ms = decode_audio->start_at_jiffies - now;

		decode_audio->state &= ~DECODE_STATE_AUTOSTART;
		decode_audio->state |= DECODE_STATE_RUNNING;
	}

	/* audio running? */
	if (!(decode_audio->state & DECODE_STATE_RUNNING)) {
		memset(output_buffer, 0, PCM_FRAMES_TO_BYTES(output_frames));

		return;
	}

	add_silence_ms = decode_audio->add_silence_ms;
	if (add_silence_ms) {
		unsigned int add_frames;

		add_frames = (add_silence_ms * state->pcm_sample_rate) / 1000;
		if (add_frames > output_frames) {
			add_frames = output_frames;
		}
		memset(output_buffer, 0, PCM_FRAMES_TO_BYTES(add_frames));
		output_buffer += PCM_FRAMES_TO_BYTES(add_frames);
		output_frames -= add_frames;
		add_silence_ms -= (add_frames * 1000) / state->pcm_sample_rate;
		if (add_silence_ms < 2) {
			add_silence_ms = 0;
		}

		decode_audio->add_silence_ms = add_silence_ms;

		if (!output_frames) {
			return;
		}
	}

	/* only skip if it will not cause an underrun */
	if (decode_frames >= output_frames && decode_audio->skip_ahead_bytes > 0) {
		skip_frames = decode_frames - output_frames;
		if (skip_frames > BYTES_TO_SAMPLES(decode_audio->skip_ahead_bytes)) {
			skip_frames = BYTES_TO_SAMPLES(decode_audio->skip_ahead_bytes);
		}
	}

	if (decode_frames > output_frames) {
		decode_frames = output_frames;
	}

	/* audio underrun? */
	if (decode_frames < output_frames) {
		memset(output_buffer + PCM_FRAMES_TO_BYTES(decode_frames), 0, PCM_FRAMES_TO_BYTES(output_frames) - PCM_FRAMES_TO_BYTES(decode_frames));

		if ((decode_audio->state & DECODE_STATE_UNDERRUN) == 0) {
			LOG_ERROR("Audio underrun: used %ld frames, requested %ld frames. elapsed samples %ld", decode_frames, output_frames, decode_audio->elapsed_samples);
		}

		decode_audio->state |= DECODE_STATE_UNDERRUN;
	}
	else {
		decode_audio->state &= ~DECODE_STATE_UNDERRUN;
	}
	
	if (skip_frames) {
		size_t wrap_frames;

		LOG_DEBUG("Skipping %d frames", (int)skip_frames);
		
		wrap_frames = BYTES_TO_SAMPLES(fifo_bytes_until_rptr_wrap(&decode_audio->fifo));

		if (wrap_frames < skip_frames) {
			fifo_rptr_incby(&decode_audio->fifo, SAMPLES_TO_BYTES(wrap_frames));
			decode_audio->skip_ahead_bytes -= SAMPLES_TO_BYTES(wrap_frames);
			decode_audio->elapsed_samples += wrap_frames;
			skip_frames -= wrap_frames;
		}

		fifo_rptr_incby(&decode_audio->fifo, SAMPLES_TO_BYTES(skip_frames));
		decode_audio->skip_ahead_bytes -= SAMPLES_TO_BYTES(skip_frames);
		decode_audio->elapsed_samples += skip_frames;
	}

	while (decode_frames) {
		size_t wrap_frames, frames_write, frames_cnt;
		s32_t lgain, rgain;
		
		lgain = decode_audio->lgain;
		rgain = decode_audio->rgain;

		wrap_frames = BYTES_TO_SAMPLES(fifo_bytes_until_rptr_wrap(&decode_audio->fifo));

		frames_write = decode_frames;
		if (wrap_frames < frames_write) {
			frames_write = wrap_frames;
		}

		frames_cnt = frames_write;
		
		/* Handle fading and delayed fading */
		if (decode_audio->samples_to_fade) {
			if (decode_audio->samples_until_fade > frames_write) {
				decode_audio->samples_until_fade -= frames_write;
			}
			else {
				decode_audio->samples_until_fade = 0;
			
				/* initialize transition parameters */
				if (!decode_audio->transition_gain_step) {
					size_t nbytes;
					fft_fixed interval;
				
					interval = determine_transition_interval(decode_audio->transition_sample_rate, (u32_t)(decode_audio->samples_to_fade / decode_audio->transition_sample_rate), &nbytes);
					if (!interval)
						interval = 1;
					
					decode_audio->transition_gain_step = fixed_div(FIXED_ONE, fixed_mul(interval, s32_to_fixed(TRANSITION_STEPS_PER_SECOND)));
					decode_audio->transition_gain = FIXED_ONE;
					decode_audio->transition_sample_step = decode_audio->transition_sample_rate / TRANSITION_STEPS_PER_SECOND;
					decode_audio->transition_samples_in_step = 0;
				
					LOG_DEBUG("Starting FADEOUT over %d seconds, transition_gain_step %d, transition_sample_step %d",
						fixed_to_s32(interval), decode_audio->transition_gain_step, decode_audio->transition_sample_step);	
				}
				
				/* Apply transition gain to left/right gain values */
				lgain = fixed_mul(lgain, decode_audio->transition_gain);
				rgain = fixed_mul(rgain, decode_audio->transition_gain);
				
				/* Reduce transition gain when we've processed enough samples */
				decode_audio->transition_samples_in_step += frames_write;
				while (decode_audio->transition_gain && decode_audio->transition_samples_in_step >= decode_audio->transition_sample_step) {
					decode_audio->transition_samples_in_step -= decode_audio->transition_sample_step;
					decode_audio->transition_gain -= decode_audio->transition_gain_step;
				}
			}
		}

		switch (state->format) {
		case SND_PCM_FORMAT_S16_LE:
			{
				sample_t *decode_ptr;
				Sint16 *output_ptr;

				output_ptr = (Sint16 *)(void *)output_buffer;
				decode_ptr = (sample_t *)(void *)(decode_fifo_buf + decode_audio->fifo.rptr);

				if (lgain == FIXED_ONE && rgain == FIXED_ONE) {
					while (frames_cnt--) {
						*(output_ptr++) = *(decode_ptr++) >> 16;
						*(output_ptr++) = *(decode_ptr++) >> 16;
					}
				}
				else {
					while (frames_cnt--) {
						*(output_ptr++) = fixed_mul(lgain, *(decode_ptr++)) >> 16;
						*(output_ptr++) = fixed_mul(rgain, *(decode_ptr++)) >> 16;
					}
				}
			}
			break;
		case SND_PCM_FORMAT_S24_LE: 
			{
				sample_t *decode_ptr;
				Sint32 *output_ptr;
				
				output_ptr = (Sint32 *)(void *)output_buffer;
				decode_ptr = (sample_t *)(void *)(decode_fifo_buf + decode_audio->fifo.rptr);

				if (lgain == FIXED_ONE && rgain == FIXED_ONE) {
					while (frames_cnt--) {
						*(output_ptr++) = *(decode_ptr++) >> 8;
						*(output_ptr++) = *(decode_ptr++) >> 8;
					}
				}
				else {
					while (frames_cnt--) {
						*(output_ptr++) = fixed_mul(lgain, *(decode_ptr++)) >> 8;
						*(output_ptr++) = fixed_mul(rgain, *(decode_ptr++)) >> 8;
					}
				}
			}
			break;
		case SND_PCM_FORMAT_S24_3LE:
			{
				sample_t *decode_ptr;
				u8_t *output_ptr;
				
				output_ptr = (u8_t *)(void *)output_buffer;
				decode_ptr = (sample_t *)(void *)(decode_fifo_buf + decode_audio->fifo.rptr);

				if (lgain == FIXED_ONE && rgain == FIXED_ONE) {
					while (frames_cnt--) {
						sample_t lsample = *(decode_ptr++);
						sample_t rsample = *(decode_ptr++);
						*(output_ptr++) = (lsample & 0x0000ff00) >>  8;
						*(output_ptr++) = (lsample & 0x00ff0000) >> 16;
						*(output_ptr++) = (lsample & 0xff000000) >> 24;
						*(output_ptr++) = (rsample & 0x0000ff00) >>  8;
						*(output_ptr++) = (rsample & 0x00ff0000) >> 16;
						*(output_ptr++) = (rsample & 0xff000000) >> 24;
					}
				}
				else {
					while (frames_cnt--) {
						sample_t lsample = fixed_mul(lgain, *(decode_ptr++));
						sample_t rsample = fixed_mul(rgain, *(decode_ptr++));
						*(output_ptr++) = (lsample & 0x0000ff00) >>  8;
						*(output_ptr++) = (lsample & 0x00ff0000) >> 16;
						*(output_ptr++) = (lsample & 0xff000000) >> 24;
						*(output_ptr++) = (rsample & 0x0000ff00) >>  8;
						*(output_ptr++) = (rsample & 0x00ff0000) >> 16;
						*(output_ptr++) = (rsample & 0xff000000) >> 24;
					}
				}
			}
			break;
		case SND_PCM_FORMAT_S32_LE:
			{
				sample_t *decode_ptr;
				Sint32 *output_ptr;
				
				output_ptr = (Sint32 *)(void *)output_buffer;
				decode_ptr = (sample_t *)(void *)(decode_fifo_buf + decode_audio->fifo.rptr);

				if (lgain == FIXED_ONE && rgain == FIXED_ONE) {
					memcpy(output_ptr, decode_ptr, frames_cnt * 8);
				}
				else {
					while (frames_cnt--) {
						*(output_ptr++) = fixed_mul(lgain, *(decode_ptr++));
						*(output_ptr++) = fixed_mul(rgain, *(decode_ptr++));
					}
				}
			}
			break;
		default:
			break;
		}

		fifo_rptr_incby(&decode_audio->fifo, SAMPLES_TO_BYTES(frames_write));
		decode_audio->elapsed_samples += frames_write;

		output_buffer += PCM_FRAMES_TO_BYTES(frames_write);
		decode_frames -= frames_write;
	}

	reached_start_point = decode_check_start_point();
	if (reached_start_point) {
		decode_audio->samples_to_fade = 0;
		decode_audio->transition_gain_step = 0;
		
		if (decode_audio->track_sample_rate != state->pcm_sample_rate) {
			decode_audio->set_sample_rate = decode_audio->track_sample_rate;
		}

		LOG_DEBUG("playback started, copyright %s asserted", (decode_audio->track_copyright)?"is":"not");

		decode_alsa_copyright(state, decode_audio->track_copyright);
	}
}


static void capture_read(struct decode_alsa *state,
			 snd_pcm_uframes_t output_frames)
{
	snd_pcm_sframes_t frames;
	s16_t *ptr;

	assert(PCM_SAMPLE_WIDTH() == 16);

	if (state->cbuf_size < PCM_FRAMES_TO_BYTES(output_frames)) {
		if (state->cbuf) {
			free(state->cbuf);
		}
		state->cbuf = malloc(PCM_FRAMES_TO_BYTES(output_frames));
	}

	frames = snd_pcm_readi(state->capture_pcm, state->cbuf, output_frames);
	if (frames < 0) {
		LOG_WARN("overrun? %s", snd_strerror(frames));
		snd_pcm_recover(state->capture_pcm, frames, 1);
		memset(state->cbuf, 0, PCM_FRAMES_TO_BYTES(output_frames));
		return;
	}

	/* apply gain */
	ptr = state->cbuf;
	while(frames--) {
		*ptr = fixed_mul(decode_audio->capture_lgain, *ptr); ptr++;
		*ptr = fixed_mul(decode_audio->capture_rgain, *ptr); ptr++;
	}
}


static int pcm_close(struct decode_alsa *state, snd_pcm_t **pcmp, int mode) {
	int err;

	if (!*pcmp) {
		return 0;
	}

	if ((err = snd_pcm_drain(*pcmp)) < 0) {
		LOG_ERROR("snd_pcm_drain error: %s", snd_strerror(err));
	}

	if ((err = snd_pcm_close(*pcmp)) < 0) {
		LOG_ERROR("snd_pcm_close error: %s", snd_strerror(err));
	}

	*pcmp = NULL;

	if (state->hctl && mode == SND_PCM_STREAM_PLAYBACK) {
		snd_hctl_close(state->hctl);
		state->hctl = NULL;
		state->iec958_elem = NULL;
	}

	return 0;
}


static int _pcm_open(struct decode_alsa *state,
		     snd_pcm_t **pcmp,
		     int mode,
		     const char *device,
		     snd_pcm_access_t access,
		     u32_t sample_rate)
{
	int err, dir, fmt;
	unsigned int val;
	snd_pcm_uframes_t size;
	snd_ctl_elem_id_t *id;
	snd_pcm_hw_params_t *hw_params;
	int plug = 0;

	hw_params = (snd_pcm_hw_params_t *) alloca(snd_pcm_hw_params_sizeof());

	/* Close existing pcm (if any) */
	if (*pcmp) {
		pcm_close(state, pcmp, mode);
	}

	/* Open pcm */
	if ((err = snd_pcm_open(pcmp, device, mode, 0)) < 0) {
		LOG_ERROR("Playback open error: %s(%s)", snd_strerror(err), device);
		return err;
	}

	memset(hw_params, 0, snd_pcm_hw_params_sizeof());
	if ((err = snd_pcm_hw_params_any(*pcmp, hw_params)) < 0) {
		LOG_ERROR("hwparam init error: %s(%s)", snd_strerror(err), device);
		return err;
	}

	/* for hw devices - try exact rate first without resampling, otherwise reopen in plug mode with resampling */
	if (!strncmp(device, "hw:", 3)) {

		/* no hardware resampling */
		if ((err = snd_pcm_hw_params_set_rate_resample(*pcmp, hw_params, 0)) < 0) {
			LOG_ERROR("Resampling setup failed: %s", snd_strerror(err));
			return err;
		}

		/* try exact rate, otherwise reopen as plughw: with resampling */
		if ((err = snd_pcm_hw_params_set_rate(*pcmp, hw_params, sample_rate, 0)) < 0) {

			char *plug_device = alloca(strlen(device) + 4 + 1);
			strcpy(plug_device, "plug");
			strcat(plug_device, device);

			LOG_INFO("Reopening device %s in plug mode as %s", device, plug_device);
			device = plug_device;
			plug = 1;

			snd_pcm_close(*pcmp);
			if ((err = snd_pcm_open(pcmp, device, mode, 0)) < 0) {
				LOG_ERROR("Playback open error: %s", snd_strerror(err));
				return err;
			}

			memset(hw_params, 0, snd_pcm_hw_params_sizeof());
			if ((err = snd_pcm_hw_params_any(*pcmp, hw_params)) < 0) {
				LOG_ERROR("hwparam init error: %s", snd_strerror(err));
				return err;
			}

			if ((err = snd_pcm_hw_params_set_rate_resample(*pcmp, hw_params, 1)) < 0) {
				LOG_ERROR("Resampling setup failed: %s", snd_strerror(err));
				return err;
			}

			val = sample_rate;
			if ((err = snd_pcm_hw_params_set_rate_near(*pcmp, hw_params, &val, 0)) < 0) {
				LOG_ERROR("Rate not available: %s", snd_strerror(err));
				return err;
			}
		}

	/* default device */
	} else {

		/* hardware resampling enabled  */
		if ((err = snd_pcm_hw_params_set_rate_resample(*pcmp, hw_params, 1)) < 0) {
			LOG_ERROR("Resampling setup failed: %s", snd_strerror(err));
			return err;
		}

		val = sample_rate;
		if ((err = snd_pcm_hw_params_set_rate_near(*pcmp, hw_params, &val, 0)) < 0) {
			LOG_ERROR("Rate not available: %s", snd_strerror(err));
			return err;
		}
	}

	/* set access format */
	if ((err = snd_pcm_hw_params_set_access(*pcmp, hw_params, access)) < 0) {
		LOG_ERROR("Access type not available: %s", snd_strerror(err));
		return err;
	}

	/* set the sample format */
	fmt = 0;
	while (fmts[fmt] != SND_PCM_FORMAT_UNKNOWN) {
		if (snd_pcm_hw_params_set_format(*pcmp, hw_params, fmts[fmt]) >= 0) {
			LOG_INFO("Opened device %s using format: %s sample rate: %u", device, snd_pcm_format_name(fmts[fmt]), sample_rate);
			state->format = fmts[fmt];
			break;
		}
		++fmt;
	}

	if (fmts[fmt] == SND_PCM_FORMAT_UNKNOWN) {
		LOG_ERROR("Unable to open audio device with any supported format");
		return -1;
	}

	/* set the channel count */
	if ((err = snd_pcm_hw_params_set_channels(*pcmp, hw_params, 2)) < 0) {
		LOG_ERROR("Channel count not available: %s", snd_strerror(err));
		return err;
	}

	/* set buffer and period times */
	val = !plug ? state->period_count : 2;  // safe value when plug layer used, else snd_pcm_close can crash
	if ((err = snd_pcm_hw_params_set_periods_near(*pcmp, hw_params, &val, 0)) < 0) {
		LOG_ERROR("Unable to set period size %s", snd_strerror(err));
		return err;
	}
	else
	{
		LOG_INFO("Using buffer period count: %d", val);
	}
	state->period_count = val;

	val = !plug ? state->buffer_time : 20000; // safe value when plug layer used, else snd_pcm_close can crash
	dir = 1;
	if ((err = snd_pcm_hw_params_set_buffer_time_near(*pcmp, hw_params, &val, &dir)) < 0) {
		LOG_ERROR("Unable to set  buffer time %s", snd_strerror(err));
		return err;
	}
	else
	{
		LOG_INFO("Using buffer time: %d", val);
	}

	/* set hardware parameters */
	if ((err = snd_pcm_hw_params(*pcmp, hw_params)) < 0) {
		LOG_ERROR("Unable to set hw params: %s", snd_strerror(err));
		return err;
	}

	if ((err = snd_pcm_hw_params_get_period_size(hw_params, &size, 0)) < 0) {
		LOG_ERROR("Unable to get period size: %s", snd_strerror(err));
		return err;
	}
	state->period_size = size;

	if ((err = snd_pcm_hw_params_get_buffer_size(hw_params, &size)) < 0) {
		LOG_ERROR("Unable to get buffer size: %s", snd_strerror(err));
		return err;
	}
	state->buffer_size = size;

	/* iec958 control for playback device only */
	if (!(state->flags & FLAG_STREAM_PLAYBACK) || mode != SND_PCM_STREAM_PLAYBACK) {
		goto skip_iec958;	  
	}

	if ((err = snd_hctl_open(&state->hctl, state->playback_device, 0)) < 0) {
		LOG_ERROR("snd_hctl_open failed: %s", snd_strerror(err));
		goto skip_iec958;
	}

	if ((err = snd_hctl_load(state->hctl)) < 0) {
		LOG_ERROR("snd_hctl_load failed: %s", snd_strerror(err));
		goto skip_iec958;
	}

	/* dies with warning on GCC 4.2:
	 * snd_ctl_elem_id_alloca(&id);
	 */
	id = (snd_ctl_elem_id_t *) alloca(snd_ctl_elem_id_sizeof());
	memset(id, 0, snd_ctl_elem_id_sizeof());
	snd_ctl_elem_id_set_interface(id, SND_CTL_ELEM_IFACE_MIXER);
	snd_ctl_elem_id_set_name(id, "IEC958 Playback Default");

	state->iec958_elem = snd_hctl_find_elem(state->hctl, id);

 skip_iec958:
	if (IS_LOG_PRIORITY(LOG_PRIORITY_DEBUG)) {
		snd_pcm_dump(*pcmp, output);
	}

	return 0;
}


static int pcm_open(struct decode_alsa *state, bool_t loopback, int mode)
{
	int err = 0;

	if (mode == SND_PCM_STREAM_PLAYBACK) {
		u32_t sample_rate;


		decode_audio_lock();
		sample_rate = decode_audio->set_sample_rate;
		decode_audio_unlock();

		if (sample_rate == 0 || sample_rate > 384000) {
			LOG_ERROR("invalid sample rate\n");
			sample_rate = 44100;
		}

		if ( !(state->flags & FLAG_NOMMAP) ) {
			LOG_DEBUG("PCM Open %X %s",state->flags,state->playback_device);
			err = _pcm_open(state,
				&state->pcm,
				mode,
				state->playback_device,
				SND_PCM_ACCESS_MMAP_INTERLEAVED,
				sample_rate);
			state->has_mmap = 1;
		}

		if (err < 0 || (state->flags & FLAG_NOMMAP) ) {
                        if (err < 0) {
			   LOG_WARN("PCM Open with mmap failed trying to continue,%s\n",snd_strerror(err));
                        }
			LOG_DEBUG("PCM Open NOMMAP %X %s",state,state->playback_device);
			/* Retry without MMAP */
			err = _pcm_open(state,
					&state->pcm,
					mode,
					state->playback_device,
					SND_PCM_ACCESS_RW_INTERLEAVED,
					sample_rate);
			state->has_mmap = 0;
		}

		if (err < 0) {
			return err;
		}

		state->pcm_sample_rate = sample_rate;
	}
	else {
		err = _pcm_open(state,
				&state->capture_pcm,
				mode,
				state->capture_device,
				SND_PCM_ACCESS_RW_INTERLEAVED,
				state->pcm_sample_rate);

		if (err < 0) {
			return err;
		}
	}

	return 0;
}


static int pcm_probe(const char *device) {
	snd_pcm_t *pcm;
	int err;

	if ((err = snd_pcm_open(&pcm, device, SND_PCM_STREAM_PLAYBACK, 0)) < 0) {
		return err;
	}

	if ((err = snd_pcm_close(pcm)) < 0) {
		LOG_ERROR("snd_pcm_close error: %s", snd_strerror(err));
	}

	return 0;
}


static int pcm_test(struct decode_alsa *state) {
	snd_pcm_t *pcm;
	snd_pcm_hw_params_t *hw_params;
	int err;

	/* Open pcm */
	if ((err = snd_pcm_open(&pcm, state->playback_device, SND_PCM_STREAM_PLAYBACK, 0)) < 0) {
		LOG_ERROR("Playback open error: %s (%s)", snd_strerror(err),state->playback_device);
		return err;
	}

	/* Set hardware parameters */
	hw_params = (snd_pcm_hw_params_t *) alloca(snd_pcm_hw_params_sizeof());
	memset(hw_params, 0, snd_pcm_hw_params_sizeof());

	/* get maxmimum supported rate */
	if ((err = snd_pcm_hw_params_any(pcm, hw_params)) < 0) {
		LOG_ERROR("hwparam init error: %s(%s)", snd_strerror(err),state->playback_device);
		goto err;
	}

	if ((err = snd_pcm_hw_params_set_rate_resample(pcm, hw_params, 0)) < 0) {
		LOG_ERROR("Resampling setup failed: %s(%s)", snd_strerror(err),state->playback_device);
		goto err;
	}

	if ((err = snd_pcm_hw_params_get_rate_max(hw_params, &decode_audio->max_rate, 0)) < 0) {
		LOG_ERROR("Get Rate max failed: %s(%s)", snd_strerror(err),state->playback_device);
		goto err;
	}
	LOG_DEBUG("max sample rate %d", decode_audio->max_rate);

	if ((err = snd_pcm_close(pcm)) < 0) {
		LOG_ERROR("snd_pcm_close error: %s", snd_strerror(err));
	}

	return 0;

err:
	if ((err = snd_pcm_close(pcm)) < 0) {
		LOG_ERROR("snd_pcm_close error: %s", snd_strerror(err));
	}

	return -1;
}


static void *audio_thread_execute(void *data) {
	struct decode_alsa *state = (struct decode_alsa *)data;
	snd_pcm_state_t pcm_state;
	snd_pcm_uframes_t size;
	snd_pcm_sframes_t avail;
	snd_pcm_status_t *status;
	int err, count = 0, count_max = 441, first = 1;
	u32_t delay, do_open = 1;
	void *buf = NULL;

	LOG_DEBUG("audio_thread_execute");

	if (randomise_cpu) LOG_INFO("cpu randomisation enabled");

	/* assume we'll be 44.1k to start with */
	decode_audio->set_sample_rate = 44100;

	status = malloc(snd_pcm_hw_params_sizeof());

	while (1) {
		TIMER_INIT(10.0f); /* 10 ms limit */

		if (do_open == 2) {
			// wait until device returns - to allow usb audio devices to be turned off
			while (pcm_probe(state->playback_device) < 0) {
				LOG_DEBUG("waiting for device %s to return", state->playback_device);
				sleep(2);
			}
		}

		if (do_open) {
			
			bool_t loopback = ((decode_audio->state & DECODE_STATE_LOOPBACK) != 0);

			do_open = 0;

			if (loopback) {
				decode_audio->set_sample_rate = 44100;
			}

			if ((err = pcm_open(state, loopback, SND_PCM_STREAM_PLAYBACK)) < 0) {
				LOG_ERROR("Playback open failed: %s", snd_strerror(err));
				goto thread_error;
			}
			assert(state->pcm);

			if (state->capture_device && loopback) {
				if ((err = pcm_open(state, loopback, SND_PCM_STREAM_CAPTURE)) < 0) {
					LOG_ERROR("Capture open failed: %s", snd_strerror(err));
					goto thread_error;
				}
			}
			else {
				pcm_close(state, &state->capture_pcm, SND_PCM_STREAM_CAPTURE);
			}

			first = 1;
			count_max = state->pcm_sample_rate / 1000;
		}

		if (count++ > count_max) {
			count = 0;

#if DEBUG_PAGEFAULTS
			debug_pagefaults();
#endif

			if (kill(state->parent_pid, 0) < 0) {
				/* parent is dead, exit */
				LOG_ERROR("exit, parent is dead");
				goto thread_error;
			}
		}
		    
		TIMER_CHECK("OPEN");

		pcm_state = snd_pcm_state(state->pcm);
		if (pcm_state == SND_PCM_STATE_XRUN) {
			struct timeval now, diff, tstamp;
			gettimeofday(&now, 0);
			snd_pcm_status_get_trigger_tstamp(status, &tstamp);
			timersub(&tstamp, &now, &diff);
			LOG_WARN("underrun!!! (at least %.3f ms long)", diff.tv_sec * 1000.0 + diff.tv_usec / 1000.0);

			if ((err = snd_pcm_recover(state->pcm, -EPIPE, 1)) < 0) {
				LOG_ERROR("XRUN recovery failed: %s", snd_strerror(err));
			}
			first = 1;
		}
		else if (pcm_state == SND_PCM_STATE_SUSPENDED) {
			if ((err = snd_pcm_recover(state->pcm, -ESTRPIPE, 1)) < 0) {
				LOG_ERROR("SUSPEND recovery failed: %s", snd_strerror(err));
			}
		}

		avail = snd_pcm_avail_update(state->pcm);
		if (avail < 0) {
			LOG_WARN("xrun (avail_update)");
			if ((err = snd_pcm_recover(state->pcm, avail, 1)) < 0) {
				LOG_ERROR("Avail update failed: %s", snd_strerror(err));
				if (err == -ENODEV) {
					LOG_WARN("Device %s no longer available - waiting for it to return", state->playback_device);
					do_open = 2;
					continue;
				}
			}
			first = 1;
			continue;
		}

		if (avail > state->buffer_size) {
			LOG_WARN( "snd_pcm_avail_update returned %#lx frames, but buffer "
			          "size is only %#lx frames. Re-opening pcm device.",
			          avail, state->buffer_size);
			do_open = 1;
			continue;
		}

		/* this is needed to ensure the sound works on resume */
		if (( err = snd_pcm_status(state->pcm, status)) < 0) {
			LOG_ERROR("snd_pcm_status err=%s", snd_strerror(err));
		}

		TIMER_CHECK("STATE");

		if (avail < state->period_size) {
			if (first) {
				first = 0;

				if ((err = snd_pcm_start(state->pcm)) < 0) {
					LOG_ERROR("snd_pcm_start error: %s", snd_strerror(err));
				}

				if (state->capture_pcm) {
					if ((err = snd_pcm_start(state->capture_pcm)) < 0) {
						LOG_ERROR("snd_pcm_start capture error: %s", snd_strerror(err));
					}
				}
			}
			else {
				if (randomise_cpu) {
					// apply jitter to wait period to avoid metronomic scheduling of this process
					// wait = time until full period_size would be available + then add 0-90% of period of jitter
					unsigned wait_us = (state->period_size - avail) * 1000000 / state->pcm_sample_rate;
					unsigned jitter = rand() % (state->period_size * 900000 / state->pcm_sample_rate);
					usleep(wait_us + jitter);
					avail = snd_pcm_avail_update(state->pcm);
				}
		
				if (avail < state->period_size) {
					if ((err = snd_pcm_wait(state->pcm, state->pcm_wait_timeout)) < 0) {
						LOG_WARN("xrun (snd_pcm_wait) err=%s",snd_strerror(err));
						if ((err = snd_pcm_recover(state->pcm, err, 1)) < 0) {
							LOG_ERROR("PCM wait recover failed: %s", snd_strerror(err));
						}
						first = 1;
					}
				}

				if (err == 0) {
					LOG_INFO("snd_pcm_wait timeout(%d)",state->pcm_wait_timeout);
				}

			}
			continue;
		}

		TIMER_CHECK("WAIT");

		size = state->period_size;
		while (size > 0) {
			const snd_pcm_channel_area_t *areas;
			snd_pcm_uframes_t frames, offset;
			snd_pcm_sframes_t commitres;

			frames = size;

			if (state->capture_pcm) {
				capture_read(state, frames);
			}

			if (state->has_mmap) {
				if ((err = snd_pcm_mmap_begin(state->pcm, &areas, &offset, &frames)) < 0) {
					LOG_WARN("xrun (snd_pcm_mmap_begin) err=%s", snd_strerror(err));
					if ((err = snd_pcm_recover(state->pcm, err, 1)) < 0) {
						LOG_ERROR("mmap begin failed: %s", snd_strerror(err));
					}
					first = 1;
				}
			}

			TIMER_CHECK("BEGIN");

			if (state->has_mmap) {
				buf = ((u8_t *)areas[0].addr) + (areas[0].first + offset * areas[0].step) / 8;
			} else {
				if (!buf)
					buf = malloc(PCM_FRAMES_TO_BYTES(state->period_size));
			}

			if (state->flags & FLAG_STREAM_PLAYBACK) {
				decode_audio_lock();
				TIMER_CHECK("LOCK");

				if (state->capture_pcm) {
					memcpy(buf, state->cbuf, PCM_FRAMES_TO_BYTES(frames));
				}
				else {

					/* sync accurate playpoint */
					if (size == ( snd_pcm_uframes_t) state->period_size) {
						/* only first time around loop, before calling playback_callback(),
						 * because then this should be just after the ALSA DMA interrupt has fired
						 * which will have actualised the delay validity */

						decode_audio->sync_elapsed_samples = decode_audio->elapsed_samples;
						delay = snd_pcm_status_get_delay(status);

						if (decode_audio->sync_elapsed_samples > delay) {
							decode_audio->sync_elapsed_samples -= delay;
						}
						
						/* have not reached start of track yet */
						else {
							/* This value - '0' - will usually be an over-estimate;
							 * The STMs (track-start) can then be sent prematurely by up to 20ms
							 * (or more if non-default ALSA parameters are being used)
							 * but this is rather unlikely in practice.
							 */
							decode_audio->sync_elapsed_samples = 0;
						}
					
						decode_audio->sync_elapsed_timestamp = jive_jiffies();
					}

					playback_callback(state, buf, frames);
				}

				/* sample rate changed? we do this check while the
				 * fifo is locked, so we don't need to lock it twice
				 * per loop.
				 */
				do_open = (decode_audio->set_sample_rate && (decode_audio->set_sample_rate != state->pcm_sample_rate)) ? 1 : 0;

				/* start or stop loopback? */
				if (state->capture_device && decode_audio->state & DECODE_STATE_LOOPBACK) {
					do_open |= (state->capture_pcm) ? 0 : 1;
				}
				else {
					do_open |= (state->capture_pcm) ? 1 : 0;
				}

				decode_audio_unlock();
			}
			else {
				memset(buf, 0, PCM_FRAMES_TO_BYTES(frames));
			}

			TIMER_CHECK("PLAYBACK");

			if (state->flags & FLAG_STREAM_NOISE) {
				generate_noise(buf, frames);
			}

			if (state->flags & FLAG_STREAM_EFFECTS) {
				decode_mix_effects(buf, frames, PCM_SAMPLE_WIDTH(), state->pcm_sample_rate);
			}

			TIMER_CHECK("EFFECTS");

			if (state->has_mmap) {
				commitres = snd_pcm_mmap_commit(state->pcm, offset, frames); 
				if (commitres < 0 || (snd_pcm_uframes_t)commitres != frames) { 
					LOG_WARN("xrun (snd_pcm_mmap_commit) err=%s", snd_strerror(commitres));
					if ((err = snd_pcm_recover(state->pcm, commitres, 1)) < 0) {
						LOG_ERROR("mmap commit failed: %s", snd_strerror(err));
					}
					first = 1;
				}
			} else {
				commitres = snd_pcm_writei(state->pcm, buf, frames); 
				if (commitres < 0 || (snd_pcm_uframes_t)commitres != frames) { 
					LOG_WARN("xrun (snd_pcm_writei) err=%s", snd_strerror(commitres));
					if ((err = snd_pcm_recover(state->pcm, commitres, 1)) < 0) {
						LOG_ERROR("PCM recover failed sound writei failed: %s", snd_strerror(err));
					}
					first = 1;
				}
			}

			size -= frames;

			TIMER_CHECK("COMMIT");
		}
	}

 thread_error:
	if (!state->has_mmap && buf) free(buf);
	free(status);

	LOG_ERROR("Audio thread exited");
	return (void *)-1;
}


static int decode_realtime_process(struct decode_alsa *state)
{
	struct sched_param sched_param;
	int err;

	/* Set realtime scheduler policy. Use 45 as the PREEMPT_PR patches
	 * use 50 as the default prioity of the kernel tasklets and irq 
	 * handlers.
	 *
	 * For the best performance on a tuned RT kernel, make non-audio
	 * threads have a priority < 45.
	 */
	sched_param.sched_priority = (state->flags & FLAG_STREAM_PLAYBACK) ? 45 : 35;

	if ((err = sched_setscheduler(0, SCHED_FIFO, &sched_param)) == -1) {
		if (errno == EPERM) {
			LOG_INFO("Can't set audio thread priority");
			return -1;
		}
		else {
			LOG_ERROR("sched_setscheduler: %s", strerror(errno));
			return -1;
		}
	}

	return 0;
}

static int decode_lock_memory()
{
	size_t i, page_size;

	/* lock all current and future pages into ram */
	if (mlockall(MCL_CURRENT | MCL_FUTURE)) {
		LOG_WARN("mlockall failed");
		return -1;
	}

	/* Turn off malloc trimming.*/
   	mallopt(M_TRIM_THRESHOLD, -1);
	LOG_DEBUG("malloc trim");
   
   	/* Turn off mmap usage. */
   	mallopt(M_MMAP_MAX, 0);
	LOG_DEBUG("mmap max");


	page_size = sysconf(_SC_PAGESIZE);

	/* touch each page of buffer */
	for (i=0; i<DECODE_AUDIO_BUFFER_SIZE; i+=page_size) {
		*(decode_fifo_buf + i) = 0;
	}

#if DEBUG_PAGEFAULTS
	debug_pagefaults();
#endif
	
	LOG_DEBUG("decode_lock_memory done");
	return 0;
}


static int decode_alsa_shared_mem_attach(void)
{
	int shmid;

	/* attach to shared memory */
	shmid = shmget(56833, 0, 0600 | IPC_CREAT);
	// XXXX errors

	decode_audio = shmat(shmid, 0, 0);
	// XXXX errors

	decode_fifo_buf = (((u8_t *)decode_audio) + sizeof(struct decode_audio));
	effect_fifo_buf = ((u8_t *)decode_fifo_buf) + DECODE_FIFO_SIZE;

	return 0;
}


int main(int argv, char **argc)
{
	struct utsname utsname;
	int err, i;

#ifdef HAVE_SYSLOG
	openlog("squeezeplay_alsa", LOG_ODELAY | LOG_CONS | LOG_PID, LOG_USER);
#endif
        LOG_DEBUG("Parse Args")
	/* parse args */
	for (i=1; i<argv; i++) {
		if (strcmp(argc[i], "-v") == 0) {
			is_debug = 1;
		}
		else if (strcmp(argc[i], "-d") == 0) {
			state.playback_device = argc[++i];
		}
		else if (strcmp(argc[i], "-c") == 0) {
			state.capture_device = argc[++i];
		}
		else if (strcmp(argc[i], "-b") == 0) {
			state.buffer_time = strtoul(argc[++i], NULL, 0);
		}
		else if (strcmp(argc[i], "-p") == 0) {
			state.period_count = strtoul(argc[++i], NULL, 0);
			// period_count > 100 used to enable cpu randomisation
			if (state.period_count > 100) {
				state.period_count -= 100;
				randomise_cpu = 1;
			}
		}
		else if (strcmp(argc[i], "-f") == 0) {
			state.flags = strtoul(argc[++i], NULL, 0);
		}
		else if (strcmp(argc[i], "-t") == 0) {
			state.pcm_wait_timeout = strtoul(argc[++i], NULL, 0);
                }
                else if (strcmp(argc[i], "-s") == 0) {
                        if (strcmp(argc[++i], "0") == 0) {
				// NoOp... Auto
                        }
                        else if (strcmp(argc[i], "32") == 0) {
                                fmts[0] = SND_PCM_FORMAT_S32_LE;
                                fmts[1] = SND_PCM_FORMAT_UNKNOWN;
                        }
                        else if (strcmp(argc[i], "24") == 0) {
                                fmts[0] = SND_PCM_FORMAT_S24_LE;
                                fmts[1] = SND_PCM_FORMAT_UNKNOWN;
                        }
                        else if (strcmp(argc[i], "24_3") == 0) {
                                fmts[0] = SND_PCM_FORMAT_S24_3LE;
                                fmts[1] = SND_PCM_FORMAT_UNKNOWN;
                        }
                        else if (strcmp(argc[i], "16") == 0) {
                                fmts[0] = SND_PCM_FORMAT_S16_LE;
                                fmts[1] = SND_PCM_FORMAT_UNKNOWN;
                        }
                }
	}

	if (!state.playback_device || !state.buffer_time || !state.period_count || !state.flags) {
		printf("Usage: %s [-v] -d <playback_device> [-c <capture_device>] [ -t <pcm_timeout>] [ -s <sample_size>] -b <buffer_time> -p <period_count> -f <flags>\n", argc[0]);
		exit(-1);
	}

	if(!state.pcm_wait_timeout) {
		state.pcm_wait_timeout = PCM_WAIT_TIMEOUT;
	}

	/* attach to shared memory buffer */
	if (decode_alsa_shared_mem_attach() != 0) {
		LOG_ERROR("Can't attach to shared memory");
		exit(-1);
	}

	/* do this on RT Linux only, as it seems to interfere with suspend/resume on jive */
	if ((err = uname(&utsname)) < 0) {
		LOG_ERROR("uname failed: %s", snd_strerror(err));
		exit(-1);
	}
	if (strstr(utsname.version, "PREEMPT") != NULL) {
		decode_lock_memory();
	} else {
		LOG_INFO("PREEMPT Not Detected");
	}

	/* who is our parent */
	state.parent_pid = getppid();

	/* alsa messages */
	if ((err = snd_output_stdio_attach(&output, stdout, 0)) < 0) {
		LOG_ERROR("Output failed: %s", snd_strerror(err));
		exit(-1);
	}

	/* test audio device */
	if (pcm_test(&state) < 0) {
		LOG_ERROR("exit, pcm_test failed");
		exit(0);
	}

	/* set real-time properties */
	decode_realtime_process(&state);

	/* wake parent */
	decode_audio_lock();
	decode_audio->running = true;
	fifo_signal(&decode_audio->fifo);
	decode_audio_unlock();

	/* start thread */
	audio_thread_execute(&state);

	LOG_INFO("Audio Thread Exited");
	exit(0);
}


#endif // HAVE_LIBASOUND
