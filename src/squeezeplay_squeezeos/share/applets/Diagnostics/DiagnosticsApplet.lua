
local ipairs, tostring, tonumber = ipairs, tostring, tonumber

-- NETWORK HEALTH STUFF
local type, pairs, setmetatable = type, pairs, setmetatable

-- stuff we use
local oo               = require("loop.simple")
local io               = require("io")
local math             = require("math")
local string           = require("string")
local table            = require("jive.utils.table")

local Applet           = require("jive.Applet")
local System           = require("jive.System")
local DNS              = require("jive.net.DNS")
local Networking       = require("jive.net.Networking")
local Process          = require("jive.net.Process")
local SocketTcp        = require("jive.net.SocketTcp")
local SlimServer       = require("jive.slim.SlimServer")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")

-- NETWORK HEALTH STUFF
local Popup                  = require("jive.ui.Popup")
local Icon                   = require("jive.ui.Icon")
local Tile                   = require("jive.ui.Tile")
local jive = jive

local jnt = jnt
local appletManager    = appletManager
local JIVE_VERSION  = jive.JIVE_VERSION


module(..., Framework.constants)
oo.class(_M, Applet)

function init(self)
	self.generalTests = {
	      "FIRMWARE_VERSION",
	      "HARDWARE_VERSION",
	      "MAC_ADDRESS",
	      "CURRENT_PLAYER",
	      "PLAYER_TYPE",
	      "UPTIME",
	      "MEMORY",
	}

	self.wirelessTests = {
	      "WLAN_SSID",
	      "WLAN_ENCRYPTION",
	      "WLAN_STRENGTH",
	      -- (for testing): "WLAN_SNR",
	      "IP_ADDRESS",
	      "SUBNET_MASK",
	      "GATEWAY",
	      "DNS_SERVER",
	}

	self.ethernetTests = {
	      "ETH_CONNECTION",
	      "IP_ADDRESS",
	      "SUBNET_MASK",
	      "GATEWAY",
	      "DNS_SERVER",
	}

	self.serverTests = {
	      "SC_ADDRESS",
	      "SC_NAME",
	      "SC_PING",
	      "SC_PORT_3483",
	      "SC_PORT_9000",
	}

	self.powerTests = {
	      "MSP_VERSION",
	      "POWER_MODE",
	      "WALL_VOLTAGE",
	      "CHARGE_STATE",
	      "BATTERY_TEMPERATURE",
	      "BATTERY_VOLTAGE",
	      "BATTERY_VMON1",
	      "BATTERY_VMON2",
	}

	self.powerMode = {
		  ["3"] = "POWER_ON_AC",
		  ["7"] = "POWER_ON_AC_AND_BATT",
		  ["5"] = "POWER_ON_BATT",
	}

	self.chargerState = {
		  ["1"]  = "BATT_NONE",
		  ["2"]  = "BATT_IDLE",
		  ["3"]  = "BATT_DISCHARGING",
		  ["35"] = "BATT_DISCHARGING_WARNING",
		  ["8"]  = "BATT_CHARGING",
		  ["24"] = "BATT_CHARGING_PAUSED",
	}

	self.netResultToText = {
		[1] = {		text="NET_INTERFACE",		},
		[-1] = {	text="NET_INTERFACE_NOK",	},
		[3] = {		text="NET_LINK",		},
		[5] = {		text="NET_LINK_WIRELESS_OK",	},
		[-5] = {	text="NET_LINK_WIRELESS_NOK",	help="NET_LINK_WIRELESS_NOK_HELP"},
		[6] = {		text="NET_LINK_ETHERNET_OK",	},
		[-6] = {	text="NET_LINK_ETHERNET_NOK",	help="NET_LINK_ETHERNET_NOK_HELP"},
		[8] = {		text="NET_IP_OK",		},
		[-8] = {	text="NET_IP_NOK",		help="NET_IP_NOK_HELP"},
		[10] = {	text="NET_GATEWAY_OK",		},
		[-10] = {	text="NET_GATEWAY_NOK",		help="NET_GATEWAY_NOK_HELP"},
		[12] = {	text="NET_DNS_OK",		},
		[-12] = {	text="NET_DNS_NOK",		help="NET_DNS_NOK_HELP"},
		[20] = {	text="NET_ARPING",		},
		[21] = {	text="NET_ARPING_OK",		},
		[-21] = {	text="NET_ARPING_NOK",		help="NET_ARPING_NOK_HELP"},
		[-23] = {	text="NET_SERVER_NOK",		},
		[25] = {	text="NET_RESOLVE",		},
		[27] = {	text="NET_RESOLVE_OK",		},
		[-27] = {	text="NET_RESOLVE_NOK",		help="NET_RESOLVE_NOK_HELP"},
		[29] = {	text="NET_PING",		},
		[31] = {	text="NET_PING_OK",		},
		[-31] = {	text="NET_PING_NOK",		help="NET_PING_NOK_HELP"},
		[33] = {	text="NET_PORT",		},
		[35] = {	text="NET_PORT_OK",		},
		[-35] = {	text="NET_PORT_NOK",		help="NET_PORT_NOK_HELP"},
		[37] = {	text="NET_PORT_OK",		},
		[-37] = {	text="NET_PORT_NOK",		help="NET_PORT_NOK_HELP"},
		[100] = {	text="NET_BRINGING_NETWORK_DOWN",	},
		[102] = {	text="NET_BRINGING_NETWORK_UP",		},
		[104] = {	text="NET_REPAIR_NETWORK_DONE",		},
	}

end



function setValue(self, key, value, customLabel)
	if not value then
		value = '-'
	end

	-- if we have customLabelArgs, we want to insert those first to the string args
	if customLabel then
		self.menu:setText(self.labels[key], self:string(key, tostring(customLabel), value))
	else
		self.menu:setText(self.labels[key], self:string(key, value))
	end
end


function serverPort(self, server, port, key, customLabel)

	if not server then
		self:setValue(key, self.notConnected)
		return
	end

	local portOk = tostring(self:string('PORT_OK'))
	local portFail = tostring(self:string('PORT_FAIL'))
	Task("ports", self, function()
		local serverip = server:getIpPort()

		local ip, err
		if DNS:isip(serverip) then
			ip = serverip
		else
			ip, err = DNS:toip(serverip)
		end

		if ip == nil then
			self:setValue(key, portFail, customLabel)
			return
		end

		local tcp = SocketTcp(jnt, ip, port, "porttest")

		tcp:t_connect()
		tcp:t_addWrite(function(err)
			local res, err = tcp.t_sock:send(" ")

			if err then
				self:setValue(key, portFail, customLabel)
			else
				self:setValue(key, portOk, customLabel)
			end

			tcp:close()
		end)
	end):addTask()
end


function serverPing(self, server, dnsKey, pingKey)
	local serverip = server and server:getIpPort()

	local dnsFail            = tostring(self:string('DNS_FAIL'))
	local pingFailString     = tostring(self:string('PING_FAIL'))
	local pingOkString       = tostring(self:string('PING_OK'))

	if not serverip then
		self:setValue(dnsKey, self.notConnected)
		self:setValue(pingKey, self.notConnected)
		return
	end

	Task("ping", self, function()
		local ipaddr

		-- DNS lookup
		if DNS:isip(serverip) then
			ipaddr = serverip
		else
			ipaddr = DNS:toip(serverip)
		end

		if not ipaddr then
			self:setValue(dnsKey, dnsFail)
			self:setValue(pingKey, pingFailString)
			return
		end

		self:setValue(dnsKey, ipaddr)

		-- Ping
		local pingOK = false
		local ping = Process(jnt, "ping -c 1 " .. ipaddr)
		ping:read(function(chunk)
			if chunk then
				if string.match(chunk, "bytes from") then
					pingOK = true
				end
			else
				if pingOK then
					self:setValue(pingKey, pingOkString)
				else
					self:setValue(pingKey, pingFailString)
				end
			end
		end)
	end):addTask()
end


function wlanStatus(self, iface)
	if not iface then
		-- flag up hardware/firmware failure
		return "no_interface"
	end

	Task("Netstatus", self, function()
		local status = iface:t_wpaStatus()
		-- (for testing): local snr, minsnr, maxsnr = iface:getSNR()
		local signalStrength = iface:getSignalStrength()

		if status.ssid then
			local encryption = status.key_mgmt
			-- white lie :)
			if string.match(status.pairwise_cipher, "WEP") then
				encryption = "WEP"
			end

			self:setValue("WLAN_SSID", status.ssid)
			self:setValue("WLAN_ENCRYPTION", encryption)
			self:setValue("WLAN_STRENGTH", signalStrength .. "%")
			-- (for testing): self:setValue("WLAN_SNR", minsnr .. "/" .. snr .. "/" .. maxsnr)

			if status.ip_address then
				self:setValue("IP_ADDRESS", tostring(status.ip_address))
				self:setValue("SUBNET_MASK", tostring(status.ip_subnet))
				self:setValue("GATEWAY", tostring(status.ip_gateway))
				self:setValue("DNS_SERVER", tostring(status.ip_dns))
			end
		else
			self:setValue('WLAN_SSID', self.notConnected)
			self:setValue("WLAN_ENCRYPTION", nil)
			self:setValue("WLAN_STRENGTH", nil)
		end
	end):addTask()
end


function ethStatus(self, iface)
	if not iface then
		-- flag up hardware/firmware failure
		return "no_interface"
	end

	Task("Netstatus", self, function()
		local status = iface:t_wpaStatus()

		if status.link then
			if status.fullduplex then
				self:setValue("ETH_CONNECTION", tostring(self:string("ETH_FULL_DUPLEX", status.speed)))
			else
				self:setValue("ETH_CONNECTION", tostring(self:string("ETH_HALF_DUPLEX", status.speed)))
			end

			if status.ip_address then
				self:setValue("IP_ADDRESS", tostring(status.ip_address))
				self:setValue("SUBNET_MASK", tostring(status.ip_subnet))
				self:setValue("GATEWAY", tostring(status.ip_gateway))
				self:setValue("DNS_SERVER", tostring(status.ip_dns))
			end
		else
			self:setValue("ETH_CONNECTION", self.notConnected)
		end
	end):addTask()
end


function systemStatus(self)
	local uptime = ""
	local memory = ""
	
	local f = io.open("/proc/uptime")
	if f then
		local time = f:read("*all")
		f:close()
	
		time = string.match(time, "(%d+)")
	
		uptime = {}
		uptime.days = math.floor(time / 86400)
		time = math.fmod(time, 86400)
		uptime.hours = math.floor(time / 3600)
		time = math.fmod(time, 3600)
		uptime.minutes = math.floor(time / 60)
	
		local ut = {}
		if uptime.days > 0 then
		 	ut[#ut + 1] = tostring(self:string("UPTIME_DAYS", uptime.days))
		end
		if uptime.hours > 0 then
			ut[#ut + 1] = tostring(self:string("UPTIME_HOURS", uptime.hours))
		end
		ut[#ut + 1] = tostring(self:string("UPTIME_MINUTES", uptime.minutes))
		uptime = table.concat(ut, " ")
	end
	
	local f = io.open("/proc/meminfo")
	if f then
		local mem = {}
	
		while true do
			local line = f:read()
			if line == nil then
				break
			end
	
			local key, value = string.match(line, "(.+):%s+(%d+)")
		 	mem[key] = value
		end
		f:close()

		memory = math.ceil(((mem.MemTotal - (mem.MemFree + mem.Buffers + mem.Cached)) / mem.MemTotal) * 100) .. "%"
	end
	
	self:setValue("UPTIME", uptime)
	self:setValue("MEMORY", memory)
end


function _getSysValue(self, param)

	local f = io.open("/sys/bus/i2c/devices/1-0010/" .. param)

	local value = f:read("*all")
	f:close()

	return value
end


function _getPowerSysValue(self, param)

	local f = io.open("/sys/devices/platform/i2c-adapter:i2c-1/1-0010/" .. param)
	log:warn("opening: ", param)

	local value = f:read("*all")
	f:close()

	return value
end


-- DO VALUES

function doGeneralValues(self, menu)
	self.menu = menu

	local machine, revision = System:getMachine();

	self:setValue("FIRMWARE_VERSION", JIVE_VERSION)
	if revision then
		self:setValue("HARDWARE_VERSION", tostring(revision))
	end
	self:setValue("MAC_ADDRESS", System:getMacAddress())

	self:systemStatus()

	local currentPlayer = appletManager:callService("getCurrentPlayer")
	if currentPlayer then
		self:setValue("CURRENT_PLAYER", currentPlayer:getName())
		if currentPlayer:isLocal() then
			self:setValue("PLAYER_TYPE", tostring(self:string("DIAGNOSTICS_LOCAL")))
		else
			self:setValue("PLAYER_TYPE", tostring(self:string("DIAGNOSTICS_REMOTE")))
		end
	else
		self:setValue("CURRENT_PLAYER", tostring(self:string("DIAGNOSTICS_NONE")))
		self:setValue("PLAYER_TYPE", "")

	end
end


function doWirelessValues(self, menu)
	self.menu = menu

	local wlanIface = Networking:wirelessInterface(jnt)

	return self:wlanStatus(wlanIface) -- pass back result
end


function doEthernetValues(self, menu)
	self.menu = menu

	local ethIface = Networking:wiredInterface(jnt)

	if System:hasWiredNetworking() then
		return self:ethStatus(ethIface) -- pass back result
	end
end


function doServerValues(self, menu)
	self.menu = menu

	local sc = SlimServer:getCurrentServer()

	self:setValue("SC_NAME", sc:getName())
	self:serverPing(sc, "SC_ADDRESS", "SC_PING")
	self:serverPort(sc, 3483, "SC_PORT_3483")
	local ip, port = sc:getIpPort()
	self:serverPort(sc, port, "SC_PORT_9000", port)
end


function roundNumber(num, idp)
	return tonumber(string.format("%." .. (idp or 0) .. "f", num))
end


function doPowerValues(self, menu)
	self.menu = menu

	self:setValue("MSP_VERSION", self:_getSysValue("fw"))

	local mode = self:_getPowerSysValue("power_mode"):gsub("^%s*(.-)%s*$", "%1")
	self:setValue("POWER_MODE", tostring(self:string(self.powerMode[mode])))

	-- Battery only
	if mode == "5" then
		self:setValue("WALL_VOLTAGE", "-")
	-- AC (maybe Battery)
	else
		local wallVoltage = roundNumber(self:_getPowerSysValue("wall_voltage") / 1000.0, 1)
		self:setValue("WALL_VOLTAGE", tostring(wallVoltage .. " V"))
	end

	local mode = self:_getPowerSysValue("charger_state"):gsub("^%s*(.-)%s*$", "%1")
	self:setValue("CHARGE_STATE", tostring(self:string(self.chargerState[mode])))

	-- No battery installed
	if mode == "1" then
		self:setValue("BATTERY_TEMPERATURE", "-")
		self:setValue("BATTERY_VOLTAGE", "-")
		self:setValue("BATTERY_VMON1", "-")
		self:setValue("BATTERY_VMON2", "-")

	-- Battery installed
	else
		local batteryTemperature = roundNumber(self:_getPowerSysValue("battery_temperature") / 32.0, 1)
		local batteryVoltage = roundNumber(self:_getPowerSysValue("battery_voltage") / 1000.0, 1)
		local batteryMonitor1 = roundNumber(self:_getPowerSysValue("battery_vmon1_voltage") / 1000.0, 1)
		local batteryMonitor2 = roundNumber(self:_getPowerSysValue("battery_vmon2_voltage") / 1000.0, 1)

		self:setValue("BATTERY_TEMPERATURE", tostring(batteryTemperature) .. " C")
		self:setValue("BATTERY_VOLTAGE", tostring(batteryVoltage) .. " V")
		self:setValue("BATTERY_VMON1", tostring(batteryMonitor1) .. " V")
		self:setValue("BATTERY_VMON2", tostring(batteryMonitor2) .. " V")
	end
end


-- SUB MENUS

function showGeneralDiagnosticsMenu(self)
	local window = Window("text_list", self:string("MENU_GENERAL"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self.labels = {}

	for i,name in ipairs(self.generalTests) do
		self.labels[name] = {
			text = self:string(name, ''),
			style = 'item_info',
		}
		menu:addItem(self.labels[name])
	end

	doGeneralValues(self, menu)
	menu:addTimer(5000, function()
		doGeneralValues(self, menu)
	end)

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function showWirelessDiagnosticsMenu(self)
	local window = Window("text_list", self:string("MENU_WIRELESS"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self.labels = {}

	for i,name in ipairs(self.wirelessTests) do
		self.labels[name] = {
			text = self:string(name, ''),
			style = 'item_info',
		}
		menu:addItem(self.labels[name])
	end

	local res = doWirelessValues(self, menu)

	if res == "no_interface" then
		-- Probable hardware/firmware error.
		-- Show explanatory screen instead of list of 'empty' values
		-- 'help_text' gives a better display than 'text' or 'multiline_text'
		window:addWidget(Textarea('help_text', self:string("NO_INTERFACE_FOUND_WIFI")))
		self:tieAndShowWindow(window)
		return window
	end

	menu:addTimer(5000, function()
		doWirelessValues(self, menu)
	end)

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function showEthernetDiagnosticsMenu(self)
	local window = Window("text_list", self:string("MENU_ETHERNET"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self.labels = {}

	for i,name in ipairs(self.ethernetTests) do
		self.labels[name] = {
			text = self:string(name, ''),
			style = 'item_info',
		}
		menu:addItem(self.labels[name])
	end

	local res = doEthernetValues(self, menu)

	if res == "no_interface" then
		-- see 'showWirelessDiagnosticsMenu' above
		window:addWidget(Textarea('help_text', self:string("NO_INTERFACE_FOUND_ETH")))
		self:tieAndShowWindow(window)
		return window
	end

	menu:addTimer(5000, function()
		doEthernetValues(self, menu)
	end)

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function showServerDiagnosticsMenu(self)
	local window = Window("text_list", self:string("MENU_SERVER"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self.labels = {}

	for i,name in ipairs(self.serverTests) do
		local label
		if name == 'SC_PORT_9000' then
			label = self:string(name, '9000', '-')
		else
			label = self:string(name, '-')
		end
	
		self.labels[name] = {
			text = label,
			style = 'item_info',
		}
		menu:addItem(self.labels[name])
	end

	doServerValues(self, menu)
	menu:addTimer(5000, function()
		doServerValues(self, menu)
	end)

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function showPowerDiagnosticsMenu(self)
	local window = Window("text_list", self:string("POWER"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self.labels = {}

	for i,name in ipairs(self.powerTests) do
		self.labels[name] = {
			text = self:string(name, ''),
			style = 'item_info',
		}
		menu:addItem(self.labels[name])
	end

	doPowerValues(self, menu)
	menu:addTimer(5000, function()
		doPowerValues(self, menu)
	end)

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


-- Error Troubleshooting menu
function networkTroubleshootingMenu(self, iface)

	log:warn('networkTroubleshootingMenu: ', iface)
	if not iface then
		log:error('You must specify the interface object when calling this method')
		return false
	end

        local errorCode = iface:getNetworkResult()
	if type(errorCode) == 'number' and errorCode >= 0 then
		log:warn('A positive number means there is no error. Do not push a diags window in this condition.')
		return false
	elseif type(errorCode) == 'number' then
		log:warn('Error code is listed as: ', errorCode)
	else
		log:error('There is no network problem registered on this interface')
		return
	end

	local titleToken    = self.netResultToText[errorCode] and self.netResultToText[errorCode].text or "NETWORK_PROBLEM"
	local helpTextToken = self.netResultToText[errorCode] and self.netResultToText[errorCode].help or "NETWORK_PROBLEM_HELP"

        local window = Window("text_list", self:string(titleToken) )
	window:setButtonAction("rbutton", nil)

        local menu = SimpleMenu("menu")
	
	menu:setHeaderWidget( Textarea( "help_text", self:string(helpTextToken) ) )

	self:_addDiagnosticsMenuItem(menu)
	self:_addRepairNetworkItem(menu)

        window:addWidget(menu)

        window:show()
	return window

end


-- MAIN MENU

-- Service menu
function diagnosticsMenu(self, suppressNetworkingItem)
	local window = Window("text_list", self:string("DIAGNOSTICS"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	menu:addItem({
		text = self:string("MENU_GENERAL"),
		sound = "WINDOWSHOW",		
		style = 'item',
		callback = function ()
			self:showGeneralDiagnosticsMenu()
		end
	})

	menu:addItem({
		text = self:string("MENU_NETWORK_HEALTH"),
		sound = "WINDOWSHOW",		
		style = 'item',
		callback = function ()
			self:showNetworkHealthDiagnosticsMenu()
		end
	})

	menu:addItem({
		text = self:string("MENU_WIRELESS"),
		sound = "WINDOWSHOW",		
		style = 'item',
		callback = function ()
			self:showWirelessDiagnosticsMenu()
		end
	})

	if System:getMachine() ~= 'jive' then
		menu:addItem({
			text = self:string("MENU_ETHERNET"),
			sound = "WINDOWSHOW",		
			style = 'item',
			callback = function ()
				self:showEthernetDiagnosticsMenu()
			end
		})
	end

	menu:addItem({
		text = self:string("MENU_SERVER"),
		sound = "WINDOWSHOW",		
		style = 'item',
		callback = function ()
			self:showServerDiagnosticsMenu()
		end
	})

	if System:getMachine() == "baby" then
		menu:addItem({
			text = self:string("POWER"),
			sound = "WINDOWSHOW",		
			style = 'item',
			callback = function ()
				self:showPowerDiagnosticsMenu()
			end
		})
	end
	
	if System:isHardware() then
		menu:addItem({
			text = self:string("SOFTWARE_UPDATE"),
			sound = "WINDOWSHOW",		
			style = 'item',
			callback = function ()
				--todo: this does setup style FW upgrade only (since this menu is avilable from setup).  When we want different support for a non-setup version, make sure to leave the setup style behavior
				appletManager:callService("firmwareUpgrade", nil, true)
			end
		})

		if not suppressNetworkingItem then
			menu:addItem({
				text = self:string("DIAGNOSTICS_NETWORKING"),
				sound = "WINDOWSHOW",		
				style = 'item',
				callback = function ()
					appletManager:callService("settingsNetworking")
				end
			})
		end
	end

	self.notConnected = tostring(self:string('NOT_CONNECTED'))

	self.menu = menu

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

-- Service menu
function supportMenu(self)
	local window = Window("help_list", self:string("SUPPORT"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self:_addDiagnosticsMenuItem(menu, true)

	menu:setHeaderWidget(Textarea("help_text", self:string("SUPPORT_HELP")))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end




-- NETWORK HEALTH STUFF
function showNetworkHealthDiagnosticsMenu(self)
	local window = Window("text_list", self:string("MENU_NETWORK_HEALTH"))
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	self.labels = {}
	self.labels["NETWORK_STATUS"] = {
-- For some reason (I have no idea why) the second line is not show anymore in this label
--  and since the second line is the important one the quick fix is to swap the two lines
--		text = self:string("NETWORK_STATUS", tostring(self:string("NET_HEALTH_HINT"))),
		text = self:string(tostring(self:string("NET_HEALTH_HINT")), ''),
		style = 'item_info',
	}
	menu:addItem(self.labels["NETWORK_STATUS"])

	menu:addItem({
		text = self:string("CHECK_NETWORK"),
		style = 'item',
		callback = function ()
			self:manualCheckNetworkHealth(true)
		end
	})

--	menu:addItem({
--		text = self:string("CHECK_NETWORK_PART"),
--		style = 'item',
--		callback = function ()
--			self:manualCheckNetworkHealth(false)
--		end
--	})

	self:_addRepairNetworkItem(menu)
	self.networkHealthMenu = menu

	window:addWidget(menu)

	self:tieAndShowWindow(window)

	return window
end

function _addDiagnosticsMenuItem(self, menu, suppressNetworkingItem)
	menu:addItem({
		text = self:string("DIAGNOSTICS"),
		style = 'item',
		callback = function ()
			self:diagnosticsMenu(suppressNetworkingItem)
		end
	})
end


function _addRepairNetworkItem(self, menu)
	menu:addItem({
		text = self:string("REPAIR_NETWORK"),
		style = 'item',
		callback = function ()
			self:manualRepairNetwork()
		end
	})
end


function setResult(self, index, result, msgStr)
	self:addExtraStyle(jive.ui.style)

	local myItem = self.labels[index]

	-- no error
	if result >= 0 then
		-- Replace everything's ok message with a user friendly one
		msgStr = tostring(self:string("NET_SUCCESS"))
		-- Hack for 'manualRepairNetwork' - a different success message
		if result == 104 then
			msgStr = tostring(self:string("NETWORK_REPAIR_COMPLETE"))
		end
		myItem.style = "item_info_green"
	-- some error
	else
		myItem.style = "item_info_red"
	end

-- For some reason (I have no idea why) the second line is not show anymore in this label
--  and since the second line is the important one the quick fix is to swap the two lines
--	self.networkHealthMenu:setText(self.labels[index], self:string(index, msgStr))
	self.networkHealthMenu:setText(self.labels[index], self:string(msgStr, ''))
	self.networkHealthMenu:setSelectedIndex(1)

-- TODO: needed?
--	self.networkHealthMenu:replaceIndex(myItem, 1)
end


function manualCheckNetworkHealth(self, full_check)
	local popup = Popup("waiting_popup")
	popup:setAllowScreensaver(false)
	popup:ignoreAllInputExcept()

        popup:addWidget(Icon("icon_connecting"))

	if full_check then
	        popup:addWidget(Label("text", self:string("CHECK_NETWORK")))
	else
	        popup:addWidget(Label("text", self:string("CHECK_NETWORK_PART")))
	end

	local status = Label("subtext", self:string("STATUS_MSG", "-"))
	popup:addWidget(status)

	-- Backstop timer. Should 'Networking:checkNetwork' fail without
	-- calling the 'continuation' callback the UI will lock up showing a
	-- spinny. So explicitly close the popup. Allow 10 seconds.
	local checkHasCompleted = false
	popup:addTimer(10000, function()
		if not checkHasCompleted then
				log:info("check network timed out")
				-- Update final message.
				local msgStr = tostring(self:string("NOT_CONNECTED"))
				setResult(self, "NETWORK_STATUS", -1, msgStr)
				popup:hide()
		end
	end,
	true) -- once only

	-- Get current server
	local server = SlimServer:getCurrentServer()

	if server then

	local ifObj = Networking:activeInterface()

	Networking:checkNetworkHealth(
		ifObj,
		function(continue, result, msg_param)
			local msg = self.netResultToText[result].text
			local msgStr = tostring(self:string(msg, msg_param))

			log:debug("checkNetworkHealth status: ", msgStr)

			if continue then
				-- Update spinny message
				status:setValue(self:string("STATUS_MSG", msgStr))
			else
				log:debug("Network health error: ", result)

				-- Update final message
				setResult(self, "NETWORK_STATUS", result, msgStr)
				checkHasCompleted = true

				popup:hide()
			end
		end,
		full_check,		-- true full check (includes arping, DNS resolution and ping)
		server
	)

	end

	self:tieAndShowWindow(popup)
end


function manualRepairNetwork(self)
	local popup = Popup("waiting_popup")
	popup:setAllowScreensaver(false)
	popup:ignoreAllInputExcept()

        popup:addWidget(Icon("icon_connecting"))
        popup:addWidget(Label("text", self:string("REPAIR_NETWORK")))

	local status = Label("subtext", self:string("STATUS_MSG", "-"))
	popup:addWidget(status)

	-- Backstop timer. Should 'Networking:repairNetwork' fail without
	-- calling the 'continuation' callback the UI will lock up showing a
	-- spinny. So explicitly close the popup. Allow 20 seconds.
	local repairHasCompleted = false
	popup:addTimer(20000, function()
		if not repairHasCompleted then
				log:info("Repair network timed out")
				-- Update final message.
				local msgStr = tostring(self:string("NETWORK_REPAIR_PROBLEM"))
				setResult(self, "NETWORK_STATUS", -1, msgStr)
				popup:hide()
		end
	end,
	true) -- once only

	local ifObj = Networking:activeInterface()

	Networking:repairNetwork(
		ifObj,
		function(continue, result)
			local msg = self.netResultToText[result].text
			local msgStr = tostring(self:string(msg))

			log:debug("repairNetwork status: ", msgStr)

			if continue then
				-- Update spinny message
				status:setValue(self:string("STATUS_MSG", msgStr))
			else
				-- Update final message
				log:debug("Repair network error: ", result)
				setResult(self, "NETWORK_STATUS", result, msgStr)
				repairHasCompleted = true

				popup:hide()
			end
		end
	)

	self:tieAndShowWindow(popup)
end


-- defines a new style that inherrits from an existing style
function _uses(parent, value)
	if parent == nil then
		log:warn("nil parent in _uses at:\n", debug.traceback())
	end
	local style = {}
	setmetatable(style, { __index = parent })
	for k,v in pairs(value or {}) do
		if type(v) == "table" and type(parent[k]) == "table" then
			-- recursively inherrit from parent style
			style[k] = _uses(parent[k], v)
		else
			style[k] = v
		end
	end

	return style
end


function addExtraStyle(self, s)
	s.item_info_green = _uses(s.item_info, {
		bgImg = Tile:fillColor(0x00ff0088),
	})
	s.item_info_red = _uses(s.item_info, {
		bgImg = Tile:fillColor(0xff000088),
	})
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

