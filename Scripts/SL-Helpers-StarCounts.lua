-- Aggregate star-lamp counts for a player's whole profile.
--
-- Nothing in the theme or the engine keeps a running total of these. Profile's Lua API can
-- count charts by Grade (GetTotalStepsWithTopGrade) but not by StageAward, and there is no
-- way to enumerate only the charts a profile has actually played -- so the counts have to
-- be gathered by walking every song on the machine.
--
-- That is why this runs at most once per session and caches into SL.Global. Callers should
-- kick it off a little after their screen has settled rather than during load, so the walk
-- cannot show up as a hitch on screen entry.
--
-- NOTE: this Scripts file is loaded before SL_Init.lua, so nothing here may touch
-- SL.Global at load time -- only from inside these functions, which run at runtime.

-- Which StageAward earns how many stars.
--
-- The award names and their grouping mirror the AwardMap in
-- Graphics/MusicWheelItem Song NormalPart/GetLamp.lua, which is what the wheel's lamps
-- already use -- except that map numbers 1 as the BEST lamp, whereas here the number IS
-- the star count, so the two run in opposite directions.
local AwardStars = {
	["StageAward_FullComboW1"]   = 4,   -- every tap fantastic: a quad
	["StageAward_SingleDigitW2"] = 3,
	["StageAward_OneW2"]         = 3,
	["StageAward_FullComboW2"]   = 3,
	["StageAward_SingleDigitW3"] = 2,
	["StageAward_OneW3"]         = 2,
	["StageAward_100PercentW3"]  = 2,
	["StageAward_FullComboW3"]   = 2,
}

-- How many charts the player has quinted (ITL clear type 5: a full combo of nothing but
-- white fantastics).
--
-- Quints come from the ITL score file rather than from the profile walk below, because
-- StageAward has no quint: the engine's W1 is the white window in FA+ mode and the
-- fantastic window in ITG mode, so the same StageAward_FullComboW1 means "quint" or
-- "quad" depending on which mode the score was set in. ITL stores its own judgment
-- breakdown, which is unambiguous -- and it is the same source the wheel uses to decide
-- whether to show quint.png (Graphics/MusicWheelItem Grades/default.lua).
--
-- Consequence: this only covers ITL charts, and a quinted chart is ALSO counted in the
-- quad row, since the two numbers come from two sources that cannot be joined -- the
-- profile walk has no chart hashes to match against ITL's.
local function QuintCount(pn)
	local itl = SL[pn] and SL[pn].ITLData
	local hashMap = itl and itl["hashMap"]
	if not hashMap then return 0 end

	local n = 0
	for _, data in pairs(hashMap) do
		if type(data) == "table" and data["clearType"] == 5 then n = n + 1 end
	end
	return n
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
	local stars = AwardStars[ score:GetStageAward() ]
	if stars then return stars end

	-- A full combo that includes decents earns no StageAward of its own, so a plain FC has
	-- to be recognised directly. Combo survives decents but not way-offs, misses or a
	-- dropped hold/roll -- the same set GetLamp.lua checks when it synthesises its
	-- FullComboW4 for FA+ mode.
	if score:GetGrade() == "Grade_Failed" then return nil end

	local broken = score:GetTapNoteScore("TapNoteScore_Miss")
	             + score:GetTapNoteScore("TapNoteScore_W5")
	             + score:GetTapNoteScore("TapNoteScore_CheckpointMiss")
	             + score:GetHoldNoteScore("HoldNoteScore_LetGo")

	if broken == 0 then return 1 end
	return nil
end

-- Walk the profile once and fill the cache. Returns the counts table.
--
-- Only charts of the style currently being played are counted, so switching between single
-- and double gives figures that match what the player is actually looking at.
StarCountsCompute = function(player)
	StarCountsInit()
	local pn = ToEnumShortString(player)

	local counts = {0, 0, 0, 0, QuintCount(pn)}
	counts.cleared = 0

	if not PROFILEMAN:IsPersistentProfile(player) then
		SL.Global.StarCounts[pn] = counts
		return counts
	end

	local profile = PROFILEMAN:GetProfile(player)
	local style = GAMESTATE:GetCurrentStyle()
	local steps_type = style and style:GetStepsType() or nil

	for song in ivalues(SONGMAN:GetAllSongs()) do
		for steps in ivalues(song:GetAllSteps()) do
			if steps_type == nil or steps:GetStepsType() == steps_type then
				local list = profile:GetHighScoreListIfExists(song, steps)
				if list then
					-- A chart counts once, in its best bucket only -- a quadded chart is
					-- not also counted as a lesser full combo.
					local best = 0
					local cleared = false
					for score in ivalues(list:GetHighScores()) do
						local stars = StarsForScore(score)
						if stars and stars > best then best = stars end
						-- A score only lands in the list once the chart has been played
						-- to the end, so anything that isn't a fail is a clear.
						if score:GetGrade() ~= "Grade_Failed" then cleared = true end
					end
					if best > 0 then counts[best] = counts[best] + 1 end
					if cleared then counts.cleared = counts.cleared + 1 end
				end
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
