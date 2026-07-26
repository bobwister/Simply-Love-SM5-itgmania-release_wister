local af = Def.ActorFrame{ OffCommand=function(self) self:linear(0.1):diffusealpha(0) end }

-- generic header elements (background Def.Quad, left-aligned screen name)
af[#af+1] = LoadActor( THEME:GetPathG("", "_header.lua") )

-- In EventMode the header used to carry the session and in-song clocks. They
-- moved to the footer (BGAnimations/ScreenSelectMusic overlay/Footer.lua), which
-- also primes SL.Global.TimeAtSessionStart, leaving this band free.
if not PREFSMAN:GetPreference("EventMode") then

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
		Name="Stage Number",
		Text=SSM_Header_StageText(),
		InitCommand=function(self)
			self:zoom( SL_WideScale(0.5, 0.6) )
			self:y( SL_WideScale(7.5, 9) / self:GetZoom() )
			self:diffusealpha(0):x(_screen.cx)
		end,
		OnCommand=function(self)
			self:sleep(0.1):decelerate(0.33):diffusealpha(1)
		end,
	}

end

-- "ITG" or "FA+"; aligned to right of screen
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Header")..{
	Name="GameModeText",
	Text=THEME:GetString("ScreenSelectPlayMode", SL.Global.GameMode),
	InitCommand=function(self)
		self:diffusealpha(0):halign(1):y(15)
		self:zoom( SL_WideScale(0.5, 0.6) )

		-- move the GameMode text further left if MenuTimer is enabled.
		-- Shifted right relative to stock now that the P2 pad is gone.
		if PREFSMAN:GetPreference("MenuTimer") then
			self:x(_screen.w - SL_WideScale(95, 110))
		else
			self:x(_screen.w - SL_WideScale(40, 47))
		end
	end,
	OnCommand=function(self)
		self:sleep(0.1):decelerate(0.33):diffusealpha(1)
	end,
	SLGameModeChangedMessageCommand=function(self)
		self:settext(THEME:GetString("ScreenSelectPlayMode", SL.Global.GameMode))
	end
}

-- P1 pad
af[#af+1] = LoadActor( THEME:GetPathB("ScreenSelectStyle", "underlay/pad.lua"), {nil, nil, 1, nil} )..{
	InitCommand=function(self)
		-- takes the slot the P2 pad used to occupy, hugging the right edge
		self:x(_screen.w - (PREFSMAN:GetPreference("MenuTimer") and SL_WideScale(70, 81) or SL_WideScale(15, 17)))
		self:y( SL_WideScale(22, 23.5) ):zoom(0.24)
		self:playcommand("Set", {Player=PLAYER_1})
	end,
	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == PLAYER_1 then
			self:playcommand("Set", {Player=PLAYER_1})
		end
	end
}

-- P2 pad is omitted: this theme targets solo play, so a permanently-unjoined
-- second pad icon is just noise in the header.

return af