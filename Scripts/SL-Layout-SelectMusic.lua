-- Geometry for the ScreenSelectMusic left column.
--
-- Banner, song description, step artist credit, density graph and difficulty picker
-- are one vertical stack of cards sharing a left edge and a width. Those numbers used
-- to be spelled out independently in each of those files as its own offset from
-- _screen.cx, which is how the density graph ended up 34px short of the banner's right
-- edge, how the difficulty picker ended up as a narrow vertical strip pinned to the
-- right of the stack rather than part of it, and how the column ended up with a 6px
-- hole in its middle.
--
-- The column's width is dictated by the banner: Banner.lua draws a 418x164 banner at a
-- zoom chosen per aspect ratio, and everything else lines up with the art.
--
-- Solo, 16:9 is what these were checked against -- this theme is single player, event
-- mode. The 2-player branches in those files still carry their own numbers.

SSM = {}

-- Banner.lua applies this to its 418x164 art, and the column takes its width from the
-- result. TWEAK: this sets the width of every card in the stack.
SSM.banner_zoom = IsUsingWideScreen() and 0.7655 or 0.75

SSM.column = {
	-- the x every card in the stack centres on
	cx = _screen.cx - (IsUsingWideScreen() and 170 or 165),
	w  = 418 * SSM.banner_zoom,
}
SSM.column.left  = SSM.column.cx - SSM.column.w/2
SSM.column.right = SSM.column.cx + SSM.column.w/2

-- Five difficulty chips across the width of the difficulty card.
--
-- TWEAK: chip height, the gap between chips, and the card's padding around them. Chip
-- width is whatever is left once the padding and the four gaps are taken out, so the
-- row spans the column exactly however wide the column is.
SSM.chip = { h = 30, gap = 6, pad = 8 }
SSM.chip.w = (SSM.column.w - 2*SSM.chip.pad - 4*SSM.chip.gap) / 5

-- Centre of chip `i` (1..5), relative to the difficulty card's own centre.
function SSM_ChipX(i)
	local inner = SSM.column.w - 2*SSM.chip.pad
	return -inner/2 + SSM.chip.w/2 + (i-1) * (SSM.chip.w + SSM.chip.gap)
end

-- -----------------------------------------------------------------------
-- The stack itself.
--
-- Screen elements that bound it: the 32px header band at the top, and the stats pane
-- that PaneDisplay.lua hangs above the 32px footer band at the bottom. Nothing in the
-- column may cross either line.
-- TWEAK: keep these two in step with footer_height and pane_height in PaneDisplay.lua.
local HEADER_HEIGHT = 32
local PANE_HEIGHT   = 60
local FOOTER_HEIGHT = 32
SSM.pane_top = _screen.h - FOOTER_HEIGHT - PANE_HEIGHT

-- Cards are laid out top down, each flush against the one above. The content is about
-- 10px shorter than the space available, and that slack belongs at the two ends -- a
-- margin under the header band and above the stats pane reads as deliberate, whereas
-- the same 10px sitting between two cards reads as a mistake.
-- TWEAK: raise TOP_GAP to push the whole stack down; the bottom margin absorbs it.
local TOP_GAP = 6

SSM.cards = {}
local stack_y = HEADER_HEIGHT + TOP_GAP

local function stack(name, h)
	SSM.cards[name] = { top = stack_y, h = h, cy = stack_y + h/2 }
	stack_y = stack_y + h
end

stack("banner",  164 * SSM.banner_zoom)
stack("song",    50)
-- the step artist card fades out towards its bottom edge, so its full height is only
-- ever reached by a chart with three credit lines
stack("artist",  60)
stack("density", 64)
stack("steps",   SSM.chip.h + 2*SSM.chip.pad)

-- What is left between the bottom of the stack and the stats pane. Negative means the
-- stack has overflowed into the pane and something above needs to give.
SSM.bottom_gap = SSM.pane_top - stack_y
