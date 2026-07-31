-- The ScreenEvaluation pane manifest: which panes exist, in what order, and what to call
-- them.
--
-- WHY NAMES AND NOT NUMBERS. Panes used to be addressed by their position, and that
-- position was three different things at once: the folder name on disk (Panes/Pane5), the
-- actor name in the tree (Pane5_SideP1), and the value stored in SL[pn].EvalPanePrimary.
-- Merging two panes or reordering them therefore silently changed which pane a player
-- landed on, and nothing could be renamed without touching every one of those meanings.
--
-- It also carried a real bug, acknowledged in InputHandler.lua's own FIXME. Several panes
-- return nil rather than an actor -- the EX pane outside ITG mode, everything GrooveStats
-- when the service is off, TestInput without dedicated menu buttons. The loader skipped
-- those but kept naming the survivors after their ORIGINAL position, while InputHandler
-- compacted them into a gap-free list. So with any pane missing, position 5 in the list
-- and the actor named "Pane5" were different panes: the handler showed one and drove the
-- other. On a machine with GrooveStats disabled that is four holes.
--
-- Now: this file owns the order, the loader names actors by their COMPACTED position and
-- records which ids survived, and everyone else resolves an id through EvalPaneIndex().
-- Positions stay an internal detail of one screen's actor tree.
--
-- NOTE: loaded before SL_Init.lua, so nothing here may touch SL at load time.

-- `dir` is the folder under BGAnimations/ScreenEvaluation common/Panes/.
--
-- The folders keep their historical numeric names deliberately: renaming them would be a
-- large diff for no behavioural gain, and the id beside each one is what the rest of the
-- theme now uses. The two only have to agree here.
EVAL_PANE_MANIFEST = {
	{ id="ScoreITG",  dir="Pane1"  },
	{ id="ScoreEX",   dir="Pane2"  },
	{ id="Columns",   dir="Pane3"  },
	{ id="Machine",   dir="Pane4"  },
	{ id="Timing",    dir="Pane5"  },
	{ id="InputTest", dir="Pane6"  },
	{ id="Upload",    dir="Pane7"  },
	{ id="World",     dir="Pane8"  },
	{ id="RPG",       dir="Pane9"  },
	{ id="ITL",       dir="Pane10" },
}

-- Which ids actually produced actors this time round, in display order. Recorded by
-- BGAnimations/ScreenEvaluation common/Panes/default.lua as it loads them, because
-- availability cannot be predicted without loading: each pane decides for itself, from
-- conditions spread across game mode, player modifiers, preferences and service state.
-- Duplicating those tests here would be a second source of truth waiting to drift.
--
-- Kept PER SIDE, because two players do not necessarily get the same set: ShowFaPlusPane
-- is a player modifier, so in versus one side can carry the EX pane and the other not,
-- which shifts every position after it on that side alone.
EvalPaneSetOrder = function(pn, ids)
	SL.Global.EvalPaneOrder = SL.Global.EvalPaneOrder or {}
	SL.Global.EvalPaneOrder[pn] = ids
end

EvalPaneOrder = function(pn)
	local all = SL.Global.EvalPaneOrder
	return (all and all[pn]) or {}
end

EvalPaneCount = function(pn)
	return #EvalPaneOrder(pn)
end

-- Position of a pane id on one side, or nil when that pane is not on screen this time.
-- Callers holding an id must cope with nil: a player whose primary pane is the EX score
-- will not have it in Casual.
EvalPaneIndex = function(pn, id)
	if id == nil then return nil end

	for i, loaded in ipairs(EvalPaneOrder(pn)) do
		if loaded == id then return i end
	end
	return nil
end

EvalPaneIdAt = function(pn, index)
	return EvalPaneOrder(pn)[index]
end

-- The heading shown for a pane. Falls back to the raw id rather than erroring, so adding
-- a pane to the manifest without adding its string yields something readable instead of
-- taking the screen down.
EvalPaneTitle = function(pn, index)
	local id = EvalPaneIdAt(pn, index)
	if id == nil then return "" end

	local key = "PaneTitle" .. id
	if THEME:HasString("ScreenEvaluation", key) then
		return THEME:GetString("ScreenEvaluation", key)
	end
	return id
end
