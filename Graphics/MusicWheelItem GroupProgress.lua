-- Clear progress on a wheel group row: how many of the pack's charts at the currently
-- selected difficulty this profile has passed.
--
-- Loaded by both group rows -- "MusicWheelItem SectionCollapsed NormalPart.lua" (folder
-- shut) and "MusicWheelItem SectionExpanded NormalPart.lua" (folder open, the header line
-- above its songs) -- so a pack reads the same either way.
--
-- It owns the end of the row outright. The engine's plain song count used to sit there
-- and has been retired (see SectionCountSetCommand in Metrics.ini): it was a second
-- number, of a different thing, a few pixels away from this one -- songs in the pack
-- against charts at one difficulty -- and the pair read as one confused figure.
--
-- Which difficulty is being counted is not spelled out here. The chip ladder at the foot
-- of the left column already answers that, permanently and in colour, and a row 32px tall
-- is the wrong place to answer it twice.

-- Deliberately NOT gated on the FolderStats operator pref. That switch is described in
-- the operator menu as showing/hiding the big folder summary panel
-- (BGAnimations/ScreenSelectMusic overlay/PerPlayer/FolderStats.lua), and turning the
-- panel off is not a statement about the wheel. Song rows carry their PTS/ITL/ITG/EX
-- columns with no pref behind them; group rows carry this the same way.
if GAMESTATE:IsCourseMode() then return Def.Actor{} end

local item_width = _screen.w / 2.125

-- TWEAK: right-aligned on the row's trailing edge with the same 14px margin the
-- points/rank/EX group on song rows uses, so both kinds of row end their numbers on the
-- same line.
local PROGRESS_ZOOM = 0.60
local PROGRESS_X    = item_width - 14

-- Backstop only, and it is what guarantees the lane: the figure can never start further
-- left than PROGRESS_X minus this, so the pack name's maxwidth under [MusicWheelItem] is
-- set against it. The widest string a real pack produces ("199/199", 34px at this zoom)
-- is nowhere near it; a four-digit pack would compress rather than reach the name.
local PROGRESS_MAXWIDTH = WideScale(39, 55) / PROGRESS_ZOOM

return Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text="",
	Name="SectionProgress",

	InitCommand=function(self)
		self:visible(false):horizalign(right):zoom(PROGRESS_ZOOM)
		self:x(PROGRESS_X):maxwidth(PROGRESS_MAXWIDTH)
		-- One tone across both numbers, and it is the shared label slate rather than
		-- white: this is a figure you glance at, not the row's subject, and it has to sit
		-- behind the pack name. Same colour the XO/FS/SS/JA/BR labels carry in the stats
		-- pane, so the wheel and the left column grade their text the same way.
		--
		-- Neither half is tinted. Dimming the denominator on its own read as grey text at
		-- this size, and tinting the numerator by difficulty made the row's number carry
		-- a meaning that wasn't its own.
		self:diffuse(HUD_LABEL)
		self.group = nil
	end,

	-- params.Text is the group name, the same field the row's banner reads.
	SetCommand=function(self, params)
		self.group = params and params.Text or nil
		self:playcommand("RefreshProgress")
	end,

	-- The wheel keeps one difficulty selected at a time, so every group row's figure
	-- changes when the player switches difficulty. Both sides are handled because solo
	-- can be played on either.
	CurrentStepsP1ChangedMessageCommand=function(self) self:playcommand("RefreshProgress") end,
	CurrentStepsP2ChangedMessageCommand=function(self) self:playcommand("RefreshProgress") end,
	PlayerProfileSetMessageCommand=function(self)      self:playcommand("RefreshProgress") end,

	RefreshProgressCommand=function(self)
		self:visible(false)
		if not self.group then return end

		-- Solo only, the same gate the ITG score on song rows uses: this is one
		-- profile's progress and there is nowhere on a 32px row to stack two of them.
		local humans = GAMESTATE:GetHumanPlayers()
		if #humans ~= 1 then return end

		local cleared, total = FolderProgressGet(humans[1], self.group)
		-- nil = nothing to count against; 0 = a section row that isn't a pack at all
		if not total or total == 0 then return end

		self:settext( cleared .. "/" .. total )
		self:visible(true)
	end,
}
