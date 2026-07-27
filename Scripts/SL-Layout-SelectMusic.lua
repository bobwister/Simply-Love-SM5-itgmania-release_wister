-- Geometry for the ScreenSelectMusic left column.
--
-- Banner, song description, step artist credit, density graph, stats pane, difficulty
-- picker, player card and leaderboard are one vertical stack of cards sharing a left
-- edge and a width. Those numbers used to be spelled out independently in each of those
-- files as its own offset from _screen.cx, which is how the density graph ended up 34px
-- short of the banner's right edge, how the difficulty picker ended up as a narrow
-- vertical strip pinned to the right of the stack rather than part of it, and how the
-- column ended up with a 6px hole in its middle.
--
-- Solo is what these were checked against -- this theme is single player, event mode.
-- The 2-player branches in those files still carry their own numbers.

SSM = {}

-- Column width and centre.
--
-- The 4:3 width makes the column exactly as wide as the stats pane used to be
-- (_screen.w/2 - 10 = 310) and flush with the screen's left edge. It used to be 313.5,
-- which put SSM.column.left at -1.75: the column overhung the screen edge, and the
-- player card's old strip -- sized as "whatever is left to the left of the column" --
-- came out with a NEGATIVE width and drew on top of the density graph.
-- TWEAK: this sets the width of every card in the stack.
SSM.column = {
	-- the x every card in the stack centres on
	cx = _screen.cx - (IsUsingWideScreen() and 170 or 165),
	w  = IsUsingWideScreen() and 320 or 310,
}
SSM.column.left  = SSM.column.cx - SSM.column.w/2
SSM.column.right = SSM.column.cx + SSM.column.w/2

-- Banner art, at the full column width.
--
-- 418x164 native with the aspect kept, so the height follows from the column width and
-- the art fills its card edge to edge -- it used to be scaled to a fixed 80px and pinned
-- to the left of the card, with the CD title and the music-rate readout using the free
-- space to its right. There is none any more, so the CD title went back to
-- overlapping the artwork's bottom corner (Banner.lua).
SSM.banner = { zoom = SSM.column.w / 418 }
SSM.banner.w = SSM.column.w
SSM.banner.h = 164 * SSM.banner.zoom

-- Five difficulty chips across the width of the difficulty card.
--
-- TWEAK: chip height, the gap between chips, and the card's padding around them. Chip
-- width is whatever is left once the padding and the four gaps are taken out, so the
-- row spans the column exactly however wide the column is.
SSM.chip = { h = 26, gap = 6, pad = 6 }
SSM.chip.w = (SSM.column.w - 2*SSM.chip.pad - 4*SSM.chip.gap) / 5

-- Centre of chip `i` (1..5), relative to the difficulty card's own centre.
function SSM_ChipX(i)
	local inner = SSM.column.w - 2*SSM.chip.pad
	return -inner/2 + SSM.chip.w/2 + (i-1) * (SSM.chip.w + SSM.chip.gap)
end

-- -----------------------------------------------------------------------
-- The stack itself.
--
-- Screen elements that bound it: the 32px header band at the top and the 32px footer
-- band at the bottom. Nothing in the column may cross either line. The stats pane used
-- to sit between them as a separate full-height-of-the-screen fixture; it is a card in
-- this stack now, directly above the difficulty picker.
-- TWEAK: keep FOOTER_HEIGHT in step with ./Graphics/_footer.lua.
local HEADER_HEIGHT = 32
local FOOTER_HEIGHT = 32
local TOP_GAP    = 3
local BOTTOM_GAP = 0

-- Fixed card heights.
-- TWEAK: raising any of these takes the space out of the density graph, which absorbs
-- whatever the others leave over.
local SONG_H   = 30   -- two rows: artist, then BPM / NPS / eBPM / length
local ARTIST_H = 44   -- three credit lines at zoom 0.55, plus the card's top margin
local STATS_H  = 50   -- three rows of chart counts, technical counts and high scores
local BOTTOM_H = 80   -- five 16px leaderboard rows

SSM.cards = {}
local stack_y = HEADER_HEIGHT + TOP_GAP

local function stack(name, h)
	SSM.cards[name] = { top = stack_y, h = h, cy = stack_y + h/2 }
	stack_y = stack_y + h
end

-- The density graph is the one card whose height is purely a matter of how much
-- silhouette you get to look at, so it takes the slack. This is also what keeps the
-- stack inside the footer line as the banner's height follows the column width across
-- aspect ratios: 52px of graph in 4:3, 48px in 16:9 -- of which the breakdown caption
-- strip along its bottom edge takes 17.
--
-- Hitting the floor below means the fixed heights no longer fit and the stack would
-- cross into the footer -- take the difference out of one of them rather than here.
local steps_h = SSM.chip.h + 2*SSM.chip.pad
local fixed_h = SSM.banner.h + SONG_H + ARTIST_H + STATS_H + steps_h + BOTTOM_H
local density_h = math.max(24, (_screen.h - FOOTER_HEIGHT - BOTTOM_GAP) - stack_y - fixed_h)

stack("banner",  SSM.banner.h)
stack("song",    SONG_H)
stack("artist",  ARTIST_H)
stack("density", density_h)
stack("stats",   STATS_H)
stack("steps",   steps_h)
stack("bottom",  BOTTOM_H)

-- -----------------------------------------------------------------------
-- The bottom card is split into two side by side: the player card on the left, the
-- GrooveStats / RPG / ITL leaderboard on the right.
--
-- Neither fits the full column height on its own once the banner takes its full width,
-- and stacking them would cross the footer by ~75px. The leaderboard needs the width
-- (five rank/name/score rows), the player card needs less, so it gets the smaller half.
-- TWEAK: PLAYERCARD_W trades the two against each other.
local PLAYERCARD_W = 126
-- Flush, like every join in the vertical stack. A 2px gap still read as a hole, because
-- the leaderboard's hairline border only reaches back into one of those two pixels; at 0
-- the border lands on the player card's edge and the two panels simply meet.
local SPLIT_GAP    = 0

SSM.playercard = { w = PLAYERCARD_W, h = SSM.cards.bottom.h }
SSM.playercard.cx = SSM.column.left + SSM.playercard.w/2

SSM.scorebox = { w = SSM.column.w - PLAYERCARD_W - SPLIT_GAP, h = SSM.cards.bottom.h }
SSM.scorebox.cx = SSM.column.right - SSM.scorebox.w/2

-- Which of the two leaderboards owns SSM.scorebox.
--
-- The GrooveStats box (BGAnimations/.../PerPlayer/Scorebox.lua) takes it when it can, and
-- the local machine board (BGAnimations/.../LocalLeaderboard.lua) fills the card when it
-- can't -- which is most of the time on a home cabinet, since the GrooveStats box needs
-- an API key on the profile and an actual connection. Both files gate on this, so they
-- can never claim the card at once, and neither can leave it empty.
--
-- Decided once, at screen load, which is all the GrooveStats box does too: it returns
-- outright when this is false, so it cannot come back mid-screen either.
function SSM_GrooveStatsBoxActive(player)
	if GAMESTATE:IsCourseMode() then return false end
	if ThemePrefs.Get("MusicWheelGS") ~= "Scorebox" then return false end
	if not IsServiceAllowed(SL.GrooveStats.GetScores) then return false end
	return SL[ ToEnumShortString(player) ].ApiKey ~= ""
end
