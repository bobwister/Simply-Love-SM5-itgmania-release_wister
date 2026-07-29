-- It's possible for players to edit their Simply Love UserPrefs.ini file
-- in various ways that might break the theme.  Also, sometimes theme-specific mods
-- are deprecated or change their internal name, leaving old values behind in player profiles
-- that might break the theme as well. Use this table to validate settings read in
-- from and written out to player profiles.
--
-- For now, this table is local to this file, but might be moved into the SL table (or something)
-- in the future to facilitate type checking in ./Scripts/SL-PlayerOptions.lua and elsewhere.

local permitted_profile_settings = {

	----------------------------------
	-- "Main Modifiers"
	-- OptionRows that appear in SL's first page of PlayerOptions

	SpeedModType     = "string",
	SpeedMod         = "number",
	Mini             = "string",
	NoteSkin         = "string",
	JudgmentGraphic  = "string",
	ComboFont        = "string",
	HeldGraphic      = "string",
	HoldJudgment     = "string",
	BackgroundFilter = "number",
	NoteFieldOffsetX = "number",
	NoteFieldOffsetY = "number",
	VisualDelay      = "string",

	----------------------------------
	-- "Advanced Modifiers"
	-- OptionRows that appear in SL's second page of PlayerOptions

	HideTargets          = "boolean",
	HideSongBG           = "boolean",
	HideCombo            = "boolean",
	HideLifebar          = "boolean",
	HideScore            = "boolean",
	HideDanger           = "boolean",
	HideComboExplosions  = "boolean",

	LifeMeterType        = "string",
	DataVisualizations   = "string",
	StepStatsExtra       = "string",
	TargetScore          = "string",
	TargetScoreNumber    = "number",
	ActionOnMissedTarget = "string",

	MeasureCounter       = "string",
	MeasureCounterLeft   = "boolean",
	MeasureCounterUp     = "boolean",
	MeasureCounterVert   = "boolean",
	BrokenRun            = "boolean",
	RunTimer             = "boolean",
	MeasureCounterLookahead = "number",
	
	RainbowMax           = "boolean",
	ResponsiveColors     = "boolean",
	ShowLifePercent      = "boolean",
	
	MiniIndicator		 = "string",
	MiniIndicatorColor	 = "string",

	MeasureLines         = "string",

	ColumnFlashOnMiss    = "boolean",
	SubtractiveScoring   = "boolean",
	Pacemaker            = "boolean",
	TrackEarlyJudgments  = "boolean",
	TrackRecalc          = "boolean",
	NPSGraphAtTop        = "boolean",
	JudgmentTilt         = "boolean",
	ColumnCues           = "boolean",
	ColumnCountdown      = "boolean",
	TrackFoot            = "boolean",
	ScaleGraph           = "boolean",

	-- Error Bar Options --
	Colorful             = "boolean",
	Monochrome           = "boolean", 
	Text                 = "boolean", 
	Highlight            = "boolean",
	Average              = "boolean",
	--
	ErrorBarUp           = "boolean",
	ErrorBarMultiTick    = "boolean",
	ErrorBarCap    		 = "number",

	ShowFaPlusWindow     = "boolean",
	ShowEXScore          = "boolean",
	ShowFaPlusPane       = "boolean",
	SmallerWhite     = "boolean",
	PrimaryScore         = "string",
	SecondaryScore       = "string",

	HideEarlyDecentWayOffJudgments = "boolean",
	HideEarlyDecentWayOffFlash     = "boolean",
	
	PackBanner           = "boolean",
	StepInfo             = "boolean",
	DisplayScorebox      = "boolean",
	
	SBITGScore           = "boolean",
	SBEXScore            = "boolean",
	SBEvents             = "boolean",
	
	FlashMiss            = "boolean",
	FlashWayOff          = "boolean",
	FlashDecent          = "boolean",
	FlashGreat           = "boolean",
	FlashExcellent       = "boolean",
	FlashFantastic       = "boolean",
	
	TiltMultiplier       = "number",
	
	ComboColors			 = "string",
	ComboMode			 = "string",
	TimerMode            = "string",
	JudgmentAnimation    = "string",
	
	JudgmentBack         = "boolean",
	ErrorMSDisplay       = "boolean",
	GhostFault           = "boolean",
	SplitWhites          = "boolean",
	BreakUI              = "boolean",

	GrowCombo			 = "boolean",
	SpinCombo			 = "boolean",
	WildCombo			 = "boolean",
	RainbowComboOptions	 = "string",
	TiltOptions			 = "string",
	Waterfall			 = "boolean",
	FadeFantastic		 = "boolean",
	NoBar				 = "boolean",
	
	----------------------------------
	-- Profile Settings without OptionRows
	-- these settings are saved per-profile, but are transparently managed by the theme
	-- they have no player-facing OptionRows

	PlayerOptionsString = "string",
}

-- -----------------------------------------------------------------------

local theme_name = THEME:GetThemeDisplayName()
local filename =  theme_name .. " UserPrefs.ini"


-- Function called when a [GUEST] joins during SSM, either by late joining or via the fast
-- profile switcher. It does two things:
-- 1) properly reset profile state (e.g. modifiers), and
-- 2) persist any state that should survive a profile switch (e.g., session history
--    in SL[pn].Stages with songs played for displaying on ScreenEvaluationSummary).
-- LoadProfileCustom takes care of this for persistent profiles.
LoadGuest = function(player)
	GAMESTATE:ResetPlayerOptions(player)
	local pn = ToEnumShortString(player)
	local stages = SL[pn].Stages
	SL[pn]:initialize()
	SL[pn].Stages = stages
end


-- -----------------------------------------------------------------------
-- Two things in the profile ini are NOT per-player modifiers: the Simply Love color and
-- which of the two online events the panels report on. They are single, theme-wide pieces
-- of state -- SL.Global.ActiveColorIndex and the ActiveEvent theme pref -- so they cannot
-- go through permitted_profile_settings, which exists to route keys into the per-player
-- SL[pn].ActiveModifiers table.
--
-- They are applied by setting the same runtime state the option screens set, rather than
-- by adding a per-profile override alongside it. That matters: every existing reader
-- (PlayerColor -> GetHexColor(SL.Global.ActiveColorIndex) in SL-Colors.lua, and
-- SRPGIsActiveEvent -> ThemePrefs.Get("ActiveEvent")) keeps working untouched, and the
-- option rows in the menus keep working too -- an override would have shadowed them, so
-- changing Active Event in the menu would have appeared to do nothing.
--
-- The consequence to know: the machine-wide prefs become "whatever the last profile to
-- load wanted". That is already how SimplyLoveColor behaved, and it is what a guest with
-- no profile of their own inherits.
--
-- ThemePrefs.Save() is deliberately NOT called here. The profile ini is the source of
-- truth for these two, and this runs on every profile switch, so saving would rewrite the
-- machine ini each time for no gain.
--
-- Only the master player's profile is honoured. There is one color and one event panel for
-- the whole theme, so in versus the second profile to load would otherwise silently
-- overwrite the first; this way P2 switching profiles cannot repaint P1's theme. P2's own
-- values are still written to P2's profile by SaveProfileCustom, they are just not applied.
local function ApplyGlobalProfileSettings(player, filecontents)
	if not filecontents then return end
	if player ~= (GAMESTATE:GetMasterPlayerNumber() or PLAYER_1) then return end

	-- Validated rather than trusted: the header of this file notes that players can and do
	-- hand-edit their UserPrefs.ini, and an out-of-range index here would be indexed
	-- straight into SL.Colors by GetHexColor.
	local color = tonumber(filecontents.SimplyLoveColor)
	if color and color == math.floor(color) and color >= 1 and color <= #SL.Colors then
		if color ~= SL.Global.ActiveColorIndex then
			SL.Global.ActiveColorIndex = color
			ThemePrefs.Set("SimplyLoveColor", color)
			-- what ScreenSelectColor broadcasts, and what the shared backgrounds, the
			-- header and the footer listen for
			MESSAGEMAN:Broadcast("ColorSelected")
		end
	end

	local event = filecontents.ActiveEvent
	if event == "Auto" or event == "ITL" or event == "SRPG" then
		ThemePrefs.Set("ActiveEvent", event)
	end
end

-- function assigned to "CustomLoadFunction" under [Profile] in metrics.ini
LoadProfileCustom = function(profile, dir)

	local path =  dir .. filename
	local player, pn, filecontents

	-- we've been passed a profile object as the variable "profile"
	-- see if it matches against anything returned by PROFILEMAN:GetProfile(player)
	for p in ivalues( GAMESTATE:GetHumanPlayers() ) do
		if profile == PROFILEMAN:GetProfile(p) then
			player = p
			pn = ToEnumShortString(p)
			break
		end
	end

	if pn then
		-- Remember and persist stats about songs played across profile switches
		local stages = SL[pn].Stages

		SL[pn]:initialize()
		ParseGrooveStatsIni(player)
		ReadItlFile(player)

		SL[pn].Stages = stages
	end

	if pn and FILEMAN:DoesFileExist(path) then
		filecontents = IniFile.ReadFile(path)[theme_name]

		-- the color and the active event, which are theme-wide rather than per-player
		ApplyGlobalProfileSettings(player, filecontents)

		-- for each key/value pair read in from the player's profile
		for k,v in pairs(filecontents) do
			-- ensure that the key has a corresponding key in permitted_profile_settings
			if permitted_profile_settings[k]
			--  ensure that the datatype of the value matches the datatype specified in permitted_profile_settings
			and type(v)==permitted_profile_settings[k] then
				-- if the datatype is string and this key corresponds with an OptionRow in ScreenPlayerOptions
				-- ensure that the string read in from the player's profile
				-- is a valid value (or choice) for the corresponding OptionRow
				if type(v) == "string" and CustomOptionRow(k) and FindInTable(v, CustomOptionRow(k).Values or CustomOptionRow(k).Choices)
				or type(v) ~= "string" then
					SL[pn].ActiveModifiers[k] = v
				end

				-- special-case PlayerOptionsString for now
				-- it is saved to and read from profile as a string, but doesn't have a corresponding
				-- OptionRow in ScreenPlayerOptions, so it will fail validation above
				-- we want engine-defined mods (e.g. dizzy) to be applied as well, not just SL-defined mods
				if k=="PlayerOptionsString" and type(v)=="string" then
					-- v here is the comma-delimited set of modifiers the engine's PlayerOptions interface understands

					-- update the SL table so that this PlayerOptionsString value is easily accessible throughout the theme
					SL[pn].PlayerOptionsString = v

					-- use the engine's SetPlayerOptions() method to set a whole bunch of mods in the engine all at once
					GAMESTATE:GetPlayerState(player):SetPlayerOptions("ModsLevel_Preferred", v)

					-- However! It's quite likely that a FailType mod could be in that^ string, meaning a player could
					-- have their own setting for FailType saved to their profile.  I think it makes more sense to let
					-- machine operators specify a default FailType at a global/machine level, so use this opportunity to
					-- use the PlayerOptions interface to set FailSetting() using the default FailType setting from
					-- the operator menu's Advanced Options
					GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):FailSetting( GetDefaultFailType() )
				end
			end
		end
	end

	return true
end

-- function assigned to "CustomSaveFunction" under [Profile] in metrics.ini
SaveProfileCustom = function(profile, dir)

	local path =  dir .. filename

	for player in ivalues( GAMESTATE:GetHumanPlayers() ) do
		if profile == PROFILEMAN:GetProfile(player) then
			local pn = ToEnumShortString(player)
			local output = {}
			for k,v in pairs(SL[pn].ActiveModifiers) do
				if permitted_profile_settings[k] and type(v)==permitted_profile_settings[k] then
					output[k] = v
				end
			end

			-- these values are saved outside the SL[pn].ActiveModifiers tables
			-- and thus won't be handled in the loop above
			output.PlayerOptionsString = SL[pn].PlayerOptionsString

			-- Theme-wide settings kept per profile so the look and the event panel follow
			-- whoever is playing. See ApplyGlobalProfileSettings for why these two can't
			-- ride in permitted_profile_settings, and why only the master player's copy is
			-- applied on load even though every profile writes its own.
			output.SimplyLoveColor = SL.Global.ActiveColorIndex
			output.ActiveEvent     = ThemePrefs.Get("ActiveEvent")

			IniFile.WriteFile( path, {[theme_name]=output} )

			-- Write to the ITL file if we need to.
			-- This is relevant for memory cards.
			WriteItlFile(player)
			break
		end
	end

	return true
end

-- -----------------------------------------------------------------------
-- returns a path to a profile avatar, or nil if none is found

GetAvatarPath = function(profileDirectory, displayName)

	if type(profileDirectory) ~= "string" then return end

	local path = nil

	-- sequence matters here
	-- prefer png first, then jpg, then jpeg, etc.
	-- (note that SM5 does not support animated gifs at this time, so SL doesn't either)
	-- TODO: investigate effects (memory footprint, fps) of allowing movie files as avatars in SL
	local extensions = { "png", "jpg", "jpeg", "bmp", "gif" }

	-- prefer an avatar named:
	--    "avatar" in the player's profile directory (preferred by Simply Love)
	--    then "profile picture" in the player's profile directory (used by Digital Dance)
	--    then (whatever the profile's DisplayName is) in /Appearance/Avatars/ (used in OutFox?)
	local paths = {
		("%savatar"):format(profileDirectory),
		("%sprofile picture"):format(profileDirectory),
		("/Appearance/Avatars/%s"):format(displayName)
	}

	for _, path in ipairs(paths) do
		for _, extension in ipairs(extensions) do
			local avatar_path = ("%s.%s"):format(path, extension)

			if FILEMAN:DoesFileExist(avatar_path)
			and ActorUtil.GetFileType(avatar_path) == "FileType_Bitmap"
			then
				-- return the first valid avatar path that is found
				return avatar_path
			end
		end
	end

	-- or, return nil if no avatars were found in any of the permitted paths
	return nil
end

-- -----------------------------------------------------------------------
-- returns a path to a player's profile avatar, or nil if none is found

GetPlayerAvatarPath = function(player)
	if not player then return end

	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}

	if not profile_slot[player] then return end

	local dir  = PROFILEMAN:GetProfileDir(profile_slot[player])
	local name = PROFILEMAN:GetProfile(player):GetDisplayName()

	return GetAvatarPath(dir, name)
end
