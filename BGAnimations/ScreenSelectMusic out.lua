-- Screen-out transition for ScreenSelectMusic.
-- Shows the "Press Start for Options" prompt plus a shrink-to-center countdown
-- gauge for the (engine-controlled) ShowOptionsMessageSeconds window during
-- which a Start press opens Player Options. Pressing Start plays
-- ShowEnteringOptions, which stops the gauge's long tween so the engine's
-- GetTweenTimeLeft()-based scheduling lets options open near-immediately.

return Def.ActorFrame{
	InitCommand=function(self) self:draworder(200) end,

	Def.Quad{
		InitCommand=function(self) self:diffuse(0,0,0,0):FullScreen():cropbottom(1):fadebottom(0.5) end,
		OffCommand=function(self) self:linear(0.3):cropbottom(-0.5):diffusealpha(1) end
	},

	-- "Press Start for Options" prompt (kept). On Start, fade out quickly with
	-- no sleep so the engine's GetTweenTimeLeft() stays small (near-immediate entry).
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Text=THEME:GetString("ScreenSelectMusic", "Press Start for Options"),
		InitCommand=function(self) self:visible(false):Center():zoom(1.0) end,
		ShowPressStartForOptionsCommand=function(self) self:visible(true) end,
		ShowEnteringOptionsCommand=function(self) self:stoptweening():linear(0.1):diffusealpha(0) end,
	},

	-- shrink-to-center countdown gauge for the options window
	Def.ActorFrame{
		Name="OptionsCountdown",
		InitCommand=function(self)
			-- TWEAK: vertical position of the gauge, below the centered prompt
			self:xy(_screen.cx, _screen.cy + 28):visible(false)
		end,
		ShowPressStartForOptionsCommand=function(self)
			local dur = tonumber(THEME:GetMetric("ScreenSelectMusic", "ShowOptionsMessageSeconds")) or 1.5
			self:visible(true):diffusealpha(1)
			-- animate width via zoomtowidth (a Quad's zoomto sets zoomx to the pixel
			-- width, so zoomx(1) would collapse it to 1px; zoomtowidth is the correct idiom)
			self:GetChild("Fill"):finishtweening():zoomtowidth(300):linear(dur):zoomtowidth(0)
		end,
		ShowEnteringOptionsCommand=function(self)
			-- stop the long gauge tween so GetTweenTimeLeft() drops and options open fast
			self:GetChild("Fill"):stoptweening()
			self:stoptweening():linear(0.1):diffusealpha(0)
		end,

		Def.Quad{
			Name="Track",
			-- TWEAK: gauge size/color (dim static background track)
			InitCommand=function(self) self:zoomto(300, 8):diffuse(color("#ffffff")):diffusealpha(0.25) end
		},
		Def.Quad{
			Name="Fill",
			-- TWEAK: gauge size/color (bright fill that shrinks toward center)
			InitCommand=function(self) self:zoomto(300, 8):diffuse(color("#ffffff")) end
		},
	},
}
