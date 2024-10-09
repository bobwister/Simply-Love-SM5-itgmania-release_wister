local t = Def.ActorFrame{}

t[#t+1] = Def.ActorFrame{

	--Def.Sprite{
	--	Texture="roxor",
	--	OnCommand=function(self)
	--		self:xy(SCREEN_LEFT+90,SCREEN_TOP+30):diffusealpha(0):sleep(0.5):linear(0.5):diffusealpha(1)
	--	end;
	--},

		Def.ActorFrame{
			OnCommand=function(self)
				self:xy(SCREEN_CENTER_X - 440,SCREEN_CENTER_Y - 220)
			end;
				--smaller negative x goes to the right
				--smaller negative y goes down
				Def.Sprite{
					Texture="in",
					OnCommand=function(self)
						self:xy(-200,-80):zoom(0):sleep(0.1):bounceend(0.4):zoom(1.0)
						--self:xy(-240,-70):zoom(0):sleep(0.1):bounceend(0.4):zoom(1.0)
					end;
				},
				Def.Sprite{
					Texture="the",
					OnCommand=function(self)
						self:xy(-50,-80):zoom(0):sleep(0.1):bounceend(0.4):zoom(1.0)
						--self:xy(-106,-70):zoom(0):sleep(0.1):bounceend(0.4):zoom(1.0)
					end;
				},
				Def.Sprite{
					Texture="2",
					OnCommand=function(self)
						self:xy(200,0):zoomx(0):glow(1,1,1,1):sleep(0.4):zoomy(3):bounceend(.3):zoom(0.8):glow(1,1,1,0)
						--self:xy(190,10):zoomx(0):glow(1,1,1,1):sleep(0.8):zoomy(3):bounceend(.3):zoom(0.7):glow(1,1,1,0)
					end;
				},
				Def.Sprite{
					Texture="groove",
					OnCommand=function(self)
						self:xy(-30,16):zoom(0):sleep(0.1):bounceend(0.4):zoom(0.9)
						--self:xy(-50,26):zoom(0):sleep(0.1):bounceend(0.4):zoom(1.0)
					end;
				},
				
				--Def.Sprite{
				--	Texture="trademark",
				--	OnCommand=function(self)
				--		self:xy(176,-24):diffusealpha(0):sleep(0.5):linear(0.5):diffusealpha(1):diffuse(color("#000000"))
				--	end;
				--},
		},

	--Def.BitmapText{
	--Font="_eurostile normal",
	--Condition="SelectButtonAvailable()",
	--Text="&xa9; 2005 Andamiro Co., Ltd.",
	--OnCommand=function(self)
	--	self:xy(SCREEN_CENTER_X,SCREEN_BOTTOM-31):zoom(0.5):shadowlength(2):diffusealpha(0.8)
	--end;
	--},
	--
	--Def.BitmapText{
	--Font="_eurostile normal",
	--Condition="SelectButtonAvailable()",
	--Text="&xa9; 2005 Roxor Games, Inc.",
	--OnCommand=function(self)
	--	self:xy(SCREEN_CENTER_X,SCREEN_BOTTOM-17):zoom(0.5):shadowlength(2):diffusealpha(0.8)
	--end;
	--},
	--
	--Def.BitmapText{
	--Font="_eurostile normal",
	--Condition="SelectButtonAvailable()",
	--Text="r5",
	--OnCommand=function(self)
	--	self:xy(SCREEN_CENTER_X+94,SCREEN_BOTTOM-17):zoom(0.5):shadowlength(2):horizalign(left):diffusealpha(0.8)
	--end;
	--},
	--
	--Def.Quad{
	--OnCommand=function(self)
	--	self:stretchto(SCREEN_LEFT,SCREEN_TOP,SCREEN_RIGHT,SCREEN_BOTTOM):diffuse(color("#FFFFFF")):diffusealpha(0):sleep(0.1):accelerate(0.5):diffusealpha(1):sleep(0.2):decelerate(0.5):diffusealpha(0)
	--end
	--}

}



return t;