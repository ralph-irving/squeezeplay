local oo            = require("loop.simple")
local math          = require("math")

local Framework     = require("jive.ui.Framework")
local Icon          = require("jive.ui.Icon")
local surface       = require("jive.ui.Surface")
local Timer         = require("jive.ui.Timer")
local Widget        = require("jive.ui.Widget")

local decode        = require("squeezeplay.decode")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("audio.decode")

local FRAME_RATE    = jive.ui.FRAME_RATE

local amp_offset    = 100 -- offset of amplitude to allow "low levels" to be visualized
local dial_length   = 220 -- lenght of dials
local dial_hide     = 38  -- lenght of dials (from center outward) to hide as this is made to look like it is behind the dial cover of the bgImg
local dial_cx       = { 192, 590 } -- center x poistion of left and right dial 
local dial_cy       = 435 -- center y position of dials
local over_x        = { 370, 768 } -- posstion of over indicator for both left and right
local over_y        = 261 -- center y position for over indicators
local over_radius   = 10 -- radius of the over light indicator
local thickr        = 2 -- thickness of the dial
local shadow_color  = 50 -- dial shadow color (do not use full hex code code due to the way the gradient is produced)
local shadow_thick  = 8 -- dial shadow thickness
local over_draw     = 3 -- needed to prevent poor drawing of the dial
local samples       = 8192 -- 1 to max of 8192, sets the analog response function (number of samples to average)

module(...)
oo.class(_M, Icon)


function __init(self, style)
	local obj = oo.rawnew(self, Icon(style))

	obj.style = style

	obj:addAnimation(function() obj:reDraw() end, FRAME_RATE)

	return obj
end


function _skin(self)
	Icon._skin(self)
	            
        self.bgImg = self:styleImage("bgImg")
        
        self.dialColor = self:styleColor("dialColor", { 0xff, 0x46, 0x00, 0xff })

        self.overColor = self:styleColor("overColor", { 0x00, 0xff, 0xff, 0xA0 }) 
end


function draw(self, surface)
	        
        self.bgImg:blit(surface, self:getBounds())
        
        local sampleAcc = decode:vumeter(samples)       
	
        _drawMeter(self, surface, sampleAcc, 1)
	_drawMeter(self, surface, sampleAcc, 2)
        
end


function _drawMeter(self, surface, sampleAcc, ch)
	        
        local amp_ch = (math.log((sampleAcc[ch]+amp_offset)/105))/0.0874
        
            if amp_ch <= 0 then
                amp_ch = 0
            end
                      
        local dial_angle = ((83/45) * amp_ch) - 41.5
        
            if dial_angle >= 45 then
                dial_angle = 45
            end
        
        local dial_x2 = math.sin(math.rad(dial_angle)) * dial_length
        local dial_y2 = math.cos(math.rad(dial_angle)) * dial_length
        local dial_x1 = math.sin(math.rad(dial_angle)) * dial_hide
        local dial_y1 = math.cos(math.rad(dial_angle)) * dial_hide
        
        local x1 = dial_cx[ch] + dial_x1  
        local y1 = dial_cy - dial_y1
        local x2 = dial_cx[ch] + dial_x2 
        local y2 = dial_cy - dial_y2
                
        local sx1 = x1 + thickr
        local sx2 = x2 + thickr
        local abs = math.abs
        
        for n = 1, over_draw do
        
            for shd = -1*shadow_thick, shadow_thick do
                surface:aaline(
                    sx1 + shd,
                    y1,
                    sx2 + shd,
                    y2,
                    shadow_color / abs(shd)
                )
            end
            
            
            for tck = -1*thickr, thickr do
                surface:aaline(
                    x1 + tck,
                    y1,
                    x2 + tck,
                    y2,
                    self.dialColor
                )
            end        
            
            surface:filledCircle(
                x2,
                y2,
                thickr,
                self.dialColor
            )
        
        end
        
        if dial_angle >= 20 then
                surface:filledCircle(
                    over_x[ch],
                    over_y,
                    over_radius,
                    self.overColor
                )
        end
end


--[[

=head1 LICENSE



=cut
--]]

