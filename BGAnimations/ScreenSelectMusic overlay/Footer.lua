-- "Technique HUD" footer content for ScreenSelectMusic.
--
-- This theme targets solo play in Event Mode, so the stock footer's centered
-- "EVENT MODE" banner and the P2 "PRESS START" prompt are suppressed in
-- BGAnimations/ScreenSystemLayer overlay.lua. What's left of the footer is:
--
--   left    profile avatar + name   (engine CreditDisplay, untouched)
--   center  session clock + in-song clock  (moved down out of the header)
--   right   GrooveStats connection light
--
-- The two clocks used to live in Graphics/ScreenSelectMusic header.lua; they
-- were moved here so the header band is free for future use.

local session_bmt, play_bmt

local hours, mins, secs
local hmmss = "%d:%02d:%02d"

-- prefer the engine's SecondsToHMMSS()
-- but define it ourselves if it isn't provided by this version of SM5
local SecondsToHMMSS = SecondsToHMMSS or function(s)
	-- native floor division sounds nice but isn't available in Lua 5.1
	hours = math.floor(s/3600)
	mins  = math.floor((s % 3600) / 60)
	secs  = s - (hours * 3600) - (mins * 60)
	return hmmss:format(hours, mins, secs)
end

local FormatDuration = function(s)
	if s < 3600  then return SecondsToMMSS(s)   end
	if s < 36000 then return SecondsToHMMSS(s)  end
	return SecondsToHHMMSS(s)
end

local UpdateTimers = function(af, dt)
	if not (session_bmt and play_bmt) then return end
	if not SL.Global.TimeAtSessionStart then return end

	session_bmt:settext( FormatDuration(GetTimeSinceStart() - SL.Global.TimeAtSessionStart) )

	-- time actually spent in gameplay, summed across the set. Stats are recorded
	-- per player, so read whichever side has them (see
	-- BGAnimations/ScreenGameplay overlay/TrackTimeSpentInGameplay.lua).
	local totalTime = 0
	local anyPlayer = (#SL["P1"].Stages.Stats == 0) and "P2" or "P1"
	for i, stats in pairs( SL[anyPlayer].Stages.Stats ) do
		totalTime = totalTime + (stats and stats.duration or 0)
	end
	play_bmt:settext( FormatDuration(totalTime) )
end

-- -----------------------------------------------------------------------

local accent = PlayerColor(PLAYER_1)
local label_color = color("#7C939E")
local value_zoom = SL_WideScale(0.28, 0.32)
local label_zoom = 0.5

-- The clock values and their labels use different fonts, and BitmapText centers
-- on the line box rather than on the glyphs, so they don't sit on the same
-- optical line. Correction, in font units, is
--     (Top + Baseline)/2  -  LineSpacing/2
-- which for Wendy monospace numbers (Top=18, Baseline=50, LineSpacing=48) is
-- +10 -- the digits render 10 units low -- against -0.5 for Miso, i.e. nil.
-- That texture is doubleres, so 10 units is 5px at zoom 1.
-- TWEAK: nudge this if the digits still don't line up with SESSION / IN-SONG.
local value_baseline_fix = -5 * value_zoom

-- vertical center of the 32px footer band
local footer_cy = _screen.h - 16

local af = Def.ActorFrame{
	InitCommand=function(self)
		-- TimeAtSessionStart is reset to nil between game sessions, so a nil value
		-- means this is the first ScreenSelectMusic of this session. This used to
		-- be primed by the header; it moved here with the clocks.
		if SL.Global.TimeAtSessionStart == nil then
			SL.Global.TimeAtSessionStart = GetTimeSinceStart()
		end
		self:SetUpdateFunction( UpdateTimers )
	end,
	OffCommand=function(self) self:linear(0.1):diffusealpha(0) end,
}

-- The footer band itself. Drawn here rather than by the screen-level footer
-- quad (Graphics/_footer.lua, disabled for this screen) because the engine
-- sorts a screen's children by draw order only once, at Init: a draw order set
-- from a metrics OnCommand never triggers a re-sort, so that quad kept painting
-- over the overlay. As a sibling of the clocks it stacks predictably.
af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:zoomto(_screen.w, 32):vertalign(bottom)
		self:xy(_screen.cx, _screen.h)
		-- opaque: the wheel rows run the full height of the screen and would
		-- otherwise show through behind the clocks
		self:diffuse(color("#05080A")):diffusealpha(0.97)
	end
}

-- accent hairline capping the band
af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:zoomto(_screen.w, 1):vertalign(bottom)
		self:xy(_screen.cx, _screen.h - 32)
		self:diffuse(DimColor(accent, 1.0, 0.45))
	end
}

-- -----------------------------------------------------------------------
-- center: the two clocks, each a dim label followed by a right-aligned value

af[#af+1] = Def.ActorFrame{
	InitCommand=function(self) self:xy(_screen.cx, footer_cy) end,

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="SESSION",
		InitCommand=function(self)
			self:horizalign(right):zoom(label_zoom):x(-58):diffuse(label_color)
		end
	},
	LoadFont(ThemePrefs.Get("ThemeFont") .. " numbers")..{
		Name="SessionTimer",
		InitCommand=function(self)
			session_bmt = self
			self:horizalign(left):zoom(value_zoom):xy(-52, value_baseline_fix):diffuse(Color.White)
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="IN-SONG",
		InitCommand=function(self)
			self:horizalign(right):zoom(label_zoom):x(58):diffuse(label_color)
		end
	},
	LoadFont(ThemePrefs.Get("ThemeFont") .. " numbers")..{
		Name="PlayTimer",
		InitCommand=function(self)
			play_bmt = self
			self:horizalign(left):zoom(value_zoom):xy(64, value_baseline_fix):diffuse(accent)
		end
	},
}

-- -----------------------------------------------------------------------
-- right: GrooveStats connection light

af[#af+1] = Def.ActorFrame{
	InitCommand=function(self) self:xy(_screen.w - 14, footer_cy) end,
	OnCommand=function(self) self:playcommand("RefreshStatus") end,
	ScreenChangedMessageCommand=function(self) self:playcommand("RefreshStatus") end,

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="GSLabel",
		Text="GROOVESTATS",
		InitCommand=function(self)
			self:horizalign(right):zoom(label_zoom):diffuse(label_color)
		end,
		RefreshStatusCommand=function(self)
			self:visible(ThemePrefs.Get("EnableGrooveStats"))
		end
	},

	Def.Quad{
		Name="StatusLight",
		InitCommand=function(self)
			self:zoomto(6,6)
			-- sit just left of the label; measured rather than hardcoded because
			-- the label's width depends on which ThemeFont is selected
			local label = self:GetParent():GetChild("GSLabel")
			self:x( -(label:GetWidth() * label:GetZoom()) - 9 )
		end,
		RefreshStatusCommand=function(self)
			if not ThemePrefs.Get("EnableGrooveStats") then
				self:visible(false)
				return
			end
			self:visible(true):stopeffect()

			local gs = SL.GrooveStats
			if gs.GetScores and gs.Leaderboard and gs.AutoSubmit then
				-- everything up: steady green
				self:diffuse(color("#5CE087"))
			elseif gs.IsConnected then
				-- reachable but some service is refused: amber, pulsing
				self:diffuse(color("#FFE84D"))
				self:diffuseshift():effectperiod(2)
				self:effectcolor1(color("#FFE84D"))
				self:effectcolor2(color("#8A7A18"))
			else
				self:diffuse(color("#C4444B"))
			end
		end
	},
}

return af
