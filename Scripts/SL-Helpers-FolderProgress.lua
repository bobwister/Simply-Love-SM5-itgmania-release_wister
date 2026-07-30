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
-- a best score exists on the chart and its grade isn't Grade_Failed -- or a score for it
-- was imported from GrooveStats, which only ever happens for a run that was passed.

-- Keyed by profile GUID as well as by group, so swapping profiles misses the cache
-- rather than needing anyone to remember to clear it.
local cache = {}

-- Grade tier -> star count and the quint test both live in Scripts/SL-Helpers-StarCounts
-- .lua, and are shared rather than repeated here so this panel and the player card's tally
-- cannot drift apart. A quint outranks the quad it also grades as, and replaces it rather
-- than adding to it, in both places.

-- Scores earned since the cache was filled won't be in it. Difficulty and profile are
-- both part of the key, so the events that can stale an entry are the player passing
-- something -- which always comes back through this screen -- and a score arriving from
-- GrooveStats while browsing. The latter is deliberately NOT invalidated on arrival: an
-- import lands every time a new song is selected, and re-walking the pack that often is
-- exactly the cost this cache exists to avoid. Such a score joins the count on the next
-- entry to the screen. So one call on entry to ScreenSelectMusic covers it.
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

	-- Tested once rather than per chart: on a profile that has never imported anything the
	-- lookup below would otherwise build a key string for every chart in the pack only to
	-- miss.
	local store = SL[pn].OnlineScores
	local has_online = store ~= nil and next(store) ~= nil

	for song in ivalues(SONGMAN:GetSongsInGroup(group)) do
		-- One engine-side lookup, rather than pulling the song's whole steps table into
		-- Lua and filtering it here the way the old row code did once per song.
		local chart = song:GetOneSteps(stepstype, difficulty)

		if chart then
			total = total + 1

			local passed = false
			local tier = nil

			local list = profile:GetHighScoreListIfExists(song, chart)
			if list then
				local scores = list:GetHighScores()
				if scores and #scores > 0 then
					local grade = scores[1]:GetGrade()

					if grade ~= "Grade_Failed" then
						passed = true
						tier = StarsForGrade(grade)
					end
				end
			end

			-- A score is only ever imported for a run that was passed, so the presence of
			-- an entry IS the clear, and its percentage gives the tier the same way a
			-- local grade does.
			if has_online then
				local entry = OnlineScoreGet(player, song, chart)
				if entry then
					passed = true
					local stars = StarsForPercent(entry.itg)
					if stars and (tier == nil or stars > tier) then tier = stars end
					if type(entry.ex) == "number" and entry.ex >= 100 then tier = 5 end
				end
			end

			if passed then
				cleared = cleared + 1

				-- quint last, so it isn't also counted as the quad it grades as
				if IsQuintSong(pn, song) then tier = 5 end
				if tier then tiers[tier] = tiers[tier] + 1 end
			end
		end
	end

	cache[key] = { cleared, total, tiers }
	return cleared, total, tiers
end
