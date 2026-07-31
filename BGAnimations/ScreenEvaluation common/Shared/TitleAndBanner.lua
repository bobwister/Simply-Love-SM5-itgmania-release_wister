local path = "/"..THEME:GetCurrentThemeDirectory().."Graphics/_FallbackBanners/"..ThemePrefs.Get("VisualStyle")
local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()

local banner = {
	directory = (FILEMAN:DoesFileExist(path) and path or THEME:GetPathG("","_FallbackBanners/Arrows")),
	width = 418,
	zoom = 0.7,
}

-- the Quad containing the bpm and music rate doesn't appear in Casual mode
-- so nudge the song title and banner down a bit when in Casual
--
-- The title bar carries two rows now -- title, then artist -- so it sits higher than the
-- single row did. The artist used to live on the bpm/length row below the banner, sharing
-- it with a bpm string that is CENTRED on the same axis the artist starts from: at x=-145
-- growing right, against a centred string growing both ways, the two ran into each other
-- on any song whose artist was not very short. Moving it here removes the conflict rather
-- than tuning two maxwidths against each other forever.
local y_offset = SL.Global.GameMode=="Casual" and 44 or 40

-- TWEAK: the title bar's unzoomed height; on screen it is this times banner.zoom. It has
-- to stay clear of the banner's top edge, which sits at y_offset + BANNER_Y - 57.4.
local TITLE_BAR_H = 42

-- Local offsets inside that bar, and the two text scales. The title keeps the larger one:
-- it is what identifies the song, the artist is context.
local TITLE_Y,  TITLE_ZOOM  = -7, 0.8
local ARTIST_Y, ARTIST_ZOOM =  7, 0.6

-- Pushed down by the same amount the bar grew, so the banner and everything below it --
-- the bpm row, the panes -- stay exactly where they were.
local BANNER_Y = 72


local af = Def.ActorFrame{ InitCommand=function(self) self:xy(_screen.cx, y_offset) end }

if SongOrCourse and SongOrCourse:HasBanner() then
	--song or course banner, if there is one
	af[#af+1] = Def.Banner{
		Name="Banner",
		InitCommand=function(self)
			if GAMESTATE:IsCourseMode() then
				self:LoadFromCourse( GAMESTATE:GetCurrentCourse() ):animate(false)
			else
				self:LoadFromSong( GAMESTATE:GetCurrentSong() ):animate(false)
			end
			self:y(BANNER_Y):setsize(banner.width, 164):zoom(banner.zoom)
		end,
	}
else
	--fallback banner
	af[#af+1] = LoadActor(banner.directory .. "/banner" .. SL.Global.ActiveColorIndex .. " (doubleres).png")..{
		InitCommand=function(self) self:y(BANNER_Y):zoom(banner.zoom) end
	}
end

-- quad behind the song/course title text
af[#af+1] = Def.Quad{
	InitCommand=function(self) 
		self:diffuse(color("#1E282F")):setsize(banner.width, TITLE_BAR_H):zoom(banner.zoom)
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0.5)
		end
	end,
}

-- song/course title text
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self)
		self:y(TITLE_Y):zoom(TITLE_ZOOM):maxwidth(banner.width*banner.zoom/TITLE_ZOOM)
		local songtitle = (GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse():GetDisplayFullTitle()) or GAMESTATE:GetCurrentSong():GetDisplayFullTitle()
		if songtitle then self:settext(songtitle) end
	end
}

-- artist, on its own row directly under the title. Course mode has no single artist, so
-- this simply stays empty there rather than being conditionally omitted -- the bar is
-- sized for two rows either way.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self)
		self:y(ARTIST_Y):zoom(ARTIST_ZOOM):maxwidth(banner.width*banner.zoom/ARTIST_ZOOM)
		self:diffuse(HUD_LABEL)

		local artist = (not GAMESTATE:IsCourseMode()) and GAMESTATE:GetCurrentSong():GetDisplayArtist()
		if artist then self:settext(artist) end
	end
}

return af