return Def.ActorFrame{
	Def.Sound{
		File="../Sounds/_logo.ogg",
		OnCommand=function(self)
			self:play()
		end
	},
}