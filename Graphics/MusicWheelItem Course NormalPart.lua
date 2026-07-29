local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2

local item_width = _screen.w / 2.125
local item_height = _screen.h / num_visible_items

-- "Technique HUD" restyle: rows are smoked-glass parallelograms, with the
-- player's Simply Love color surviving only as a tint on the leading edge
-- rather than flooding the whole row. See Scripts/SL-Helpers-WheelPlate.lua.
local accent = PlayerColor(PLAYER_1)
local tint = DimColor(accent, 0.30, 0.90) -- darkened so titles stay legible
local ink  = { 0.045, 0.070, 0.085, 0.84 }
local edge = DimColor(accent, 0.55, 0.50)

local af = Def.ActorFrame{
	-- the MusicWheel is centered via metrics under [ScreenSelectMusic]; offset by a slight amount to the right here
	InitCommand=function(self) self:x(WideScale(28,33)) end,

	WheelPlate(item_width, item_height, edge, edge),
	WheelPlate(item_width, item_height, tint, ink, 1),
}


-- The per-player SRPG rate actor that used to be loaded here is gone. The rate now shares
-- the song row's event column with ITL points -- an SRPG pack shows a rate there, an ITL
-- pack shows points -- rather than being drawn separately at its own hand-tuned
-- coordinates. See Graphics/MusicWheelItem Song NormalPart/default.lua, SetRateCommand.

return af
