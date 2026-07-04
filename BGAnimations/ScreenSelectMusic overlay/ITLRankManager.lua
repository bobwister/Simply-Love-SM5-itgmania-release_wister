-- Sequential, rate-limit-friendly fetcher for global ITL leaderboard ranks.
-- Wheel rows enqueue the chart hashes they need (Scripts/SL-Helpers-ITLRank.lua);
-- this manager drains the queue ONE request at a time, only after the wheel
-- settles (~0.4s debounce), caches each result, and broadcasts "ITLRankResolved"
-- so rows update. Backs off on HTTP 429; never triggers the global GS disconnect.

local humans = GAMESTATE:GetHumanPlayers()
-- Solo only.
if #humans ~= 1 then return Def.ActorFrame{} end

local player = humans[1]
local pn = ToEnumShortString(player)

-- Needs GrooveStats scores allowed and the active player's api key.
if not IsServiceAllowed(SL.GrooveStats.GetScores) or SL[pn].ApiKey == "" then
	return Def.ActorFrame{}
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
	local data = JsonDecode(res.body)
	if data and data["player1"] and data["player1"]["itl"]
			and data["player1"]["itl"]["itlLeaderboard"] then
		for entry in ivalues(data["player1"]["itl"]["itlLeaderboard"]) do
			if entry["isSelf"] then
				rank = entry["rank"]
				break
			end
		end
	end
	ITLRankSet(hash, rank)
	MESSAGEMAN:Broadcast("ITLRankResolved", { hash=hash })
	manager:playcommand("RequestDone")
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
		if not hash then return end

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
