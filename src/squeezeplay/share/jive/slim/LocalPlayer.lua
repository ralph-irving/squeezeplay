--[[

Player instance for local playback.

--]]

local assert = assert

local oo             = require("loop.simple")

local Framework      = require("jive.ui.Framework")
local Player         = require("jive.slim.Player")
local math           = require("math")

local SlimProto      = require("jive.net.SlimProto")
local Playback       = require("jive.audio.Playback")

local jiveMain       = jiveMain
local debug          = require("jive.utils.debug")
local log            = require("jive.utils.log").logger("squeezebox.player")

local JIVE_VERSION   = jive.JIVE_VERSION

-- can be overridden by hardware specific classes
local DEVICE_ID      = 12
local DEVICE_MODEL   = "squeezeplay"
local DEVICE_NAME    = "SqueezePlay"


module(...)
oo.class(_M, Player)


-- class method to set the device type
function setDeviceType(self, model, name)
	 DEVICE_ID = 9
	 DEVICE_MODEL = model
	 DEVICE_NAME = name or model
end


-- class method to get the device type etc.
function getDeviceType(self)
	return DEVICE_ID, DEVICE_MODEL, DEVICE_NAME
end


--class method - disconnect from player and server and re-set "clean (no server)" LocalPlayer as current player (if there is a local player), otherwise set current player to nil
function disconnectServerAndPreserveLocalPlayer(self)
	--disconnect from player and server
	self:setCurrentPlayer(nil)

	--Free server from local player (removed: todo clean up this method name), and re-set current player to LocalPlayer
	local localPlayer = Player:getLocalPlayer()
	if localPlayer then
		if localPlayer:getSlimServer() then
			localPlayer:stop()
		end
		Player:setCurrentPlayer(localPlayer)
	end


end


function getLastSqueezeCenter(self)
	return self.lastSqueezeCenter
end


function setLastSqueezeCenter(self, server)
	log:debug("lastSqueezeCenter set: ", server)

	self.lastSqueezeCenter = server
end


function __init(self, jnt, playerId, uuid)
	local obj = oo.rawnew(self, Player(jnt, playerId))

	obj.slimproto = SlimProto(jnt, {
		opcode = "HELO",
		deviceID = DEVICE_ID,
	       	version = JIVE_VERSION,
		mac = obj.id,
		uuid = uuid,
		model = DEVICE_MODEL,
		modelName = DEVICE_NAME,
	})
	obj.playback = Playback(jnt, obj.slimproto)

	-- initialize with default values
	obj:updateInit(nil, {
		name = DEVICE_NAME,
		model = DEVICE_MODEL,
	})

	return obj
end


function destroy(self, server)
	-- close any previous connection
	if self.slimproto then
		self.slimproto:disconnect()
		self.slimproto = nil
	end

	if self.playback then
		self.playback:stop()
		self.playback = nil
	end

	Player.free(self, server)
end


function playFileInLoop(self, file)
	return self.playback:playFileInLoop(file)
end


function updateInit(self, server, init)
	Player.updateInit(self, server, init)

	if server then
		self:connectToServer(server)
	end
end


function incrementSequenceNumber(self)
	return self.playback:incrementSequenceNumber()
end

function getCurrentSequenceNumber(self)
	return self.playback:getCurrentSequenceNumber()
end

function isSequenceNumberInSync(self, serverSequenceNumber)
	return self.playback:isSequenceNumberInSync(serverSequenceNumber)
end

function isStreaming(self)
	if self.playback and self.playback.stream then
		return true
	else
		return false
	end
end

--resend local values to server, but only update seq number on last call, so that the next player status comes back with a single increase 
function refreshLocallyMaintainedParameters(self)
	log:debug("refreshLocallyMaintainedParameters()")

	--refresh volume
	self:_volumeNoIncrement(self:getVolume(), true, true)

	--refresh power state
	self:setPower(jiveMain:getSoftPowerState() == "on")

	--todo: pause, mute

end

function isLocal(self)
	return true
end


function needsNetworkConfig(self)
	return false
end


function needsMusicSource(self)
	if not self.slimproto then
		log:warn("no slimproto connection")
		return true
	end
	return not self.slimproto:isConnected()
end


function canConnectToServer(self)
	return true
end


function connectToServer(self, server)

	if not server then
		log:error("No server passed to connectToServer() method")
		return false
	end

	-- make sure the server we are connecting to is awake
	server:wakeOnLan()

	-- Needs to be fully connected, both SlimProto and Comet connection before we can use server connection
	-- Otherwise, just do it locally
	if not self:isConnected() and self.slimproto then
		log:info('connectToServer(): connecting localPlayer to server', server, ' via internal call')

		-- close any previous connection
		self.slimproto:disconnect()

		server:addLocallyRequestedServer(server)
		self.slimproto:connect(server)
	else
		log:info('connectToServer(): switching localPlayer to server', server)
		local ip, port = server:getIpPort()

		server:addLocallyRequestedServer(server)
		self:send({'connect', ip}, true)
	end
	return true

end

function connectIp(self, serverip, slimserverip)
	if not self.slimproto then
		log:warn("no slimproto connection")
		return
	end
	self.slimproto:disconnect()
	self.slimproto:connectIp(serverip, slimserverip)
end


function disconnectFromServer(self)
	if not self.slimproto then
		log:warn("no slimproto connection")
		return
	end
	self.slimproto:disconnect()
	self.playback:stop()
end


function getLastSeen(self)
	-- never timeout a local player
	return Framework:getTicks()
end


-- Alan Young, 20100223 - I do not understand why the local player's 
-- isConnected method only took into account the state of the Slimproto
-- connection and ignored whether any server that we know about has reported that the
-- player is connected.
--
-- If, however, someone comes back to this and decides that should be like that after all,
-- then connectToServer() needs to be changed to use 
-- "Player.isConnected(self) and self.slimproto:isConnected()", 
-- instead of self:isConnected() as the test to determine whether or not the server
-- can be used to tell the player to switch servers.

function isConnected(self)
	if not self.slimproto then
		log:warn('no slimproto connection')
		return false
	end
	return self.slimproto:isConnected() and Player.isConnected(self)
end


-- Has the connection attempt actually failed
function hasConnectionFailed(self)
	if not self.slimproto then
		return true
	end
	return self.slimproto:hasConnectionFailed()
end


function setSignalStrength(self, signalStrength)
	self.playback:setSignalStrength(signalStrength)
end


function getEffectivePlayMode(self)
	local source = self.playback:getSource()

	if source == "capture" then
		return self:getCapturePlayMode()
	elseif source == "file" then
		return "play"
	else
		return self:getPlayMode()
	end
end

function getCapturePlayMode(self)
	return self.playback:getCapturePlayMode()
end


function setCapturePlayMode(self, capturePlayMode)
	self.playback:setCapturePlayMode(capturePlayMode)
	self:updateIconbar()
end

function captureVolume(self, volume)
	self.playback:setCaptureVolume(volume)
end


function getCaptureVolume(self)
	return self.playback:getCaptureVolume()
end


function getVolume(self)
	return self.playback:getVolume()
end


-- volume
-- send new volume value to SS, returns a negative value if the player is muted
function volume(self, vol, send)
	self:volumeLocal(vol)
	return Player.volume(self, vol, send, self:incrementSequenceNumber())
end


function _volumeNoIncrement(self, vol, send, stateOnly)
	self:volumeLocal(vol, nil, stateOnly)
	return Player.volume(self, vol, send)
end

function volumeLocal(self, vol, updateSequenceNumber, stateOnly)
	--sometime we want to update the sequence number directly, like when there is no server connection and volume is changed
	if updateSequenceNumber then
		self:incrementSequenceNumber()
	end
	self.playback:setVolume(vol, stateOnly)
end

function volumeFromController(self, vol, controller, sequenceNumber)
	self.playback:setVolume(vol, false, controller, sequenceNumber)
end

function mute(self, mute)
	local vol = self:getVolume()

	if mute and vol >= 0 then
		-- mute
		self:volumeLocal(-math.abs(vol), true)

	elseif vol < 0 then
		-- unmute
		self:volumeLocal(math.abs(vol), true)

	end

	return Player.mute(self, mute, self:incrementSequenceNumber())
end


function pause(self, useBackgroundRequest, localActionOnly)
	local active = self.playback:isLocalPauseOrStopTimeoutActive()
	if not active then
		self.playback:startLocalPauseTimeout()
		self.mode = "pause"
		self:updateIconbar()

		if not localActionOnly then Player.pause(self, useBackgroundRequest) end
	else
		log:debug("discarding pause while timeout active")
	end
end


function stop(self, skipDelay)
	local active = self.playback:isLocalPauseOrStopTimeoutActive()
	if not active then
		if skipDelay then
			self.playback:stopInternal()
		else
			self.playback:startLocalStopTimeout()
		end
		if self:isConnected() then
			self.mode = "stop"
			self:updateIconbar()
	
			Player.stop(self)
		end
	else
		log:debug("discarding stop while timeout active")
	end
end


--overridden only to prevent unpausing while awaiting possible local timeout, otherwise just call parent, since no local unpause
function unpause(self)
	local active = self.playback:isLocalPauseOrStopTimeoutActive()
	if not active then
		Player.unpause(self)
	else
		log:debug("discarding unpause while timeout active")
	end
end


--overridden only to prevent unpausing while awaiting possible local timeout, otherwise just call parent, since no local unpause
function play(self)
	local active = self.playback:isLocalPauseOrStopTimeoutActive()
	if not active then
		Player.play(self)
	else
		log:debug("discarding unpause while timeout active")
	end
end


--overridden to stop playback when powering off
function setPower(self, on, _, isServerRequest) -- ignoring third param 'sequenceNumber' (only used by parent class's version)
	if not on then
		if self:getCapturePlayMode() then
			self:setCapturePlayMode("pause")
		else
			--purely local pause so as not to interfere with SC player sync logic
			self.playback:pause()
		end

	end
	if self:getSlimServer() and not isServerRequest then
		Player.setPower(self, on, self:incrementSequenceNumber())
	end
end


function __tostring(self)
	return "LocalPlayer {" .. self:getName() .. "}"
end



--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
