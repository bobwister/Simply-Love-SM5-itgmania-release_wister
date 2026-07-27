local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2
local item_width = _screen.w / 2.125
local item_height = _screen.h / num_visible_items

local accent = PlayerColor(PLAYER_1)

local af = Def.ActorFrame{}

-- "Technique HUD" focus frame. The engine renders every wheel row at a fixed
-- height, so the selected row can't actually grow; instead this highlight actor
-- sits on top of it and draws a halo + edge rules, which reads as the row
-- lifting out of the stack. Aligned to the row plates in
-- Graphics/MusicWheelItem Course NormalPart.lua, hence the same x offset.
af[#af+1] = Def.ActorFrame{
	InitCommand=function(self) self:x(WideScale(28,33)) end,

	-- additive halo bleeding just past the row's edges. Vertices are left white
	-- so the pulsing diffuse below is what carries the accent color; tinting
	-- both would square the hue and muddy it.
	Def.ActorMultiVertex{
		InitCommand=function(self)
			local white = {1,1,1,1}
			local v = WheelPlateVerts(item_width + 12, item_height + 8, SL_WHEEL_BEVEL, white, white)
			self:SetDrawState({Mode="DrawMode_Fan"}):SetNumVertices(#v):SetVertices(v)
			self:x(-6):blend("BlendMode_Add")
			self:diffuseshift():effectperiod(3)
			self:effectcolor1(DimColor(accent, 1.00, 0.10))
			self:effectcolor2(DimColor(accent, 1.00, 0.26))
		end
	},

	-- bright slanted bar down the leading edge
	Def.ActorMultiVertex{
		InitCommand=function(self)
			local c = DimColor(accent, 1.00, 0.95)
			local top, bot = -item_height/2, item_height/2
			local b, w = SL_WHEEL_BEVEL, 3
			local v = {
				{{b,     top, 0}, c},
				{{b + w, top, 0}, c},
				{{w,     bot, 0}, c},
				{{0,     bot, 0}, c},
			}
			self:SetDrawState({Mode="DrawMode_Fan"}):SetNumVertices(#v):SetVertices(v)
		end
	},

	-- hairline rules along the (unslanted) top and bottom edges
	Def.Quad{
		InitCommand=function(self)
			self:horizalign(left):zoomto(item_width - SL_WHEEL_BEVEL, 1.5)
			self:xy(SL_WHEEL_BEVEL, -item_height/2):diffuse(DimColor(accent, 1.00, 0.85))
		end
	},
	Def.Quad{
		InitCommand=function(self)
			self:horizalign(left):zoomto(item_width - SL_WHEEL_BEVEL, 1.5)
			self:xy(0, item_height/2):diffuse(DimColor(accent, 1.00, 0.85))
		end
	},
}

--animated arrow cursor
af[#af+1] = Def.Sprite{
	Texture=THEME:GetPathB("ScreenSelectMusic", "overlay/PerPlayer/arrow.png"),
	InitCommand=function(self)
		self:zoom(1.0)
		self:bounce():effectclock("beatnooffset"):effectmagnitude(-6,0,0):effectperiod(1)
		self:xy(30, 0)
	end,
}

-- Current speedmod, in the margin between the left column and the row plate, with the
-- shortcut that changes it spelled out above and below.
--
-- Two players still get the old pair of lines at y -15/+15: three lines each will not
-- fit in a 32px row, and the hotkey they'd document (ctrl+Up/Down) moves BOTH players'
-- speedmods at once anyway, so a hint sitting beside one player's figure would be
-- misleading. Solo -- which is what this theme is set up for -- gets the stack.
local solo = (#GAMESTATE:GetHumanPlayers() == 1)

-- The hotkey only exists on ScreenSelectMusic (BGAnimations/ScreenSelectMusic
-- overlay/SpeedModHotkey.lua). This highlight is also the course wheel's and the casual
-- wheel's, so the hint has to stay off those two rather than promise a key that does
-- nothing there.
local hotkey_screen = (Var("LoadingScreen") == "ScreenSelectMusic")

-- TWEAK: three lines inside a row that is item_height (32) tall. The outer two have to
-- clear the highlight's own hairline rules at +/- item_height/2.
local SPEED_X    = 10
local SPEED_ZOOM = solo and hotkey_screen and 0.40 or 0.5
local HINT_ZOOM  = 0.26      -- same size as the Pack Rail's CTRL+LEFT / CTRL+RIGHT legend
local HINT_DY    = 12

-- The margin this sits in is only ~38px wide (the left column ends at x 310, the row
-- plate starts at 348), so the hints are capped rather than left to bleed over either.
local HINT_MAXWIDTH = 38 / HINT_ZOOM

local hint_color = color("#6E838D")

-- Strings are asked of ScreenSelectMusic by name instead of via Screen.String: this file
-- is loaded by three different screens and only one of them declares them.
local HINT_UP   = THEME:GetString("ScreenSelectMusic", "SpeedModHintUp")
local HINT_DOWN = THEME:GetString("ScreenSelectMusic", "SpeedModHintDown")

for player in ivalues(GAMESTATE:GetHumanPlayers()) do
	local pn = ToEnumShortString(player)

	-- solo centres the figure so the two hints can sit either side of it
	local speed_y = 0
	if not solo or not hotkey_screen then
		speed_y = (player == PLAYER_2) and 15 or -15
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
			InitCommand=function(self)
				self:diffuse(PlayerColor(player))
				self:xy(SPEED_X, speed_y):zoom(SPEED_ZOOM)
				self:settext( ("%s%s"):format(SL[pn].ActiveModifiers.SpeedModType, SL[pn].ActiveModifiers.SpeedMod) )
			end,
			PlayerOptionsChangedMessageCommand=function(self, params)
				if params.Player ~= player then return false end
				self:settext( ("%s%s"):format(SL[pn].ActiveModifiers.SpeedModType, SL[pn].ActiveModifiers.SpeedMod) )
			end,
		}
end

if solo and hotkey_screen then
	for _, hint in ipairs({ {HINT_UP, -HINT_DY}, {HINT_DOWN, HINT_DY} }) do
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Text=hint[1],
			InitCommand=function(self)
				self:xy(SPEED_X, hint[2]):zoom(HINT_ZOOM)
				self:maxwidth(HINT_MAXWIDTH):diffuse(hint_color)
			end
		}
	end
end

return af
