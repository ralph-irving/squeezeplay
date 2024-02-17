
local assert, getmetatable = assert, getmetatable

local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")
local Timer                  = require("jive.ui.Timer")

local LocalPlayer   = require("jive.slim.LocalPlayer")
local SlimServer    = require("jive.slim.SlimServer")
local Framework              = require("jive.ui.Framework")

local EVENT_KEY_ALL          = jive.ui.EVENT_KEY_ALL
local EVENT_KEY_DOWN         = jive.ui.EVENT_KEY_DOWN
local EVENT_KEY_HOLD         = jive.ui.EVENT_KEY_HOLD
local EVENT_KEY_UP           = jive.ui.EVENT_KEY_UP
local EVENT_KEY_PRESS        = jive.ui.EVENT_KEY_PRESS
local EVENT_IR_REPEAT        = jive.ui.EVENT_IR_REPEAT
local EVENT_IR_DOWN          = jive.ui.EVENT_IR_DOWN
local EVENT_IR_ALL           = jive.ui.EVENT_IR_ALL
local EVENT_SCROLL           = jive.ui.EVENT_SCROLL
local ACTION                 = jive.ui.ACTION

local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_UNUSED           = jive.ui.EVENT_UNUSED

local KEY_GO                 = jive.ui.KEY_GO
local KEY_VOLUME_DOWN        = jive.ui.KEY_VOLUME_DOWN
local KEY_VOLUME_UP          = jive.ui.KEY_VOLUME_UP


local debug         = require("jive.utils.debug")

local appletManager = appletManager
local jiveMain      = jiveMain
local jnt           = jnt


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function defaultSettings(self)
	return {
		-- Enable audio playback
		-- 0 == default off
		-- 1 == default on
		-- 2 == user off
		-- 3 == user on
		enableAudio = 0,
	}
end


function registerApplet(meta)
	local settings = meta:getSettings()

	-- this allows us to share state with the applet
	meta.state = {}

	if not System:hasAudioByDefault() then
		jiveMain:addItem(meta:menuItem('audioPlayback', 'advancedSettingsBetaFeatures', "AUDIO_PLAYBACK", function(applet, ...) applet:settingsShow(meta.state) end))
	end
end


function configureApplet(meta)
	local settings = meta:getSettings()

	if settings.enableAudio & 1 == 0 then
		-- no audio playback
		return
	end

	-- Create player instance
	local uuid = System:getUUID()
	local playerid = System:getMacAddress()
	assert(uuid)
	assert(playerid)

	meta.state.player = LocalPlayer(jnt, playerid, uuid)

	if not settings.volume then
		settings.volume = 40
	end

	if not settings.captureVolume then
		settings.captureVolume = 40
	end
	meta.state.player:volumeLocal(settings.volume)
	meta.state.player:captureVolume(settings.captureVolume)

	if not settings.powerState then
		settings.powerState = "on"
	end
	--must defer this since skin isn't loaded yet
	jiveMain:registerPostOnScreenInit(      function()
							--Bug 16593: always start on, even if soft power state was off when shutdown
							-- this is to avoid a situation where a Radio powers up to a black screen (fallback whenOff SS when clock is not set)
							jiveMain:setSoftPowerState("on")
						end)
	
	-- Connect player
	local server = nil
	if settings.serverName then
		if not settings.serverUuid then
			settings.serverUuid = settings.serverName
		end
		server = SlimServer(jnt, settings.serverUuid, settings.serverName)

		server:updateInit(settings.serverInit)
		meta.state.player:setLastSqueezeCenter(server)
	end

	-- if settings.squeezeNetwork then
	--	server = SlimServer(jnt, "mysqueezebox.com", "mysqueezebox.com")
	--	server:updateInit({ip=jnt:getSNHostname()}, 9000)
	-- end

	-- Init player
	if settings.playerInit then
	--always try to go back to last SC - good/bad?
--		if settings.squeezeNetwork then
--		meta.state.player:updateInit(nil, settings.playerInit)
--		else
--		meta.state.player:updateInit(server, settings.playerInit)
--		end

		meta.state.player:updateInit(server, settings.playerInit)
	end

	local playerSettingsTimer = Timer(10000,
				function ()
					_updateLocallyMaintainedParams(meta)
				end)
	playerSettingsTimer:start()

	-- Subscribe to changes in player status
	jnt:subscribe(meta)

	--add listeners for local control. SlimBrowser's handlers for this will win when a player is connected
	local volumeActionHandler = function(self, event)
		local currentPlayer = LocalPlayer:getCurrentPlayer()
		if not currentPlayer or currentPlayer ~= meta.state.player then --todo or if not line-in is selected
			--only adjust local volume when the current player is the local player.
			return
		end

		log:debug("Using local volume control Handler")

		local volume = appletManager:callService('getAudioVolumeManager')
		volume:setPlayer(meta.state.player)
		volume:setOffline(true)
		
		return volume:event(event, true)
	end

	Framework:addActionListener("volume_up", self, volumeActionHandler, 2)
	Framework:addActionListener("volume_down", self, volumeActionHandler, 2)

	Framework:addListener(EVENT_KEY_DOWN | EVENT_KEY_PRESS | EVENT_KEY_HOLD | EVENT_IR_ALL,
		function(event)
			local type = event:getType()

			if (type & EVENT_IR_ALL ) > 0 then
				if event:isIRCode("volup") or event:isIRCode("voldown") then
					return volumeActionHandler(self, event)
				end
				return EVENT_UNUSED
			end

			if event:getKeycode() == KEY_VOLUME_UP or event:getKeycode() == KEY_VOLUME_DOWN then
					return volumeActionHandler(self, event)
			end

			return EVENT_UNUSED
		end,
		2
	)

	jiveMain:registerPostOnScreenInit(      function()
							if appletManager:callService("isLineInConnected") and settings.capturePlayMode then
								log:info("Activating Line In")
								appletManager:callService("activateLineIn", true, settings.capturePlayMode)
							end
						end)

end

function _updateLocallyMaintainedParams(meta)
	local saveSettings = false
	local settings = meta:getSettings()

	if meta.state.player then
		if meta.state.player:getVolume() ~= settings.volume then
			saveSettings = true
			settings.volume = meta.state.player:getVolume()
		end

		if jiveMain:getSoftPowerState() ~= settings.powerState then
			saveSettings = true
			settings.powerState = jiveMain:getSoftPowerState()
		end

		if meta.state.player:getCaptureVolume() ~= settings.captureVolume then
			saveSettings = true
			settings.captureVolume = meta.state.player:getCaptureVolume()
		end

		if meta.state.player:getCapturePlayMode() ~= settings.capturePlayMode then
			saveSettings = true
			settings.capturePlayMode = meta.state.player:getCapturePlayMode()
		end

	end

	if saveSettings then
		meta:storeSettings()
	end
end


function _updateSettings(meta, player, force)
	local settings = meta:getSettings()

	local server = player and player:getSlimServer() or false
	local serverName = server and server:getName() or false

	if not player:isConnected() then
		return
	end

	local ipChanged = false

	local settingsIp
	if meta:getSettings().serverInit then
		settingsIp = meta:getSettings().serverInit.ip
	end
	if player and player:getSlimServer() and player:getSlimServer().ip ~= settingsIp then
		--actual server ip might have changed from what Playback's settings has (re-dhcp, moving locations, etc)
		log:debug("Updating Playback server on new ip address: ", player:getSlimServer().ip)
		ipChanged = true
	end

	local macChanged = false
	local settingsMac
	if meta:getSettings().serverInit then
		settingsMac = meta:getSettings().serverInit.mac
	end
	if player and player:getSlimServer() and player:getSlimServer():getInit().mac ~= settingsMac then
		log:debug("Updating Playback server on new mac address: ", player:getSlimServer():getInit().mac)
		ipChanged = true
	end

	if not macChanged and not ipChanged and not force and
	   settings.serverName == serverName and
	   settings.squeezeNetwork == server:isSqueezeNetwork() then
		-- no change
		return
	end

	if macChanged or ipChanged or (server and
		( settings.squeezeNetwork ~= server:isSqueezeNetwork()
		  or settings.serverName ~= server:getName() )) then
		settings.squeezeNetwork = server:isSqueezeNetwork()

		-- remember server if it's not SN
		if not settings.squeezeNetwork then
			settings.serverName = server:getName()
			settings.serverUuid = server:getId()
			settings.serverInit = server:getInit()
		end

		saveSettings = true
	end
	settings.playerInit = player:getInit()

	meta:storeSettings()
end


function notify_playerConnected(meta, player)
	if meta.state.player ~= player then
		return
	end

	_updateSettings(meta, player)
end


function notify_playerNewName(meta, player, playerName)
	if meta.state.player ~= player then
		return
	end

	_updateSettings(meta, player, true)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

