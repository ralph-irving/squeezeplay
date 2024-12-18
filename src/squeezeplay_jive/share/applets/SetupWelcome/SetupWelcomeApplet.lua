
--[[
=head1 NAME

applets.SetupWelcome.SetupWelcome

=head1 DESCRIPTION

Setup Applet for (Controller) Squeezebox

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>.

=cut
--]]


-- stuff we use
local ipairs, pairs, assert, io, string, tonumber = ipairs, pairs, assert, io, string, tonumber

local oo               = require("loop.simple")
local os               = require("os")

local Applet           = require("jive.Applet")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local Icon             = require("jive.ui.Icon")
local Group            = require("jive.ui.Group")
local Button           = require("jive.ui.Button")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")
local Popup            = require("jive.ui.Popup")

local localPlayer      = require("jive.slim.LocalPlayer")
local slimServer       = require("jive.slim.SlimServer")

local DNS              = require("jive.net.DNS")
local Networking       = require("jive.net.Networking")

local debug            = require("jive.utils.debug")
local locale           = require("jive.utils.locale")
local string           = require("jive.utils.string")
local table            = require("jive.utils.table")

local appletManager    = appletManager

local jiveMain         = jiveMain
local jnt              = jnt

local welcomeTitleStyle = 'setuptitle'

module(..., Framework.constants)
oo.class(_M, Applet)


function startSetup(self)
	step1(self)
end


function _addReturnToSetupToHomeMenu(self)
	--first remove any existing
	jiveMain:removeItemById('returnToSetup')

	local returnToSetup = {
		id   = 'returnToSetup',
		node = 'home',
		text = self:string("RETURN_TO_SETUP"),
		iconStyle = 'hm_settings',
		weight = 2,
		callback = function()
			self:step1()
		end
		}
	jiveMain:addItem(returnToSetup)
end


function _setupComplete(self, gohome)
	log:info("_setupComplete gohome=", gohome)

	jiveMain:removeItemById('returnToSetup')

	if gohome then
		jiveMain:closeToHome(true, Window.transitionPushLeft)
	end
end


function step1(self)
	-- add 'RETURN_TO_SETUP' at top
	log:debug('step1')
	self:_addReturnToSetupToHomeMenu()

	-- choose language
	appletManager:callService("setupShowSetupLanguage",
		function()
			self:step4()
		end, false)
end


-- Scan for not yet setup squeezebox
function step4(self, transition)
	log:info("step4")

	-- Finding networks including not yet setup squeezebox
	self.scanWindow = appletManager:callService("setupScan",
				function()
					self:step5()
					-- FIXME is this required:
					if self.scanWindow then
						self.scanWindow:hide()
						self.scanWindow = nil
					end
				end,
				transition)

	return self.scanWindow
end


-- Scan for not yet setup squeezebox
function step5(self)
	log:info("step5")

	-- Get scan results
	local wlanIface = Networking:wirelessInterface(jnt)
	local scanResults = wlanIface:scanResults()

	for ssid,_ in pairs(scanResults) do
		log:warn("checking ssid ", ssid)

		-- '+' in SSID means squeezebox has ethernet connected
		if string.match(ssid, "logitech%+squeezebox%+%x+") then
			return self:setupConnectionShow(
					function()
						self:step51()
					end,
					function()
						self:step52()
					end)
		end
	end

	return self:step52()
end

-- Setup bridged mode
function step51(self)
	log:info("step51")

	-- Connect using squeezebox in adhoc mode
	return appletManager:callService("setupAdhocShow",
				function()
					self:step8point5()
				end)
end

-- Setup Controller to AP
function step52(self)
	log:info("step52")

	-- Connect using regular network, i.e. connect to AP
	return appletManager:callService("setupNetworking",
			function()
				self:step8point5()
			end)
end


-- Offer selection between standard wireless/wired or bridged setup
function setupConnectionShow(self, setupSqueezebox, setupNetwork)
	local window = Window("window", self:string("WIRELESS_CONNECTION"), welcomeTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu")

	menu:addItem({
			     text = self:string("CONNECT_USING_SQUEEZEBOX"),
			     sound = "WINDOWSHOW",
			     callback = setupSqueezebox,
		     })
	menu:addItem({
			     text = self:string("CONNECT_USING_NETWORK"),
			     sound = "WINDOWSHOW",
			     callback = setupNetwork,
		     })
	
	window:addWidget(Textarea("help", self:string("CONNECT_HELP")))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


-- step 8.5 makes sure we have a current player, this will already be the
-- case for a local player or a bridged setup (on jive).

function step8point5(self)
	log:info("step8point5")

	-- find player
	return appletManager:callService("setupShowSelectPlayer", function()
		self:step9()
	end, 'setuptitle')
end


function step9(self)
	log:info("step9")

	_setupComplete(self, false)
	_setupDone(self, true, true)

	jiveMain:goHome()

end


--finish setup if connected server is SC
function notify_playerCurrent(self, player)
	if not player then
		return
	end

	local server = player:getSlimServer()

	if not server then
		return
	end

	log:info("Calling step9 server: ", server)

	step9(self)
end


function isSetupDone(self)
	local settings = self:getSettings()

	return settings and settings.setupDone
end


function _setupDone(self, setupDone, registerDone)
	log:info("network setup complete")

	local settings = self:getSettings()

	settings.setupDone = setupDone
	settings.registerDone = registerDone
	self:storeSettings()

	-- FIXME: workaround until filesystem write issue resolved
	os.execute("sync")
end


function init(self)
	log:info("subscribe")
	jnt:subscribe(self)
end


function free(self)
	appletManager:callService("setDateTimeDefaultFormats")
	return not self.locked
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

