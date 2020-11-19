/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


#ifndef AUDIO_DECODE_PRIV
#define AUDIO_DECODE_PRIV

#include "audio/fifo.h"
#include "audio/fixed_math.h"


extern LOG_CATEGORY *log_audio_decode;
extern LOG_CATEGORY *log_audio_codec;
extern LOG_CATEGORY *log_audio_output;

#define TRANSITION_NONE         0x0
#define TRANSITION_CROSSFADE    0x1
#define TRANSITION_FADE_IN      0x2
#define TRANSITION_FADE_OUT     0x4
#define TRANSITION_IMMEDIATE    0x8

/* Transition steps per second should be a common factor
 * of all supported sample rates.
 */
#define TRANSITION_STEPS_PER_SECOND 10
#define TRANSITION_MINIMUM_SECONDS 1
#define TRANSITION_MAXIMUM_SECONDS 10

/* Audio sample, 32-bits. */
typedef s32_t sample_t;

#define SAMPLE_MAX (sample_t)0x7FFFFFFF
#define SAMPLE_MIN (sample_t)0x80000000

static inline sample_t sample_clip(sample_t a, sample_t b) {
	s64_t s = a + b;

	if (s < SAMPLE_MIN) {
		return SAMPLE_MIN;
	} else if (s > SAMPLE_MAX) {
		return SAMPLE_MAX;
	}
	else {
		return s;
	}
}


/* Effect sample, 16-bits. */
typedef s16_t effect_t;


#define DECODER_MAX_PARAMS 32


/* Decode interface */
struct decode_module {
	u32_t id;
	char *name;
	/* start the decode, params is from SC */
	void *(*start)(u8_t *params, u32_t num_params);
	/* stop and free the decode */
	void (*stop)(void *data);
	/* max samples to be written to output buffer */
	size_t (*samples)(void *data);
	/* callback to decode samples to output buffer */
	bool_t (*callback)(void *data);
};


/* Built-in decoders */ 
extern struct decode_module decode_tones;
extern struct decode_module decode_pcm;
extern struct decode_module decode_flac;
extern struct decode_module decode_mad;
extern struct decode_module decode_vorbis;
extern struct decode_module decode_alac;
#ifdef WITH_SPPRIVATE
extern struct decode_module decode_wma;
extern struct decode_module decode_aac;
extern struct decode_module decode_spotify;
#else
extern struct decode_module decode_aac;
#endif


/* Private decoder api */
extern u32_t current_decoder_state;

extern void decode_keepalive(int ticks);

extern u32_t decode_output_percent_used(void);

extern void decode_output_samples(sample_t *buffer, u32_t samples, int sample_rate);

extern int decode_output_samplerate(void);

extern int decode_output_max_rate(void);

extern void decode_output_song_ended(void);

extern void decode_output_set_transition(u32_t type, u32_t period);

extern void decode_output_set_track_gain(u32_t replay_gain);

extern void decode_set_track_polarity_inversion(u8_t inversion);

extern void decode_set_output_channels(u8_t channels);
extern void decode_set_trigger_resume(void);


/* Audio output backends */
struct decode_audio_func {
	int (*init)(lua_State *L);
	void (*start)(void);
	void (*pause)(void);
	void (*resume)(void);
	void (*stop)(void);
};

struct decode_audio {
	struct decode_audio_func *f;

	/* fifo locks: playback state, track state, sync state */
	struct fifo fifo;

	/* playback state */
	bool_t running;
	u32_t state;
	s32_t lgain, rgain;
	s32_t capture_lgain, capture_rgain;
	u32_t set_sample_rate;

	u32_t output_threshold; /* tenths of a second */

	u32_t sync_elapsed_samples;
	u32_t sync_elapsed_timestamp;

	/* track state */
	bool_t check_start_point;
	size_t track_start_point;
	bool_t track_copyright;
	u32_t track_sample_rate;
	u32_t elapsed_samples;
	u32_t num_tracks_started;
	
	/* sync state */
	size_t skip_ahead_bytes;
	int add_silence_ms;
	u32_t start_at_jiffies;

	/* effect_fifo locks: effect_gain */
	struct fifo effect_fifo;
	fft_fixed effect_gain;

	/* device info */
	u32_t max_rate;
	
	/* fading state */
	u32_t samples_until_fade;
	u32_t samples_to_fade;
	u32_t transition_sample_rate;
	fft_fixed transition_gain;
	fft_fixed transition_gain_step;
	u32_t transition_sample_step;
	u32_t transition_samples_in_step;
};

extern struct decode_audio *decode_audio;

#define decode_audio_lock() fifo_lock(&(decode_audio->fifo))
#define decode_audio_unlock() fifo_unlock(&(decode_audio->fifo))

#define ASSERT_AUDIO_LOCKED() ASSERT_FIFO_LOCKED(&(decode_audio->fifo))

/* Audio output backends */
extern struct decode_audio_func decode_alsa;
extern struct decode_audio_func decode_portaudio;
extern struct decode_audio_func decode_null;

/* Decode output api */
extern void decode_init_buffers(void *buf, bool_t prio_inherit);
extern void decode_output_begin(void);
extern void decode_output_end(void);
extern void decode_output_flush(void);
extern bool_t decode_check_start_point(void);
extern void decode_mix_effects(void *outputBuffer, size_t framesPerBuffer, int sample_width, int output_sample_rate);


/* Sample playback api (sound effects) */
extern int decode_sample_init(lua_State *L);
extern void decode_sample_fill_buffer(void);


/* visualizers */
extern int decode_vumeter(lua_State *L);
extern int decode_spectrum(lua_State *L);
extern int decode_spectrum_init(lua_State *L);

/* Internal state */

#define SAMPLES_TO_BYTES(n)  (2 * (n) * sizeof(sample_t))
#define BYTES_TO_SAMPLES(n)  ((n) / (2 * sizeof(sample_t)))

/* State variables for the current track */
extern bool_t decode_first_buffer;


/* The fifo used to store decoded samples */
/* '10 * 2 * 44100 * sizeof(sample_t)' equates to:
	10 seconds of a 44,100 Hz stream,
	2.29 seconds of a 192,000 Hz stream,
	1.14 seconds of a 384,000 Hz stream.
    SqueezePlay will stall if the requested output threshold approaches
    these limits. For example, LMS sets an output threshold of 2 seconds
    for a 'high sample rate ( >= 88200 )' flac stream.
    Refer 'decode_alsa_backend.c' and 'decode_portaudio.c' for mitigation.
*/
#define DECODE_FIFO_SIZE (10 * 2 * 44100 * sizeof(sample_t)) 
extern u8_t *decode_fifo_buf;

#define EFFECT_FIFO_SIZE (1 * 1 * 44100 * sizeof(effect_t))
extern u8_t *effect_fifo_buf;

#define DECODE_AUDIO_BUFFER_SIZE (sizeof(struct decode_audio) + DECODE_FIFO_SIZE + EFFECT_FIFO_SIZE)

/* Decode message queue */
extern struct mqueue decode_mqueue;

/* This is here because it's needed in decode_alsa_backend.
 * Determine whether we have enough audio in the output buffer to do
 * a transition. Start at the requested transition interval and go
 * down till we find an interval that we have enough audio for.
 */
static fft_fixed determine_transition_interval(u32_t sample_rate, u32_t transition_period, size_t *nbytes) {
	size_t bytes_used, sample_step_bytes;
	fft_fixed interval, interval_step;
	u32_t transition_sample_step;

	ASSERT_AUDIO_LOCKED();

	if (sample_rate != decode_audio->track_sample_rate) {
		return 0;
	}

	bytes_used = fifo_bytes_used(&decode_audio->fifo);
	*nbytes = SAMPLES_TO_BYTES(TRANSITION_MINIMUM_SECONDS * sample_rate);
	if (bytes_used < *nbytes) {
		return 0;
	}

	*nbytes = SAMPLES_TO_BYTES(transition_period * sample_rate);
	transition_sample_step = sample_rate / TRANSITION_STEPS_PER_SECOND;
	sample_step_bytes = SAMPLES_TO_BYTES(transition_sample_step);

	interval = s32_to_fixed(transition_period);
	interval_step = fixed_div(FIXED_ONE, TRANSITION_STEPS_PER_SECOND);

	while (bytes_used < (*nbytes + sample_step_bytes)) {
		*nbytes -= sample_step_bytes;
		interval -= interval_step;
	}

	return interval;
}

#endif // AUDIO_DECODE_PRIV
