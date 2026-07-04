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

-- Tier color for a rank, reusing the FA+ judgment gradient (top ranks = gold),
-- mirroring the existing per-row local-rank coloring.
ITLRankColor = function(n)
	if type(n) ~= "number" then return Color.White end
	if     n <= 10 then return SL.JudgmentColors["FA+"][1]
	elseif n <= 25 then return SL.JudgmentColors["FA+"][2]
	elseif n <= 50 then return SL.JudgmentColors["FA+"][3]
	elseif n <= 75 then return SL.JudgmentColors["FA+"][4]
	elseif n <= 85 then return SL.JudgmentColors["FA+"][5]
	else                return Color.Red end
end
