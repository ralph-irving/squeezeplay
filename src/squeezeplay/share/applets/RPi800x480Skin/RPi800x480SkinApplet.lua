--[[
=head1 NAME

applets.RPi800x480Skin.RPi800x480SkinApplet

=head1 DESCRIPTION

This skin was developed for use with the Raspbery Pi 800x480 Touchscreen but will work with any 800x480 monitor or on the desktop and looks nice on desktops with high DPI.
   
This skin was built upon the the work of pssc, 3guk, Tarkan Akdam, Justblair and birdslikewires.co.uk using the following:
   
Squeezeplay-800x480 skin by pssc and 3guk (https://github.com/pssc/Squeezeplay-800x480Skin),

which was forked from the JoggleSkin (3guk/Joggler-Squeezeplayer),
   
which was redesigned from WQVGAsmallSkin by Andy Davison.

  
This skin uses a larger font size for readability, updated clock for 800x480 resolution, change to popup windows, updated time input (requires updated Timeinput applet to resolve issue with number "jumping" when selecting time and am/pm), and new nowplaying screens (requires new VUMeterNew.lua and VUMeterBar.lua). The changes to the visualizers also requires an updated NowPlaying applet. In addition, changes in NowPlaying alter the default behavior of the elpased and remaining time for "large" and "small" to a mm:ss or hh:mm format. -yobnoc

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
SqueezeboxSkin overrides the following methods:

=cut
--]]


local ipairs, pairs, setmetatable, type, tostring = ipairs, pairs, setmetatable, type, tostring

local oo                     = require("loop.simple")

local Applet                 = require("jive.Applet")
local Audio                  = require("jive.ui.Audio")
local Font                   = require("jive.ui.Font")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Surface                = require("jive.ui.Surface")
local Textarea               = require("jive.ui.Textarea")
local Tile                   = require("jive.ui.Tile")
local Window                 = require("jive.ui.Window")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")
local autotable              = require("jive.utils.autotable")
local Keyboard		     = require("jive.ui.Keyboard")

local log                    = require("jive.utils.log").logger("applet.RPi800x480Skin")

local EVENT_ACTION           = jive.ui.EVENT_ACTION
local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_WINDOW_POP       = jive.ui.EVENT_WINDOW_POP
local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE
local LAYER_TITLE            = jive.ui.LAYER_TITLE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local WH_FILL                = jive.ui.WH_FILL

local jiveMain               = jiveMain
local appletManager          = appletManager



module(..., Framework.constants)
oo.class(_M, Applet)


-- Define useful variables for this skin
local imgpath = "applets/RPi800x480Skin/images/"
local fontpath = "fonts/"
local FONT_NAME = "FreeSans"
local BOLD_PREFIX = "Bold"

-- change to either hide or show volume control. Usefull for systems with fixed audio out where the volume is controlled by an external amp.
local controlWidth = 74 -- normal
--local controlWidth = 160  -- 74 normal, no volume control use 160
local vc_order = { 'rew', 'div1', 'play', 'div2', 'fwd', 'div3', 'repeatMode', 'div4', 'shuffleMode', 'div5', 'volDown', 'div6', 'volSlider', 'div7', 'volUp' } -- normal
--local vc_order = { 'rew', 'div1', 'play', 'div2', 'fwd', 'div3', 'repeatMode', 'div4', 'shuffleMode'} -- hide volume control


function init(self)
	self.images = {}

	self.imageTiles = {}
	self.hTiles = {}
	self.vTiles = {}
	self.tiles = {}
end


function param(self)
        return {
		THUMB_SIZE = 40,
		THUMB_SIZE_MENU = 40,	
		NOWPLAYING_MENU = false, --changed by justblair
		-- NOWPLAYING_TRACKINFO_LINES used in assisting scroll behavior animation on NP
		-- 3 is for a three line track, artist, and album (e.g., SBtouch)
		-- 2 is for a two line track, artist+album (e.g., SBradio, SBcontroller)
		NOWPLAYING_TRACKINFO_LINES = 3,
		POPUP_THUMB_SIZE = 100,
		
		nowPlayingScreenStyles = { 
			-- every skin needs to start off with a nowplaying style
			{
				style = 'nowplaying', 
				artworkSize = '300x300',
				text = self:string("ART_AND_TEXT"),
			},
			{
				style = 'nowplaying_large_art', 
				artworkSize = '480x480',
				text = self:string("LARGE_ART_AND_TEXT"),
			},
                        {
				style = 'nowplaying_art_only',
				artworkSize = '480x480',
				suppressTitlebar = 1,
				text = self:string("ART_ONLY"),
			},
			{
				style = 'nowplaying_text_only',
				artworkSize = '300x300',
				text = self:string("TEXT_ONLY"),
			},
			{
				style = 'nowplaying_vubar_new_text',
				artworkSize = '300x300',
				localPlayerOnly = 1,
				text = self:string("TEXT_VU_BAR"),
			},
                        {
				style = 'nowplaying_spectrum_text',
				artworkSize = '300x300',
				localPlayerOnly = 1,
				text = self:string("SPECTRUM_ANALYZER"),
			},
			{
				style = 'nowplaying_vuanalog_new_text',
				artworkSize = '300x300',
				localPlayerOnly = 1,
				text = self:string("ANALOG_VU_METER"),
			},
                        
		},
        }
end

local function _loadImage(self, file)
	return Surface:loadImage(imgpath .. file)
end


local function _buildTileKey(tileTable)
	local key = ""
	for i = 1, #tileTable do
		local element = tileTable[i] or "NIL"
		key = key .. element .. "&"
	end

	return key
end

local function _loadTile(self, tileTable)
	if not tileTable then
		return nil
	end

	local key = _buildTileKey(tileTable)


	if not self.tiles[key] then
		self.tiles[key] = Tile:loadTiles(tileTable)
	end

	return self.tiles[key]
end


local function _loadHTile(self, tileTable)
	if not tileTable then
		return nil
	end

	local key = _buildTileKey(tileTable)

	if not self.hTiles[key] then
		self.hTiles[key] = Tile:loadHTiles(tileTable)
	end

	return self.hTiles[key]
end


local function _loadVTile(self, tileTable)
	if not tileTable then
		return nil
	end

	local key = _buildTileKey(tileTable)

	if not self.vTiles[key] then
		self.vTiles[key] = Tile:loadVTiles(tileTable)
	end

	return self.vTiles[key]
end


local function _loadImageTile(self, file)
	if not file then
		return nil
	end

	return Tile:loadImage(file)
end


-- define a local function to make it easier to create icons.
local function _icon(x, y, img)
	local var = {}
	var.x = x
	var.y = y
	var.img = _loadImage(self, img)
	var.layer = LAYER_FRAME
	var.position = LAYOUT_SOUTH

	return var
end

-- define a local function that makes it easier to set fonts
local function _font(fontSize)
	return Font:load(fontpath .. FONT_NAME .. ".ttf", fontSize)
end

-- define a local function that makes it easier to set bold fonts
local function _boldfont(fontSize)
	return Font:load(fontpath .. FONT_NAME .. BOLD_PREFIX .. ".ttf", fontSize)
end

-- defines a new style that inherrits from an existing style
local function _uses(parent, value)
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


-- skin
-- The meta arranges for this to be called to skin the interface.
function skin(self, s)
	Framework:setVideoMode(800, 480, 0, jiveMain:isFullscreen())

	local screenWidth, screenHeight = Framework:getScreenSize()

	log:info(self," Skin Screen ",screenWidth,"x",screenHeight," Full:",jiveMain:isFullscreen())

	--init lastInputType so selected item style is not shown on skin load
	Framework.mostRecentInputType = "mouse"

	-- skin
	local thisSkin = 'touch'
	local skinSuffix = "_" .. thisSkin .. ".png"

	-- Images and Tiles
	local inputTitleBox           = _loadImageTile(self,  imgpath .. "Titlebar/titlebar.png" )
	local backButton              = _loadImageTile(self,  imgpath .. "Icons/icon_back_button_tb.png")
	local cancelButton            = _loadImageTile(self,  imgpath .. "Icons/icon_close_button_tb.png")
	local homeButton              = _loadImageTile(self,  imgpath .. "Icons/icon_home_button_tb.png")
	local helpButton              = _loadImageTile(self,  imgpath .. "Icons/icon_help_button_tb.png")
	local powerButton             = _loadImageTile(self,  imgpath .. "Icons/icon_power_button_tb.png")
	local nowPlayingButton        = _loadImageTile(self,  imgpath .. "Icons/icon_nplay_button_tb.png")
	local playlistButton          = _loadImageTile(self,  imgpath .. "Icons/icon_nplay_list_tb.png")
	local moreButton              = _loadImageTile(self,  imgpath .. "Icons/icon_more_tb.png")
	local touchToolbarBackground  = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_tch_bkgrd.png")
	local sliderBackground        = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_lrg.png")
	local touchToolbarKeyDivider  = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_divider.png")
	local deleteKeyBackground     = _loadImageTile(self,  imgpath .. "Buttons/button_delete_text_entry.png")
	local deleteKeyPressedBackground = _loadImageTile(self,  imgpath .. "Buttons/button_delete_text_entry_press.png")
        local helpTextBackground  = _loadImageTile(self, imgpath .. "Titlebar/tbar_dropdwn_bkrgd.png")


	local nocturneWallpaper = _loadImageTile(self, imgpath .. "wallpaper/speckle_nocturne.png")

	--FIXME, _r asset here doesn't work...it's supposed to have a fadeout effect and it doesn't appear on screen
	local fiveItemBox             = _loadHTile(self, {
		 imgpath .. "5_line_lists/tch_5line_divider_l.png",
		 imgpath .. "5_line_lists/tch_5line_divider.png",
		 imgpath .. "5_line_lists/tch_5line_divider_r.png",
	})
	local fiveItemSelectionBox    = _loadHTile(self, {
		 imgpath .. "5_line_lists/menu_sel_box_5line_l.png", --added
		 imgpath .. "5_line_lists/menu_sel_box_5line.png",
		 imgpath .. "5_line_lists/menu_sel_box_5line_r.png",
	})
	local fiveItemPressedBox      = _loadHTile(self, {
		 imgpath .. "5_line_lists/menu_sel_box_5line_press_l.png",--added
		 imgpath .. "5_line_lists/menu_sel_box_5line_press.png",
		 imgpath .. "5_line_lists/menu_sel_box_5line_press_r.png",
	})

	local threeItemSelectionBox            = _loadHTile(self, {
		 imgpath .. "3_line_lists/menu_sel_box_3line_l.png",
		 imgpath .. "3_line_lists/menu_sel_box_3line.png",
		 imgpath .. "3_line_lists/menu_sel_box_3line_r.png",
	})
	local threeItemPressedBox = _loadImageTile(self, imgpath .. "3_line_lists/menu_sel_box_3item_press.png")
	
	local contextMenuPressedBox    = _loadTile(self, {
		imgpath .. "Popup_Menu/button_cm_press.png",
		imgpath .. "Popup_Menu/button_cm_tl_press.png",
		imgpath .. "Popup_Menu/button_cm_t_press.png",
		imgpath .. "Popup_Menu/button_cm_tr_press.png",
		imgpath .. "Popup_Menu/button_cm_r_press.png",
		imgpath .. "Popup_Menu/button_cm_br_press.png",
		imgpath .. "Popup_Menu/button_cm_b_press.png",
		imgpath .. "Popup_Menu/button_cm_bl_press.png",
		imgpath .. "Popup_Menu/button_cm_l_press.png",
	})
	
	local keyTopLeft = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_tl.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_t.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_l.png",
	})

	local keyTopLeftPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_n_button_press.png",
		imgpath .. "Buttons/keybrd_nw_button_press_tl.png",
		imgpath .. "Buttons/keybrd_n_button_press_t.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keybrd_nw_button_press_l.png",
	})

	local keyTop = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_t_wvert.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyTopPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_n_button_press.png",
		nil,
		imgpath .. "Buttons/keybrd_n_button_press_t.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyTopRight = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_t_wvert.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_tr.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_r.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyTopRightPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_n_button_press.png",
		nil,
		imgpath .. "Buttons/keybrd_n_button_press_t.png",
		imgpath .. "Buttons/keybrd_ne_button_press_tr.png",
		imgpath .. "Buttons/keybrd_ne_button_press_r.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyLeft = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardLeftEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_l.png",
	})

	local keyLeftPressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keyboard_button_press.png",
	})

	local keyMiddle = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyMiddlePressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local sliderButtonPressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyRight = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardRightEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_r.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyRightPressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		nil,
		nil,
	})

	local keyBottomLeft = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardLeftEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_b.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_bl.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_l.png",
	})

	local keyBottomLeftPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_s_button_press.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardLeftEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keybrd_s_button_press_b.png",
		imgpath .. "Buttons/keybrd_sw_button_press_bl.png",
		imgpath .. "Buttons/keybrd_sw_button_press_l.png",
	})

	local keyBottom = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_b_wvert.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyBottomPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_s_button_press.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keybrd_s_button_press_b.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyBottomRight = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardRightEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_r.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_br.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_b_wvert.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyBottomRightPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_s_button_press.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardRightEdge.png",
		imgpath .. "Buttons/keybrd_se_button_press_r.png",
		imgpath .. "Buttons/keybrd_se_button_press_br.png",
		imgpath .. "Buttons/keybrd_s_button_press_b.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local titleBox                =
		_loadTile(self, {
				 imgpath .. "Titlebar/titlebar.png",
				 nil,
				 nil,
				 nil,
				 nil,
				 nil,
				 imgpath .. "Titlebar/titlebar_shadow.png",
				 nil,
				 nil,
		})

	local textinputBackground     = 
		_loadTile(self, {
				 imgpath .. "Text_Entry/Keyboard_Touch/titlebar_box.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_tl.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_t.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_tr.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_r.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_br.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_b.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_bl.png",
				 imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_l.png",
				})

	local pressedTitlebarButtonBox =
		_loadTile(self, {
					imgpath .. "Buttons/button_titlebar_press.png",
					imgpath .. "Buttons/button_titlebar_tl_press.png",
					imgpath .. "Buttons/button_titlebar_t_press.png",
					imgpath .. "Buttons/button_titlebar_tr_press.png",
					imgpath .. "Buttons/button_titlebar_r_press.png",
					imgpath .. "Buttons/button_titlebar_br_press.png",
					imgpath .. "Buttons/button_titlebar_b_press.png",
					imgpath .. "Buttons/button_titlebar_bl_press.png",
					imgpath .. "Buttons/button_titlebar_l_press.png",
				})

	local titlebarButtonBox = 
		_loadTile(self, {
					imgpath .. "Buttons/button_titlebar.png",
					imgpath .. "Buttons/button_titlebar_tl.png",
					imgpath .. "Buttons/button_titlebar_t.png",
					imgpath .. "Buttons/button_titlebar_tr.png",
					imgpath .. "Buttons/button_titlebar_r.png",
					imgpath .. "Buttons/button_titlebar_br.png",
					imgpath .. "Buttons/button_titlebar_b.png",
					imgpath .. "Buttons/button_titlebar_bl.png",
					imgpath .. "Buttons/button_titlebar_l.png",
				})

	local popupBox = 
		_loadTile(self, {
				       imgpath .. "Popup_Menu/popup_box.png",
				       imgpath .. "Popup_Menu/popup_box_tl.png",
				       imgpath .. "Popup_Menu/popup_box_t.png",
				       imgpath .. "Popup_Menu/popup_box_tr.png",
				       imgpath .. "Popup_Menu/popup_box_r.png",
				       imgpath .. "Popup_Menu/popup_box_br.png",
				       imgpath .. "Popup_Menu/popup_box_b.png",
				       imgpath .. "Popup_Menu/popup_box_bl.png",
				       imgpath .. "Popup_Menu/popup_box_l.png",
			       })

	local contextMenuBox = popupBox -- change to be same as popup, i.e. removed "cm_" prefix from file name
	
        local contextMenuAlarm = 
        	_loadTile(self, {
				       imgpath .. "Popup_Menu/cm_popup_box.png", 
				       imgpath .. "Popup_Menu/cm_popup_box_tl.png",
				       imgpath .. "Popup_Menu/cm_popup_box_t.png",
				       imgpath .. "Popup_Menu/cm_popup_box_tr.png",
				       imgpath .. "Popup_Menu/cm_popup_box_r.png",
				       imgpath .. "Popup_Menu/cm_popup_box_br.png",
				       imgpath .. "Popup_Menu/cm_popup_box_b.png",
				       imgpath .. "Popup_Menu/cm_popup_box_bl.png",
				       imgpath .. "Popup_Menu/cm_popup_box_l.png",
			       })

	local scrollBackground = 
		_loadVTile(self, {
					imgpath .. "Scroll_Bar/scrollbar_bkgrd_t.png",
					imgpath .. "Scroll_Bar/scrollbar_bkgrd.png",
					imgpath .. "Scroll_Bar/scrollbar_bkgrd_b.png",
			       })

	local scrollBar = 
		_loadVTile(self, {
					imgpath .. "Scroll_Bar/scrollbar_body_t.png",
					imgpath .. "Scroll_Bar/scrollbar_body.png",
					imgpath .. "Scroll_Bar/scrollbar_body_b.png",
			       })

	local popupBackground = Tile:fillColor(0x000000ff) 

	local textinputCursor = _loadImageTile(self, imgpath .. "Text_Entry/Keyboard_Touch/tch_cursor.png")

	local THUMB_SIZE = self:param().THUMB_SIZE
	
	local TITLE_PADDING  = { 0, 0, 0, 0 } 
	local CHECK_PADDING  = { 2, 0, 6, 0 }
	local CHECKBOX_RADIO_PADDING  = { 2, 0, 0, 0 }

	local MENU_ITEM_ICON_PADDING = { 0, 3, 8, 0 } -- added 1 to shift icons down so they don't show up in bottom of screen when scrolling
	local MENU_PLAYLISTITEM_TEXT_PADDING = { 16, 1, 9, 1 } 

	local MENU_CURRENTALBUM_TEXT_PADDING = { 6, 20, 0, 10 }
	local TEXTAREA_PADDING = { 14, 8, 8, 0 } 

	local TEXT_COLOR = { 0xE7, 0xE7, 0xE7 }
	local TEXT_COLOR_BLACK = { 0x00, 0x00, 0x00 }
	local TEXT_SH_COLOR = { 0x37, 0x37, 0x37 }
	local TEXT_COLOR_TEAL = { 0, 0xbe, 0xbe }
        local TEXT_COLOR_TIME_VIS = { 0x96, 0x96, 0x96 }

	local SELECT_COLOR = { 0xE7, 0xE7, 0xE7 }
	local SELECT_SH_COLOR = { }

	local TITLE_HEIGHT = 65
	local TITLE_FONT_SIZE = 40 
	local ALBUMMENU_FONT_SIZE = 28 
	local ALBUMMENU_SMALL_FONT_SIZE = 18 
	local TEXTMENU_FONT_SIZE = 34 -- text in main menu and submenu lists
	local POPUP_TEXT_SIZE_1 = 36  
	local POPUP_TEXT_SIZE_2 = 36 
	local TRACK_FONT_SIZE = 24 
	local TEXTAREA_FONT_SIZE = 36 -- sets the text size in the popup menues (such as play) 
	local CENTERED_TEXTAREA_FONT_SIZE = 36 -- should be the same as above otheriwse the lines of text are not the same in popup

	local CM_MENU_HEIGHT = 47-- scoll bar height in popup window

	local TEXTINPUT_FONT_SIZE = 48 
	local TEXTINPUT_SELECTED_FONT_SIZE = 44 

	local HELP_FONT_SIZE = 22 
	local UPDATE_SUBTEXT_SIZE = 22 

	local ITEM_ICON_ALIGN   = 'center'
	local ITEM_LEFT_PADDING = 12
	local THREE_ITEM_HEIGHT = 51
	local FIVE_ITEM_HEIGHT = 51 -- changed size of images in 5_line folder to match
	local TITLE_BUTTON_WIDTH = 76

	local smallSpinny = {
		img = _loadImage(self, "Alerts/wifi_connecting_sm.png"),
		frameRate = 8,
		padding = 0,
		h = WH_FILL,
	}
	local largeSpinny = {
		img = _loadImage(self, "Alerts/wifi_connecting.png"),
		position = LAYOUT_CENTER,
		w = WH_FILL,
		align = "center",
		frameRate = 8,
		frameWidth = 180, -- (rescaled image)
                padding = { 0, 0, 0, 10 }
	}
	-- convenience method for removing a button from the window
	local noButton = { 
		img = false, 
		bgImg = false, 
		w = 0 
	}

	local playArrow = { 
		img = _loadImage(self, "Icons/selection_play_3line_on.png"),
	}
	local addArrow  = { 
		img = _loadImage(self, "Icons/selection_add_3line_off.png"),
	}


	--------- CONSTANTS ---------

	local _progressBackground = _loadImageTile(self, imgpath .. "Alerts/alert_progress_bar_bkgrd.png")

	local _progressBar = _loadHTile(self, {
		nil,
		imgpath .. "Alerts/alert_progress_bar_body.png",
	})

	local _songProgressBackground = _loadHTile(self, {
		imgpath .. "Song_Progress_Bar/SP_Bar_Touch/tch_progressbar_bkgrd_l.png",
		imgpath .. "Song_Progress_Bar/SP_Bar_Touch/tch_progressbar_bkgrd.png",
		imgpath .. "Song_Progress_Bar/SP_Bar_Touch/tch_progressbar_bkgrd_r.png",
	})

	local _songProgressBar = _loadHTile(self, {
			nil,
			nil,
			imgpath .. "Song_Progress_Bar/SP_Bar_Touch/tch_progressbar_slider.png"
	})

	local _songProgressBarDisabled = _loadHTile(self, {
			nil,
			nil,
			imgpath .. "Song_Progress_Bar/SP_Bar_Remote/rem_progressbar_slider.png"
	})

	local _vizProgressBar = _loadHTile(self, {
			imgpath .. "UNOFFICIAL/viz_progress_fill_l.png",
			imgpath .. "UNOFFICIAL/viz_progress_fill.png",
			imgpath .. "UNOFFICIAL/viz_progress_fill_r.png",
	})
	local _vizProgressBarPill = _loadImageTile(self, imgpath .. "UNOFFICIAL/viz_progress_slider.png")

	local _volumeSliderBackground = _loadHTile(self, {
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_l.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_r.png",
	})

	local _volumeSliderBar = _loadHTile(self, {
               imgpath .. "UNOFFICIAL/tch_volumebar_fill_l.png",
               imgpath .. "UNOFFICIAL/tch_volumebar_fill.png",
               imgpath .. "UNOFFICIAL/tch_volumebar_fill_r.png",
	})
	
	local _volumeSliderPill = _loadImageTile(self, imgpath .. "Touch_Toolbar/tch_volume_slider.png")

	local _popupSliderBar = _loadHTile(self, {
		imgpath .. "Touch_Toolbar/tch_volumebar_fill_l.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_fill.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_fill_r.png",
        })

--------- DEFAULT WIDGET STYLES ---------
	--
	-- These are the default styles for the widgets 

	s.window = {
		w = screenWidth,
		h = screenHeight,
	}

	-- window with absolute positioning
	s.absolute = _uses(s.window, {
		layout = Window.noLayout,
	})

	s.popup = _uses(s.window, {
		border = { 0, 0, 0, 0 },
		bgImg = popupBackground,
	})

	s.title = {
		h = TITLE_HEIGHT,
		border = 0,
		position = LAYOUT_NORTH,
		bgImg = titleBox,
		padding = { 0, 5, 0, 5 },
		order = { "lbutton", "text", "rbutton" },
		lbutton = {
			border = { 8, 0, 8, 0 },
			h = WH_FILL,
		},
		rbutton = {
			border = { 8, 0, 8, 0 },
			h = WH_FILL,
		},
		text = {
			w = WH_FILL,
			padding = TITLE_PADDING,
			align = "center",
			font = _boldfont(TITLE_FONT_SIZE),
			fg = TEXT_COLOR,
		}
	}

	s.title.textButton = _uses(s.title.text, {
		bgImg = false, --removed to give consitent look
		padding = { 4, 15, 4, 15 },
	})

	s.title.pressed = {}
	s.title.pressed.textButton = _uses(s.title.textButton, {
		bgImg = false, --removed to give consitent look
	})

	s.text_block_black = {
		bgImg = Tile:fillColor(0x000000ff),
		position = LAYOUT_NORTH,
		h = 100,
		order = { 'text' },
		text = {
			w = WH_FILL,
			h = 100,
                        padding = { 10, 160, 10, 0 },
                        align = "center",
                        font = _boldfont(TEXTAREA_FONT_SIZE), 
                        fg = TEXT_COLOR,
                        sh = TEXT_SH_COLOR,
                },
	}

	s.menu = {
		position = LAYOUT_CENTER,
		padding = { 0, 0, 0, 0 },  
		itemHeight = FIVE_ITEM_HEIGHT,
		fg = {0xbb, 0xbb, 0xbb},
		font = _boldfont(240), --sets font size of alpha/numeric search when scrolling
	}

	s.menu_hidden = _uses(s.menu, {
		hidden = 1,
	})
	
	s.item = {
		order = { "icon", "text", "arrow" },
		padding = { ITEM_LEFT_PADDING, 0, 20, 0 }, --was 8 add space between list and scrollbar
		text = {
			padding = { 0, 0, 2, 0 },
			align = "left",
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(TEXTMENU_FONT_SIZE),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		icon = {
			padding = MENU_ITEM_ICON_PADDING,
			align = 'center',
		},
		arrow = {
	      		align = ITEM_ICON_ALIGN,
	      		img = _loadImage(self, "Icons/selection_right_5line.png"),
			padding = { 0, 0, 0, 0 },
		},
		bgImg = fiveItemBox,
	}

	s.item_play = _uses(s.item, { 
		arrow = { img = false },
	})
	s.item_add = _uses(s.item, { 
		arrow = addArrow 
	})

	-- Checkbox
        s.checkbox = {}
	s.checkbox.align = 'center'
	s.checkbox.padding = CHECKBOX_RADIO_PADDING
	s.checkbox.h = WH_FILL
        s.checkbox.img_on = _loadImage(self, "Icons/checkbox_on.png")
        s.checkbox.img_off = _loadImage(self, "Icons/checkbox_off.png")


        -- Radio button
        s.radio = {}
	s.radio.align = 'center'
	s.radio.padding = CHECKBOX_RADIO_PADDING
	s.radio.h = WH_FILL
        s.radio.img_on = _loadImage(self, "Icons/radiobutton_on.png")
        s.radio.img_off = _loadImage(self, "Icons/radiobutton_off.png")

	s.item_choice = _uses(s.item, {
		order  = { 'icon', 'text', 'check' },
		choice = {
			h = WH_FILL,
			padding = CHECKBOX_RADIO_PADDING,
			align = 'right',
			font = _boldfont(TEXTMENU_FONT_SIZE),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	})
	s.item_checked = _uses(s.item, {
		order = { "icon", "text", "check", "arrow" },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
	      	}
	})

	s.item_info = _uses(s.item, {
		order = { 'text' },
		padding = { ITEM_LEFT_PADDING, 0, 0, 0 },
		text = {
			align = "top-left",
			w = WH_FILL,
			h = WH_FILL,
			padding = { 0, 6, 0, 6 },
			font = _boldfont(TEXTAREA_FONT_SIZE), -- 14
			line = {
				{
					font = _boldfont(TEXTAREA_FONT_SIZE), -- 14
					height = 14,
				},
				{
					font = _boldfont(TEXTAREA_FONT_SIZE), --18
					height = 18,
				},
			},
		},
	})

	s.item_no_arrow = _uses(s.item, {
		order = { 'icon', 'text' },
	})
	s.item_checked_no_arrow = _uses(s.item, {
		order = { 'icon', 'text', 'check' },
	})

	s.selected = {
		item               = _uses(s.item, {
			bgImg = fiveItemSelectionBox
		}),
		item_play           = _uses(s.item_play, {
			bgImg = fiveItemSelectionBox
		}),
		item_add            = _uses(s.item_add, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked        = _uses(s.item_checked, {
			bgImg = fiveItemSelectionBox
		}),
		item_no_arrow        = _uses(s.item_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
		item_choice         = _uses(s.item_choice, {
			bgImg = fiveItemSelectionBox
		}),
		item_info         = _uses(s.item_info, {
			bgImg = fiveItemSelectionBox
		}),
	}

	s.pressed = {
		item = _uses(s.item, {
			bgImg = fiveItemPressedBox,
		}),
		item_checked = _uses(s.item_checked, {
			bgImg = fiveItemPressedBox,
		}),
		item_play = _uses(s.item_play, {
			bgImg = fiveItemPressedBox,
		}),
		item_add = _uses(s.item_add, {
			bgImg = fiveItemPressedBox,
		}),
		item_no_arrow = _uses(s.item_no_arrow, {
			bgImg = fiveItemPressedBox,
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			bgImg = fiveItemPressedBox,
		}),
		item_choice = _uses(s.item_choice, {
			bgImg = fiveItemPressedBox,
		}),
		item_info         = _uses(s.item_info, {
			bgImg = fiveItemPressedBox,
		}),
	}

	s.locked = {
		item = _uses(s.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.pressed.item_play, {
			arrow = smallSpinny
		}),
		item_add = _uses(s.pressed.item_add, {
			arrow = smallSpinny
		}),
		item_no_arrow = _uses(s.item_no_arrow, {
			arrow = smallSpinny
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			arrow = smallSpinny
		}),
		item_info         = _uses(s.item_info, {
			arrow = smallSpinny,
		}),
	}

	s.item_blank = {
		padding = {  },
		text = {},
		bgImg = helpTextBackground,
	}

	s.pressed.item_blank = _uses(s.item_blank)
	s.selected.item_blank = _uses(s.item_blank)

	s.help_text = {
		w = screenWidth - 30,
		padding = { 16, 16, 16, 16}, -- second number y offset of text in help box
		font = _boldfont(HELP_FONT_SIZE),
		lineHeight = 23,
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		align = "top-left",
	}

	s.scrollbar = {
		w = 60, -- scroll bar position width (must change image size to matach)
		h = 380, -- add to shrink scollbar otherwise cannot touch bottom cornner on some screens 
		border = { 0, 15, 0, 0 }, --used to move scroll bar if necessary 
		padding = { 0, 0, 0, 0 },
		horizontal = 0,
		bgImg = scrollBackground,
		img = scrollBar,
		layer = LAYER_CONTENT_ON_STAGE,
	}

	s.text = {
		w = screenWidth,
		h = WH_FILL,
		padding = TEXTAREA_PADDING,
		font = _boldfont(TEXTAREA_FONT_SIZE),
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		align = "left",
	}

	s.multiline_text = {
		w = WH_FILL,
		padding = { 10, 0, 2, 10 },
		font = _boldfont(TEXTAREA_FONT_SIZE),
                height = 21,
		fg = { 0xe6, 0xe6, 0xe6 },
		sh = { },
		align = "left",
	}
	s.multiline_popup_text = _uses(s.multiline_text, {
		padding = { 14, 18, 14, 18 },
		border = { 0, 0, 10, 0 },
	})

	s.slider = {
		border = 10,
                position = LAYOUT_SOUTH,
                horizontal = 1,
                bgImg = _progressBackground,
                img = _progressBar,
	}

	s.slider_group = {
		w = WH_FILL,
		border = { 0, 5, 0, 10 },
		order = { "min", "slider", "max" },
	}


--------- SPECIAL WIDGETS ---------


	-- text input
	s.textinput = {
		h = 72, 
		padding = { 12, 0, 12, 0 }, 
		font = _boldfont(TEXTINPUT_FONT_SIZE),
		cursorFont = _boldfont(TEXTINPUT_SELECTED_FONT_SIZE),
		wheelFont = _boldfont(TEXTINPUT_FONT_SIZE),
		charHeight = TEXTINPUT_SELECTED_FONT_SIZE,
		fg = TEXT_COLOR_BLACK,
		charOffsetY = 18, --offsets text up/down in text box 
		wh = { 0x55, 0x55, 0x55 },
		cursorImg = textinputCursor,
	}

	-- keyboard
	s.keyboard = {
		w = WH_FILL,
		h = WH_FILL,
		border = { 8, 6, 8, 0 },
		padding = { 2, 0, 2, 0 },
	}

	s.keyboard_textinput = {
		bgImg = textinputBackground,
		w = WH_FILL,
		order = { "textinput", "backspace" },
		border = 0,
		textinput = {
			padding = { 16, 0, 0, 4 },
		},
	}

	s.keyboard.key = {
        	font = _boldfont(48), 
        	fg = { 0xDC, 0xDC, 0xDC },
        	align = 'center',
		bgImg = keyMiddle,
	}

	s.keyboard.key_topLeft     = _uses(s.keyboard.key, { bgImg = keyTopLeft })
	s.keyboard.key_top         = _uses(s.keyboard.key, { bgImg = keyTop })
	s.keyboard.key_topRight    = _uses(s.keyboard.key, { bgImg = keyTopRight })
	s.keyboard.key_left        = _uses(s.keyboard.key, { bgImg = keyLeft })
	s.keyboard.key_middle      = _uses(s.keyboard.key, { bgImg = keyMiddle })
	s.keyboard.key_right       = _uses(s.keyboard.key, { bgImg = keyRight })
	s.keyboard.key_bottomLeft  = _uses(s.keyboard.key, { bgImg = keyBottomLeft })
	s.keyboard.key_bottom      = _uses(s.keyboard.key, { bgImg = keyBottom })
	s.keyboard.key_bottomRight = _uses(s.keyboard.key, { bgImg = keyBottomRight })

	-- styles for keys that use smaller font 
	s.keyboard.key_bottom_small      = _uses(s.keyboard.key_bottom, { font = _boldfont(36) } )
	s.keyboard.key_bottomRight_small = _uses(s.keyboard.key_bottomRight, { 
			font = _boldfont(36), 
			fg = { 0xe7, 0xe7, 0xe7 },
	} )
	s.keyboard.key_bottomLeft_small  = _uses(s.keyboard.key_bottomLeft, { font = _boldfont(36) } )
	s.keyboard.key_left_small        = _uses(s.keyboard.key_left, { font = _boldfont(36) } )


	s.keyboard.spacer_topLeft     = _uses(s.keyboard.key_topLeft)
	s.keyboard.spacer_top         = _uses(s.keyboard.key_top)
	s.keyboard.spacer_topRight    = _uses(s.keyboard.key_topRight)
	s.keyboard.spacer_left        = _uses(s.keyboard.key_left)
	s.keyboard.spacer_middle      = _uses(s.keyboard.key_middle)
	s.keyboard.spacer_right       = _uses(s.keyboard.key_right)
	s.keyboard.spacer_bottomLeft  = _uses(s.keyboard.key_bottomLeft)
	s.keyboard.spacer_bottom      = _uses(s.keyboard.key_bottom)
	s.keyboard.spacer_bottomRight = _uses(s.keyboard.key_bottomRight)

	s.keyboard.shiftOff = _uses(s.keyboard.key_left, {
		img = _loadImage(self, "Icons/icon_shift_off.png"),
		padding = { 1, 0, 0, 0 },
	})
	s.keyboard.shiftOn = _uses(s.keyboard.key_left, {
		img = _loadImage(self, "Icons/icon_shift_on.png"),
		padding = { 1, 0, 0, 0 },
	})

	s.keyboard.arrow_left_middle = _uses(s.keyboard.key_middle, {
		img = _loadImage(self, "Icons/icon_arrow_left.png")
	})
	s.keyboard.arrow_right_right = _uses(s.keyboard.key_right, {
		img = _loadImage(self, "Icons/icon_arrow_right.png")
	})
	s.keyboard.arrow_left_bottom = _uses(s.keyboard.key_bottom, {
		img = _loadImage(self, "Icons/icon_arrow_left.png")
	})
	s.keyboard.arrow_right_bottom = _uses(s.keyboard.key_bottom, {
		img = _loadImage(self, "Icons/icon_arrow_right.png")
	})


    	s.keyboard.done = {
		text = _uses(s.keyboard.key_bottomRight_small, {
			text = self:string("ENTER_SMALL"),
			fg = { 0x00, 0xbe, 0xbe },
			sh = { },
			h = WH_FILL,
			padding = { 0, 0, 0, 1 },
		}),
		icon = { hidden = 1 },
	}

	s.keyboard.doneDisabled =  _uses(s.keyboard.done, {
		text = {
			fg = { 0x66, 0x66, 0x66 },
		}
	})

	s.keyboard.doneSpinny =  {
                icon = _uses(s.keyboard.key_bottomRight, {
			bgImg = keyBottomRight,
			hidden = 0,
                        img = _loadImage(self, "Alerts/wifi_connecting_sm.png"),
			frameRate = 8,
			frameWidth = 26,
			w = WH_FILL+20, 
			h = WH_FILL+20,
			align = 'center',
		}),
		text = { hidden = 1, w = 0 },
        }


	s.keyboard.space = _uses(s.keyboard.key_bottom_small, {
		bgImg = keyBottom,
		text = self:string("SPACEBAR_SMALL"),
	})

	s.keyboard.pressed = {
		shiftOff = _uses(s.keyboard.shiftOff, {
			bgImg = keyLeftPressed
		}),
		shiftOn = _uses(s.keyboard.shiftOn, {
			bgImg = keyLeftPressed
		}),
		done = _uses(s.keyboard.done, {
			bgImg = keyBottomRightPressed,
		}),
		doneDisabled = _uses(s.keyboard.doneDisabled, {
			-- disabled, not set
		}),
		doneSpinny = _uses(s.keyboard.doneSpinny, {
			-- disabled, not set
		}),
		space = _uses(s.keyboard.space, {
			bgImg = keyBottomPressed
		}),
		arrow_right_bottom = _uses(s.keyboard.arrow_right_bottom, {
			bgImg = keyBottomPressed
		}),
		arrow_right_right = _uses(s.keyboard.arrow_right_right, {
			bgImg = keyRightPressed
		}),
		arrow_left_bottom = _uses(s.keyboard.arrow_left_bottom, {
			bgImg = keyBottomPressed
		}),
		arrow_left_middle = _uses(s.keyboard.arrow_left_middle, {
			bgImg = keyMiddlePressed
		}),
		key = _uses(s.keyboard.key, {
			bgImg = keyMiddlePressed
		}),
		key_topLeft     = _uses(s.keyboard.key_topLeft, {
			bgImg = keyTopLeftPressed
		}),
		key_top         = _uses(s.keyboard.key_top, {
			bgImg = keyTopPressed
		}),
		key_topRight    = _uses(s.keyboard.key_topRight, {
			bgImg = keyTopRightPressed
		}),
		key_left        = _uses(s.keyboard.key_left, {
			bgImg = keyLeftPressed
		}),
		key_middle      = _uses(s.keyboard.key_middle, {
			bgImg = keyMiddlePressed
		}),
		key_right       = _uses(s.keyboard.key_right, {
			bgImg = keyRightPressed
		}),
		key_bottomLeft  = _uses(s.keyboard.key_bottomLeft, {
			bgImg = keyBottomLeftPressed
		}),
		key_bottom      = _uses(s.keyboard.key_bottom, {
			bgImg = keyBottomPressed
		}),
		key_bottomRight = _uses(s.keyboard.key_bottomRight, {
			bgImg = keyBottomRightPressed
		}),
		key_left_small  = _uses(s.keyboard.key_left_small, {
			bgImg = keyLeftPressed
		}),
		key_bottomLeft_small  = _uses(s.keyboard.key_bottomLeft_small, {
			bgImg = keyBottomLeftPressed
		}),
		key_bottom_small      = _uses(s.keyboard.key_bottom_small, {
			bgImg = keyBottomPressed
		}),
		key_bottomRight_small = _uses(s.keyboard.key_bottomRight_small, {
			bgImg = keyBottomRightPressed
		}),

		spacer_topLeft     = _uses(s.keyboard.spacer_topLeft),
		spacer_top         = _uses(s.keyboard.spacer_top),
		spacer_topRight    = _uses(s.keyboard.spacer_topRight),
		spacer_left        = _uses(s.keyboard.spacer_left),
		spacer_middle      = _uses(s.keyboard.spacer_middle),
		spacer_right       = _uses(s.keyboard.spacer_right),
		spacer_bottomLeft  = _uses(s.keyboard.spacer_bottomLeft),
		spacer_bottom      = _uses(s.keyboard.spacer_bottom),
		spacer_bottomRight = _uses(s.keyboard.spacer_bottomRight),
	}

	local _timeFirstColumnX12h = 218 
	local _timeFirstColumnX24h = 280 

	s.time_input_background_12h = {
		w = WH_FILL,
		h = screenHeight - TITLE_HEIGHT,
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/tch_multi_char_bkgrd_3c.png"),
		x = 0,
		y = TITLE_HEIGHT,
	}

	s.time_input_background_24h = {
		w = WH_FILL,
		h = screenHeight - TITLE_HEIGHT,
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/tch_multi_char_bkgrd_2c.png"),
		x = 0,
		y = TITLE_HEIGHT,
	}

	s.time_input_menu_box_12h = {
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/menu_box_fixed.png"),
		w = 384, 
		h = 80,  
		x = 208, 
		y = 228, 
	}
	
        s.time_input_menu_box_24h = {
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/menu_box_fixed.png"),
		w = 259, 
		h = 80,  
		x = 270, 
		y = 228, 
        }
        
        
	-- time input window
	s.input_time_12h = _uses(s.window)
	s.input_time_12h.hour = _uses(s.menu, {
		w = 100,
		h = screenHeight,
		itemHeight = 80,
		position = LAYOUT_WEST,
		padding = 0,
		border = { _timeFirstColumnX12h +10, TITLE_HEIGHT, 0, 0 },
		item = {
			bgImg = false,
			order = { 'text' },
			text = {
				align = 'right',
				font = _boldfont(45),
				padding = { 2, 4, 8, 0 },
				fg = { 0xb3, 0xb3, 0xb3 },
				sh = { },
			},
		},
		selected = {
			item = {
				order = { 'text' },
				bgImg = false,
				text = {
					font = _boldfont(45),
					fg = { 0xe6, 0xe6, 0xe6 },
					sh = { },
					align = 'right',
					padding = { 2, 4, 8, 0 },
				},
			},
		},
		pressed = {
			item = {
				order = { 'text' },
				bgImg = false,
				text = {
					font = _boldfont(45),
					fg = { 0xe6, 0xe6, 0xe6 },
					sh = { },
					align = 'right',
					padding = { 2, 4, 8, 0 },
				},
			},
		},
	})
	s.input_time_12h.minute = _uses(s.input_time_12h.hour, {
		border = { _timeFirstColumnX12h + 135, TITLE_HEIGHT, 0, 0 },
	})
	s.input_time_12h.ampm = _uses(s.input_time_12h.hour, {
		border = { _timeFirstColumnX12h + 135 + 120, TITLE_HEIGHT, 0, 0 },
		item = {
			text = {
				padding = { 0, 4, 8, 0 }, 
				font = _boldfont(32),
			},
		},
		selected = {
			item = {
				text = {
					padding = { 0, 4, 8, 0 },
					font = _boldfont(32),
				},
			},
		},
		pressed = {
			item = {
				text = {
					padding = { 0, 4, 8, 0 },
					font = _boldfont(32),
				},
			},
		},
	})
	s.input_time_12h.hourUnselected   = s.input_time_12h.hour
	s.input_time_12h.minuteUnselected = s.input_time_12h.minute
	s.input_time_12h.ampmUnselected   = s.input_time_12h.ampm

	s.input_time_24h = _uses(s.input_time_12h, {
		hour = {
			border = { _timeFirstColumnX24h + 10, TITLE_HEIGHT, 0, 0 },
		},
		minute = {
			border = { _timeFirstColumnX24h + 135, TITLE_HEIGHT, 0, 0 }, 
		},
		hourUnselected = {
			border = { _timeFirstColumnX24h + 10, TITLE_HEIGHT, 0, 0 },
		},
		minuteUnselected = {
			border = { _timeFirstColumnX24h + 135, TITLE_HEIGHT, 0, 0 }, 
		},
	})

	-- one set for buttons, one for spacers

--------- WINDOW STYLES ---------
	--
	-- These styles override the default styles for a specific window

	-- typical text list window
	s.text_list = _uses(s.window)

	-- text_only removes icons
        s.text_only = _uses(s.text_list, {
		menu = {
			item = {
				order = { 'text', 'arrow', },
			},
			selected = {
				item = {
					order = { 'text', 'arrow', },
				}
			},
			pressed = {
				item = {
					order = { 'text', 'arrow', },
				}
			},
		},
	})

	s.text_list.title = _uses(s.title, {
		text = {
			line = {
				{
					font = _boldfont(TITLE_FONT_SIZE),  
					height = 32,
				},
				{
					font = _boldfont(TITLE_FONT_SIZE),  
					fg   = { 0xB3, 0xB3, 0xB3 },
				},
			},
                },
	})

	s.text_list.title.textButton = _uses(s.text_list.title.text, {
		bgImg = titlebarButtonBox,
		padding = { 4, 15, 4, 15 },
	})
	s.text_list.title.pressed = {}
	s.text_list.title.pressed.textButton = _uses(s.text_list.title.text, {
		bgImg = pressedTitlebarButtonBox,
		padding = { 4, 15, 4, 15 },
	})

	-- choose player window is exactly the same as text_list on all windows except WQVGAlarge
	s.choose_player = s.text_list

	s.multiline_text_list = _uses(s.text_list)

	s.multiline_text_list.menu = _uses(s.menu, {
		itemHeight = THREE_ITEM_HEIGHT,
		item = {
			padding = { 10, 8, 0, 8 },
			bgImg = false,
			icon = {
				align = 'top',
			},
		},
	})

	s.multiline_text_list.menu.item_no_arrow = _uses(s.multiline_text_list.menu.item)

	s.multiline_text_list.menu.selected = {}
	s.multiline_text_list.menu.selected.item = _uses(s.multiline_text_list.menu.item, {
		--bgImg = threeItemSelectionBox,
                bgImg = fiveItemSelectionBox,
	})
	s.multiline_text_list.menu.selected.item_no_arrow = _uses(s.multiline_text_list.menu.selected.item)

	s.multiline_text_list.menu.pressed = {}
	s.multiline_text_list.menu.pressed.item = _uses(s.multiline_text_list.menu.item, {
		--bgImg = threeItemPressedBox,
                bgImg = fiveItemSelectionBox,
	})
	s.multiline_text_list.menu.pressed.item_no_arrow = _uses(s.multiline_text_list.menu.pressed.item)
 
	-- popup "spinny" window
	s.waiting_popup = _uses(s.popup, {
		text = {
			w = WH_FILL,
			h = (POPUP_TEXT_SIZE_1 + 8 ),
			position = LAYOUT_NORTH,
			border = { 0, 50, 0, 0 },
			padding = { 15, 0, 15, 0 },
			align = "center",
			font = _boldfont(POPUP_TEXT_SIZE_1),
			lineHeight = POPUP_TEXT_SIZE_1 + 8,
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		subtext = {
			w = WH_FILL,
			h = 47,
			position = LAYOUT_SOUTH,
			border = { 0, 0, 0, 20 },
			padding = { 15, 0, 15, 0 },
			align = "top",
			font = _boldfont(POPUP_TEXT_SIZE_2),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	})

	s.waiting_popup.subtext_connected = _uses(s.waiting_popup.subtext, {
		fg = TEXT_COLOR_TEAL,
	})

	s.black_popup = _uses(s.waiting_popup)
	s.black_popup.title = _uses(s.title, {
		bgImg = false,
		order = { },
	})

	-- input window (including keyboard)
	s.input = _uses(s.window)
	s.input.title = _uses(s.title, {
			
                        zOrder = 1,
			text = {
				font = _boldfont(TITLE_FONT_SIZE),
                                padding = { 0, 0, 0, 0},
                                bgImg   = false, -- removed button for consistant look
			},
			rbutton  = {
				font    = _font(14),
				fg      = TEXT_COLOR,
				bgImg   = titlebarButtonBox,
				w       = TITLE_BUTTON_WIDTH,
				padding = { 8, 0, 8, 0},
				align   = 'center',
			}
		})

	local clearMask = Tile:fillColor(0x00000000)

	s.power_on_window =  _uses(s.window)
	s.power_on_window.maskImg = clearMask
	s.power_on_window.title = _uses(s.title, {
		bgImg = false,
	})

	-- update window
	s.update_popup = _uses(s.popup, {
		text = {
			w = WH_FILL,
			h = (POPUP_TEXT_SIZE_1 + 8 ),
			position = LAYOUT_NORTH,
			border = { 0, 34, 0, 2 },
			padding = { 10, 0, 10, 0 },
			align = "center",
			font = _boldfont(POPUP_TEXT_SIZE_1),
			lineHeight = POPUP_TEXT_SIZE_1 + 8,
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,		
		},
		subtext = {
			w = WH_FILL,
			-- note this is a hack as the height and padding push
			-- the content out of the widget bounding box.
			h = 30,
			padding = { 0, 0, 0, 28 },
			font = _boldfont(UPDATE_SUBTEXT_SIZE),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
			align = "bottom",
			position = LAYOUT_SOUTH,
		},

		progress = {
			border = { 15, 7, 15, 17 },
			position = LAYOUT_SOUTH,
			horizontal = 1,
			bgImg = _progressBackground,
			img = _progressBar,
		},
	})

	s.home_menu = _uses(s.text_list, {
		menu = {
			item = _uses(s.item, {
				icon = {
					img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix)
				},
			}),
			selected = {
				item = _uses(s.selected.item, {
					icon = {
						img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
					},
				}),
			},
			locked = {
				item = _uses(s.locked.item, {
					icon = {
						img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
					},
				}),
			},
		},
	})

	s.home_menu.menu.item.icon_no_artwork = {
		img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix ),
		h   = THUMB_SIZE,
		padding = MENU_ITEM_ICON_PADDING,
		align = 'center',
	}
	s.home_menu.menu.selected.item.icon_no_artwork = s.home_menu.menu.item.icon_no_artwork
	s.home_menu.menu.locked.item.icon_no_artwork = s.home_menu.menu.item.icon_no_artwork

	-- icon_list window
	s.icon_list = _uses(s.window, {
		menu = {
			item = {
				order = { "icon", "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 18, 0 },  -- added to make space between list and scollbar
				text = {
					w = WH_FILL,  
					h = WH_FILL,
					align = 'left',
					font = _font(ALBUMMENU_SMALL_FONT_SIZE),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							fg = TEXT_COLOR,
                                                        height = 29, -- controls spacing between track title and album info
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE),
                                                        fg = TEXT_COLOR_TIME_VIS,
						},
					},
					sh = TEXT_SH_COLOR,
				},
				icon = {
					h = THUMB_SIZE,
					padding = MENU_ITEM_ICON_PADDING,
					align = 'center',
				},
				arrow = _uses(s.item.arrow),
			},
		},
	})

	s.icon_list.menu.item_checked = _uses(s.icon_list.menu.item, {
		order = { 'icon', 'text', 'check', 'arrow' },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
		},
	})
	s.icon_list.menu.item_play = _uses(s.icon_list.menu.item, { 
		arrow = { img = false },
	})
	s.icon_list.menu.albumcurrent = _uses(s.icon_list.menu.item_play, {
		arrow = { 
			img = _loadImage(self, "Icons/icon_nplay_3line_off.png"),
		},
		text = { padding = 0, },
		-- Bug 11482c#13, don't know why the bgImg has to be redefined again here, but this fixes the issue
		bgImg = fiveItemBox,
	})
	s.icon_list.menu.item_add  = _uses(s.icon_list.menu.item, { 
		arrow = addArrow,
	})
	s.icon_list.menu.item_no_arrow = _uses(s.icon_list.menu.item, {
		order = { 'icon', 'text' },
	})
	s.icon_list.menu.item_checked_no_arrow = _uses(s.icon_list.menu.item_checked, {
		order = { 'icon', 'text', 'check' },
	})

	s.icon_list.menu.selected = {
                item               = _uses(s.icon_list.menu.item, {
			bgImg = fiveItemSelectionBox
		}),
                albumcurrent       = _uses(s.icon_list.menu.albumcurrent, {
			arrow = { 
				img = _loadImage(self, "Icons/icon_nplay_3line_sel.png"),
			},
			bgImg = fiveItemSelectionBox,
		}),
                item_checked        = _uses(s.icon_list.menu.item_checked, {
			bgImg = fiveItemSelectionBox
		}),
		item_play           = _uses(s.icon_list.menu.item_play, {
			bgImg = fiveItemSelectionBox
		}),
		item_add            = _uses(s.icon_list.menu.item_add, {
			bgImg = fiveItemSelectionBox
		}),
		item_no_arrow        = _uses(s.icon_list.menu.item_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked_no_arrow = _uses(s.icon_list.menu.item_checked_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
        }
        s.icon_list.menu.pressed = {
                item = _uses(s.icon_list.menu.item, { 
			bgImg = fiveItemPressedBox 
		}),
                albumcurrent       = _uses(s.icon_list.menu.albumcurrent, {
			bgImg = fiveItemSelectionBox
		}),
                item_checked = _uses(s.icon_list.menu.item_checked, { 
			bgImg = fiveItemPressedBox 
		}),
                item_play = _uses(s.icon_list.menu.item_play, { 
			bgImg = fiveItemPressedBox 
		}),
                item_add = _uses(s.icon_list.menu.item_add, { 
			bgImg = fiveItemPressedBox 
		}),
                item_no_arrow = _uses(s.icon_list.menu.item_no_arrow, { 
			bgImg = fiveItemPressedBox 
		}),
                item_checked_no_arrow = _uses(s.icon_list.menu.item_checked_no_arrow, { 
			bgImg = fiveItemPressedBox 
		}),
        }
	s.icon_list.menu.locked = {
		item = _uses(s.icon_list.menu.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.icon_list.menu.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.icon_list.menu.pressed.item_play, {
			arrow = smallSpinny
		}),
		item_add = _uses(s.icon_list.menu.pressed.item_add, {
			arrow = smallSpinny
		}),
                albumcurrent       = _uses(s.icon_list.menu.pressed.albumcurrent, {
			arrow = smallSpinny
		}),
	}

	-- list window with help text
	s.help_list = _uses(s.text_list)


	s.error = _uses(s.help_list)


	-- information window
	s.information = _uses(s.window)

	s.information.text = {
		font = _boldfont(28),
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		padding = { 18, 18, 10, 0},
		lineHeight = 28,
	}

	-- help window (likely the same as information)
	s.help_info = _uses(s.information)


	--track_list window
	-- XXXX todo
	-- identical to text_list but has icon in upper left of titlebar
	s.track_list = _uses(s.text_list)

	s.track_list.title = _uses(s.title, {
		order = { 'lbutton', 'icon', 'text', 'rbutton' },
		icon  = {
			w = THUMB_SIZE,
			h = WH_FILL,
			padding = { 10, 1, 8, 1 },
		},
	})

	--playlist window
	-- identical to icon_list but with some different formatting on the text
	s.play_list = _uses(s.icon_list, {
		menu = {
			item = {
				text = {
					padding = MENU_PLAYLISTITEM_TEXT_PADDING,
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							height = ALBUMMENU_FONT_SIZE
						},
						{
							height = ALBUMMENU_SMALL_FONT_SIZE + 2
						},
						{
							height = ALBUMMENU_SMALL_FONT_SIZE + 2
						},
					},	
				},
			},
		},
	})
	s.play_list.menu.item_checked = _uses(s.play_list.menu.item, {
		order = { 'icon', 'text', 'check', 'arrow' },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
		},
	})
	s.play_list.menu.selected = {
                item = _uses(s.play_list.menu.item, {
			bgImg = fiveItemSelectionBox
		}),
                item_checked = _uses(s.play_list.menu.item_checked, {
			bgImg = fiveItemSelectionBox
		}),
        }
        s.play_list.menu.pressed = {
                item = _uses(s.play_list.menu.item, { bgImg = fiveItemPressedBox }),
                item_checked = _uses(s.play_list.menu.item_checked, { bgImg = fiveItemPressedBox }),
        }
	s.play_list.menu.locked = {
		item = _uses(s.play_list.menu.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.play_list.menu.pressed.item_checked, {
			arrow = smallSpinny
		}),
	}

	-- toast_popup popup (is now text only)
	s.toast_popup_textarea = {
		x = 32, 
		y = 110, 
		w = screenWidth - 64, 
		h = 260, 
		padding = { 76, 32, 0, 0 } ,
		align = 'center', 
		font = _boldfont(TEXTAREA_FONT_SIZE),  
		lineHeight = TEXTAREA_FONT_SIZE + 12, 
                fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
        }

	-- toast_popup popup with art and text
	s.toast_popup = {
		x = 32, 
		y = 110, 
		w = screenWidth - 64, 
		h = 260, 
		bgImg = popupBox,
		group = {
			padding = 10,
			order = { 'icon', 'text' },
			text = { 
				padding = { 12, 12, 12, 12 } ,
				align = 'center',
                                --align = 'top-left',
				w = WH_FILL,
				h = WH_FILL,
				font = _boldfont(HELP_FONT_SIZE),
				lineHeight = HELP_FONT_SIZE + 5,
			},
			icon = { 
				align = 'center',
                                --align = 'top-left', 
				border = { 12, 12, 12, 12 },
				img = _loadImage(self, "UNOFFICIAL/menu_album_noartwork_64.png"),
				h = WH_FILL,
				w = 64,
			}
		}
	}
	-- toast popup with textarea
	s.toast_popup_text = _uses(s.toast_popup, {
		group = {
			order = { 'text' },
			text = {
				w = WH_FILL,
				h = WH_FILL,
				align = 'top-left',
				padding = { 10, 12, 12, 12 },
				fg = TEXT_COLOR,
				sh = TEXT_SH_COLOR,
			},
		}
	})

	-- toast popup with icon only
	s.toast_popup_icon = _uses(s.toast_popup, {
		w = 200,
		h = 180,
		x = 300,
		y = 150,
                position = LAYOUT_NONE,
		group = {
			order = { 'icon' },
			border = { 22, 22, 0, 0 },
			padding = 0,
			icon = {
				w = WH_FILL,
				h = WH_FILL,
				align = 'center',
			},
		}
	})

	-- new style that incorporates text, icon, more text, and maybe a badge
        -- This is the popup used for adding a song (from Music library to playlist or favorites) 
	s.toast_popup_mixed = {
		x = 32, 
		y = 110, -- center on screen (y direction)
		position = LAYOUT_NONE,
		w = screenWidth - 64,
		h = 260,
		bgImg = popupBox,
		text = {
			position = LAYOUT_NORTH,
			padding = { 8, 30, 8, 0 },
			align = 'top',
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(TEXTAREA_FONT_SIZE), --  changes font size when "adding to end" popup
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		subtext = {
			position = LAYOUT_NORTH,
			padding = { 8, 194, 8, 0 },
			align = 'top',
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(TEXTAREA_FONT_SIZE), 
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	}

	s._badge = {
		position = LAYOUT_NONE,
		zOrder = 99,
		-- middle of the screen plus half of the icon width minus half of the badge width. gotta love LAYOUT_NONE
		x = screenWidth/2 + 21,
		w = 34,
		y = 34,
	}
	-- These "badges" look odd in the popup windows so they were elimintaed. 
        s.badge_none = _uses(s._badge, {
		img = false,
	})
	s.badge_favorite = s.badge_none 
	s.badge_add = s.badge_none  
	

	s.context_menu = {
		x = 32, 
		y = 32, 
		w = screenWidth - 64, 
		h = screenHeight - 64, 
		bgImg = contextMenuBox,
		layer = LAYER_TITLE,
				
		multiline_text = {
                        w = WH_FILL,
                        h = 172, 
                        padding = { 18, 0, 14, 18 },
                        border = { 0, 0, 6, 15 },
                        lineHeight = FIVE_ITEM_HEIGHT,
                        font = _boldfont(TEXTAREA_FONT_SIZE), 
                        fg = { 0xe6, 0xe6, 0xe6 },
                        sh = { },
                        align = "top-left",
                        scrollbar = {
                                h = 164,
                                border = {0, 2, 2, 10},
                        },
                },

		title = {
		layer = LAYER_TITLE,
			h = 52,
			padding = {10,10,10,5},
			bgImg = false,
			button_cancel  = {
				layer = LAYER_TITLE,
				w       = 43,
				align = 'right',
			},
			pressed = {
				button_cancel  = {
					bgImg = pressedTitlebarButtonBox,
					layer = LAYER_TITLE,
					w       = 43,
				},
			},
			text = {
				layer = LAYER_TITLE,
				w = WH_FILL,
				padding = {0,0,20,0},
				align = "center",
				font = _boldfont(TITLE_FONT_SIZE),
				fg = TEXT_COLOR,
			},

		},
		menu = {  --- this is the popup menu for selection info 
			h = CM_MENU_HEIGHT * 8,
			border = { 7, -8, 7, 0 },
			padding = { 0, 0, 0, 100 },
			scrollbar = { 
				h = CM_MENU_HEIGHT * 7,
				border = { 10, 15, -6, 10 }, -- added to center scrollbar under button
			},
			item = {
				h = FIVE_ITEM_HEIGHT,
				order = { "icon", "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 4, 0 },
				text = {
					padding = { 0, 4, 0, 0 },
					w = WH_FILL,
					h = WH_FILL,
					align = 'left',
                                        font = _boldfont(TEXTAREA_FONT_SIZE),
                                        fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				icon = {
					h = THUMB_SIZE,
					padding = MENU_ITEM_ICON_PADDING,
					align = 'center',
				},
				arrow = _uses(s.item.arrow),
			},
			selected = {
				item = {
					h = FIVE_ITEM_HEIGHT,
                                        order = { "icon", "text", "arrow" },
					bgImg = fiveItemSelectionBox,
					padding = { ITEM_LEFT_PADDING, 0, 4, 0 },
					text = {
						padding = { 0, 4, 0, 0 },
						w = WH_FILL,
						h = WH_FILL,
						align = 'left',
						font = _boldfont(TEXTAREA_FONT_SIZE),
                                                fg = TEXT_COLOR,
						sh = TEXT_SH_COLOR,
					},
					icon = {
						h = THUMB_SIZE,
						padding = MENU_ITEM_ICON_PADDING,
						align = 'center',
					},
					arrow = _uses(s.item.arrow),
				},
			},

		},
	}
	
	s.context_menu.menu.item_play = _uses(s.context_menu.menu.item, {
		order = { 'text' },
	})
	s.context_menu.menu.selected.item_play = _uses(s.context_menu.menu.selected.item, {
		order = { 'text' },
	})

	s.context_menu.menu.pressed = _uses(s.context_menu.menu.selected, { -- popup menu selection type (funny looking, changed to typical menu style ) 
		item = {
			bgImg = fiveItemPressedBox
		},
	})

	s.context_menu.menu.locked = _uses(s.context_menu.menu.pressed, {
		item = {
			arrow = smallSpinny,
		},
	})

	-- alarm popup
	s.alarm_header = {
			w = screenWidth,
			order = { 'time' },
	}

	s.alarm_time = {
		w = screenWidth - 128,
		fg = TEXT_COLOR,
		align = "center",
		font = _font(180),
                padding = { 0, 20, 0, 30 }
	}

	s.preview_text = _uses(s.alarm_time, {
		font = _boldfont(TITLE_FONT_SIZE),
	})
	
	-- alarm menu window
	s.alarm_popup = {
		x = 64,
		y = 64,
		w = screenWidth - 128,
		h = screenHeight - 128,
		border = 0,
		padding = 0,
		bgImg = contextMenuAlarm,
		layer = LAYER_TITLE,

     		title = {
			layer = LAYER_TITLE,
			w = WH_FILL,
			h = 52,
			--padding = { 0, 10, 0, 0 },
			padding = { 500, 10, 10, 5 },
			img = false,
                        bgImg = false,
		},

		menu = {
			h = CM_MENU_HEIGHT * 6,
			w = screenWidth - 148,
			x = 10,
			y = 50,
			border = 0,
			itemHeight = CM_MENU_HEIGHT,
			position = LAYOUT_NORTH,
			scrollbar = { 
				h = CM_MENU_HEIGHT * 5 - 8,
				border = {10,0,10,0},
			},
			item = {
				h = CM_MENU_HEIGHT,
				order = { "text", "arrow" },
				text = {
					w = WH_FILL,
					h = WH_FILL,
					align = 'left',
					font = _boldfont(TEXTMENU_FONT_SIZE),
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				arrow = _uses(s.item.arrow),
			},
			selected = {
				item = {
					bgImg = fiveItemSelectionBox,
					order = { "text", "arrow" },
					text = {
						w = WH_FILL,
						h = CM_MENU_HEIGHT + 60,
						align = 'left',
						font = _boldfont(TEXTMENU_FONT_SIZE),
						fg = TEXT_COLOR,
						sh = TEXT_SH_COLOR,
					},
					arrow = _uses(s.item.arrow),
				},
			},

		},
	}
        
        -- slider popup (volume)
	s.slider_popup = {
		x = 50,
		y = screenHeight/2 - 100,
		w = screenWidth - 100,
		h = 200,
		bgImg = popupBox,
		heading = {
			w = WH_FILL,
		      border = 10,
		      fg = TEXT_COLOR,
		      font = _boldfont(32),
			padding = { 4, 16, 4, 0 },
		      align = "center",
		      bgImg = false,
		},
		slider_group = {
			w = WH_FILL,
			align = 'center',
			padding = { 10, 0, 10, 0 },
			order = { 'slider' },
		},
	}


       -- scanner popup
	s.scanner_popup = _uses(s.slider_popup, {
		h = 110,
		y = screenHeight/2 - 55,
	})

	s.image_popup = _uses(s.popup, {
		image = {
			w = screenWidth,
			position = LAYOUT_CENTER,
			align = "center",
			h = screenHeight,
			border = 0,
		},
	})


--------- SLIDERS ---------


	s.volume_slider = {
		w = WH_FILL,
		border = { 0, 0, 0, 10 },
                bgImg = _volumeSliderBackground,
                img = _popupSliderBar,
	}

        s.scanner_slider = _uses(s.volume_slider, {
                img = _volumeSliderBar,
	})
	
--------- BUTTONS ---------

	-- base button
	local _button = {
		bgImg = titlebarButtonBox,
		w = TITLE_BUTTON_WIDTH,
		h = WH_FILL,
		border = { 8, 0, 8, 0 },
		icon = {
			w = WH_FILL,
			h = WH_FILL,
			hidden = 1,
			align = 'center',
			img = false,
		},
		text = {
			w = WH_FILL,
			h = WH_FILL,
			hidden = 1,
			border = 0,
			padding = 0,
			align = 'center',
			font = _boldfont(20),  -- button text size (i.e. done on time set)
			fg = { 0xdc,0xdc, 0xdc },
		},
	}
	local _pressed_button = _uses(_button, {
		bgImg = pressedTitlebarButtonBox,
	})


	-- icon button factory
	local _titleButtonIcon = function(name, icon, attr)
		s[name] = _uses(_button)
		s[name].layer = LAYER_TITLE

		s.pressed[name] = _uses(_pressed_button)

		attr = {
			hidden = 0,
			img = icon,
			layer = LAYER_TITLE,
		}

		s[name].icon = _uses(_button.icon, attr)
		s[name].w = 65
		s.pressed[name].icon = _uses(_pressed_button.icon, attr)
		s.pressed[name].w = 65
	end

	-- text button factory
	local _titleButtonText = function(name, string)
		s[name] = _uses(_button)
		s.pressed[name] = _uses(_pressed_button)

		attr = {
			hidden = 0,
			text = string,
		}

		s[name].text = _uses(_button.text, attr)
		s[name].w = 65
		s.pressed[name].text = _uses(_pressed_button.text, attr)
		s.pressed[name].w = 65
	end


	-- invisible button
	s.button_none = _uses(_button, {
		bgImg    = false,
		w = TITLE_BUTTON_WIDTH  - 12,
	})

	_titleButtonIcon("button_back", backButton)
	_titleButtonIcon("button_cancel", cancelButton)
	_titleButtonIcon("button_go_home", homeButton)
	_titleButtonIcon("button_playlist", playlistButton)
	_titleButtonIcon("button_more", moreButton)
	_titleButtonIcon("button_go_playlist", playlistButton)
	_titleButtonIcon("button_go_now_playing", nowPlayingButton)
	_titleButtonIcon("button_power", powerButton)
	_titleButtonIcon("button_nothing", nil)
	_titleButtonIcon("button_help", helpButton)
	_titleButtonText("button_more_help", self:string("MORE_HELP"))
	_titleButtonText("button_finish_operation", self:string("ENTER"))

	s.button_back.padding     = { 2, 0, 0, 2 }
	s.button_playlist.padding = { 2, 0, 0, 2 }

	s.button_volume_min = {
		img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
		border = { 5, 0, 5, 0 },
	}

	s.button_volume_max = {
		img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
		border = { 5, 0, 5, 0 },
	}

        s.button_brightness_min = {
		img = _loadImage(self, "Icons/icon_toolbar_brightness_down.png"),
		border = { 5, 0, 5, 0 },
	}

	s.button_brightness_max = {
		img = _loadImage(self, "Icons/icon_toolbar_brightness_up.png"),
		border = { 5, 0, 5, 0 },
	}
        
	s.button_keyboard_back = {
		align = 'left',
		w = 96, -- was 48
		h = 66, -- was 33
		padding = { 14, 0, 0, 0 }, --was 8
		border = { 0, 2, 9, 5}, 
		img = _loadImage(self, "Icons/icon_delete_tch_text_entry.png"),
		bgImg = deleteKeyBackground,
	}
	s.pressed.button_keyboard_back = _uses(s.button_keyboard_back, {
                bgImg = deleteKeyPressedBackground,
	})


	local _buttonicon = {
		h   = THUMB_SIZE,
		padding = MENU_ITEM_ICON_PADDING,
		align = 'center',
		img = false,
	}

	s.region_US = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_region_americas" .. skinSuffix),
	})
	s.region_XX = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_region_other" .. skinSuffix),
	})
	s.icon_help = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_help" .. skinSuffix),
	})
	s.wlan = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_wireless" .. skinSuffix),
	})
	s.wired = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ethernet" .. skinSuffix),
	})


--------- ICONS --------

	-- icons used for 'waiting' and 'update' windows
	local _icon = {
		w = WH_FILL,
		align = "center",
		position = LAYOUT_CENTER,
		padding = { 0, 0, 0, 10 }
	}

	local _popupicon = {
                padding = 0,
                border = { 22, 22, 0, 0 },
                h = WH_FILL,
                w = 146,
        }

	-- icon for albums with no artwork
	s.icon_no_artwork = {
		img = _loadImage(self, "IconsResized/icon_album_noart" .. skinSuffix ),
		h   = THUMB_SIZE,
		padding = MENU_ITEM_ICON_PADDING,
		align = 'center',
	}

	s.icon_connecting = _uses(_icon, {
		img = _loadImage(self, "Alerts/wifi_connecting.png"),
		frameRate = 8,
		frameWidth = 180, 
                padding = { 0, 65, 0, 10 },
	})

	s.icon_connected = _uses(_icon, {
		img = _loadImage(self, "Alerts/connecting_success_icon.png"),
                padding = { 0, 65, 0, 10 },
	})

	s.icon_photo_loading = _uses(_icon, {
		img = _loadImage(self, "Icons/image_viewer_loading.png"),
	})

	s.icon_software_update = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_firmware_update" .. skinSuffix),
	})

	s.icon_restart = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_restart" .. skinSuffix),
	})

	s.icon_popup_pause = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_pause.png"),
	})

	s.icon_popup_play = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_play.png"),
	})

	s.icon_popup_fwd = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_fwd.png"),
	})
	s.icon_popup_rew = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_rew.png"),
	})

	s.icon_popup_stop = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_stop.png"),
	})
	s.icon_popup_lineIn = _uses(_popupicon, {
		img = _loadImage(self, "IconsResized/icon_linein_134.png"),
	})

	s.icon_popup_volume = {
		img = _loadImage(self, "Icons/icon_popup_box_volume_bar.png"),
		w = WH_FILL,
		h = 90,
		align = 'center',
		padding = { 0, 5, 0, 5 },
	}

	s.icon_popup_mute = _uses(s.icon_popup_volume, {
		img = _loadImage(self, "Icons/icon_popup_box_volume_mute.png"),
	})

	s.icon_popup_shuffle0 = _uses(_popupicon, {
                img = _loadImage(self, "Icons/icon_popup_box_shuffle_off.png"),
        })

        s.icon_popup_shuffle1 = _uses(_popupicon, {
                img = _loadImage(self, "Icons/icon_popup_box_shuffle.png"),
        })

        s.icon_popup_shuffle2 = _uses(_popupicon, {
                img = _loadImage(self, "Icons/icon_popup_box_shuffle_album.png"),
        })

	s.icon_popup_repeat0 = _uses(_popupicon, {
                img = _loadImage(self, "Icons/icon_popup_box_repeat_off.png"),
        })

        s.icon_popup_repeat1 = _uses(_popupicon, {
                img = _loadImage(self, "Icons/icon_popup_box_repeat_song.png"),
        })

        s.icon_popup_repeat2 = _uses(_popupicon, {
                img = _loadImage(self, "Icons/icon_popup_box_repeat.png"),
        })

	s.icon_popup_sleep_15 = {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_15.png"),
		h = WH_FILL,
		w = WH_FILL,
		padding = { 24, 24, 0, 0 },
	}
	s.icon_popup_sleep_30 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_30.png"),
	})
	s.icon_popup_sleep_45 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_45.png"),
	})
	s.icon_popup_sleep_60 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_60.png"),
	})
	s.icon_popup_sleep_90 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_90.png"),
	})
	s.icon_popup_sleep_cancel = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_off.png"),
		padding = { 24, 34, 0, 0 },
	})

	s.icon_power = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_restart" .. skinSuffix),
	})

	s.icon_locked = _uses(_icon, {
-- FIXME no asset for this (needed?)
--		img = _loadImage(self, "Alerts/popup_locked_icon.png"),
	})

	s.icon_alarm = {
		img = _loadImage(self, "Icons/icon_alarm.png"),
	}

        s.icon_art = _uses(_icon, {
                padding = 0,
                img = false,
        })

	s.player_transporter = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_transporter" .. skinSuffix),
	})
	s.player_squeezebox = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_SB1n2" .. skinSuffix),
	})
	s.player_squeezebox2 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_SB1n2" .. skinSuffix),
	})
	s.player_squeezebox3 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_SB3" .. skinSuffix),
	})
	s.player_boom = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_boom" .. skinSuffix),
	})
	s.player_slimp3 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_slimp3" .. skinSuffix),
	})
	s.player_softsqueeze = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_softsqueeze" .. skinSuffix),
	})
	s.player_controller = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_controller" .. skinSuffix),
	})
	s.player_receiver = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_receiver" .. skinSuffix),
	})
	s.player_squeezeplay = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_squeezeplay" .. skinSuffix),
	})
	s.player_http = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_tunein_url" .. skinSuffix),
	})
	s.player_baby = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_baby" .. skinSuffix),
	})
	s.player_fab4 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_fab4" .. skinSuffix),
	})

	-- misc home menu icons
	s.hm_appletImageViewer = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_image_viewer" .. skinSuffix),
	})
	s.hm_eject = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_eject" .. skinSuffix),
	})
	s.hm_sdcard = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_device_SDcard" .. skinSuffix),
	})
	s.hm_usbdrive = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_device_USB" .. skinSuffix),
	})
	s.hm_appletNowPlaying = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_nowplaying" .. skinSuffix),
	})
	s.hm_settings = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings" .. skinSuffix),
	})
	s.hm_advancedSettings = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_adv" .. skinSuffix),
	})
	s.hm_radio = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_internet_radio" .. skinSuffix),
	})
	s.hm_radios = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_internet_radio" .. skinSuffix),
	})
	s.hm_myApps = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_my_apps" .. skinSuffix),
	})
	s.hm_myMusic = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_mymusic" .. skinSuffix),
	})
	s.hm__myMusic = _uses(s.hm_myMusic)
   	s.hm_otherLibrary = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_ml_other_library" .. skinSuffix),
        })
	s.hm_myMusicSelector = _uses(s.hm_myMusic)

	s.hm_favorites = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_favorites" .. skinSuffix),
	})
	s.hm_settingsAlarm = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_alarm" .. skinSuffix),
	})
	s.hm_settingsPlayerNameChange = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_name" .. skinSuffix),
	})
	s.hm_settingsBrightness = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_brightness" .. skinSuffix),
	})
	s.hm_settingsSync = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_sync" .. skinSuffix),
	})
	s.hm_selectPlayer = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_choose_player" .. skinSuffix),
	})
	s.hm_quit = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_power_off" .. skinSuffix),
	})
	s.hm_playerpower = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_power_off" .. skinSuffix),
	})
	s.hm_settingsScreen = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_blank" .. skinSuffix),
	})
	s.hm_myMusicArtists = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_artist" .. skinSuffix),
	})
	s.hm_myMusicAlbums = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_albums" .. skinSuffix),
	})
	s.hm_myMusicGenres = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_genres" .. skinSuffix),
	})
	s.hm_myMusicYears = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_years" .. skinSuffix),
	})

	s.hm_myMusicNewMusic = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_new_music" .. skinSuffix),
	})
	s.hm_myMusicPlaylists = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_playlist" .. skinSuffix),
	})
	s.hm_myMusicSearch = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_search" .. skinSuffix),
	})
	s.hm_myMusicSearchArtists   = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchAlbums    = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchSongs     = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchPlaylists = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchRecent    = _uses(s.hm_myMusicSearch)
	s.hm_homeSearchRecent       = _uses(s.hm_myMusicSearch)
	s.hm_globalSearch           = _uses(s.hm_myMusicSearch)

	s.hm_myMusicMusicFolder = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_folder" .. skinSuffix),
	})
	s.hm_randomplay = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_random" .. skinSuffix),
	})
	s.hm_skinTest = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_blank" .. skinSuffix),
	})

        s.hm_settingsRepeat = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_repeat" .. skinSuffix),
        })
        s.hm_settingsShuffle = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_shuffle" .. skinSuffix),
        })
        s.hm_settingsSleep = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_sleep" .. skinSuffix),
        })
        s.hm_settingsScreen = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_screen" .. skinSuffix),
        })
        s.hm_appletCustomizeHome = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_home" .. skinSuffix),
        })
        s.hm_settingsAudio = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_audio" .. skinSuffix),
        })
        s.hm_linein = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_linein" .. skinSuffix),
        })

        -- ??
        s.hm_loading = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
        })
        -- ??
        s.hm_settingsPlugin = _uses(_buttonicon, {
                img = _loadImage(self, "IconsResized/icon_settings_plugin" .. skinSuffix),
        })

	-- indicator icons, on right of menus
	local _indicator = {
		align = "center",
	}

	s.wirelessLevel1 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_1.png")
	})

	s.wirelessLevel2 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_2.png")
	})

	s.wirelessLevel3 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_3.png")
	})

	s.wirelessLevel4 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_4.png")
	})


--------- ICONBAR ---------

	s.iconbar_group = {
		hidden = 1,
	}

	-- time (hidden off screen)
	s.button_time = {
		hidden = 1,
	}



	-- BEGIN NowPlaying skin code

	local NP_ARTISTALBUM_FONT_SIZE = 38 
	local NP_TRACK_FONT_SIZE = 48 
        local NP_PROGRESS_BAR_FONT_SIZE = 28
        
	local controlHeight = 72 -- was 76 fix grey on bottom...
	--local controlWidth = 74  -- 74 normal, no volume control use 160
        local volumeBarWidth = 260 -- 196 -- was 163 screenWidth - (transport controls + volume controls + dividers + border around volume bar)
	local buttonPadding = 0

	local _transportControlButton = {
		w = controlWidth,
		h = controlHeight,
		align = 'center',
		padding = buttonPadding,
	}

	local _transportControlBorder = _uses(_transportControlButton, {
		w = 2,
		padding = 0,
		img = touchToolbarKeyDivider,		
	})

	-- This bit can be used to pad between controls and the volume slider, but I extended the slider instead, because I always want that in-between setting. ;)
	local _transportVolumeBorder = _uses(_transportControlButton, {
		w = 0, 
		padding = { 88, 0, 0, 0 },
		img = touchToolbarKeyDivider,
	}) 

	s.toolbar_spacer = _uses(_transportControlButton, {
		w = WH_FILL,
	})

	local _tracklayout = {
		border = { 4, 0, 4, 0 },
		position = LAYOUT_NONE,
		w = WH_FILL,
		align = "left",
		lineHeight = NP_TRACK_FONT_SIZE+10, 
		fg = TEXT_COLOR,
		x = 318,
	}

	s.nowplaying = _uses(s.window, {
		--title bar
		
                title = _uses(s.title, {
			
                        zOrder = 1,
			text = {
				font = _boldfont(TITLE_FONT_SIZE),
                                padding = { 0, 0, 0, 0},
                                bgImg   = false, -- removed button for consistant look
			},
			rbutton  = {
				font    = _font(14),
				fg      = TEXT_COLOR,
				bgImg   = titlebarButtonBox,
				w       = TITLE_BUTTON_WIDTH,
				padding = { 8, 0, 8, 0},
				align   = 'center',
			}
		}),
	
		-- Song metadata
		nptitle = {
			order = { 'nptrack' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = _tracklayout.x,
			y          = TITLE_HEIGHT + 70, 
			h          = NP_TRACK_FONT_SIZE+20, 
			nptrack =  {
				w          = screenWidth - _tracklayout.x -10 ,
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _boldfont(NP_TRACK_FONT_SIZE), 
				sh = TEXT_SH_COLOR,
			},
		},
		npartistgroup = {
			order = { 'npartist' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = _tracklayout.x,
			y          = TITLE_HEIGHT + 32 + 32 + 100 -20,
			h          = NP_ARTISTALBUM_FONT_SIZE+20, 
			npartist = {
				padding    = { 0, 6, 0, 0 },
				w          = screenWidth - _tracklayout.x - 10,
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _font(NP_ARTISTALBUM_FONT_SIZE),
				sh = TEXT_SH_COLOR,
			},
		},
		npalbumgroup = {
			order = {'npalbum' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = _tracklayout.x,
			y          = TITLE_HEIGHT + 32 + 32 + 32 + 110 -15, 
			h          = NP_ARTISTALBUM_FONT_SIZE+20, 
			npalbum = {
				w          = screenWidth - _tracklayout.x - 10,
				padding    = { 0, 6, 0, 0 },
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _font(NP_ARTISTALBUM_FONT_SIZE),
				sh = TEXT_SH_COLOR,
			},
		},
		npartistalbum = {
			hidden = 1,
		},
	
		-- cover art
		npartwork = {
			w = 300,
			position = LAYOUT_NONE,
			x = 8,
			y = TITLE_HEIGHT + 20,
			align = "center",
			h = 300,
			artwork = {
				w = 300,
				align = "center",
				padding = 0,
				img = false,
			},
		},

		npvisu = { hidden = 1 },
	
		--transport controls
		npcontrols = {
			order = vc_order, 
                        position = LAYOUT_SOUTH,
			h = controlHeight,
			w = WH_FILL,
			bgImg = touchToolbarBackground,

			div1 = _uses(_transportControlBorder),
			div2 = _uses(_transportControlBorder),
			div3 = _uses(_transportControlBorder),
			div4 = _uses(_transportControlBorder),
			div5 = _uses(_transportVolumeBorder),--_transportControlBorder
			div6 = _uses(_transportControlBorder),
			div7 = _uses(_transportControlBorder),

			rew   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_rew.png"),
			}),
			play  = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_play.png"),
			}),
			pause = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_pause.png"),
			}),
			fwd   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_ffwd.png"),
			}),
			shuffleMode   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_off.png"),
			}),
			shuffleOff   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_off.png"),
			}),
			shuffleSong  = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_on.png"),
			}),
			shuffleAlbum = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_album_on.png"),
			}),
			repeatMode   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_off.png"),
			}),
			repeatOff   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_off.png"),
			}),
			repeatPlaylist = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_on.png"),
			}),
			repeatSong = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_song_on.png"),
			}),
			volDown   = _uses(_transportControlButton, {
				w = 74, -- was 34
				img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
			}),
			volUp   = _uses(_transportControlButton, {
				w = 74, -- was 34 made larger to match control putton width
				img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
			}),
			thumbsUp   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbup.png"),
			}),
			thumbsDown   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbdown.png"),
			}),
			thumbsUpDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbup_dis.png"),
			}),
			thumbsDownDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbdown_dis.png"),
			}),
			love   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_love_on.png"),
			}),
			hate   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_love_off.png"),
			}),
			fwdDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_ffwd_dis.png"),
			}),
			rewDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_rew_dis.png"),
			}),
			shuffleDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_dis.png"),
			}),
			repeatDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_dis.png"),
			}),
		},
	
		-- Progress bar
		npprogress = {
			position = LAYOUT_NONE,
			x = 322,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 110, 
			padding = { 12, 10, 0, 0 },-- 11
			order = { "elapsed", "slider", "remain" },
			elapsed = {
				w = 65,
				align = 'right',
				padding = { -14, 0, -10, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remain = {
				w = 65,
				align = 'left',
				padding = { 32, 0, -70, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = 65,
				align = 'right',
				padding = { -14, 0, -10, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remainSmall = {
				w = 65,
				align = 'left',
				padding = { 32, 0, -70, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			npprogressB = {
				w = 240,
				h = 50,
				border = { 8, 0, 0, 0 }, -- added
				padding = { 0, 0, 0, 0 },
		        position = LAYOUT_SOUTH,
				horizontal = 1,
				bgImg = _songProgressBackground,
				img = _songProgressBar,
			},
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			order = { "elapsed" },
			position = LAYOUT_NONE,
			x = 322,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 110,
			elapsed = {
				w = WH_FILL,
				align = "left",
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = WH_FILL,
				align = "left",
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
		},

	})

        s.nowplaying.npprogressNB.elapsedSmall = s.nowplaying.npprogressNB.elapsed -- fixed problem of large art not being able to move to next visusalizer
	-- sliders
	s.nowplaying.npprogress.npprogressB_disabled = _uses(s.nowplaying.npprogress.npprogressB, {
		img = _songProgressBarDisabled,
	})

	s.npvolumeB = {
		w = volumeBarWidth,
		border = { 5, 20, 5, 0 },
		padding = { 6, 0, 6, 0 },
                position = LAYOUT_SOUTH,
                horizontal = 1,
                bgImg = _volumeSliderBackground,
                img = _volumeSliderBar,
                pillImg = _volumeSliderPill,
	}
	s.npvolumeB_disabled = _uses(s.npvolumeB, {
		pillImg = false,
	})
        
	-- pressed styles
	s.nowplaying.title.pressed = _uses(s.nowplaying.title, {
		text = {
			fg = { 0xB3, 0xB3, 0xB3 },
			sh = { },
			bgImg = false,
		},
		lbutton = {
			bgImg = pressedTitlebarButtonBox,
		},
		rbutton = {
			bgImg = pressedTitlebarButtonBox,
		},
	})

	s.nowplaying.pressed = s.nowplaying
	s.nowplaying.nptitle.pressed = _uses(s.nowplaying.nptitle)
	s.nowplaying.npalbumgroup.pressed = _uses(s.nowplaying.npalbumgroup)
	s.nowplaying.npartistgroup.pressed = _uses(s.nowplaying.npartistgroup)
	s.nowplaying.npartwork.pressed = s.nowplaying.npartwork

	s.nowplaying.npcontrols.pressed = {
		rew     = _uses(s.nowplaying.npcontrols.rew, { bgImg = keyMiddlePressed }),
		play    = _uses(s.nowplaying.npcontrols.play, { bgImg = keyMiddlePressed }),
		pause   = _uses(s.nowplaying.npcontrols.pause, { bgImg = keyMiddlePressed }),
		fwd     = _uses(s.nowplaying.npcontrols.fwd, { bgImg = keyMiddlePressed }),
		repeatPlaylist  = _uses(s.nowplaying.npcontrols.repeatPlaylist, { bgImg = keyMiddlePressed }),
		repeatSong      = _uses(s.nowplaying.npcontrols.repeatSong, { bgImg = keyMiddlePressed }),
		repeatOff       = _uses(s.nowplaying.npcontrols.repeatOff, { bgImg = keyMiddlePressed }),
		repeatMode      = _uses(s.nowplaying.npcontrols.repeatMode, { bgImg = keyMiddlePressed }),
		shuffleAlbum    = _uses(s.nowplaying.npcontrols.shuffleAlbum, { bgImg = keyMiddlePressed }),
		shuffleSong     = _uses(s.nowplaying.npcontrols.shuffleSong, { bgImg = keyMiddlePressed }),
		shuffleMode     = _uses(s.nowplaying.npcontrols.shuffleMode, { bgImg = keyMiddlePressed }),
		shuffleOff      = _uses(s.nowplaying.npcontrols.shuffleOff, { bgImg = keyMiddlePressed }),
		shuffleDisabled = _uses(s.nowplaying.npcontrols.shuffleOff, { bgImg = keyMiddlePressed }),
		volDown = _uses(s.nowplaying.npcontrols.volDown, { bgImg = keyMiddlePressed }),
		volUp   = _uses(s.nowplaying.npcontrols.volUp, { bgImg = keyMiddlePressed }),

		thumbsUp    = _uses(s.nowplaying.npcontrols.thumbsUp, { bgImg = keyMiddlePressed }),
		thumbsDown  = _uses(s.nowplaying.npcontrols.thumbsDown, { bgImg = keyMiddlePressed }),
		thumbsUpDisabled    = s.nowplaying.npcontrols.thumbsUpDisabled,
		thumbsDownDisabled  = s.nowplaying.npcontrols.thumbsDownDisabled,
		love        = _uses(s.nowplaying.npcontrols.love, { bgImg = keyMiddlePressed }),
		hate        = _uses(s.nowplaying.npcontrols.hate, { bgImg = keyMiddlePressed }),
		fwdDisabled = _uses(s.nowplaying.npcontrols.fwdDisabled),
		rewDisabled = _uses(s.nowplaying.npcontrols.rewDisabled),
	}
	
	s.nowplaying_large_art = _uses(s.window, {
		--title bar
		title = {
                        zorder = 1,
                        x = 480,
                        w = 320,
                        h = TITLE_HEIGHT,
                        border = 0,
                        position = LAYOUT_NORTH,
                        bgImg = titleBox,
                        padding = { 0, 5, 0, 5 },
                        order = { "lbutton", "text", "rbutton" },
                        lbutton = {
                                border = { 8, 0, 8, 0 },
                                h = WH_FILL,
                            },
                        rbutton = {
                                border = { 8, 0, 8, 0 },
                                h = WH_FILL,
                        },
                        text = {
                                padding = { -70, 110, -80, 0 },
                                w = 160,
                                align = "left",
                                font = _boldfont(HELP_FONT_SIZE + 2),
                                fg = TEXT_COLOR,
                                bgImg = false,
                        }
                },
                        
	
		-- Song metadata
		nptitle = {
			order = { 'nptrack' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = 490,
                        y          = TITLE_HEIGHT + 80, 
			h          = NP_TRACK_FONT_SIZE+20, 
			nptrack =  {
				w          = screenWidth - 490 -10 ,
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _boldfont(NP_TRACK_FONT_SIZE - 10), 
				sh = TEXT_SH_COLOR,
			},
		},
		npartistgroup = {
			order = { 'npartist' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = 490,
                        y          = TITLE_HEIGHT + 32 + 32 + 100 -10,
			h          = NP_ARTISTALBUM_FONT_SIZE+20, 
			npartist = {
				padding    = { 0, 6, 0, 0 },
				w          = screenWidth - 490 - 10,
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _font(NP_ARTISTALBUM_FONT_SIZE -6),
				sh = TEXT_SH_COLOR,
			},
		},
		npalbumgroup = {
			order = {'npalbum' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = 490,
                        y          = TITLE_HEIGHT + 32 + 32 + 32 + 110 -5, 
			h          = NP_ARTISTALBUM_FONT_SIZE+20, 
			npalbum = {
				w          = screenWidth - 490 - 10,
				padding    = { 0, 6, 0, 0 },
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _font(NP_ARTISTALBUM_FONT_SIZE -6),
				sh = TEXT_SH_COLOR,
			},
		},
		npartistalbum = {
			hidden = 1,
		},
	
		-- cover art
		npartwork = {
			w = 480,
			position = LAYOUT_NONE,
			x = 0,
			y = 0,
			align = "center",
			h = 480,
			artwork = {
				w = 480,
				align = "center",
				padding = 0,
				img = false,
			},
		},

		npvisu = { hidden = 1 },
	
		--transport controls
		npcontrols = {
			order = { 'rew', 'div1', 'play', 'div2', 'fwd', 'div3', 'repeatMode' },
                        --order = { 'rew', 'div1', 'play', 'div2', 'fwd', 'div3', 'volDown', 'div4', 'volUp', 'div5' },
			position = LAYOUT_SOUTH,
			x = 480,
                        h = controlHeight,
			w = 320,
			bgImg = touchToolbarBackground,

			div1 = _uses(_transportControlBorder),
			div2 = _uses(_transportControlBorder),
			div3 = _uses(_transportControlBorder),
			div4 = _uses(_transportControlBorder),
			                        
			rew   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_rew.png"),
			}),
			play  = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_play.png"),
			}),
			pause = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_pause.png"),
			}),
			fwd   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_ffwd.png"),
			}),
			shuffleMode   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_off.png"),
			}),
			shuffleOff   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_off.png"),
			}),
			shuffleSong  = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_on.png"),
			}),
			shuffleAlbum = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_album_on.png"),
			}),
			repeatMode   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_off.png"),
			}),
			repeatOff   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_off.png"),
			}),
			repeatPlaylist = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_on.png"),
			}),
			repeatSong = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_song_on.png"),
			}),
			volDown   = _uses(_transportControlButton, {
				w = 34,
				img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
			}),
			volUp   = _uses(_transportControlButton, {
				w = 34,
				img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
			}),
			thumbsUp   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbup.png"),
			}),
			thumbsDown   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbdown.png"),
			}),
			thumbsUpDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbup_dis.png"),
			}),
			thumbsDownDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_thumbdown_dis.png"),
			}),
			love   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_love_on.png"),
			}),
			hate   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_love_off.png"),
			}),
			fwdDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_ffwd_dis.png"),
			}),
			rewDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_rew_dis.png"),
			}),
			shuffleDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_dis.png"),
			}),
			repeatDisabled   = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_dis.png"),
			}),
		},
	
		-- Progress bar
		npprogress = {
			position = LAYOUT_NONE,
			x = 480,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 120, 
			w = 200,
                        padding = { 12, 10, 0, 0 },-- 11
			order = { "elapsed", "slider", "remain" },
			elapsed = {
				w = 65,
				align = 'right',
				padding = { 0, 0, -10, 22 },
				font = _boldfont(24),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remain = {
				w = 65,
				align = 'left',
				padding = { 28, 0, -10, 22 },
				font = _boldfont(24),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = 65,
				align = 'right',
				padding = { 0, 0, -10, 22 },
				font = _boldfont(24),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remainSmall = {
				w = 65,--70
				align = 'left',
				padding = { 28, 0, -10, 22 },
				font = _boldfont(24),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			npprogressB = {
				w = 240,--nowplaying prgross bar 
				h = 50,
				border = { 8, 0, 0, 0 }, 
				padding = { 0, 0, 0, 0 },
		        position = LAYOUT_SOUTH,
				horizontal = 1,
				bgImg = _songProgressBackground,
				img = _songProgressBar,
			},
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			order = { "elapsed" },
			position = LAYOUT_NONE,
			x = 480,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 120, 
			padding = { 12, 10, 0, 0 },
                        elapsed = {
				w = WH_FILL,
				align = "left",
				font = _boldfont(24),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = WH_FILL,
				align = "left",
				font = _boldfont(24),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
		},

	})

	-- sliders
	s.nowplaying_large_art.npprogress.npprogressB_disabled = _uses(s.nowplaying_large_art.npprogress.npprogressB, {
		img = _songProgressBarDisabled,
	})

	s.npvolumeB = {
		w = volumeBarWidth,
		border = { 5, 20, 5, 0 },
		padding = { 6, 0, 6, 0 },
                position = LAYOUT_SOUTH,
                horizontal = 1,
                bgImg = _volumeSliderBackground,
                img = _volumeSliderBar,
                pillImg = _volumeSliderPill,
	}
	s.npvolumeB_disabled = _uses(s.npvolumeB, {
		pillImg = false,
	})

	-- pressed styles
	s.nowplaying_large_art.title.pressed = _uses(s.nowplaying_large_art.title, {
		text = {
			fg = { 0xB3, 0xB3, 0xB3 },
			sh = { },
			bgImg = false, --pressedTitlebarButtonBox,
		},
		lbutton = {
			bgImg = pressedTitlebarButtonBox,
		},
		rbutton = {
			bgImg = pressedTitlebarButtonBox,
		},
	})
        
	s.nowplaying_large_art.pressed = s.nowplaying_large_art
	s.nowplaying_large_art.nptitle.pressed = _uses(s.nowplaying_large_art.nptitle)
	s.nowplaying_large_art.npalbumgroup.pressed = _uses(s.nowplaying_large_art.npalbumgroup)
	s.nowplaying_large_art.npartistgroup.pressed = _uses(s.nowplaying_large_art.npartistgroup)
	s.nowplaying_large_art.npartwork.pressed = s.nowplaying_large_art.npartwork

	s.nowplaying_large_art.npcontrols.pressed = {
		rew     = _uses(s.nowplaying.npcontrols.rew, { bgImg = keyMiddlePressed }),
		play    = _uses(s.nowplaying.npcontrols.play, { bgImg = keyMiddlePressed }),
		pause   = _uses(s.nowplaying.npcontrols.pause, { bgImg = keyMiddlePressed }),
		fwd     = _uses(s.nowplaying.npcontrols.fwd, { bgImg = keyMiddlePressed }),
		repeatPlaylist  = _uses(s.nowplaying.npcontrols.repeatPlaylist, { bgImg = keyMiddlePressed }),
		repeatSong      = _uses(s.nowplaying.npcontrols.repeatSong, { bgImg = keyMiddlePressed }),
		repeatOff       = _uses(s.nowplaying.npcontrols.repeatOff, { bgImg = keyMiddlePressed }),
		repeatMode      = _uses(s.nowplaying.npcontrols.repeatMode, { bgImg = keyMiddlePressed }),
		shuffleAlbum    = _uses(s.nowplaying.npcontrols.shuffleAlbum, { bgImg = keyMiddlePressed }),
		shuffleSong     = _uses(s.nowplaying.npcontrols.shuffleSong, { bgImg = keyMiddlePressed }),
		shuffleMode     = _uses(s.nowplaying.npcontrols.shuffleMode, { bgImg = keyMiddlePressed }),
		shuffleOff      = _uses(s.nowplaying.npcontrols.shuffleOff, { bgImg = keyMiddlePressed }),
		shuffleDisabled = _uses(s.nowplaying.npcontrols.shuffleOff, { bgImg = keyMiddlePressed }),
		volDown = _uses(s.nowplaying.npcontrols.volDown, { bgImg = keyMiddlePressed }),
		volUp   = _uses(s.nowplaying.npcontrols.volUp, { bgImg = keyMiddlePressed }),

		thumbsUp    = _uses(s.nowplaying.npcontrols.thumbsUp, { bgImg = keyMiddlePressed }),
		thumbsDown  = _uses(s.nowplaying.npcontrols.thumbsDown, { bgImg = keyMiddlePressed }),
		thumbsUpDisabled    = s.nowplaying.npcontrols.thumbsUpDisabled,
		thumbsDownDisabled  = s.nowplaying.npcontrols.thumbsDownDisabled,
		love        = _uses(s.nowplaying.npcontrols.love, { bgImg = keyMiddlePressed }),
		hate        = _uses(s.nowplaying.npcontrols.hate, { bgImg = keyMiddlePressed }),
		fwdDisabled = _uses(s.nowplaying.npcontrols.fwdDisabled),
		rewDisabled = _uses(s.nowplaying.npcontrols.rewDisabled),
	}
        
        s.nowplaying_art_only = _uses(s.nowplaying, {

		bgImg = nocturneWallpaper,
		title            = { hidden = 1 },
		nptitle          = { hidden = 1 },
		npcontrols       = { hidden = 1 },
		npprogress       = { hidden = 1 },
		npprogressNB     = { hidden = 1 },
		npartistgroup    = { hidden = 1 },
		npalbumgroup     = { hidden = 1 },
		npartwork = {
			position = LAYOUT_CENTER,
			     w = WH_FILL,
			     h = WH_FILL,
			artwork = {
			    align = "center",
				img = false,
			    w = WH_FILL,
			    h = WH_FILL,
			},
		},

		npvisu = { hidden = 1 },

	})
	s.nowplaying_art_only.pressed = s.nowplaying_art_only

	s.nowplaying_text_only = _uses(s.nowplaying, {
		nptitle = { 
            x = 40,
            y = TITLE_HEIGHT + 70,  -- set to matach with art+info
             nptrack = {
                w = screenWidth - 80,
		font = _boldfont(NP_TRACK_FONT_SIZE), 
            },
		},
		npartistgroup = { 
            x = 40,
            y = TITLE_HEIGHT + 32 + 32 + 100 -20, 
            npartist =  {
                w = screenWidth - 80,
            },
		},
		npalbumgroup = { 
            x = 40,
            y = TITLE_HEIGHT + 32 + 32 + 32 + 110 -15, 
                npalbum =  {
                    w = screenWidth - 80,
            },
		},

		npartwork = { hidden = 1 },

		npvisu = { hidden = 1 },
		
		-- Progress bar
		npprogress = {
			position = LAYOUT_NONE,
			x = 50,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 110, 
			padding = { 0, 10, 0, 0 },
			order = { "elapsed", "slider", "remain" },
			elapsed = {
				w = 80,
				align = 'left',
				padding = { -8, 0, -10, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remain = {
				w = 80,
				align = 'right',
				padding = { 30, 0, -60, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = 80,
				align = 'left',
				padding = { -8, 0, -10, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remainSmall = {
				w = 80,
				align = 'right',
				padding = { 30, 0, -60, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			npprogressB = {
				w = 515,
				h = 50,
				padding     = { 0, 0, 0, 0 },
		                position = LAYOUT_SOUTH,
				horizontal = 1,
				bgImg = _songProgressBackground,
				img = _songProgressBar,
			},
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			order = { "elapsed" },
			position = LAYOUT_NONE,
			x = 40,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 110,
                        elapsed = {
				align = "left",
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = WH_FILL,
				align = "left",
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
		},
	})
	s.nowplaying_text_only.npprogress.npprogressB_disabled = _uses(s.nowplaying_text_only.npprogress.npprogressB, {
		img = _songProgressBarDisabled,
	})
	s.nowplaying_text_only.pressed = s.nowplaying_text_only
	s.nowplaying_text_only.nptitle.pressed = _uses(s.nowplaying_text_only.nptitle)
	s.nowplaying_text_only.npalbumgroup.pressed = _uses(s.nowplaying_text_only.npalbumgroup)
	s.nowplaying_text_only.npartistgroup.pressed = _uses(s.nowplaying_text_only.npartistgroup)

	-- Visualizer: Container with titlebar, progressbar and controls.
	--  The space between title and controls is used for the visualizer.
	s.nowplaying_visualizer_common = _uses(s.nowplaying, {
		bgImg = nocturneWallpaper,

		npartistgroup = { hidden = 1 },
		npalbumgroup = { hidden = 1 },
		npartwork = { hidden = 1 },

		title = _uses(s.title, {
			zOrder = 1,
			h = TITLE_HEIGHT,
			text = {
				-- Hack: text needs to be there to fill the space, but is not visible
				font = _font(0), -- needed, otherwise NowPlaying text visbile when switching to playlist
                                padding = { screenWidth, 0, 0, 0 }
			},
		}),

		-- Drawn over regular info between buttons
		nptitle = { 
			zOrder = 2,
			position = LAYOUT_NONE,
			x = 100,
			y = 3,
			w = screenWidth - 200,
			h = TITLE_HEIGHT+30,
			border = { 0, 0 ,0, 0 },
			padding = { 0, 14, 0, 0 },
			nptrack = {
				align = "center",
				font = _boldfont(TITLE_FONT_SIZE), 
                        w = screenWidth - 179,
			},
		},

		npartistalbum = {
			hidden = 0,
			zOrder = 2,
			position = LAYOUT_NONE,
			x = 0,
			y = TITLE_HEIGHT,
			w = screenWidth,
			h = 60,
			bgImg = titleBox,
			align = "center",
			fg = { 0xb3, 0xb3, 0xb3 },
			padding = { 130, 0, 130, 10 }, 
			font = _font(NP_ARTISTALBUM_FONT_SIZE),
		},

		npprogress = {
			zOrder = 3,
			position = LAYOUT_NONE,
			x = 10,
			y = TITLE_HEIGHT + 10, 
			h = 60,
			w = screenWidth - 30,
			elapsed = {
				w = 90, 
				align = 'left',
				padding = { -2, 10, 0, 55 }, 
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = TEXT_COLOR_TIME_VIS,
                        },
			remain = {
				w = 90,
				align = 'right',
				padding = { 10, 10, 0, 55 }, 
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = TEXT_COLOR_TIME_VIS,
                        },
			elapsedSmall = {
				w = 90,
				align = 'left',
				padding = { -2, 10, 0, 55 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = TEXT_COLOR_TIME_VIS,
                        },
			remainSmall = {
				w = 90,
				align = 'right',
				padding = { 10, 10, 0, 55 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = TEXT_COLOR_TIME_VIS,
                                -- border = 0,
			},
			npprogressB = {
				x = 20, 
                                y = TITLE_HEIGHT + 20,
                                h = 60,
                                w = WH_FILL,
				padding = { 0, 18, 0, 8 }, -- second number y-shift, third, x-shift progress bar
				horizontal = 1,
				bgImg = false,
				img = _vizProgressBar,
                		pillImg = _vizProgressBarPill,
			},
		},

		npprogressNB = {
			zOrder = 3,
			position = LAYOUT_NONE,
			x = 22,
			y = TITLE_HEIGHT + 15, 
			h = 60,
			w = screenWidth - 30,
			elapsed = {
				w = 90, 
				align = 'left',
				padding = { -2, 10, 0, 55 }, 
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = TEXT_COLOR_TIME_VIS,
                        },
                        elapsedSmall = {
				w = 90,
				align = 'left',
				padding = { -2, 10, 0, 55 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = TEXT_COLOR_TIME_VIS,
                        },
                },
	})
	s.nowplaying_visualizer_common.npprogress.npprogressB_disabled = s.nowplaying_visualizer_common.npprogress.npprogressB

	-- pressed styles
	        
	s.nowplaying_visualizer_common.pressed = s.nowplaying_visualizer_common
	s.nowplaying_visualizer_common.nptitle.pressed = _uses(s.nowplaying_visualizer_common.nptitle)
	s.nowplaying_visualizer_common.npalbumgroup.pressed = _uses(s.nowplaying_visualizer_common.npalbumgroup)
	s.nowplaying_visualizer_common.npartistgroup.pressed = _uses(s.nowplaying_visualizer_common.npartistgroup)
	
               
        
        -- Visualizer: Spectrum Visualizer
	s.nowplaying_spectrum_text = _uses(s.nowplaying_visualizer_common, {
		npvisu = {
			hidden = 0,
			position = LAYOUT_NONE,
			x = 0,
			y = 2 * TITLE_HEIGHT + 4,
			w = screenWidth,
			h = 446 - (2 * TITLE_HEIGHT + 4 + 45), 
			border = { 0, 0, 0, 0 },
			padding = { 0, 0, 0, 0 },

			spectrum = {
				position = LAYOUT_NONE,
				x = 0,
				y = 2 * TITLE_HEIGHT + 4,
				w = screenWidth,
				h = 446 - (2 * TITLE_HEIGHT + 4 + 45), 
				border = { 0, 0, 0, 0 },
				padding = { 0, 0, 0, 0 },

				bg = { 0x00, 0x00, 0x00, 0x00 },

				barColor = { 0xbe, 0xbe, 0xbe, 0xff }, 
                                capColor = { 0x14, 0xbc, 0xbc, 0xff }, -- changed to cyan for consistant look with other visualizers
                                

				isMono = 0,				-- 0 / 1

				capHeight = { 6, 6 },			-- >= 0
				capSpace = { 4, 4 },			-- >= 0
				channelFlipped = { 0, 1 },		-- 0 / 1
				barsInBin = { 1, 1 },			-- > 1
				barWidth = { 6, 6 },			-- > 1 -- was 1
				barSpace = { 3, 3 },			-- >= 0
				binSpace = { 6, 6 },			-- >= 0
				clipSubbands = { 1, 1 },		-- 0 / 1
			}
		},
	})
	s.nowplaying_spectrum_text.pressed = s.nowplaying_spectrum_text

	s.nowplaying_spectrum_text.title.pressed = _uses(s.nowplaying_spectrum_text.title, {
		text = {
			-- Hack: text needs to be there to fill the space, not visible
			padding = { screenWidth, 0, 0, 0 }
		},
	})

	-- Visualizer: Analog VU Bar
	s.nowplaying_vubar_new_text = _uses(s.nowplaying, {
		nptitle = { 
            x = 40,
            y = TITLE_HEIGHT + 70,  -- was 50 set to matach with art+info
             nptrack = {
                w = screenWidth - 270,
		font = _boldfont(NP_TRACK_FONT_SIZE), 
            },
		},
		npartistgroup = { 
            x = 40,
            y = TITLE_HEIGHT + 32 + 32 + 100 -20, 
            npartist =  {
                w = screenWidth - 270,
            },
		},
		npalbumgroup = { 
            x = 40,
            y = TITLE_HEIGHT + 32 + 32 + 32 + 110 -15, 
                npalbum =  {
                    w = screenWidth - 270,
            },
		},

		npartwork = { hidden = 1 },

		npvisu = {
			hidden = 0,
			position = LAYOUT_NONE,
			x = 540,
			y = TITLE_HEIGHT,
			w = screenWidth,
			h = 480 - 2 * TITLE_HEIGHT, 
			border = { 0, 0, 0, 0 },
			padding = { 0, 0, 0, 0 },
                                                
			vumeter_analog = {
				position = LAYOUT_NONE,
                                x = 540,
                                y = TITLE_HEIGHT,
                                w = screenWidth,
                                h = 480 - 2 * TITLE_HEIGHT, 
                                border = { 0, 0, 0, 0 },
                                padding = { 0, 0, 0, 0 },
                                bgImg = Tile:fillColor(0x00000000),
                                offColor = { 0x50, 0x50, 0x50, 0x80 },
                                lowColor = { 0xff, 0xff, 0xff, 0xff },
                                midColor = { 0xff, 0x46, 0x00, 0xff },
                                highColor = { 0x00, 0xff, 0xff, 0xff },
                                }
		},
		
		-- Progress bar
		npprogress = {
			position = LAYOUT_NONE,
			x = 50,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 110, 
			padding = { 0, 10, 0, 0 },
			order = { "elapsed", "slider", "remain" },
			elapsed = {
				w = 80,
				align = 'left',
				padding = { -8, 0, -10, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remain = {
				w = 80,
				align = 'right',
				padding = { 30, 0, -60, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = 80,
				align = 'left',
				padding = { -8, 0, -10, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remainSmall = {
				w = 80,
				align = 'right',
				padding = { 30, 0, -60, 22 },
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			npprogressB = {
				w = 330,
				h = 50,
				padding     = { 0, 0, 0, 0 },
		                position = LAYOUT_SOUTH,
				horizontal = 1,
				bgImg = _songProgressBackground,
				img = _songProgressBar,
			},
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			order = { "elapsed" },
			position = LAYOUT_NONE,
			x = 40,
			y = TITLE_HEIGHT + 29 + 26 + 32 + 32 + 23 + 110,
                        elapsed = {
				align = "left",
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = WH_FILL,
				align = "left",
				font = _boldfont(NP_PROGRESS_BAR_FONT_SIZE),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
		},
	})
	s.nowplaying_vubar_new_text.npprogress.npprogressB_disabled = _uses(s.nowplaying_vubar_new_text.npprogress.npprogressB, {
		img = _songProgressBarDisabled,
	})
	s.nowplaying_vubar_new_text.pressed = s.nowplaying_vubar_new_text
	s.nowplaying_vubar_new_text.nptitle.pressed = _uses(s.nowplaying_vubar_new_text.nptitle)
	s.nowplaying_vubar_new_text.npalbumgroup.pressed = _uses(s.nowplaying_vubar_new_text.npalbumgroup)
	s.nowplaying_vubar_new_text.npartistgroup.pressed = _uses(s.nowplaying_vubar_new_text.npartistgroup)

        -- Visualizer: Analog VU Meter
	s.nowplaying_vuanalog_new_text = _uses(s.nowplaying_visualizer_common, {
		npvisu = {
			hidden = 0,
			position = LAYOUT_NONE,
			x = 0,
			y = 2 * TITLE_HEIGHT - 5,
			w = screenWidth,
			h = 284, 
			border = { 0, 0, 0, 0 },
			padding = { 0, 0, 0, 0 },
                                                
			vumeter_analog = {
				position = LAYOUT_NONE,
                                x = 0,
                                y = 2 * TITLE_HEIGHT - 5,
                                w = screenWidth,
                                h = 284, 
                                border = { 0, 0, 0, 0 },
                                padding = { 0, 0, 0, 0 },
                                bgImg = _loadImageTile(self, imgpath .. "UNOFFICIAL/VUMeter/Analog_VU.png"), 
                                dialColor = { 0xff, 0x46, 0x00, 0xff },
                                }
		},
	})
	s.nowplaying_vuanalog_new_text.pressed = s.nowplaying_vuanalog_new_text

	s.nowplaying_vuanalog_new_text.title.pressed = _uses(s.nowplaying_vuanalog_new_text.title, {
		text = {
			-- Hack: text needs to be there to fill the space, not visible
			padding = { screenWidth, 0, 0, 0 }
		},
	})
        
	s.brightness_group = {
		order = {  'down', 'div1', 'slider', 'div2', 'up' },
		position = LAYOUT_SOUTH,
		h = 56,
		w = WH_FILL,
		bgImg = sliderBackground,

		div1 = _uses(_transportControlBorder),
		div2 = _uses(_transportControlBorder),

		down   = _uses(_transportControlButton, {
			w = 56,
			h = 56,
			img = _loadImage(self, "Icons/icon_toolbar_brightness_down.png"),
		}),
		up   = _uses(_transportControlButton, {
			w = 56,
			h = 56,
			img = _loadImage(self, "Icons/icon_toolbar_brightness_up.png"),
		}),
	}
	s.brightness_group.pressed = {

		down   = _uses(s.brightness_group.down, { bgImg = sliderButtonPressed }),
		up   = _uses(s.brightness_group.up, { bgImg = sliderButtonPressed }),
	}

	s.brightness_slider = {
		w = WH_FILL,
		border = { 5, 12, 5, 0 },
		padding = { 6, 0, 6, 0 },
                position = LAYOUT_SOUTH,
                horizontal = 1,
                bgImg = _volumeSliderBackground,
                img = _volumeSliderBar,
                pillImg = _volumeSliderPill,
	}
	
	s.settings_slider_group = _uses(s.brightness_group, {
		down = {
			img = _loadImage(self, "Icons/icon_toolbar_minus.png"),
		},
		up = {
			img = _loadImage(self, "Icons/icon_toolbar_plus.png"),
		},
	})

	s.settings_slider = _uses(s.brightness_slider, {
	})
	s.settings_slider_group.pressed = {
		down = _uses(s.settings_slider_group.down, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_minus_dis.png"),
		}),
		up = _uses(s.settings_slider_group.up, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_plus_dis.png"),
		}),
	}

	s.settings_volume_group = _uses(s.brightness_group, {
		down = {
			img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
		},
		up = {
			img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
		},
	})
	s.settings_volume_group.pressed = {
		down = _uses(s.settings_volume_group.down, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_vol_down_dis.png"),
		}),
		up = _uses(s.settings_volume_group.up, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_vol_up_dis.png"),
		}),
	}

	s.debug_canvas = {
			zOrder = 9999
	}

        s.demo_text = {
                font = _boldfont(18),
                position = LAYOUT_SOUTH,
                w = screenWidth,
		h = 50,
                align = 'center',
                padding = { 6, 0, 6, 10 },
                fg = TEXT_COLOR,
                sh = TEXT_SH_COLOR,
        }

	return s

end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

