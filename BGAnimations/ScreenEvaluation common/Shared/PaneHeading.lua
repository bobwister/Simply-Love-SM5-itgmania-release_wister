-- Names the pane being shown, and its position in the series, on the screen's own title
-- line: "Evaluation : EX Score (5 / 6)".
--
-- ScreenEvaluation cycles through up to ten panes with nothing on screen naming any of
-- them or saying how many there are. You learn the order by memorising it, and a pane that
-- happens to be empty is indistinguishable from having reached the end.
--
-- This draws nothing itself. An earlier version put a heading above each pane column, but
-- there is no free band there -- it landed on the difficulty and grade block above. The
-- title line already exists, already sits alone on its row, and is exactly where you look
-- to find out what a screen is showing.
--
-- The count goes to the header's quieter suffix slot rather than into the same string,
-- which keeps it visually subordinate and, more practically, avoids AddAttribute: that
-- takes a CHARACTER offset while Lua's # returns BYTES, and pane titles are translated --
-- "Test entrées" alone would have put the attribute in the wrong place.

if SL.Global.GameMode == "Casual" then return end

-- Which side the title should describe.
--
-- In versus each side scrolls its panes independently and one line cannot name both, so
-- the title follows whichever side moved last -- that is the side the player just acted
-- on, and therefore the one they want feedback about.
-- `index` identifies WHICH pane (its position among the loaded ones, which is what names
-- the actor and resolves the title). `shown` and `total` are the numbers to PRINT, and
-- they are deliberately different: InputHandler counts only the panes the cursor will stop
-- on, so a machine with GrooveStats switched on but no network reads "1/4" rather than
-- numbering four reachable pages against nine loaded ones.
local function Announce(pn, index, shown, total)
	if EvalPaneCount(pn) == 0 then return end

	local base = THEME:GetString(SCREENMAN:GetTopScreen():GetName(), "HeaderText")

	MESSAGEMAN:Broadcast("SetHeaderText", {
		Text = ("%s : %s"):format(base, EvalPaneTitle(pn, index))
	})

	-- A lone "1 / 1" says nothing; leave the tail empty rather than pad the title with it.
	MESSAGEMAN:Broadcast("SetHeaderSuffix", {
		Text = (total and total > 1) and ("(%d / %d)"):format(shown, total) or ""
	})
end

-- Purely a listener. The opening announcement comes from InputHandler too, because only it
-- can see the panes and therefore tell a reachable page from one the cursor skips.
return Def.Actor{
	EvalPaneChangedMessageCommand=function(self, params)
		Announce("P" .. tostring(params.Controller), params.Index, params.Display, params.Total)
	end,
}
