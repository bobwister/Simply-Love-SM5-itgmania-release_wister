# SelectMusic Options Countdown + Fast Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the post-song-select "Press Start for Options" window, add a shrink-to-center countdown gauge showing the time left, and make pressing Start open Player Options near-immediately (removing the artificial ~1s delay).

**Architecture:** All in the screen-out transition actor `BGAnimations/ScreenSelectMusic out.lua`. The engine plays `ShowPressStartForOptions` when the window opens and `ShowEnteringOptions` when Start is pressed, then schedules the screen change from `GetTweenTimeLeft()`. We drive a gauge Quad off those commands, and on `ShowEnteringOptions` we stop the gauge's long tween (and drop the prompt's `sleep(1)` animation) so `GetTweenTimeLeft()` falls to ~0 and options open right away.

**Tech Stack:** Lua 5.1 (ITGmania theme scripting). No build step, no test runner. Verification is manual, in-game.

## Global Constraints

- Single file changed: `BGAnimations/ScreenSelectMusic out.lua`. No engine changes.
- Gauge duration = the real window length, read dynamically: `tonumber(THEME:GetMetric("ScreenSelectMusic", "ShowOptionsMessageSeconds")) or 1.5` (fallback default is 1.5s).
- Gauge style: a full-width bar whose fill shrinks toward the center (via `zoomtowidth(px)` tween 300→0) over the window duration, over a dim static track. Positioned below the centered "Press Start for Options" prompt. (Use `zoomtowidth`, not `zoomx`: a Quad's `zoomto` makes `zoomx` == pixel width, so `zoomx(1)` would collapse it to 1px.) On `ShowEnteringOptions` the fill's tween is stopped so it doesn't linger.
- The "Press Start for Options" text is KEPT (shown on `ShowPressStartForOptions`).
- On `ShowEnteringOptions` (any player pressed Start — already an engine-level "any Start" trigger): stop the gauge's long tween and quick-fade the prompt+gauge (~0.1s, NO `sleep`). This is what makes entry near-immediate; the engine comment at ScreenSelectMusic.cpp:598 explicitly expects the theme to short-circuit these animations.
- Positions/sizes/colors are estimates marked with `-- TWEAK` comments for later adjustment.
- **Per user instruction: do NOT `git commit`.** Leave changes in the working tree.
- No automated test framework (Lua theme, engine not launchable here). The task ends with a static review plus concrete in-game manual verification.

---

### Task 1: Countdown gauge + fast options entry in the SelectMusic out transition

**Files:**
- Modify (full rewrite): `BGAnimations/ScreenSelectMusic out.lua`

**Interfaces:**
- Consumes: engine-broadcast commands `ShowPressStartForOptions` and `ShowEnteringOptions` (played by `ScreenSelectMusic.cpp`); globals `THEME:GetMetric`, `THEME:GetString`, `LoadFont`, `color`, `_screen`, `ThemePrefs`.
- Produces: no interfaces consumed elsewhere (leaf transition actor).

- [ ] **Step 1: Replace the file contents**

Overwrite `BGAnimations/ScreenSelectMusic out.lua` with:

```lua
-- Screen-out transition for ScreenSelectMusic.
-- Shows the "Press Start for Options" prompt plus a shrink-to-center countdown
-- gauge for the (engine-controlled) ShowOptionsMessageSeconds window during
-- which a Start press opens Player Options. Pressing Start plays
-- ShowEnteringOptions, which stops the gauge's long tween so the engine's
-- GetTweenTimeLeft()-based scheduling lets options open near-immediately.

return Def.ActorFrame{
	InitCommand=function(self) self:draworder(200) end,

	Def.Quad{
		InitCommand=function(self) self:diffuse(0,0,0,0):FullScreen():cropbottom(1):fadebottom(0.5) end,
		OffCommand=function(self) self:linear(0.3):cropbottom(-0.5):diffusealpha(1) end
	},

	-- "Press Start for Options" prompt (kept). On Start, fade out quickly with
	-- no sleep so the engine's GetTweenTimeLeft() stays small (near-immediate entry).
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Text=THEME:GetString("ScreenSelectMusic", "Press Start for Options"),
		InitCommand=function(self) self:visible(false):Center():zoom(1.0) end,
		ShowPressStartForOptionsCommand=function(self) self:visible(true) end,
		ShowEnteringOptionsCommand=function(self) self:stoptweening():linear(0.1):diffusealpha(0) end,
	},

	-- shrink-to-center countdown gauge for the options window
	Def.ActorFrame{
		Name="OptionsCountdown",
		InitCommand=function(self)
			-- TWEAK: vertical position of the gauge, below the centered prompt
			self:xy(_screen.cx, _screen.cy + 28):visible(false)
		end,
		ShowPressStartForOptionsCommand=function(self)
			local dur = tonumber(THEME:GetMetric("ScreenSelectMusic", "ShowOptionsMessageSeconds")) or 1.5
			self:visible(true):diffusealpha(1)
			-- animate width via zoomtowidth (a Quad's zoomto sets zoomx to the pixel
			-- width, so zoomx(1) would collapse it to 1px; zoomtowidth is the correct idiom)
			self:GetChild("Fill"):finishtweening():zoomtowidth(300):linear(dur):zoomtowidth(0)
		end,
		ShowEnteringOptionsCommand=function(self)
			-- stop the long gauge tween so GetTweenTimeLeft() drops and options open fast
			self:GetChild("Fill"):stoptweening()
			self:stoptweening():linear(0.1):diffusealpha(0)
		end,

		Def.Quad{
			Name="Track",
			-- TWEAK: gauge size/color (dim static background track)
			InitCommand=function(self) self:zoomto(300, 8):diffuse(color("#ffffff")):diffusealpha(0.25) end
		},
		Def.Quad{
			Name="Fill",
			-- TWEAK: gauge size/color (bright fill that shrinks toward center)
			InitCommand=function(self) self:zoomto(300, 8):diffuse(color("#ffffff")) end
		},
	},
}
```

- [ ] **Step 2: Static review**

Confirm: the file returns one `Def.ActorFrame` with (a) the black wipe Quad unchanged, (b) the prompt BitmapText whose `ShowEnteringOptionsCommand` has NO `sleep` and no `NewText` chain, and (c) the `OptionsCountdown` ActorFrame with a `Track` and a `Fill` Quad. Verify `ShowEnteringOptionsCommand` on the gauge calls `self:GetChild("Fill"):stoptweening()` before fading. Balanced braces/`end`s.

- [ ] **Step 3: In-game verification**

1. On ScreenSelectMusic, pick a song and press Start once to confirm it.
   - Expected: the "Press Start for Options" prompt appears with a white bar below it that shrinks from full width toward its center over ~1.5s. If you do nothing, the bar empties and the game proceeds to gameplay.
2. Confirm a song, then press Start again during the window.
   - Expected: Player Options opens near-immediately (just a brief wipe) — no ~1s "Entering Options…" wait. The gauge stops/fades at once.
3. Two players joined: confirm a song, either player presses Start during the window.
   - Expected: same near-immediate options entry (any single Start triggers it).
4. Let the window expire several times without pressing Start.
   - Expected: consistent behavior; the gauge always animates over the same ~1.5s and gameplay starts when it empties.

- [ ] **Step 4: Leave for user to commit** (do not run `git commit`)

Changed file: `BGAnimations/ScreenSelectMusic out.lua`.

---

## Self-Review notes (author)

- **Spec coverage:** countdown gauge shrinking to center (Step 1, `OptionsCountdown` frame, `zoomx` 1→0); duration = real window via `ShowOptionsMessageSeconds` metric; prompt text kept; near-immediate entry by removing the prompt's `sleep(1)` AND stopping the gauge's long tween on `ShowEnteringOptions` (both required so `GetTweenTimeLeft()` collapses). All covered.
- **Key correctness point:** the gauge's `linear(dur)` tween would otherwise keep `GetTweenTimeLeft()` high and re-introduce the delay on Start — hence the explicit `Fill:stoptweening()` in `ShowEnteringOptionsCommand`.
- **No placeholders**; positions/colors are intentionally tweakable and marked.
