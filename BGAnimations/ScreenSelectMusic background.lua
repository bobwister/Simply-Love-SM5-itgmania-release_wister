return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self) self:FullScreen():Center():diffuse( Color.White ) end
	},

	--LoadActor( THEME:GetPathB("", "_shared background") ),
	
	Def.Sprite{
		Texture="./_shared background/CJ126/CJ126 Normal.mp4",--use the video without the lua animations
		OnCommand=function(self)
			self:rate(1.0):diffusealpha(0.7):stretchto(0,0,SCREEN_WIDTH,SCREEN_HEIGHT)
		end;
	},

	Def.Quad{
		InitCommand=function(self)
			self:diffuse((ThemePrefs.Get("VisualStyle") == "SRPG6") and Color.Black or Color.White)
				:Center()
				:FullScreen()
				:sleep(0.6):linear(0.5):diffusealpha(0)
				:queuecommand("Hide")
		end,
		HideCommand=function(self) self:visible(false) end
	}
}
