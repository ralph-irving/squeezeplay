--[[
=head1 NAME

jive.net.Networking 

=head1 DESCRIPTION

This class implements methods for administering network interfaces.

Much of the methods in this class need to be done through Task. These methods are by convention prefixed with t_

=head1 SYNOPSIS

pull in networking object to manipulate wireless interface

	local wirelessInterface = Networking:wirelessInterface()
	local wireless = Networking(jnt, wirelessInterface)

=head1 FUNCTIONS

=cut
--]]

--[[

The file modifies the /etc/network/interfaces file, as described below:

    # Local loopback - always needed
    auto lo
    iface lo inet loopback

    # Wired interface
    # start / stop using 'ifup eth0' and 'ifdown eth0'
    # 'auto eth0' brings this interface up automatically on boot
    auto eth0
    iface eth0 inet dhcp
    	script /etc/network/udhcpc_action

    # Wireless interface
    # the mapping file is used by the network scripts, and must not be changed
    mapping wlan0
        script /etc/network/if_mapping

    # in this file you must use '_' instead of ' ' in ssid
    # start / stop using 'ifup wlan0=<SSID>' and 'ifdown wlan0=<SSID>
    # the wireless configuration must be in /etc/wpa_supplicant.conf
    auto wlan0=<SSID>
    iface <SSID> inet dhcp
        script /etc/network/udhcpc_action

This file also contains any static-ip configuration.

--]]


local assert, ipairs, pairs, pcall, tonumber, tostring, type = assert, ipairs, pairs, pcall, tonumber, tostring, type

local oo          = require("loop.simple")

local io          = require("io")
local os          = require("os")
local math        = require("math")
local string      = require("jive.utils.string")
local table       = require("jive.utils.table")
local ltn12       = require("ltn12")

local debug       = require("jive.utils.debug")
local log         = require("jive.utils.log").logger("net.socket")

local System      = require("jive.System")
local Framework   = require("jive.ui.Framework")
local Socket      = require("jive.net.Socket")
local Process     = require("jive.net.Process")
local Task        = require("jive.ui.Task")
local network     = require("jiveWireless")

-- Needed for network health check function
local DNS         = require("jive.net.DNS")
local jnt         = jnt
local SocketTcp   = require("jive.net.SocketTcp")


module("jive.net.Networking")
oo.class(_M, Socket)


local SSID_TIMEOUT = 20000

-- TODO: Remove when wpsapp is replaced with WPS capable wpa_supplicant
local wpaSupplicantRunning = true


-- wpa scan results signal level -> quality
-- FIXME tune with production boards
local WIRELESS_LEVEL = {
	0,
	175,
	180,
	190,
}

-- FIXME: reduce to two regions, and make sure XX is the correct code for all other regions
local REGION_CODE_MAPPING = {
	-- name, marvell code, atheros code
	[ "US" ] = { 0x10, 4  }, -- ch 1-11
	[ "XX" ] = { 0x30, 14 }, -- ch 1-13
}


-- global for interface objects
local interfaceTable = {}



--[[

=head2 jive.net.Networking(jnt, interface, name)

Constructs an object for administration of a network interface. This
methods should not be called from the application code directly, instead
one of the factory methods below should be used.

=cut
--]]

function __init(self, jnt, interface, isWireless)
	local obj = oo.rawnew(self, Socket(jnt, interface))

	obj.interface     = interface
	obj.wireless      = isWireless
	obj.networkResult = -9999

	if isWireless then
		obj:detectChipset()
	end

	obj._scanResults = {}
	obj.responseQueue = {}
	obj:open()

	return obj
end


--[[

=head2 jive.net.Networking:detectChipset()

Returns chipset used on particular platform
- Jive - Marvell (gspi8686)
- Radio - Atheros (ar6000)
- Touch - Marvell (sd8686)

=cut
--]]

function detectChipset(self)
	local f = io.popen("/sbin/lsmod 2> /dev/null")
	if f == nil then
		return
	end

        while true do
               	local line = f:read("*l")
        	if line == nil then
               		break
        	end

       		local module = string.match(line, "^(%w+)%s+")
       		if module == "ar6000" then
               		self.chipset = "atheros"
       		elseif module == "sd8686" then
               		self.chipset = "marvell"
       		elseif module == "gspi8xxx" then
               		self.chipset = "marvell"
       		end
       	end
       	f:close()
end


--[[

=head2 jive.net.Networking:interfaces(jnt)

Factory method to return a table of interfaces on a device.

=cut
--]]

function interfaces(self, jnt)
	assert(jnt, debug.traceback())

	-- only scan once
	for interface, _ in pairs(interfaceTable) do
		return interfaceTable
	end

	log:debug('looking for network interfaces')

	local interfaces = {}

        local f = assert(io.open("/proc/net/dev"))
	while true do
        	local line = f:read("*l")
		if line == nil then
			break
		end

		local interface = string.match(line, "^%s*(%w+):")
		log:debug("found: ", interface)

		if interface ~= nil and interface ~= 'lo' and not string.find( interface, "usb") then
			table.insert(interfaces, interface)
		end
	end
	f:close()

	log:debug('looking for wireless interfaces')

	local wireless = {}

	-- XXXX replace iwconfig with ioctl lookup
	local f = io.popen("/sbin/iwconfig 2> /dev/null")
        if f ~= nil then
		while true do
        		local line = f:read("*l")
			if line == nil then
				break
			end

			local interface = string.match(line, "^(%w+)%s+")
			if interface then
				log:debug("found wireless: ", interface)
				wireless[interface] = true
			end
		end

        	f:close()
	end

	-- create Networking interface objects
	for _, interface in ipairs(interfaces) do
		interfaceTable[interface] = self(jnt, interface, wireless[interface])
	end

	return interfaceTable
end


--[[

Returns the active interface

--]]
function activeInterface(self)
	local active = nil

        local f = assert(io.open("/etc/network/interfaces"))
	while true do
        	local line = f:read("*l")
		if line == nil then
			break
		end

		local iface = string.match(line, "auto (%w+)")
		if iface ~= nil and iface ~= 'lo' then
			active = iface
			break
		end
	end
	f:close()

	return interfaceTable[active]
end


--[[

=head2 jive.net.Networking:wirelessInterface(jnt)

Convience method to return first wireless interface object.

=cut
--]]

function wirelessInterface(self, jnt)
        self:interfaces(jnt)

	for _, interface in pairs(interfaceTable) do
		if interface.wireless then
			return interface
		end
	end
	return nil
end


--[[

=head2 jive.net.Networking:wiredInterface(jnt)

Convience method to return first wired interface object.

=cut
--]]

function wiredInterface(self, jnt)
        self:interfaces(jnt)

	for _, interface in pairs(interfaceTable) do
		if not interface.wireless  then
			return interface 
		end
	end
	return nil
end


--[[

=head2 networking:getName(self, interface)

Returns the interface name of interface object

=cut
--]]

function getName(self)
	return self.interface
end


--[[

=head2 networking:isAtheros(self)

Returns true if the system is using Atheros wlan

=cut
--]]
function isAtheros(self)
	return self.chipset == "atheros"
end


--[[

=head2 networking:isMarvell(self)

Returns true if the system is using Marvell wlan

=cut
--]]
function isMarvell(self)
	return self.chipset == "marvell"
end


--[[

=head2 networking:isWireless(self)

Return true if the I<interface> is wireless

=cut
--]]

function isWireless(self)
	return self.wireless
end


function isNetworkError(self)
	if self.networkResult and type(self.networkResult) == 'number' and self.networkResult < 0 then
		return true
	end
	return false
end


function getNetworkResult(self)
	return self.networkResult
end

function setNetworkResult(self, result)
	self.networkResult = result
end

--[[

=head2 networking:getIPAddressAndSubnet(self)

Returns the ip address and subnet, if any

=cut
--]]

function getIPAddressAndSubnet(self)
	if not self.t_sock then
		return
	end

	local ip_address, ip_subnet

	local ifdata = self.t_sock:getIfConfig()
	if ifdata ~= nil then
		ip_address = ifdata[1]
		ip_subnet = ifdata[2]
	end

	return ip_address, ip_subnet
end


--[[

=head2 networking:getRegionNames()

returns the available wireless region names

=cut
--]]

function getRegionNames(self)
	return pairs(REGION_CODE_MAPPING)
end


--[[

=head2 networking:getRegion()

Returns the current region for this interface

=cut
--]]

function getRegion(self)
	-- check config file
	local fh = io.open("/etc/network/config")
	if fh then
		local file = fh:read("*a")
		fh:close()

		local region = string.match(file, "REGION=([^%s]+)")
		if  region then
			return region
		end
	end
	
	-- check marvell region
	local fh = assert(io.popen("/sbin/iwpriv " .. self.interface .. " getregioncode"))
	local line = fh:read("*a")
	fh:close()

	local code = tonumber(string.match(line, "getregioncode:(%d+)"))

	for name,mapping in pairs(REGION_CODE_MAPPING) do
		log:debug("code=", code, " mapping[1]=", mapping[1])
		if mapping[1] == code then
			log:debug("returning=", name)
			return name
		end
	end
	return nil
end


--[[

=head2 networking:setRegion(region)

Sets the current region for this interface

=cut
--]]

function setRegion(self, region)
	if type(self.interface) ~= "string" then
		return
	end
	local mapping = REGION_CODE_MAPPING[region]
	if not mapping then
		return
	end

	-- save config file
	System:atomicWrite("/etc/network/config",
		"REGION=" .. region .. "\n" ..
		"REGIONCODE=" .. mapping[1] .. "\n")

	-- set new region
	local cmd = "/sbin/iwpriv " .. self.interface .. " setregioncode " .. mapping[1]
	log:info("setRegion: ", cmd)
	os.execute(cmd)

end


--[[

=head2 jive.net.Networking:getMarvellRegionCode()

returns the region code for Marvell on Jive

=cut
--]]

function getMarvellRegionCode(self)
	local mapping = REGION_CODE_MAPPING[region or self:getRegion()]
	return mapping and mapping[1] or 0
end


--[[

=head2 jive.net.Networking:getAtherosRegionCode()

returns the region code for Atheros on Squeezebox

=cut
--]]

function getAtherosRegionCode(self)
	local mapping = REGION_CODE_MAPPING[region or self:getRegion()]
	return mapping and mapping[2] or 0
end


--[[

=head2 jive.net.Networking:scan(callback)

Start a wireless network scan in a new task.

=cut
--]]

function scan(self, callback)
	if self._scantask then
		return
	end

	self._scantask = Task("networkScan", self, function()
		if self.wireless then
			_wirelessScanTask(self, callback)
		else
			_ethernetScanTask(self, callback)
		end
		self._scantask = nil
	end):addTask()
end


--[[

=head2 jive.net.Networking:scanResults()

returns wireless scan results, or nil if a network scan has not been performed.

=cut
--]]

function scanResults(self)
	assert(self, debug.traceback())

	return self._scanResults
end


--[[

=head2 jive.net.Networking:_wirelessScanTask(callback)

network scanning. this can take a little time so we do this in 
the network thread so the ui is not blocked.

=cut
--]]

function _wirelessScanTask(self, callback)
	assert(Task:running(), "Networking:scan must be called in a Task")

	-- Get the active interface mapping (ssid)
	-- Wireless: ssid, Ethernet: false
	local activenSSID = self:_ifstate()

	-- If we currently use ethernet wpa_supplicant needs to be kicked to allow scanning again
	-- (I.e. move wpa_supplicant state from DISCONNECTED to INACTIVE)
	-- Only Fab4 wpa_supplicant (Marvell?) has this issue
	-- Jive does not have ethernet - not an issue
	-- Baby uses different wpa_supplicant (newer) - not an issue
	if System:getMachine() == "fab4" then
		if not activenSSID then
			self:request("REASSOCIATE")
		end
	end

	-- Scan wireless network
 	local status, err = self:request("SCAN")
	if err then
		return
	end

	-- Get the associated network (ssid)
	local associatedSSID = false
	if activenSSID then
		local status, err = self:request("STATUS")
		if err then
			return
		end

		associatedSSID = string.match(status, "\nssid=([^\n]+)")
	end
 
	-- Load configured networks from wpa supplicant
	local networks = self:request("LIST_NETWORKS")

	-- Get scan results
	local scan, err = self:request("SCAN_RESULTS")
	if err then
		return
	end

	local now = Framework:getTicks()

	-- Process scan results
	-- note: Newer versions of wpa_supplicant may return 'signal level'
	--       strictly in dBm (a negative number).
	for bssid, level, flags, ssid in string.gmatch(scan, "([%x:]+)\t%d+\t([-]?%d+)\t(%S*)\t([^\n]+)\n") do

		local quality = 1
		level = tonumber(level)
		if level < 0 then
			-- Undo the conversion made by newer versions of wpa_supplicant.
			-- This restates 'level' into 'old style', and the following
			-- quality assessment will then work as expected.
			level = level + 256
		end
		for i, l in ipairs(WIRELESS_LEVEL) do
			if level < l then
				break
			end
			quality = i
		end

		-- Add (or update) all found networks to _scanResults list
		self._scanResults[ssid] = {
			bssid = string.lower(bssid),
			flags = flags,
			level = level,
			quality = quality,
			associated = false,
			lastScan = now
		}
	end

	-- Timeout networks - remove from _scanResults list
	for ssid, entry in pairs(self._scanResults) do
		if now - entry.lastScan > SSID_TIMEOUT then
			self._scanResults[ssid] = nil
		end
	end

	-- Add (or update) already configured networks to _scanResults list
	for id, ssid, flags in string.gmatch(networks, "([%d]+)\t([^\t]*)\t[^\t]*\t([^\t]*)\n") do
		if not self._scanResults[ssid] then
			self._scanResults[ssid] = {
				bssid = false,
				flags = "",
				level = 0,
				quality = 0,
				associated = false,
				lastScan = now,
			}
		end

		self._scanResults[ssid].id = id
	end

	-- Mark current network (and count entries)
	local count = 0
	for ssid, entry in pairs(self._scanResults) do
		-- Ssids do not have spaces replaced
		local nssid = string.gsub(ssid, "[ \t]", "_")

		local associated = false

		if nssid and activenSSID and associatedSSID then
			associated = (nssid == activenSSID)
		end

		self._scanResults[ssid].associated = associated

		count = count + 1
	end

	log:info("scan found ", count, " wireless networks")

	-- Bug #5227 if we are associated use the same quality indicator
	-- as the icon bar
	if associatedSSID and self._scanResults[associatedSSID] then
		local percentage, quality = self:getSignalStrength()

		self._scanResults[associatedSSID].quality = quality
	end

	if callback then
		callback(self._scanResults)
	end
end


--[[

=head2 jive.net.Networking:_ethernetScanTask(callback)

Similar to wireless scan task, but for wired interfaces

=cut
--]]

function _ethernetScanTask(self, callback)
	if not self.t_sock then
		return 0
	end

	local status = self.t_sock:ethStatus()

	-- This is eth0=eth0 for ethernet connection
	local active = self:_ifstate()

	status.flags  = "[ETH]"
	status.lastScan = Framework:getTicks()
	status.associated = (self.interface == active)

	self._scanResults[self.interface] = status

	if callback then
		callback(self._scanResults)
	end
end


--[[

=head2 jive.net.Networking:_ifstate()

Check the ifup interface state. returns true if the interface is enabled
or the enabled ssid for wireless interfaces.

=cut
--]]

function _ifstate(self)
	 local active = false

	 local f = assert(io.open("/var/run/ifstate"))
	 while true do
	 	local line = f:read("*l")
		if line == nil then
			break
		end

		local iface, mapping = string.match(line, "([^=]+)=?(.*)")
		if iface == self.interface then
			active = mapping or true
			break
		end
	end
	f:close()

	return active
end


--[[

=head2 jive.net.Networking:status()

Get status information for wireless or wired interface.
- Wired: link, speed, fullDuplex
- Wireless: ssid, encryption, ...

=cut
--]]

function status(self)
	assert(Task:running(), "Networking:basicStatus must be called in a Task")

	local status = {}

	if self.wireless then
		local statusStr = self:request("STATUS")

		for k,v in string.gmatch(statusStr, "([^=]+)=([^\n]+)\n") do
			status[k] = v
		end
	else
		if not self.t_sock then
			return 0
		end
		status = self.t_sock:ethStatus()
		status.wpa_state = "COMPLETED"
	end

	return status
end


--[[

=head2 jive.net.Networking:t_wpaStatus()

parse and return wpa status

=cut
--]]

-- XXXX rename to just status()
function t_wpaStatus(self)
	assert(Task:running(), "Networking:wpaStatus must be called in a Task")

	local status = self:status()

	-- exit early if we are not connected
	if status.wpa_state ~= "COMPLETED" then
		return status
	end

	local ip_address, ip_subnet = self:getIPAddressAndSubnet()

	if ip_address and ip_subnet then
		status.ip_address = ip_address
		status.ip_subnet = ip_subnet
	end

	-- exit early if we do not have an ip address
	if not status.ip_address then
		return status
	end

	-- Get gateway
	local f2 = io.open("/proc/net/route")
	if f2 ~= nil then
		-- Read header line
		local line = f2:read("*l")
		while true do
			local line = f2:read("*l")
			if line == nil then
				break
			end

			local gateway, flags = string.match(line, "%S+%s+%x+%s+(%x+)%s+(%x+)")

			-- Look for the default gateway (RTF_UP | RTF_GATEWAY = 0x03)
			if tonumber(flags) == 0x03 then
				-- Convert ip4v to dotted format
				local a, b, c, d = string.match(gateway, "(%x%x)(%x%x)(%x%x)(%x%x)")
				gateway = tonumber(d, 16) .. "." .. tonumber(c, 16) .. "." .. tonumber(b, 16) .. "." .. tonumber(a, 16)
				status.ip_gateway = gateway
			end
		end
		f2:close()
	end

	-- Get nameserver
	local f = io.open("/etc/resolv.conf")
	if f ~= nil then
		while true do
			local line = f:read("*l")
			if line == nil then
				break
			end

			local dns = string.match(line, "nameserver ([%d\.]+)")
			if dns then
				status.ip_dns = dns
				break
			end
		end
		f:close()
	end

	return status
end


--[[

=head2 jive.net.Networking:t_addWPSNetwork(ssid)

wpa_supplicant using with Atheros already adds the network
to wpa_supplicant.conf when using WPS but it still needs to
be added to the interfaces file

=cut
--]]

function t_addWPSNetwork(self, ssid)
	assert(Task:running(), "Networking:addNetwork must be called in a Task")

	-- Set to use dhcp by default
	self:_editNetworkInterfaces(ssid, "dhcp", "script /etc/network/udhcpc_action")
end

--[[

=head2 jive.net.Networking:t_addNetwork(ssid, option)

adds a network to the list of discovered networks

=cut
--]]

function t_addNetwork(self, ssid, option)
	assert(Task:running(), "Networking:addNetwork must be called in a Task")

	log:info("add network ", ssid)

	-- make sure this ssid is not in any configuration
	self:t_removeNetwork(ssid)

	-- Set to use dhcp by default
	self:_editNetworkInterfaces(ssid, "dhcp", "script /etc/network/udhcpc_action")

	if not self.wireless then
		-- no further action for ethernet
		return
	end

	log:info("Connect to ", ssid)
	local flags = (self._scanResults[ssid] and self._scanResults[ssid].flags) or ""

	local request, response

	response = self:request("ADD_NETWORK")
	local id = string.match(response, "%d+")
	assert(id, "wpa_cli failed: to add network")

	request = 'SET_NETWORK ' .. id .. ' ssid "' .. ssid .. '"'
	assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	if string.find(flags, "IBSS") or option.ibss then
		request = 'SET_NETWORK ' .. id .. ' mode 1 '
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)
	end

	if option.encryption == "wpa" then
		log:info("encryption WPA")

		request = 'SET_NETWORK ' .. id .. ' key_mgmt WPA-PSK'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		request = 'SET_NETWORK ' .. id .. ' proto WPA'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		if #option.psk <= 63 then
			-- psk is ASCII passphrase (8 - 63 chars) and needs quotes
			request = 'SET_NETWORK ' .. id .. ' psk "' .. option.psk .. '"'
		else
			-- psk is 64 hex-digits (32 bytes) and needs _no_ quotes
			request = 'SET_NETWORK ' .. id .. ' psk ' .. option.psk
		end

		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	elseif option.encryption == "wpa2" then
		log:info("encryption WPA2")

		request = 'SET_NETWORK ' .. id .. ' key_mgmt WPA-PSK'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		request = 'SET_NETWORK ' .. id .. ' proto WPA2'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		if #option.psk <= 63 then
			-- psk is ASCII passphrase (8 - 63 chars) and needs quotes
			request = 'SET_NETWORK ' .. id .. ' psk "' .. option.psk .. '"'
		else
			-- psk is 64 hex-digits (32 bytes) and needs _no_ quotes
			request = 'SET_NETWORK ' .. id .. ' psk ' .. option.psk
		end

		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)
	else
		request = 'SET_NETWORK ' .. id .. ' key_mgmt NONE'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)
	end

-- fm+
--	if option.encryption == "wep40" or option.encryption == "wep104" then
	if option.encryption == "wep40_104" then
-- fm-
		log:info("encryption WEP")

		request = 'SET_NETWORK ' .. id .. ' wep_key0 ' .. option.key
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)
	end

	-- Enable scanning with ssid specific probe requests at all times.
	-- (Previously we only did it for hidden SSIDs, i.e. when not listed in self._scanResults[ssid])
	-- This allows us to find APs with hidden SSIDs _and_ APs where the SSID
	--  is hidden later on. And it also works for non hidden SSIDs.
	request = 'SET_NETWORK ' .. id .. ' scan_ssid 1'
	assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	-- Disconnect from existing network
	self:_ifDown()

	-- Use select network to disable all other networks
	request = 'SELECT_NETWORK ' .. id
	assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	-- Reassociate seems to break ad hoc
	if not (string.find(flags, "IBSS") or option.ibss) then
		-- Allow association
		request = 'REASSOCIATE'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)
	end

	-- Save config, it will be removed later if it fails
	request = 'SAVE_CONFIG'
	assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	return id
end


--[[

=head2 jive.net.Networking:t_removeNetwork(ssid)

forgets a previously discovered network 

=cut
--]]

function t_removeNetwork(self, ssid)
	assert(Task:running(), "Networking:removeNetwork must be called in a Task")

	log:info("remove network ", ssid)

	if self.wireless then
		local networkResults = self:request("LIST_NETWORKS")

		local id = false
		local flags = false
		for nid, nssid, nbssid, nflags in string.gmatch(networkResults, "([%d]+)\t([^\t]*)\t([^\t]*)\t(.-)\n") do
			if nssid == ssid then
				id = nid
				flags = nflags
				break
			end
		end

		-- Remove ssid from wpa supplicant
		if id then
			local request = 'REMOVE_NETWORK ' .. id
			assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

			request = 'SAVE_CONFIG'
			assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)
		end

		-- Bug 10869: Make sure only one dhcp client is running on the wireless interface
		-- If we are forgetting the currently used wireless connection, also disconnect
		-- This in turn calls ifdown and stops the dhcp client daemon
		if flags and flags == "[CURRENT]" then
			self:t_disconnectNetwork()
		end

		-- Remove dhcp/static ip configuration for network
		self:_editNetworkInterfaces(ssid)
	end
end


--[[
=head2 jive.net.Networking:t_disconnectNetwork()

brings down a network interface. If wireless, then force the wireless disconnect as well

=cut
--]]
function t_disconnectNetwork(self)
	 self:_ifDown()
end


--[[

=head2 jive.net.Networking:t_selectNetwork(ssid)

selects a network to connect to. wireless only

=cut
--]]

function t_selectNetwork(self, ssid)
	assert(Task:running(), "Networking:selectNetwork must be called in a Task")

	log:info("select network ", ssid)

	-- set as auto network
	self:_editAutoInterfaces(ssid)

	-- bring the interface up
	self:_ifUp(ssid)
end


--[[

=head2 jive.net.Networking:t_setStaticIp(ssid, ipAddress, ipSubnet, ipGateway, ipDNS)

apply IP address and associated configuration parameters to a network interface

=cut
--]]


function t_setStaticIP(self, ssid, ipAddress, ipSubnet, ipGateway, ipDNS)
	assert(type(self.interface) == 'string')
	-- Reset the network
	local killCommand   = "kill -TERM `cat /var/run/udhcpc." .. self.interface .. ".pid`"
	local killCommand2  = "killall zcip > /dev/null"
	local configCommand = "/sbin/ifconfig " .. self.interface .. " 0.0.0.0"

	os.execute(killCommand)
	os.execute(killCommand2)
	os.execute(configCommand)

	-- Set static ip configuration for network
	self:_editNetworkInterfaces(ssid, 
		"static",
		"address " .. ipAddress,
		"netmask " .. ipSubnet,
		"gateway " .. ipGateway,
		"dns " .. ipDNS,
		"up echo 'nameserver " .. ipDNS .. "' > /etc/resolv.conf"
	)

	self:_ifUp(ssid)
end


--[[

=head2 jive.net.Networking:_ifUp(ssid)

brings I<interface> up, and all others (except loopback) down
writes to /etc/network/interfaces and configures i<interface> 
to be the only interface brought up at next boot time

if the optional ssid argument is given, correct use of ifup I<interface>=I<ssid> is used

=cut
--]]

function _ifUp(self, ssid)
	-- bring down all other interfaces
	for _, interface in pairs(interfaceTable) do
		if interface ~= self then
			interface:_ifDown()
		end
	end

	-- associate
	if self.wireless then
		-- FIXME this should be handled by the ifup scripts

		-- We need to kick wpa_cli in order to work properly
		-- Also during WPS wpa_cli was stopped
		self:restartWpaCli()

		local networkResults = self:request("LIST_NETWORKS")

		local id = false
		for nid, nssid in string.gmatch(networkResults, "([%d]+)\t([^\t]*).-\n") do
			if nssid == ssid then
				id = nid
				break
			end

			-- In wpa_supplicant.conf ssids do not have spaces replaced
			--  doublecheck with spaces replaced
			nssid = string.gsub(nssid, "[ \t]", "_")
			if nssid == ssid then
				id = nid
				break
			end
		end

		-- Select network
		if not id then
			log:warn("_ifUp - can't find network ", ssid)
			return
		end

		-- Disconnect from existing network
		local request = 'DISCONNECT'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		local request = 'SELECT_NETWORK ' .. id
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		-- Allow association
		request = 'REASSOCIATE'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		-- Save configuration
		request = 'SAVE_CONFIG'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	end

	-- bring interface up
	local iface = self.interface
	if self.wireless then
		ssid = string.gsub(ssid, "[ \t]", "_")
		-- Bug 11840: Allow special chars in SSID
		-- First escape '\' and '"' ...
		ssid = string.gsub(ssid, '\\', '\\\\')
		ssid = string.gsub(ssid, '"', '\\"')
		-- ... then quote SSID for ifup call
		iface = '"' .. iface .. "=" .. ssid .. '"'
	end

	log:info("ifup ", iface)
	self:_ifUpDown("/sbin/ifup " .. iface)
end


--[[

=head2 networking:_ifDown()

brings I<interface> down
=cut
--]]

function _ifDown(self)
	-- bring interface down
	local active = self:_ifstate()

	if active then
		local iface = self.interface
		if self.wireless then
			-- Bug 11840: Allow special chars in SSID
			-- First escape '\' and '"' ...
			local ssid = string.gsub(active, '\\', '\\\\')
			ssid = string.gsub(ssid, '"', '\\"')
			-- ... then quote SSID for ifdown call
			iface = '"' .. iface .. "=" .. ssid .. '"'
		end

		log:info("ifdown ", iface)
		self:_ifUpDown("/sbin/ifdown " .. iface .. " -f")

		if not self.wireless then
			return
		end

		-- FIXME this should be handled by the ifdown scripts

		-- disconnect
		local networkResults = self:request("LIST_NETWORKS")

		local id = false
		for nid, nssid in string.gmatch(networkResults, "([%d]+)\t([^\t]*).-\n") do
			log:info("id=", nid, " ssid=", nssid)
			if nssid == active then
				id = nid
				break
			end

			-- In wpa_supplicant.conf ssids do not have spaces replaced
			--  doublecheck with spaces replaced
			nssid = string.gsub(nssid, "[ \t]", "_")
			if nssid == active then
				id = nid
				break
			end
		end

		-- Select network
		if not id then
			log:warn("_ifDown - can't find network ", active)
			return
		end

		-- Disconnect from existing network
		local request = 'DISCONNECT'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		-- Disable network
		local request = 'DISABLE_NETWORK ' .. id
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

		-- Save configuration
		request = 'SAVE_CONFIG'
		assert(self:request(request) == "OK\n", "wpa_cli failed:" .. request)

	end
end

--[[

=head2 jive.net.Networking:_ifUpDown(cmd)

Utility function to call ifup and ifdown in a process.

=cut
--]]


function _ifUpDown(self, cmd)
	-- reading the output of ifup causes the process to block, we
	-- don't need the output, so send stdout and stderr to /dev/null
	local proc = Process(self.jnt, cmd .. " 2>/dev/null 1>/dev/null")
	proc:read(
		function(chunk, err)
			if err then
				log:error("if command failed: ", err)
				return false
			end
                       	-- FIXME: if command was ifup and command succeeded, bring down other interfaces
                       	if chunk ~= nil then
                       	end
                        return 1
       		end)

	while proc:status() ~= "dead" do
		-- wait for the process to complete
		Task:yield()
	end
end


--[[

=head2 jive.net.Networking:_editAutoInterfaces( ssid)

Handles the 'auto' entry for the active interface in /etc/network/interfaces

=cut
--]]

function _editAutoInterfaces(self, ssid)
	local interface = self.interface

	-- for the `auto interface[=<ssid>]` line
	local autoInterface = interface

	-- for the `iface <interface|ssid> inet ...` line
	local iface_name = interface

	if ssid and self.wireless then
		ssid = string.gsub(ssid, "[ \t]", "_")
		autoInterface = interface .. "=" .. ssid
		iface_name = ssid
	end

	log:debug('writing /etc/network/interfaces, enabling auto for ', autoInterface)

	local fi = assert(io.open("/etc/network/interfaces", "r+"))
	local outStr = ""

	local autoSet = false
	for line in fi:lines() do
		if string.match(line, "^auto%s") then
			-- if the interface is to be enabled, it should continue to be set to auto 
			if string.matchLiteral(line, autoInterface) then
				outStr = outStr .. line .. "\n"
				autoSet = true
			elseif string.match(line, "^auto%slo") then
				outStr = outStr .. line .. "\n"
			else
				log:debug('disabling interface: ', line)
			end
		elseif string.match(line, "^iface%s") then
			if not autoSet and string.matchLiteral(line, iface_name) then
				log:debug('enabling interface:', autoInterface)
				outStr = outStr .. "auto " .. autoInterface .. "\n"
				autoSet = true
			end
			outStr = outStr .. line .. "\n"
		else
			outStr = outStr .. line .. "\n"
		end
	end

	fi:close()

	System:atomicWrite("/etc/network/interfaces", outStr)
end

--[[

=head2 jive.net.Networking:_editNetworkInterfacesBlock( outStr, iface_name, method, ...)

Helper function for _editInterfaces()

=cut
--]]


function _editNetworkInterfacesBlock( self, outStr, iface_name, method, ...)

	if method then
		outStr = outStr .. "iface " .. iface_name .. " inet " .. method .. "\n"
		log:debug("WRITING: ", "iface ", iface_name, " inet ", method)
		for _,v in ipairs{...} do
			outStr = outStr .. "\t" .. v .. "\n"
			log:debug("WRITING:\t", v)
		end
	end

	return outStr
end


--[[

=head2 jive.net.Networking:_editInterfaces(ssid, method, ...)

Add and removes interfaces to /etc/network/interfaces

=cut
--]]

function _editNetworkInterfaces( self, ssid, method, ...)
	local iface = self.interface

	-- the interfaces file uses " \t" as word breaks so munge the ssid
	-- FIXME ssid's with \n are not supported
	assert(ssid, debug.traceback())
	ssid = string.gsub(ssid, "[ \t]", "_")

	log:debug('WRITING /etc/network/interfaces for ', iface, ', ssid: ', ssid , ' method: ', method)

	local fi = assert(io.open("/etc/network/interfaces", "r+"))
	local outStr = ""

	local iface_name

	if ssid then
		iface_name = ssid
	else
		iface_name = iface
	end

	local network = ""
	local done = false

	for line in fi:lines() do
		-- this cues a new block, so clear the network variable
		if string.match(line, "^mapping%s") or string.match(line, "^auto%s") then
			network = ""
		-- this also cues a new block, possibly for iface_name
		elseif string.match(line, "^iface%s") then
			network = string.match(line, "^iface%s([^%s]+)%s")
			-- when network is iface_name, write a new block for it
			if network == iface_name then
				outStr = self:_editNetworkInterfacesBlock( outStr, network, method, ...)
				-- mark that we're done writing the iface_name block
				done = true
			end
		end
		-- write any line except what previously existed for the iface_name block
		if network ~= iface_name then
			outStr = outStr .. line .. "\n"
		end
	end

	-- if we haven't written the block for iface_name, do it now
	if not done then
		outStr = self:_editNetworkInterfacesBlock( outStr, iface_name, method, ...)
	end

	fi:close()

	System:atomicWrite("/etc/network/interfaces", outStr)
end


--[[
=head2 jive.net.Networking:getLinkQuality()

returns "quality" and snr of wireless interface
used for dividing SNR values into categorical levels of signal quality

(deprecated, use getSignalStrength instead)

=cut
--]]

function getLinkQuality(self)
	log:error("**** This function is deprecated - use getSignalStrength() instead")

	local percentage, quality = self:getSignalStrength()

	return quality, percentage
end


--[[

=head2 jive.net.Networking:getSNR()

returns signal to noise ratio of wireless link

=cut
--]]

function getSNR(self)
	if type(self.interface) ~= 'string' then
		return 0
	end

	if not self.t_sock then
		return 0
	end

	local t = self.t_sock:getSNR()
	if t == nil then
		log:error("getSNR() failed")
		return 0
	end

	-- == Marvell ==
	-- t[1] : Beacon non-average
	-- t[2] : Beacon average
	-- t[3] : Data non-average
	-- t[4] : Data average
	-- == Atheros ==
	-- t[1] : Beacon non-average
	-- t[2] : Beacon average
	-- t[3] : 0
	-- t[4] : 0

	if self.minSNR == nil then
		self.minSNR = t[2]
		self.maxSNR = t[2]
	else
		self.minSNR = math.min(self.minSNR, t[2])
		self.maxSNR = math.max(self.maxSNR, t[2])
	end

	return t[2], self.minSNR, self.maxSNR
end


--[[

=head2 jive.net.Networking:getSignalStrength()

Returns wireless signal strength as a percentage (0-100) and quality (0-4)

=cut
--]]

function getSignalStrength(self)
	local snr = getSNR(self)

	-- with informal testing I see a SNR range of: 
	-- jive: 5 - 71
	-- baby: 5 - 72

	-- an SNR of 20dB should be adequate, this is tuned so
	-- percentage: 100% = 40 SNR
	-- quality: 0 - 4

	local percentage = math.ceil((math.min(snr, 40) / 40) * 100)
	local quality = math.ceil(percentage / 25)

	return percentage, quality
end


--[[

=head2 jive.net.Networking:getTxBitRate()

returns bitrate of a wireless interface

=cut
--]]

function getTxBitRate(self)
	if type(self.interface) ~= 'string' then
		return "0"
	end
	local f = io.popen("/sbin/iwconfig " .. self.interface)
	if f == nil then
		return "0"
	end

	local t = f:read("*all")
	f:close()

	return string.match(t, "Bit Rate:(%d+%s[^%s]+)")
end


--[[

=head2 jive.net.Networking:powerSave(enable)

sets wireless power save state

=cut
--]]

function powerSave(self, enable)
	if self._powerSaveState == enable then
		return
	end

	if not self.t_sock then
		return
	end

	self._powerSaveState = enable
	if enable then
		log:info("iwconfig power on")
		self.t_sock:setPower(true)
	else
		log:info("iwconfig power off")
		self.t_sock:setPower(false)
	end
end


--[[

=head2 jive.net.Networking:open()

opens a socket to pick up network events

=cut
--]]

function open(self)
	if self.t_sock then
		log:error("Socket already open")
		return
	end

	local err

	log:debug('Open network socket')
	-- self.wireless and self.chipset are only valid for wireless interfaces
	self.t_sock, err = network:open(self.interface, self.wireless, self.chipset)
	if err then
		log:warn(err)
	
		self:close()
		return false
	end

	if self.wireless then
		local source = function()
				       return self.t_sock:receive()
			       end
	
		local sink = function(chunk, err)
				     if chunk and string.sub(chunk, 1, 1) == "<" then
					     -- wpa event message
					     if self.eventSink  then
						     Task("wirelessEvent", nil,
							  function()
								  self.eventSink(chunk, err)
							  end):addTask()
					     end
				     else
					     -- request response
					     local task = table.remove(self.responseQueue, 1)
					     if task then
						     task:addTask(chunk, err)
					     end
				     end
			     end
	
		self:t_addRead(function()
				       -- XXXX handle timeout
				       local status, err = ltn12.pump.step(source, sink)
				       if err then
					       log:warn(err)
					       self:close()
				       end
			       end,
	       0) -- no timeout
	end

	return true
end


--[[

=head2 jive.net.Networking:close()

closes existing socket

=cut
--]]

function close(self)
	-- cancel queued requests
	for i, task in ipairs(self.responseQueue) do
		task:addTask(nil, "closed")
	end
	self.responseQueue = {}

	Socket.close(self)
end


--[[

=head2 jive.net.Networking:request()

pushes request to open socket

=cut
--]]

function request(self, ...)
	local task = Task:running()
	assert(task, "Networking:request must be called in a Task")

	if self:isMarvell(self) then
		if wpaSupplicantRunning == false then
			return "", "not running"
		end
	end


	log:debug("REQUEST: ", ...)

	-- open the socket if it is closed
	if not self.t_sock and not self:open() then
		-- XXXX callers expect a string
		return "", "closed"
	end

	local status, err = self.t_sock:request(...)

	if err then
		log:warn(err)
		self:close()

		-- XXXX callers expect a string
		return "", err
	end

	-- yield task
	table.insert(self.responseQueue, task)
	local _, reply, err = Task:yield(false)

	if not reply or err then
		log:warn(err)
		self:close()

		-- XXXX callers expect a string
		return "", err
	end

	log:debug("REPLY:", reply, " for ", ...)
	return reply
end


function attach(self, sink)
	-- XXXX allow multiple sinks
	self.eventSink = sink
end


function detach(self)
	self.eventSink = nil
end




--[[

=head2 jive.net.Networking:computeWPSChecksum()

Computes last digit of WPS pin

=cut
--]]

function computeWPSChecksum( pin)
	local accum = 0
	local digit
	local pin = pin * 10

	accum = accum + 3 * (math.floor(pin / 10000000) % 10)
	accum = accum + 1 * (math.floor(pin / 1000000) % 10)
	accum = accum + 3 * (math.floor(pin / 100000) % 10)
	accum = accum + 1 * (math.floor(pin / 10000) % 10)
	accum = accum + 3 * (math.floor(pin / 1000) % 10)
	accum = accum + 1 * (math.floor(pin / 100) % 10)
	accum = accum + 3 * (math.floor(pin / 10) % 10)
	digit = (accum % 10)

	return (10 - digit) % 10
end


--[[

=head2 jive.net.Networking:generateWPSPin()

Returns 8 digit generated WPS pin

=cut
--]]

function generateWPSPin(self)
	local wps_pin

-- TODO: Needed? Seem to be different after each reboot already
--	math.randomseed(os.time())
	wps_pin = math.random(0,10000000) % 10000000

	if wps_pin < 1000000 then
		wps_pin = wps_pin + 1000000
	end

	wps_pin = wps_pin * 10 + computeWPSChecksum( wps_pin)

	return wps_pin
end

--[[

=head2 jive.net.Networking:startWPSApp()

Starts the wpsapp (Marvell) to get passphrase etc. via WPS
Removes old wps.conf file

=cut
--]]

function startWPSApp(self, wpsmethod, wpspin)
	assert(wpsmethod, debug.traceback())

--	Do this in the same shell command to maintain the correct sequence, i.e.
--	 first stopping a still running wpsapp, then starting the new one.
--	Seems to be an issue lately - maybe since using the RT kernel?
--	self:stopWPSApp()
	log:info("startWPSApp")
	os.execute("rm /usr/sbin/wps/wps.conf 2>/dev/null 1>/dev/null &")
	if( wpsmethod == "pbc") then
		os.execute("killall wpsapp 2>/dev/null 1>/dev/null; cd /usr/sbin/wps; ./wpsapp " .. self.interface .. " " .. wpsmethod .. " 2>/dev/null 1>/dev/null &")
	else
		assert( wpspin, debug.traceback())
		os.execute("killall wpsapp 2>/dev/null 1>/dev/null; cd /usr/sbin/wps; ./wpsapp " .. self.interface .. " " .. wpsmethod .. " " .. wpspin .. " 2>/dev/null 1>/dev/null &")
	end
end

--[[

=head2 jive.net.Networking:stopWPSApp()

Stops the wpsapp (Marvell) to get passphrase etc. via WPS

=cut
--]]

function stopWPSApp(self)
	log:info("stopWPSApp")
	os.execute("killall wpsapp 2>/dev/null 1>/dev/null &")
end

--[[

=head2 jive.net.Networking:startWPASupplicant()

Starts wpa supplicant

=cut
--]]

function startWPASupplicant(self)
	log:info("startWPASupplicant")
	os.execute("/usr/sbin/wpa_supplicant -B -Dmarvell -i" .. self.interface .. " -c/etc/wpa_supplicant.conf")
	wpaSupplicantRunning = true
end

--[[

=head2 jive.net.Networking:stopWPASupplicant()

Stops wpa supplicant

=cut
--]]

function stopWPASupplicant(self)
	log:info("stopWPASupplicant")
	wpaSupplicantRunning = false
	os.execute("killall wpa_supplicant 2>/dev/null 1>/dev/null &")
	self:close()
end

--[[

=head2 jive.net.Networking:restartWpaCli()

Restarts wpa cli

=cut
--]]

function restartWpaCli(self)
	log:info("restartWpaCli")
	os.execute("killall wpa_cli 2>/dev/null 1>/dev/null; /usr/sbin/wpa_cli -B -a/etc/network/wpa_action 2>/dev/null 1>/dev/null &")
end

--[[

=head2 jive.net.Networking:stopWpaCli()

Stops wpa cli

=cut
--]]

function stopWpaCli(self)
	log:info("stopWpaCli")
	os.execute("killall wpa_cli 2>/dev/null 1>/dev/null &")
end

--[[

=head2 jive.net.Networking:t_wpsStatus()

Returns data from wps.conf if present

=cut
--]]

function t_wpsStatus(self)
	assert(Task:running(), "Networking:t_wpsStatus must be called in a Task")

	local status = {}

	local fh = io.open("/usr/sbin/wps/wps.conf", "r")
	if fh == nil then
		status.wps_state = "IN_PROGRESS"
	else
		local wpsconf = fh:read("*all")
		fh:close()

		local proto = string.match(wpsconf, "proto=([^%s]+)")
		-- psk is ASCII passphrase (8 - 63 chars) and has quotes
		local psk = string.match(wpsconf, "psk=\"(.+)\"\n")
		if psk == nil then
			-- psk is 64 hex-digits (32 bytes) and has _no_ quotes
			psk = string.match(wpsconf, "psk=([^%s]+)")
		end
		local key = string.match(wpsconf, "wep_key0=([^%s]+)")

		-- No encryption
		if proto == nil and psk == nil and key == nil then
			status.wps_encryption = "none"

-- fm+
--		-- WEP 64
--		elseif key ~= nil and #key <= 10 then
--			status.wps_encryption = "wep40"
--		-- WEP 128
--		elseif key ~= nil then
--			status.wps_encryption = "wep104"
		elseif key ~= nil then
			status.wps_encryption = "wep10_104"
-- fm-

		-- WPA
		elseif proto == "WPA" then
			status.wps_encryption = "wpa"
		-- WPA2
		else
			status.wps_encryption = "wpa2"
		end

		status.wps_psk = psk
		status.wps_key = key

		status.wps_state = "COMPLETED"
	end

	return status
end

--[[

=head2 jive.net.Networking:checkNetworkHealth()

The following checks are done (wired or wireless):
- Check for a valid network object
- Check link
- Check for valid ip address
- Check for gateway ip address
- Check for DNS ip address
The following checks are only done if full_check is true
- Check if our ip address is already used by another device
- Resolve ip address for server (SC or SN)
- Ping server (SC or SN)
- Try to connect to port 3483 and 9000

While the checks are running status values are returned
via callback function. The callback provides three params:
- continue: true or false
- result: ok >= 0, nok < 0 (for specific values see code below or sample use in DiagnosticsApplet)
- msg_param: additional message info

class		- Networking class
ifObj		- network object
callback	- callback function
full_check	- includes ip check, DNS resolution, ping and ports test
server		- server to ping and test ports

=cut
--]]

function checkNetworkHealth(class, ifObj, callback, full_check, server)
	assert(type(callback) == 'function', "No callback function provided")

	Task("checknetworkhealth", ifObj, function()
		log:debug("checkNetworkHealth task started")

		callback(true, 1)

		-- ------------------------------------------------------------
		-- Check for valid network interface
		if ifObj == nil then
			callback(false, -1)
			return
		end

		-- ------------------------------------------------------------
		-- Getting network status (link / no link)
		callback(true, 3)

		local status = ifObj:t_wpaStatus()

		if ifObj:isWireless() then
			local percentage, quality = ifObj:getSignalStrength()

			if (status.wpa_state ~= "COMPLETED") or (quality == 0) then
				ifObj:setNetworkResult(-5)
				callback(false, -5)
				return
			end
			callback(true, 5)
		else
			if status.link ~= true then
				ifObj:setNetworkResult(-6)
				callback(false, -6)
				return
			end
			callback(true, 6)
		end

		-- We have a network link (wired or wireless)

		-- ------------------------------------------------------------
		-- Check for valid ip address
		if status.ip_address == nil or string.match(status.ip_address, "^169.254.") then
			ifObj:setNetworkResult(-8)
			callback(false, -8)
			return
		end

		-- We have a valid ip address
		callback(true, 8, tostring(status.ip_address))

		-- ------------------------------------------------------------
		-- Check for valid gateway
		if status.ip_gateway == nil then
			ifObj:setNetworkResult(-10)
			callback(false, -10)
			return
		end

		-- We have a valid gateway
		callback(true, 10, tostring(status.ip_gateway))

		-- ------------------------------------------------------------
		-- Check for valid dns sever ip
		if status.ip_dns == nil then
			ifObj:setNetworkResult(-12)
			callback(false, -12)
			return
		end

		-- We have a valid dns server ip
		callback(true, 12, tostring(status.ip_dns))

		-- ------------------------------------------------------------
		-- Stop here if not full check is needed
		if not full_check then
			ifObj:setNetworkResult(12)
			callback(false, 12, tostring(status.ip_dns))

			log:debug("checkNetworkHealth task done (part)")

			return
		end

		-- ------------------------------------------------------------
		-- Arping our own ip address
		callback(true, 20, tostring(status.ip_address))

		-- Arping
		local arpingOK = false
		local arpingProc = Process(jnt, "arping -I " .. ifObj:getName() .. " -f -c 2 -w 5 " .. status.ip_address .. " 2>&1")
		arpingProc:read(function(chunk)
			if chunk then
				if string.match(chunk, "Received 0 reply") then
					arpingOK = true
				end
			else
				if arpingOK then
					callback(true, 21)
				else
					callback(false, -21, tostring(status.ip_address))
				end
			end
		end)

		-- Wait until arping has finished
		while arpingProc:status() ~= "dead" do
			Task:yield()
		end

		if not arpingOK then
			ifObj:setNetworkResult(-21)
			return
		end

		-- ------------------------------------------------------------
		-- Check for server
		if not server then
			ifObj:setNetworkResult(-23)
			callback(false, -23)
			return
		end

		-- ------------------------------------------------------------
		-- Get ip of server (SC or SN)
		local server_uri, server_port = server:getIpPort()
		local server_name = server:getName()

		local server_ip, err
		if DNS:isip(server_uri) then
			server_ip = server_uri
		else
			callback(true, 25, server_name)
			server_ip, err = DNS:toip(server_uri)
		end

		-- Check for valid SN ip address
		if server_ip == nil then
			ifObj:setNetworkResult(-27)
			callback(false, -27, server_name)
			return
		end

		-- We have a valid ip address for SN
		callback(true, 27, server_name .. ": " .. server_ip)

		-- ------------------------------------------------------------
		-- Ping server (SC or SN)
		callback(true, 29, server_name)

		local pingOK = false
		local pingProc = Process(jnt, "ping -c 1 " .. server_ip)
		pingProc:read(function(chunk)
			if chunk then
				if string.match(chunk, "bytes from") then
					pingOK = true
				end
			else
				if pingOK then
					callback(true, 31, server_name .. " (" .. server_ip .. ")")
				else
					callback(false, -31, server_name .. " (" .. server_ip .. ")")
				end
			end
		end)

		-- Wait until ping has finished - takes a while especially if it fails
		while pingProc:status() ~= "dead" do
			Task:yield()
		end

		if not pingOK then
			ifObj:setNetworkResult(-31)
			return
		end

		-- ------------------------------------------------------------
		-- Port 3483 test
		callback(true, 33, server_name .. " (3483)")

		local portOk_3483 = false
		local tcp_3483 = SocketTcp(jnt, server_ip, 3483, "porttest")
		tcp_3483:t_connect()
		tcp_3483:t_addWrite(function(err)
			local res, err = tcp_3483.t_sock:send(" ")
			if not err then
				portOk_3483 = true
			end

			if portOk_3483 then
				callback(true, 35, server_name .. " (3483)")
			else
				callback(false, -35, server_name .. " (3483)")
			end
			tcp_3483:close()
		end)

		-- Wait until port test has finished
		while tcp_3483.t_sock ~= nil do
			Task:yield()
		end

		if not portOk_3483 then
			ifObj:setNetworkResult(-35)
			return
		end

		-- ------------------------------------------------------------
		-- Port 9000 test
		-- First, check that 'server_port' has been set to a numeric value.
		-- If not, expect an '_assert' failure in SocketTcp.
		-- (In some circumstances server discovery may not fully succeed,
		--  and 'server_port' may be at its initial value of 'false').
		callback(true, 33, server_name .. " (" .. tostring(server_port) .. ")")
		if not tonumber(server_port) then
				callback(false, -37, server_name .. " ( port not defined )")
				return
		end

		local portOk = false
		local tcp = SocketTcp(jnt, server_ip, server_port, "porttest")
		tcp:t_connect()
		tcp:t_addWrite(function(err)
			local res, err = tcp.t_sock:send(" ")
			if not err then
				portOk = true
			end

			if portOk then
				callback(false, 37, server_name .. " (" .. server_port .. ")")
			else
				callback(false, -37, server_name .. " (" .. server_port .. ")")
			end
			tcp:close()
		end)

		-- Wait until port test has finished
		while tcp.t_sock ~= nil do
			Task:yield()
		end

		if not portOk then
			ifObj:setNetworkResult(-37)
			return
		end

		ifObj:setNetworkResult(37)

		log:debug("checkNetworkHealth task done (full)")
	end):addTask()
end


--[[

=head2 jive.net.Networking:repairNetwork()

Attempt to repair network connction doing the following:
- Bring down the active interface - this also stops DHCP
- Disconnect from wireless network / wired network
- Bring up the active network - this also starts DHCP
- Connect to wireless network / wired network

While it's running status values are returned via
callback function. The callback provides two params:
- continue: true or false
- result: ok >= 0, nok < 0

class		- Networking class
ifObj		- network object
callback	- callback function

=cut
--]]

function repairNetwork(class, ifObj, callback)
	assert(type(callback) == 'function', "No callback function provided")

	Task("repairnetwork", ifObj, function()
		log:info("repairNetwork task started")

		-- Check for valid network interface
		if ifObj == nil then
			callback(false, -1)
			return
		end

		local active = ifObj:_ifstate()

		callback(true, 100)

		ifObj:_ifDown()

		callback(true, 102)

		ifObj:_ifUp(active)

		callback(false, 104)

		log:info("repairNetwork task done")
	end):addTask()
end


--[[

=head2 jive.net.Networking:pingServer()

Ping a server by name or ip address
Note: DNS resolution has a long timeout, especially when there is no DNS or network

--]]
function pingServer(self, serverNameOrIP)
	assert(Task:running(), "Networking:pingServer must be called in a Task")

	local ipaddr, err
	if DNS:isip(serverNameOrIP) then
		ipaddr = serverNameOrIP
	else
		ipaddr, err = DNS:toip(serverNameOrIP)
	end

	if not ipaddr then
		return false
	end

	local pingOK = false
	local pingProc = Process(jnt, "ping -c 1 -W 2 " .. ipaddr)

	pingProc:read(function(chunk)
		if chunk then
			if string.match(chunk, "bytes from") then
				pingOK = true
			end
		end
	end)

	while pingProc:status() ~= "dead" do
		Task:yield()
	end

	return pingOK
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
