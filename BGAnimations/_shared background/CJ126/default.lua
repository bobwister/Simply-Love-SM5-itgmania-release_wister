local t = Def.ActorFrame{
	Def.Sprite{
		Texture="CJ126 Normal.mp4",
		OnCommand=function(self)
			self:rate(1.0):diffusealpha(0.7):stretchto(0,0,SCREEN_WIDTH,SCREEN_HEIGHT)
			--PROFILEMAN:GetMachineProfile():SetLastUsedHighScoreName(""):SetDisplayName("")
		end;
	},
	LoadActor("_lower")..{
		InitCommand=function(self) self:Center():blend(Blend.Add):zoomtowidth(SCREEN_WIDTH) end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:croptop(-0.8):cropbottom(1):fadebottom(0.45):fadetop(0.45):linear(3):croptop(1):cropbottom(-0.8):sleep(1):queuecommand("Anim") end
	},
	LoadActor("_upper")..{
		InitCommand=function(self) self:Center():blend(Blend.Add):zoomtowidth(SCREEN_WIDTH) end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:croptop(-0.8):cropbottom(1):fadebottom(0.45):fadetop(0.45):linear(3):croptop(1):cropbottom(-0.8):sleep(1):queuecommand("Anim") end
	},
	LoadActor("_lower")..{
		InitCommand=function(self) self:Center():blend(Blend.Add):zoomtowidth(SCREEN_WIDTH) end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:croptop(-0.8):cropbottom(1):fadebottom(0.45):fadetop(0.45):linear(3):croptop(1):cropbottom(-0.8):sleep(1):queuecommand("Anim") end
	},
	LoadActor("_upper")..{
		InitCommand=function(self) self:Center():blend(Blend.Add):zoomtowidth(SCREEN_WIDTH) end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:croptop(-0.8):cropbottom(1):fadebottom(0.45):fadetop(0.45):linear(3):croptop(1):cropbottom(-0.8):sleep(1):queuecommand("Anim") end
	},

	LoadActor("_topright")..{
		InitCommand=function(self) self:blend(Blend.Add):FullScreen() end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:diffusealpha(1):sleep(0.3):diffusealpha(1):croptop(-0.8):cropbottom(1):fadebottom(0.45):fadetop(0.45):sleep(0.5):diffusealpha(1):linear(3):croptop(1):cropbottom(-0.8):sleep(0.3):queuecommand("Anim") end
	},
	LoadActor("_center")..{
		InitCommand=function(self) self:blend(Blend.Add):FullScreen() end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:diffusealpha(1):sleep(0.3):diffusealpha(1):croptop(-0.8):cropbottom(1):fadebottom(0.45):fadetop(0.45):sleep(0.8):diffusealpha(1.5):linear(3):croptop(1):cropbottom(-0.8):sleep(0.3):queuecommand("Anim") end
	},
	LoadActor("_2top")..{
		InitCommand=function(self) self:blend(Blend.Add):FullScreen() end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:cropright(-0.8):cropleft(1):fadeleft(0.45):faderight(0.45):sleep(0.1):diffusealpha(1):linear(3):cropright(1):cropleft(-0.8):sleep(0.25):queuecommand("Anim") end
	},
	LoadActor("_left")..{
		InitCommand=function(self) self:blend(Blend.Add):FullScreen() end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:cropright(-0.8):cropleft(1):fadeleft(0.45):faderight(0.45):sleep(0.4):diffusealpha(1):linear(3):cropright(1):cropleft(-0.8):sleep(0.2):queuecommand("Anim") end
	},
	LoadActor("_right")..{
		InitCommand=function(self) self:blend(Blend.Add):FullScreen() end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:cropleft(-0.8):cropleft(1):faderight(0.45):fadeleft(0.45):sleep(0.2):diffusealpha(1):linear(3):cropleft(1):cropright(-0.8):sleep(0.5):queuecommand("Anim") end
	},
	LoadActor("_2center")..{
		InitCommand=function(self) self:blend(Blend.Add):FullScreen() end,
		OnCommand=function(self) self:queuecommand("Anim") end,
		AnimCommand=function(self) self:cropright(-0.8):cropleft(1):fadeleft(0.45):faderight(0.45):sleep(0.4):diffusealpha(1):linear(3):cropright(1):cropleft(-0.8):sleep(0.2):queuecommand("Anim") end
	},
}

return t
