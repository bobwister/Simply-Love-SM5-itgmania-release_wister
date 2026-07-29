local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2

local item_width = _screen.w / 2.125
local item_height = _screen.h / num_visible_items

-- "Technique HUD" restyle: rows are smoked-glass parallelograms, with the
-- player's Simply Love color surviving only as a tint on the leading edge
-- rather than flooding the whole row. See Scripts/SL-Helpers-WheelPlate.lua.
-- Derived inside functions rather than captured in locals: WheelPlate re-runs these on
-- ColorSelected so the rows repaint when the Simply Love color changes without a screen
-- reload, which is what a profile switch from the song wheel does.
local ink = { 0.045, 0.070, 0.085, 0.84 }

local function edge_colors()
	local edge = DimColor(PlayerColor(PLAYER_1), 0.55, 0.50)
	return edge, edge
end

local function face_colors()
	-- darkened so titles stay legible
	return DimColor(PlayerColor(PLAYER_1), 0.30, 0.90), ink
end

local af = Def.ActorFrame{
	-- the MusicWheel is centered via metrics under [ScreenSelectMusic]; offset by a slight amount to the right here
	InitCommand=function(self) self:x(WideScale(28,33)) end,

	WheelPlate(item_width, item_height, edge_colors),
	WheelPlate(item_width, item_height, face_colors, 1),
}


-- The per-player SRPG rate actor that used to be loaded here is gone. The rate now shares
-- the song row's event column with ITL points -- an SRPG pack shows a rate there, an ITL
-- pack shows points -- rather than being drawn separately at its own hand-tuned
-- coordinates. See Graphics/MusicWheelItem Song NormalPart/default.lua, SetRateCommand.

return af
