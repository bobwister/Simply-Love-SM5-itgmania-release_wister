local player, controller = unpack(...)
local pn = ToEnumShortString(player)
local mods = SL[pn].ActiveModifiers

-- The big score is whatever the player chose as Primary Score Display, full stop. There is
-- no EX <-> H. EX marquee any more; see Scripts/SL-Helpers-ScoreDisplay.lua for the mapping
-- and for why the alternation was removed.
local counts      = GetExJudgmentCounts(player)
local score_type  = ScoreDisplayType(player, "primary")
local percent     = ScoreDisplayPercent(player, score_type, counts) or 0
local diffuse     = ScoreDisplayColor(score_type)
local score_label = ScoreDisplayLabel(score_type)

-- Layout of the pair. Both are right-aligned: the type label ends at LABEL_X, the number
-- ends at NUMBER_X and grows leftwards into the gap between them.
-- TWEAK: these two anchors are the horizontal position of the label and of the number.
local LABEL_X  = (controller == PLAYER_1) and -95 or 45
local NUMBER_X = (controller == PLAYER_1) and 1.5 or 141
local NUMBER_ZOOM = 0.8 * 1.3 * 1.1
local LABEL_GAP = 6

-- The number is capped so it can never run back over its own label.
--
-- It has to be capped rather than merely sized to fit: in _eurostile outline (which
-- "Common Bold" redirects to) a digit advances 19 units and the point 10, so "100.00" is
-- ~105 units = ~120px at this zoom, against the ~96px between the two anchors. A maxed ITG
-- score therefore printed straight through the "ITG" beside it, while a typical two-digit
-- EX score fit and hid the problem -- which is exactly why this only showed up with ITG as
-- the primary score.
--
-- maxwidth caps the UNZOOMED width, hence the division: on-screen width is
-- min(rawWidth, maxWidth) * zoom.
local NUMBER_MAXWIDTH = (NUMBER_X - LABEL_X - LABEL_GAP) / NUMBER_ZOOM

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

	-- score type label ("ITG" / "EX" / "H. EX") to the LEFT of the big score.
	-- Uses the same font/color scheme as the secondary label in JudgmentLabels.lua.
	LoadFont(ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small"
			or ThemePrefs.Get("ThemeFont") == "Mega" and "Mega/_mega font"
			or ThemePrefs.Get("ThemeFont") == "Unprofessional" and "Unprofessional/_unprofessional small")..{
		Name="ScoreTypeLabel",
		Text=score_label,
		InitCommand=function(self)
			self:horizalign(right):zoom(0.5)
			self:x( LABEL_X )
			self:diffuse(diffuse)
		end,
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Name="Percent",
		Text=("%.2f"):format(percent),
		InitCommand=function(self)
			-- Matches the secondary score's effective size (JudgmentNumbers.lua: zoom 1.3
			-- inside its own 0.8-zoom parent frame = 1.04), + 10%.
			self:horizalign(right):zoom(NUMBER_ZOOM)
			self:x( NUMBER_X )
			self:maxwidth( NUMBER_MAXWIDTH )
			self:diffuse(diffuse)
		end,
	}
}
