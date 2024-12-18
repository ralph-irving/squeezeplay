
local ipairs = ipairs

local oo            = require("loop.simple")

local lfs           = require("lfs")
local string        = require("string")

local AppletMeta    = require("jive.AppletMeta")
local Timer         = require("jive.ui.Timer")

local appletManager = appletManager
local jiveMain      = jiveMain
local jnt           = jnt


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {
		[ "sendLog" ] = false,
	}
end


function registerApplet(meta)
	meta:registerService("crashLog")

	meta.prompt = false
end


local function _findCrash(meta, boot)
	local crashLogs = {}

	for file in lfs.dir("/root") do
		if string.match(file, "^crashlog%.") then
			crashLogs[#crashLogs + 1] = "/root/" .. file

			appletManager:callService("crashLog", "/root/" .. file, meta.prompt)
			meta.prompt = false
		end
	end

	if boot and #crashLogs > 0 then
		-- XXXX need to somehow stop the player, this is not a
		-- reliable solution as it creates a race condition between
		-- the slimproto and comet connections to SC.
		jnt:subscribe(meta)
	end

	if #crashLogs > 0 then
		-- check every ten minutes
		meta.timer:setInterval(1000 * 60 * 10)
	else
		-- check every hour minutes
		meta.timer:setInterval(1000 * 60 * 60)
	end

	return crashLogs
end


function configureApplet(meta)
	meta.timer = Timer(1000, function()
		local crashLogs = _findCrash(meta, false)
	end)
	meta.timer:start()

	_findCrash(meta, true)
end


function notify_playerNew(meta, player)
	if player:isLocal() and player:getSlimServer() then
		log:info("crash log stopping player")
		player:stop()
		
		-- Bug 16170: after initial stop we do not want to do this again
		-- after any Comet reconnect 
		jnt:unsubscribe(meta)
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

