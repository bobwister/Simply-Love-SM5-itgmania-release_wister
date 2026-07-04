# Evaluation Mean-Based Song Resync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `ScreenEvaluation`, let a solo player press **Ctrl+Shift+R** to rewrite the just-played song's `#OFFSET` so their systematic timing bias (signed mean offset) is cancelled, with an on-screen confirmation of old/new sync and the applied shift.

**Architecture:** A pure logic function `ResyncSongOffsetFromMean(player)` in `Scripts/SL-Helpers.lua` computes the signed mean from the gameplay offsets, edits the song's `.ssc`/`.sm` file in place via `RageFile`, and reloads the song. A new Shared evaluation actor `ResyncHandler.lua` registers a Ctrl+Shift+R input callback (solo-only, gated by `KeyboardFeatures`, not course mode) and renders a few-seconds feedback overlay. A one-line guard in `RestartHandler.lua` stops Ctrl+**Shift**+R from also firing the existing Ctrl+R replay.

**Tech Stack:** Lua 5.1 (ITGmania theme scripting). No build step, no automated test runner — verification is a static review plus in-game manual testing.

## Global Constraints

- **Do NOT `git commit`.** Leave all changes in the working tree; the user commits themselves.
- Lua theme only; no engine changes.
- **Sign convention (authoritative, verified in engine source):** `new_offset_seconds = old_offset_seconds - (mean_seconds)`, where the mean is Simply Love's signed offset (**positive = late**, negative = early), same as Pane 5 "Mean Offset". A late player → offset decreases → notes move later. Increasing `#OFFSET` makes notes arrive **earlier** (`AdjustSync.cpp`: `delta>0` → "earlier", `delta<0` → "later").
- **RageFile open modes:** read = `1`, write = `2` (write truncates the file on open — always read fully first, then reopen to write).
- The song file to edit is `GAMESTATE:GetCurrentSong():GetSongFilePath()` — the exact `.ssc`/`.sm` the engine loaded (`.ssc` takes priority).
- Only the **first** `#OFFSET:` in the file (the song-level tag) is edited; per-steps split-timing offsets are out of scope.
- Solo-only: active only when `#GAMESTATE:GetHumanPlayers() == 1`.
- Reference design doc: `docs/superpowers/specs/2026-07-04-eval-mean-resync-design.md`.

---

### Task 1: Core resync logic `ResyncSongOffsetFromMean(player)`

**Files:**
- Modify (append a new global function): `Scripts/SL-Helpers.lua`

**Interfaces:**
- Consumes: `SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].sequential_offsets` (array of `{musicSeconds, offset_or_"Miss", ...}`, populated by `BGAnimations/ScreenGameplay overlay/JudgmentOffsetTracking.lua`); `GAMESTATE:GetCurrentSong()`; `RageFileUtil.CreateRageFile()`; `ToEnumShortString`; `ivalues`.
- Produces: global `ResyncSongOffsetFromMean(player)` →
  - on success: `{ old=<sec>, new=<sec>, delta=<sec>, mean_ms=<signed, +late>, direction="later"|"earlier" }`
  - on failure: `nil, reason` where reason ∈ `"no-data" | "no-song" | "read-failed" | "no-offset-tag" | "write-failed"`.

- [ ] **Step 1: Append the function to `Scripts/SL-Helpers.lua`**

Add at the end of the file:

```lua
-- ----------------------------------------------------------------------------
-- ResyncSongOffsetFromMean(player)
--
-- Rewrites the current song's #OFFSET so the player's systematic timing bias
-- (their signed mean judgment offset) is cancelled out, mirroring the engine's
-- autosync math:  new_offset = old_offset - mean_seconds  (mean positive = late).
--
-- Reads the mean from the offsets collected during gameplay (Pane 5 uses the same
-- source), edits the song's loaded .ssc/.sm file in place, then reloads the song
-- so the change is live in memory (an immediate Ctrl+R replay uses the new sync).
--
-- Returns a result table on success:
--   { old=<sec>, new=<sec>, delta=<sec>, mean_ms=<signed, +late>, direction }
-- Returns (nil, reason) on failure, reason one of:
--   "no-data", "no-song", "read-failed", "no-offset-tag", "write-failed"
ResyncSongOffsetFromMean = function(player)
	local pn = ToEnumShortString(player)

	-- 1. signed mean of this stage's judgment offsets (seconds; positive = late)
	local stage = SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1]
	local sequential_offsets = stage and stage.sequential_offsets
	if not sequential_offsets then return nil, "no-data" end

	local sum, count = 0, 0
	for t in ivalues(sequential_offsets) do
		local val = t[2]
		if val ~= "Miss" then
			sum = sum + val
			count = count + 1
		end
	end
	if count == 0 then return nil, "no-data" end
	local mean_seconds = sum / count

	-- 2. locate the song file the engine actually loaded (.ssc has priority)
	local song = GAMESTATE:GetCurrentSong()
	if not song then return nil, "no-song" end
	local path = song:GetSongFilePath()
	if not path or path == "" then return nil, "no-song" end

	-- 3. read the whole file (read mode = 1), same idiom as SL-ChartParser.lua
	local rf = RageFileUtil.CreateRageFile()
	local contents
	if rf:Open(path, 1) then
		contents = rf:Read()
	end
	rf:destroy()
	if not contents or contents == "" then return nil, "read-failed" end

	-- 4. parse the first (song-level) #OFFSET tag
	local old_str = contents:match("#OFFSET:%s*(-?%d*%.?%d+)%s*;")
	if not old_str then return nil, "no-offset-tag" end
	local old = tonumber(old_str)
	if not old then return nil, "no-offset-tag" end

	-- 5. compensate the bias
	local new = old - mean_seconds
	local replacement = ("#OFFSET:%.6f;"):format(new)

	-- 6. replace only the first #OFFSET occurrence. Use a function replacement so
	-- the formatted value is inserted literally (no gsub %-escaping surprises).
	local new_contents = contents:gsub("#OFFSET:%s*-?%d*%.?%d+%s*;", function() return replacement end, 1)

	-- 7. write it back (write mode = 2 truncates on open)
	local wf = RageFileUtil.CreateRageFile()
	local wrote = false
	if wf:Open(path, 2) then
		wf:Write(new_contents)
		wf:Flush()
		wrote = true
	end
	wf:destroy()
	if not wrote then return nil, "write-failed" end

	-- 8. reload the song so the new sync is live in memory
	song:ReloadFromSongDir()

	-- 9. result
	local delta = new - old
	return {
		old = old,
		new = new,
		delta = delta,
		mean_ms = mean_seconds * 1000,
		direction = (delta < 0) and "later" or "earlier",
	}
end
```

- [ ] **Step 2: Static review**

Confirm, reading only the added function:
1. The mean loops `sequential_offsets`, skips `"Miss"`, averages `t[2]` (seconds) → matches Pane 5's `avg_offset` (positive = late).
2. `new = old - mean_seconds` (NOT `+`). This is the approved "compensate the bias" direction.
3. The file is read fully (mode `1`) and the RageFile destroyed **before** reopening in write mode (mode `2`) — write mode truncates on open, so reading first is mandatory.
4. `gsub(..., <function>, 1)` replaces exactly one occurrence (the first / song-level `#OFFSET`).
5. Every early-return path returns `nil, "<reason>"` and leaves the file untouched (the write only happens at step 7; a failed write returns before the reload).
6. `direction` = `"later"` when `delta < 0` (offset decreased) — consistent with the engine (`delta<0` → notes later).

- [ ] **Step 3: In-game smoke check (deferred to Task 4)**

This function has no UI of its own and needs live gameplay data + a song on disk, so its true in-game test happens once the Task 4 handler can call it. For now, only the static review above gates this task. (Do not attempt to unit-test it outside the game — the harness has no Lua runner and the function depends on `GAMESTATE`, `SL`, and `RageFile`.)

- [ ] **Step 4: Leave for user to commit** (do NOT run `git commit`)

Changed file: `Scripts/SL-Helpers.lua`.

---

### Task 2: Localization strings

**Files:**
- Modify: `Languages/en.ini` (section `[ScreenEvaluation]`, after the `MaxError=...` line ~299)
- Modify: `Languages/fr.ini` (section `[ScreenEvaluation]`, after the `MaxError=...` line ~229)

**Interfaces:**
- Produces: `THEME:GetString("ScreenEvaluation", <key>)` for keys `SongResynced`, `SongResyncOffset`, `SongResyncShift`, `SongResyncEarlier`, `SongResyncLater`, `SongResyncMean`, `SongResyncNoData`, `SongResyncNoSong`, `SongResyncWriteFailed` (consumed by Task 4).

- [ ] **Step 1: Add English strings**

In `Languages/en.ini`, immediately after the line `MaxError=max error` (inside `[ScreenEvaluation]`), insert:

```ini

# --- Mean-based song resync (Ctrl+Shift+R on evaluation) ---
SongResynced=Song resynced
SongResyncOffset=Song offset %+.3f → %+.3f
SongResyncShift=Notes %.2f ms %s
SongResyncEarlier=earlier
SongResyncLater=later
SongResyncMean=(Mean %+.2f ms)
SongResyncNoData=No timing data to resync.
SongResyncNoSong=No current song to resync.
SongResyncWriteFailed=Couldn't update the song file (read-only?).
```

- [ ] **Step 2: Add French strings**

In `Languages/fr.ini`, immediately after the line `MaxError=erreur max` (inside `[ScreenEvaluation]`), insert:

```ini

# --- Resync de la chanson par la moyenne (Ctrl+Shift+R à l'évaluation) ---
SongResynced=Chanson resynchronisée
SongResyncOffset=Décalage chanson %+.3f → %+.3f
SongResyncShift=Notes %.2f ms %s
SongResyncEarlier=plus tôt
SongResyncLater=plus tard
SongResyncMean=(Moyenne %+.2f ms)
SongResyncNoData=Aucune donnée de timing pour resynchroniser.
SongResyncNoSong=Aucune chanson à resynchroniser.
SongResyncWriteFailed=Écriture du fichier impossible (lecture seule ?).
```

- [ ] **Step 3: Static review**

Confirm: both blocks are inside `[ScreenEvaluation]` (before the next `[Section]` header); the format specifiers match how Task 4 calls them — `SongResyncOffset` has two `%+.3f`, `SongResyncShift` has `%.2f` then `%s`, `SongResyncMean` has one `%+.2f`; the files stay UTF-8 (the `→`, `é`, and accented chars render, matching the existing `❌`/accented lines).

- [ ] **Step 4: Leave for user to commit** (do NOT run `git commit`)

Changed files: `Languages/en.ini`, `Languages/fr.ini`.

---

### Task 3: Shift-guard the existing Ctrl+R replay

**Files:**
- Modify: `BGAnimations/ScreenEvaluation common/Shared/RestartHandler.lua`

**Interfaces:**
- Consumes: engine input events via the existing `AddInputCallback`.
- Produces: no new interface. Behavioral change only: Ctrl+R still replays, but Ctrl+**Shift**+R no longer triggers the replay (so it is free for the resync in Task 4). Needed only in EventMode, where both callbacks are active.

- [ ] **Step 1: Replace the handler function**

Replace the `RestartHandler` function (lines 1–18) with:

```lua
local RestartHandler = function(event)
	if not event then return end

	if event.type == "InputEventType_FirstPress" then
		if event.DeviceInput.button == "DeviceButton_left ctrl" then
			holdingCtrl = true
		elseif event.DeviceInput.button == "DeviceButton_left shift"
		    or event.DeviceInput.button == "DeviceButton_right shift" then
			holdingShift = true
		elseif event.DeviceInput.button == "DeviceButton_r" then
			-- Ctrl+R replays. Ctrl+Shift+R is reserved for the mean-based resync
			-- hotkey (see Shared/ResyncHandler.lua), so don't replay when Shift is held.
			if holdingCtrl and not holdingShift then
				SM("Replaying Song")
				SCREENMAN:GetTopScreen():SetNextScreenName("ScreenGameplay"):StartTransitioningScreen("SM_GoToNextScreen")
			end
		end
	elseif event.type == "InputEventType_Release" then
		if event.DeviceInput.button == "DeviceButton_left ctrl" then
			holdingCtrl = false
		elseif event.DeviceInput.button == "DeviceButton_left shift"
		    or event.DeviceInput.button == "DeviceButton_right shift" then
			holdingShift = false
		end
	end
end
```

Leave the rest of the file (the `Def.ActorFrame{...}` with the `KeyboardFeatures`/`EventMode`/course-mode gate and `AddInputCallback(RestartHandler)`) unchanged.

- [ ] **Step 2: Static review**

Confirm: the replay trigger condition is now `holdingCtrl and not holdingShift`; shift state is tracked on both left and right shift for FirstPress and Release; no other behavior changed (still `SM("Replaying Song")` + transition). `holdingShift`, like the pre-existing `holdingCtrl`, is an implicit file-global — matches the file's existing style.

- [ ] **Step 3: In-game verification**

In EventMode with `KeyboardFeatures` on, on evaluation:
1. Press Ctrl+R → song replays (unchanged).
2. Press Ctrl+Shift+R → song does **not** replay. (Its resync effect is added in Task 4; here just confirm no replay/transition happens.)

- [ ] **Step 4: Leave for user to commit** (do NOT run `git commit`)

Changed file: `BGAnimations/ScreenEvaluation common/Shared/RestartHandler.lua`.

---

### Task 4: Resync input handler + feedback overlay, wired into evaluation

**Files:**
- Create: `BGAnimations/ScreenEvaluation common/Shared/ResyncHandler.lua`
- Modify: `BGAnimations/ScreenEvaluation common/default.lua` (add a `LoadActor` line after the RestartHandler load, ~line 52)

**Interfaces:**
- Consumes: `ResyncSongOffsetFromMean(player)` (Task 1); the localization keys (Task 2); `GAMESTATE:GetHumanPlayers()`, `ThemePrefs.Get("KeyboardFeatures")`, `GAMESTATE:IsCourseMode()`, `SCREENMAN:GetTopScreen():AddInputCallback`, `MESSAGEMAN:Broadcast`, `LoadFont`, `ThemePrefs.Get("ThemeFont")`, `_screen`, `color`, `Color.White`.
- Produces: the `SongResynced` MESSAGEMAN message (payload `{ result=<table or nil>, reason=<string or nil> }`) and the visible feedback; registered as a Shared evaluation actor.

- [ ] **Step 1: Create `Shared/ResyncHandler.lua`**

Create `BGAnimations/ScreenEvaluation common/Shared/ResyncHandler.lua` with:

```lua
-- Ctrl+Shift+R on ScreenEvaluation: resync the just-played song's #OFFSET to
-- cancel the (solo) player's systematic timing bias — their signed mean offset.
-- The math + file IO live in ResyncSongOffsetFromMean() (Scripts/SL-Helpers.lua);
-- this actor wires up the hotkey (solo only, KeyboardFeatures, not course mode)
-- and renders a brief confirmation of the old/new sync and the applied shift.

local Players = GAMESTATE:GetHumanPlayers()

-- Solo-only: the file #OFFSET is a single global value, so only allow this when
-- exactly one human player is joined; that player's mean drives the resync.
local player = (#Players == 1) and Players[1] or nil

-- modifier state for the Ctrl+Shift+R combo, plus a debounce while feedback shows
local holdingCtrl  = false
local holdingShift = false
local busy = false

local ResyncInputHandler = function(event)
	if not event or not player then return end

	if event.type == "InputEventType_FirstPress" then
		local btn = event.DeviceInput.button
		if btn == "DeviceButton_left ctrl" or btn == "DeviceButton_right ctrl" then
			holdingCtrl = true
		elseif btn == "DeviceButton_left shift" or btn == "DeviceButton_right shift" then
			holdingShift = true
		elseif btn == "DeviceButton_r" then
			if holdingCtrl and holdingShift and not busy then
				busy = true
				local result, reason = ResyncSongOffsetFromMean(player)
				MESSAGEMAN:Broadcast("SongResynced", { result=result, reason=reason })
			end
		end

	elseif event.type == "InputEventType_Release" then
		local btn = event.DeviceInput.button
		if btn == "DeviceButton_left ctrl" or btn == "DeviceButton_right ctrl" then
			holdingCtrl = false
		elseif btn == "DeviceButton_left shift" or btn == "DeviceButton_right shift" then
			holdingShift = false
		end
	end
end

local NormalFont = ThemePrefs.Get("ThemeFont") .. " Normal"
local BoldFont   = ThemePrefs.Get("ThemeFont") .. " Bold"
local ERROR_COLOR = color("#ffb266")
local LATER_COLOR = color("#89ffa2")

local t = Def.ActorFrame{
	Name="ResyncHandler",
	OnCommand=function(self)
		if player
		and ThemePrefs.Get("KeyboardFeatures")
		and not GAMESTATE:IsCourseMode() then
			SCREENMAN:GetTopScreen():AddInputCallback(ResyncInputHandler)
		end
	end,
}

-- feedback overlay: hidden until a resync is attempted, then shown ~4s and faded
t[#t+1] = Def.ActorFrame{
	Name="ResyncFeedback",
	InitCommand=function(self)
		self:xy(_screen.cx, _screen.cy):draworder(200):visible(false):diffusealpha(0)
	end,
	SongResyncedMessageCommand=function(self)
		self:stoptweening():visible(true):diffusealpha(0)
		self:linear(0.15):diffusealpha(1):sleep(4):linear(0.3):diffusealpha(0):queuecommand("Hide")
	end,
	HideCommand=function(self)
		self:visible(false)
		busy = false
	end,

	-- backdrop
	Def.Quad{
		InitCommand=function(self) self:zoomto(380, 104):diffuse(color("#101519")):diffusealpha(0.92) end
	},

	-- title / error line
	LoadFont(BoldFont)..{
		InitCommand=function(self) self:y(-32):zoom(0.55) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				self:settext(THEME:GetString("ScreenEvaluation", "SongResynced")):diffuse(Color.White)
			else
				local key = (params.reason == "no-data" and "SongResyncNoData")
						or (params.reason == "no-song" and "SongResyncNoSong")
						or "SongResyncWriteFailed"
				self:settext(THEME:GetString("ScreenEvaluation", key)):diffuse(ERROR_COLOR)
			end
		end,
	},

	-- old -> new offset line
	LoadFont(NormalFont)..{
		InitCommand=function(self) self:y(-8):zoom(0.5) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				self:settext(THEME:GetString("ScreenEvaluation", "SongResyncOffset"):format(params.result.old, params.result.new))
			else
				self:settext("")
			end
		end,
	},

	-- applied shift line (colored: green = later, orange = earlier)
	LoadFont(NormalFont)..{
		InitCommand=function(self) self:y(14):zoom(0.6) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				local word = THEME:GetString("ScreenEvaluation",
					params.result.direction == "later" and "SongResyncLater" or "SongResyncEarlier")
				self:settext(THEME:GetString("ScreenEvaluation", "SongResyncShift"):format(math.abs(params.result.delta * 1000), word))
				self:diffuse(params.result.direction == "later" and LATER_COLOR or ERROR_COLOR)
			else
				self:settext("")
			end
		end,
	},

	-- mean recap line
	LoadFont(NormalFont)..{
		InitCommand=function(self) self:y(34):zoom(0.42):diffuse(color("#888888")) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				self:settext(THEME:GetString("ScreenEvaluation", "SongResyncMean"):format(params.result.mean_ms))
			else
				self:settext("")
			end
		end,
	},
}

return t
```

- [ ] **Step 2: Wire it into `default.lua`**

In `BGAnimations/ScreenEvaluation common/default.lua`, immediately after the RestartHandler load block (the two lines: the `-- code for immediately retrying...` comment and `t[#t+1] = LoadActor("./Shared/RestartHandler.lua")`, ~line 52), add:

```lua

	-- code for resyncing the song's #OFFSET to the solo player's mean timing (Ctrl+Shift+R)
	t[#t+1] = LoadActor("./Shared/ResyncHandler.lua")
```

- [ ] **Step 3: Static review**

Confirm:
1. `player` is set only when `#Players == 1`; both `OnCommand` (registration) and `ResyncInputHandler` early-return when `player` is nil → no-op in 2P/0P.
2. The trigger requires `holdingCtrl and holdingShift and not busy`; `busy` is set true on trigger and reset to false in `HideCommand` (~4.3s later) — prevents accidental double-shift.
3. Every text child guards on `params.result` and blanks itself on failure; the title child maps `reason` → a localized key.
4. Format calls match Task 2's specifiers: `SongResyncOffset` gets `(old, new)`, `SongResyncShift` gets `(abs(delta*1000), word)`, `SongResyncMean` gets `(mean_ms)`.
5. `default.lua` now loads `./Shared/ResyncHandler.lua` (Shared actors are loaded explicitly here, not auto-scanned).
6. Balanced braces / `end`s; the file returns the `t` ActorFrame.

- [ ] **Step 4: In-game verification**

1. **Solo**, `KeyboardFeatures` on. Play a song hitting deliberately **late** (mean shows positive on Pane 5). On evaluation press **Ctrl+Shift+R**:
   - Overlay appears ~4s: "Song resynced", `old → new` with **new < old**, "Notes X.XX ms **later**" (green), "(Mean +X.XX ms)".
   - Open the song's `.ssc`/`.sm` on disk → the first `#OFFSET:` equals `old − mean` (to ~6 decimals).
2. Play hitting deliberately **early** (mean negative) → resync shows **new > old**, "Notes X.XX ms **earlier**" (orange).
3. Ctrl+R immediately after a resync (EventMode) → replays with the new sync; the replay's mean should trend toward 0.
4. Ctrl+R alone (no Shift) → plain replay, no resync overlay.
5. **Two players** joined → Ctrl+Shift+R does nothing (no overlay).
6. Course mode → no overlay (disabled).
7. Play that is all misses / no taps → overlay shows "No timing data to resync."; the file is unchanged.
8. Song in a read-only location → overlay shows "Couldn't update the song file (read-only?)"; no crash.
9. **Reload sanity:** after a resync on the eval screen, confirm the rest of the evaluation screen still behaves (no errors in `Logs/log.txt` from `ReloadFromSongDir`). If the reload causes problems, apply the fallback below.

**Fallback (only if Step 4.9 shows reload problems):** in `Scripts/SL-Helpers.lua`, remove the `song:ReloadFromSongDir()` call (step 8 of the function). The disk write still persists; the new sync then applies the next time the song is loaded (e.g. game restart / song rescan) rather than immediately.

- [ ] **Step 5: Leave for user to commit** (do NOT run `git commit`)

Changed files: `BGAnimations/ScreenEvaluation common/Shared/ResyncHandler.lua` (new), `BGAnimations/ScreenEvaluation common/default.lua`.

---

## Self-Review notes (author)

- **Spec coverage:**
  - Hotkey Ctrl+Shift+R on evaluation, solo, gated → Task 4 (handler + gate) + Task 3 (shift-guard so Ctrl+R replay doesn't collide).
  - `new = old − Mean` compensate-the-bias direction, correct signs → Task 1 (Global Constraints spell out the verified convention).
  - Read current offset from the loaded file, rewrite first `#OFFSET`, reload → Task 1.
  - Feedback text with old sync, new sync, applied shift (notes earlier/later) + mean → Task 4 + Task 2 strings.
  - Error/edge handling (no data, no song, read/write fail, read-only pack) → Task 1 returns reasons, Task 4 renders them.
  - Reload risk + fallback → Task 4 Step 4.9 + Fallback note.
- **Placeholder scan:** none — all code, paths, and strings are concrete.
- **Type consistency:** `ResyncSongOffsetFromMean` returns `{old,new,delta,mean_ms,direction}` in Task 1 and Task 4 reads exactly those fields; message name `SongResynced` and payload `{result,reason}` consistent between broadcast (Task 4 handler) and the `SongResyncedMessageCommand` consumers; localization keys used in Task 4 all defined in Task 2.
- **No-commit constraint** honored: every task ends with "Leave for user to commit".
```