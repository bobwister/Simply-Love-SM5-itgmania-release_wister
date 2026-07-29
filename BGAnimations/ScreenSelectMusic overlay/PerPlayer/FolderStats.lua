-- Folder stats: how far into the current pack this profile is, at the difficulty the
-- wheel is on.
--
-- A floating card over the right of the screen, shown while the wheel is sorted by group.
-- It answers what a wheel row cannot: a row is 32px tall and the engine will not let a
-- group row be any taller than a song row -- WheelBase hands ItemTransformFunction a
-- throwaway Actor and caches the result on (offset, index) alone, so row height cannot
-- depend on what a row contains. The star tally needs more than one line, so it needs a
-- card.
--
-- It reads the same cached walk the wheel's group rows read
-- (Scripts/SL-Helpers-FolderProgress.lua). This file used to run its own, uncached,
-- identical pass over every song in the group, with a hand-rolled
-- currentFolder/currentDifficulty memo of its own -- two walks of a 199-song pack where
-- one does.

-- No folders in course mode to get stats for
if GAMESTATE:IsCourseMode() then return end

-- Don't show folder stats if disabled in the operator menu
if not ThemePrefs.Get("FolderStats") then return end

local player = ...
local pn = ToEnumShortString(player)

-- Read at paint time, not captured: a profile switch from the wheel changes the Simply
-- Love color without a screen reload, and the actors below repaint on ColorSelected.
local function Accent() return PlayerColor(player) end

-- TWEAK: the card.
--
-- WIDTH is held to roughly what this panel already occupied, because two of them tile
-- side by side in versus (see the x positions below) and 4:3 has no room for anything
-- wider. That is also why the star tally stacks its count UNDER its icon rather than
-- beside it: a 26px cell fits a 14px icon over a three-digit count, but not the two in a
-- row.
local W = WideScale(146, 188)
local H = 74
local PAD = 8

-- Everything vertical is measured DOWN from the card's top edge, which is this frame's
-- origin -- same convention as PlayerCard.lua.
local NAME_Y  = 12
local ROW_Y   = 30
local RULE_Y  = 40
local ICON_Y  = 52
local COUNT_Y = 65

local NAME_ZOOM  = 0.50
local LABEL_ZOOM = 0.38
local VALUE_ZOOM = 0.50
local COUNT_ZOOM = 0.38

local CELL_W    = (W - 2*PAD) / 5
local ICON_SIZE = 14

local GRADE_SHEET = THEME:GetPathG("MusicWheelItem", "Grades/grades 1x18.png")
local QUINT_ICON  = THEME:GetPathG("MusicWheelItem", "Grades/quint.png")

-- Where the card sits. Solo hugs the right edge; versus tiles two of them leftward.
-- These are the positions this panel already used, kept so a versus cabinet doesn't have
-- its layout moved out from under it.
local SOLO_X   = _screen.cx * 1.77
local VERSUS_X = _screen.cx * 1.305
local CARD_TOP = _screen.cy * 0.3 - H/2

local function CardX()
	if #GAMESTATE:GetHumanPlayers() > 1 and player == PLAYER_1 then return VERSUS_X end
	return SOLO_X
end

-- Centre of star cell `i`, i = 1 for quints down to 5 for one star, reading left to right
-- best first -- the same order the player card's tally uses.
local function CellX(i)
	return -W/2 + PAD + (i - 1) * CELL_W + CELL_W/2
end

-- -----------------------------------------------------------------------

local af = Def.ActorFrame{
	Name="FolderStats",
	InitCommand=function(self)
		self:xy(CardX(), CARD_TOP)
	end,

	OnCommand=function(self)                            self:playcommand("Refresh") end,
	CurrentSongChangedMessageCommand=function(self)     self:playcommand("Refresh") end,
	["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self) self:playcommand("Refresh") end,
	MusicWheelSortMessageCommand=function(self)         self:playcommand("Refresh") end,
	PlayerProfileSetMessageCommand=function(self)       self:playcommand("Refresh") end,

	PlayerJoinedMessageCommand=function(self, params)
		self:x(CardX())
		if params.Player == player then self:playcommand("Refresh") end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		self:x(CardX())
		if params.Player == player then self:playcommand("Refresh") end
	end,

	-- One place decides whether the card has anything to say, then hands the figures to
	-- every child. The children never look the pack up themselves.
	RefreshCommand=function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen or screen:GetName() ~= "ScreenSelectMusic" then
			self:visible(false)
			return
		end

		-- Outside a group sort the wheel's "section" is a letter or a BPM band, not a
		-- pack, and none of this means anything.
		if not GAMESTATE:IsPlayerEnabled(player)
				or GAMESTATE:GetSortOrder() ~= "SortOrder_Group" then
			self:visible(false)
			return
		end

		local wheel = screen:GetMusicWheel()
		local group = wheel and wheel:GetSelectedSection()
		if not group or group == "" then
			self:visible(false)
			return
		end

		local cleared, total, tiers = FolderProgressGet(player, group)
		-- nil = no profile or no chart selected; 0 = a section that holds no charts at
		-- this difficulty, which there is nothing useful to say about
		if not total or total == 0 then
			self:visible(false)
			return
		end

		local steps = GAMESTATE:GetCurrentSteps(player)

		self:visible(true)
		self:playcommand("SetFolder", {
			group      = group,
			cleared    = cleared,
			total      = total,
			tiers      = tiers,
			difficulty = steps:GetDifficulty(),
		})
	end,

	Def.Quad{
		InitCommand=function(self)
			HUDPanel(self):zoomto(W, H):vertalign(top)
		end
	},
}

af[#af+1] = HUDCardDecor(W, H, 0, H/2)

-- The pack's name, in the player's accent so the card reads as belonging to them.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	Name="FolderName",
	Text="",
	InitCommand=function(self)
		self:y(NAME_Y):zoom(NAME_ZOOM):maxwidth((W - 2*PAD) / NAME_ZOOM)
		self:diffuse(Accent())
	end,
	SetFolderCommand=function(self, params) self:settext(params.group) end,
	ColorSelectedMessageCommand=function(self) self:diffuse(Accent()) end
}

-- Which difficulty is being counted, left, and the clear progress, right. The difficulty
-- has to be named here: unlike the wheel row, this card is read on its own.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	Name="Difficulty",
	Text="",
	InitCommand=function(self)
		self:horizalign(left):xy(-W/2 + PAD, ROW_Y):zoom(LABEL_ZOOM)
		self:maxwidth((W - 2*PAD - 44) / LABEL_ZOOM):diffuse(HUD_LABEL)
	end,
	SetFolderCommand=function(self, params)
		self:settext( THEME:GetString("Difficulty", ToEnumShortString(params.difficulty)):upper() )
	end
}

af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	Name="Progress",
	Text="",
	InitCommand=function(self)
		self:horizalign(right):xy(W/2 - PAD, ROW_Y):zoom(VALUE_ZOOM):diffuse(HUD_TEXT)
	end,
	SetFolderCommand=function(self, params)
		self:settext( params.cleared .. "/" .. params.total )
	end
}

af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:zoomto(W - 2*PAD, 1):y(RULE_Y)
		self:playcommand("Paint")
	end,
	PaintCommand=function(self) self:diffuse( DimColor(Accent(), 1.0, 0.20) ) end,
	ColorSelectedMessageCommand=function(self) self:playcommand("Paint") end,
}

-- The tally: five tiers, best first, icon over count.
--
-- The icons are the wheel's own -- the star tiers off the grade sheet, quint.png for the
-- fifth -- exactly as the player card draws them, so a pack's tally and a profile's tally
-- say the same thing with the same pictures.
for tier = 5, 1, -1 do
	local cell_x = CellX(6 - tier)

	if tier == 5 then
		af[#af+1] = Def.Sprite{
			Texture=QUINT_ICON,
			InitCommand=function(self)
				self:zoomto(ICON_SIZE, ICON_SIZE):xy(cell_x, ICON_Y)
			end
		}
	else
		af[#af+1] = Def.Sprite{
			Texture=GRADE_SHEET,
			InitCommand=function(self)
				-- state 0 is Grade_Tier01, the four-star grade, so a 4-star tier is state 0
				self:animate(false):setstate(4 - tier)
				self:zoomto(ICON_SIZE, ICON_SIZE):xy(cell_x, ICON_Y)
			end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="StarCount"..tier,
		Text="",
		InitCommand=function(self)
			self:xy(cell_x, COUNT_Y):zoom(COUNT_ZOOM)
			self:maxwidth((CELL_W - 2) / COUNT_ZOOM):diffuse(HUD_TEXT)
		end,
		SetFolderCommand=function(self, params)
			local n = params.tiers[tier]
			-- a dim zero rather than a blank: "none at this tier" is an answer
			self:settext(n):diffuse( n > 0 and HUD_TEXT or HUD_LABEL )
		end
	}
end

return af
