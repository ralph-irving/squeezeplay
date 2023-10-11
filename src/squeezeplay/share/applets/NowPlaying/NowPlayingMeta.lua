local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function defaultSettings(self)
	return {
		scrollText = true,
		scrollTextOnce = false,
		views = {},
		doubleClickMode = false,
		doubleClickInterval = 500,
	}
end

function registerApplet(self)

	jiveMain:addItem(
		self:menuItem(
			'appletNowPlayingScrollMode', 
			'screenSettingsNowPlaying', 
			'SCREENSAVER_SCROLLMODE', 
			function(applet, ...) 
				applet:scrollSettingsShow(...) 
			end,
			2
		)
	)
	jiveMain:addItem(
		self:menuItem(
			'appletNowPlayingViewsSettings', 
			'screenSettingsNowPlaying', 
			'NOW_PLAYING_VIEWS', 
			function(applet, ...) 
				applet:npviewsSettingsShow(...) 
			end,
			1
		)
	)
	jiveMain:addItem(
		self:menuItem(
			'appletNowPlayingClickMode',
			'screenSettingsNowPlaying',
			'NOW_PLAYING_CLICK_MODE',
			function(applet, ...)
				applet:clickModeSettingsShow(...)
			end,
			3
		)
	)
	jiveMain:addItem(
		self:menuItem(
			'appletNowPlayingClickInterval',
			'screenSettingsNowPlaying',
			'NOW_PLAYING_CLICK_INTERVAL',
			function(applet, ...)
				applet:clickIntervalSettingsShow(...)
			end,
			4
		)
	)
	self:registerService('goNowPlaying')
	self:registerService("hideNowPlaying")

end


function configureApplet(self)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_NOWPLAYING"), 
		"NowPlaying", 
		"openScreensaver", 
		_,
		_,
		10,
		nil,
		nil,
		nil,
		{"whenOff"}
	)

	-- NowPlaying is a resident applet
	appletManager:loadApplet("NowPlaying")

end

