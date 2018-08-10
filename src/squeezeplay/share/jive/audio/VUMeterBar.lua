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

local amp_offset    = 100
local cx            = { 620, 700 }
local cy            = 370
local bar_gap       = 4
local samples       = 4096 -- 1 to max of 8192, sets the analog response function (number of samples to average)
local num_bars      = 20
local tw            = 60
local th            = 9 -- must be an odd number as the radius of the end cap is calculated as (th + 1) / 2 and must be an interger
local cr            = (th + 1) / 2
local over_corr     = (16/44)*num_bars

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
        
        self.offColor = self:styleColor("offColor", { 0x50, 0x50, 0x50, 0x80 })
               
        self.lowColor = self:styleColor("lowColor", { 0xff, 0xff, 0xff, 0xff })
        
        self.midColor = self:styleColor("midColor", { 0xff, 0x46, 0x00, 0xff })
        
        self.highColor = self:styleColor("highColor", { 0x00, 0xff, 0xff, 0xff })
end


function draw(self, surface)
	        
        sampleAcc = decode:vumeter(samples)       
	
        _drawMeter(self, surface, sampleAcc, 1)
	_drawMeter(self, surface, sampleAcc, 2)
        
end


function _drawMeter(self, surface, sampleAcc, ch)
	        
        local amp_ch = (math.log((sampleAcc[ch]+amp_offset)/105))/0.0874
        
            if amp_ch <= 0 then
                amp_ch = 0
            end
            
        local amp_corr = (amp_ch/44)*num_bars
        
        local rec_x1 = cx[ch] + cr / 2
        local rec_y1 = cy 
        local rec_x2 = cx[ch] + tw - 2 * cr
        local rec_y2 = cy + th 
                
        local cir_l_x = cx[ch] + 1
        local cir_l_y = cy -1 + cr 
                
        local cir_r_x = cx[ch] + 1 + tw - 2 * cr
        local cir_r_y = cy + cr 
        
        local gap = th + bar_gap 
        
        for i = 1, num_bars do
            
            tick_color = self.offColor
            
            if i < amp_corr then
                
                if i < over_corr * 2 then
                    
                    if i < over_corr then
                            
                            tick_color = self.lowColor
                    
                    else
                        
                        tick_color = self.highColor
                    
                    end
                    
                    else
                    
                        tick_color = self.midColor
                
                    end
                
                end
        
            surface:filledRectangle(
                    rec_x1,
                    rec_y1 - gap * i,
                    rec_x2,
                    rec_y2 - gap * i,
                    tick_color
                    )
            
            surface:filledPie(
                    cir_l_x,
                    cir_l_y - gap * i,
                    cr,
                    90,
                    269,
                    tick_color
                    )
            
            surface:filledPie(
                    cir_r_x,
                    cir_r_y - gap * i,
                    cr,
                    270,
                    89,
                    tick_color
                    )
        
        end
        
end


--[[

=head1 LICENSE



=cut
--]]

