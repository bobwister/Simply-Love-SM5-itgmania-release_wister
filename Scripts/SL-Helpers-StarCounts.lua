-- Aggregate star counts for a player's whole profile.
--
-- Nothing in the theme or the engine keeps a running total of these. Profile's Lua API
-- offers GetTotalStepsWithTopGrade, but only per (stepstype, difficulty) and only over
-- grades the engine itself recorded -- it cannot see imported scores, cannot tell a quint
-- from the quad it grades as, and yields no clear count. All three are wanted here, and
-- each needs the chart in hand, so the counts are gathered by walking every song on the
-- machine instead.
--
-- That is why this runs at most once per session and caches into SL.Global. Callers should
-- kick it off a little after their screen has settled rather than during load, so the walk
-- cannot show up as a hitch on screen entry.
--
-- NOTE: this Scripts file is loaded before SL_Init.lua, so nothing here may touch
-- SL.Global at load time -- only from inside these functions, which run at runtime.

-- Grade tier -> star count, best first.
--
-- Simply Love's stars ARE the top grade tiers, not a separate award: Graphics/_grades/
-- Grade_Tier01.lua draws four stars, Tier02 three, Tier03 two, Tier04 one, and Metrics.ini
-- annotates those very rows "★★★★" down to "★" beside GradePercentTier01=1.00 through
-- Tier04=0.96. A star count is therefore a function of the ITG percentage and of nothing
-- else -- no StageAward, no judgment breakdown.
--
-- That is what lets a score imported from GrooveStats, which carries a percentage and
-- nothing more, land in the right bucket. It is also why this must NOT be derived from
-- StageAward, which measures something quite different (how deep a full combo went) and
-- disagrees wildly: a full combo of nothing but excellents is StageAward_FullComboW2 at
-- 80.00%, which is no star at all, while a 99.2% run carrying a few greats is three stars
-- despite earning only FullComboW3.
local STAR_TIER = {
	Grade_Tier01 = 4,
	Grade_Tier02 = 3,
	Grade_Tier03 = 2,
	Grade_Tier04 = 1,
}

-- Built on first use rather than at load, so this file stays safe to load in any order.
local tier_cutoffs = nil

-- The grade a percentage earns, as a "Grade_TierNN" string, or nil when it falls below the
-- lowest tier. `percent` is 0..100, the form the wheel and the online store both hold.
--
-- The cutoffs are read from the very metrics the engine grades against, so this cannot
-- drift from a locally played score's own GetGrade() -- the two agree by construction.
GradeFromPercent = function(percent)
	if type(percent) ~= "number" then return nil end

	if tier_cutoffs == nil then
		tier_cutoffs = {}
		for i=1, THEME:GetMetric("PlayerStageStats", "NumGradeTiersUsed") do
			local tier = ("Tier%02d"):format(i)
			tier_cutoffs[i] = {
				"Grade_" .. tier,
				THEME:GetMetric("PlayerStageStats", "GradePercent" .. tier),
			}
		end
	end

	-- Compared with a tolerance because both sides are doubles and 0.99 * 100 is
	-- 99.00000000000001 -- a bare >= would reject a score that is exactly 99.00, which is
	-- precisely the boundary the three-star tier sits on.
	for cutoff in ivalues(tier_cutoffs) do
		if percent >= cutoff[2] * 100 - 1e-9 then return cutoff[1] end
	end
	return nil
end

-- How many stars a grade is worth, or nil for none. Grade_Failed included: it is not in
-- the table, so it comes back nil.
StarsForGrade = function(grade)
	return STAR_TIER[grade]
end

-- Same, straight from a percentage -- the path an imported score takes.
StarsForPercent = function(percent)
	local grade = GradeFromPercent(percent)
	return grade and STAR_TIER[grade] or nil
end

-- Did this profile quint (ITL FFPC) this song?
--
-- ITL-only by nature: outside an ITL pack there is no hash and the answer is false, which
-- is correct rather than merely convenient. A quint grades as four stars like any other
-- 100%, so nothing but ITL's own judgment breakdown can tell the two apart.
--
-- Keyed by song rather than by chart because that is all ITL's pathMap records, so every
-- cleared difficulty of a quinted song reads as quinted. Scripts/SL-Helpers-FolderProgress
-- .lua shares this function precisely so the two tallies cannot disagree.
IsQuintSong = function(pn, song)
	local data = SL[pn] and SL[pn].ITLData
	if not data or not data["pathMap"] or not data["hashMap"] then return false end

	local hash = data["pathMap"][ song:GetSongDir() ]
	if not hash then return false end

	local entry = data["hashMap"][hash]
	return entry ~= nil and entry["clearType"] == 5
end

StarCountsInit = function()
	SL.Global.StarCounts = SL.Global.StarCounts or {}
end

-- The cached counts for a player, or nil if the walk hasn't run yet.
--
-- Index 1 is one star, index 4 is a quad, index 5 a quint. The table also carries a
-- `cleared` field: how many charts have been passed at all, star or no star.
StarCountsGet = function(player)
	StarCountsInit()
	return SL.Global.StarCounts[ToEnumShortString(player)]
end

-- How many stars a single high score is worth, or nil for none.
local function StarsForScore(score)
	return STAR_TIER[ score:GetGrade() ]
end

-- Walk the profile once and fill the cache. Returns the counts table.
--
-- Only charts of the style currently being played are counted, so switching between single
-- and double gives figures that match what the player is actually looking at.
StarCountsCompute = function(player)
	StarCountsInit()
	local pn = ToEnumShortString(player)

	local counts = {0, 0, 0, 0, 0}
	counts.cleared = 0

	if not PROFILEMAN:IsPersistentProfile(player) then
		SL.Global.StarCounts[pn] = counts
		return counts
	end

	local profile = PROFILEMAN:GetProfile(player)
	local style = GAMESTATE:GetCurrentStyle()
	local steps_type = style and style:GetStepsType() or nil

	-- Tested once rather than per chart: on a profile that has never imported anything the
	-- lookup below would otherwise build a key string for every chart on the machine, tens
	-- of thousands of times, only to miss.
	local online = SL[pn].OnlineScores
	local has_online = online ~= nil and next(online) ~= nil

	for song in ivalues(SONGMAN:GetAllSongs()) do
		for steps in ivalues(song:GetAllSteps()) do
			if steps_type == nil or steps:GetStepsType() == steps_type then
				-- A chart counts once, in its best bucket only -- a quadded chart is not
				-- also counted as a lesser tier.
				local best = 0
				local cleared = false

				local list = profile:GetHighScoreListIfExists(song, steps)
				if list then
					for score in ivalues(list:GetHighScores()) do
						local stars = StarsForScore(score)
						if stars and stars > best then best = stars end
						-- A score only lands in the list once the chart has been played
						-- to the end, so anything that isn't a fail is a clear.
						if score:GetGrade() ~= "Grade_Failed" then cleared = true end
					end
				end

				-- A score is only ever imported for a run that was passed -- the capture
				-- in ScreenSelectMusic's Scorebox drops entries flagged isFail -- so the
				-- presence of an entry IS the clear, and the percentage gives the tier.
				if has_online then
					local entry = OnlineScoreGet(player, song, steps)
					if entry then
						cleared = true
						local stars = StarsForPercent(entry.itg)
						if stars and stars > best then best = stars end
						-- EX 100.00 means every note was a white fantastic, which is a
						-- quint. Nothing weaker than a perfect EX can imply one.
						if type(entry.ex) == "number" and entry.ex >= 100 then best = 5 end
					end
				end

				-- Quint outranks the quad it also grades as, and replaces it rather than
				-- adding to it -- the double count the old ITL-sourced tally had.
				if cleared and IsQuintSong(pn, song) then best = 5 end

				if best > 0 then counts[best] = counts[best] + 1 end
				if cleared then counts.cleared = counts.cleared + 1 end
			end
		end
	end

	SL.Global.StarCounts[pn] = counts
	return counts
end

-- Drop the cache, so the next Compute re-walks. Call after anything that can change the
-- player's scores or which style they are playing.
StarCountsInvalidate = function(player)
	StarCountsInit()
	if player then
		SL.Global.StarCounts[ToEnumShortString(player)] = nil
	else
		SL.Global.StarCounts = {}
	end
end
