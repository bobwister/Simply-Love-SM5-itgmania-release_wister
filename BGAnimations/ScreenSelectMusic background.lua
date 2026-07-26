-- "Technique HUD" background. The CJ126 video is kept as the base plate, then
-- the HUD layers go on top of it: a slow accent-tinted grid borrowed from the
-- Technique visual style, a scrim behind the wheel column so rows read cleanly
-- over busy video frames, and vignette bands top and bottom.
local accent = PlayerColor(PLAYER_1)

return Def.ActorFrame{

	Def.Sprite{
		Texture="./_shared background/CJ126/CJ126 Normal.mp4",--use the video without the lua animations
		OnCommand=function(self)
			self:rate(1.0):diffusealpha(0.8):stretchto(0,0,SCREEN_WIDTH,SCREEN_HEIGHT)
		end;
	},

	Def.Quad{
		InitCommand=function(self) self:FullScreen():Center():diffuse( Color.Black ):diffusealpha(0.35) end
	},

	-- slow drifting grid, same square.png the Technique visual style scrolls
	Def.Sprite{
		Texture="./_shared background/square.png",
		OnCommand=function(self)
			self:zoom(20):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
				:customtexturerect(0,0,60,60):texcoordvelocity(0.02, 0.015)
				:diffuse(DimColor(accent, 1.0, 0.06))
		end
	},
	Def.Sprite{
		Texture="./_shared background/square.png",
		OnCommand=function(self)
			self:zoom(20):xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
				:customtexturerect(0,0,60,60):texcoordvelocity(0.04, 0.03)
				:diffuse(DimColor(accent, 1.0, 0.03))
		end
	},

	-- scrim under the wheel column
	Def.Quad{
		InitCommand=function(self)
			self:horizalign(left):vertalign(top):xy(_screen.cx - 60, 0)
			self:zoomto(_screen.w - (_screen.cx - 60), _screen.h)
			self:diffuse(color("#05080A")):diffusealpha(0.55):fadeleft(0.35)
		end
	},

	-- vignette bands
	Def.Quad{
		InitCommand=function(self)
			self:horizalign(left):vertalign(top):xy(0, 0):zoomto(_screen.w, 90)
			self:diffuse(Color.Black):diffusealpha(0.55):fadebottom(1)
		end
	},
	Def.Quad{
		InitCommand=function(self)
			self:horizalign(left):vertalign(bottom):xy(0, _screen.h):zoomto(_screen.w, 90)
			self:diffuse(Color.Black):diffusealpha(0.55):fadetop(1)
		end
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
