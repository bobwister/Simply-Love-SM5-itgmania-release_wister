-- this difficulty grid doesn't support CourseMode
-- CourseContentsList.lua should be used instead
if GAMESTATE:IsCourseMode() then return end
-- ----------------------------------------------

-- The difficulty picker, as a horizontal card at the foot of the left column.
--
-- It used to be a 32x152 vertical strip pinned to the right of the column, outside
-- the stack the other panels form. It is now five chips across a card the full width
-- of the column, filling the dead space that sat between the density graph and the
-- stats pane. Geometry comes from Scripts/SL-Layout-SelectMusic.lua so the card lines
-- up with the banner above it.
--
-- Up/Down still change difficulty -- only the display turned sideways. Cursor.lua
-- points down at the active chip instead of right at the active row.

local GetStepsToDisplay = LoadActor("./StepsToDisplay.lua")

-- The four actors making up one chip, in draw order. They are flat siblings of Grid
-- rather than one nested frame per chip because Cursor.lua reaches into Grid by child
-- name to work out where to park itself, so the shape has to stay flat.
local CHIP_PARTS = { "MeterBackground_", "MeterTick_", "Meter_", "MeterLabel_" }

-- TWEAK: the ladder look.
--
-- CELL_TINT is how much of the chip's difficulty color is kept behind the number --
-- the point being that the five chips read as a colored ladder at a glance. Keep it
-- low: the number sits on top in that same hue at full strength and needs contrast.
--
-- The tick is the same device the density graph uses: a dim fill carries the hue, a
-- bright edge along the chip's bottom makes it read.
local CELL_TINT  = 0.30
local CELL_ALPHA = 0.95
local CELL_EMPTY = color("#101619")
local CELL_EMPTY_ALPHA = ThemePrefs.Get("RainbowMode") and 0.9 or 1

local TICK_HEIGHT = 2
local TICK_ALPHA  = 0.9

local t = Def.ActorFrame{
	Name="StepsDisplayList",
	InitCommand=function(self) self:xy(SSM.column.cx, SSM.cards.steps.cy) end,

	OnCommand=function(self)                           self:queuecommand("RedrawStepsDisplay") end,
	CurrentSongChangedMessageCommand=function(self)    self:queuecommand("RedrawStepsDisplay") end,
	CurrentStepsP1ChangedMessageCommand=function(self) self:queuecommand("RedrawStepsDisplay") end,
	CurrentStepsP2ChangedMessageCommand=function(self) self:queuecommand("RedrawStepsDisplay") end,

	RedrawStepsDisplayCommand=function(self)

		local song = GAMESTATE:GetCurrentSong()

		if song then
			local steps = SongUtil.GetPlayableSteps( song )

			if steps then
				local StepsToDisplay = GetStepsToDisplay(steps)
				local grid = self:GetChild("Grid")

				for i=1,5 do
					if StepsToDisplay[i] then
						-- if this particular song has a stepchart for this chip, update the
						-- Meter and coloring appropriately
						local params = {
							Meter      = StepsToDisplay[i]:GetMeter(),
							Difficulty = StepsToDisplay[i]:GetDifficulty(),
						}
						for part in ivalues(CHIP_PARTS) do
							grid:GetChild(part..i):playcommand("Set", params)
						end
					else
						-- otherwise, blank the meter and hide this chip's coloring
						for part in ivalues(CHIP_PARTS) do
							grid:GetChild(part..i):playcommand("Unset")
						end
					end
				end
			end
		else
			-- playcommand recurses into descendants, so this reaches every chip part
			self:playcommand("Unset")
		end
	end,
}

t[#t+1] = Def.Quad{
	Name="Background",
	InitCommand=function(self)
		HUDPanel(self):zoomto(SSM.column.w, SSM.cards.steps.h)
		if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.9)
		end
	end
}

t[#t+1] = HUDCardDecor(SSM.column.w, SSM.cards.steps.h)

-- The selection highlight, one per player. Loaded HERE, between the card's background
-- and the chips, and nowhere else: it draws a quad slightly larger than a chip and
-- relies on the chip's own opaque background covering the middle to read as a ring.
-- Loaded from PerPlayer/default.lua as it used to be, it would have been buried under
-- this card's background quad.
for player in ivalues( PlayerNumber ) do
	t[#t+1] = LoadActor("../PerPlayer/Cursor.lua", player)
end

local Grid = Def.ActorFrame{
	Name="Grid",
	InitCommand=function(self) end,
}

for i=1, 5 do
	local chip_x = SSM_ChipX(i)

	Grid[#Grid+1] = Def.Quad{
		Name="MeterBackground_"..i,
		InitCommand=function(self)
			self:zoomto(SSM.chip.w, SSM.chip.h):x(chip_x)
			self:diffuse(CELL_EMPTY):diffusealpha(CELL_EMPTY_ALPHA)
		end,
		SetCommand=function(self, params)
			self:diffuse( DimColor(DifficultyColor(params.Difficulty), CELL_TINT, CELL_ALPHA) )
		end,
		UnsetCommand=function(self)
			self:diffuse(CELL_EMPTY):diffusealpha(CELL_EMPTY_ALPHA)
		end
	}

	Grid[#Grid+1] = Def.Quad{
		Name="MeterTick_"..i,
		InitCommand=function(self)
			self:zoomto(SSM.chip.w, TICK_HEIGHT)
			self:xy(chip_x, SSM.chip.h/2 - TICK_HEIGHT/2)
			self:visible(false)
		end,
		SetCommand=function(self, params)
			self:diffuse( DifficultyColor(params.Difficulty) ):diffusealpha(TICK_ALPHA)
			self:visible(true)
		end,
		UnsetCommand=function(self) self:visible(false) end
	}

	Grid[#Grid+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Name="Meter_"..i,
		InitCommand=function(self)
			-- lifted off centre to leave room for the difficulty name underneath
			self:xy(chip_x, -5):zoom(0.55)
		end,
		SetCommand=function(self, params)
			self:diffuse( DifficultyColor(params.Difficulty) )
			self:settext(params.Meter)
		end,
		UnsetCommand=function(self) self:settext(""):diffuse(color("#182025")) end,
	}

	-- The difficulty's name, which the vertical strip had no room for. Comes from the
	-- [Difficulty] section of the language files, so Challenge reads as "Expert" here
	-- the way it does everywhere else in Simply Love.
	Grid[#Grid+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="MeterLabel_"..i,
		InitCommand=function(self)
			-- 7, not 8: the chip lost 4px of height when the stats pane moved into the
			-- column above it, and the tick along its bottom edge now starts at y=11.
			self:xy(chip_x, 7):zoom(0.38):maxwidth((SSM.chip.w - 4) / 0.38)
			self:diffuse(HUD_LABEL)
		end,
		SetCommand=function(self, params)
			self:settext( THEME:GetString("Difficulty", ToEnumShortString(params.Difficulty)):upper() )
		end,
		UnsetCommand=function(self) self:settext("") end,
	}
end

t[#t+1] = Grid

return t
