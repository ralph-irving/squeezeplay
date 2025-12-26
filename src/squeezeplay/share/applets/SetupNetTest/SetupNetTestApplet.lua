
--[[
=head1 NAME

SetupNetTest Applet

=head1 DESCRIPTION

Test the network bandwidth between SqueezeCenter and a Player

=cut
--]]

-- stuff we use
local pairs, ipairs, tonumber, tostring, type = pairs, ipairs, tonumber, tostring, type

local oo            = require("loop.simple")
local table         = require("table")
local string        = require("string")

local Applet        = require("jive.Applet")

local Framework     = require("jive.ui.Framework")
local SimpleMenu    = require("jive.ui.SimpleMenu")
local Window        = require("jive.ui.Window")
local Textarea      = require("jive.ui.Textarea")
local Label         = require("jive.ui.Label")
local Button        = require("jive.ui.Button")
local RadioButton   = require("jive.ui.RadioButton")
local RadioGroup    = require("jive.ui.RadioGroup")
local Surface       = require("jive.ui.Surface")
local Icon          = require("jive.ui.Icon")
local Popup         = require("jive.ui.Popup")
local Timer         = require("jive.ui.Timer")
local ContextMenuWindow = require("jive.ui.ContextMenuWindow")

local debug         = require("jive.utils.debug")

local appletManager    = appletManager

module(..., Framework.constants)
oo.class(_M, Applet)

local scroll = 2

local bground = 0x808080FF
local graphBG = 0x303040FF
local graphFG = 0x808080FF
local graphR  = 0x800000FF
local graphA  = 0x808000FF
local graphG  = 0x008000FF

-- open window
function open(self, menuItem)

	-- find a server: server for current player, else first server
	self.player = appletManager:callService("getCurrentPlayer")
	if self.player then
		self.server = self.player:getSlimServer()
	end

	local sw, sh = Framework:getScreenSize()
	local edge = (sw - 200) / 2

	self.window = Window("nettest", self:string('SETUPNETTEST_TESTING'))
	self.window:setSkin({
		nettest = {
			icon = {
				padding = { edge, 3, edge, 1 }
			},
			graphtitle = {
				padding = { edge, 7, 0, 0 },
				fg = { 0xE7, 0xE7, 0xE7 }
			},
			graphaxis = {
				padding = { edge, 1, 0, 0 },
				fg = { 0xE7, 0xE7, 0xE7 }
			}
		}
	})

	local title = Button(Label("textButton", self:string('SETUPNETTEST_TESTING')), function() self:showContextMenu() end)
	self.window:setIconWidget("text", title)
	self:tieAndShowWindow(self.window)

	local timer = Timer(1000, function() self.window:addWidget(Textarea("text", self:string('SETUPNETTEST_NOSERVER'))) end, true)
	timer:start()

	self:requestStatus(function() timer:stop() self:showMainWindow() end)
end


function showMainWindow(self)
	self.window:addWidget(Label("graphtitle", self:string('SETUPNETTEST_CURRENT')))
	local sw, sh = Framework:getScreenSize()

	local graphHeight =  sh / 7
	self.graph1 = Surface:newRGBA(200, graphHeight)
	self.graph1:filledRectangle(0, 0, 200, graphHeight, graphBG)
	local icon1 = Icon("icon", self.graph1)
	self.window:addWidget(icon1)
	self.window:addWidget(Label("graphtitle", self:string('SETUPNETTEST_HISTORY')))

	self.graph2 = Surface:newRGBA(200, graphHeight)
	self.graph2:filledRectangle(0, 0, 200, graphHeight, graphBG)
	local icon2 = Icon("icon", self.graph2)
	self.window:addWidget(icon2)
	self.window:addWidget(Label("graphaxis", "0                                         100 %"))

	self.window:addWidget(Textarea("help_text", tostring(self:string('SETUPNETTEST_TESTINGTO')) .. ' ' .. self.player:getName() .. "\n" .. tostring(self:string('SETUPNETTEST_INFO'))))

	-- No screensaver. Title bar right hand button is 'help'.
	self.window:setAllowScreensaver(false)
	self.window:setButtonAction("rbutton", "help")

	self.window:focusWidget(nil)
	self.window:addActionListener("add", self, _event_handler)
	self.window:addActionListener("go", self, _event_handler)
	self.window:addActionListener("help", self, _event_handler)
	self.window:addListener(EVENT_SCROLL | EVENT_IR_ALL,
		function(event)
			return _event_handler(self, event)
		end
	)

	self.timer = Timer(1000, function() self:requestStatus(response) end)
	self.timer:start()
end


function _event_handler(self, event)

	if self.rates == nil or #self.rates == 0 then
		return
	end

	local type = event:getType()

	if type == EVENT_SCROLL or 
		(type == EVENT_IR_DOWN and (event:isIRCode("arrow_up") or event:isIRCode("arrow_down"))) then
		local rate = self.rate or 0
		local index = self.index[rate] or 1

		if (type == EVENT_SCROLL and event:getScroll() > 0) or (type == EVENT_IR_DOWN and event:isIRCode("arrow_down")) then
			if index < #self.rates then index = index + 1 end
		else
			if index > 1 then index = index - 1 end
		end

		self:startTest(self.rates[index])

		return EVENT_CONSUME
	end

	if type == ACTION then
		local action = event:getAction()

		if action == "add" then
			-- start test at last running rate
			if self.rate then
				self:startTest(self.rate)
			end
		end
		if action == "go" or action == "help" then
			self:showHelpWindow()
		end

		return EVENT_CONSUME
	end

	if type == EVENT_IR_DOWN and event:isIRCode("arrow_right") then
		self:showHelpWindow()
		return EVENT_CONSUME
	end

	return EVENT_UNUSED
end


function showHelpWindow(self)
	local window = Window("text_list", self:string('SETUPNETTEST_HELPTITLE'))
	local help = Textarea("text", self:string('SETUPNETTEST_HELP'))

	-- No screensaver & title bar right hand button.
	window:setAllowScreensaver(false)
	window:setButtonAction("rbutton", nil)

	window:addWidget(help)
	
	self:tieAndShowWindow(window)

	return window
end


function showContextMenu(self)
	local window = ContextMenuWindow(self:string('SETUPNETTEST_TESTING'))
	local menu = SimpleMenu("menu")
	local group = RadioGroup()
	
	for index, rate in ipairs(self.rates) do
		menu:addItem({ 
			text  = rate .. " kbps",
			style = 'item_choice',
			check = RadioButton("radio",
								group,
								function(_, isSelected)
									self:startTest(rate)
								end,
								rate == self.rate
					)
		})
	end

	menu:addItem({
		text = self:string('SETUPNETTEST_INFO'),
		callback = function()
					   self:showHelpWindow()
				   end
	})

	window:addWidget(menu)
	self:tieAndShowWindow(window)
end


-- request status
function requestStatus(self, sink)

	-- do we need the list of rates ?
	local query = ''
	if self.rates == nil or #self.rates == 0 then
		query = 'rates'
	end

	self.server:userRequest(
		function(chunk, err)
			if err then
				log:debug(err)
			elseif chunk then
				sink(self, chunk.data)
			end
		end,
		self.player:getId(),
		{ 'nettest', query }
	)
end


-- sink to process response
function response(self, data)

	if data.rates_loop then
		local index = 1
		self.rates = {}
		self.index = {}
		for _,entry in pairs(data.rates_loop) do
			for k, v in pairs(entry) do
				if tonumber(v) then -- self.rates & self.index tables *must* be numeric
					self.rates[index] = tonumber(v)
					self.index[tonumber(v)] = index
					index = index + 1
				end
			end
		end
		self.default = tonumber(data.default)
	end

	if data.state == 'running' then
		-- update display for current test
		self.rate = tonumber(data.rate)
		self.window:setTitle(tostring(self:string('SETUPNETTEST_TESTING')) .. ' ' .. data.rate .. " kbps")
		self:graph1Update(data.inst)
		self:graph2Update(data.distrib)
		Framework:reDraw(nil)

	-- only autostart once, in case of failure 
	elseif self.default and not self.autostarted then
		self:startTest(self.default)
		self.autostarted = true
	end
end


function startTest(self, rate)
	self.server:userRequest(nil, self.player:getId(), { 'nettest', 'start', rate })
	self.timer.callback()
	self.timer:restart()
end


function stopTest(self)
	self.server:userRequest(nil, self.player:getId(), { 'nettest', 'stop' })
end


function graph1Update(self, val)
	local graph = self.graph1
	local w, h = graph:getSize()

	graph:blitClip(scroll, 0, w - scroll, h, graph, 0, 0)
	graph:filledRectangle(w - scroll, 0, w, h, graphBG)
	graph:filledRectangle(w - scroll, h - (val * h / 100), w, h, graphFG)
end


function graph2Update(self, distrib)
	local graph = self.graph2
	local w, h = graph:getSize()

	graph:filledRectangle(0, 0, w, h, graphBG)

	local bar = w / #distrib
	local count = 0

	for i, res in ipairs(distrib) do
		for k, v in pairs(res) do
			count = count + v
		end
	end

	if count == 0 then return end

	for i, res in ipairs(distrib) do
		for k, v in pairs(res) do
			k = tonumber(k) or 100
			local color
			if     k > 95 then color = graphG
			elseif k > 80 then color = graphA
			else   color = graphR
			end
			graph:filledRectangle((i-1) * bar, h - (v / count * 100), i * bar - 2, h, color)
		end
	end
end


function free(self)
	self.timer:stop()
	self:stopTest()

	return true
end

