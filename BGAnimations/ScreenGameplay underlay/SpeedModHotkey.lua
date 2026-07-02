-- BGAnimations/ScreenGameplay underlay/SpeedModHotkey.lua
-- Lets a player nudge their active speedmod (XMod/MMod/CMod) up or down
-- in real time while notes are already scrolling, via ctrl+Up/Down
-- (keyboard, all human players) or Select(Back)+MenuUp/Down (arcade,
-- per player). Restricted to EventMode, mirroring the ctrl+R / Select+Start
-- restart hotkey in ./default.lua. See Scripts/SL-Helpers.lua for the
-- shared AdjustSpeedMod / SpeedModHotkeyInputHandler implementation.

local InputHandler = SpeedModHotkeyInputHandler('ModsLevel_Song')

return Def.Actor{
	OnCommand=function(self)
		if PREFSMAN:GetPreference("EventMode") then
			SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		end
	end,
	OffCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
}
