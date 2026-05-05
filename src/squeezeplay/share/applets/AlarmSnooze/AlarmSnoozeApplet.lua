local _assert, pairs = _assert, pairs
local os	       = require("os")	
local io               = require("io")
local table            = require("jive.utils.table")
local string	       = require("jive.utils.string")
local debug	       = require("jive.utils.debug")
local datetime         = require("jive.utils.datetime")

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local System           = require("jive.System")
local Framework        = require("jive.ui.Framework")
local Group            = require("jive.ui.Group")
local Icon             = require("jive.ui.Icon")
local Label            = require("jive.ui.Label")
local StickyMenu       = require("jive.ui.StickyMenu")
local Window           = require("jive.ui.Window")
local Popup            = require("jive.ui.Popup")
local Timer            = require("jive.ui.Timer")

local Player           = require("jive.slim.Player")
local LocalPlayer      = require("jive.slim.LocalPlayer")
local decode           = require("squeezeplay.decode")
                       
local appletManager	= appletManager
local iconbar           = iconbar
local jiveMain          = jiveMain
local jnt               = jnt

module(..., Framework.constants)
oo.class(_M, Applet)

--[[
New alarm code with less server dependency

We do not distiguish between 'server' and 'rtc' alarm anymore, because it's impossible to handle all cases like when a player gets disconnected / reconnected before an alarm, during an alarm or during a snooze phase. I also removed most of the 'notify_*' stuff as it does not help the case.

Instead we only use information from the server about the next alarm time. If a next alarm is set from the server we internally start a timer in parallel (RTCAlarmTimer). When the alarm time is reached the server will start to play the playlist and at the same time the internal timer shows the alarm window and checks periodically whether the audio state is indicating sound is actually playing.

- If the player is connected and the audio state test is ok the user hears the originally selected alarm.
- If the player is disconnected the audio state test will fail and the fallback alarm will be heard.

In both cases the user can stop the alarm or snooze as many times as she likes. After each snooze period the same scenario as with the original alarm happens.

If a particular alarm is still ongoing (either playing or snoozing) a new alarm time set from the server only starts the internal (RTCAlarmTimer) again, but does not affect the ongoing alarm. (i.e. snoozeTimer).

What's been changed so far:
- Unyfied log messages
- Server input via alarm notification is only used to set or clear an alarm time
- Server does not actually start the alarm process on the player (that is done by RTCAlarmTimer)
- Server only starts to play the choosen playlist at the alarm time
- A separate timer is used for snoozing (snoozeTimer) instead of sharing the alarm timer (RTCAlarmTimer)
- Check for good audio has been extended to a total of 60 seconds (was 25 seconds) to allow more time for slow radio stations

** Alarm version 2 adds:
- Retrieve one (the next) full alarm, including repeat and weekdays etc. to act upon it in case there is no server connection

TODO:
- Readd fade in for fallback alarm

]]--


function init(self, ...)
	-- Read stored alarm - for instance after reboot
	self.alarmNext = self:getSettings()['alarmNext']
	self.alarmRepeat = self:getSettings()['alarmRepeat']
	self.alarmDays = self:getSettings()['alarmDays']

	-- Get some data about the player
	self.localPlayer = Player:getLocalPlayer()
	self.server = self.localPlayer and self.localPlayer:getSlimServer()

	jnt:subscribe(self)

	self.alarmTone = "applets/AlarmSnooze/alarm.mp3"
	self.alarmInProgress = nil

	local timeToAlarm
	local startRTCAlarmTimer = false
	-- If there is a stored alarm start the RTC timer
	if self.alarmNext then
		timeToAlarm = self:_inFuture()
		if timeToAlarm then
			startRTCAlarmTimer  = true
		else
			timeToAlarm = 86400000
		end
	else
		-- arbitrarily set timeToAlarm if there isn't one, 
		-- as it will be set again whenever it is invoked by an self.alarmNext param
		timeToAlarm = 86400000
	end

	self.RTCAlarmTimer = Timer(timeToAlarm,
		function ()
			log:warn("*** Alarm: RTC alarm firing")

			if self.alarmInProgress then
				self:_alarmOff(true)
			end

			self.alarmInProgress = 'rtc'

			-- Rearm fallback alarm (if repeating)
			self:rearmRTCAlarm()

			-- This also starts check about audio state
			self:openAlarmWindow()
		end,
		true	-- once
	)

	self.snoozeTimer = Timer(86400000,
		function ()
			log:warn("*** Alarm: Snooze time passed")
			self.alarmInProgress = 'rtc'
			-- Kick server again to play
			self.localPlayer:play(true)
			-- This also starts check about audio state
			self:openAlarmWindow()
		end,
		true	-- once
	)

	self.failedAudioTicker = 0
	self.goodAudioTicker = 0
	self.decodeStatePoller = Timer(5000,
		function ()
			self:_pollDecodeState()
		end,
		false	-- repeat
	)

	self.wakeOnLanTimer = Timer(86400000, -- arbitrary countdown, as timer interval will be set by _startTimer(), not here
		function()
			if self.server then
				log:warn("*** Alarm: WOL packet being sent to ", self.server)
				self.server:wakeOnLan()
			else
				log:warn("*** Alarm: WOL timer has been hit, but no self.server is available to send to")
			end
		end,
		true	-- once
	)

	self.statusPoller = Timer(1000, 
		function ()
			local status = decode:status()
			log:warn("*** Alarm ------------------------")
			log:warn("*** self.alarmInProgress:         ", self.alarmInProgress)
			log:warn("*** status.audioState:            ", status.audioState)
			log:warn("*** self.localPlayer.alarmState:  ", self.localPlayer:getAlarmState())
			log:warn("*** RTC fallback running?:        ", self.RTCAlarmTimer:isRunning())
			log:warn("*** self.server:                  ", self.server)

			if self.fallbackAlarmTimeout and self.fallbackAlarmTimeout:isRunning() then
				log:warn("*** Fallback timeout running?:    ", self.fallbackAlarmTimeout:isRunning())
			end

			if self.server then
				log:warn("*** self.server.mac:              ", self.server.mac)
			end
		end,
		false	-- repeat
	)

	-- this timer is for debug purposes only, to log state information every second for tracking purposes
	-- very useful when needed...
	--self.statusPoller:start()

	if startRTCAlarmTimer then
		self:_startRTCAlarmTimer()
	end
	
	return self
end

-- When an alarm fires, check if it's a repeating alarm and if yes, set the timer
--  according to the next day it should fire
-- This will be overwritten if the player is still connected or gets reconnected
function rearmRTCAlarm(self)
	if self.alarmRepeat and self.alarmRepeat == 1 and self.alarmDays and self.alarmDays != "0000000" then
		log:info("*** Alarm: Set repeating fallback alarm.")

		-- os.date("%w") returns 0-6 for Sun-Sat convert to 1-7 for Sun-Sat
		local weekDay = os.date("%w") + 1

		log:debug("*** Alarm: weekDay (1-7 => Sun-Sat): ", weekDay)
		log:debug("*** Alarm: days: ", self.alarmDays)

		-- Add alarm days at the end of itself to avoid dealing with wrapping
		local alarmDaysList = self.alarmDays .. self.alarmDays

		-- Find next day the alarm should fire
		local start, stop = string.find( alarmDaysList, "1", weekDay + 1)

		if not start then
			return
		end

		local numDays = start - weekDay

		log:debug("*** Alarm: nuber of days the next alarm is away: ", numDays)

		-- Calculate the next alarm time
		self.alarmNext = os.time() + numDays * (24 * 60 * 60)

		log:info("*** Alarm: Storing epochseconds of next alarm: ", self.alarmNext, " now: ", os.time())
	        self:getSettings()['alarmNext'] = self.alarmNext
		self:storeSettings()
		-- This is Baby only
		self:_setWakeupTime()
		-- Restart local timer
		self:_stopRTCAlarmTimer()
		self:_startRTCAlarmTimer()
	end
end


-- This notification is player status info from the server
-- OLD ALARM CODE
-- alarmNext > 0 sets an alarm (max 24 hours later)
-- alarmState == 'none' clears next alarm (but not an ongoing alarm), all other states are ignored as
--  it can hold old information and restart an old alarm if connection is reestablished

-- NEW ALARM CODE - handles repeated alarm that can be later than 24 hours
-- alarmNext2: epoch seconds to the next alarm (if any) or nil
-- alarmRepeat: 0/1/nil
-- alarmDays: string with alarm days starting with Sunday. Sample weekdays: "0111110"
function notify_playerAlarmState(self, player, alarmState, alarmNext, alarmVersion, alarmNext2, alarmRepeat, alarmDays)
	log:debug("*** Alarm: notify_playerAlarmState: player: ", player, " alarmState: ", alarmState)

	if not player then
		return
	end

	if not player:isLocal() then
		return
	end
	
	log:debug("*** Alarm: notify_playerAlarmState: alarmState: ", alarmState, " alarmNext: ", alarmNext)
	log:debug("*** Alarm: notify_playerAlarmState: alarmVersion: ", alarmVersion, " alarmNext2: ", alarmNext2, " alarmRepeat: ", alarmRepeat, " alarmDays: ", alarmDays)

	-- Old alarm code
	if not alarmVersion then
		log:debug("*** OLD ALARM CODE ***")
		-- Clear out alarm
		if alarmState == 'none' then
			self.alarmNext = false
			log:info("*** Alarm: No alarm set, clearing settings")
			self:getSettings()['alarmNext'] = false
			self:storeSettings()
			-- This is baby only
			self:_setWakeupTime('none')
			self:_stopRTCAlarmTimer()
		end
		
		-- store alarmNext data as epoch seconds
		if alarmNext and alarmNext > 0 then
			self.alarmNext = alarmNext

			log:info("*** Alarm: Storing epochseconds of next alarm: ", alarmNext, " now: ", os.time())
		        self:getSettings()['alarmNext'] = alarmNext
			self:storeSettings()
			-- This is Baby only
			self:_setWakeupTime()
			-- Restart local timer
			self:_stopRTCAlarmTimer()
			self:_startRTCAlarmTimer()
		end
	end

	-- New alarm code
	-- need to check alarmState too to prevent overriding values when it is 'active' or 'snooze'
	if alarmVersion and alarmVersion == 2 and (alarmState == 'none' or alarmState == 'set') then
		log:debug("*** NEW ALARM CODE ***")
		-- store alarmNext2 as epoch seconds
		if alarmNext2 and alarmNext2 > 0 then
			if alarmNext2 > os.time() then
				log:info("*** Alarm: Storing epochseconds of next alarm: ", alarmNext2, " now: ", os.time())

				-- use existing variable
				self.alarmNext = alarmNext2
				self.alarmRepeat = alarmRepeat
				self.alarmDays = alarmDays

				self:getSettings()['alarmNext'] = self.alarmNext
				self:getSettings()['alarmRepeat'] = self.alarmRepeat
				self:getSettings()['alarmDays'] = self.alarmDays
				self:storeSettings()

				-- This is Baby only
				self:_setWakeupTime()

				-- Restart local timer
				self:_stopRTCAlarmTimer()
				self:_startRTCAlarmTimer()
			else
				log:warn("*** Alarm: ignoring past alarm: ", alarmNext2, " now: ", os.time())
			end
		-- clear out alarm
		else
			log:info("*** Alarm: No alarm set, clearing settings")

			-- use existing variable
			self.alarmNext = false
			self.alarmRepeat = false
			self.alarmDays = false

			-- use existing variable
			self:getSettings()['alarmNext'] = false
			self:getSettings()['alarmRepeat'] = false
			self:getSettings()['alarmDays'] = false
			self:storeSettings()

			-- This is baby only
			self:_setWakeupTime('none')

			self:_stopRTCAlarmTimer()
		end
	end
end


function notify_playerPower(self, player, power)
	if not player then
		return
	end
        if player ~= self.localPlayer then
                return
        end
        log:debug("*** Alarm: notify_playerPower(): ", power)

        -- turning power off while alarm is in progress always means alarm should be cancelled
        if not power then
		if self.alarmInProgress then
			log:warn("*** Alarm: Power turned off while alarm in progress. By design, turn the alarm off")
			self:_alarmOff(true)
		end
        end
end


function notify_playerCurrent(self, player)
	log:info("*** Alarm: notify_playerCurrent: ", player)
	if not player then
		return
	end
	if player:isLocal() then
		self.localPlayer = player
	end
end


function notify_playerConnected(self, player)
	if not player then
		return
	end
	if player == self.localPlayer then
		-- Update our server
		self.server = player:getSlimServer()
	end
end


function _alarmSnooze(self)
	log:warn("*** Alarm: _alarmSnooze: alarmInProgress: ", self.alarmInProgress, " local player connected: ", self.localPlayer:isConnected())

	local alarmSnoozeSeconds = self.localPlayer:getAlarmSnoozeSeconds()
	local fallbackAlarmMsecs = alarmSnoozeSeconds * 1000 

	log:warn("*** Alarm: _alarmSnooze: fallback alarm snoozing for ", alarmSnoozeSeconds, " seconds")

	self:_stopDecodeStatePoller()
	self:_stopSnoozeTimer()
	self:_startSnoozeTimer(fallbackAlarmMsecs)
	
	log:warn("*** Alarm: _alarmSnooze: stopping fallback alarm audio")
	-- stop playback
	self:_silenceFallbackAlarm()

	if self.alarmWindow then
		self.alarmWindow:playSound("WINDOWHIDE")
		self:_hideAlarmWindow()
	end

	-- Inform server
	if self.localPlayer:isConnected() then
		log:warn("*** Alarm: _alarmSnooze: sending snooze command to connected server for connected local player ", self.localPlayer)
		self.localPlayer:snooze()
	end
end


function _alarmOff(self, stopStream)
	log:warn("*** Alarm: _alarmOff: RTC alarm canceled")
	
	self:_silenceFallbackAlarm()
	self.alarmInProgress = nil
	self:_stopSnoozeTimer()

	if self.alarmWindow then
		self.alarmWindow:playSound("WINDOWHIDE")
		self:_hideAlarmWindow()
	end
	self:_stopDecodeStatePoller()

	-- Inform server
	if self.localPlayer:isConnected() then
		log:warn("*** Alarm: _alarmOff: tell server alarm is off, and only pause if stopStream is true")
		self.localPlayer:stopAlarm(not stopStream)
	end
end


function _alarmDismiss(self)
	log:warn("*** Alarm: _alarmDismiss: dismissing alarm popup, leaving audio playing")

	self:_silenceFallbackAlarm()
	self.alarmInProgress = nil
	self:_stopSnoozeTimer()
	self:_stopDecodeStatePoller()

	if self.alarmWindow then
		self.alarmWindow:playSound("WINDOWHIDE")
		self:_hideAlarmWindow()
	end

	-- Inform server: stop alarm state but leave audio and player state untouched
	if self.localPlayer:isConnected() then
		self.localPlayer:stopAlarm(true)
	end
end


function soundFallbackAlarm(self)
	log:warn("*** Alarm: soundFallbackAlarm()")
	self.alarmVolume = 43 -- forget fade in stuff, just do it - it's an alarm!
	-- cache previous volume setting
	self.previousVolume = self.localPlayer:getVolume()
	self.localPlayer:stop(true)
	-- Bug 16100 - Sound comes from headphones although Radio is set to use speaker
	-- We need to set a valid alarm state for the fallback case
	self.localPlayer:setAlarmState("active_fallback")
	self.localPlayer:playFileInLoop(self.alarmTone)
	self.localPlayer:volumeLocal(self.alarmVolume)
end


function _silenceFallbackAlarm(self)
	if not self.localPlayer then
		log:error("*** Alarm: No self.localPlayer found!")
		return
	end
	self.localPlayer:stop(true)
	if self.previousVolume then
		log:warn("*** Alarm: setting player back to self.previousVolume: ", self.previousVolume)
		self.localPlayer:volumeLocal(self.previousVolume)
	end
	if self.fallbackAlarmTimeout and self.fallbackAlarmTimeout:isRunning() then
		log:warn("*** Alarm: stopping fallback alarm timeout timer")
		self.fallbackAlarmTimeout:stop()
	end
end


function _pollDecodeState(self)
	local status = decode:status()

	log:warn("*** Alarm: _pollDecodeState: alarmInProgress: ", self.alarmInProgress, " audioState: ", status.audioState)

	if self.alarmInProgress and status.audioState ~= 1 then
		self.failedAudioTicker = self.failedAudioTicker + 1
		self.goodAudioTicker = 0
		log:warn("*** Alarm: Audio failed! failedAudioTicker: ", self.failedAudioTicker)
	else
		self.goodAudioTicker = (self.goodAudioTicker or 0) + 1
		-- Only reset the failure counter after sustained audio (3 consecutive good polls = 15 seconds).
		-- A single good poll is not enough: stream plugins may briefly retry after failure,
		-- causing a transient audioState=1 that would otherwise reset the counter and
		-- prevent the fallback alarm from ever firing.
		if self.goodAudioTicker >= 3 then
			self.failedAudioTicker = 0
		end
		log:warn("*** Alarm: Audio ok -> goodAudioTicker: ", self.goodAudioTicker, " failedAudioTicker: ", self.failedAudioTicker)
	end

	if self.failedAudioTicker > 12 then
		log:warn("*** Alarm: Decode state bad! failedAudioTicker: ", self.failedAudioTicker, " Trigger fallback alarm!")

		self.failedAudioTicker = 0
		self.goodAudioTicker = 0
		return self:soundFallbackAlarm()
	end
end


function _startDecodeStatePoller(self)
	if self.decodeStatePoller then
		if self.decodeStatePoller:isRunning() then
			log:warn("*** Alarm: restart decodeStatePoller")
			self.decodeStatePoller:restart()
		else
			log:warn("*** Alarm: start decodeStatePoller")
			self.decodeStatePoller:start()
		end
	end
end


function _stopDecodeStatePoller(self)
	if self.decodeStatePoller and self.decodeStatePoller:isRunning() then
		log:warn("*** Alarm: stopping decodeStatePoller")
		self.decodeStatePoller:stop()
	end
end


function _inFuture(self)
	if not self.alarmNext then
		return false
	end

	local now = os.time()
	if self.alarmNext - now > 0 then
		return self.alarmNext - now
	end
	return false
end


function _startRTCAlarmTimer(self)
	
	if not self.alarmNext then
		log:error("*** Alarm: alarmNext has no value!")
		return
	end

	if self.RTCAlarmTimer:isRunning() then
		self.RTCAlarmTimer:stop()
		log:warn("*** Alarm: _startRTCAlarmTimer: stopping RTC fallback alarm timer")
	end
	
	-- get msecs between now and requested alarm
	local rtcSleepMsecs = self:_deltaMsecs(self.alarmNext)

	log:warn("*** Alarm: _startRTCAlarmTimer: starting RTC fallback alarm timer - rtcSleepMsecs: ", rtcSleepMsecs)
	self.RTCAlarmTimer:setInterval(rtcSleepMsecs)

	-- restart the WOL timer for 5 minutes, or immediately send WOL if alarm is within 5 mins
	self:_restartWakeOnLanTimer(rtcSleepMsecs)

	self.RTCAlarmTimer:start()
	iconbar:setAlarm('ON')
end


function _stopRTCAlarmTimer(self)
	if self.RTCAlarmTimer:isRunning() then
		log:warn("*** Alarm: _stopRTCAlarmTimer: stopping RTC fallback alarm timer")
		self.RTCAlarmTimer:stop()
	end

	if self.wakeOnLanTimer:isRunning() then
		log:warn("*** Alarm: _stopRTCAlarmTimer: stopping WOL timer")
		self.wakeOnLanTimer:stop()
	end

	-- no RTC timer means no alarm, so let's go ahead and remove our alarm icon
	iconbar:setAlarm('OFF')
end


function _startSnoozeTimer(self, interval)
	
	if not interval then
		log:error("*** Alarm: interval has no value!")
		return
	end

	if self.snoozeTimer:isRunning() then
		self.snoozeTimer:stop()
		log:warn("*** Alarm: _startSnoozeTimer: stopping snooze timer")
	end
	
	log:warn("*** Alarm: _startSnoozeTimer: starting snooze timer - interval: ", interval)
	self.snoozeTimer:setInterval(interval)

	self.snoozeTimer:start()
	iconbar:setAlarm('ON')
end


function _stopSnoozeTimer(self)
	if self.snoozeTimer:isRunning() then
		log:warn("*** Alarm: _stopSnoozeTimer: stopping snooze timer")
		self.snoozeTimer:stop()
	end

	-- no RTC timer means no alarm, so let's go ahead and remove our alarm icon
	iconbar:setAlarm('OFF')
end


function _restartWakeOnLanTimer(self, msecsToAlarm)
	local wolLeadTime = 1000 * 60 * 5 -- 5 minutes
	if msecsToAlarm > wolLeadTime then
		log:warn("*** Alarm: _wolTimerRestart - Start WOL timer: ", msecsToAlarm - wolLeadTime)
		self.wakeOnLanTimer:setInterval(msecsToAlarm - wolLeadTime)
		if self.wakeOnLanTimer:isRunning() then
			self.wakeOnLanTimer:restart()
		else
			self.wakeOnLanTimer:start()
		end
	-- if it's within 5 minutes, send a WOL packet as a best effort
	elseif self.server then
		log:warn("*** Alarm: _wolTimerRestart - Send WOL now!")
		self.server:wakeOnLan()
	end	
end


function openAlarmWindow(self)

	-- Bug 16230: if self.localPlayer hasn't been set, try to here as it's essential to the alarm working
	if not self.localPlayer then
		log:warn("*** Alarm: openAlarmWindow: called without self.localPlayer being set. try to acquire it now")
		self.localPlayer = Player:getLocalPlayer()
		-- if that returns nil (very unlikely), throw an error and return
		if not self.localPlayer then
			log:error("*** Alarm: openAlarmWindow: without self.localPlayer the alarm cannot sound")
			return
		end
	end

	log:warn("*** Alarm: openAlarmWindow: local player connected: " , self.localPlayer:isConnected())

	-- if UI is controlling a different player, switch to the local player
	local currentPlayer = Player:getCurrentPlayer()

	if currentPlayer ~= self.localPlayer then
		log:warn("*** Alarm: openAlarmWindow: switching squeezeplay control to local player: ", self.localPlayer, " from current player: ", currentPlayer)
		appletManager:callService("setCurrentPlayer", self.localPlayer)
	end

	appletManager:callService("deactivateScreensaver")
	
	-- this method is called when the alarm time is hit
	-- when the alarm time is hit, unset the wakeup mcu time
	self:_setWakeupTime('none')

	self:_startDecodeStatePoller()

	local alarmTimeoutSeconds = self.localPlayer:getAlarmTimeoutSeconds() or ( 60 * 60 ) -- defaults to 1 hour
	if alarmTimeoutSeconds ~= 0 then
		local alarmTimeoutMsecs = alarmTimeoutSeconds * 1000
		log:info("*** Alarm: Fallback alarm will timeout in ", alarmTimeoutSeconds, " seconds")
		self.fallbackAlarmTimeout = Timer(alarmTimeoutMsecs,
				function ()
					if self.alarmInProgress then
						log:warn("*** Alarm: RTC alarm has timed out")
						self:_alarmOff()
					end
				end,
				true
		)
		if self.fallbackAlarmTimeout:isRunning() then
			self.fallbackAlarmTimeout:restart()
		else
			self.fallbackAlarmTimeout:start()
		end
	end

	-- Bug 16100 - Sound comes from headphones although Radio is set to use speaker
	-- Calling _alarmThroughSpeakers() here works for regular, fallback alarm and snooze
	self:_alarmThroughSpeakers()

	if self.alarmWindow then
		return
	end

	local window = Window('alarm_popup')

	self.time = self:_formattedTime()

	local label = Label('alarm_time', self.time)
	local headerGroup = Group('alarm_header', {
		time = label,
	})

	-- Bug 15398: make this menu 6x stickier than a normal menu for scrolling
	local menu = StickyMenu('menu', 6)
	menu:addItem({
		text = self:string("ALARM_SNOOZE_SNOOZE"),
		sound = "WINDOWHIDE",
		callback = function()
			self:_alarmSnooze()
			end,
	})
	menu:addItem({
		text = self:string("ALARM_SNOOZE_TURN_OFF_ALARM"),
		sound = "WINDOWHIDE",
		callback = function()
			self:_alarmOff(true)
			end,
	})	
	if self.server and self.server:getVersion() and self.server:isMoreRecent(self.server:getVersion(), '9.1.0') then
		menu:addItem({
			text = self:string("ALARM_SNOOZE_DISMISS"),
			sound = "WINDOWHIDE",
			callback = function()
				self:_alarmDismiss()
				end,
		})
	end
	menu:setSelectedIndex(1)

	local cancelAction = function()
		window:playSound("WINDOWHIDE")
		self:_alarmOff(false)
		return EVENT_CONSUME
	end

	local pauseAction = function()
		window:playSound("WINDOWHIDE")
		self:_alarmOff(true)
		return EVENT_UNUSED
	end

	local consumeAction = function()
		log:warn("*** Alarm: Consuming this action")
		Framework:playSound("BUMP")
		window:bumpLeft()
		return EVENT_CONSUME
	end

	local offAction = function()
		self:_alarmOff(true)
		return EVENT_UNUSED
	end
	
	local snoozeAction = function()
		self:_alarmSnooze()
		return EVENT_CONSUME
	end

	menu:addActionListener("back", self, cancelAction)
	menu:addActionListener("power", self, offAction)
	menu:addActionListener("mute", self, snoozeAction)
	menu:addActionListener("pause", self, pauseAction)

	window:ignoreAllInputExcept(
		--these actions are not ignored
		{ 'go', 'back', 'power', 'mute', 'volume_up', 'volume_down', 'pause' }, 
		-- consumeAction is the callback issued for all "ignored" input
		consumeAction 
	)

	menu:setHeaderWidget(headerGroup)

	window:setButtonAction('rbutton', 'cancel')
        window:addActionListener("cancel", self, 
		function() 	
			window:hide(Window.transitionNone)
		end 
	)
        window:setButtonAction('lbutton', nil, nil)

	window:addWidget(menu)
	window:setShowFrameworkWidgets(false)
	window:setAllowScreensaver(false)
	window:show(Window.transitionFadeIn)

	window:addTimer(1000, 
			function() 
				self:_updateTime() 
			end
	)

	window:setAlwaysOnTop(true)
	self.alarmWindow = window
	self.timeWidget  = label

end


function _hideAlarmWindow(self)
	if self.alarmWindow then
		self.alarmWindow:hide()
		self.alarmWindow = nil
		self:_revertAudioEndpointOverride()
	end
end


function free(self)
	self.alarmWindow = nil
	return false
end


function _updateTime(self)
	local time = self:_formattedTime()
	if time ~= self.time then 	 
		log:debug("*** Alarm: updating time in alarm window") 	 
		self.time = time 	 
		self.timeWidget:setValue(time) 	 
	end 	 
end


function _formattedTime(self)
	if not self.clockFormat then
		self.clockFormat = datetime:getHours()
	end

	local time
	if self.clockFormat == '12' then
		time = datetime:getCurrentTime('%I:%M')
	else
		time = datetime:getCurrentTime()
	end
	return time
end


-- returns the millisecond delta between now (current time) and the epochsecs parameter
-- returns default of 1000ms if epochsecs is in the past...
function _deltaMsecs(self, epochsecs)

	local deltaSecs = epochsecs - os.time() 
	if deltaSecs <= 0 then
		log:warn("*** Alarm: _deltaMsecs: epochsecs is in the past, deltaSecs: ", deltaSecs)
		return(1000)
	end
	-- else
	return(deltaSecs * 1000)
end


-- This is Baby only
function _setWakeupTime(self, setting)
	if not setting then
		-- wakeup 3 minutes before alarm
		setting = self.alarmNext - 180
	end
	appletManager:callService("setWakeupAlarm", setting)
end


-- On player with multiple audio output endpoints guarantee that alarm audio
-- comes through speakers even even Headphones (or some other output) is enabled
function _alarmThroughSpeakers(self)
	appletManager:callService("overrideAudioEndpoint", 'Speaker')
end

-- If alarm was overridden to the speaker then, when alarm is turned off, we need to 
-- revert the audio endpoint
--
-- note: this method is called from the _hideAlarmWindow() method, so if at some future date
-- there are options added to allow a user to have an alarm with no notification window, 
-- where the revert method is called  needs rethinking
function _revertAudioEndpointOverride(self)
	appletManager:callService("overrideAudioEndpoint", nil)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
