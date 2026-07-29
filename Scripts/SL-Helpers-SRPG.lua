-- Stamina RPG: which pack belongs to which event, and the best rate this profile has
-- cleared each of its songs at.
--
-- SRPG scores on RATE, not on points: the leaderboards rank you by the highest music rate
-- you cleared a chart at. GrooveStats' API says nothing about that -- its ["rpg"] node is
-- a per-chart leaderboard and nothing else -- so the theme keeps the figure itself, in a
-- plain "<title>=<rate>" file in the profile directory, written after every qualifying
-- clear. See BGAnimations/ScreenEvaluation common/PerPlayer/RpgRatemod.lua.
--
-- Everything here used to be inline in two files, both hardcoded to SRPG 8 in both the
-- pack name and the file name, and with the read and the write each carrying their own
-- copy of the format. They are one thing now, and generic over the event number, so
-- installing Stamina RPG 10 needs no code change.

-- -----------------------------------------------------------------------
-- Which event a pack belongs to.
--
-- Returns the event number as a string ("8", "10"), or nil for a pack that isn't SRPG.
-- Both spellings are accepted because packs and the API disagree: the song folders are
-- named "Stamina RPG 8" while the API calls the event "SRPG8".
SRPGEventFromGroupName = function(groupName)
	if not groupName then return nil end
	local group = string.lower(groupName)
	return group:match("stamina%s+rpg%s+(%d+)") or group:match("srpg%s*(%d+)")
end

local profile_slot = {
	[PLAYER_1] = "ProfileSlot_Player1",
	[PLAYER_2] = "ProfileSlot_Player2",
}

-- <profile>/SRPG<n>.rpg, or nil when the player has no profile directory.
local function RpgFilePath(player, event)
	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	if not dir or #dir == 0 then return nil end
	return dir .. "SRPG" .. event .. ".rpg"
end

-- The key a song is stored under. Non-word characters are replaced because the original
-- format did so, and existing .rpg files in players' profiles are written that way -- this
-- has to keep reading them.
local function SongKey(song)
	return (song:GetDisplayFullTitle():gsub("%W", "_"))
end

-- -----------------------------------------------------------------------
-- Parsed contents, keyed by file path.
--
-- The old reader opened the file, read it whole and ran string.find over it ONCE PER ROW,
-- from the wheel row's SetCommand -- which is to say file I/O inside the scroll loop, up
-- to fifteen times per frame. It is parsed once into a table here instead.
local cache = {}

-- Peaks are a walk over the season's packs rather than a file read; same lifetime.
local peaks_cache = {}

-- Called on entry to ScreenSelectMusic, where a run just played may have raised a rate,
-- a difficulty or a BPM.
SRPGInvalidate = function()
	cache = {}
	peaks_cache = {}
end

local function Load(path)
	local hit = cache[path]
	if hit then return hit end

	local rates = {}

	if FILEMAN:DoesFileExist(path) then
		local f = RageFileUtil:CreateRageFile()
		if f:Open(path, 1) then
			local contents = f:Read()
			f:Close()
			-- one line per song, "<key>=<rate>"; anything else is skipped rather than
			-- guessed at
			for key, rate in contents:gmatch("([^\r\n=]+)=([%d%.]+)") do
				rates[key] = tonumber(rate)
			end
		end
		f:destroy()
	end

	cache[path] = rates
	return rates
end

-- -----------------------------------------------------------------------
-- The newest Stamina RPG season installed on this machine, or nil if none is.
--
-- Read off the song groups rather than off the player's scores, so a season just
-- installed and not yet played still counts -- the same reasoning as ITLCurrentSeason.
local current_event = false
SRPGCurrentEvent = function()
	if current_event ~= false then return current_event end

	local newest = nil
	for group in ivalues(SONGMAN:GetSongGroupNames() or {}) do
		local n = SRPGEventFromGroupName(group)
		-- compared as numbers: "10" sorts before "8" as a string
		if n and (newest == nil or tonumber(n) > tonumber(newest)) then newest = n end
	end

	current_event = newest
	return current_event
end

-- -----------------------------------------------------------------------
-- Which of the two online events the profile panels should be showing.
--
-- ITL and Stamina RPG alternate across the year and nothing in the API says which is
-- live -- there is no endpoint for it. But the calendar does say, because the two events
-- run in fixed windows:
--
--   March .. June       ITL
--   July .. October     Stamina RPG
--   November .. February  neither, so whichever ran last keeps the panel
--
-- The windows repeat every year, so nothing here needs revisiting each season -- unlike
-- the theme's earlier attempt at this, whose absolute start/end timestamps are still
-- sitting in RpgRatemod.lua's history, disabled, with the note that the event "lasts
-- forever it seems".
--
-- The off-season carry-over is what LastAutoEvent stores: it is written whenever a month
-- decides, and read back through the months that don't. It is seeded to SRPG, so a
-- machine first started in the off-season shows Stamina RPG rather than nothing.
--
-- ActiveEvent in the operator menu overrides all of it.
local MONTH_EVENT = {
	[3] = "ITL",  [4] = "ITL",  [5] = "ITL",  [6]  = "ITL",
	[7] = "SRPG", [8] = "SRPG", [9] = "SRPG", [10] = "SRPG",
}

SRPGIsActiveEvent = function()
	local pref = ThemePrefs.Get("ActiveEvent")
	if pref == "ITL"  then return false end
	if pref == "SRPG" then return true  end

	-- MonthOfYear is 0-based, as everywhere else in this theme
	local decided = MONTH_EVENT[ MonthOfYear() + 1 ]

	if decided then
		-- Remember it for the off-season, but only write when it actually changes: this
		-- is asked on every card refresh, and ThemePrefs.Save touches disk.
		if ThemePrefs.Get("LastAutoEvent") ~= decided then
			ThemePrefs.Set("LastAutoEvent", decided)
			ThemePrefs.Save()
		end
		return decided == "SRPG"
	end

	return ThemePrefs.Get("LastAutoEvent") == "SRPG"
end

-- -----------------------------------------------------------------------
-- What this profile has done in one Stamina RPG season, across the whole event.
--
-- Returns best, cleared -- the highest rate cleared anywhere in the event, and how many
-- songs have been cleared at all. nil, 0 when none have.
--
-- Both are records of things that happened, and deliberately nothing more. A mean rate
-- was returned here briefly and has been removed: SRPG defines no such figure, so it was
-- an invention of this theme's presented alongside official ones. If a derived statistic
-- is ever wanted here it should be labelled as one.
SRPGProfileStats = function(player, event)
	if not event then return nil, 0 end
	if not PROFILEMAN:IsPersistentProfile(player) then return nil, 0 end

	local path = RpgFilePath(player, event)
	if not path then return nil, 0 end

	local best, count = nil, 0
	for _, rate in pairs(Load(path)) do
		count = count + 1
		if best == nil or rate > best then best = rate end
	end

	return best, count
end

-- -----------------------------------------------------------------------
-- Every installed pack belonging to one event. A season usually ships more than one --
-- the main pack and its unlocks -- and both count towards the same standing.
local event_groups = nil
local function GroupsForEvent(event)
	if not event_groups then
		event_groups = {}
		for group in ivalues(SONGMAN:GetSongGroupNames() or {}) do
			local n = SRPGEventFromGroupName(group)
			if n then
				event_groups[n] = event_groups[n] or {}
				table.insert(event_groups[n], group)
			end
		end
	end
	return event_groups[event] or {}
end

-- -----------------------------------------------------------------------
-- The hardest chart and the fastest song this profile has passed in one Stamina RPG
-- season. Returns meter, bpm -- nil, nil when nothing has been passed.
--
-- These do NOT come from the .rpg file: that format records a title and a rate, and
-- nothing else -- not even which chart of the song was played. So they come from the
-- profile's own scores instead, the same source the star tally and the wheel's clear
-- progress read, which means they also cover charts passed before the rate rules let
-- anything be recorded.
--
-- Restricted to charts playable in the current style, so a doubles chart cannot set the
-- record on a single cabinet.
--
-- The walk is the length of the season's packs -- 310 songs for a big one -- so it is
-- kept, keyed by profile and style, and dropped on entry to ScreenSelectMusic.
SRPGPassedPeaks = function(player, event)
	if not event then return nil, nil end
	if not PROFILEMAN:IsPersistentProfile(player) then return nil, nil end

	local profile   = PROFILEMAN:GetProfile(player)
	local stepstype = GAMESTATE:GetCurrentStyle():GetStepsType()
	local key = table.concat({ profile:GetGUID(), event, stepstype }, "|")

	local hit = peaks_cache[key]
	if hit then return hit[1], hit[2] end

	local meter, bpm = nil, nil

	for _, group in ipairs(GroupsForEvent(event)) do
		for song in ivalues(SONGMAN:GetSongsInGroup(group)) do
			local passed = false

			for steps in ivalues(SongUtil.GetPlayableSteps(song)) do
				if steps:GetStepsType() == stepstype then
					local list = profile:GetHighScoreListIfExists(song, steps)
					if list then
						local scores = list:GetHighScores()
						if scores and #scores > 0 and scores[1]:GetGrade() ~= "Grade_Failed" then
							passed = true
							local m = steps:GetMeter()
							if meter == nil or m > meter then meter = m end
						end
					end
				end
			end

			-- BPM is the song's, so it is only asked for once the song has been passed on
			-- some chart. GetDisplayBpms is {min, max}; a variable-BPM song counts at its
			-- fastest, which is the number that makes it hard.
			if passed then
				local bpms = song:GetDisplayBpms()
				local top = bpms and bpms[2]
				if top and (bpm == nil or top > bpm) then bpm = top end
			end
		end
	end

	peaks_cache[key] = { meter, bpm }
	return meter, bpm
end

-- -----------------------------------------------------------------------
-- The best rate this profile has cleared `song` at, as a number (1.35), or nil if it has
-- never been cleared. `event` comes from SRPGEventFromGroupName.
SRPGBestRate = function(player, song, event)
	if not song or not event then return nil end
	if not PROFILEMAN:IsPersistentProfile(player) then return nil end

	local path = RpgFilePath(player, event)
	if not path then return nil end

	return Load(path)[ SongKey(song) ]
end

-- Record `rate` for `song` if it beats what is stored. Returns true if the file changed.
--
-- The original did this by string.gsub-ing "<key>=<oldrate>" for "<key>=<newrate>" over
-- the whole file, which rewrites EVERY line whose key contains that key as a substring --
-- "Fly" would corrupt "Flying". Parse, update, serialise instead.
SRPGRecordRate = function(player, song, event, rate)
	if not song or not event then return false end

	local path = RpgFilePath(player, event)
	if not path then return false end

	local key   = SongKey(song)
	local rates = Load(path)

	-- stored to 2dp, and compared at that precision, so a run cannot "beat" a stored
	-- rate by a rounding difference that then writes the same string back
	rate = tonumber(("%.2f"):format(rate))
	if rates[key] and rates[key] >= rate then return false end

	rates[key] = rate

	-- Sorted so the file has a stable order and diffs are readable; pairs() alone would
	-- reshuffle every line on every write.
	local keys = {}
	for k in pairs(rates) do keys[#keys+1] = k end
	table.sort(keys)

	local out = {}
	for _, k in ipairs(keys) do
		out[#out+1] = ("%s=%.2f"):format(k, rates[k])
	end

	local f = RageFileUtil:CreateRageFile()
	if f:Open(path, 2) then
		f:Write(table.concat(out, "\n") .. "\n")
		f:Close()
	end
	f:destroy()

	return true
end
