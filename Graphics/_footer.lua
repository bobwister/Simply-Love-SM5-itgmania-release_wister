-- tables of rgba values
local dark  = {0,0,0,0.9}
local light = {0.65,0.65,0.65,1}

return Def.Quad{
	Name="Footer",
	InitCommand=function(self)
		self:draworder(90):zoomto(_screen.w, 32):vertalign(bottom):y(32)
		if ThemePrefs.Get("VisualStyle") == "SRPG8" then
			self:diffuse(GetCurrentColor(true))
		elseif DarkUI() then
			self:diffuse(dark)
		elseif ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0)
		else
			self:diffuse(light)
		end
	end,
	ScreenChangedMessageCommand=function(self)
		local topscreen = SCREENMAN:GetTopScreen():GetName()
		if topscreen == "ScreenSelectMusicCasual" then
			self:diffuse(dark)
		end
		if ThemePrefs.Get("VisualStyle") == "SRPG8" then
			self:diffuse(GetCurrentColor(true))
		end
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0)
		end

		-- ScreenSelectMusic draws its own footer band, inside the overlay, in
		-- BGAnimations/ScreenSelectMusic overlay/Footer.lua. It has to: the
		-- engine sorts a screen's children by draw order once, during Init, so a
		-- draw order set from a metrics OnCommand never re-sorts and this quad
		-- would keep covering the overlay content that belongs on top of it.
		-- Band and content are siblings there, so they stack predictably.
		self:visible(topscreen ~= "ScreenSelectMusic")
	end,
	ColorSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "SRPG8" then
			self:diffuse(GetCurrentColor(true))
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0)
		end
	end,
}
