

-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------



-- stuff we use
local assert, getmetatable, ipairs, pairs, pcall, setmetatable, tonumber, tostring, type = assert, getmetatable, ipairs, pairs, pcall, setmetatable, tonumber, tostring, type

local oo                     = require("loop.simple")

local io                     = require("io")
local os                     = require("os")
local string                 = require("string")
local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local Applet                 = require("jive.Applet")
local System                 = require("jive.System")
local Event                  = require("jive.ui.Event")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local Button                 = require("jive.ui.Button")
local Group                  = require("jive.ui.Group")
local Keyboard               = require("jive.ui.Keyboard")
local Tile                   = require("jive.ui.Tile")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Surface                = require("jive.ui.Surface")
local Task                   = require("jive.ui.Task")
local Textarea               = require("jive.ui.Textarea")
local Textinput              = require("jive.ui.Textinput")
local Window                 = require("jive.ui.Window")
local Popup                  = require("jive.ui.Popup")

local Networking             = require("jive.net.Networking")


local appletManager          = appletManager
local jnt                    = jnt
local jiveMain               = jiveMain

local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE


-- configuration
local CONNECT_TIMEOUT = 30		-- Used twice: connecting and DHCP
local WPS_WALK_TIMEOUT = 120		-- WPS walk timeout


module(..., Framework.constants)
oo.class(_M, Applet)


function init(self)
	self.wlanIface = Networking:wirelessInterface(jnt)
	self.ethIface = Networking:wiredInterface(jnt)

	self.scanResults = {}
end


function _helpAction(self, window, titleText, bodyText, menu)
	if titleText or bodyText then
		local moreHelpAction =  function()
						window:playSound("WINDOWSHOW")
						appletManager:callService("supportMenu")
					end
		local helpAction =      function()
						local window = Window("help_info", self:string(titleText), "helptitle")
						window:setAllowScreensaver(false)

						window:setButtonAction("rbutton", "more_help")
						window:addActionListener("more_help", self, moreHelpAction)
						local menu = SimpleMenu("menu")
						jiveMain:addHelpMenuItem(menu, self, moreHelpAction, "GLOBAL_SUPPORT")

						local textarea = Textarea("help_text", self:string(bodyText))
						window:addWidget(menu)
						menu:setHeaderWidget(textarea)
						self:tieAndShowWindow(window)

						window:playSound("WINDOWSHOW")
					end

		window:addActionListener("help", self, helpAction)
		if menu then
			jiveMain:addHelpMenuItem(menu, self, helpAction)
		end
	else
		if menu then
	                        jiveMain:addHelpMenuItem(menu, self,    function()
                        							appletManager:callService("supportMenu")
                        						end)

		end
	end

	window:setButtonAction("rbutton", "help")
end


-- Setup: Needed to find not yet setup Receiver
function setupScan(self, setupNext)
	local window = Popup("waiting_popup")
	window:setAllowScreensaver(false)

	window:addWidget(Icon("icon_connecting"))
	window:addWidget(Label("text", self:string("NETWORK_FINDING_NETWORKS")))

	-- wait for network scan (in task)
	self.wlanIface:scan(setupNext)

	-- or timeout after 10 seconds if no networks are found
	window:addTimer(10000, function() setupNext() end, true)	-- once

	self:tieAndShowWindow(window)
	return window
end


-- start network setup flow
function setupNetworking(self, setupNext, transition)
	self.mode = "setup"

	self.setupNext = setupNext

	_wirelessRegion(self, self.wlanIface, transition)
end


-- start network settings flow
function settingsNetworking(self)
	self.mode = "settings"

	local topWindow = Framework.windowStack[1]
	self.setupNext = function()
		local stack = Framework.windowStack
		for i=1,#stack do
			if stack[i] == topWindow then
				for j=i-1,1,-1 do
					stack[j]:hide(Window.transitionPushLeft)
				end
			end
		end
	end

	_wirelessRegion(self, self.wlanIface)
end


-------- CONNECTION TYPE --------

-- connection type (ethernet or wireless)
function _connectionType(self)
	log:debug('_connectionType')

	assert(self.wlanIface or self.ethIface)

-- fm+
	-- Shortcut to use Ethernet immediately if available and link is up
	if self.ethIface then
		Task("halfDuplexBugVerification", self,
			function()
				local pingOK = false
				local status = self.ethIface:t_wpaStatus()
				if status.link and status.ip_dns then
					local window = Popup("waiting_popup")
					window:setAllowScreensaver(false)

					window:addWidget(Icon("icon_connecting"))
					window:addWidget(Label("text", self:string("NETWORK_ETHERNET_CHECK")))
					self:tieAndShowWindow(window)

					-- First ping dns server to prevent long
					--  delays while trying to resolve mysb.com
					if self.ethIface:pingServer(status.ip_dns) then
						-- Then ping mysb.com
						pingOK = self.ethIface:pingServer(jnt:getSNHostname())
					end
				end

				if pingOK then
					return _halfDuplexBugVerification(self, self.ethIface)
				else
					-- Ethernet available but no link or ping failed - do a wireless scan
					return _networkScan(self, self.wlanIface)
				end
			end
		):addTask()
	else
		-- Only wireless available - do a wireless scan
		return _networkScan(self, self.wlanIface)
	end
-- fm-


--[[
	-- short cut if only one interface is available
	if not self.wlanIface then
		-- Only ethernet available
		return _networkScan(self, self.ethIface)
	elseif not self.ethIface then
		-- Only wireless available
		return _networkScan(self, self.wlanIface)
	end

	-- ask the user to choose
	local window = Window("text_list", self:string("NETWORK_CONNECTION_TYPE"), "setup")
	window:setAllowScreensaver(false)

	local connectionMenu = SimpleMenu("menu")

	connectionMenu:addItem({
		iconStyle = 'wlan',
		text = (self:string("NETWORK_CONNECTION_TYPE_WIRELESS")),
		sound = "WINDOWSHOW",
		callback = function()
			_networkScan(self, self.wlanIface)
		end,
		weight = 1
	})
	
	connectionMenu:addItem({
		iconStyle = 'wired',
		text = (self:string("NETWORK_CONNECTION_TYPE_WIRED")),
		sound = "WINDOWSHOW",
		callback = function()
			_networkScan(self, self.ethIface)
		end,
		weight = 2
	})

	window:addWidget(connectionMenu)

	_helpAction(self, window, "NETWORK_CONNECTION_HELP", "NETWORK_CONNECTION_HELP_BODY", connectionMenu)

	self:tieAndShowWindow(window)
--]]
end


-------- WIRELESS REGION --------

-- select wireless region
function _wirelessRegion(self, wlan, transition)
	-- skip region if already set and not in setup mode, or if wlan is nil
	if (self:getSettings()['region'] and self.mode ~= "setup") or not wlan then
		return _connectionType(self)
	end

	-- skip region for atheros wlan as it supports 'world' region that
	-- automatically configures the radio based on ap beacons
	-- if wlan:isAtheros() then
	--	 return _connectionType(self)
	-- end

	local window = Window("text_list", self:string("NETWORK_REGION"), "setup")
	window:setAllowScreensaver(false)

	local region = wlan:getRegion()

	local menu = SimpleMenu("menu")

	for name in wlan:getRegionNames() do
		log:debug("region=", region, " name=", name)
		local item = {
			text = self:string("NETWORK_REGION_" .. name),
			iconStyle = "region_" .. name,
			sound = "WINDOWSHOW",
			callback = function()
					if region ~= name then
						wlan:setRegion(name)
					end
					self:getSettings()['region'] = name
                       			self:storeSettings()

					_connectionType(self)
				   end
		}

		menu:addItem(item)
		if region == name then
			menu:setSelectedItem(item)
		end
	end

	window:addWidget(menu)

	_helpAction(self, window, "NETWORK_REGION_HELP", "NETWORK_REGION_HELP_BODY", menu)

	self:tieAndShowWindow(window, transition)
end


-------- NETWORK SCANNING --------

-- scan menu: add network
function _addNetwork(self, iface, ssid)

	local mSsid = ""
	if iface:isWireless() then
		-- I am pretty sure there is a more elegant Lua solution to
		--  replace every character above 127 with a question mark...
		local tSsid = {ssid:byte( 1, -1)}
		for i = 1, #tSsid do
			if tSsid[i] < 32 or tSsid[i] >= 127 then
				tSsid[i] = string.byte( '?')
			end
			mSsid = mSsid .. string.char( tSsid[i])
		end
	end

	local item = {
		text = iface:isWireless() and mSsid or tostring(self:string("NETWORK_ETHERNET")),
		arrow = Icon("icon"),
		sound = "WINDOWSHOW",
		callback = function()
			_enterPassword(self, iface, ssid)
		end,
		weight = iface:isWireless() and 1 or 2
	}
		      
	self.scanResults[ssid] = {
		item = item,            -- menu item
		iface = iface,		-- interface
		-- flags = nil,         -- beacon flags
		-- bssid = nil,         -- bssid if know from scan
		-- id = nil             -- wpa_ctrl id if configured
	}

	if self.scanMenu then
		self.scanMenu:addItem(item)
	end
end


-- perform scan on the network interface
function _networkScan(self, iface)
	local popup = Popup("waiting_popup")
	popup:setAllowScreensaver(false)
	popup:ignoreAllInputExcept()

        popup:addWidget(Icon("icon_connecting"))
        popup:addWidget(Label("text", self:string("NETWORK_FINDING_NETWORKS")))

	local status = Label("subtext", self:string("NETWORK_FOUND_NETWORKS", 0))
	popup:addWidget(status)

	local now = os.time()

        popup:addTimer(1000, function()
			local numNetworks = 0

			local results = iface:scanResults()
			for k, v in pairs(results) do
				numNetworks = numNetworks + 1
			end

			status:setValue(self:string("NETWORK_FOUND_NETWORKS", tostring(numNetworks) ) )
		end,
		false	-- repeat
	)

	-- start network scan
	iface:scan(function()
		-- Wait at least 2 seconds (and leave the spinny up)
		--  to allow the user to read the screen
		if os.time() > (now + 2) then
			_networkScanComplete(self, iface)
		else
			popup:addTimer(2000,
				function ()
					_networkScanComplete(self, iface)
				end,
				true	-- once
			)
		end
	end)

	-- or timeout after 10 seconds if no networks are found
	popup:addTimer(10000,
		function()
			ifaceCount = 0
			_networkScanComplete(self, iface)
		end,
		true	-- once
	)

	self:tieAndShowWindow(popup)
end


-- network scan is complete, show results
function _networkScanComplete(self, iface)
	self.scanResults = {}

-- fm+
--[[
	-- for ethernet, automatically connect
	if not iface:isWireless() then
		local nextStep =        function()
						_scanResults(self, iface)

						_connect(self, iface, iface:getName(), true, false)
					end

		if appletManager:callService("performHalfDuplexBugTest") then
			_halfDuplexBugTest(self, iface, nextStep)
			return
		else
			nextStep()
			return
		end
	end
--]]
-- fm-

	local window = Window("text_list", self:string("NETWORK_WIRELESS_NETWORKS"), 'setuptitle')
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu")
	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	-- add hidden ssid menu
	menu:addItem({
-- fm+
--		text = self:string("NETWORK_ENTER_ANOTHER_NETWORK"),
		text = "[" .. tostring(self:string("NETWORK_NETWORK_NAME")) .. "]",
-- fm-
		sound = "WINDOWSHOW",
		callback = function()
-- fm+
--			_chooseEnterSSID(self, iface)
			_enterSSID(self, iface)
-- fm-
		end,
		weight = 10
	})

-- fm+
	-- add 'Ethernet' menu item if available
	if self.ethIface then
		menu:addItem({
			text = self:string("NETWORK_ETHERNET"),
			sound = "WINDOWSHOW",
			callback = function()
				_halfDuplexBugVerification(self, self.ethIface)
			end,
			weight = 11
		})
	end

	-- add 'search again' menu item
	menu:addItem({
		text = self:string("NETWORK_SEARCH_FOR_MY_NETWORK"),
		sound = "WINDOWSHOW",
		callback = function()
			_networkScanAgain(self, iface, false)
		end,
		weight = 12
	})
-- fm-


	window:addWidget(menu)

	self.scanWindow = window
	self.scanMenu = menu

	-- process existing scan results
	_scanResults(self, iface)

	-- schedule network scan 
	self.scanMenu:addTimer(5000,
		function()
			-- only scan if this window is on top, not under a transparent popup
			if Framework.windowStack[1] ~= window then
				return
			end

			window:setTitle(self:string("NETWORK_FINDING_NETWORKS"))
			iface:scan(function()
				-- Restore window title, but after an interval, otherwise flashes by too fast on baby.
				window:addTimer(500,
								function()
									window:setTitle(self:string("NETWORK_WIRELESS_NETWORKS"))
								end,
								true)	-- once
				_scanResults(self, iface)
			end)
		end,
		false	-- repeat
	)
	_helpAction(self, window, "NETWORK_LIST_HELP", "NETWORK_LIST_HELP_BODY", self.scanMenu)

	self:tieAndShowWindow(window)
end


-- collapse windows and reopen network scan
function _networkScanAgain(self, iface, isComplete)
	self.scanWindow:hideToTop()

	if isComplete then
		_networkScanComplete(self, iface)
	else
		_networkScan(self, iface)
	end
end


function _scanResults(self, iface)
	local scanTable = iface:scanResults()

	for ssid, entry in pairs(scanTable) do

		if string.match(ssid, "logitech[%-%+%*]squeezebox[%-%+%*](%x+)") then
			-- hide squeezebox ad-hoc networks

		elseif string.match(ssid, "^\\x00") then
			-- hide "hidden" SSIDs
			-- Note: wpa_supplicant >= v2.0 changed its SSID output to use
			-- printf-escaped strings for non-ASCII characters instead of
			-- masking with '_'.
			-- Immediate impact is that "hidden" SSIDs are now visible.
			-- We recognize these by their 'null' first byte which will
			-- show up as '\x00'.
			log:debug("hiding SSID: " .. ssid)

		else
			if not self.scanResults[ssid] then
				_addNetwork(self, iface, ssid)
			end

			-- always update the id, bssid and flags
			self.scanResults[ssid].id = entry.id
			self.scanResults[ssid].bssid = entry.bssid
			self.scanResults[ssid].flags = entry.flags

			self.scanResults[ssid].associated = entry.associated
			self.scanResults[ssid].quality = entry.quality
		end
	end

	-- remove old networks
	for ssid, entry in pairs(self.scanResults) do
		if entry.iface == iface and not scanTable[ssid] then
			if self.scanMenu then
				self.scanMenu:removeItem(entry.item)
			end
			self.scanResults[ssid] = nil
		end
	end

	-- update networks
	for ssid, entry in pairs(self.scanResults) do
		if iface:isWireless() then
			local item = entry.item

			-- Mark current wireless network (if available)
			if entry.associated and entry.quality > 0 then
				item.style = "item_checked"
			else
				item.style = "item"
			end

			-- Update wireless signal quality
			item.arrow:setStyle("wirelessLevel" .. (entry.quality or 0))

-- fm+
			item.weight = 4 - (entry.quality or 0)
			item.text = ssid
-- fm-

			if self.scanMenu then
				self.scanMenu:updatedItem(item)
			end
		end
	end

-- fm+
	if self.scanMenu then
		self.scanMenu:setComparator(SimpleMenu.itemComparatorWeightAlpha)
	end
-- fm-


end

-- fm+
function _halfDuplexBugVerification(self, iface)
	log:info("_halfDuplexBugVerification")
	local nextStep = function()
		_connect(self, iface, iface:getName(), true, false)
	end

	if appletManager:callService("performHalfDuplexBugTest") then
		_halfDuplexBugTest(self, iface, nextStep)
		return
	else
		nextStep()
		return
	end
end
-- fm-

function _halfDuplexBugTest(self, iface, nextStep, useShowInstead)
	log:info("_halfDuplexBugTest:")
	local status = iface:t_wpaStatus()
	if not status.link or (status.link and status.fullduplex) then
		log:info("_halfDuplexBugTest: success. Link status: ", status.link)
		if nextStep then
			nextStep()
		end
		return
	end

	local window = Window("help_info", self:string("NETWORK_CONNECTION_PROBLEM"), "helptitle")
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu")

	menu:addItem({
		text = (self:string("NETWORK_TRY_AGAIN")),
		sound = "WINDOWSHOW",
		callback = function()
			log:info("_halfDuplexBugTest: try again")
			_halfDuplexBugTest(self, iface, nextStep, true)
		end,
		weight = 1
	})

	menu:addItem({
		text = (self:string("NETWORK_CONNECTION_TYPE_WIRELESS")),
		sound = "WINDOWSHOW",
		callback = function()
			_networkScan(self, self.wlanIface)
		end,
		weight = 2
	})

	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)


	local textarea = Textarea("help_text", self:string("NETWORK_HALF_SPEED_HUB"))
	window:addWidget(menu)
	menu:setHeaderWidget(textarea)

	if not useShowInstead then
		self:tieAndShowWindow(window)
	else
		window:showInstead()
	end

--	window:playSound("WINDOWSHOW")


end

-------- WIRELESS SSID AND PASSWORD --------

-- fm+
--[[
function _chooseEnterSSID(self, iface)
	local window = Window("help_list", self:string("NETWORK_DONT_SEE_YOUR_NETWORK"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textarea = Textarea("help_text", self:string("NETWORK_ENTER_SSID_HINT"))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_SEARCH_FOR_MY_NETWORK"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, false)
			end
		},
		{
			text = self:string("NETWORK_ENTER_SSID"),
			sound = "WINDOWSHOW",
			callback = function()
				_enterSSID(self, iface, ssid)
			end
		},
	})

	menu:setHeaderWidget(textarea)
	window:addWidget(menu)

	_helpAction(self, window, "NETWORK_LIST_HELP", "NETWORK_LIST_HELP_BODY", menu)

	self:tieAndShowWindow(window)
end
--]]
-- fm-

function _enterSSID(self, iface)
	assert(iface, debug.traceback())

	local window = Window("input", self:string("NETWORK_NETWORK_NAME"), 'setuptitle')
	window:setAllowScreensaver(false)

	local v = Textinput.textValue("", 1, 32)

	local textinput = Textinput("textinput", v,
				    function(widget, value)
				    	    value = tostring(value)

					    if #value == 0 then
						    return false
					    end

					    widget:playSound("WINDOWSHOW")

					    _enterPassword(self, iface, value)

					    return true
				    end
			    )

	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

        window:addWidget(group)
	window:addWidget(Keyboard("keyboard", 'qwerty', textinput))
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_NETWORK_NAME_HELP', 'NETWORK_NETWORK_NAME_HELP_BODY', menu)

	self:tieAndShowWindow(window)
end


-- This fuction is called with nocheck set to nil, "config" or "wps"
--
-- nocheck = nil:      User has selected an SSID from the list
-- nocheck = "config": Connection failed, user selected "Try again"
-- nocheck = "wps":    WPS capable AP, but user has chosen to enter passphrase manually
--
-- Possible reasons for a failed connection:
-- a) Connection failed (AP too far away, incorrect passhrase or key)
-- b) DHCP failed
--
-- Reason a) could also mean passphrase has been changed on the AP, i.e. we still
--  have a network configuration stored for that SSID from an earlier successful
--  connection, but now fail due to the changed passphrase.
-- If such an SSID is chosen from the list (and we enter with nocheck = nil) the
--  connection attempt will fail, but if "Try again" is then chosen (nocheck = "config")
--  which bypasses the automatic connection attempt for this already configured SSID
--  and the user can modify the passphrase.
-- We also need to bypass the automatic connection attempt for already configured
--  SSIDs for WPS APs which are using manual passphrases. (nocheck = "wps")

-- wireless network choosen, we need the password
function _enterPassword(self, iface, ssid, nocheck)
	assert(iface and ssid, debug.traceback())

	-- check if we know about this ssid
	if self.scanResults[ssid] == nil then
		return _chooseEncryption(self, iface, ssid)
	end

	-- is the ssid already configured
	if nocheck ~= "config" and nocheck ~= "wps" and self.scanResults[ssid].id ~= nil then
		return _connect(self, iface, ssid, false, false)
	end

	local flags = self.scanResults[ssid].flags
	log:debug("ssid is: ", ssid, " flags are: ", flags, " nocheck is: ", nocheck)

	if flags == "" then
		self.encryption = "none"
		return _connect(self, iface, ssid, true, false)

	-- A WPS capable AP with encryption set to none
	elseif flags == "[WPS]" then
		self.encryption = "none"
		return _connect(self, iface, ssid, true, false)

	elseif string.find(flags, "ETH") then
		self.encryption = "none"
		return _connect(self, iface, ssid, true, false)

-- fm+
-- Disable WPS until the UX team has figured out how the correct wording should be
--	-- FIXME: 08/31/09 Re-enable WPS for Controller at a later stage (after more testing is done)
--	elseif nocheck ~= "wps" and string.find(flags, "WPS") and System:getMachine() ~= "jive" then
--		self.encryption = "wpa2"
--		return _chooseWPS(self, iface, ssid)
-- fm-

	elseif string.find(flags, "WPA2%-PSK") then
		self.encryption = "wpa2"
		return _enterPSK(self, iface, ssid)

	elseif string.find(flags, "WPA%-PSK") then
		self.encryption = "wpa"
		return _enterPSK(self, iface, ssid)

	elseif string.find(flags, "WEP") then
-- fm+
--		return _chooseWEPLength(self, iface, ssid)
		self.encryption = "wep40_104"
		return _enterWEPKey(self, iface, ssid)
-- fm-

	elseif string.find(flags, "WPA%-EAP") or string.find(flags, "WPA2%-EAP") then
		return _enterEAP(self, iface, ssid)

	else
		return _chooseEncryption(self, iface, ssid)

	end
end


function _chooseEncryption(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("text_list", self:string("NETWORK_WIRELESS_ENCRYPTION"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_NO_ENCRYPTION"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "none"
				_connect(self, iface, ssid, true, false)
			end
		},
-- fm+
--		{
--			text = self:string("NETWORK_WEP_64"),
--			sound = "WINDOWSHOW",
--			callback = function()
--				self.encryption = "wep40"
--				_enterWEPKey(self, iface, ssid)
--			end
--		},
-- fm-

		{
			text = self:string("NETWORK_WEP_64_128"),
			sound = "WINDOWSHOW",
			callback = function()
-- fm+
--				self.encryption = "wep104"
				self.encryption = "wep40_104"
-- fm-
				_enterWEPKey(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WPA"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wpa"
				_enterPSK(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WPA2"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wpa2"
				_enterPSK(self, iface, ssid)
			end
		},
	})
	window:addWidget(menu)

	--_helpAction(self, window, "NETWORK_WIRELESS_ENCRYPTION", "NETWORK_WIRELESS_ENCRYPTION_HELP")
	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


function _chooseWEPLength(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("text_list", self:string("NETWORK_PASSWORD_TYPE"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_WEP_64"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wep40"
				_enterWEPKey(self, iface, ssid)
			end
		},
		{
			text = self:string("NETWORK_WEP_128"),
			sound = "WINDOWSHOW",
			callback = function()
				self.encryption = "wep104"
				_enterWEPKey(self, iface, ssid)
			end
		},
	})
	window:addWidget(menu)

	--_helpAction(self, window, "NETWORK_WIRELESS_ENCRYPTION", "NETWORK_WIRELESS_ENCRYPTION_HELP")
	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


function _enterWEPKey(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("input", self:string("NETWORK_WIRELESS_KEY"), 'setuptitle')
	window:setAllowScreensaver(false)

	local v

-- fm+
--	-- set the initial value
--	if self.encryption == "wep40" then
--		v = Textinput.hexValue("", 10, 10)
--	else
--		v = Textinput.hexValue("", 26, 26)
--	end

	-- allow for longer input
	self.encryption = "wep40_104"
	v = Textinput.hexValue("", 10, 26)
-- fm-

	local textinput = Textinput("textinput", v,
				    function(widget, value)
					    self.key = value:getValue()

					    widget:playSound("WINDOWSHOW")

					    _connect(self, iface, ssid, true, false)
					    return true
				    end
			    )

	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard('keyboard', 'hex', textinput)

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_WIRELESS_PASSWORD_HELP', 'NETWORK_WIRELESS_PASSWORD_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterPSK(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("input", self:string("NETWORK_WIRELESS_PASSWORD"), 'setuptitle')
	window:setAllowScreensaver(false)

	local v = Textinput.textValue(self.psk, 8, 63)
	local textinput = Textinput("textinput", v,
				    function(widget, value)
					    self.psk = tostring(value)

					    widget:playSound("WINDOWSHOW")

					    _connect(self, iface, ssid, true, false)
					    return true
				    end,
				    self:string("ALLOWEDCHARS_WPA")
			    )
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

        window:addWidget(group)
	window:addWidget(Keyboard('keyboard', 'qwerty', textinput))
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_WIRELESS_PASSWORD_HELP', 'NETWORK_WIRELESS_PASSWORD_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterEAP(self, iface, ssid)
	local window = Window("error", self:string('NETWORK_ERROR'), 'setuptitle')
	window:setAllowScreensaver(false)


	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_UNSUPPORTED_OTHER_NETWORK"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, true)
			end
		},
	})
	window:addWidget(menu)
	menu:setHeaderWidget(Textarea("help_text", self:string("NETWORK_UNSUPPORTED_TYPES_HELP")))
	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)		
end


-------- WIRELESS PROTECTED SETUP --------


function _chooseWPS(self, iface, ssid)
	log:debug('chooseWPS')

	-- ask the user to choose
	local window = Window("text_list", self:string("NETWORK_WPS_METHOD"), 'setuptitle')
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu")

	menu:addItem({
		text = (self:string("NETWORK_WPS_METHOD_PBC")),
		sound = "WINDOWSHOW",
		callback = function()
			_chooseWPSPbc(self, iface, ssid)
		end,
	})

--[[
	-- Bug: 12229 - disable WPS pin method
	-- WPS pin method is more secure than PBC method, but it is also very confusing
	--  as the pin needs to be entered into the router (and not into our device).
	-- WPS pin method is only mandatory if we want WiFi (WPS) logo certification
	menu:addItem({
		text = (self:string("NETWORK_WPS_METHOD_PIN")),
		sound = "WINDOWSHOW",
		callback = function()
			_chooseWPSPin(self, iface, ssid)
		end,
	})
--]]

	menu:addItem({
		text = (self:string("NETWORK_WPS_METHOD_PSK")),
		sound = "WINDOWSHOW",
		callback = function()
			-- Calling regular enter password function (which determinds the
			--  encryption) but do not check flags for WPS anymore to prevent
			--  ending up in this function again
			_enterPassword(self, iface, ssid, "wps")
		end,
	})

	window:addWidget(menu)

	_helpAction(self, window, "NETWORK_WPS_HELP", "NETWORK_WPS_HELP_BODY", menu)

	self:tieAndShowWindow(window)
end


--[[
	-- Bug: 12229 - disable WPS pin method
	-- WPS pin method is more secure than PBC method, but it is also very confusing
	--  as the pin needs to be entered into the router (and not into our device).
	-- WPS pin method is only mandatory if we want WiFi (WPS) logo certification

function _chooseWPSPin(self, iface, ssid)
	local wpspin = iface:generateWPSPin()

	local window = Window("help_list", self:string('NETWORK_ENTER_PIN'), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)


	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_START_TIMER"),
			sound = "WINDOWSHOW",
			callback = function()
				_processWPS(self, iface, ssid, "pin", wpspin)
			end
		},
	})
	menu:setHeaderWidget(Textarea("help_text", self:string("NETWORK_ENTER_PIN_HINT", tostring(wpspin))))
	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)		
end
--]]


function _chooseWPSPbc(self, iface, ssid)
	local window = Window("help_list", self:string('NETWORK_ENTER_PBC'), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)


	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_START_TIMER"),
			sound = "WINDOWSHOW",
			callback = function()
				_processWPS(self, iface, ssid, "pbc")
			end
		},
	})
	menu:setHeaderWidget(Textarea("help_text", self:string("NETWORK_ENTER_PBC_HINT")))
	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)		
end


function _processWPS(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid and wpsmethod, debug.traceback())

	self.processWPSTimeout = 0

	-- Get rid of wpa_cli while doing WPS
	-- It gets restarted when the new network is selected
	iface:stopWpaCli()

	if iface:isMarvell() then
		-- Stop wpa_supplicant - cannot run while wpsapp is running
		iface:stopWPASupplicant()
		-- Remove wps.conf, (re-)start wpsapp
		iface:startWPSApp(wpsmethod, wpspin)
	end

	if iface:isAtheros() then
		_startWPS(self, iface, ssid, wpsmethod, wpspin)
	end

	-- Progress window
	local popup = Popup("waiting_popup")
	popup:setAllowScreensaver(false)

	popup:addWidget(Icon("icon_connecting"))
	if wpsmethod == "pbc" then
		popup:addWidget(Label("text", self:string("NETWORK_WPS_PROGRESS_PBC")))
	else
		popup:addWidget(Label("text", self:string("NETWORK_WPS_PROGRESS_PIN", tostring(wpspin))))
	end

	local status = Label("subtext", self:string("NETWORK_WPS_REMAINING_WALK_TIME", tostring(WPS_WALK_TIMEOUT)))
	popup:addWidget(status)

	popup:addTimer(1000, function()
			_timerWPS(self, iface, ssid, wpsmethod, wpspin)

			local remaining_walk_time = WPS_WALK_TIMEOUT - self.processWPSTimeout
			status:setValue(self:string("NETWORK_WPS_REMAINING_WALK_TIME", tostring(remaining_walk_time)))
		end,
		false	-- repeat
	)

	local _stopWPSAction = function(self, event)
		if iface:isMarvell() then
			iface:stopWPSApp()
			iface:startWPASupplicant()
		end
		iface:restartWpaCli()
		popup:hide()
	end

	popup:addActionListener("back", self, _stopWPSAction)
	popup:addActionListener("soft_reset", self, _stopWPSAction)
	popup:ignoreAllInputExcept({"back"})

	self:tieAndShowWindow(popup)
	return popup
end


-- Only for Atheros wlan chipset
function _startWPS(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid, debug.traceback())

	Task("startWPS", self,
		function()
			iface:request("DISCONNECT")

			if( wpsmethod == "pbc") then
				iface:request("WPS_PBC")
			elseif( wpsmethod == "pin") then
				-- 'any' need to be lowercase
				iface:request("WPS_PIN any " .. wpspin)
			end
		end):addTask()
end


function _timerWPS(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid, debug.traceback())

	Task("networkWPS", self,
		function()
			log:debug("processWPSTimeout=", self.processWPSTimeout)

			if iface:isMarvell() then
				local status = iface:t_wpsStatus()
				if not (status.wps_state == "COMPLETED") then
					self.processWPSTimeout = self.processWPSTimeout + 1
					if self.processWPSTimeout ~= WPS_WALK_TIMEOUT then
						return
					end

					-- WPS walk timeout
					processWPSFailed(self, iface, ssid, wpsmethod, wpspin)
					return
				else
					-- Make sure wpa supplicant is running again
					iface:startWPASupplicant()

					-- Set credentials from WPS
					self.encryption = status.wps_encryption
					self.psk = status.wps_psk
					self.key = status.wps_key

					_connect(self, iface, ssid, true, false)
				end
			end

			if iface:isAtheros() then
				local status = iface:t_wpaStatus()
				if not (status.wpa_state == "COMPLETED") then
					self.processWPSTimeout = self.processWPSTimeout + 1

					if self.processWPSTimeout ~= WPS_WALK_TIMEOUT then
						return
					end

					-- WPS walk timeout
					processWPSFailed(self, iface, ssid, wpsmethod, wpspin)
					return
				else
					_connect(self, iface, ssid, false, true)
				end
			end

		end):addTask()
end


function processWPSFailed(self, iface, ssid, wpsmethod, wpspin)
	assert(iface and ssid, debug.traceback())

	log:debug("processWPSFailed")

	if iface:isMarvell() then
-- TODO: Remove later (should not be necessary)
		iface:stopWPSApp()

		iface:startWPASupplicant()
	end

	iface:restartWpaCli()

	-- popup failure
	local window = Window("error", self:string("NETWORK_WPS_PROBLEM"), 'setuptitle')
	window:setAllowScreensaver(false)


	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_TRY_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				window:hide()
				_processWPS(self, iface, ssid, wpsmethod, wpspin)
			end
		},
		{
			text = self:string("NETWORK_WPS_DIFFERENT_METHOD"),
			sound = "WINDOWHIDE",
			callback = function()
				window:hide()
				Framework.windowStack[1]:hide()
			end
		},
	})

	menu:setHeaderWidget(Textarea("help_text", self:string("NETWORK_WPS_PROBLEM_HINT")))
	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


-------- CONNECT TO NETWORK --------


-- start to connect
function _connect(self, iface, ssid, createNetwork, useSupplicantWPS)
	assert(iface and ssid, debug.traceback())

	if not iface:isWireless() then
		-- Bug 11769: We should decide whether we want _connect() always being called in a task or not.
		-- It's not called in a task at least for ehternet / DHCP failed / Try again, but t_wpaStatus()
		--  needs to be called in a task.
		Task("attachEthernet", self,
			function()
				local status = iface:t_wpaStatus()
				if not status.link then
					return _attachEthernet(self, iface, ssid, createNetwork)
				end

				_connect_1(self, iface, ssid, createNetwork, useSupplicantWPS)

			end
		):addTask()
	else
		_connect_1(self, iface, ssid, createNetwork, useSupplicantWPS)
	end
end

function _connect_1(self, iface, ssid, createNetwork, useSupplicantWPS)

	-- Avoid race condition when switching from one network to another (seen on Jive)
	-- Successful connection was reportet, but to the previous network not to the current
	-- Now we wait until disconnection from the previous network has happened
	self.disconnectedFromPreviousNetwork = false

	self.connectTimeout = 0
	self.dhcpTimeout = 0

	-- progress window
	local popup = Popup("waiting_popup")

	local icon  = Icon("icon_connecting")
	icon:addTimer(1000,
		function()
			_connectTimer(self, iface, ssid, createNetwork)
		end,
		false	-- repeat
	)
	popup:addWidget(icon)
	popup:ignoreAllInputExcept()

	-- XXXX popup text, including dhcp detection text

	-- ensure the network state exists
	if self.scanResults[ssid] == nil then
		_addNetwork(self, iface, ssid)
	end

	local name = ssid
	if self.scanResults[ssid] then
		name = self.scanResults[ssid].item.text
	end
	popup:addWidget(Label("text", self:string("NETWORK_CONNECTING_TO_SSID")))
	popup:addWidget(Label("subtext", name))

	self:tieAndShowWindow(popup)

	-- Select/create the network in a background task
	Task("networkSelect", self, _selectNetworkTask):addTask(iface, ssid, createNetwork, useSupplicantWPS)
end


-- task to modify network configuration
function _selectNetworkTask(self, iface, ssid, createNetwork, useSupplicantWPS)
	assert(iface and ssid, debug.traceback())

	-- disconnect from existing network
	iface:t_disconnectNetwork()

	-- Avoid race condition when switching from one network to another (seen on Jive)
	-- Successful connection was reportet, but to the previous network not to the current
	-- Now we wait until disconnection from the previous network has happened
	self.disconnectedFromPreviousNetwork = true

  if useSupplicantWPS then

	iface:t_addWPSNetwork(ssid)

  else

	-- remove any existing network config
	if createNetwork then
		_removeNetworkTask(self, iface, ssid)
	end

	-- ensure the network state exists
	if self.scanResults[ssid] == nil then
		_addNetwork(self, iface, ssid)
	end

	local id = self.scanResults[ssid].id

	-- create the network config (if necessary)
	if id == nil then
		local option = {
			encryption = self.encryption,
			psk = self.psk,
			key = self.key
		}

		local id = iface:t_addNetwork(ssid, option)

		self.createdNetwork = true
		if self.scanResults[ssid] then
			self.scanResults[ssid].id = id
		end
	end
  end

	-- select new network
	iface:t_selectNetwork(ssid)
end


-- remove the network configuration
function _removeNetworkTask(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	iface:t_removeNetwork(ssid)

	if self.scanResults[ssid] then
		-- remove from menu
		local item = self.scanResults[ssid].item
		if self.scanMenu then
			self.scanMenu:removeItem(item)
		end

		-- clear entry
		self.scanResults[ssid] = nil
	end
end


-- warning if ethernet cable is not connected
function _attachEthernet(self, iface, ssid, createNetwork)
	local window = Window("help_list", self:string("NETWORK_ATTACH_CABLE"))
        window:setAllowScreensaver(false)

	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")
	local textarea = Textarea('help_text', self:string("NETWORK_ATTACH_CABLE_DETAILED"))
	window:addWidget(menu)
	menu:setHeaderWidget(textarea)

	window:addTimer(500,
		function(event)
			log:debug("Checking Link")
			Task("ethernetConnect", self,
				function()
					local status = iface:t_wpaStatus()
					log:debug("link=", status.link)
					if status.link then
						log:debug("connected")
						window:hide()
						_connect(self, iface, ssid, createNetwork, false)
					end
             			end
			):addTask()
		end,
		false	-- repeat
	)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


-- timer to check connection state
function _connectTimer(self, iface, ssid, createNetwork)
	assert(iface and ssid, debug.traceback())

	local completed = false

	Task("networkConnect", self, function()
		log:debug("connectTimeout=", self.connectTimeout, " dhcpTimeout=", self.dhcpTimeout)

		-- Avoid race condition when switching from one network to another (seen on Jive)
		-- Successful connection was reportet, but to the previous network not to the current
		-- Now we wait until disconnection from the previous network has happened
		if not self.disconnectedFromPreviousNetwork then
			-- Still connected to previous network
			self.connectTimeout = self.connectTimeout + 1
			if self.connectTimeout <= CONNECT_TIMEOUT then
				return
			end

			-- connection timed out
			return _connectFailed(self, iface, ssid, "timeout")
		end

		local status = iface:t_wpaStatus()

		log:debug("wpa_state=", status.wpa_state)
		log:debug("ip_address=", status.ip_address)

		if status.wpa_state == "COMPLETED" then
			completed = true
		end

		-- Wireless: connected to network and we've got a non self assigned ip address -> we're done
		-- Wired: connected (i.e. link) and we've got a non self assigned ip address -> we're done
		if completed and status.ip_address and not string.match(status.ip_address, "^169.254.") then
			-- dhcp completed
			_connectSuccess(self, iface, ssid)
			return
		end

		-- Not yet there

		if not completed then
			-- Not yet connected -> countdown connection timeout
			self.connectTimeout = self.connectTimeout + 1
			if self.connectTimeout <= CONNECT_TIMEOUT then
				return
			end
		else
			-- Connected, but no DHCP yet -> countdown dhcp timeout
			self.dhcpTimeout = self.dhcpTimeout + 1
			if self.dhcpTimeout <= CONNECT_TIMEOUT then
				return
			end
		end

		-- Either timeout has expired

		-- Wired: check if ethernet cable has been removed / fallen out in the mean time
		if not (iface:isWireless() or status.link) then
			return _attachEthernet(self, iface, ssid, createNetwork)
		end

		-- Wireless: we've been connected to the network, but didn't get an ip address -> allow for static
		if completed then
			-- dhcp timed out
			_failedDHCP(self, iface, ssid)
			return
		end

		-- Wireless: not even connected to the network -> connection timed out
		_connectFailed(self, iface, ssid, "timeout")

	end):addTask()
end


function _connectFailedTask(self, iface, ssid)
	-- Stop trying to connect to the network
	iface:t_disconnectNetwork()

	if self.createdNetwork then
		-- Remove failed network
		_removeNetworkTask(self, iface, ssid)
		self.createdNetwork = nil
	end
end


function _connectSuccess(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	if ssid == nil then
		-- make sure we are still trying to connect
		return
	end

	log:debug("connection OK ", ssid)

	-- forget connection state
	self.encryption = nil
	self.psk = nil
	self.key = nil

	-- send notification we're on a new network
	jnt:notify("networkConnected")

	-- popup confirmation
	local popup = Popup("waiting_popup")
	popup:addWidget(Icon("icon_connected"))
	popup:ignoreAllInputExcept()

	local name = self.scanResults[ssid].item.text
	local text = Label("text", self:string("NETWORK_CONNECTED_TO"))
	local subtext = Label("subtext_connected", name)
	popup:addWidget(text)
	popup:addWidget(subtext)

	popup:addTimer(2000,
			function(event)
				self.setupNext()
			end,
			true	-- once
	)

	popup:addListener(EVENT_KEY_PRESS | EVENT_MOUSE_PRESS, --todo IR should work too, but not so simple - really window:hideOnAllButtonInput should allow for a callback on hide for "next" type situations such as this
			   function(event)
				self.setupNext()
				return EVENT_CONSUME
			   end)

	self:tieAndShowWindow(popup)
end


function _connectFailed(self, iface, ssid, reason)
	assert(iface and ssid, debug.traceback())

	log:debug("connection failed")

	-- Stop trying to connect to the network, if this network is
	-- being added this will also remove the network configuration
	Task("networkFailed", self, _connectFailedTask):addTask(iface, ssid)

	-- Message based on failure type
	local password = ""
	if self.encryption then
		if self.key and string.match(self.encryption, "^wep.*") then
			password = self.key
		elseif self.psk and string.match(self.encryption, "^wpa*") then
			password = self.psk
		end
	end

	local helpText = self:string("NETWORK_CONNECTION_PROBLEM_HELP", password)

	-- popup failure
	local window = Window("error", self:string('NETWORK_CANT_CONNECT'), 'setuptitle')
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_TRY_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				_networkScanAgain(self, iface, true)
				_enterPassword(self, iface, ssid, "config")
			end
		},
		{
			text = self:string("NETWORK_TRY_DIFFERENT"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, true)
			end
		},
	})


	if password and password ~= "" then
		menu:setHeaderWidget(Textarea("help_text", helpText))
	end

	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


function _failedDHCP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	log:debug("self.encryption=", self.encryption)

	if self.encryption and string.match(self.encryption, "^wep.*") then
		-- use different error screen for WEP, the failure may
		-- be due to a bad WEP passkey, not DHCP.
		return _failedDHCPandWEP(self, iface, ssid)
	else
		return _failedDHCPandWPA(self, iface, ssid)
	end
end


function _failedDHCPandWPA(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("error", self:string("NETWORK_DHCP_ERROR"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)
	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_DHCP_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				-- poke udhcpto try again
				_sigusr1("udhcpc")
				_connect(self, iface, ssid, false, false)
				window:hide(Window.transitionNone)
			end
		},
		{
			text = self:string("NETWORK_TRY_PASSWORD"),
			sound = "WINDOWHIDE",
			callback = function()
				_networkScanAgain(self, iface, true)
				_enterPassword(self, iface, ssid, "config")
			end
		},		
		{
			text = self:string("STATIC_ADDRESS"),
			sound = "WINDOWSHOW",
			callback = function()
				_enterIPHelp(self, iface, ssid)
			end
		},
		{
			text = self:string("ZEROCONF_ADDRESS"),
			sound = "WINDOWSHOW",
			callback = function()
				-- already have a self assigned address, we're done
				_connectSuccess(self, iface, ssid)
			end
		},
	})

	menu:setHeaderWidget(Textarea("help_text", self:string("NETWORK_DHCP_ERROR_HINT")))
	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


function _failedDHCPandWEP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("error", self:string("NETWORK_ERROR"), 'setuptitle')
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu", {
		{
			text = self:string("NETWORK_TRY_AGAIN"),
			sound = "WINDOWHIDE",
			callback = function()
				-- poke udhcpto try again
				_sigusr1("udhcpc")
				_connect(self, iface, ssid, false, false)
				window:hide(Window.transitionNone)
			end
		},
		{
			text = self:string("NETWORK_TRY_PASSWORD"),
			sound = "WINDOWHIDE",
			callback = function()
				_networkScanAgain(self, iface, true)
				_enterPassword(self, iface, ssid, "config")
			end
		},
		{
			text = self:string("NETWORK_TRY_DIFFERENT"),
			sound = "WINDOWSHOW",
			callback = function()
				_networkScanAgain(self, iface, true)
			end
		},
		{
			text = self:string("NETWORK_WEP_DHCP"),
			sound = "WINDOWHIDE",
			callback = function()
				_failedDHCPandWPA(self, iface, ssid)
			end
		},
	})

	menu:setHeaderWidget(Textarea("help_text", self:string("NETWORK_ADDRESS_HELP_WEP", tostring(self.key))))
	window:addWidget(menu)

	_helpAction(self, window, nil, nil, menu)

	self:tieAndShowWindow(window)
end


-------- STATIC-IP --------


function _parseip(str)
	local ip = 0
	for w in string.gmatch(str, "%d+") do
		ip = ip << 8
		ip = ip | tonumber(w)
	end
	return ip
end


function _ipstring(ip)
	local str = {}
	for i = 4,1,-1 do
		str[i] = string.format("%d", ip & 0xFF)
		ip = ip >> 8
	end
	str = table.concat(str, ".")
	return str
end


function _validip(str)
	local ip = _parseip(str)
	if ip == 0x00000000 or ip == 0xFFFFFFFF then
		return false
	else
		return true
	end
end


function _subnet(self)
	local ip = _parseip(self.ipAddress or "0.0.0.0")

	if ((ip & 0xC0000000) == 0xC0000000) then
		return "255.255.255.0"
	elseif ((ip & 0x80000000) == 0x80000000) then
		return "255.255.0.0"
	elseif ((ip & 0x80000000) == 0) then
		return "255.0.0.0"
	else
		return "0.0.0.0";
	end
end


function _gateway(self)
	local ip = _parseip(self.ipAddress or "0.0.0.0")
	local subnet = _parseip(self.ipSubnet or "255.255.255.0")

	return _ipstring(ip & subnet | 1)
end


function _sigusr1(process)
	local pid

	local pattern = "%s*(%d+).*" .. process

	local cmd = io.popen("/bin/ps")
	for line in cmd:lines() do
		pid = string.match(line, pattern)
		if pid then break end
	end
	cmd:close()

	if pid then
		log:debug("kill -usr1 ", pid)
		os.execute("kill -usr1 " .. pid)
	else
		log:error("cannot sigusr1 ", process)
	end
end

function _enterIPHelp(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local window = Window("help_list", self:string("NETWORK_IP_ADDRESS_HELP"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textarea = Textarea("help_text", self:string("NETWORK_IP_ADDRESS_HELP_BODY"))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("SETUP_NETWORKING_CONTINUE"),
			sound = "WINDOWSHOW",
			callback = function()
				_enterIP(self, iface, ssid)
			end
		},
	})

	menu:setHeaderWidget(textarea)
	window:addWidget(menu)

	self:tieAndShowWindow(window)

end

function _enterIP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipAddress)

	local window = Window("input", self:string("NETWORK_IP_ADDRESS"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()
					   if not _validip(value) then
						   return false
					   end

					   self.ipAddress = value
					   self.ipSubnet = _subnet(self)

					   widget:playSound("WINDOWSHOW")
					   _enterSubnet(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "ip", textinput)

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterSubnet(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipSubnet)

	local window = Window("input", self:string("NETWORK_SUBNET"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   self.ipSubnet = value
					   self.ipGateway = _gateway(self)

					   widget:playSound("WINDOWSHOW")
					   _enterGateway(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "ip", textinput)

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterGateway(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipGateway)

	local window = Window("input", self:string("NETWORK_GATEWAY"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   if not _validip(value) then
						   return false
					   end

					   self.ipGateway = value
					   self.ipDNS = self.ipGateway

					   widget:playSound("WINDOWSHOW")
					   _enterDNS(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "ip", textinput)

        window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _enterDNS(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	local v = Textinput.ipAddressValue(self.ipDNS)

	local window = Window("input", self:string("NETWORK_DNS"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   if not _validip(value) then
						   return false
					   end

					   self.ipDNS = value

					   widget:playSound("WINDOWSHOW")
					   _setStaticIP(self, iface, ssid)
					   return true
				   end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )
	local keyboard = Keyboard("keyboard", "ip", textinput)

	window:addWidget(group)
	window:addWidget(keyboard)
        window:focusWidget(group)

	_helpAction(self, window, 'NETWORK_IP_ADDRESS_HELP', 'NETWORK_IP_ADDRESS_HELP_BODY')

	self:tieAndShowWindow(window)
end


function _setStaticIP(self, iface, ssid)
	assert(iface and ssid, debug.traceback())

	log:debug("setStaticIP addr=", self.ipAddress, " subnet=", self.ipSubnet, " gw=", self.ipGateway, " dns=", self.ipDNS)

	local popup = Popup("waiting_popup")
	popup:addWidget(Icon("icon_connecting"))
	popup:ignoreAllInputExcept()

	local name = self.scanResults[ssid].item.text
	popup:addWidget(Label("text", self:string("NETWORK_CONNECTING_TO_SSID")))
	popup:addWidget(Label("subtext", name))

	self:tieAndShowWindow(popup)

	Task("networkStatic", self, function()
		iface:t_disconnectNetwork()

		iface:t_setStaticIP(ssid, self.ipAddress, self.ipSubnet, self.ipGateway, self.ipDNS)
		_connectSuccess(self, iface, ssid)
	end):addTask()
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
