-- Shared geometry for the "Technique HUD" MusicWheel rows.
--
-- Every wheel row (song, course, expanded/collapsed group header) is drawn as a
-- parallelogram: the left and right edges are slanted by `bevel` px so rows read
-- as angled HUD plates rather than stacked rectangles. Quads can't do slanted
-- edges or per-vertex gradients, so these are ActorMultiVertex triangle fans.
--
-- NOTE: this Scripts file is loaded before SL_Init.lua, so it must NOT touch
-- SL.Global at load time. Callers pass colors in.

-- The slant, in pixels, applied to the left and right edges of every row.
-- TWEAK: rows are only ~32px tall, so this reads as roughly a 14 degree lean;
-- raising it past ~12 starts to look like a skew rather than a HUD chamfer.
SL_WHEEL_BEVEL = 8

-- Vertices in perimeter order. A convex quad fans correctly from v0 under
-- DrawMode_Fan, which (unlike DrawMode_Quads) has an unambiguous vertex order.
-- c_left tints the leading edge, c_right the trailing edge.
WheelPlateVerts = function(w, h, bevel, c_left, c_right)
	local top, bot = -h/2, h/2
	return {
		{{bevel,     top, 0}, c_left },
		{{w,         top, 0}, c_right},
		{{w - bevel, bot, 0}, c_right},
		{{0,         bot, 0}, c_left },
	}
end

-- Def.ActorMultiVertex rendering one plate. `inset` shrinks it on all sides so a
-- larger plate behind can show through as a hairline border.
--
-- `getcolors` is a FUNCTION returning the two colors, not the colors themselves. That is
-- deliberate: the Simply Love color can change while a screen is up -- switching profile
-- from the song wheel applies the new profile's color without rebuilding the screen -- so
-- the plate has to be able to recompute, which means it needs the recipe rather than the
-- result. Callers that captured `local accent = PlayerColor(...)` at file scope froze the
-- color at load and could never repaint.
WheelPlate = function(w, h, getcolors, inset)
	inset = inset or 0

	-- Vertex colors live inside the vertex array, so repainting means rebuilding it.
	-- A diffuse() could not do this job: the plate is a gradient between two different
	-- colors, and diffuse would flatten it to one.
	local function paint(self)
		local c_left, c_right = getcolors()
		local v = WheelPlateVerts(w - inset*2, h - inset*2, SL_WHEEL_BEVEL, c_left, c_right)
		self:SetDrawState({Mode="DrawMode_Fan"}):SetNumVertices(#v):SetVertices(v)
	end

	return Def.ActorMultiVertex{
		InitCommand=function(self)
			paint(self)
			self:x(inset)
		end,
		ColorSelectedMessageCommand=paint,
	}
end

-- Scale a color's RGB toward black and set an explicit alpha, returning a plain
-- {r,g,b,a} table. Used all over the Technique HUD to derive dark card and row
-- tints from a source color (the player's Simply Love color, a difficulty color)
-- while keeping that color's hue as the signal.
DimColor = function(c, mult, alpha)
	return { c[1]*mult, c[2]*mult, c[3]*mult, alpha }
end

-- Shared look for the ScreenSelectMusic left-column panels (song description,
-- density graph, pattern info, difficulty grid). They all used #1e282f at alpha
-- 0.5 under the Technique visual style, which let the background video read
-- straight through and washed the whole column out. One ink and one alpha here
-- so the column reads as a set of solid cards.
-- TWEAK: lower HUD_PANEL_ALPHA to let more of the background through.
HUD_PANEL_COLOR = color("#0E1519")
HUD_PANEL_ALPHA = 0.90

-- Applies the panel look to a Quad, replacing a per-file diffuse/alpha pair.
HUDPanel = function(actor)
	return actor:diffuse(HUD_PANEL_COLOR):diffusealpha(HUD_PANEL_ALPHA)
end

-- Two-step text scale for those panels: one near-white for the values you actually
-- read, one desaturated slate for the labels that name them. Both started life as
-- literals repeated across the pane display, the step artist box and the footer;
-- panels styled from here on should use these so the column stays consistent.
HUD_TEXT  = color("#E8F1F4")
HUD_LABEL = color("#7C939E")

-- Corner brackets marking out a panel as a HUD card: a two-armed L at the top
-- left and another at the bottom right, the same device the mockup used.
--
-- Add the result as a SIBLING of the panel quad it decorates, passing the same
-- local offset that quad uses, so the brackets inherit every transform the
-- parent frame applies -- several of these frames animate on entry (the step
-- artist box slides up 30px, panes bounce in), and absolute screen coordinates
-- would drift away from the panel they belong to.
--
--   w, h    : the panel's size
--   dx, dy  : the panel's local position, if it isn't at the frame origin
--   corners : "both" (default), "tl" for the top-left bracket alone -- what
--             panels whose bottom edge fades out want -- or "br" for panels that
--             already carry a full-width rule along their top edge
--
-- TWEAK: HUD_CARD_ARM is how far the brackets reach along each edge, and
-- HUD_CARD_ALPHA how strongly they read.
HUD_CARD_ARM = 10
HUD_CARD_THICKNESS = 2
HUD_CARD_ALPHA = 0.65

HUDCardDecor = function(w, h, dx, dy, corners)
	dx, dy = dx or 0, dy or 0
	local hw, hh = w/2, h/2
	local arm, thick = HUD_CARD_ARM, HUD_CARD_THICKNESS

	local af = Def.ActorFrame{
		InitCommand=function(self) self:xy(dx, dy) end
	}

	-- Read at paint time rather than captured, so a profile switch from the song wheel
	-- repaints the brackets instead of leaving them on the previous profile's color.
	-- Every panel in the theme that calls HUDCardDecor inherits this.
	local function paint(self)
		self:diffuse(DimColor(PlayerColor(PLAYER_1), 1.0, HUD_CARD_ALPHA))
	end

	-- One L, anchored at (cx,cy) growing inward by (sx,sy) which are each +/-1.
	local function bracket(cx, cy, sx, sy)
		af[#af+1] = Def.Quad{
			InitCommand=function(self)
				self:zoomto(arm, thick):xy(cx + sx*arm/2, cy + sy*thick/2)
				paint(self)
			end,
			ColorSelectedMessageCommand=paint,
		}
		af[#af+1] = Def.Quad{
			InitCommand=function(self)
				self:zoomto(thick, arm):xy(cx + sx*thick/2, cy + sy*arm/2)
				paint(self)
			end,
			ColorSelectedMessageCommand=paint,
		}
	end

	if corners ~= "br" then
		bracket(-hw, -hh,  1,  1)
	end
	if corners ~= "tl" then
		bracket( hw,  hh, -1, -1)
	end

	return af
end
