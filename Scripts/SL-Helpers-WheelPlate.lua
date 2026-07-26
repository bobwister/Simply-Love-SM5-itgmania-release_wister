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
WheelPlate = function(w, h, c_left, c_right, inset)
	inset = inset or 0
	return Def.ActorMultiVertex{
		InitCommand=function(self)
			local v = WheelPlateVerts(w - inset*2, h - inset*2, SL_WHEEL_BEVEL, c_left, c_right)
			self:SetDrawState({Mode="DrawMode_Fan"}):SetNumVertices(#v):SetVertices(v)
			self:x(inset)
		end
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
