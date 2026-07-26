-- the difficulty picker and per-player cursors don't support CourseMode
-- CourseContentsList.lua should be used instead
if GAMESTATE:IsCourseMode() then return end
-- ----------------------------------------------

-- Highlight ring around the selected difficulty chip.
--
-- This used to be a bouncing arrow parked just outside the card. Once the picker
-- turned horizontal (see StepsDisplayList/Grid.lua) the only place left for an arrow
-- was above the card, where it overlapped the density panel -- the card's top edge is
-- at 340 and the density panel ends at 334, so anything standing off the card at all
-- pokes into it. A ring costs no space outside the card.
--
-- It is loaded by StepsDisplayList/Grid.lua, as a child of the picker's own frame
-- sitting between the card background and the chips -- NOT from PerPlayer/default.lua
-- where the arrow used to live, since everything there draws under the whole card.
-- That position is what makes the trick work: a quad a little larger than a chip reads
-- as a border around it once the chip's own opaque background covers the middle.
--
-- Coordinates below are therefore local to the card, whose centre is the origin.

local player = ...
local pn = ToEnumShortString(player)

local GetStepsToDisplay = LoadActor("../StepsDisplayList/StepsToDisplay.lua")

local RowIndex = 1

-- TWEAK: how far the ring and its halo stand off the chip's edge, in px.
local RING_PAD = 2
local HALO_PAD = 7

local RING_ALPHA = 0.95
local HALO_ALPHA_LOW  = 0.06
local HALO_ALPHA_HIGH = 0.22

local FAVORITE_COLOR = color("#ffc0cb")

local af = Def.ActorFrame{
	Name="Cursor"..pn,

	InitCommand=function(self)
		self:visible( GAMESTATE:IsHumanPlayer(player) )
		self:x( SSM_ChipX(1) )
	end,

	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == player then self:queuecommand("Set") end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then self:visible(false) end
	end,

	OnCommand=function(self) self:queuecommand("Set") end,
	CurrentSongChangedMessageCommand=function(self) self:queuecommand("Set") end,
	["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self) self:queuecommand("Set") end,

	SetCommand=function(self)
		local song = GAMESTATE:GetCurrentSong()

		-- On a group row there is no chart, so the chips are blank -- ringing one of
		-- them would be pointing at nothing. The old arrow stayed put through this.
		self:visible( GAMESTATE:IsHumanPlayer(player) and song ~= nil )
		if not song then return end

		local playable_steps = SongUtil.GetPlayableSteps( song )
		local current_steps = GAMESTATE:GetCurrentSteps(player)

		-- the ring carries the favourite marker the arrow used to
		local tint = FindInTable(song, SL[pn].Favorites) and FAVORITE_COLOR or PlayerColor(player)
		self:playcommand("Tint", {Color=tint})

		for i,chart in pairs( GetStepsToDisplay(playable_steps) ) do
			if chart == current_steps then
				RowIndex = i
				break
			end
		end

		-- keep within reasonable limits because Edit charts are a thing
		RowIndex = clamp(RowIndex, 1, 5)

		-- Chip centres come from Scripts/SL-Layout-SelectMusic.lua, the same table
		-- Grid.lua lays the chips out from, so the ring cannot drift off them.
		self:stoptweening():linear(0.1)
		self:x( SSM_ChipX(RowIndex) )
	end,

	-- Soft halo, breathing on the beat -- the bit of life the bouncing arrow had.
	-- Faded on all four sides so its edge doesn't read as a second hard border.
	Def.Quad{
		Name="Halo",
		InitCommand=function(self)
			self:zoomto(SSM.chip.w + HALO_PAD*2, SSM.chip.h + HALO_PAD*2)
			self:fadeleft(0.4):faderight(0.4):fadetop(0.4):fadebottom(0.4)
			self:diffuseshift():effectclock("beatnooffset"):effectperiod(1)
		end,
		TintCommand=function(self, params)
			local c = params.Color
			self:effectcolor1(c[1], c[2], c[3], HALO_ALPHA_LOW)
			self:effectcolor2(c[1], c[2], c[3], HALO_ALPHA_HIGH)
		end
	},

	-- The ring itself: the chip's opaque background covers all but RING_PAD of it.
	Def.Quad{
		Name="Ring",
		InitCommand=function(self)
			self:zoomto(SSM.chip.w + RING_PAD*2, SSM.chip.h + RING_PAD*2)
		end,
		TintCommand=function(self, params)
			self:diffuse(params.Color):diffusealpha(RING_ALPHA)
		end
	},
}

return af
