# SelectMusic Global ITL Rank on Visible Rows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `ScreenSelectMusic`, show a solo player's global ITL leaderboard rank (e.g. `47th`) to the left of each visible wheel row that is a played ITL song, fetched on demand — sequentially, debounced, cached, with 429 backoff.

**Architecture:** A shared helper module (`SL-Helpers-ITLRank.lua`) owns a per-session cache, a fetch queue, and formatting helpers. A single manager actor (`ITLRankManager.lua`) drains the queue one GrooveStats request at a time after the wheel settles, caches each self ITL rank, and broadcasts `ITLRankResolved`. Each wheel row (`MusicWheelItem Song NormalPart`) looks up its song's hash, shows the cached rank or enqueues a fetch, and updates on the broadcast. In Scorebox mode, `Scorebox.lua` seeds the cache for the selected song (one fewer request).

**Tech Stack:** Lua 5.1 (ITGmania theme scripting). No build step, no automated test runner — verification is static review plus in-game manual testing.

## Global Constraints

- **Do NOT `git commit`.** Leave changes in the working tree; the user commits.
- Lua theme only; no engine changes.
- **Rate-limit safety is mandatory:** requests are strictly **sequential** (one in flight at a time), **debounced** (only after the wheel settles), **cached** per hash, and **back off on HTTP 429**. Requests must mirror the known-valid Scorebox request shape so they never trip the global `SL.GrooveStats.IsConnected = false` disable (which happens on a non-429 4xx).
- **Endpoint:** `player-leaderboards.php?chartHashP1=<hash>&maxLeaderboardResults=1` with header `x-api-key-player-1: <apiKey>`. Always use the P1 request slot (a channel); parse `data.player1.itl.itlLeaderboard`, taking the `isSelf` entry's `rank`.
- **Scope:** solo only (`#GAMESTATE:GetHumanPlayers() == 1`), active player with a persistent profile + non-empty `ApiKey`, ITL songs the player has **played** (hash present in `SL[pn].ITLData.pathMap`).
- **Cache values:** `SL.Global.ITLRankCache[hash]` = `number` (resolved rank) | `false` (fetched, no rank) | `nil` (not fetched).
- **Message:** `ITLRankResolved` with payload `{ hash = <hash> }`.
- `Scripts/` files are auto-loaded by the engine at startup and must NOT touch `SL.Global` at file-load time (this file loads before `SL_Init.lua`); only touch it at runtime via `ITLRankInit()`.
- Reference design doc: `docs/superpowers/specs/2026-07-04-selectmusic-itl-rank-design.md`.

---

### Task 1: Shared helper module (cache, queue, formatting)

**Files:**
- Create: `Scripts/SL-Helpers-ITLRank.lua`

**Interfaces:**
- Consumes: `SL.Global`, `SL.JudgmentColors`, `Color` (all runtime globals).
- Produces (globals):
  - `ITLRankInit()` — idempotent; ensures `SL.Global.ITLRankCache/Queue/Pending` exist.
  - `ITLRankGet(hash)` → `number | false | nil`.
  - `ITLRankSet(hash, value)` — store value, clear pending.
  - `ITLRankEnqueue(hash)` — enqueue if truthy, uncached, not pending.
  - `ITLRankDequeue()` → next uncached queued `hash` or `nil`.
  - `ITLRankOrdinal(n)` → `string` (e.g. `"47th"`, `"103rd"`, `"1st"`).
  - `ITLRankColor(n)` → a color.

- [ ] **Step 1: Create the file**

Create `Scripts/SL-Helpers-ITLRank.lua` with exactly:

```lua
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
```

- [ ] **Step 2: Static review**

Confirm by reading:
1. No `SL.Global` access happens at file scope — only inside functions (so load-order before `SL_Init.lua` is safe).
2. `ITLRankOrdinal` outputs: `1→"1st"`, `2→"2nd"`, `3→"3rd"`, `4→"4th"`, `11→"11th"`, `12→"12th"`, `13→"13th"`, `21→"21st"`, `101→"101st"`, `103→"103rd"`, `111→"111th"`.
3. `ITLRankEnqueue` dedupes via cache and pending; `ITLRankDequeue` skips hashes cached after queuing and clears their pending mark.
4. `ITLRankGet` distinguishes `false` (no rank) from `nil` (unfetched).

- [ ] **Step 3: Leave for user to commit** (do NOT run `git commit`)

Changed file: `Scripts/SL-Helpers-ITLRank.lua`.

---

### Task 2: Fetch manager actor + wiring

**Files:**
- Create: `BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua`
- Modify: `BGAnimations/ScreenSelectMusic overlay/default.lua` (add one `LoadActor` line after the `PlayerModifiers.lua` load, ~line 42)

**Interfaces:**
- Consumes: `ITLRankInit`, `ITLRankEnqueue`, `ITLRankSet`, `ITLRankDequeue` (Task 1); `SL.Global.ITLRankPending`; `IsServiceAllowed`, `SL.GrooveStats.GetScores`, `SL[pn].ApiKey`, `RequestResponseActor`, `NETWORK:EncodeQueryParameters`, `JsonDecode`, `GetTimeSinceStart`, `ivalues`, `GAMESTATE:GetHumanPlayers`.
- Produces: broadcasts `ITLRankResolved { hash }`; drains `SL.Global.ITLRankQueue`.

- [ ] **Step 1: Create the manager**

Create `BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua` with exactly:

```lua
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
```

- [ ] **Step 2: Wire it into the overlay**

In `BGAnimations/ScreenSelectMusic overlay/default.lua`, find (~line 41-42):

```lua
	-- Apply player modifiers from profile
	LoadActor("./PlayerModifiers.lua"),
```

Immediately AFTER that line, insert:

```lua

	-- On-demand global ITL leaderboard ranks for visible wheel rows (sequential,
	-- debounced, cached, 429-backoff). Inert unless solo + GrooveStats + api key.
	LoadActor("./ITLRankManager.lua"),
```

- [ ] **Step 3: Static review**

Confirm:
1. The manager returns an inert `Def.ActorFrame{}` unless solo AND `IsServiceAllowed(SL.GrooveStats.GetScores)` AND the active player's `ApiKey ~= ""`.
2. Exactly one request is in flight at a time: `DrainNext` returns early while `self.requesting`; `RequestDone`/`RateLimited` reset it; each response schedules exactly one follow-up `DrainNext`.
3. `CurrentSongChanged` debounces via `stoptweening()` + `sleep(0.4)`.
4. `429` → requeue the hash + `RateLimited` (cooldown 30s; stop after 3 hits); non-429 error → cache `false`; success → cache the `isSelf` rank (or `false`), broadcast `ITLRankResolved`.
5. The request uses the P1 slot (`chartHashP1`, `x-api-key-player-1`) and parses `data.player1.itl.itlLeaderboard`; the `RequestResponseActor` is off-screen `(-1000,-1000)` so its spinner never shows.
6. `default.lua` gains exactly one `LoadActor("./ITLRankManager.lua")` in the code group; no other lines disturbed.

- [ ] **Step 4: In-game verification**

Solo, GrooveStats connected, api key present, inside an ITL pack:
1. Enter SelectMusic; after ~1s the manager begins fetching. Watch `Logs/log.txt` / network: requests fire **one at a time**, not in a burst.
2. Scroll fast across many songs → still no burst (debounce): fetches happen after you stop.
3. Non-solo, or GrooveStats disabled, or no api key → no requests fired.

- [ ] **Step 5: Leave for user to commit** (do NOT run `git commit`)

Changed files: `BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua` (new), `BGAnimations/ScreenSelectMusic overlay/default.lua`.

---

### Task 3: Per-row rank display on the wheel

**Files:**
- Modify: `Graphics/MusicWheelItem Song NormalPart/default.lua` (append one `BitmapText` to `af` before `return af`)

**Interfaces:**
- Consumes: `ITLRankGet`, `ITLRankEnqueue`, `ITLRankOrdinal`, `ITLRankColor` (Task 1); the `ITLRankResolved` message (Task 2 / Task 4); `SL[pn].ITLData.pathMap`, `GAMESTATE:GetHumanPlayers`, `PROFILEMAN:IsPersistentProfile`, `ThemePrefs.Get`.
- Produces: a per-row visual only.

- [ ] **Step 1: Append the display actor**

In `Graphics/MusicWheelItem Song NormalPart/default.lua`, immediately BEFORE the final `return af` line, insert:

```lua
-- Global ITL leaderboard rank (fetched on demand; see Scripts/SL-Helpers-ITLRank.lua
-- and BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua). Shown to the LEFT
-- of the row for the solo active player on played ITL songs.
af[#af+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small" or "Mega/_mega font",
	Text="",
	Name="ITLGlobalRank",
	InitCommand=function(self)
		self:visible(false):horizalign(left):zoom(0.22)
		-- TWEAK: horizontal position of the rank at the left of the row
		self:x(4)
		self.hash = nil
	end,
	SetCommand=function(self, params)
		self:visible(false)
		self.hash = nil

		-- Solo only; active player needs a persistent profile.
		local humans = GAMESTATE:GetHumanPlayers()
		if #humans ~= 1 then return end
		local player = humans[1]
		if not PROFILEMAN:IsPersistentProfile(player) then return end
		local pn = ToEnumShortString(player)

		local song = params.Song
		if not song then return end
		local song_dir = song:GetSongDir()
		if not song_dir or #song_dir == 0 then return end

		local hash = SL[pn].ITLData["pathMap"][song_dir]
		if not hash then return end
		self.hash = hash

		local rank = ITLRankGet(hash)
		if type(rank) == "number" then
			self:settext(ITLRankOrdinal(rank)):diffuse(ITLRankColor(rank)):visible(true)
		elseif rank == false then
			-- fetched: player has no ITL rank on this chart
			self:visible(false)
		else
			-- not fetched yet: ask the manager, but only if it can actually fetch
			-- (mirror ITLRankManager's gate) so we don't accumulate hashes that
			-- will never be drained. Updates arrive via ITLRankResolved.
			if SL[pn].ApiKey ~= "" and IsServiceAllowed(SL.GrooveStats.GetScores) then
				ITLRankEnqueue(hash)
			end
		end
	end,
	ITLRankResolvedMessageCommand=function(self, params)
		if self.hash and params.hash == self.hash then
			local rank = ITLRankGet(self.hash)
			if type(rank) == "number" then
				self:settext(ITLRankOrdinal(rank)):diffuse(ITLRankColor(rank)):visible(true)
			else
				self:visible(false)
			end
		end
	end,
}
```

- [ ] **Step 2: Static review**

Confirm:
1. On every `Set`, the actor resets to hidden and recomputes `self.hash` (wheel items are reused for different songs as they scroll).
2. It shows only for solo + persistent profile + a `pathMap` hash (played ITL song); otherwise hidden.
3. Cache hit (number) → shows ordinal, colored; `false` → hidden; `nil` → hidden + `ITLRankEnqueue`.
4. `ITLRankResolvedMessageCommand` updates only rows whose current `self.hash` matches `params.hash` (guards against stale updates as rows scroll).
5. Balanced braces; the actor is appended to `af` before `return af`.

- [ ] **Step 3: In-game verification**

Solo, GrooveStats + api key, inside an ITL pack:
1. Browse the wheel; after it settles, played ITL rows show a global rank on their left (`47th`, `103rd`, …) colored by tier; unplayed / non-ITL rows show nothing.
2. Scroll away and back to a resolved row → its rank shows immediately (cached).
3. Confirm the position reads as "to the left of the row"; adjust the `-- TWEAK` `x(4)` if it overlaps the title.

- [ ] **Step 4: Leave for user to commit** (do NOT run `git commit`)

Changed file: `Graphics/MusicWheelItem Song NormalPart/default.lua`.

---

### Task 4: Seed the cache from the Scorebox (Scorebox mode optimization)

**Files:**
- Modify: `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua` (insert into `LeaderboardRequestProcessor`, right after the stale-hash guard ~line 172)

**Interfaces:**
- Consumes: `ITLRankSet` (Task 1); the ITL leaderboard already parsed from the Scorebox response.
- Produces: seeds `SL.Global.ITLRankCache` and broadcasts `ITLRankResolved { hash }` for the selected song.

- [ ] **Step 1: Insert the cache seeding**

In `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua`, find this existing line inside `LeaderboardRequestProcessor` (~line 172):

```lua
		if SL[pn].Streams.Hash ~= data[playerStr]["chartHash"] then return end
```

Immediately AFTER that line, insert:

```lua

		-- Seed the global-ITL-rank cache for the selected song so ITLRankManager
		-- doesn't re-fetch it (see Scripts/SL-Helpers-ITLRank.lua). Runs regardless
		-- of the ITL scorebox display toggle.
		if data[playerStr]["itl"] and data[playerStr]["itl"]["itlLeaderboard"] then
			local selfRank = false
			for entry in ivalues(data[playerStr]["itl"]["itlLeaderboard"]) do
				if entry["isSelf"] then selfRank = entry["rank"]; break end
			end
			ITLRankSet(data[playerStr]["chartHash"], selfRank)
			MESSAGEMAN:Broadcast("ITLRankResolved", { hash=data[playerStr]["chartHash"] })
		end
```

- [ ] **Step 2: Static review**

Confirm:
1. The insertion is inside `LeaderboardRequestProcessor`, after the `if data and data[playerStr] then` check and the stale-hash guard (so `data[playerStr]` and `chartHash` are valid and current).
2. It sets `selfRank` from the `isSelf` entry (or `false` if none), calls `ITLRankSet(chartHash, selfRank)`, and broadcasts `ITLRankResolved` with that hash.
3. It does NOT depend on `showEvents` / the ITL scorebox display path; no existing lines are changed.
4. `ITLRankSet` is a global from Task 1 (auto-loaded via `Scripts/`).

- [ ] **Step 3: In-game verification**

Solo, `MusicWheelGS = Scorebox`, GrooveStats + api key, on an ITL song:
1. Select an ITL song → its row's global rank appears without the manager firing a separate request for it (the Scorebox request seeds it). It matches the rank the Scorebox shows in its ITL leaderboard style.
2. In `MusicWheelGS = Pane` or `Off`, the selected song's rank still appears (fetched by the manager instead).

- [ ] **Step 4: Leave for user to commit** (do NOT run `git commit`)

Changed file: `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua`.

---

## Self-Review notes (author)

- **Spec coverage:**
  - Per-row global ITL rank on visible rows, left of the row → Task 3 (display) + Task 1 (helpers) + Task 2 (fetch).
  - Fetched on demand, sequential, debounced, cached, 429 backoff, no GS disconnect → Task 2 (manager) + Global Constraints.
  - ITL event leaderboard (`itlLeaderboard`, `isSelf` rank), endpoint `player-leaderboards.php` → Task 2 + Task 4.
  - Solo / profile / api key gating; played ITL songs only → Tasks 2 & 3.
  - Scorebox-mode cache seeding (one fewer request) → Task 4.
  - Ordinal + tier color → Task 1.
- **Placeholder scan:** none — all code, paths, and the one position value (`x(4)`, flagged `-- TWEAK`) are concrete.
- **Type consistency:** cache values `number|false|nil` used consistently across Tasks 1–4; message `ITLRankResolved`/`{hash}` produced (Tasks 2, 4) and consumed (Task 3) identically; helper names (`ITLRankInit/Get/Set/Enqueue/Dequeue/Ordinal/Color`) match between definition (Task 1) and use (Tasks 2, 3, 4).
- **No-commit constraint** honored: every task ends with "Leave for user to commit".
```