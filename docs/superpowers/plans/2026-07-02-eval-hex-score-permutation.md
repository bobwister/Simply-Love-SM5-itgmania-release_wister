# Evaluation H. EX Score Permutation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the evaluation screen's FA+ pane (Pane2, ITG mode), when the "10ms Blue Window" (`SmallerWhite`) option is on, make the EX percentage score alternate — in sync with the existing 15ms/10ms judgment-count marquee — between EX (blue, 15ms) and H. EX (magenta, 10ms); and rename the displayed "S. EX" score label to "H. EX" everywhere.

**Architecture:** Reuse the existing per-actor 2s `Marquee` pattern already used for the judgment counts and the "15ms"/"10ms" text on Pane2. Add the same pattern to the three actors that show the EX score/label: the big center score (`Percentage.lua`), the breakdown score (`JudgmentNumbers.lua`), and the EX/ITG text label (`JudgmentLabels.lua`). The H. EX value is `CalculateSuperExScore(player, GetExJudgmentCounts(player))`, which already exists. Only display labels are renamed; the internal `SuperEXScore` value and `CalculateSuperExScore` function name are unchanged.

**Tech Stack:** Lua 5.1 (ITGmania theme scripting). No build step, no test runner. Verification is manual, in-game.

## Global Constraints

- The magenta H. EX color is `color("#FF4FCB")` (same as gameplay); the EX blue is the existing `SL.JudgmentColors[SL.Global.GameMode][1]` used by these files (in ITG mode = `#21CCE8`).
- The H. EX value on evaluation is `CalculateSuperExScore(player, GetExJudgmentCounts(player))`; the EX value is the existing `CalculateExScore(player, GetExJudgmentCounts(player))`.
- The permutation only runs when `SL[pn].ActiveModifiers.SmallerWhite` is true (same gate as the existing count/label marquees). When it's off, behavior is unchanged (EX stays blue, no marquee).
- New marquees must be phase-matched to the existing ones: each uses a `show10` boolean initialized to `true` so the FIRST displayed frame is the 10ms/H. EX variant, matching the existing count marquee (`display10=true`) and label marquee (`show15=false`, shows "10ms" first).
- Marquee cadence is `self:sleep(2):queuecommand("Marquee")` — identical to the existing marquees.
- Displayed label rename: "S. EX" → "H. EX" (full name "High EX Score"). Internal identifiers (`SuperEXScore`, `CalculateSuperExScore`) are NOT renamed.
- Scope is Pane2 (ITG-mode FA+ pane) only. FA+ GameMode (Pane1), EvaluationSummary, and other EX displays are out of scope.
- **Per user instruction: do NOT `git commit`.** Where a task says "leave for user", leave the changes in the working tree; the user commits themselves.
- No automated test framework (Lua theme, engine not launchable here). Each task ends with a static block-balance review plus concrete in-game manual verification.

---

### Task 1: Rename displayed "S. EX" score label to "H. EX"

**Files:**
- Modify: `Languages/en.ini` (line 1143 label; line 994 explanation)
- Modify: `Languages/fr.ini` (line 1121 label; line 984 explanation)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the localization key `SuperEXScore` now renders as "H. EX Score" (en) / "Score H. EX" (fr). No code depends on the display text.

- [ ] **Step 1: Rename the English choice label** (`Languages/en.ini`)

Find (line 1143):

```
SuperEXScore=S. EX Score
```

Replace with:

```
SuperEXScore=H. EX Score
```

- [ ] **Step 2: Update the English explanation** (`Languages/en.ini`)

Find (line 994):

```
PrimaryScoreDisplay=Main score shown during gameplay: ITG (white), EX (blue, 15ms), or Super EX (magenta, 10ms).
```

Replace with:

```
PrimaryScoreDisplay=Main score shown during gameplay: ITG (white), EX (blue, 15ms), or High EX (magenta, 10ms).
```

- [ ] **Step 3: Rename the French choice label** (`Languages/fr.ini`)

Find (line 1121):

```
SuperEXScore=Score S. EX
```

Replace with:

```
SuperEXScore=Score H. EX
```

- [ ] **Step 4: Update the French explanation** (`Languages/fr.ini`)

Find (line 984):

```
PrimaryScoreDisplay=Score principal affiché en jeu : ITG (blanc), EX (bleu, 15ms) ou Super EX (magenta, 10ms).
```

Replace with:

```
PrimaryScoreDisplay=Score principal affiché en jeu : ITG (blanc), EX (bleu, 15ms) ou High EX (magenta, 10ms).
```

- [ ] **Step 5: Static review**

Grep `en.ini` and `fr.ini` for `S. EX` and `Super EX` — there should be no remaining matches in either file. Confirm `SuperEXScore=` still exists (renamed, not deleted) in both.

- [ ] **Step 6: Leave for user to commit** (do not run `git commit`)

Changed files: `Languages/en.ini`, `Languages/fr.ini`.

---

### Task 2: EX ⇄ H. EX permutation on evaluation Pane2

**Files:**
- Modify (full rewrite): `BGAnimations/ScreenEvaluation common/Panes/Pane2/Percentage.lua`
- Modify: `BGAnimations/ScreenEvaluation common/Panes/Pane2/JudgmentNumbers.lua` (add file-scope locals near top; replace the `index == 1` score block, ~lines 104-132)
- Modify: `BGAnimations/ScreenEvaluation common/Panes/Pane2/JudgmentLabels.lua` (add file-scope locals near top; replace the `index == 1` label block, ~lines 130-154)

**Interfaces:**
- Consumes: globals `CalculateExScore(player, counts)`, `CalculateSuperExScore(player, counts)`, `GetExJudgmentCounts(player)`, `FormatPercentScore`, `color`, `SL.JudgmentColors`, `SL[pn].ActiveModifiers.ShowEXScore`, `SL[pn].ActiveModifiers.SmallerWhite`.
- Produces: no new interfaces (leaf UI actors).

- [ ] **Step 1: Rewrite `Percentage.lua`** (the big center score)

Overwrite `BGAnimations/ScreenEvaluation common/Panes/Pane2/Percentage.lua` with:

```lua
local player, controller = unpack(...)
local pn = ToEnumShortString(player)
local mods = SL[pn].ActiveModifiers

local HEX_COLOR = color("#FF4FCB")
local show10 = true

local percent = nil
local diffuse = nil
-- when EX is the displayed score, precompute both EX and H.EX for the SmallerWhite marquee
local ex_percent, hex_percent
local marquee = false

if mods.ShowEXScore then
	local counts = GetExJudgmentCounts(player)
	ex_percent  = CalculateExScore(player, counts)
	hex_percent = CalculateSuperExScore(player, counts)
	percent = ex_percent
	diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
	marquee = mods.SmallerWhite or false
else
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	local PercentDP = stats:GetPercentDancePoints()
	percent = FormatPercentScore(PercentDP):gsub("%%", "")
	-- Format the Percentage string, removing the % symbol
	percent = tonumber(percent)
	diffuse = Color.White
end

return Def.ActorFrame{
	Name="PercentageContainer"..ToEnumShortString(player),
	OnCommand=function(self)
		self:y( _screen.cy-26 )
	end,

	-- dark background quad behind player percent score
	Def.Quad{
		InitCommand=function(self)
			self:diffuse(color("#101519")):zoomto(158.5, SL.Global.GameMode == "Casual" and 60 or 88)
			self:horizalign(controller==PLAYER_1 and left or right)
			self:x(150 * (controller == PLAYER_1 and -1 or 1))
			if SL.Global.GameMode ~= "Casual" then
				self:y(14)
			end
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0.5)
			end
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Name="Percent",
		Text=("%.2f"):format(percent),
		InitCommand=function(self)
			self:horizalign(right):zoom(1.3)
			self:x( (controller == PLAYER_1 and 1.5 or 141))
			self:diffuse(diffuse)
		end,
		BeginCommand=function(self)
			if marquee then self:playcommand("Marquee") end
		end,
		MarqueeCommand=function(self)
			if show10 then
				self:settext(("%.2f"):format(hex_percent)):diffuse(HEX_COLOR)
				show10 = false
			else
				self:settext(("%.2f"):format(ex_percent)):diffuse(diffuse)
				show10 = true
			end
			self:sleep(2):queuecommand("Marquee")
		end,
	}
}
```

- [ ] **Step 2: Add file-scope marquee locals to `JudgmentNumbers.lua`**

Find (lines 3-4):

```lua
local pn = ToEnumShortString(player)
local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
```

Replace with:

```lua
local pn = ToEnumShortString(player)
local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)

-- H.EX (10ms) score marquee support (see the index==1 block below)
local HEX_COLOR = color("#FF4FCB")
local show10 = true
```

- [ ] **Step 3: Replace the score block in `JudgmentNumbers.lua`**

Find (starts at the line after `for index, RCType in ipairs(RadarCategories.Types) do`, through the closing `end` of the `if index == 1 then` block — lines 105-132):

```lua
	-- Swap to displaying ITG score if we're showing EX score in gameplay.
	local percent = nil
	if SL[pn].ActiveModifiers.ShowEXScore then
		local PercentDP = pss:GetPercentDancePoints()
		percent = FormatPercentScore(PercentDP):gsub("%%", "")
		-- Format the Percentage string, removing the % symbol
		percent = tonumber(percent)
	else
		percent = CalculateExScore(player, counts)
	end

	if index == 1 then
		t[#t+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
			Name="Percent",
			Text=("%.2f"):format(percent),
			InitCommand=function(self)
				self:horizalign(right):zoom(1.3)
				self:x( ((controller == PLAYER_1) and -114) or 286 )
				self:y(47)
				
				if SL[pn].ActiveModifiers.ShowEXScore then
					self:diffuse(Color.White)
				else
					self:diffuse( SL.JudgmentColors[SL.Global.GameMode][1] )
				end
			end
		}
	end
```

Replace with:

```lua
	-- Swap to displaying ITG score if we're showing EX score in gameplay.
	if index == 1 then
		local score_percent, score_diffuse
		local ex_percent, hex_percent, marquee

		if SL[pn].ActiveModifiers.ShowEXScore then
			-- EX is the big score (Percentage.lua); show ITG% here.
			local PercentDP = pss:GetPercentDancePoints()
			-- note: gsub returns (string, count); assign to a local first so
			-- tonumber() doesn't receive the count as its (out-of-range) base arg
			local PercentStr = FormatPercentScore(PercentDP):gsub("%%", "")
			score_percent = tonumber(PercentStr)
			score_diffuse = Color.White
		else
			-- EX is the breakdown score; support EX <-> H.EX marquee when SmallerWhite is on.
			ex_percent  = CalculateExScore(player, counts)
			hex_percent = CalculateSuperExScore(player, counts)
			score_percent = ex_percent
			score_diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
			marquee = SL[pn].ActiveModifiers.SmallerWhite or false
		end

		t[#t+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
			Name="Percent",
			Text=("%.2f"):format(score_percent),
			InitCommand=function(self)
				self:horizalign(right):zoom(1.3)
				self:x( ((controller == PLAYER_1) and -114) or 286 )
				self:y(47)
				self:diffuse(score_diffuse)
			end,
			BeginCommand=function(self)
				if marquee then self:playcommand("Marquee") end
			end,
			MarqueeCommand=function(self)
				if show10 then
					self:settext(("%.2f"):format(hex_percent)):diffuse(HEX_COLOR)
					show10 = false
				else
					self:settext(("%.2f"):format(ex_percent)):diffuse(score_diffuse)
					show10 = true
				end
				self:sleep(2):queuecommand("Marquee")
			end,
		}
	end
```

(The holds/mines/rolls code that follows this block — the `local possible = counts["total"..RCType]` line onward — is unchanged. Note the old top-of-loop `local percent` computation is intentionally moved inside `if index == 1`, since the holds/mines code never used `percent`.)

- [ ] **Step 4: Add file-scope marquee locals to `JudgmentLabels.lua`**

Find (lines 3-4):

```lua
local pn = ToEnumShortString(player)
local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
```

Replace with:

```lua
local pn = ToEnumShortString(player)
local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)

-- H.EX (10ms) label marquee support (see the index==1 block below)
local HEX_COLOR = color("#FF4FCB")
local show10 = true
```

- [ ] **Step 5: Replace the EX/ITG label block in `JudgmentLabels.lua`**

Find (lines 130-154, the `if index == 1 then ... end` inside `for index, label in ipairs(RadarCategories) do`):

```lua
	if index == 1 then
		text = nil
		if SL[pn].ActiveModifiers.ShowEXScore then
			text = "ITG"
		else
			text = "EX"
		end


		t[#t+1] = LoadFont(ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small"
							or ThemePrefs.Get("ThemeFont") == "Mega" and "Mega/_mega font"
							or ThemePrefs.Get("ThemeFont") == "Unprofessional" and "Unprofessional/_unprofessional small")..{
			Text=text,
			InitCommand=function(self) self:zoom(0.5):horizalign(right) end,
			BeginCommand=function(self)
				self:x( (controller == PLAYER_1 and -160) or 90 )
				self:y(38)

				if SL[pn].ActiveModifiers.ShowEXScore then
					self:diffuse(Color.White)
				else
					self:diffuse( SL.JudgmentColors[SL.Global.GameMode][1] )
				end
			end
		}
	end
```

Replace with:

```lua
	if index == 1 then
		local text, label_diffuse, marquee
		if SL[pn].ActiveModifiers.ShowEXScore then
			text = "ITG"
			label_diffuse = Color.White
		else
			text = "EX"
			label_diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
			marquee = SL[pn].ActiveModifiers.SmallerWhite or false
		end

		t[#t+1] = LoadFont(ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small"
							or ThemePrefs.Get("ThemeFont") == "Mega" and "Mega/_mega font"
							or ThemePrefs.Get("ThemeFont") == "Unprofessional" and "Unprofessional/_unprofessional small")..{
			Text=text,
			InitCommand=function(self) self:zoom(0.5):horizalign(right) end,
			BeginCommand=function(self)
				self:x( (controller == PLAYER_1 and -160) or 90 )
				self:y(38)
				self:diffuse(label_diffuse)
				if marquee then self:playcommand("Marquee") end
			end,
			MarqueeCommand=function(self)
				if show10 then
					self:settext("H. EX"):diffuse(HEX_COLOR)
					show10 = false
				else
					self:settext("EX"):diffuse(label_diffuse)
					show10 = true
				end
				self:sleep(2):queuecommand("Marquee")
			end
		}
	end
```

- [ ] **Step 6: Static review**

- `Percentage.lua`: returns a single `Def.ActorFrame` with a `Def.Quad` and a `Percent` BitmapText; the `else` (ITG%) branch leaves `ex_percent`/`hex_percent` nil and `marquee=false`, so `MarqueeCommand` never fires there (no nil-format). Balanced `end`s.
- `JudgmentNumbers.lua`: `HEX_COLOR`/`show10` declared once at file scope; the `index == 1` block is balanced; the holds/mines code after it is intact; `counts` (from line 28) is in scope where `CalculateExScore`/`CalculateSuperExScore` are called.
- `JudgmentLabels.lua`: `HEX_COLOR`/`show10` declared once at file scope; `text` is now `local`; the label block is balanced; the separate "10ms"/"15ms" marquee (earlier in the file) is untouched.
- All three: the H. EX color literal is `color("#FF4FCB")`; the marquee uses `show10` starting `true` and `self:sleep(2):queuecommand("Marquee")`.

- [ ] **Step 7: In-game verification**

Prerequisite: ITG GameMode, "Display FA+ Pane" on, and "10ms Blue Window" (SmallerWhite) ON in the FA+ Options row.

1. Set Primary/Secondary so that EX is shown (e.g. Primary = EX Score) → this makes `ShowEXScore` true. Play a song with a mix of ≤10ms and 10–15ms Fantastics, reach evaluation.
   - Expected: the big center score alternates every ~2s between an EX value (blue) and an H. EX value (magenta), in sync with the judgment-count 15ms/10ms marquee and the "15ms"/"10ms" text. The H. EX value is ≤ the EX value.
2. Set Primary = ITG Score (so `ShowEXScore` false, but keep SmallerWhite on and — if needed to still show EX — set Secondary = EX Score). Reach evaluation.
   - Expected: the big center score shows ITG% (white, static); the breakdown score + its "EX" label alternate EX (blue) ⇄ "H. EX" (magenta) every ~2s.
3. Turn "10ms Blue Window" (SmallerWhite) OFF, play, reach evaluation.
   - Expected: no marquee anywhere — the EX score stays blue and static, exactly as before this change (regression check).
4. Confirm the options menu now shows the score choice labelled "H. EX Score" (not "S. EX Score").

- [ ] **Step 8: Leave for user to commit** (do not run `git commit`)

Changed files: `BGAnimations/ScreenEvaluation common/Panes/Pane2/Percentage.lua`, `.../JudgmentNumbers.lua`, `.../JudgmentLabels.lua`.

---

## Self-Review notes (author)

- **Spec coverage:** rename S.EX→H.EX everywhere (Task 1 + verification step 4); EX⇄H.EX permutation "wherever EX blue appears" — big score `Percentage.lua` (Task 2 Step 1) and breakdown score `JudgmentNumbers.lua` (Step 3); "EX"⇄"H. EX" text label toggle `JudgmentLabels.lua` (Step 5); synced 2s cadence + phase (Global Constraints + `show10=true`); gated on `SmallerWhite`; magenta `#FF4FCB`. All covered.
- **Type consistency:** `show10` and `HEX_COLOR` named identically across all three files; `CalculateSuperExScore(player, counts)` matches the Task-1 signature from the prior feature; `SL.JudgmentColors[SL.Global.GameMode][1]` is the exact blue expression already used in each file.
- **No literal rename of internals:** `SuperEXScore`/`CalculateSuperExScore` deliberately unchanged; only displayed strings renamed.
