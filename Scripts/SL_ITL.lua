-- -----------------------------------------------------------------------
IsItlSong = function(player)
	local song = GAMESTATE:GetCurrentSong()
	local song_dir = song:GetSongDir()
	local group = string.lower(song:GetGroupName())
	local pn = ToEnumShortString(player)
	-- Match "itl <year>" / "itl online <year>" for any year, not just 2024,
	-- so newer season packs (ITL 2025, 2026, ...) are recognized too.
	return string.find(group, "itl online %d%d%d%d") or string.find(group, "itl %d%d%d%d") or SL[pn].ITLData["pathMap"][song_dir] ~= nil
end

-- Extracts the 4-digit ITL season year from a song's group name (e.g.
-- "ITL Online 2025 Unlocks" -> "2025"), or nil if it isn't an ITL group.
-- GrooveStats runs ITL as a fresh competition every season, with its own
-- single/doubles standings - a chart's local Top-N rank must only ever be
-- compared against other charts from the SAME season, never pooled together.
ITLSeasonFromGroupName = function(groupName)
	if not groupName then return nil end
	local group = string.lower(groupName)
	return group:match("itl%s+online%s+(%d%d%d%d)") or group:match("itl%s+(%d%d%d%d)")
end

UpdatePathMap = function(player, hash)
	local song = GAMESTATE:GetCurrentSong()
	local song_dir = song:GetSongDir()
	if song_dir ~= nil and #song_dir ~= 0 then
		local pn = ToEnumShortString(player)
		local pathMap = SL[pn].ITLData["pathMap"]
		if pathMap[song_dir] == nil or pathMap[song_dir] ~= hash then
			pathMap[song_dir] = hash
			WriteItlFile(player)
		end
	end
end


IsItlActive = function()
	-- The file is only written to while the event is active.
	-- These are just placeholder dates.
	-- local startTimestamp = 20230317
	-- local endTimestamp = 20240420

	-- local year = Year()
	-- local month = MonthOfYear()+1
	-- local day = DayOfMonth()
	-- local today = year * 10000 + month * 100 + day

	-- return startTimestamp <= today and today <= endTimestamp

	-- Assume ITL is always active. This helps when we close and reopen the event.
	return true
end


-- -----------------------------------------------------------------------
-- The ITL file is a JSON file that contains two mappings:
--
-- {
--    pathMap = {
--      '<song_dir>': '<song_hash>',
--    },
--    hashMap = {
--      '<song_hash': { ..itl metadata .. }
--    }
-- }
--
-- The pathMap maps a song directory corresponding to an ITL chart to its song hash
-- The hashMap is a mapping from that hash to the relevant data stored for the event.
--
-- This set up lets us display song wheel grades for ITL both from playing within the
-- ITL pack and also outside of it.
-- Note that songs resynced for ITL but played outside of the pack will not be covered in the pathMap.
local itlFilePath = "itl2024.json"

local TableContainsData = function(t)
	if t == nil then return false end

	for _, _ in pairs(t) do
			return true
	end
	return false
end

-- Takes the ITLData loaded in memory and writes it to the local profile.
WriteItlFile = function(player)
	local pn = ToEnumShortString(player)
	-- No data to write, return early.
	if (not TableContainsData(SL[pn].ITLData["pathMap"]) and
			not TableContainsData(SL[pn].ITLData["hashMap"])) then
		return
	end

	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}
	
	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	-- We require an explicit profile to be loaded.
	if not dir or #dir == 0 then return end

	local path = dir .. itlFilePath
	local f = RageFileUtil:CreateRageFile()

	if f:Open(path, 2) then
		f:Write(JsonEncode(SL[pn].ITLData))
		f:Close()
	end
	f:destroy()
end

-- EX score is a number like 92.67
local GetPointsForSong = function(maxPoints, exScore)
	local thresholdEx = 50.0
	local percentPoints = 40.0

	-- Helper function to take the logarithm with a specific base.
	local logn = function(x, y)
		return math.log(x) / math.log(y)
	end

	-- The first half (logarithmic portion) of the scoring curve.
	local first = logn(
		math.min(exScore, thresholdEx) + 1,
		math.pow(thresholdEx + 1, 1 / percentPoints)
	)

	-- The seconf half (exponential portion) of the scoring curve.
	local second = math.pow(
		100 - percentPoints + 1,
		math.max(0, exScore - thresholdEx) / (100 - thresholdEx)
	) - 1

	-- Helper function to round to a specific number of decimal places.
	-- We want 100% EX to actually grant 100% of the points.
	-- We don't want to  lose out on any single points if possible. E.g. If
	-- 100% EX returns a number like 0.9999999999999997 and the chart points is
	-- 6500, then 6500 * 0.9999999999999997 = 6499.99999999999805, where
	-- flooring would give us 6499 which is wrong.
	local roundPlaces = function(x, places)
		local factor = 10 ^ places
		return math.floor(x * factor + 0.5) / factor
	end

	local percent = roundPlaces((first + second) / 100.0, 6)
	return math.floor(maxPoints * percent)
end

-- Generally to be called only once when a profile is loaded.
-- This parses the ITL data file and stores it in memory for the song wheel to reference.
ReadItlFile = function(player)
	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}
	
	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	local pn = ToEnumShortString(player)
	-- We require an explicit profile to be loaded.
	if not dir or #dir == 0 then return end

	local path = dir .. itlFilePath
	local itlData = { 
		["pathMap"] = {},
		["hashMap"] = {},
	}
	if FILEMAN:DoesFileExist(path) then
		local f = RageFileUtil:CreateRageFile()
		local existing = ""
		if f:Open(path, 1) then
			existing = f:Read()
			f:Close()
		end
		f:destroy()
		itlData = JsonDecode(existing)
	end
	-- SL 5.2.0 had a bug where the EX scores weren't calculated correctly.
	-- If that's the case, then recalculate the scores the first time the v5.2.1 theme
	-- is loaded. Use this variable called "fixedEx" to determine if the EX scores
	-- have been fixed. Luckily we can use the judgment counts, which have all the info,
	-- in order to calculate the values.
	--
	-- Judgment spread has the following keys:
	--
	-- "judgments" : {
	--             "W0" -> the fantasticPlus count
	--             "W1" -> the fantastic count
	--             "W2" -> the excellent count
	--             "W3" -> the great count
	--             "W4" -> the decent count (may not exist if window is disabled)
	--             "W5" -> the way off count (may not exist if window is disabled)
	--           "Miss" -> the miss count
	--     "totalSteps" -> the total number of steps in the chart (including hold heads)
	--          "Holds" -> total number of holds held
	--     "totalHolds" -> total number of holds in the chart
	--          "Mines" -> total number of mines hit
	--     "totalMines" -> total number of mines in the chart
	--          "Rolls" -> total number of rolls held
	--     "totalRolls" -> total number of rolls in the chart
	--  },
	if itlData["fixedEx"] == nil then
		itlData["fixedEx"] = true
	end
	if itlData["fixedEx2024"] == nil then
		local hashMap = itlData["hashMap"]
		local keys = { "W0", "W1", "W2", "W3", "W4", "W5", "Miss" }

		if hashMap ~= nil then
			for hash, data in pairs(hashMap) do
				local counts = data["judgments"]
				if counts ~= nil and counts["W0"] ~= nil then
					local totalSteps = counts["totalSteps"]
					local totalHolds = counts["totalHolds"]
					local totalRolls = counts["totalRolls"]

					local total_possible = totalSteps * SL.ExWeights["W0"] + (totalHolds + totalRolls) * SL.ExWeights["Held"]
					local total_points = 0

					for key in ivalues(keys) do
						local value = counts[key]
						if key == "W0" or key == "W1" then
							key15ms = key .. "15"
							if counts[key15ms] ~= nil then value = counts[key15ms] end
						end
						if value ~= nil then		
							total_points = total_points + value * SL.ExWeights[key]
						end
					end

					local held = counts["Holds"] + counts["Rolls"]
					total_points = total_points + held * SL.ExWeights["Held"]

					local letGo = (totalHolds - counts["Holds"]) + (totalRolls - counts["Rolls"])
					total_points = total_points + letGo * SL.ExWeights["LetGo"]

					local hitMine = counts["Mines"]
					total_points = total_points + hitMine * SL.ExWeights["HitMine"]

					data["ex"] = math.max(0, math.floor(total_points/total_possible * 10000))
					if data["maxPoints"] ~= nil and data["maxPoints"] > 0 then
						data["points"] = GetPointsForSong(data["maxPoints"], data["ex"]/100)					
					end
				end
			end
		end
		itlData["fixedEx2024"] = true	
	end
	
	if itlData["fixedLamps"] == nil then
		local hashMap = itlData["hashMap"]
		for hash, data in pairs(hashMap) do
			if data["ex"] == 10000 then
				data["clearType"] = 5
			end
		end
	end
	itlData["fixedLamps"] = true
	
	-- Fix points that got default-stored as empty strings in an earlier
	-- version of my remote ITL score pull code to 0. If the data is already
	-- fixed, then skip this step. -Zankoku
	if itlData["fixedPoints"] == nil then
		local hashMap = itlData["hashMap"]
		
		if hashMap ~= nil then
			for hash, data in pairs(hashMap) do
				if data["points"] == "" then
					data["points"] = 0
				end
				local counts = data["judgments"]
			end
		end
		
		itlData["fixedPoints"] = true
	end

	-- As of ITL 2024, there is a separate ranking for singles and doubles.
	-- Old json file didn't store stepsType, so do a one time sweep to populate
	if itlData["fixedStepsType"] == nil then
		-- Loop through pathMap to find the stepsType of all the songs, and update it in the hashMap		
		local pathMap = itlData["pathMap"]
		local hashMap = itlData["hashMap"]
		
		for path, hash in pairs(pathMap) do
			if hashMap[hash] ~= nil then
				local songPath = path:gsub("/Songs","")		
				local song = SONGMAN:FindSong(songPath)
				if song ~= nil then
					local allSteps = song:GetAllSteps()
					-- Songs with more than one chart will be from the original pack i.e. not ITL.
					-- These ones could have both singles and doubles, so it won't be accurate
					if #allSteps == 1 then				
						local steps = allSteps[1]
						local stepsType = steps:GetStepsType() == "StepsType_Dance_Single" and "single" or "double"
						hashMap[hash]["stepsType"] = stepsType		
					end	
				end
			end
		end
		itlData["fixedStepsType"] = true
	end

	-- Backfill "season" (the ITL year each chart belongs to, e.g. "2025") on
	-- older data that predates this field, same cross-reference as the
	-- stepsType sweep above. Needed so CalculateITLSongRanks can rank each
	-- season's charts separately instead of pooling 2024/2025/2026 together.
	if itlData["fixedSeason"] == nil then
		local pathMap = itlData["pathMap"]
		local hashMap = itlData["hashMap"]

		for path, hash in pairs(pathMap) do
			if hashMap[hash] ~= nil and hashMap[hash]["season"] == nil then
				local songPath = path:gsub("/Songs", "")
				local song = SONGMAN:FindSong(songPath)
				if song ~= nil then
					hashMap[hash]["season"] = ITLSeasonFromGroupName(song:GetGroupName()) or "unknown"
				end
			end
		end
		itlData["fixedSeason"] = true
	end

	-- Fix songs whose points got stuck at 0. Two causes, both since fixed:
	-- UpdateItlExScore referenced an undefined variable, and it ran tonumber()
	-- directly on #CHARTNAME - which yields nil for the "<P> (P) + <S> (S)"
	-- format introduced in ITL 2025. Either way points stayed 0, which also
	-- clumped every affected chart onto the same rank in CalculateITLSongRanks.
	-- One-time sweep: re-parse each chart's #CHARTNAME and recompute points,
	-- then re-rank everything once.
	local fixedZeroPoints = false
	if itlData["fixedSplitFormatPoints"] == nil then
		local pathMap = itlData["pathMap"]
		local hashMap = itlData["hashMap"]

		for path, hash in pairs(pathMap) do
			local data = hashMap[hash]
			if data ~= nil and (data["points"] or 0) == 0
					and type(data["ex"]) == "number" and data["ex"] > 0 then
				local songPath = path:gsub("/Songs", "")
				local song = SONGMAN:FindSong(songPath)
				if song ~= nil then
					local allSteps = song:GetAllSteps()
					if #allSteps == 1 then
						local points, passingPoints, maxScoringPoints =
								ITLPointsForSteps(allSteps[1], data["ex"]/100)
						if points then
							data["points"]           = points
							data["passingPoints"]    = passingPoints
							data["maxScoringPoints"] = maxScoringPoints
							data["maxPoints"]        = passingPoints + maxScoringPoints
							fixedZeroPoints = true
						end
					end
				end
			end
		end

		itlData["fixedSplitFormatPoints"] = true
	end

	SL[pn].ITLData = itlData

	-- CalculateITLSongRanks now scopes ranks per (season, stepsType) instead
	-- of pooling every season together (see below) - force one recompute for
	-- profiles that still have the old pooled ranks cached, even if nothing
	-- else needed fixing this load.
	local needsRankRecompute = fixedZeroPoints or (itlData["fixedSeasonScopedRanks"] == nil)
	itlData["fixedSeasonScopedRanks"] = true

	if needsRankRecompute then
		CalculateITLSongRanks(player)
		WriteItlFile(player)
	end
end

-- EX score is a number like 92.67
GetITLPointsForSong = function(maxPoints, exScore)
	local thresholdEx = 50.0
	local percentPoints = 40.0

	-- Helper function to take the logarithm with a specific base.
	local logn = function(x, y)
		return math.log(x) / math.log(y)
	end

	-- The first half (logarithmic portion) of the scoring curve.
	local first = logn(
		math.min(exScore, thresholdEx) + 1,
		math.pow(thresholdEx + 1, 1 / percentPoints)
	)

	-- The seconf half (exponential portion) of the scoring curve.
	local second = math.pow(
		100 - percentPoints + 1,
		math.max(0, exScore - thresholdEx) / (100 - thresholdEx)
	) - 1

	-- Helper function to round to a specific number of decimal places.
	-- We want 100% EX to actually grant 100% of the points.
	-- We don't want to  lose out on any single points if possible. E.g. If
	-- 100% EX returns a number like 0.9999999999999997 and the chart points is
	-- 6500, then 6500 * 0.9999999999999997 = 6499.99999999999805, where
	-- flooring would give us 6499 which is wrong.
	local roundPlaces = function(x, places)
		local factor = 10 ^ places
		return math.floor(x * factor + 0.5) / factor
	end

	local percent = roundPlaces((first + second) / 100.0, 6)
	return math.floor(maxPoints * percent)
end

-- -----------------------------------------------------------------------
-- ITL chart point values live in the chart's #CHARTNAME field, in one of two
-- formats depending on the event year (both are present in a typical install,
-- since players keep old season packs installed alongside new ones):
--
--   ITL 2024 and earlier:  "1295 pts"             all points are scoring points
--   ITL 2025 and later:    "1360 (P) + 2043 (S)"  flat passing award + scoring points
--
-- Returns passingPoints, maxScoringPoints, format ("ps" or "pts"),
-- or nil when the field can't be parsed.
ITLParseChartPoints = function(chartName)
	if type(chartName) ~= "string" then return nil end

	-- Newer split format.
	local p, s = chartName:match("(%d+)%s*%(P%)%s*%+%s*(%d+)%s*%(S%)")
	if p and s then return tonumber(p), tonumber(s), "ps" end

	-- Legacy "<N> pts".
	local n = chartName:match("(%d+)%s*pts")
	if n then return 0, tonumber(n), "pts" end

	return nil
end

-- ITL 2025+ scoring curve: passing the chart awards passingPoints outright,
-- and the scoring points are earned along a single exponential curve.
-- Mirrors GetITLPointsForSong in the stock Simply Love theme.
local ITLPointsSplitFormat = function(passingPoints, maxScoringPoints, exScore)
	local scalar = 40.0
	local curve = (math.pow(scalar, math.max(0, exScore) / scalar) - 1)
			* (100.0 / (math.pow(scalar, 100 / scalar) - 1.0))

	local factor = 10 ^ 6
	local percent = math.floor((curve / 100.0) * factor + 0.5) / factor

	return passingPoints + math.floor(maxScoringPoints * percent)
end

-- Points for a chart, dispatching on which #CHARTNAME format it used.
-- exScore is a percentage like 92.67.
ITLComputePoints = function(passingPoints, maxScoringPoints, format, exScore)
	if format == "ps" then
		return ITLPointsSplitFormat(passingPoints, maxScoringPoints, exScore)
	end
	-- Legacy charts: the whole value is scoring points on the old two-part curve.
	return GetITLPointsForSong(maxScoringPoints, exScore)
end

-- Convenience: read a chart's point values straight off its #CHARTNAME and
-- compute the points an exScore (percentage like 92.67) would be worth.
-- Returns points, passingPoints, maxScoringPoints, format - or nil if the
-- chart doesn't declare parseable point values.
ITLPointsForSteps = function(steps, exScore)
	if not steps then return nil end
	local passingPoints, maxScoringPoints, format = ITLParseChartPoints(steps:GetChartName())
	if not format then return nil end
	return ITLComputePoints(passingPoints, maxScoringPoints, format, exScore),
			passingPoints, maxScoringPoints, format
end

-- Helper function used within UpdateItlData() below.
-- Curates all the ITL data to be written to the ITL file for the played song.
local DataForSong = function(player, prevData)
	local GetClearType = function(judgments)
		-- 1 = Pass
		-- 2 = FGC
		-- 3 = FEC
		-- 4 = FFC
		-- 5 = FFPC
		local clearType = 1

		-- Dropping a hold or roll will always be a Pass
		local droppedHolds = judgments["totalRolls"] - judgments["Rolls"]
		local droppedRolls = (judgments["totalHolds"] - judgments["Holds"])
		if droppedHolds > 0 or droppedRolls > 0 then
			return 1
		end

		local totalTaps = judgments["Miss"]

		if judgments["W5"] ~= nil then
			totalTaps = totalTaps + judgments["W5"]
		end

		if judgments["W4"] ~= nil then
			totalTaps = totalTaps + judgments["W4"]
		end

		if totalTaps == 0 then clearType = 2 end

		totalTaps = totalTaps + judgments["W3"]
		if totalTaps == 0 then clearType = 3 end

		totalTaps = totalTaps + judgments["W2"]
		if totalTaps == 0 then clearType = 4 end

		totalTaps = totalTaps + judgments["W1"]
		if totalTaps == 0 then clearType = 5 end

		return clearType
	end

	local pn = ToEnumShortString(player)

	local steps = GAMESTATE:GetCurrentSteps(player)

	-- Note that playing OUTSIDE of the ITL pack will result in 0 points for all upscores.
	-- Technically this number isn't displayed, but players can opt to swap the EX score in the
	-- wheel with this value instead if they prefer.
	--
	-- #CHARTNAME comes in two formats (see ITLParseChartPoints): "<N> pts" up to
	-- ITL 2024, and "<P> (P) + <S> (S)" from ITL 2025 on. Parsing must handle
	-- both, or every chart from a 2025+ pack records 0 points.
	local passingPoints, maxScoringPoints, format = ITLParseChartPoints(steps:GetChartName())

	if not format and prevData ~= nil then
		-- Fall back to values stored from an earlier successful parse.
		if (prevData["maxScoringPoints"] or 0) > 0 then
			passingPoints    = prevData["passingPoints"] or 0
			maxScoringPoints = prevData["maxScoringPoints"]
			format = passingPoints > 0 and "ps" or "pts"
		elseif (prevData["maxPoints"] or 0) > 0 then
			-- Legacy data predating the split fields.
			passingPoints, maxScoringPoints, format = 0, prevData["maxPoints"], "pts"
		end
	end

	if not format then
		-- Otherwise we don't know how many points this chart is. Default to 0.
		passingPoints, maxScoringPoints, format = 0, 0, "pts"
	end

	local maxPoints = passingPoints + maxScoringPoints
	
	
	-- Assume C-Mod is okay by default.
	local noCmod = false

	if prevData == nil or prevData["noCmod"] == nil then
		-- If we have no prior play data data for this ITL song, or the noCmod bit hasn't been
		-- calculated, parse the subtitle to see if this chart explicitly calls for noCmod.
		local song = GAMESTATE:GetCurrentSong()
		local subtitle = song:GetDisplaySubTitle():lower()
		if string.find(subtitle, "no cmod") then
			noCmod = true
		end
	else
		-- If the bit exists then read it from the previous data.
		-- My boy De Morgan says the below condition is the exact same as the else but my
		-- computer brain is tired and I just want to make sure.
		if prevData ~= nil and prevData["noCmod"] ~= nil then
			noCmod = prevData["noCmod"]
		end
	end
	
	local year = Year()
	local month = MonthOfYear()+1
	local day = DayOfMonth()

	local judgments = GetExJudgmentCounts(player)
	local ex = CalculateExScore(player, judgments)
	local clearType = GetClearType(judgments)
	local points = ITLComputePoints(passingPoints, maxScoringPoints, format, ex)
	local usedCmod = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred"):CMod() ~= nil
	local date = ("%04d-%02d-%02d"):format(year, month, day)
	local stepsType = steps:GetStepsType() == "StepsType_Dance_Single" and "single" or "double"

	return {
		["judgments"] = judgments,
		["ex"] = ex * 100,
		["clearType"] = clearType,
		["points"] = points,
		["usedCmod"] = usedCmod,
		["date"] = date,
		["noCmod"] = noCmod,
		["passingPoints"] = passingPoints,
		["maxScoringPoints"] = maxScoringPoints,
		["maxPoints"] = maxPoints,
		["stepsType"] = stepsType,
	}
end

-- Calculate ITL Stats
-- Returns TP, RP, and songs played
CalculateITLStats = function(player)
    local pn = ToEnumShortString(player)
    
    -- Grab data from memory
    itlData = SL[pn].ITLData
	local points = itlData["points"]
    local tp = 0
    local rp = 0
    local played = 0

	for i=1,#points do
		played = played + 1
		tp = tp + points[i]
		if i <= 75 then
			rp = rp + points[i]
		end		
	end

    return tp, rp, played
end

-- Calculate Song Ranks.
--
-- The displayed per-song "rank" (used to color-code the points line green/
-- yellow/white on the wheel) is scoped to (season, stepsType): GrooveStats
-- runs ITL as a fresh competition every year, with separate single/doubles
-- standings, so a chart's Top-N standing must only ever be compared against
-- other charts from the SAME season and style - never pooled across seasons,
-- or a chart that's genuinely Top 75 within its own season could get pushed
-- down by unrelated charts from a different year entirely.
CalculateITLSongRanks = function(player)
	local pn = ToEnumShortString(player)

	-- Grab data from memory
	itlData = SL[pn].ITLData
	local songHashes = itlData["hashMap"]

	-- Overall (all seasons/styles pooled) point list - kept only because
	-- CalculateITLStats reads itlData["points"] for the TP/RP display.
	local points = {}
	for key in pairs(songHashes) do
		points[#points + 1] = songHashes[key]["points"]
	end
	table.sort(points, function(a,b) return a > b end)
	itlData["points"] = points

	-- Bucket every chart by (season, stepsType), then rank within each bucket.
	local buckets = {}
	for key, data in pairs(songHashes) do
		local bucketKey = (data["season"] or "unknown") .. "|" .. (data["stepsType"] or "single")
		buckets[bucketKey] = buckets[bucketKey] or {}
		buckets[bucketKey][#buckets[bucketKey] + 1] = key
	end

	local pointsSingle, pointsDouble = {}, {}
	for bucketKey, keys in pairs(buckets) do
		local bucketPoints = {}
		for _, key in ipairs(keys) do
			bucketPoints[#bucketPoints + 1] = songHashes[key]["points"]
		end
		table.sort(bucketPoints, function(a,b) return a > b end)

		for _, key in ipairs(keys) do
			local point = songHashes[key]["points"]
			for k, v in ipairs(bucketPoints) do
				if v == point then
					songHashes[key]["rank"] = k
					break
				end
			end
		end

		-- Combined-across-seasons single/double point lists, preserved for
		-- continuity with pre-existing data; nothing outside this function
		-- currently reads them.
		local target = bucketKey:match("|single$") and pointsSingle or pointsDouble
		for _, p in ipairs(bucketPoints) do target[#target + 1] = p end
	end

	itlData["hashMap"] = songHashes
	itlData["pointsSingle"] = pointsSingle
	itlData["pointsDouble"] = pointsDouble

	-- Rewrite the data in memory
	SL[pn].ITLData = itlData
end

-- Quick function that overwrites EX score entry if the score found is higher than what is found locally.
-- `song`/`steps` must be the ones `hash` actually belongs to - NOT read from
-- GAMESTATE:GetCurrentSong/Steps(), since callers may be updating a chart the
-- player never selected (e.g. ITLRankManager fetches leaderboards for the whole
-- pack, not just whatever's currently highlighted on the wheel).
-- `steps` is optional: pass nil when the exact chart isn't cheaply known (only
-- costs the "<N> pts" #CHARTNAME route to maxPoints, which falls back to the
-- pack title's "[<N>]" prefix anyway).
UpdateItlExScore = function(player, hash, exscore, song, steps)
	local pn = ToEnumShortString(player)
	local hashMap = SL[pn].ITLData["hashMap"]
	if hashMap[hash] == nil then
		-- New score, just copy things over.
		local stepsType = "single"
		if steps then
			stepsType = steps:GetStepsType() == "StepsType_Dance_Single" and "single" or "double"
		elseif song then
			-- No explicit chart: unambiguous only when the song has just one.
			local allSteps = song:GetAllSteps()
			if #allSteps == 1 then
				stepsType = allSteps[1]:GetStepsType() == "StepsType_Dance_Single" and "single" or "double"
			end
		end

		hashMap[hash] = {
			["judgments"] = {},
			["ex"] = 0,
			["clearType"] = 1,
			["points"] = 0,
			["usedCmod"] = false,
			["date"] = "",
			["maxPoints"] = 0,
			["noCmod"] = false,
			-- ITL has doubles now. populate the steps type of the song
			["stepsType"] = stepsType,
			-- Which ITL year this chart belongs to, so CalculateITLSongRanks
			-- never pools different seasons' standings together.
			["season"] = song and ITLSeasonFromGroupName(song:GetGroupName()) or "unknown",
		}

		updated = true
	end

	if exscore >= hashMap[hash]["ex"] or hashMap[hash]["points"] == 0 then
		hashMap[hash]["ex"] = exscore

		-- Point values come from the chart's #CHARTNAME. Two formats exist
		-- (see ITLParseChartPoints): "<N> pts" for ITL 2024 and earlier, and
		-- "<P> (P) + <S> (S)" from ITL 2025 on. The old code here ran
		-- tonumber() on the raw field, which silently yields nil for the split
		-- format - that's why 2025/2026 charts were all stuck at 0 points.
		if not steps and song then
			-- Recover the chart when the caller couldn't cheaply supply it;
			-- unambiguous only for single-chart songs (the ITL pack norm).
			local allSteps = song:GetAllSteps()
			if #allSteps == 1 then steps = allSteps[1] end
		end

		local passingPoints, maxScoringPoints, format
		if steps then
			passingPoints, maxScoringPoints, format = ITLParseChartPoints(steps:GetChartName())
		end

		if not format then
			-- Fall back to values stored from an earlier successful parse.
			if (hashMap[hash]["maxScoringPoints"] or 0) > 0 then
				passingPoints   = hashMap[hash]["passingPoints"] or 0
				maxScoringPoints = hashMap[hash]["maxScoringPoints"]
				format = passingPoints > 0 and "ps" or "pts"
			end
		end

		if format then
			hashMap[hash]["passingPoints"]   = passingPoints
			hashMap[hash]["maxScoringPoints"] = maxScoringPoints
			hashMap[hash]["maxPoints"]        = passingPoints + maxScoringPoints
			hashMap[hash]["points"] = ITLComputePoints(passingPoints, maxScoringPoints, format, exscore/100)
		end

		updated = true

		if updated then
			CalculateITLSongRanks(player)
			WriteItlFile(player)
		end
	end
end

-- Should be called during ScreenEvaluation to update the ITL data loaded.
-- Will also write the contents to the file.
UpdateItlData = function(player)
	local pn = ToEnumShortString(player)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
		
	-- Do the same validation as GrooveStats.
	-- This checks important things like timing windows, addition/removal of arrows, etc.
	local _, valid = ValidForGrooveStats(player)

	-- ITL additionally requires the music rate to be 1.00x.
	local so = GAMESTATE:GetSongOptionsObject("ModsLevel_Song")
	local rate = so:MusicRate()

	-- We also require mines to be on.
	local po = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred")
	local minesEnabled = not po:NoMines()

	-- We also require all the windows to be enabled.
	-- ITG mode is the only mode that has all the windows enabled by default.
	local allWindowsEnabled = SL.Global.GameMode == "ITG"
	for enabled in ivalues(SL[pn].ActiveModifiers.TimingWindows) do
		allWindowsEnabled = allWindowsEnabled and enabled
	end

	if (GAMESTATE:IsHumanPlayer(player) and
				valid and
				rate == 1.0 and
				minesEnabled and
				not stats:GetFailed() and
				allWindowsEnabled) then
		local hash = SL[pn].Streams.Hash
		local hashMap = SL[pn].ITLData["hashMap"]

		local prevData = nil
		if hashMap ~= nil and hashMap[hash] ~= nil then
			prevData = hashMap[hash]
		end

		local data = DataForSong(player, prevData)

		-- C-Modded a No CMOD chart. Don't save this score.
		if data["noCmod"] and data["usedCmod"] then
			return
		end

		-- Update the pathMap as needed.
		local song = GAMESTATE:GetCurrentSong()
		local song_dir = song:GetSongDir()
		if song_dir ~= nil and #song_dir ~= 0 then
			local pathMap = SL[pn].ITLData["pathMap"]
			pathMap[song_dir] = hash
		end
		
		-- Then maybe update the hashMap.
		local updated = false
		if hashMap[hash] == nil then
			-- New score, just copy things over.
			hashMap[hash] = {
				["judgments"] = DeepCopy(data["judgments"]),
				["ex"] = data["ex"],
				["clearType"] = data["clearType"],
				["points"] = data["points"],
				["usedCmod"] = data["usedCmod"],
				["date"] = data["date"],
				["maxPoints"] = data["maxPoints"],
				["noCmod"] = data["noCmod"],
				["stepsType"] = data["stepsType"],
				["season"] = ITLSeasonFromGroupName(song:GetGroupName()) or "unknown",
			}
			updated = true
		else
			if data["ex"] >= hashMap[hash]["ex"] then
				hashMap[hash]["ex"] = data["ex"]
				hashMap[hash]["points"] = data["points"]
				
				if data["ex"] > hashMap[hash]["ex"] then
					-- EX count is strictly better, copy the judgments over.
					hashMap[hash]["judgments"] = DeepCopy(data["judgments"])
					updated = true
				else
					-- EX count is tied.
					-- "Smart" update judgment counts by picking the one with the highest top judgment.
					local better = false
					local keys = { "W0", "W1", "W2", "W3", "W4", "W5", "Miss" }
					for key in ivalues(keys) do
						local prev = hashMap[hash]["judgments"][key]
						local cur = data["judgments"][key]
						-- If both windows are defined, take the greater one.
						-- If current is defined but previous is not, then current is better.
						if (cur ~= nil and prev ~= nil and cur > prev) or (cur ~= nil and prev == nil) then
							better = true
							break
						end
					end

					if better then
						hashMap[hash]["judgments"] = DeepCopy(data["judgments"])
						updated = true
					end
				end
			end	

			if data["clearType"] > hashMap[hash]["clearType"] then
				hashMap[hash]["clearType"] = data["clearType"]
				updated = true
			end

			if updated then
				hashMap[hash]["usedCmod"] = data["usedCmod"]
				hashMap[hash]["date"] = data["date"]
				hashMap[hash]["noCmod"] = data["noCmod"]
				hashMap[hash]["maxPoints"] = data["maxPoints"]
				hashMap[hash]["stepsType"] = data["stepsType"]
			end
		end

		if updated then
			CalculateITLSongRanks(player)
			WriteItlFile(player)
		end
		-- This probably doesn't need to be a global message
		if SCREENMAN:GetTopScreen():GetName() == "ScreenEvaluationStage" then MESSAGEMAN:Broadcast("ItlDataReady",{player=player}) end
	end
end