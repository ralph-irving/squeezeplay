/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"

#include "audio/fifo.h"
#include "audio/fixed_math.h"
#include "audio/mqueue.h"
#include "audio/streambuf.h"
#include "audio/decode/decode.h"
#include "audio/decode/decode_priv.h"


#ifdef HAVE_LIBASOUND

#include <pthread.h>
#include <alsa/asoundlib.h>
#include <sys/wait.h>


#define ALSA_DEFAULT_DEVICE "default"
#define ALSA_DEFAULT_BUFFER_TIME 30000
#define ALSA_DEFAULT_PERIOD_COUNT 3
#define ALSA_PCM_WAIT_TIMEOUT 500

#define FLAG_STREAM_PLAYBACK 0x01
#define FLAG_STREAM_EFFECTS  0x02
#define FLAG_STREAM_NOISE    0x04
#define FLAG_STREAM_LOOPBACK 0x08
#define FLAG_NOMMAP          0x10


pid_t effect_pid = -1;
pid_t playback_pid = -1;


static void decode_alsa_check_pids(void) {
	if (effect_pid >= 0) {
		if (waitpid(effect_pid, NULL, WNOHANG) == effect_pid) {
			/* child is dead, exit */
			LOG_ERROR(log_audio_output, "exit, effect child is dead(%d)",effect_pid);
			exit(-1);
		}
	}
	if (playback_pid >= 0) {
		if (waitpid(playback_pid, NULL, WNOHANG) == playback_pid) {
			/* child is dead, exit */
			LOG_ERROR(log_audio_output, "exit, playback child is dead(%d)",playback_pid);
			exit(-1);
		}
	}
}


static void decode_alsa_start(void) {
	LOG_DEBUG(log_audio_output, "decode_alsa_start");

	ASSERT_AUDIO_LOCKED();

	decode_audio->set_sample_rate = decode_audio->track_sample_rate;

	decode_alsa_check_pids();
}


static void decode_alsa_resume(void) {
	LOG_DEBUG(log_audio_output, "decode_alsa_resume");

	ASSERT_AUDIO_LOCKED();

	decode_alsa_check_pids();
}


static void decode_alsa_pause(void) {
	LOG_DEBUG(log_audio_output, "decode_alsa_pause");

	ASSERT_AUDIO_LOCKED();

	decode_alsa_check_pids();
}


static void decode_alsa_stop(void) {
	LOG_DEBUG(log_audio_output, "decode_alsa_stop");

	ASSERT_AUDIO_LOCKED();

	decode_alsa_check_pids();
}


static pid_t decode_alsa_fork(const char *device, const char *capture, unsigned int buffer_time, unsigned int period_count, unsigned int pcm_timeout, const char *sample_size, u32_t flags)
{
	char *path, b[10], p[10], f[10], t[10];
	char *cmd[20];
	pid_t pid;
	int i, idx = 0, ret;

	path = alloca(PATH_MAX);

	/* jive_alsa [-v] -d <device> -b <buffer_time> -p <period_count> -t <pcm_timeout> -s "<0|16|24|24_3|32>" -f <flags> */

	cmd[idx++] = "jive_alsa";

	if (IS_LOG_PRIORITY(log_audio_output, LOG_PRIORITY_DEBUG)) {
		cmd[idx++] = "-v";
	}

	cmd[idx++] = "-d";
	cmd[idx++] = (char *)device;

	if (capture) {
		cmd[idx++] = "-c";
		cmd[idx++] = (char *)capture;
	}

	snprintf(b, sizeof(b), "%d", buffer_time);
	cmd[idx++] = "-b";
	cmd[idx++] = b;

	snprintf(p, sizeof(p), "%d", period_count);
	cmd[idx++] = "-p";
	cmd[idx++] = p;

	snprintf(t, sizeof(t), "%d", pcm_timeout);
	cmd[idx++] = "-t";
	cmd[idx++] = t;

	cmd[idx++] = "-s";
	cmd[idx++] = (char *)sample_size;

	snprintf(f, sizeof(f), "%d", flags);

	cmd[idx++] = "-f";
	cmd[idx++] = f;

	cmd[idx] = '\0';

	if (IS_LOG_PRIORITY(log_audio_output, LOG_PRIORITY_DEBUG)) {
		path[0] = '\0';
		for (i=0; i<idx; i++) {
			strncat(path, cmd[i], PATH_MAX);
			strncat(path, " ", PATH_MAX);
		}
		LOG_DEBUG(log_audio_output, "fork %s", path);
	}

	/* command path */
	getcwd(path, PATH_MAX);
	strncat(path, "/jive_alsa", PATH_MAX);

	decode_audio_lock();
	decode_audio->running = false;

	/* fork + exec */
	pid = vfork();
	if (pid < 0) {
		LOG_ERROR(log_audio_output, "fork failed %d", errno);
		return -1;
	}
	if (pid == 0) {
		/* child */
		ret = execv(path, cmd);

		LOG_ERROR(log_audio_output, "execv failed %d", errno);
		_exit(-1);
	}

	/* wait for backend process to start */
	while (1) {
		fifo_wait_timeout(&decode_audio->fifo, 1500);

		if (decode_audio->running) {
			break;
		}

		if (waitpid(pid, NULL, WNOHANG) == pid) {
			decode_audio_unlock();

			LOG_ERROR(log_audio_output, "%s failed to start", cmd[0]);
			return -1;
		}

	}
	decode_audio_unlock();

	return pid;
}


static int decode_alsa_init(lua_State *L) {
	const char *playback_device;
	const char *capture_device;
	const char *effects_device;
	const char *alsadevname;
	const char *alsacapname;
	const char *alsaeffname;
	const char *alsasamplesize;
	const char *alsapcmtimeout;
	const char *alsabuffertime;
	const char *alsaperiodcount;
	const char *alsausenommap;
	unsigned int buffer_time;
	unsigned int period_count;
	unsigned int pcm_timeout;
	const char *sample_size;
	unsigned int flags;
	int shmid;
	void *buf;

	/* allocate memory */

	// XXXX use shared memory
	shmid = shmget(56833, 0, 0600 | IPC_CREAT);
	if (shmid != -1) {
		shmctl(shmid, IPC_RMID, NULL);
	}

	shmid = shmget(56833, DECODE_AUDIO_BUFFER_SIZE, 0600 | IPC_CREAT);
	if (shmid == -1) {
		// XXXX errors
		LOG_ERROR(log_audio_codec, "shmget error %s", strerror(errno));
		return 0;
	}

	buf = shmat(shmid, 0, 0);
	if (buf == (void *)-1) {
		// XXXX errors
		LOG_ERROR(log_audio_codec, "shmgat error %s", strerror(errno));
		return 0;
	}

	decode_init_buffers(buf, true);

	alsadevname = getenv("USEALSADEVICE");
	alsacapname = getenv("USEALSACAPTURE");
	alsaeffname = getenv("USEALSAEFFECTS");
	alsasamplesize = getenv("USEALSASAMPLESIZE");
	alsapcmtimeout = getenv("USEALSAPCMTIMEOUT");
	alsabuffertime = getenv("USEALSABUFFERTIME");
	alsaperiodcount = getenv("USEALSAPERIODCOUNT");
	alsausenommap = getenv("USEALSANOMMAP");

	/* start threads */
	lua_getfield(L, 2, "alsaPlaybackDevice");
	playback_device = luaL_optstring(L, -1, ALSA_DEFAULT_DEVICE);

	if ( alsadevname != NULL )
		playback_device = alsadevname ;

	lua_getfield(L, 2, "alsaCaptureDevice");
	capture_device = luaL_optstring(L, -1, ALSA_DEFAULT_DEVICE);

	if ( alsacapname != NULL )
		capture_device = alsacapname ;
	else
		if ( alsadevname != NULL )
			 capture_device = alsadevname;

	lua_getfield(L, 2, "alsaEffectsDevice");
	effects_device = luaL_optstring(L, -1, NULL);

	if ( alsaeffname != NULL )
		effects_device = alsaeffname;

	lua_getfield(L, 2, "alsaPcmTimeout");
	pcm_timeout = luaL_optinteger(L, -1, ALSA_PCM_WAIT_TIMEOUT);

	if ( alsapcmtimeout != NULL )
	{
		pcm_timeout = (unsigned int) strtoul (alsapcmtimeout, NULL, 0);
		if ( (pcm_timeout < 10) || ( pcm_timeout > ( ALSA_PCM_WAIT_TIMEOUT * 3 ) ) )
			pcm_timeout = ALSA_PCM_WAIT_TIMEOUT;
	}	

	lua_getfield(L, 2, "alsaSampleSize");
	sample_size = luaL_optstring(L, -1, "16");

	if ( alsasamplesize != NULL )
	{
		if ( ( strcmp ( alsasamplesize, "0" ) == 0 ) ||
			( strcmp ( alsasamplesize, "16" ) == 0 ) ||
			( strcmp ( alsasamplesize, "24" ) == 0 ) ||
			( strcmp ( alsasamplesize, "24_3" ) == 0 ) ||
			( strcmp ( alsasamplesize, "32" ) == 0 ) )
		{
			sample_size = alsasamplesize;
		}
	}

	lua_getfield(L, 2, "alsaFlags");
	flags = luaL_optinteger(L, -1, 0);

	if ( alsausenommap != NULL )
		flags |= FLAG_NOMMAP ;

	/* playback device */
	LOG_DEBUG(log_audio_output, "Playback device: %s", playback_device);

	lua_getfield(L, 2, "alsaPlaybackBufferTime");
	buffer_time = luaL_optinteger(L, -1, ALSA_DEFAULT_BUFFER_TIME);

	if ( alsabuffertime != NULL )
	{
		buffer_time = (unsigned int) strtoul (alsabuffertime, NULL, 0);
		if ( buffer_time < 10 )
			buffer_time = ALSA_DEFAULT_BUFFER_TIME;
	}

	lua_getfield(L, 2, "alsaPlaybackPeriodCount");
	period_count = luaL_optinteger(L, -1, ALSA_DEFAULT_PERIOD_COUNT);

	if ( alsaperiodcount != NULL )
	{
		period_count = (unsigned int) strtoul (alsaperiodcount, NULL, 0);
		if ( period_count < 1 )
			period_count = ALSA_DEFAULT_PERIOD_COUNT;
	}

	lua_pop(L, 2);

	/* Don't start playback jive_alsa if defined */
	if ( getenv("SQUEEZEPLAY_NOPLAYBACK") == NULL )
	{
		playback_pid = decode_alsa_fork(playback_device, capture_device, buffer_time, period_count, pcm_timeout,
			sample_size, (FLAG_STREAM_PLAYBACK|flags));
	}

	/* effects device */
	if (effects_device) {
		LOG_DEBUG(log_audio_output, "Effects device: %s", effects_device);

		if ( alsabuffertime != NULL )
		{
			buffer_time = (unsigned int) strtoul (alsabuffertime, NULL, 0);
			if ( buffer_time < 10 )
				buffer_time = ALSA_DEFAULT_BUFFER_TIME;
		}
		else
		{
			lua_getfield(L, 2, "alsaEffectsBufferTime");
			buffer_time = luaL_optinteger(L, -1, ALSA_DEFAULT_BUFFER_TIME);
		}

		if ( alsaperiodcount != NULL )
		{
			period_count = (unsigned int) strtoul (alsaperiodcount, NULL, 0);
			if ( period_count < 1 )
				period_count = ALSA_DEFAULT_PERIOD_COUNT;
		}
		else
		{
			lua_getfield(L, 2, "alsaEffectsPeriodCount");
			period_count = luaL_optinteger(L, -1, ALSA_DEFAULT_PERIOD_COUNT);
		}

		lua_pop(L, 2);

		/* Don't start effects jive_alsa if defined */
		if ( getenv("SQUEEZEPLAY_NOEFFECTS") == NULL )
		{
			effect_pid = decode_alsa_fork(effects_device, NULL, buffer_time, period_count, pcm_timeout,
				sample_size, (FLAG_STREAM_EFFECTS|flags));
		}
	}

	lua_pop(L, 2);

	return playback_pid > 0 ? 1 : -1;
}


struct decode_audio_func decode_alsa = {
	decode_alsa_init,
	decode_alsa_start,
	decode_alsa_pause,
	decode_alsa_resume,
	decode_alsa_stop,
};

#endif // HAVE_LIBASOUND
