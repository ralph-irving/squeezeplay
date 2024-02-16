--[[

Skin test applet.

Each window style is represented once in this applet. Every good rule needs
an exception, so multiple keyboards are included :).

To make it easier to test the following shortcuts can be used:
	jump_fwd (b) - move to next screen
	jump_rew (z) - move to previous screen
	pause (c) - take screenshot


The objective is to keep the reference code as simple as possible!

--]]

local string, ipairs, tostring = string, ipairs, tostring

local oo                  = require("loop.simple")

local Applet              = require("jive.Applet")
local Group               = require("jive.ui.Group")
local Event               = require("jive.ui.Event")
local Framework           = require("jive.ui.Framework")
local Icon                = require("jive.ui.Icon")
local Button              = require("jive.ui.Button")
local Label               = require("jive.ui.Label")
local Choice              = require("jive.ui.Choice")
local Checkbox            = require("jive.ui.Checkbox")
local RadioButton         = require("jive.ui.RadioButton")
local RadioGroup          = require("jive.ui.RadioGroup")
local Popup               = require("jive.ui.Popup")
local Keyboard            = require("jive.ui.Keyboard")
local SimpleMenu          = require("jive.ui.SimpleMenu")
local Slider              = require("jive.ui.Slider")
local Surface             = require("jive.ui.Surface")
local Textarea            = require("jive.ui.Textarea")
local Textinput           = require("jive.ui.Textinput")
local Timeinput           = require("jive.ui.Timeinput")
local Window              = require("jive.ui.Window")
local datetime            = require("jive.utils.datetime")
local jiveMain            = jiveMain

local debug               = require("jive.utils.debug")


module(..., Framework.constants)
oo.class(_M, Applet)


local windows -- defined at end
local testData -- defined at end


function _itemName(item)
	return item[2] .. " (" .. item[1] .. ")"
end


function _itemData(item)
	return testData[item[1]]
end


-- move to the next text window
function _windowNext(self, item)
	local next

	for i,anitem in ipairs(windows) do
		if item == anitem then
			next = i + 1
		end
	end

	if next > #windows then
		next = 1
	end

	windows[next][3](self, windows[next]):showInstead()
end


-- move to the next previous window
function _windowPrev(self, item)
	local prev

	for i,anitem in ipairs(windows) do
		if item == anitem then
			prev = i - 1
		end
	end

	if prev < 1 then
		prev = #windows
	end

	windows[prev][3](self, windows[prev]):showInstead()
end


-- add test actions to window
function _windowActions(self, item, window)
	window:addActionListener("jump_fwd",
		nil,
		function()
			_windowNext(self, item)
		end)

	window:addActionListener("jump_rew",
		nil,
		function()
			_windowPrev(self, item)
		end)

	window:addActionListener("pause",
		nil,
		function()
			local sw, sh = Framework:getScreenSize()
			local img = Surface:newRGB(sw, sh)

			Framework:draw(img)

			log:info("Saving ", item[1] .. ".bmp")
			img:saveBMP(item[1] .. ".bmp")
		end)
end


-- top level menu
function menu(self)
	local window = Window("text_list", "Skin Tests")

	local menu = SimpleMenu("menu")

	for i,item in ipairs(windows) do
		menu:addItem({
			text = _itemName(item),
			sound = "WINDOWSHOW",
			callback = function()
				item[3](self, item):show()
				self:showStack()
			end,
		})
	end

	window:addWidget(menu)
	self:tieAndShowWindow(window)
end


-- this is a dummy help window
function dummy_help(self)
	local window = Window("help_info", "Help")
	window:setAllowScreensaver(false)

	local textarea = Textarea("text", "This is a help window.")
	window:addWidget(textarea)
	self:tieAndShowWindow(window)
end



-- REFERENCE WINDOW STYLES ARE BELOW


--[[
Window:   "input_time"
Menu1:     "hour"
Menu2:     "minute"
Menu3:     "ampm"
--]]

function input_time(self, item)
	local data = _itemData(item)

	self.window = Window("input_time", _itemName(item))
	_windowActions(self, item, self.window)

	local submitCallback = function( hour, minute, ampm)
		log:warn(hour, ':', minute, ' ', ampm)
	end
	local timeInput = Timeinput(self.window, submitCallback)

	self:tieWindow(self.window)
	return self.window
end



--[[
Window:   "help_list"
Textarea: "help_text"
Menu:     "menu"
Item:     "item"
--]]
function setup_help_list(self, item)
	local data = _itemData(item)

	local window = Window("help_list", _itemName(item), "setup")
	_windowActions(self, item, window)

	window:addActionListener("help", self, dummy_help)
	window:setButtonAction("rbutton", "help")

	local textarea = Textarea("help_text", data[1])

	local menu = SimpleMenu("menu")
	for i,subdata in ipairs(data[2]) do
		local iconStyle = nil
		if subdata[2] then
			iconStyle = subdata[2]
		end
		log:warn(iconStyle)
		menu:addItem({
			text = subdata[1],
			iconStyle = iconStyle,
		})
	end
--	jiveMain:addHelpMenuItem(menu, self, dummy_help)

	window:addWidget(menu)
	menu:setHeaderWidget(textarea)

	self:tieWindow(window)
	return window
end


--[[
Window:   "help_info"
Textarea: "text"
--]]
function setup_help_info(self, item)
	local data = _itemData(item)

	local window = Window("help_info", _itemName(item), "setup")
	_windowActions(self, item, window)

	local textarea = Textarea("text", data[1])

	window:addWidget(textarea)

	self:tieWindow(window)
	return window
end


--[[
Popup:   "waiting_popup"
Label:    "text", "subtext"
Icon:     X
--]]
function setup_waiting_popup(self, item)
	local data = _itemData(item)

	local popup = Popup("waiting_popup")
	_windowActions(self, item, popup)

	local label = Label("text", data[1])
	local sublabel = Label("subtext", data[2])
	local icon = Icon(data[3])

	popup:addWidget(label)
	popup:addWidget(icon)
	popup:addWidget(sublabel)
	popup:focusWidget(label)

	self:tieWindow(popup)
	return popup
end


--[[
Window:    "input"
Textinput: "textinput"
Keyboard:  "keyboard"
keyboard style: method argument
--]]
function setup_input(self, item)

	local data = _itemData(item)
	
	local window = Window("input", _itemName(item), "setup")

	_windowActions(self, item, window)

	-- normal short cuts don't work with text entry
	window:addActionListener("back", nil, function()
		_windowPrev(self, item)
	end)


	local textinput = Textinput(
		"textinput", 
		data[2] or "",
		function(_, value)
			_windowNext(self, item)
		end
	)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

	window:addWidget(group)
	--window:addWidget(Keyboard("keyboard", data[1], textinput))
	window:addWidget(Keyboard("keyboard", 'foo', textinput))
	window:focusWidget(group)

	return window
end


--[[
Window:    "error"
Textarea:  "text"
Menu:      "menu"
Item:      "item"
--]]
function setup_error(self, item)
	local data = _itemData(item)

	local window = Window("error", _itemName(item), "setup")
	_windowActions(self, item, window)

	local textarea = Textarea("text", data[1])

	local menu = SimpleMenu("menu")
	for i,data in ipairs(data[2]) do
		menu:addItem({
			text = data,
		})
	end

	window:addWidget(menu)
	menu:setHeaderWidget(textarea)

	self:tieWindow(window)
	return window
end


--[[
Popup:    "update_popup"
Label:    "text"
Slider:   "progress"
Icon:     "icon_software_update"
--]]
function setup_update_popup(self, item)
	local data = _itemData(item)

	local popup = Popup("update_popup")
	_windowActions(self, item, popup)

	local label = Label("text", data[1])
	local cent = Label("subtext", "")
	local icon = Icon(data[2])
	local progress = Slider("progress", 1, 100, 1)

	local count = 1
	popup:addTimer(500, function()
		if count < 100 then
			count = count + 1
		end
		cent:setValue(count .. "%")
		progress:setRange(1, 100, count)
	end)

	popup:addWidget(label)
	popup:addWidget(icon)
	popup:addWidget(cent)
	popup:addWidget(progress)

	self:tieWindow(popup)
	return popup
end


--[[
Window:   "text_list"
Textarea: "help_text" (optional)
Menu:     "menu"
Item:     "item_play", "item_add", "item" (styles: selected, pressed, locked)
--]]
function window_track_info(self, item)
	local data = _itemData(item)

	local window = Window("text_list", _itemName(item), "home")
	_windowActions(self, item, window)

	local menu = SimpleMenu("menu")
	for i, text in ipairs(data) do
		log:warn(text)
		local itemStyle = 'item'
		self.checkMe = true
		if i == 1 then
			itemStyle = 'item_play'
			self.checkMe = false
		elseif i == 2 then
			itemStyle = 'item_add'
			self.checkMe = false
		end
		local callback 
		if self.checkMe then
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				item.style = "item_checked"
				menu:updatedItem(item)

				selected = item
			end
		else
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				selected = item
			end
		end
		menu:addItem({
			text = text,
			sound = "WINDOWSHOW",
			style = itemStyle,
			callback = callback,
		})
	end
	
	window:addWidget(menu)

	self:tieWindow(window)
	return window
end


--[[
Window:   "alarm_menu"
Menu:     "menu"
Item:     "item"
--]]
function window_alarm_popup(self, item)
	local data = _itemData(item)

	local window = Window("alarm_popup", _itemName(item), "Alarm Menu")
	_windowActions(self, item, window)

	local time = datetime:getCurrentTime()
	local icon = Icon('icon_alarm')
        local label = Label('alarm_time', time)
        local headerGroup = Group('alarm_header', {
                icon = icon,
                time = label,
        })
	local menu = SimpleMenu("menu")
	for i, text in ipairs(data[1]) do
		menu:addItem({
			text = text,
			style = 'item',
			sound = "WINDOWSHOW",
			callback = function()
				window:hide()
			end
		})
	end

	menu:setHeaderWidget(headerGroup)
	window:setButtonAction('rbutton', 'cancel')
        window:addActionListener("cancel", self, function() window:hide(Window.transitionNone) end )
	window:setButtonAction('lbutton', nil, nil)
	window:addWidget(menu)

	self:tieWindow(window)
	return window
end


--[[
Window:   "context_menu"
Menu:     "menu"
Item:     "item_play", "item_add", "item", (styles: selected, pressed, locked)
--]]
function window_context_menu(self, item)
	local data = _itemData(item)

	local window = Window("context_menu", _itemName(item), "Context Menu")
	_windowActions(self, item, window)

	-- FIXME: choice items do not work
	local menu = SimpleMenu("menu")
	for i, text in ipairs(data[1]) do
		local style = 'item'
		if i == 1 then
			style = 'item_play'
		elseif i == 2 then
			style = 'item_add'
		end
		menu:addItem({
			text = text,
			style = style,
			sound = "WINDOWSHOW",
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				item.style = "item_checked"
				menu:updatedItem(item)

				selected = item
			end
		})
	end

	window:setButtonAction('rbutton', 'cancel')
	window:setButtonAction('lbutton', nil, nil)
	window:addWidget(menu)

	self:tieWindow(window)
	return window
end

--[[
Window:   "multiline_text_list"
Menu:     "menu"
Item:     "item"
--]]
function setup_multiline_text(self, item)
	local data = _itemData(item)

	log:warn(_itemName(item))
	local window = Window("multiline_text_list", _itemName(item))
	_windowActions(self, item, window)

	local menu = SimpleMenu("menu")

	for i, textarea in ipairs(data[1]) do
		menu:addItem({
			textarea = textarea,
			style = 'item_no_arrow',
			sound = "WINDOWSHOW",
			callback = function()
				return EVENT_CONSUME
			end
		})
	end

	window:addWidget(menu)

	self:tieWindow(window)
	return window
end


--[[
Window:   "text_list"
Menu:     "menu"
Item:     "item_choice", "item", "item_checked", (styles: selected, pressed, locked)
--]]
function setup_text_list(self, item)
	local data = _itemData(item)

	local window = Window("text_list", _itemName(item), "home")
	_windowActions(self, item, window)

	-- FIXME: choice items do not work
	local menu = SimpleMenu("menu")
	local choice = Choice("choice", { 'on', 'off' },
		function(object, selectedIndex)
			log:warn('choice is: ', tostring(selectedIndex))
		end,
		1
	)
	local checkbox = Checkbox(
                        "checkbox",
                        function(_, checkboxFlag)
                                if (checkboxFlag) then
                                        log:warn("ON: ", checkboxFlag)
                                else
                                        log:warn("OFF: ", checkboxFlag)
                                end
                        end,
                        checkboxFlag == 1
	)
	local group = RadioGroup()
	local radios = {
		RadioButton(
			"radio",
			group,
			function()
				log:warn("radio button selected")
			end,
			true
		),
		RadioButton(
			"radio",
			group,
			function()
				log:warn("radio button 2 selected")
			end,
			false
		)
	}
	menu:addItem({
		text  = 'Sample Wifi Item',
		style = 'item',
		arrow  = Icon('wirelessLevel1'),
	})
	menu:addItem({
		text  = 'Sample Wifi Item',
		style = 'item',
		arrow  = Icon('wirelessLevel2'),
	})
	menu:addItem({
		text  = 'Sample Wifi Item',
		style = 'item',
		arrow  = Icon('wirelessLevel3'),
	})
	menu:addItem({
		text  = 'Sample Wifi Item',
		style = 'item',
		arrow  = Icon('wirelessLevel4'),
	})
	menu:addItem({
		text  = 'Sample Checkbox',
		style = 'item_choice',
		check  = checkbox,
	})
	menu:addItem({
		text  = 'Sample Radio 1',
		style = 'item_choice',
		check  = radios[1],
	})
	menu:addItem({
		text  = 'Sample Radio 2',
		style = 'item_choice',
		check  = radios[2],
	})
	for i, text in ipairs(data[1]) do
		log:warn(text)
		menu:addItem({
			text = text,
			sound = "WINDOWSHOW",
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				item.style = "item_checked"
				menu:updatedItem(item)

				selected = item
			end
		})
	end

	window:addWidget(menu)

	self:tieWindow(window)
	return window
end

--[[
Window:   "icon_list"
Menu:     "menu"
Item:     "item", "item_checked", (styles: selected, pressed, locked)
--]]
function window_playlist(self, item)
	local data = _itemData(item)

	local window = Window("icon_list", _itemName(item), "artists")
	_windowActions(self, item, window)

	local menu = SimpleMenu("menu")
	for i,subdata in ipairs(data) do
		menu:addItem({
			text = subdata[1],
			icon = Icon('icon_no_artwork'),
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				item.style = "item_checked"
				menu:updatedItem(item)

				selected = item
			end
		})
	end

	-- add an item for item_no_arrow and item_checked_no_arrow
	menu:addItem({
			text = "Test of no artwork",
	})
	menu:addItem({
			text  = "Clear Playlist",
	})
	menu:addItem({
			text  = "Save Playlist",
	})

	window:addWidget(menu)

	self:tieWindow(window)
	return window
end


--[[
Window:   "icon_list"
Menu:     "menu"
Item:     "item", "item_checked", (styles: selected, pressed, locked)
--]]
function window_icon_list(self, item)
	local data = _itemData(item)

	local window = Window("text_list", _itemName(item), "artists")
	_windowActions(self, item, window)

	local menu = SimpleMenu("menu")
	menu:addItem({
		text = "this is an item without an icon\njust don't add an icon in the menu item and there won't be one",
		style = 'item_info',
	})
	for i,subdata in ipairs(data) do
		menu:addItem({
			text = subdata[1],
			style = 'item_info',
			--icon = Icon('icon_no_artwork'),
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				item.style = "item_checked"
				menu:updatedItem(item)

				selected = item
			end
		})
	end

	window:addWidget(menu)

	self:tieWindow(window)
	return window
end


--[[
Window:   "information"
Textarea: "text"
--]]
function window_information(self, item)
	local data = _itemData(item)

	local window = Window("information", _itemName(item))
	_windowActions(self, item, window)

	local textarea = Textarea("text", data[1])

	window:addWidget(textarea)

	self:tieWindow(window)
	return window
end


--[[
Window:   "track_list" (with "icon" in menu bar for thumbnail)
Menu:     "menu"
1st Item: "itemplay"
Item:     "item"
--]]
function window_track_list(self, item)
	local data = _itemData(item)

	--local window = Window("track_list", _itemName(item))
	local window = Window("track_list", "Two line titles\nin track_list")
 	_windowActions(self, item, window)
 
	window:setIconWidget("icon", Icon("icon_no_artwork"))
 
	local menu = SimpleMenu("menu")
	for i, text in ipairs(data) do
		log:warn(text)
		menu:addItem({
			text = text,
			sound = "WINDOWSHOW",
			callback = function(event, item)
				if selected == item then
					menu:lock()
					return
				end

				if selected then
					selected.style = "item"
					menu:updatedItem(selected)
				end

				item.style = "item_checked"
				menu:updatedItem(item)

				selected = item
			end
		})
	end
	
	window:addWidget(menu)

	self:tieWindow(window)
	return window
end


--[[
Popup:   "toast_popup"
Group:	 "group"
  Label:   "text"
--]]
function window_toast_popup(self, item)
	local data = _itemData(item)

	local popup = Popup("toast_popup")
	_windowActions(self, item, popup)

	local group = Group("group", {
		text = Textarea("toast_popup_textarea", data[1])
		--text = Label("text", data[1])
	})

	popup:addWidget(group)

	self:tieWindow(popup)
	return popup
end

function showStack(self)
	local stack = Framework.windowStack
	for i in ipairs(stack) do
		log:warn(stack[i])
	end
end
	
--[[
Popup:   "toast_popup"
Group:	 "group"
  Label:   "text"
  Icon:    "icon"
--]]
function window_toast_popup_withicon(self, item)
	local data = _itemData(item)

	local popup = Popup("toast_popup")
	_windowActions(self, item, popup)

	local group = Group("group", {
		text = Textarea("text", data[1]),
		icon = Icon(data[2]),
	})

	popup:addWidget(group)

	self:tieWindow(popup)
	return popup
end

--[[
Popup:   "slider_popup"
Group:	 "group"
  Label:   "text"
  Icon:    "icon"
--]]
function window_slider_popup(self, item)
	local data = _itemData(item)

	local popup = Popup("slider_popup")
	_windowActions(self, item, popup)

	local title = Label("heading", data[1])

	local slider = Slider("volume_slider", -1, 100, 50)

	popup:addWidget(title)
	popup:addWidget(Icon('icon_popup_volume'))

	popup:addWidget(Group("slider_group", {
		slider = slider,
	}))

	return popup
end

--[[
Popup:   "slider_popup"
Group:	 "group"
  Label:   "text"
  Icon:    "icon"
--]]
function window_scanner_popup(self, item)
	local data = _itemData(item)

	local popup = Popup("scanner_popup")
	_windowActions(self, item, popup)

	local title = Label("heading", data[1])

	local slider = Slider("scanner_slider", -1, 100, 50)

	popup:addWidget(title)

	popup:addWidget(Group("slider_group", {
		slider = slider,
	}))

	return popup
end

--[[
Popup:   "icon_popup"
Group:	 "group"
  Label:   "text"
  Icon:    "icon"
--]]
function window_icon_popup(self, item)
	local popup = Popup("toast_popup_icon")
	local icon  = Icon("icon_popup_stop")
	_windowActions(self, item, popup)
	popup:addWidget(icon)

	return popup
end


-- REFERENCE WINDOW STYLES ARE ABOVE




-- the reference windows, and test data
windows = {
	{ "multiline_text", "Multiline Text List", setup_multiline_text, },
	{ "alarm_popup", "Alarm Menu", window_alarm_popup, },
	{ "power_down", "Power Down", setup_waiting_popup, },
	{ "input_time", "Time Input", input_time, },
	{ "update_popup", "Software Update", setup_update_popup, },
	{ "context_menu", "Context Menu", window_context_menu, },
	{ "text_list", "Text List", setup_text_list, },
	{ "help_list_one_oneline", "Setup1", setup_help_list, },
	{ "help_list_one_twoline", "Setup2", setup_help_list, },
	{ "help_list_one_threeline", "Setup3", setup_help_list, },
	{ "help_list_one_manyline", "Setupmany", setup_help_list, },
	{ "help_list_two", "Region1", setup_help_list, },
	{ "help_list_two_twoline", "Region2", setup_help_list, },
	{ "help_list_two_threeline", "Region3", setup_help_list, },
	{ "help_list_two_fourline", "Region4", setup_help_list, },
	{ "help_list_two_manyline", "Regionmany", setup_help_list, },
	{ "help_list_many", "Region (many items)", setup_help_list, },

	{ "input_ip", "IP Entry", setup_input },
	{ "input_qwerty", "QWERTY Entry", setup_input },
	{ "input_qwerty_DE", "QWERTZ Entry", setup_input },
	{ "input_qwerty_FR", "AZERTY Entry", setup_input },
	{ "input_numeric", "Number Entry", setup_input },
	{ "input_email", "Email Entry", setup_input, },
	{ "input_email_FR", "FR Email Entry", setup_input, },
	{ "input_email_DE", "DE Email Entry", setup_input, },
	{ "input_hex", "WEP Password", setup_input, },
	{ "input_wpa", "Wireless Password", setup_input, },

	{ "help_info", "Help Connection Type", setup_help_info, },
	{ "waiting_popup", "Connecting to", setup_waiting_popup, },
	{ "battery_popup", "Battery Low", setup_waiting_popup, },
	{ "restart", "Restart", setup_waiting_popup, },
	{ "error", "Error", setup_error, },
	{ "track_info", "Track Info", window_track_info, },
	{ "track_list", "Track List", window_track_list, },
	{ "playlist", "Playlist", window_playlist, },
	{ "icon_list", "Icon List", window_icon_list, },
	{ "information", "Information Window", window_information, },
	{ "toast_popup", "Popup Toast", window_toast_popup, },
	{ "toast_popup_withicon", "Popup Toast w/art", window_toast_popup_withicon, },
	{ "scanner_popup", "Song Position", window_scanner_popup, },
	{ "slider_popup", "Volume", window_slider_popup, },
	{ "icon_popup", "Icon Popup", window_icon_popup, },
}


testData = {
	input_time = {
		{ },
	},
	alarm_popup = {
		{ "Snooze", "Turn Off Alarm" },
	},
	context_menu = {
		{ "Play", "Add", "Create MusicIP Mix", "Add to Favorites", "Biography", "Album Review" },
	},
	text_list = {
		{ "Now Playing", "Music Library", "Internet Radio", "Music Services", "Favorites", "Extras", "Settings", "Choose Player", "Turn Off Player" }
	},
	multiline_text = {
		{ 
			"This is a long bunch of text for the multiline text window that should wrap to three lines to fully test this style. Multiline text windows employ textareas rather than labels for allowing word wrap on menu items. They are used for Facebook but could have applications elsewhere.",
			"This is a long bunch of text for the multiline text window that should wrap to three lines to fully test this style. Multiline text windows employ textareas rather than labels for allowing word wrap on menu items. They are used for Facebook but could have applications elsewhere.",
			"This is a long bunch of text for the multiline text window that should wrap to three lines to fully test this style. Multiline text windows employ textareas rather than labels for allowing word wrap on menu items. They are used for Facebook but could have applications elsewhere.",
			"This is a long bunch of text for the multiline text window that should wrap to three lines to fully test this style. Multiline text windows employ textareas rather than labels for allowing word wrap on menu items. They are used for Facebook but could have applications elsewhere.",
			"This is a long bunch of text for the multiline text window that should wrap to three lines to fully test this style. Multiline text windows employ textareas rather than labels for allowing word wrap on menu items. They are used for Facebook but could have applications elsewhere.",
			"This is a long bunch of text for the multiline text window that should wrap to three lines to fully test this style. Multiline text windows employ textareas rather than labels for allowing word wrap on menu items. They are used for Facebook but could have applications elsewhere.",
		}
	},
	help_list_one_oneline = {
		"Is text allowed?",
		{ { "Continue" },
		},
	},
	help_list_one_twoline = {
		"Is text allowed in thi allowed in thi allowed in thi in thi allowed in this window?",
		{ { "Continue" },
		},
	},
	help_list_one_threeline = {
		"Is text allowed in thi allow in thi allow in thi allowes sdfdsf sdf df sdf sdf sdf sdf sdf sdf sdf sdf dsfd in thi allowed in thi in thi allowed in this window?",
		{ { "Continue" },
		},
	},
	help_list_one_manyline = {
--		"Let's begin by getting\nyou connected to your network.",
	"111111111111111111111 111111111111 1 1  1 1 1 1 1 1 1  1 1 1\nFor more help and customer support, please visit \nforums.slimdevices.com.\n\nIf contacting customer support, you may be askedustomer support, you may be askedustomer sup support, you may be askedustomer sup support, you may be askedustomer sup support, you may be askedustomer sup support, you may be askedustomer sup support, you may be askedustomer sup support, you may be askedustomer support, you may be askedustomer support, you may be askedustomer support, you may be askedustomer support, you may be askedustomer support, you may be askedustomer support, you may be askedustomer support, you may be askedustomer support, you may be asked for information from\nthe \"Diagnostics\" screen, which can be found below.\nsgfsgfgsdfg",
--	"Pokud budete potřebovat další nápovědu k vašemu Squeezebox, navštivte laskavě mysqueezebox.com/support, kde naleznete odpovědi na mnoho otázek, a kontaktujte náš asistenční tým.\nPokud budete kontaktovat náš asistenční tým, můžete být požádáni o technické údaje vašeho Squeezebox poskytnuté Diagnostikou systému, dostupnou níže.",
--	"Hvis du har brug for yderligere hjælp til din Squeezebox, kan du kigge på mysqueezebox.com/support hvor der er svar på mange spørgsmål og mulighed for at kontakte supportafdelingen.\nHvis du kontakter supportafdelingen, bliver du sandsynligvis bedt om at oplyse tekniske detaljer om din Squeezebox. Dem kan du finde vha. det nye værktøj Systemdiagnosticering som der er et link til nedenfor.",
--	"Wenn Sie weitere Informationen zur Squeezebox benötigen, rufen Sie mysqueezebox.com/support auf. Dort erhalten Sie Antworten auf viele Fragen und die Möglichkeit, sich an unseren Kundendienst zu wenden.\nBei Kontaktaufnahme mit dem Kundendienst werden Sie eventuell um technische Angaben zur Squeezebox gebeten. Diese finden Sie mit einer Systemdiagnose (siehe unten).",
--	"Si necesita más ayuda con Squeezebox, visite mysqueezebox.com/support, donde encontrará respuesta a gran cantidad de preguntas y desde donde podrá ponerse en contacto con nuestro equipo de asistencia técnica.\nSi se pone en contacto con el equipo de asistencia técnica, puede que se le pida información técnica sobre Squeezebox proporcionada por Diagnóstico del sistema, disponible más abajo.",
--	"Jos tarvitset lisäohjeita Squeezeboxin käyttöön, siirry seuraavalle sivulle: mysqueezebox.com/support. Löydät sivulta vastauksia moniin kysymyksiin. Lisäksi voit ottaa sivulla yhteyttä tukitiimiimme.\nJos otat yhteyttä tukitiimiimme, sinulta saatetaan pyytää Squeezeboxia koskevia teknisiä tietoja. Saat ne järjestelmän diagnostiikasta alta.",
--	"Si vous avez besoin d'aide supplémentaire pour votre Squeezebox, rendez-vous sur le site mysqueezebox.com/support, où vous trouverez les réponses à de nombreuses questions, et contactez notre équipe d'assistance.\nLorsque vous contactez notre équipe d'assistance, vous serez invité à préciser les données techniques de la Squeezebox. Elles sont fournies par le Diagnostic système, disponible ci-dessous.",
--	"Per ottenere ulteriore assistenza relativamente a Squeezebox, consultare la pagina Web mysqueezebox.com/support, che include risposte a numerose domande e informazioni per contattare il nostro team di assistenza.\nQuando si contatta il team di assistenza, è necessario disporre delle informazioni tecniche su Squeezebox fornite dalla diagnostica del sistema, disponibile di seguito.",
--	"Als je meer hulp met je Squeezebox nodig hebt, ga dan naar mysqueezebox.com/support. Hier vind je antwoord op veel vragen en kun je contact opnemen met ons supportteam.\nAls je contact opneemt met het supportteam, kun je gevraagd worden om technische details van je Squeezebox. Deze worden geleverd door System Diagnostics (hieronder).",
--	"Gå til mysqueezebox.com/support hvis du trenger mer hjelp med Squeezebox. Her finner du svar på mange spørsmål, og du kan også kontakte støtteavdelingen.\nHvis du tar kontakt med støtteavdelingen, blir du kanskje bedt om å oppgi noen tekniske opplysninger om Squeezebox fra Systemdiagnose (se nedenfor).",
--	"Aby uzyskać więcej pomocy związanej z urządzeniem Squeezebox, odwiedź stronę WWW pod adresem mysqueezebox.com/support. Znajdują się tam odpowiedzi na wiele pytań oraz informacje, dzięki którym można skontaktować się z działem pomocy technicznej.\nPracownicy działu pomocy technicznej mogą poprosić o podanie parametrów technicznych urządzenia Squeezebox. Parametry te można sprawdzić, używając narzędzia Diagnostyka systemu, które jest dostępne poniżej.",
--	"Если вам необходима дополнительная помощь по Squeezebox, посетите\nmysqueezebox.com/support: там вы сможете найти ответы на многие вопросы, а также связаться со службой поддержки. Служба поддержки может попросить вас предоставить техническую информацию о вашем устройстве Squeezebox. Эту информацию можно извлечь с помощью программы Диагностика системы, доступной по ссылке ниже.",
--	"Om du behöver mer hjälp med Squeezebox, kan du gå till mysqueezebox.com/support där du hittar frågor och svar, och där du kan kontakta teknisk support.\nOm du kontaktar teknisk support, kanske du ombeds att ange teknisk information om din Squeezebox. Den informationen får du via Systemdiagnostik nedan.",
--]]
		{ { "Continue" },
		},
	},
	help_list_two = {
		"Is text allowed in this window?",
		{ { "North America", "region_US" },
		  { "All Other Regions" , "region_XX" },
		},
	},
	help_list_two_twoline = {
		"Is text allowed in thi allowed in thi allowed in thi in thi allowed in this window?",
		{ { "North America", "region_US" },
		  { "All Other Regions" , "region_XX" },
		},
	},
	help_list_two_threeline = {
		"Is text allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in this window?",
		{ { "North America", "region_US" },
		  { "All Other Regions" , "region_XX" },
		},
	},
	help_list_two_fourline = {
		"Is text alsdfsdf sdf dsf sdfsdf dassdf sdf sdf sd fsdf sdf dsf sdf sdf sdf sdf sdfasfsdfsdf f dsf sdf sdf lowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in this window?",
		{ { "North America", "region_US" },
		  { "All Other Regions" , "region_XX" },
		},
	},
	help_list_two_manyline = {
		"Is text asdf sd fdg sdg s dfg sdf gsd g sdf gs dfg sdf gs dfg sdf gs dfg sdf gsd fg sdf gsd fg dfsd f sdf sd fs df sdf sd f sdf sd fsd f sdf sd fs df sdflsdfsdf sdf dsf sdfsdf dassdf sdf sdf sd fsdf sdf dsf sdf sdf sdf sdf sdfasfsdfsdf f dsf sdf sdf lowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in thi allowed in this window?",
		{ { "North America", "region_US" },
		  { "All Other Regions" , "region_XX" },
		},
	},
	help_list_many = {
		"Is text allowed in this window?",
		{ { "North America", "region_US" },
		  { "All Other Regions" , "region_XX" },
		  { "Option 1" },
		  { "Option 2" },
		  { "Option 3" },
		  { "Option 4" },
		  { "Option 5" },
		},
	},
	help_info = {
		"This is some help text, in a help window. It could be very long, and may need a scrollbar.\nThe quick brown fox jumped over the lazy dog.\nForsaking monastic tradition, twelve jovial friars gave up their vocation for a questionable existence on the flying trapeze.\nSix javelins thrown by the quick savages whizzed forty paces beyond the mark.\nJaded zombies acted quaintly but kept driving their oxen forward.",
	},
	information = {
	"At this stage, we need to get your Squeezebox connected to your wireless network. To do this, you'll need to know your network name and password (if you have an open network, you won't need a password).\n\nIf you don't know your network name or password, and you have a wireless network, try one or more of the following:\n\n1. Check to see if you have them written down somewhere.\n2. Ask someone else in your home if they know them.\n3. Contact the person who set up your home network.\n4. Check your router manual.\n5. Contact your router manufacturer for assistance.\n\nNOTE: A network name is sometimes referred to as an SSID, and a password is sometimes referred to as a wireless key, or security key.\n\nIf your network does not appear on the list of wireless networks, try one or more of the following:\n\n1. Make sure the Squeezebox is within range of your wireless network.\n2. Go to your computer to make sure your network is working.\n3. If your router is configured to not broadcast your network name (SSID), select 'I don't see my network' at the bottom of the list of networks, and enter yours.\n4. Unplug your router, wait 30 seconds, and plug it back in.\n5. Refer to your router documentation or contact the manufacturer for assistance."
	},
	waiting_popup = {
		"Connecting to...", "all your base", "icon_connecting",
	},
	waiting_1line_popup = {
		"Just one main line on this screen", "all your base", "icon_connecting",
	},
	battery_popup = {
		"Battery Low", "Please Charge Me", "icon_battery_low",
	},
	power_down = {
		"Goodbye", "", "icon_power",
	},
	restart = {
		"Restarting", "", "icon_restart",
	},
	input_ip = {
		"ip",
		Textinput.ipAddressValue(""),
	},
	input_qwerty = {
		"qwerty",
	},
	input_email_DE = {
		"email_DE",
	},
	input_email_FR = {
		"email_FR",
	},
	input_qwerty_DE = {
		"qwerty_DE",
	},
	input_qwerty_FR = {
		"qwerty_FR",
	},
	input_numeric = {
		"numeric",
	},
	input_hex = {
		"hex",
		Textinput.hexValue("", 10, 10),
	},
	input_email = {
		"email",
		Textinput.textValue("", 6, 100),
	},
	input_wpa = {
		"qwerty",
		Textinput.textValue("", 8, 20),
	},
	error = {
		"DHCP Address Cannot be Found",
		{ "Try to Detect Automatically",
		  "Manually Enter IP Address",
		},
	},
	update_popup = {
		"Downloading", "icon_software_update",
	},
	track_info = {
		"Play this song",
		"Add this song",
		"Artist: Sun Kil Moon",
		"Album: April",
		"Genre: No Genre",
		"Year: 2008",
		"Comment",
	},
	icon_list = {
		{ "Something" }, 
		{ "Something Else" },
		{ "More Somethings" },
		{ "Another Something" },
		{ "How many somethings does it take to screw in a light bulb" },
	},
	track_list = {
		 "1. Something", 
		 "2. Something Else",
		 "3. More Somethings",
		 "4. Another Something",
		 "5. How many somethings does it take to screw in a light bulb",
		 "Add to Favorites",
	},
	playlist = {
		{ "Something\nThe Somethings - Greatest Hits" }, 
		{ "In Our Bedroom After The War\nStars - In Our Bedroom After The War" },
		{ "3121\nPrince - Some Very Long Album Title That Goes off Screen" },
		{ "Something\nThe Somethings - Greatest Hits" }, 
		{ "In Our Bedroom After The War\nStars - In Our Bedroom After The War" },
		{ "3121\nPrince - Some Very Long Album Title That Goes off Screen" },
	},
	toast_popup = {
		"Your toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information\nYour toast_popup is done\nline 2 has more information",
		--"Your toast_popup is done\nline 2 has more information",
	},
	toast_popup_withicon = {
		"United States. A country of central and northwest North America with coastlines on the Atlantic and Pacific oceans.",
		"region_US",
	},
	slider_popup = {
		"Volume",
	},
	scanner_popup = {
		"3:16",
	},
}
