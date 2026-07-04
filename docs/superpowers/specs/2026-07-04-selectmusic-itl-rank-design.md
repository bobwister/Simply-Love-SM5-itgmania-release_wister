# SelectMusic — Global ITL Rank on Visible Wheel Rows — Design

**Date:** 2026-07-04
**Status:** Approved (pending written-spec review)

## Goal

On `ScreenSelectMusic`, for a solo player connected to GrooveStats, show the
player's **global ITL leaderboard rank** (e.g. `47th`, `103rd`) to the **left**
of each visible wheel row that is an ITL song the player has played. Ranks are
fetched on demand — only for visible rows, only when the wheel settles — and
cached, so the GrooveStats API is queried gently (never a burst, never a bulk
scan of the whole pack).

The per-row ITL **points** and the existing per-row *local* rank
(`hashMap[hash].rank`, the player's own songs ordered by points) are unchanged —
this feature adds the **global** placement, which is not otherwise available.

## Context (verified in the codebase)

- **ITL data** lives in `SL[pn].ITLData` = `{ pathMap, hashMap }`.
  `pathMap[song_dir] = hash` for songs the player has played;
  `hashMap[hash] = { points, ex, rank (LOCAL), clearType, ... }`
  (`Scripts/SL_ITL.lua`). The `rank` field is the player's personal ordering of
  their own songs by points — **not** the global leaderboard placement.
- **Global ITL rank** is only obtainable from the GrooveStats API, per chart:
  `player-leaderboards.php?chartHashP1=<hash>` with header
  `x-api-key-player-1: <apiKey>` returns
  `data.player1.itl.itlLeaderboard` — a list of entries each with
  `rank`, `name`, `score`, `isSelf`, `isFail`; the `isSelf` entry's `rank` is
  the player's **true global placement** even when only the top few + self are
  returned (`BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua`).
  The response also carries `data.player1.chartHash` for staleness checks.
- **The API is per-chart** (one `chartHashP1` per request). There is **no bulk
  endpoint** (`player-scores.php` is likewise per-chart). GrooveStats
  **rate-limits server-side** (HTTP 429). The theme disables the whole GS
  connection (`SL.GrooveStats.IsConnected = false`) on a persistent 4xx that is
  **not** 429 — so requests must mirror the known-valid Scorebox request shape,
  and 429 must be handled with backoff (never hammering).
- **Wheel rows** each receive `SetCommand{ Song=<song> }` broadcasts as the wheel
  updates; per-row ITL lookups already use `SL[pn].ITLData.pathMap[song:GetSongDir()]`
  (`Graphics/MusicWheelItem Song NormalPart/default.lua`,
  `Graphics/MusicWheelItem Grades/default.lua`).
- **Request infra:** `RequestResponseActor(x,y)` (in
  `Scripts/SL-Helpers-GrooveStats.lua`) owns one in-flight HTTP request via
  `MakeGrooveStatsRequestCommand{ endpoint, method, headers, timeout, callback,
  args }`; `IsServiceAllowed(SL.GrooveStats.GetScores)` gates GS use.

## Decisions (from brainstorming)

- **Scope:** global ITL rank for **visible** ITL rows, fetched on demand. ✅
- **Which leaderboard:** the **ITL event** leaderboard (`itlLeaderboard`), not the
  standard GrooveStats leaderboard. ✅
- **Placement:** to the **left** of each wheel row. ✅
- **Rate-limit safety is central:** debounced (only after the wheel settles),
  strictly **sequential** (one request at a time), **cached** per hash, **429 →
  cooldown**, never triggering the global GS disconnect. ✅
- **Player scope:** solo only (one side joined); the active/joined human player.
- **Mode independence:** the feature makes its own requests, so it works
  regardless of `MusicWheelGS` (Scorebox/Pane/Off). In `Scorebox` mode we
  additionally seed the cache from the request the Scorebox already makes for the
  selected song (one fewer request).
- **Coverage:** only ITL songs the player has **played** (hash known via
  `pathMap`). Unplayed songs show nothing (the player has no rank anyway).

## Architecture & components

### Component A — ITL rank cache + fetch manager

**Files:**
- New: `Scripts/SL-Helpers-ITLRank.lua` — pure helpers (cache access, queue,
  ordinal formatting, rank→color).
- New: `BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua` — the actor
  that owns the request loop (loaded once, not per-player).

**State (in `SL.Global`, initialized in `SL-Helpers-ITLRank.lua`):**
- `SL.Global.ITLRankCache = { [hash] = <number> | false }` — `number` = resolved
  global rank; `false` = fetched, player has no ITL rank on that chart; absent =
  not yet fetched. Persists for the app session.
- `SL.Global.ITLRankQueue = {}` — array of hashes awaiting fetch.
- `SL.Global.ITLRankPending = { [hash] = true }` — dedupe set (queued or
  in-flight) so a hash is never enqueued twice.

**Helper API (`SL-Helpers-ITLRank.lua`):**
- `ITLRankInit()` — ensure the `SL.Global` tables exist (idempotent).
- `ITLRankEnqueue(hash)` — if `hash` is truthy, not in cache, and not pending →
  push to queue, mark pending. No-op otherwise.
- `ITLRankGet(hash)` — returns the cached value (`number` / `false` / `nil`).
- `ITLRankOrdinal(n)` — `1→"1st"`, `2→"2nd"`, `3→"3rd"`, `11/12/13→"th"`,
  `47→"47th"`, `103→"103rd"`.
- `ITLRankColor(n)` — tier color by absolute rank, reusing the existing per-row
  thresholds (`SL.JudgmentColors["FA+"]` gradient; e.g. ≤10 gold … else red).

**Manager actor (`ITLRankManager.lua`):**
- On screen load: `ITLRankInit()`. Gate the whole actor: return an inert frame
  unless `IsServiceAllowed(SL.GrooveStats.GetScores)` and exactly one human
  player joined with a non-empty `ApiKey`.
- **Debounced draining:** listens for `CurrentSongChangedMessageCommand` (fires
  on every wheel move). Each fire (re)arms a ~0.4s debounce; when it elapses with
  no newer change (token check), it starts draining if idle.
- **Sequential drain:** owns one `RequestResponseActor`. Pop the next hash whose
  value is still absent from the cache; issue
  `player-leaderboards.php?chartHashP1=<hash>&maxLeaderboardResults=1` with the
  active player's api-key header; on response:
  - `429` → set a cooldown (~30s), keep the hash pending, stop draining until the
    cooldown elapses (re-armed by the next settle or a scheduled retry). Repeated
    429s → stop for the screen.
  - success → find the `isSelf` entry in `data.playerN.itl.itlLeaderboard`; set
    `ITLRankCache[hash] = entry.rank` (or `false` if no self entry / no itl
    block); clear pending; `MESSAGEMAN:Broadcast("ITLRankResolved", { hash=hash })`.
  - other error → set `false` (so we don't retry endlessly this screen), clear
    pending, continue.
  - After each response, a short delay (~0.2s) then pop the next. Never more than
    one request in flight.

### Component B — per-row rank display

**Files:**
- Modify: `Graphics/MusicWheelItem Song NormalPart/default.lua` — add one
  `BitmapText` positioned to the **left** of the row.

**Behavior (on that BitmapText):**
- `SetCommand{ Song }`: reset to hidden. Only proceed if solo + active player has
  a profile + api key. Compute `hash = SL[pn].ITLData.pathMap[song:GetSongDir()]`.
  If no hash (not a played ITL song) → stay hidden, remember `self.hash=nil`.
  Else store `self.hash=hash`, then:
  - `v = ITLRankGet(hash)`: if `v` is a number → `settext(ITLRankOrdinal(v))`,
    color `ITLRankColor(v)`, visible; if `v == false` → hidden; if `nil` →
    hidden **and** `ITLRankEnqueue(hash)`.
- `ITLRankResolvedMessageCommand{ hash }`: if `hash == self.hash`, re-run the
  display logic for the now-cached value.
- Position: left margin of the wheel item (x marked `-- TWEAK`), small zoom
  consistent with the existing per-row ITL text.

### Component C — Scorebox cache seeding (optimization, Scorebox mode only)

**Files:**
- Modify: `BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua` — in
  `LeaderboardRequestProcessor`, after `data[playerStr]` is confirmed, if
  `data[playerStr].itl.itlLeaderboard` has an `isSelf` entry, write its `rank`
  into `SL.Global.ITLRankCache[data[playerStr].chartHash]` and broadcast
  `ITLRankResolved{ hash }`. This is independent of the existing `showEvents`
  display path (so it works even if the ITL scorebox style is toggled off) and
  saves the manager one request for the selected song.

## Data flow

```
wheel settles (CurrentSongChanged debounced ~0.4s)
  each visible row (Set): hash = pathMap[song_dir]
     cache hit  -> display rank immediately
     cache miss -> ITLRankEnqueue(hash)   (deduped)
  manager drains queue SEQUENTIALLY:
     pop hash -> player-leaderboards.php?chartHashP1=hash (1 in flight)
        429      -> cooldown, keep pending, back off
        success  -> cache[hash]=selfRank|false; broadcast ITLRankResolved{hash}
     (~0.2s delay) -> next hash
  rows listening for ITLRankResolved{hash} update themselves
[Scorebox mode] selected-song response also seeds cache -> one fewer request
```

## Error handling & rate-limit safety

| Situation | Behavior |
|-----------|----------|
| Not solo / no profile / no api key / GS not allowed | Manager inert; rows hide the rank. |
| Non-ITL or unplayed song (no hash) | Row hides the rank; nothing enqueued. |
| Fast scrolling | No fetches (debounce); rows only read cache. |
| HTTP 429 | Cooldown (~30s), keep hash pending, stop draining; resume gently. Persistent 429 → stop for the screen. |
| Other 4xx/5xx/timeout | Cache `false` for that hash (no retry loop this screen); continue. Requests mirror the valid Scorebox shape to avoid tripping the global `IsConnected=false` disable. |
| Player has no ITL score on a chart | `isSelf` absent → cache `false` → row shows nothing. |
| Stale response (wheel moved on) | Rows key on `self.hash`; `ITLRankResolved` only updates rows whose current hash matches. |

## Limitations (accepted)

- Ranks appear with a short async delay after the wheel settles.
- Only ITL songs the player has **played** (hash in `pathMap`) get a rank.
- Cache is session-lived; a rank that changes server-side mid-session is not
  refreshed until the theme restarts (acceptable; ranks drift slowly).
- Browsing a very large ITL pack enqueues many hashes; they are drained slowly
  (one at a time) and paused on 429 — no GS disconnect, but some ranks fill in
  gradually.

## Testing / verification (manual, in-game)

No automated test framework (Lua theme, engine not launchable here). Verify:

1. Solo, GrooveStats connected, api key present, inside an ITL pack: browse the
   wheel; after it settles, each played ITL row shows a global rank on its left
   (`47th`, `103rd`, …), colored by tier; unplayed/non-ITL rows show nothing.
2. Scroll quickly across many songs: no burst of requests (watch `Logs/log.txt`
   / network); ranks fill in gradually one at a time after you stop.
3. The currently-selected song's rank matches what the Scorebox shows in its ITL
   leaderboard style (and in Scorebox mode, appears without an extra request).
4. Force/observe a 429 (or simulate): the manager pauses and does not disconnect
   GrooveStats; the selected-song Scorebox keeps working.
5. 2 players joined, or GrooveStats disabled, or a non-ITL pack: no per-row global
   rank shown; no requests fired.
6. Re-enter the screen: cached ranks display immediately without re-fetching.

## Constraints

- **Do NOT `git commit`** — leave changes in the working tree; the user commits.
- No engine changes; Lua theme only.
- Be a good API citizen: sequential requests only, debounced, cached, 429 backoff.
