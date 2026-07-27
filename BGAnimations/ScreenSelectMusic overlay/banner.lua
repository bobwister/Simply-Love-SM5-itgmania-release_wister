local path = "/"..THEME:GetCurrentThemeDirectory().."Graphics/_FallbackBanners/"..ThemePrefs.Get("VisualStyle")
local banner_directory = FILEMAN:DoesFileExist(path) and path or THEME:GetPathG("","_FallbackBanners/Arrows")

local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()

local bannerWidth = 418
local bannerHeight = 164

-- This frame is zoomed as a whole, so every child below is laid out in PRE-ZOOM units:
-- divide any target screen size by SSM.banner.zoom to get the number to write here.
local CARD_W = SSM.column.w        / SSM.banner.zoom
local CARD_H = SSM.cards.banner.h  / SSM.banner.zoom

-- How far left of the card's centre the art sits.
--
-- The art fills the card edge to edge again (SSM.banner.zoom is derived from the column
-- width), so this is 0 and the expression is kept only because it is what says so: shrink
-- the art below the column width in the layout table and everything below re-pins itself
-- to the left of the card, which is where it used to live to leave room for the
-- leaderboard.
local ART_DX = (bannerWidth - CARD_W) / 2

local t = Def.ActorFrame{
	-- Position and zoom both come from the shared layout table.
	OnCommand=function(self)
		self:zoom(SSM.banner.zoom)
		self:xy(SSM.column.cx, SSM.cards.banner.cy)
	end,

	-- Card background. Nothing shows of it while the art is the full width of the card;
	-- it is what fills the gap if the art is ever scaled down again.
	Def.Quad{
		Name="BannerCard",
		InitCommand=function(self)
			HUDPanel(self):zoomto(CARD_W, CARD_H)
		end
	}
}

-- Hairline frame around the banner art, in the player's color.
--
-- Drawn before the art and 2px larger on every side, so it survives as a ring once the
-- art covers its middle. One ring serves both the fallback sprite and the ActorProxy: the
-- screen's own Banner actor is scaletoclipped to 418x164 by [ScreenSelectMusic]
-- BannerOnCommand, the same dimensions the fallback sprite is set to below, and the
-- metric parks it at BannerX/Y 0 so the proxy adds no offset of its own.
t[#t+1] = Def.Quad{
	Name="BannerFrame",
	InitCommand=function(self)
		self:setsize(bannerWidth + 4, bannerHeight + 4):x(ART_DX)
		self:diffuse( DimColor(PlayerColor(PLAYER_1), 1.0, 0.45) )
	end
}

-- fallback banner
t[#t+1] = Def.Sprite{
	Name="FallbackBanner",
	Texture=banner_directory.."/banner"..SL.Global.ActiveColorIndex.." (doubleres).png",
	InitCommand=function(self) self:setsize(bannerWidth, bannerHeight):x(ART_DX) end,

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
		InitCommand=function(self) self:x(ART_DX) end,
		BeginCommand=function(self)
			local banner = SCREENMAN:GetTopScreen():GetChild('Banner')
			self:SetTarget(banner)
		end
	}
end

-- the MusicRate Quad and text, along the bottom edge of the art
t[#t+1] = Def.ActorFrame{
	InitCommand=function(self)
		self:visible( SL.Global.ActiveModifiers.MusicRate ~= 1 )
		self:xy(ART_DX, bannerHeight/2 - 7)
	end,

	--quad behind the music rate text
	Def.Quad{
		InitCommand=function(self) HUDPanel(self):zoomto(bannerWidth, 14) end
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
	-- The CD title logo, over the artwork's bottom right corner. It briefly had the card's
	-- free space to the right of the art to itself; the art fills the card again, so it is
	-- back to overlapping.
	--
	-- TWEAK: how far in from that corner it sits. Enough clearance for the widest logo the
	-- zoom formula below can produce -- a 4:1 banner-shaped cdtitle comes out ~91 units
	-- across, so a 56-unit inset keeps it clear of the card's right edge.
	local CD_INSET_X = 56
	local CD_INSET_Y = 30

	-- Its zoom formula below was tuned against this frame's zoom of ~0.77, which is what
	-- the full-width art works out to; the correction is ~1.03 and only matters if the
	-- column width is ever changed.
	local CD_ZOOM_FIX = 0.7655 / SSM.banner.zoom

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
				self:xy(CARD_W/2 - CD_INSET_X, CARD_H/2 - CD_INSET_Y)
				self:zoom(22 / toScale * ratio * CD_ZOOM_FIX)
				self:finishtweening():addrotationy(0):linear(.5):addrotationy(360)
			else
				self:visible(false)
			end
		end
	}
end

return t
