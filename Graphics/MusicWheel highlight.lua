local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2
local item_width = _screen.w / 2.125

local af = Def.ActorFrame{}

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
		}
	end
		
return af