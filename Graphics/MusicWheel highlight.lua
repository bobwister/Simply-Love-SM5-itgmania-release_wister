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

--current speedmod
for player in ivalues(GAMESTATE:GetHumanPlayers()) do
	local pn = ToEnumShortString(player)

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
			InitCommand=function(self)
				self:diffuse(PlayerColor(player))
				if (player == PLAYER_1) then self:xy(10, -15) end
				if (player == PLAYER_2) then self:xy(10, 15) end
				self:zoom(0.5)
				self:settext( ("%s%s"):format(SL[pn].ActiveModifiers.SpeedModType, SL[pn].ActiveModifiers.SpeedMod) )
			end,
			PlayerOptionsChangedMessageCommand=function(self, params)
				if params.Player ~= player then return false end
				self:settext( ("%s%s"):format(SL[pn].ActiveModifiers.SpeedModType, SL[pn].ActiveModifiers.SpeedMod) )
			end,
		}
	end

return af
