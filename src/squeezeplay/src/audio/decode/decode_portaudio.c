/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"

#include "audio/fifo.h"
#include "audio/fixed_math.h"
#include "audio/mqueue.h"
#include "audio/decode/decode.h"
#include "audio/decode/decode_priv.h"

#ifdef HAVE_LIBPORTAUDIO

#include "portaudio.h"

#if defined(__APPLE__) && defined(__MACH__)
#include "pa_mac_core.h"
#include <CoreAudio/CoreAudio.h>
static PaMacCoreStreamInfo macInfo;
static unsigned long streamInfoFlags;
static OSStatus defaultDeviceChangedListener(AudioObjectID inObjectID, UInt32 inNumberAddresses, const AudioObjectPropertyAddress inAddresses[], void *inClientData);
#endif

#ifdef _WIN32
#include "pa_win_wasapi.h"
static PaWasapiStreamInfo wasapiInfo;

#define strncasecmp	strnicmp
#endif

#define PA_DEFAULT_DEVICE       (-1)

#ifdef PA18API
typedef int PaDeviceIndex;
typedef double PaTime;

typedef struct PaStreamParameters
{
	PaDeviceIndex device;
	int channelCount;
	PaSampleFormat sampleFormat;
	PaTime suggestedLatency;

} PaStreamParameters;

static int paContinue=0; /* Signal that the stream should continue invoking the callback and processing audio. */
static int paComplete=1; /* Signal that the stream should stop invoking the callback and finish once all output */
			 /* samples have played. */

static unsigned long paFramesPerBuffer = 4096L;
static unsigned long paNumberOfBuffers = 4L;

#endif /* PA18API */

/* Portaudio stream */
static PaStream *stream;
static PaStreamParameters outputParam;

/* Stream sample rate */
static u32_t stream_sample_rate;

static void decode_portaudio_openstream(void);

static void finished_handler(void) {
	mqueue_read_complete(&decode_mqueue);

	decode_audio_lock();
	decode_portaudio_openstream();
	decode_audio_unlock();
}

/*
 * This function is called when the stream needs to be reopened at a
 * different sample rate.
 */
static void finished(void *userData) {
	if (decode_audio->set_sample_rate) {
		/* We can't change the sample rate in this thread, so queue a request for
		* the decoder thread to service
		*/
		if (mqueue_write_request(&decode_mqueue, finished_handler, 0)) {
			mqueue_write_complete(&decode_mqueue);
		}
		else {
			LOG_DEBUG(log_audio_output, "Full message queue, dropped finished message");
		}
	}
}

/*
 * This function is called by portaudio when the stream is active to request
 * audio samples
 */
#ifndef PA18API
static int callback(const void *inputBuffer,
		    void *outputBuffer,
		    unsigned long framesPerBuffer,
		    const PaStreamCallbackTimeInfo *timeInfo,
		    PaStreamCallbackFlags statusFlags,
		    void *userData) {
#else
static int callback(void *inputBuffer,
                    void *outputBuffer,
                    unsigned long framesPerBuffer,
                    PaTimestamp outTime,
                    void *userData) {
#endif /* PA18API */
	size_t bytes_used, len, skip_bytes = 0, add_bytes = 0;
	int add_silence_ms;
	bool_t reached_start_point;
	Uint8 *outputArray = (u8_t *)outputBuffer;
	u32_t delay;
	int ret = paContinue;

#ifndef PA18API
	if (statusFlags & (paOutputUnderflow | paOutputOverflow)) {
		LOG_DEBUG(log_audio_output, "pa status %x", (unsigned int)statusFlags);
	}
#endif /* PA18API */

	// XXXX full port from ip3k

	len = SAMPLES_TO_BYTES(framesPerBuffer);

	decode_audio_lock();

	bytes_used = fifo_bytes_used(&decode_audio->fifo);

	/* Should we start the audio now based on having enough decoded data? */
	/* We may need to override the output_threshold if we are playing a high
	   sample rate stream, to prevent stalls. Refer note against 'DECODE_FIFO_SIZE'
	   in 'decode_priv.h'.
	   We adopt a 1 sec override for streams >96k (176/192k and 352/384k in practice).
	   This is identical to the approach already adopted by 'decode_alsa_backend.c'.
	*/

	if (decode_audio->state & DECODE_STATE_AUTOSTART
			&& bytes_used >=  len
			&& bytes_used >= (
			    stream_sample_rate <= 96000 ?
				SAMPLES_TO_BYTES((u32_t)((decode_audio->output_threshold * stream_sample_rate) / 10)) :
				SAMPLES_TO_BYTES((u32_t) stream_sample_rate)
			   )
		)
	{
		u32_t now = jive_jiffies();

		if (decode_audio->start_at_jiffies > now && now > decode_audio->start_at_jiffies - 5000)
			/* This does not consider any delay in the port-audio output chain */
			decode_audio->add_silence_ms = decode_audio->start_at_jiffies - now;

		decode_audio->state &= ~DECODE_STATE_AUTOSTART;
		decode_audio->state |= DECODE_STATE_RUNNING;
	}

	/* audio running? */
	if (!(decode_audio->state & DECODE_STATE_RUNNING)) {
		memset(outputArray, 0, len);

		/* mix in sound effects */
		goto mixin_effects;
	}

	/* sync accurate playpoint */
	decode_audio->sync_elapsed_samples = decode_audio->elapsed_samples;
#ifndef PA18API
	if (timeInfo->outputBufferDacTime > timeInfo->currentTime)
	{
		// workaround for wdm-ks which can return outputBufferDacTime with a different epoch
		delay = (u32_t)((timeInfo->outputBufferDacTime - timeInfo->currentTime) * decode_audio->track_sample_rate);
	}
	else
	{
		delay = 0;
	}
#else
	delay = 0;
#endif /* PA18API */

	if (decode_audio->sync_elapsed_samples > delay) {
		decode_audio->sync_elapsed_samples -= delay;
	}
	decode_audio->sync_elapsed_timestamp = jive_jiffies();

	add_silence_ms = decode_audio->add_silence_ms;
	if (add_silence_ms) {
		add_bytes = SAMPLES_TO_BYTES((u32_t)((add_silence_ms * stream_sample_rate) / 1000));
		if (add_bytes > len) add_bytes = len;
		memset(outputArray, 0, add_bytes);
		outputArray += add_bytes;
		len -= add_bytes;
		add_silence_ms -= (BYTES_TO_SAMPLES(add_bytes) * 1000) / stream_sample_rate;
		if (add_silence_ms < 2)
			add_silence_ms = 0;

		decode_audio->add_silence_ms = add_silence_ms;

		if (!len) {
			goto mixin_effects;
		}
	}

	/* only skip if it will not cause an underrun */
	if (bytes_used >= len && decode_audio->skip_ahead_bytes > 0) {
		skip_bytes = bytes_used - len;
		if (skip_bytes > decode_audio->skip_ahead_bytes) {
			skip_bytes = decode_audio->skip_ahead_bytes;			
		}
	}

	if (bytes_used > len) {
		bytes_used = len;
	}

	/* audio underrun? */
	if (bytes_used == 0) {
		decode_audio->state |= DECODE_STATE_UNDERRUN;
		memset(outputArray, 0, len);

		goto mixin_effects;
	}

	if (bytes_used < len) {
		decode_audio->state |= DECODE_STATE_UNDERRUN;
		memset(outputArray + bytes_used, 0, len - bytes_used);
	}
	else {
		decode_audio->state &= ~DECODE_STATE_UNDERRUN;
	}

	if (skip_bytes) {
		size_t wrap;

		LOG_DEBUG(log_audio_output, "Skipping %d bytes", (int) skip_bytes);
		
		wrap = fifo_bytes_until_rptr_wrap(&decode_audio->fifo);

		if (wrap < skip_bytes) {
			fifo_rptr_incby(&decode_audio->fifo, wrap);
			skip_bytes -= wrap;
			decode_audio->skip_ahead_bytes -= wrap;
			decode_audio->elapsed_samples += BYTES_TO_SAMPLES(wrap);
		}

		fifo_rptr_incby(&decode_audio->fifo, skip_bytes);
		decode_audio->skip_ahead_bytes -= skip_bytes;
		decode_audio->elapsed_samples += BYTES_TO_SAMPLES(skip_bytes);
	}

	while (bytes_used) {
		size_t wrap, bytes_write, samples_write;
		sample_t *output_ptr, *decode_ptr;
		s32_t lgain, rgain;
		
		lgain = decode_audio->lgain;
		rgain = decode_audio->rgain;

		wrap = fifo_bytes_until_rptr_wrap(&decode_audio->fifo);

		bytes_write = bytes_used;
		if (wrap < bytes_write) {
			bytes_write = wrap;
		}

		samples_write = BYTES_TO_SAMPLES(bytes_write);
		
		/* Handle fading and delayed fading */
		if (decode_audio->samples_to_fade) {
			if (decode_audio->samples_until_fade > samples_write) {
				decode_audio->samples_until_fade -= samples_write;
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
				
					LOG_DEBUG(log_audio_output, "Starting FADEOUT over %d seconds, transition_gain_step %d, transition_sample_step %d",
						fixed_to_s32(interval), decode_audio->transition_gain_step, decode_audio->transition_sample_step);	
				}
				
				/* Apply transition gain to left/right gain values */
				lgain = fixed_mul(lgain, decode_audio->transition_gain);
				rgain = fixed_mul(rgain, decode_audio->transition_gain);
				
				/* Reduce transition gain when we've processed enough samples */
				decode_audio->transition_samples_in_step += samples_write;
				while (decode_audio->transition_gain && decode_audio->transition_samples_in_step >= decode_audio->transition_sample_step) {
					decode_audio->transition_samples_in_step -= decode_audio->transition_sample_step;
					decode_audio->transition_gain -= decode_audio->transition_gain_step;
				}
			}
		}

		output_ptr = (sample_t *)outputArray;
		decode_ptr = (sample_t *)(decode_fifo_buf + decode_audio->fifo.rptr);
		while (samples_write--) {
			*(output_ptr++) = fixed_mul(lgain, *(decode_ptr++));
			*(output_ptr++) = fixed_mul(rgain, *(decode_ptr++));
		}

		fifo_rptr_incby(&decode_audio->fifo, bytes_write);
		decode_audio->elapsed_samples += BYTES_TO_SAMPLES(bytes_write);

		outputArray += bytes_write;
		bytes_used -= bytes_write;
	}

	reached_start_point = decode_check_start_point();
	if (reached_start_point) {
		decode_audio->samples_to_fade = 0;
		decode_audio->transition_gain_step = 0;
		
		if (decode_audio->track_sample_rate != stream_sample_rate) {
			LOG_DEBUG(log_audio_output, "Sample rate changed from %d to %d",
				stream_sample_rate, decode_audio->track_sample_rate);
			decode_audio->set_sample_rate = decode_audio->track_sample_rate;
			ret = paComplete; // will trigger the finished callback to change the samplerate
#ifdef PA18API
			finished (userData);
#endif /* PA18API */
		}
	}

 mixin_effects:
	/* mix in sound effects */
	decode_mix_effects(outputBuffer, framesPerBuffer, 24, stream_sample_rate);

	decode_audio_unlock();

	return ret;
}

static void decode_portaudio_start(void) {
	LOG_DEBUG(log_audio_output, "decode_portaudio_start");

	ASSERT_AUDIO_LOCKED();

	decode_audio->set_sample_rate = decode_audio->track_sample_rate;

	decode_portaudio_openstream();
}

static void decode_portaudio_pause(void) {
	ASSERT_AUDIO_LOCKED();
}

static void decode_portaudio_resume(void) {
	ASSERT_AUDIO_LOCKED();
}

static void decode_portaudio_stop(void) {
	LOG_DEBUG(log_audio_output, "decode_portaudio_stop");

	ASSERT_AUDIO_LOCKED();

	decode_audio->samples_to_fade = 0;
	decode_audio->transition_gain_step = 0;

	decode_portaudio_openstream();
}


static void decode_portaudio_openstream(void) {
	PaError err;
	u32_t set_sample_rate;

	ASSERT_AUDIO_LOCKED();

	set_sample_rate = decode_audio->set_sample_rate;
	decode_audio->set_sample_rate = 0;

	if (!set_sample_rate || set_sample_rate == stream_sample_rate) {
		/* no change */
		return;
	}

	if (stream) {
		if ((err = Pa_StopStream(stream)) != paNoError) {
			LOG_WARN(log_audio_output, "Pa_StopStream error %s", Pa_GetErrorText(err));
		}

		if ((err = Pa_CloseStream(stream)) != paNoError) {
			LOG_WARN(log_audio_output, "Pa_CloseStream error %s", Pa_GetErrorText(err));
		}
		else {
			LOG_DEBUG(log_audio_output, "Stream closed");
		}
	}

	LOG_DEBUG(log_audio_output, "Using sample rate %lu", set_sample_rate);

#ifndef PA18API
        LOG_DEBUG(log_audio_output, "Using latency %f", outputParam.suggestedLatency);

	err = Pa_OpenStream(
			&stream,
			NULL,
			&outputParam,
			set_sample_rate,
			paFramesPerBufferUnspecified,
			paPrimeOutputBuffersUsingStreamCallback | paDitherOff,
			callback,
			NULL);
#else
        err = Pa_OpenStream(
                        &stream,
                        paNoDevice,
                        0,
                        0,
                        NULL,
                        outputParam.device,
                        outputParam.channelCount,
                        outputParam.sampleFormat,
                        NULL,
                        set_sample_rate,
                        paFramesPerBuffer,
                        paNumberOfBuffers,
                        paDitherOff,
                        callback,
                        NULL);
#endif /* PA18API */

	if ( err != paNoError )
	{
		LOG_WARN(log_audio_output, "Pa_OpenStream error %s", Pa_GetErrorText(err));

		stream = NULL;
	}
#ifndef PA18API
	else
	{
		LOG_DEBUG(log_audio_output, "Stream latency %f", Pa_GetStreamInfo(stream)->outputLatency);
		LOG_DEBUG(log_audio_output, "Stream samplerate %f", Pa_GetStreamInfo(stream)->sampleRate);
	}
#endif /* PA18API */

	stream_sample_rate = set_sample_rate;

#ifndef PA18API
	/* playout to the end of this stream before changing the sample rate */
	if ((err = Pa_SetStreamFinishedCallback(stream, finished)) != paNoError) {
		LOG_WARN(log_audio_output, "Pa_SetStreamFinishedCallback error %s", Pa_GetErrorText(err));
	}
#endif /* PA18API */

	if ((err = Pa_StartStream(stream)) != paNoError) {
		LOG_WARN(log_audio_output, "Pa_StartStream error %s", Pa_GetErrorText(err));
	}
}

PaDeviceIndex get_padevice_id(void)
{
	int i;
	const PaDeviceInfo *pdi;
#ifndef PA18API
	const PaHostApiInfo *info;
#endif
	PaDeviceIndex DefaultDevice;
	PaDeviceIndex DeviceCount;
	
	char *default_hostapi;
	char *default_device_name;
	char *default_device_id;

	default_device_id = getenv("USEPADEVICEID");
	default_device_name = getenv("USEPADEVICE");
	default_hostapi = getenv("USEPAHOSTAPI");

#ifndef PA18API
	DeviceCount = Pa_GetDeviceCount();
#else
	DeviceCount = Pa_CountDevices();
#endif

	if ( DeviceCount < 0 )
	{
		LOG_WARN(log_audio_output, "No soundcards detected. %s", Pa_GetErrorText(DeviceCount) );
		DefaultDevice = paNoDevice;
	}
	else
	{
		/* If name not set, use device index */
		if ( default_device_name == NULL )
			if ( default_device_id != NULL )
				DefaultDevice = (PaDeviceIndex) strtoul ( default_device_id, NULL, 0 );
			else	
				DefaultDevice = PA_DEFAULT_DEVICE;
		else
		{
			/* Set the initial device to the default.
			 * If we find a match the device index will be applied.
			 */
			DefaultDevice = PA_DEFAULT_DEVICE;

		        for ( i = 0; i < DeviceCount; i++ )
		        {
		                pdi = Pa_GetDeviceInfo( i );
		                if ( pdi->name != NULL )
				{
#ifndef PA18API
					/* Match on audio system if specified */
					if ( default_hostapi != NULL )
					{
						info = Pa_GetHostApiInfo ( pdi->hostApi );
						if ( info->name != NULL )
						{
							/* No match, next */
							if ( strncasecmp (info->name, default_hostapi, strlen (info->name)) != 0 )
								continue;
						}
					}
#endif
					/* Need at least stereo output */
					if ( pdi->maxOutputChannels < 2 )
						continue;

					if ( strncasecmp (pdi->name, default_device_name, strlen (pdi->name)) == 0 )
					{
						DefaultDevice = i;
						break;
					}
				}
	                }
		}
	}

	if ( (DefaultDevice >= DeviceCount) || (DefaultDevice == PA_DEFAULT_DEVICE) )
	{
#ifndef PA18API
		DefaultDevice = Pa_GetDefaultOutputDevice();
#else
		DefaultDevice = Pa_GetDefaultOutputDeviceID();
#endif
	}

	if ( DefaultDevice == paNoDevice )
		LOG_WARN(log_audio_output, "No output devices found. %s", Pa_GetErrorText(DefaultDevice) );
	else
	{
		pdi = Pa_GetDeviceInfo(DefaultDevice);
#ifndef PA18API
		info = Pa_GetHostApiInfo(pdi->hostApi);
		LOG_INFO(log_audio_output, "Using device %d. %s (%s)", DefaultDevice, pdi->name, info->name);
#else
		LOG_INFO(log_audio_output, "Using device %d. %s", DefaultDevice, pdi->name);
#endif
	}

	return (DefaultDevice) ;
}

#ifndef PA18API
PaHostApiTypeId get_padevice_apitype ( PaDeviceIndex device )
{
	PaHostApiTypeId apitype;
	const PaDeviceInfo *pdi;
	const PaHostApiInfo *info;

	apitype = paInDevelopment;

	pdi = Pa_GetDeviceInfo( device );
	if ( pdi->name != NULL )
	{
		info = Pa_GetHostApiInfo ( pdi->hostApi );
		if ( info != NULL )
			apitype = info->type;
	}

	return (apitype);	
}
#endif

u32_t get_padevice_maxrate (void)
{
	int i;

	PaError err;
	const char *pamaxrate;
	u32_t use_pamaxrate;
	u32_t rates[] = { 384000, 352800, 192000, 176400, 96000, 88200, 48000, 44100, 32000, 24000, 22500, 16000, 12000, 11025, 8000, 0 };

	use_pamaxrate = 48000;

	pamaxrate = getenv("USEPAMAXSAMPLERATE");

	if ( pamaxrate != NULL )
	{
		use_pamaxrate = (u32_t) strtoul(pamaxrate, NULL, 0);
		if ( ( use_pamaxrate < 8000L ) || ( use_pamaxrate > rates[0] ) )
			use_pamaxrate = 48000;
	}
	else
	{
		/* check supported sample rates by opening the device */
		for (i = 0; rates[i]; ++i) {
#ifndef PA18API
			err = Pa_OpenStream(&stream, NULL, &outputParam, (double)rates[i],
				paFramesPerBufferUnspecified, paNoFlag, callback, NULL);
#else
			err = Pa_OpenStream(&stream, paNoDevice, 0, 0, NULL, outputParam.device,
				outputParam.channelCount, outputParam.sampleFormat, NULL, (double)rates[i],
				paFramesPerBuffer, paNumberOfBuffers, paNoFlag, callback, NULL);
#endif
			if (err == paNoError) {
				Pa_CloseStream(stream);
				use_pamaxrate = rates[i];
				break;
			}
		}

		if (!rates[i]) {
			use_pamaxrate = 48000;
		}
	}
	stream = NULL;

	LOG_INFO(log_audio_output, "Setting maximum samplerate to %lu", use_pamaxrate );

	return use_pamaxrate;
}

static int decode_portaudio_init(lua_State *L) {
	PaError err;
	void *buf;
	static int first_time = 1;
#ifndef PA18API
	const char *palatency;
	unsigned int userlatency;
#else
	const char *pabuffersize;
	const char *panumbufs;
#endif /* PA18API */

	if (!first_time) {
		/* in the absence of portaudio HotPlug support, re-initialize to get new devices */
		if ((err = Pa_CloseStream(stream)) != paNoError) {
			LOG_WARN(log_audio_output, "Pa_CloseStream() failed: %s", Pa_GetErrorText(err));
		}
		if ((err = Pa_Terminate()) != paNoError) {
			LOG_WARN(log_audio_output, "Pa_Terminate() failed: %s", Pa_GetErrorText(err));
		}
	}
	if ((err = Pa_Initialize()) != paNoError) {
		LOG_WARN(log_audio_output, "Pa_Initialize() failed: %s", Pa_GetErrorText(err));
		goto err0;
	}

#ifndef PA18API
	LOG_DEBUG(log_audio_output, "Portaudio version v19.%d", Pa_GetVersion());
#else
	LOG_DEBUG(log_audio_output, "Portaudio version v18.1");
#endif /* PA18API */

	memset(&outputParam, 0, sizeof(outputParam));

	outputParam.device = get_padevice_id();
	if ( outputParam.device == paNoDevice )
		goto err0;

	outputParam.channelCount = 2;
	outputParam.sampleFormat = paInt32;

#ifndef PA18API
	outputParam.hostApiSpecificStreamInfo = NULL;

	/* high latency for robust playback */
	outputParam.suggestedLatency = Pa_GetDeviceInfo(outputParam.device)->defaultHighOutputLatency;

	/* override default latency? */
	palatency = getenv("USEPALATENCY");

	if ( palatency != NULL )
	{
		userlatency = strtoul(palatency, NULL, 0);

		if ( (userlatency > 0) && (userlatency < 1000) )
			outputParam.suggestedLatency = (float) userlatency / 1000.0;
	}

	LOG_INFO(log_audio_output, "Using latency %f", outputParam.suggestedLatency);

#if defined(__APPLE__) && defined(__MACH__)
	/* Enable CoreAudio Pro mode to avoid resampling if possible, unless USEPAPLAYNICE defined */
	if ( getenv("USEPAPLAYNICE") )
	{
		streamInfoFlags = paMacCorePlayNice;
		LOG_INFO(log_audio_output, "CoreAudio PlayNice enabled" );
	}
	else
	{
		streamInfoFlags = paMacCorePro;
		LOG_INFO(log_audio_output, "CoreAudio Pro Mode enabled" );
	}

	PaMacCore_SetupStreamInfo(&macInfo, streamInfoFlags);
	outputParam.hostApiSpecificStreamInfo = &macInfo;

#endif /* APPLE */
#ifdef _WIN32
	/* Use exclusive mode for WASAPI device, default is shared which doesn't support sample rate changes */
	if ( get_padevice_apitype(outputParam.device) == paWASAPI )
	{
		wasapiInfo.size = sizeof(PaWasapiStreamInfo);
		wasapiInfo.hostApiType = paWASAPI;
		wasapiInfo.version = 1;
		wasapiInfo.flags = paWinWasapiExclusive;
		outputParam.hostApiSpecificStreamInfo = &wasapiInfo;

		LOG_INFO(log_audio_output, "WASAPI Exclusive Mode enabled" );
	}
#endif /* _WIN32 */
#else
	pabuffersize = getenv("USEPAFRAMESPERBUFFER");

	if ( pabuffersize != NULL )
	{
		paFramesPerBuffer = strtoul(pabuffersize, NULL, 0);
		if ( ( paFramesPerBuffer < 1024L ) || ( paFramesPerBuffer > 262144L ) )
			paFramesPerBuffer = 1024L;
	}

	panumbufs = getenv("USEPANUMBEROFBUFFERS");

	if ( panumbufs != NULL )
	{
		paNumberOfBuffers = strtoul(panumbufs, NULL, 0);
		if ( ( paNumberOfBuffers < 2L ) || ( paNumberOfBuffers > 32L ) )
			paNumberOfBuffers = 2L;
	}

	LOG_INFO(log_audio_output, "Using %lu buffers of %lu frames per buffer",
		paNumberOfBuffers, paFramesPerBuffer);

#endif /* PA18API */

	if (first_time) {
		/* allocate output memory */
		buf = malloc(DECODE_AUDIO_BUFFER_SIZE);
		if (!buf) {
			goto err0;
		}
		decode_init_buffers(buf, false);
	} else {
		stream_sample_rate = 0; /* reset so that stream will be reopened */
	}
	decode_audio->max_rate = get_padevice_maxrate();
	decode_audio->set_sample_rate = 44100;

#if defined(__APPLE__) && defined(__MACH__)
	if (first_time) {
		/* listen for changes to default audio output device */
		AudioObjectAddPropertyListener(kAudioObjectSystemObject,
					       &(AudioObjectPropertyAddress) {
						       kAudioHardwarePropertyDefaultOutputDevice,
						       kAudioObjectPropertyScopeGlobal,
						       kAudioObjectPropertyElementMaster },
					       defaultDeviceChangedListener,
					       NULL);
	}
#endif
	first_time = 0;

	/* open stream */
	decode_audio_lock();
	decode_portaudio_openstream();
	decode_audio_unlock();

	return 1;

 err0:
	LOG_WARN(log_audio_output,"No audio device found-playback disabled");
	return 0;
}


struct decode_audio_func decode_portaudio = {
	decode_portaudio_init,
	decode_portaudio_start,
	decode_portaudio_pause,
	decode_portaudio_resume,
	decode_portaudio_stop,
};

#if defined(__APPLE__) && defined(__MACH__)
OSStatus defaultDeviceChangedListener(AudioObjectID inObjectID, UInt32 inNumberAddresses, const AudioObjectPropertyAddress inAddresses[], void *inClientData) {
	(void)(inObjectID); // unused
	(void)(inNumberAddresses);
	(void)(inAddresses);
	(void)(inClientData);

	(void) decode_portaudio_init(NULL);
	return 0;
}
#endif // APPLE
#endif // HAVE_PORTAUDIO
