local player = ...
local pn = ToEnumShortString(player)

-- Records this stage's EX score into the profile so the song wheel can show it later, on
-- any chart rather than only on ITL ones. See Scripts/SL-Helpers-ExScores.lua for why it
-- has to be captured here and cannot be recomputed from the saved HighScore.
--
-- Unlike ItlFile.lua next door this is not gated on an event being active -- the whole
-- point is that it applies everywhere. It is gated on the things that make an EX score
-- meaningless or unstorable:
--
--   * Casual has no EX scoring at all (CalculateExScore returns 0 outright in that mode).
--   * Course mode has no single chart to key on, and the wheel never shows a course row's
--     EX anyway.
--   * A guest has no profile directory to write to.
--
-- A failed run records nothing: an EX score only counts on a chart you actually passed.
-- That is the rule ITL already applies to its own entries -- the `not stats:GetFailed()`
-- guard in UpdateItlData, which is why an ITL entry IS a pass -- and the rule the wheel's
-- ITG column follows too. The three displays therefore agree: nothing on that row claims
-- anything about a run you did not finish. The check itself is in the command below, where
-- the stage stats are already to hand.
if (SL.Global.GameMode == "Casual" or
		GAMESTATE:IsCourseMode() or
		not PROFILEMAN:IsPersistentProfile(player)) then
	return
end

return Def.Actor{
	OnCommand=function(self)
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
		if pss:GetFailed() then return end

		local song = GAMESTATE:GetCurrentSong()
		local steps = GAMESTATE:GetCurrentSteps(player)
		if not song or not steps then return end

		-- Same pair every other pane on this screen uses to arrive at an EX score.
		local ex = CalculateExScore(player, GetExJudgmentCounts(player))
		if type(ex) ~= "number" or ex <= 0 then return end

		-- Written straight to disk when this run actually beat what was stored, rather than
		-- being left for SaveProfileCustom to flush later. That mirrors ITL, which writes
		-- its own file immediately from six different places for the same reason: a profile
		-- save is not guaranteed to happen before the game is closed, and a score that only
		-- lives in memory is a score the player loses.
		--
		-- SaveProfileCustom still writes it too, which costs nothing and covers the memory
		-- card case, where the profile directory can change under us between stages.
		if ExScoreRecord(player, song, steps, ex) then
			ExScoresWrite(player)
		end
	end
}
