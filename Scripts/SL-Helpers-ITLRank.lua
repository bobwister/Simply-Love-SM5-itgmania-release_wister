-- ITL global-rank cache + fetch queue + display helpers, shared by the
-- ScreenSelectMusic wheel rows (Graphics/MusicWheelItem Song NormalPart) and the
-- fetch manager (BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua).
--
-- Global ITL rank = the active player's placement on a chart's ITL leaderboard,
-- fetched per chart from GrooveStats and cached here so each chart is fetched at
-- most once per session.
--
-- NOTE: this Scripts file is loaded before SL_Init.lua, so it must NOT touch
-- SL.Global at load time. ITLRankInit() (called at runtime) creates the tables.

-- Ensure the SL.Global scratch tables exist. Idempotent; safe to call anytime.
ITLRankInit = function()
	SL.Global.ITLRankCache   = SL.Global.ITLRankCache   or {}  -- [hash] = number | false
	SL.Global.ITLRankQueue   = SL.Global.ITLRankQueue   or {}  -- array of hashes
	SL.Global.ITLRankPending = SL.Global.ITLRankPending or {}  -- [hash] = true
end

-- Returns cached rank: a number (resolved), false (fetched, no rank),
-- or nil (not fetched yet).
ITLRankGet = function(hash)
	ITLRankInit()
	if not hash then return nil end
	return SL.Global.ITLRankCache[hash]
end

-- Store a resolved value (number or false) and clear the pending mark.
ITLRankSet = function(hash, value)
	ITLRankInit()
	if not hash then return end
	SL.Global.ITLRankCache[hash] = value
	SL.Global.ITLRankPending[hash] = nil
end

-- Enqueue a hash if it is truthy, not already cached, and not already
-- queued/in-flight. No-op otherwise.
ITLRankEnqueue = function(hash)
	ITLRankInit()
	if not hash then return end
	if SL.Global.ITLRankCache[hash] ~= nil then return end
	if SL.Global.ITLRankPending[hash] then return end
	SL.Global.ITLRankPending[hash] = true
	SL.Global.ITLRankQueue[#SL.Global.ITLRankQueue + 1] = hash
end

-- Pop the next hash that still needs fetching (skips any cached while queued).
-- Returns a hash or nil if the queue is exhausted.
ITLRankDequeue = function()
	ITLRankInit()
	local q = SL.Global.ITLRankQueue
	while #q > 0 do
		local hash = table.remove(q, 1)
		if SL.Global.ITLRankCache[hash] == nil then
			return hash
		else
			SL.Global.ITLRankPending[hash] = nil
		end
	end
	return nil
end

-- Format an integer rank as an English ordinal:
-- 1->"1st", 2->"2nd", 3->"3rd", 11/12/13->"th", 47->"47th", 103->"103rd".
ITLRankOrdinal = function(n)
	if type(n) ~= "number" then return "" end
	n = math.floor(n)
	local mod100 = n % 100
	local suffix
	if mod100 >= 11 and mod100 <= 13 then
		suffix = "th"
	else
		local mod10 = n % 10
		if     mod10 == 1 then suffix = "st"
		elseif mod10 == 2 then suffix = "nd"
		elseif mod10 == 3 then suffix = "rd"
		else                   suffix = "th" end
	end
	return tostring(n) .. suffix
end

-- Tier color for a global ITL rank.
ITLRankColor = function(n)
	if type(n) ~= "number" then return Color.White end
	if     n <= 10  then return color("#FFD700") -- gold
	elseif n <= 50  then return Color.Green
	elseif n <= 100 then return Color.Yellow
	else                 return Color.White end
end

-- Resolve song -> chart hash, computing and caching it into pathMap on the
-- fly if it isn't known yet (e.g. the player has never selected/played this
-- chart before, so nothing has populated pathMap for it). Only handles songs
-- with exactly one steps chart, same assumption ReadItlFile's stepsType sweep
-- already makes about what counts as a "pure" ITL chart. Returns a hash, or
-- nil if it can't be resolved (ambiguous song, unparseable chart, etc.).
ITLResolveHashForSong = function(pn, song)
	if not song then return nil end
	local song_dir = song:GetSongDir()
	if not song_dir or #song_dir == 0 then return nil end

	local pathMap = SL[pn].ITLData["pathMap"]
	local hash = pathMap[song_dir]
	if hash then return hash end

	local allSteps = song:GetAllSteps()
	if #allSteps ~= 1 then return nil end

	hash = ComputeItlChartHash(allSteps[1])
	if not hash then return nil end

	pathMap[song_dir] = hash
	return hash
end

-- ITL points for a chart, computed from PURELY LOCAL data - no network needed.
-- Points are a deterministic function of the chart's declared point values
-- (its #CHARTNAME field) and the player's EX score, and both are available
-- offline: `ex` is already stored in the profile's ITL file for any chart the
-- player has scored on.
--
-- This deliberately does NOT depend on the GrooveStats leaderboard fetch: the
-- fetch is only needed for the GLOBAL RANK (and to learn EX scores set on other
-- machines). Keeping points independent means they render immediately for every
-- locally-scored chart on screen, while ranks trickle in afterwards per song.
--
-- Repairs (and caches) a stuck `points = 0` in place when it can, so the
-- profile's data converges to correct values as songs get looked at. This
-- matters because a long-standing bug in UpdateItlExScore, plus the ITL 2025
-- change to the #CHARTNAME format, left many charts stored with points = 0.
-- Returns a number (0 when genuinely unknown/unscored).
ITLGetPoints = function(pn, song, hash)
	if not hash then return 0 end
	local data = SL[pn].ITLData["hashMap"][hash]
	if not data then return 0 end

	local points = data["points"] or 0
	if points > 0 then return points end

	local ex = data["ex"]
	if type(ex) ~= "number" or ex <= 0 then return 0 end
	if not song then return 0 end

	-- Recompute from the chart's own #CHARTNAME. Only unambiguous when the song
	-- has a single chart, which is the norm for ITL pack entries.
	local allSteps = song:GetAllSteps()
	if #allSteps ~= 1 then return 0 end

	local computed, passingPoints, maxScoringPoints = ITLPointsForSteps(allSteps[1], ex/100)
	if not computed then return 0 end

	data["points"] = computed
	data["passingPoints"] = passingPoints
	data["maxScoringPoints"] = maxScoringPoints
	data["maxPoints"] = passingPoints + maxScoringPoints
	return computed
end
