-- Sequential, rate-limit-friendly fetcher for global ITL leaderboard ranks
-- (and, as a side effect, local ITL points - see ProcessResponse below).
-- Wheel rows enqueue the chart hashes they need (Scripts/SL-Helpers-ITLRank.lua);
-- this manager drains the queue ONE request at a time, only after the wheel
-- settles (~0.4s debounce), caches each result, and broadcasts "ITLRankResolved"
-- so rows update. Backs off on HTTP 429; never triggers the global GS disconnect.
--
-- When the explicit queue runs dry, idle time is spent background-prefetching
-- the rest of the current ITL pack (see PrefetchNextPackHash), lowest
-- priority: on-screen rows always enqueue themselves first and get drained
-- before the background scan resumes.

local humans = GAMESTATE:GetHumanPlayers()
-- Solo only.
if #humans ~= 1 then return Def.ActorFrame{} end

local player = humans[1]
local pn = ToEnumShortString(player)

-- Needs GrooveStats scores allowed and the active player's api key.
if not IsServiceAllowed(SL.GrooveStats.GetScores) or SL[pn].ApiKey == "" then
	return Def.ActorFrame{}
end

-- Reverse-lookup: which song directory maps to this hash in pathMap? Only
-- pathMap has the association; a linear scan is fine here since this only
-- runs once per (rate-limited, ~1-per-0.5s) network response, not per frame.
local function FindSongDirForHash(hash)
	for song_dir, h in pairs(SL[pn].ITLData["pathMap"]) do
		if h == hash then return song_dir end
	end
	return nil
end

-- Parse one leaderboard response, cache the self ITL rank for params.hash, then
-- broadcast and schedule the next drain on params.manager.
local ProcessResponse = function(res, params)
	local manager = params.manager
	local hash = params.hash

	-- Rate limited: requeue and back off.
	if res.statusCode == 429 then
		SL.Global.ITLRankPending[hash] = nil
		ITLRankEnqueue(hash)
		manager:playcommand("RateLimited")
		return
	end

	if res.error or res.statusCode ~= 200 then
		-- Non-429 failure: cache false so we don't retry this chart this session.
		ITLRankSet(hash, false)
		MESSAGEMAN:Broadcast("ITLRankResolved", { hash=hash })
		manager:playcommand("RequestDone")
		return
	end

	local rank = false
	local selfScore = nil
	local data = JsonDecode(res.body)
	if data and data["player1"] and data["player1"]["itl"]
			and data["player1"]["itl"]["itlLeaderboard"] then
		for entry in ivalues(data["player1"]["itl"]["itlLeaderboard"]) do
			if entry["isSelf"] then
				rank = entry["rank"]
				selfScore = entry["score"]
				break
			end
		end
	end
	ITLRankSet(hash, rank)
	-- The leaderboard response already carries our own EX score for this
	-- chart; feed it through the same path the selected-song Scorebox uses
	-- (Scorebox.lua) so points get computed too, not just rank - for every
	-- chart this manager fetches, not only the one currently selected. Must
	-- resolve the ACTUAL song/steps this hash belongs to: GetCurrentSong()
	-- would be wrong here whenever this hash isn't the one currently
	-- highlighted on the wheel (background prefetch case).
	if type(selfScore) == "number" then
		local song_dir = FindSongDirForHash(hash)
		local song = song_dir and SONGMAN:FindSong(song_dir:gsub("/Songs", ""))
		if song then
			-- steps intentionally omitted: pinning down WHICH chart this hash
			-- belongs to would mean re-hashing every chart of the song (a file
			-- read + SHA1 each) on the main thread for every response. Not
			-- worth it here - maxPoints falls back to the pack title prefix,
			-- and the wheel computes points from local data anyway
			-- (ITLGetPoints in Scripts/SL-Helpers-ITLRank.lua).
			UpdateItlExScore(player, hash, selfScore, song, nil)
		end
	end
	MESSAGEMAN:Broadcast("ITLRankResolved", { hash=hash })
	manager:playcommand("RequestDone")
end

-- Every song in the current session's ITL pack(s) (see IsItlSong's group-name
-- pattern), lazily built once and consumed one at a time as idle-time
-- background prefetch fodder. Cheap to build (a name check per song); the
-- expensive part (hash computation) only happens for songs actually reached.
local function BuildBackgroundSongList()
	local list = {}
	for song in ivalues(SONGMAN:GetAllSongs()) do
		local group = string.lower(song:GetGroupName())
		if string.find(group, "itl online %d%d%d%d") or string.find(group, "itl %d%d%d%d") then
			list[#list + 1] = song
		end
	end
	return list
end

-- Resolves (computing+caching the hash if needed) and enqueues the next
-- not-yet-fetched pack song. Returns true if it queued something, false once
-- the whole pack has been swept this session.
local function PrefetchNextPackHash(self)
	if self.bgSongs == nil then
		self.bgSongs = BuildBackgroundSongList()
		self.bgIndex = 1
	end

	while self.bgIndex <= #self.bgSongs do
		local song = self.bgSongs[self.bgIndex]
		self.bgIndex = self.bgIndex + 1

		local hash = ITLResolveHashForSong(pn, song)
		if hash and ITLRankGet(hash) == nil then
			ITLRankEnqueue(hash)
			return true
		end
	end

	return false
end

return Def.ActorFrame{
	Name="ITLRankManager",
	InitCommand=function(self)
		ITLRankInit()
		self.requesting = false
		self.cooldownUntil = 0
		self.rateLimitHits = 0
		self.stopped = false
	end,
	OnCommand=function(self)
		-- Catch the initial visible set once the wheel has populated.
		self:sleep(0.6):queuecommand("DrainNext")
	end,
	-- Debounce: (re)arm a 0.4s timer on each wheel move; drain when it settles.
	CurrentSongChangedMessageCommand=function(self)
		self:stoptweening()
		self:sleep(0.4):queuecommand("DrainNext")
	end,
	RequestDoneCommand=function(self)
		self.requesting = false
		self.rateLimitHits = 0
		self:stoptweening()
		self:sleep(0.5):queuecommand("DrainNext")
	end,
	RateLimitedCommand=function(self)
		self.requesting = false
		self.rateLimitHits = self.rateLimitHits + 1
		if self.rateLimitHits >= 3 then
			-- Persistent throttling: stop for this screen.
			self.stopped = true
			return
		end
		self.cooldownUntil = GetTimeSinceStart() + 30
		self:stoptweening()
		self:queuecommand("DrainNext")
	end,
	DrainNextCommand=function(self)
		if self.stopped then return end
		if self.requesting then return end

		-- Still cooling down after a 429? Re-arm to resume when it elapses, so a
		-- wheel move that cancels the cooldown sleep can't strand the queue.
		local remaining = self.cooldownUntil - GetTimeSinceStart()
		if remaining > 0 then
			self:stoptweening()
			self:sleep(remaining):queuecommand("DrainNext")
			return
		end

		local hash = ITLRankDequeue()
		if not hash then
			-- Nothing explicitly queued (no visible row needs fetching right
			-- now): spend the idle time background-prefetching the rest of
			-- the pack instead of sitting idle.
			if PrefetchNextPackHash(self) then
				self:queuecommand("DrainNext")
			end
			return
		end

		self.requesting = true
		self:GetChild("Requester"):playcommand("Fetch", { hash=hash })
	end,

	RequestResponseActor(-1000, -1000)..{
		Name="Requester",
		FetchCommand=function(self, params)
			local query = {
				chartHashP1 = params.hash,
				maxLeaderboardResults = 1,
			}
			local headers = { ["x-api-key-player-1"] = SL[pn].ApiKey }
			self:playcommand("MakeGrooveStatsRequest", {
				endpoint = "player-leaderboards.php?"..NETWORK:EncodeQueryParameters(query),
				method = "GET",
				headers = headers,
				timeout = 10,
				callback = ProcessResponse,
				args = { manager = self:GetParent(), hash = params.hash },
			})
		end,
	},
}
