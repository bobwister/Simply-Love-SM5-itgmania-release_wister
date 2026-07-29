-- Which score goes in which slot on ScreenEvaluation's Pane 2, and how it is labelled.
--
-- The player has already said what they want, in Player Options: Primary Score Display and
-- Secondary Score Display. Pane 2 obeys those two directly -- the big score is the primary,
-- the smaller breakdown score is the secondary -- so the pane shows the same pair of
-- numbers, the same way round, as the gameplay HUD did. The mapping is deliberately the
-- same one BGAnimations/ScreenGameplay underlay/PerPlayer/Score.lua uses, so the two
-- screens cannot end up disagreeing about what "EX" means or what color it is.
--
-- This replaces two older behaviours:
--
--   * The big score was EX whenever ShowEXScore was set and ITG otherwise, with whichever
--     lost pushed into the breakdown line. That ignored the player's actual choice, and
--     could not express "ITG in both slots", "no secondary at all", or Super EX anywhere.
--
--   * The EX slot alternated between EX and H. EX every two seconds whenever the 10ms
--     window was on. That is gone on purpose, and not merely because of the 10/15 split: a
--     figure that silently changes what it measures while you are reading it cannot be
--     compared against anything, and cannot be screenshotted honestly. Wanting the 10ms
--     number is now said plainly, by choosing SuperEXScore in whichever slot you want it.
--
-- NOTE: this Scripts file is loaded before SL_Init.lua, so nothing here may touch SL at
-- load time -- which is why the colors are built inside ScoreDisplayColor rather than in a
-- table up here. Every function below runs long after Lua init, from an actor's command.

-- The score type in one slot, as one of the option rows' own values: "ITGScore",
-- "EXScore", "SuperEXScore", or (secondary only) "None".
--
-- The fallbacks match the defaults in PrimaryScore/SecondaryScore in
-- Scripts/SL-PlayerOptions.lua, so a profile that has never touched either row keeps
-- behaving as it did: ITG big, nothing small.
ScoreDisplayType = function(player, slot)
	local mods = SL[ ToEnumShortString(player) ].ActiveModifiers
	if slot == "secondary" then return mods.SecondaryScore or "None" end
	return mods.PrimaryScore or "ITGScore"
end

ScoreDisplayLabel = function(score_type)
	if score_type == "EXScore"      then return "EX"    end
	if score_type == "SuperEXScore" then return "H. EX" end
	return "ITG"
end

ScoreDisplayColor = function(score_type)
	if score_type == "EXScore"      then return SL.JudgmentColors["FA+"][1] end
	if score_type == "SuperEXScore" then return color("#FF4FCB")            end
	return Color.White
end

-- The figure itself as a number, or nil when the slot is "None" (or set to something
-- unrecognised, which a hand-edited profile can manage).
--
-- `counts` must be the table from GetExJudgmentCounts(player): both EX flavours need it,
-- and Super EX needs that exact table because CalculateSuperExScore reads its W010/W110
-- keys to remap them onto the stricter window.
ScoreDisplayPercent = function(player, score_type, counts)
	if score_type == "EXScore" then
		return CalculateExScore(player, counts)

	elseif score_type == "SuperEXScore" then
		return CalculateSuperExScore(player, counts)

	elseif score_type == "ITGScore" then
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
		-- Routed through FormatPercentScore so this matches the rounding the rest of the
		-- theme shows, rather than formatting GetPercentDancePoints directly.
		--
		-- Assigned to a local first because gsub returns TWO values (string, count): passing
		-- it straight to tonumber would hand the count over as an out-of-range base.
		local str = FormatPercentScore( pss:GetPercentDancePoints() ):gsub("%%", "")
		return tonumber(str)
	end

	return nil
end
