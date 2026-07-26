local path = "/"..THEME:GetCurrentThemeDirectory().."Graphics/_FallbackBanners/"..ThemePrefs.Get("VisualStyle")
local banner_directory = FILEMAN:DoesFileExist(path) and path or THEME:GetPathG("","_FallbackBanners/Arrows")

local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()

local bannerWidth = 418
local bannerHeight = 164

local t = Def.ActorFrame{
	-- Position and zoom both come from Scripts/SL-Layout-SelectMusic.lua: this banner
	-- sets the width of every card in the left column, so the two cannot be allowed to
	-- drift apart. Children are laid out in pre-zoom units and scale with the frame.
	OnCommand=function(self)
		self:zoom(SSM.banner_zoom)
		self:xy(SSM.column.cx, SSM.cards.banner.cy)
	end
}

-- Hairline frame around the banner art, in the player's color.
--
-- Drawn first and 2px larger on every side, so it survives as a ring once the art
-- covers its middle. One ring serves both the fallback sprite and the ActorProxy: the
-- screen's own Banner actor is scaletoclipped to 418x164 by [ScreenSelectMusic]
-- BannerOnCommand, the same dimensions the fallback sprite is set to below, and the
-- metric parks it at BannerX/Y 0 so the proxy adds no offset of its own.
t[#t+1] = Def.Quad{
	Name="BannerFrame",
	InitCommand=function(self)
		self:setsize(bannerWidth + 4, bannerHeight + 4)
		self:diffuse( DimColor(PlayerColor(PLAYER_1), 1.0, 0.45) )
	end
}

-- fallback banner
t[#t+1] = Def.Sprite{
	Name="FallbackBanner",
	Texture=banner_directory.."/banner"..SL.Global.ActiveColorIndex.." (doubleres).png",
	InitCommand=function(self) self:setsize(bannerWidth, bannerHeight) end,

	CurrentSongChangedMessageCommand=function(self) self:playcommand("Set") end,
	CurrentCourseChangedMessageCommand=function(self) self:playcommand("Set") end,

	SetCommand=function(self)
		-- if ShowBanners preference is false, always just show the fallback banner
		-- don't bother assessing whether to draw or not draw
		if PREFSMAN:GetPreference("ShowBanners") == false then return end

		if SongOrCourse and SongOrCourse:HasBanner() then
			self:visible(false)
		else
			self:visible(true)
		end
	end
}

if PREFSMAN:GetPreference("ShowBanners") then
	t[#t+1] = Def.ActorProxy{
		Name="BannerProxy",
		BeginCommand=function(self)
			local banner = SCREENMAN:GetTopScreen():GetChild('Banner')
			self:SetTarget(banner)
		end
	}
end

-- the MusicRate Quad and text
t[#t+1] = Def.ActorFrame{
	InitCommand=function(self)
		self:visible( SL.Global.ActiveModifiers.MusicRate ~= 1 ):y(75)
	end,

	--quad behind the music rate text
	Def.Quad{
		InitCommand=function(self) HUDPanel(self):zoomto(418,14) end
	},

	--the music rate text
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self) self:shadowlength(1):zoom(0.85):diffuse(HUD_TEXT) end,
		OnCommand=function(self)
			self:settext(("%g"):format(SL.Global.ActiveModifiers.MusicRate) .. "x " .. THEME:GetString("OptionTitles", "MusicRate"))
		end
	}
}

if not GAMESTATE:IsCourseMode() then
	t[#t+1] = Def.Sprite {
		OnCommand=function(self)
			self:draworder(101)
			self:playcommand("SetCD")
		end,
		OffCommand=function(self)
			self:bouncebegin(0.15)
		end,
		CurrentSongChangedMessageCommand=function(self) self:playcommand("SetCD") end,
		SwitchFocusToGroupsMessageCommand=function(self) self:GetChild("CdTitle"):visible(false) end,
		SetCDCommand=function(self)
			SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()
			if SongOrCourse and SongOrCourse:HasCDTitle() then
				self:visible(true)
				self:Load( GAMESTATE:GetCurrentSong():GetCDTitlePath() )
				local dim1, dim2 = math.max(self:GetWidth(), self:GetHeight()), math.min(self:GetWidth(), self:GetHeight())
				local ratio = math.max(dim1 / dim2, 2.5)

				local toScale = self:GetWidth() > self:GetHeight() and self:GetWidth() or self:GetHeight()
				self:xy((bannerWidth - 30) / 2, (bannerHeight - 30)/ 2)
				self:zoom(22 / toScale * ratio)
				self:finishtweening():addrotationy(0):linear(.5):addrotationy(360)
			else
				self:visible(false)
			end
		end
	}
end

return t