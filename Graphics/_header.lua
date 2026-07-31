-- tables of rgba values
local dark  = {0,0,0,0.9}
local light = {0.65,0.65,0.65,1}

return Def.ActorFrame{
	Name="Header",

	Def.Quad{
		InitCommand=function(self)
			self:zoomto(_screen.w, 32):vertalign(top):x(_screen.cx)
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
			if SL.Global.GameMode == "Casual" and (topscreen == "ScreenEvaluationStage" or topscreen == "ScreenEvaluationSummary") then
				self:diffuse(dark)
			end
			if ThemePrefs.Get("VisualStyle") == "SRPG8" then
				self:diffuse(GetCurrentColor(true))
			end
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0)
			end

			-- ScreenSelectMusic draws its own header band, inside the overlay, in
			-- BGAnimations/ScreenSelectMusic overlay/PackRail.lua -- for the same
			-- reason the footer does (see Graphics/_footer.lua): the engine sorts a
			-- screen's children by draw order once, at Init, so the metrics force
			-- this quad to 101 and it would cover the overlay content that belongs
			-- on top of it. The header's own text stays above the overlay band
			-- because it is a sibling of this quad, still at 101.
			self:visible(topscreen ~= "ScreenCRTTestPatterns"
			         and topscreen ~= "ScreenSelectMusic")
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
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
		Name="HeaderText",
		Text=ScreenString("HeaderText"),
		InitCommand=function(self) self:diffusealpha(0):horizalign(left):xy(20, 15):zoom( SL_WideScale(0.7,0.7) ) end,
		OnCommand=function(self) self:sleep(0.1):decelerate(0.33):diffusealpha(1) end,
		OffCommand=function(self) self:accelerate(0.33):diffusealpha(0) end,
		SetHeaderTextMessageCommand=function(self, params)
			self:settext(params.Text)
		end,
		ResetHeaderTextMessageCommand=function(self)
			self:settext(THEME:GetString(SCREENMAN:GetTopScreen():GetName(), "HeaderText"))
		end
	},

	-- A quieter tail after the header, for a counter or a position that belongs with the
	-- title but must not compete with it. ScreenEvaluation uses it for "(5 / 6)" beside the
	-- pane name; every other screen simply never broadcasts to it and it stays empty.
	--
	-- It measures the header rather than sitting at a fixed x, because the header's width
	-- changes with the screen, the language and -- on evaluation -- the pane. HeaderText
	-- carries no maxwidth, so GetZoomedWidth is its true drawn width.
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
		Name="HeaderSuffix",
		Text="",
		InitCommand=function(self)
			self:diffusealpha(0):horizalign(left):xy(20, 15)
			self:zoom( SL_WideScale(0.7,0.7) * 0.62 ):diffuse(HUD_LABEL)
		end,
		OnCommand=function(self) self:sleep(0.1):decelerate(0.33):diffusealpha(1) end,
		OffCommand=function(self) self:accelerate(0.33):diffusealpha(0) end,
		SetHeaderSuffixMessageCommand=function(self, params)
			self:settext(params.Text or "")

			local main = self:GetParent() and self:GetParent():GetChild("HeaderText")
			self:x( 20 + (main and main:GetZoomedWidth() or 0) + 8 )
		end,
	}
}
