-- Clear progress for one song group, at one difficulty.
--
-- The wheel's group rows used to carry a grade lamp doing roughly this. It was commented
-- out with the note "Disabling until we either have a more elegant implementation" (see
-- the tail of Graphics/MusicWheelItem SectionCollapsed NormalPart.lua). What made it
-- untenable was not the walk but WHERE it ran: straight out of the row's SetCommand,
-- which the wheel fires on every row on every scroll tick. Fifteen visible group rows
-- meant fifteen full walks per frame for as long as a player held Down.
--
-- So the walk happens once per (profile, group, difficulty, stepstype) and is kept. The
-- first pass over a screenful of packs pays for them; every pass after that, and every
-- scroll back and forth over the same packs, costs a table lookup.
--
-- What counts as cleared is what the FolderStats panel and the star tally already count:
-- a best score exists on the chart and its grade isn't Grade_Failed.

-- Keyed by profile GUID as well as by group, so swapping profiles misses the cache
-- rather than needing anyone to remember to clear it.
local cache = {}

-- Grade tier -> star count, best first. Grade_Tier01 IS the four-star grade in Simply
-- Love (see the GradePercentTier comments in Metrics.ini), so the buckets run 4..1 and
-- leave 5 for the quint.
local STAR_TIER = {
	Grade_Tier01 = 4,
	Grade_Tier02 = 3,
	Grade_Tier03 = 2,
	Grade_Tier04 = 1,
}

-- Did this profile quint (ITL FFPC) this song?
--
-- It matters because a quint also grades as four stars: counted naively it would land in
-- BOTH the five- and four-star buckets. The player card's tally has that older behaviour
-- -- its quint count comes from ITL data while its tiers come from a separate profile
-- walk -- and double-counts. This does not.
--
-- ITL-only by nature: outside an ITL pack there is no hash and the answer is false, which
-- is correct rather than merely convenient. Nothing else can tell a quint from a quad.
local function IsQuint(pn, song)
	local data = SL[pn].ITLData
	if not data or not data["pathMap"] or not data["hashMap"] then return false end

	local hash = data["pathMap"][ song:GetSongDir() ]
	if not hash then return false end

	local entry = data["hashMap"][hash]
	return entry ~= nil and entry["clearType"] == 5
end

-- Scores earned since the cache was filled won't be in it. Difficulty and profile are
-- both part of the key, so the only event that can stale an entry is the player actually
-- passing something -- which means one call on entry to ScreenSelectMusic covers it.
-- That call lives at file scope in BGAnimations/ScreenSelectMusic overlay/default.lua,
-- where it runs once per screen load, before any row has been Set.
FolderProgressInvalidate = function()
	cache = {}
end

-- Returns cleared, total, tiers for `group` at the difficulty and stepstype currently
-- selected, or nil when there is nothing to count against: no persistent profile to read
-- scores from, or no chart selected to take a difficulty from.
--
-- `tiers` is a 5-entry array of star counts, tiers[5] quints down to tiers[1] one star.
-- It comes out of the same pass as the clear count, which is the whole point of it living
-- here: the folder stats panel used to run its own identical walk over every song in the
-- group, uncached, alongside the one the wheel rows were already doing.
--
-- `total` counts CHARTS at that difficulty, not songs in the group. A pack of 34 songs
-- may only have 30 with an Expert chart, and 30 is the honest denominator for "how much
-- of this pack have I cleared on Expert" -- it is also why this number is allowed to
-- differ from the song count the engine draws beside it.
--
-- Section rows that aren't packs (the letter rows of a title sort, the BPM bands of a
-- BPM sort) simply have no songs under that name, so they come back 0 and the caller
-- hides itself. No sort-order test needed.
FolderProgressGet = function(player, group)
	if not group or group == "" then return nil end
	if not PROFILEMAN:IsPersistentProfile(player) then return nil end

	local steps = GAMESTATE:GetCurrentSteps(player)
	if not steps then return nil end

	local profile    = PROFILEMAN:GetProfile(player)
	local difficulty = steps:GetDifficulty()
	local stepstype  = GAMESTATE:GetCurrentStyle():GetStepsType()

	local key = table.concat({ profile:GetGUID(), group, difficulty, stepstype }, "|")

	local hit = cache[key]
	if hit then return hit[1], hit[2], hit[3] end

	local pn = ToEnumShortString(player)
	local cleared, total = 0, 0
	local tiers = { 0, 0, 0, 0, 0 }

	for song in ivalues(SONGMAN:GetSongsInGroup(group)) do
		-- One engine-side lookup, rather than pulling the song's whole steps table into
		-- Lua and filtering it here the way the old row code did once per song.
		local chart = song:GetOneSteps(stepstype, difficulty)

		if chart then
			total = total + 1

			local list = profile:GetHighScoreListIfExists(song, chart)
			if list then
				local scores = list:GetHighScores()
				if scores and #scores > 0 then
					local grade = scores[1]:GetGrade()

					if grade ~= "Grade_Failed" then
						cleared = cleared + 1

						-- quint first, so it isn't also counted as the quad it grades as
						local tier = IsQuint(pn, song) and 5 or STAR_TIER[grade]
						if tier then tiers[tier] = tiers[tier] + 1 end
					end
				end
			end
		end
	end

	cache[key] = { cleared, total, tiers }
	return cleared, total, tiers
end
