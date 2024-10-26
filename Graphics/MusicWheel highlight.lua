local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2
local item_width = _screen.w / 2.125

return Def.Sprite{
	Texture=THEME:GetPathB("ScreenSelectMusic", "overlay/PerPlayer/arrow.png"),
	InitCommand=function(self)
		self:zoom(1.0)
		self:bounce():effectclock("beatnooffset"):effectmagnitude(-6,0,0):effectperiod(1)
		self:xy(30, 0)
	end,
}

--return Def.Quad{ 
--	InitCommand=function(self) self:horizalign(left):x(WideScale(28,33) - 10):zoomto(item_width + 10,_screen.h/num_visible_items-1) end
--}