# Evaluation Mean-Based Song Resync — Design

**Date:** 2026-07-04
**Status:** Approved (pending written-spec review)

## Goal

On `ScreenEvaluation`, let a solo player press a hotkey (**Ctrl+Shift+R**) to
rewrite the just-played song's `#OFFSET` so that the player's systematic timing
bias (the signed **Mean** offset) is cancelled out. After the change the player's
average timing lands on-beat next time. A few-seconds on-screen message confirms
the old sync, the new sync, and the applied shift (notes earlier / notes later).

This mirrors ITGmania's own built-in autosync / F11–F12 sync logic, but is driven
manually from the evaluation screen using the offsets already collected during
gameplay.

## Sign convention (authoritative)

Verified against the engine source (`AdjustSync.cpp`, `Player.cpp`,
`TimingData.cpp`, `NotesLoaderSSC.cpp`, `NotesWriterSSC.cpp`):

- The file `#OFFSET` value is stored **directly** into
  `m_fBeat0OffsetInSeconds` (no sign flip) on load, and written back directly on
  save.
- **Increasing `#OFFSET` makes notes arrive earlier** in the audio
  (`AdjustSync::GetSyncChangeTextSong`: `delta > 0` → "notes earlier";
  `delta < 0` → "notes later").
- The Lua-visible `TapNoteOffset` (and therefore Simply Love's Pane 5 "Mean
  Offset" `avg_offset`) is **positive = late**, negative = early
  (`Player.cpp` broadcasts `-fNoteOffset`; `Early = fTapNoteOffset < 0`).
- The engine autosync applies `m_fBeat0OffsetInSeconds += mean(fNoteOffset)`
  where `fNoteOffset` is positive for an **early** hit. In Lua/Pane-5 terms
  (`mean_ms` positive = late), that is:

  ```
  new_offset_seconds = old_offset_seconds - (mean_ms / 1000)
  ```

**Worked examples (the behavior we implement):**

| Player Mean        | Offset change | New vs old | Message      |
|--------------------|---------------|------------|--------------|
| +5.00 ms (late)    | −5.00 ms      | offset ↓   | notes later  |
| −3.04 ms (early)   | +3.04 ms      | offset ↑   | notes earlier|

(Confirmed by the user: this is the "compensate the bias" direction — a late
player gets the notes moved later so their next play is on-time. The user's
original numeric example had the `#OFFSET` sign inverted; the direction here is
the corrected one they approved.)

## Decisions (from brainstorming)

- **Direction:** correction / compensate the bias (`new = old − Mean`). ✅
- **Hotkey:** **Ctrl+Shift+R** for resync. **Ctrl+R stays the "Replay Song"
  hotkey** (unchanged behavior). ✅
- **Player scope:** **solo only** — active only when exactly one human player is
  joined (the file `#OFFSET` is a single global value; avoids P1/P2 conflict). ✅
- **Effect:** **write to disk + `ReloadFromSongDir()`** so an immediate Ctrl+R
  replay already uses the new sync, and the change takes effect in-memory for the
  rest of the session. ✅
- **Gating:** requires `ThemePrefs.Get("KeyboardFeatures")`, **not** course mode,
  solo. **Not** gated behind EventMode (calibration is useful outside event
  mode).

## Architecture & components

### Component A — `Scripts/SL-Helpers.lua` : `ResyncSongOffsetFromMean(player)`

Pure-ish logic unit (no actors), so the math and file I/O are isolated and
reviewable.

**Input:** `player` (a PlayerNumber).

**Behavior:**
1. Read `SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].sequential_offsets`.
   Compute the signed mean of all non-`"Miss"` entries (`entry[2]`), in seconds.
   Positive = late.
   - If there are **0** valid taps → return `nil, "no-data"`.
2. `song = GAMESTATE:GetCurrentSong()`; `path = song:GetSongFilePath()`.
   - If no song / no path → return `nil, "no-song"`.
3. Read the file with a read-mode `RageFile` (mode `1`), same idiom as
   `SL-ChartParser.lua`. On open failure → return `nil, "read-failed"`.
4. Find the **first** `#OFFSET:%s*(-?%d*%.?%d+)%s*;` occurrence, parse `old`
   (seconds). If not found → return `nil, "no-offset-tag"`.
5. `new = old - mean_seconds` (mean in seconds).
6. Replace **only that first** `#OFFSET:...;` with
   `("#OFFSET:%.6f;"):format(new)`.
7. Write the modified contents back with a write-mode `RageFile` (mode `2`,
   truncates), `Write` + `Flush` + `Close`/`destroy`. On write failure → return
   `nil, "write-failed"` (leave the in-memory song untouched).
8. `song:ReloadFromSongDir()` so the change is live in memory.
9. Return a result table:
   ```lua
   {
     old   = old,                       -- seconds
     new   = new,                       -- seconds
     delta = new - old,                 -- seconds (negative = notes later)
     mean_ms = mean_seconds * 1000,     -- signed, positive = late
     direction = (new - old) < 0 and "later" or "earlier",
   }
   ```

**Notes:**
- Read the whole file into memory first (read mode), close, *then* reopen in
  write mode — write mode truncates on open.
- Only the first `#OFFSET:` is touched: it is the song-level tag (it precedes any
  `#NOTEDATA`/`#NOTES`). Per-steps `#OFFSET` (split timing) is intentionally not
  handled (see Limitations).

### Component B — `BGAnimations/ScreenEvaluation common/Shared/ResyncHandler.lua`

A `Def.ActorFrame` (modeled on `RestartHandler.lua`) that:

1. **Registers an input callback** in `OnCommand`, only if gating passes
   (`KeyboardFeatures`, not course mode, exactly one human player).
2. **Input handler** tracks held modifiers and fires on the `r` first-press:
   - Track `holdingCtrl` and `holdingShift` on FirstPress/Release of
     `DeviceButton_left ctrl` / `DeviceButton_right ctrl` and
     `DeviceButton_left shift` / `DeviceButton_right shift`.
   - On `DeviceButton_r` FirstPress with `holdingCtrl and holdingShift`:
     call `ResyncSongOffsetFromMean(player)` (the single joined human player) and
     `MESSAGEMAN:Broadcast("SongResynced", result_or_error)`.
   - Debounce: ignore repeat triggers while a resync message is already showing
     (or simply allow re-fire; re-running is idempotent-ish but shifts again —
     so **debounce**: block re-fire until the feedback finishes, to avoid
     accidental double-shift).
3. **Feedback overlay**: a high-`draworder` centered container that listens for
   `SongResyncedMessageCommand`:
   - Success: show title + `old → new` (seconds, 3 decimals) + `Notes X.XX ms
     later/earlier` (green for later, orange for earlier) + `(Mean ±X.XX ms)`.
   - Failure: show a short reason line (no data / read-only file / no song).
   - Appears, holds ~4 s, fades out (~0.3 s). Re-trigger `finishtweening()` +
     restarts.

### Component C — `RestartHandler.lua` (minimal change)

The existing replay handler fires on `holdingCtrl` + `r`. Because our resync uses
Ctrl+**Shift**+R, in EventMode (where both callbacks are active) pressing
Ctrl+Shift+R would also fire the replay. Guard it:

- Track `holdingShift` as well, and require `holdingCtrl and not holdingShift`
  for the replay trigger.

This keeps Ctrl+R = replay, and makes Ctrl+Shift+R = resync only.

### Component D — Localization (`Languages/en.ini`, `Languages/fr.ini`)

Under `[ScreenEvaluation]` (or a dedicated section), add strings for:
- Title (e.g. `SongResynced` = "Song resynced").
- The value line template, mirroring the engine:
  `SongResyncOffset` = `"Song offset %+.3f → %+.3f"`.
- The shift line: reuse "earlier"/"later" words; e.g.
  `SongResyncShift` = `"Notes %.2f ms %s"`.
- The mean recap: `SongResyncMean` = `"(Mean %+.2f ms)"`.
- Failure lines: `SongResyncNoData`, `SongResyncWriteFailed`, `SongResyncNoSong`.

French mirrors these (e.g. "Chanson resynchronisée", "Décalage chanson %+.3f →
%+.3f", "Notes %.2f ms %s", with plus tôt / plus tard for earlier/later).

## Data flow

```
Ctrl+Shift+R (FirstPress 'r' while ctrl+shift held, solo, KeyboardFeatures, not course)
  -> ResyncSongOffsetFromMean(player)
       reads sequential_offsets -> signed mean (s)
       reads song file (#OFFSET) -> old
       new = old - mean
       rewrites #OFFSET in file, Flush/Close
       song:ReloadFromSongDir()
       returns {old,new,delta,mean_ms,direction}
  -> MESSAGEMAN:Broadcast("SongResynced", result)
  -> feedback overlay shows old/new/shift/mean for ~4s
```

## Error handling

| Case                         | Behavior                                            |
|------------------------------|-----------------------------------------------------|
| 0 valid taps (all miss)      | No file change; show "no data" message.             |
| No current song / no path    | No-op; show "no song" message.                      |
| File open (read) fails       | No-op; show write/read-failed message.              |
| `#OFFSET` tag not found      | No-op; show a failure message.                      |
| File open (write) fails      | In-memory song untouched; show "write failed".      |
| Read-only pack / mounted zip | Write fails gracefully → "write failed".            |

## Limitations (accepted)

- **Split timing**: only the song-level (first) `#OFFSET` is edited. Per-steps
  `#OFFSET` (rare) is not adjusted.
- **`ReloadFromSongDir` mid-evaluation**: the engine never reloads during
  evaluation on its own. Must be verified in-game that no evaluation actor breaks
  after the reload. **Fallback if it misbehaves:** drop the reload and keep the
  disk write only (the new sync then applies the next time songs are (re)loaded /
  the game restarts). This fallback is a one-line change and does not alter the
  file-writing logic.
- **No undo in-theme**: re-running the resync shifts again relative to the new
  offset. (A subsequent play's Mean should be ~0 if the correction worked, so a
  second resync would be near-zero.) Debounce prevents accidental double-fire in
  one message window.

## Testing / verification (manual, in-game)

No automated test framework (Lua theme, engine not launchable here). Verify:

1. Solo play a song, land a clear early or late bias, press Ctrl+Shift+R on
   evaluation → message shows plausible old→new and correct direction
   (late → "notes later"; early → "notes earlier"); the `.ssc`/`.sm` `#OFFSET`
   is updated on disk by `new = old − Mean`.
2. Ctrl+R immediately after resync (EventMode) replays with the new sync
   (Mean should trend toward 0 on the replay).
3. Ctrl+R alone (no shift) still triggers a plain replay, not a resync.
4. Two players joined → Ctrl+Shift+R does nothing (solo-only).
5. Course mode → disabled.
6. All-miss / no-data play → "no data" message, file unchanged.
7. Read-only song location → "write failed" message, no crash.

## Constraints

- **Do NOT `git commit`** — leave changes in the working tree; the user commits
  themselves.
- No engine changes; Lua theme only.
