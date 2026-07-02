-- BGAnimations/ScreenSelectMusic overlay/SpeedModHotkey.lua
-- Lets a player nudge their active speedmod (XMod/MMod/CMod) up or down
-- via ctrl+Up/Down (keyboard, all human players) or Select(Back)+MenuUp/Down
-- (arcade, per player), before picking a song. Always active (not gated by
-- EventMode). See Scripts/SL-Helpers.lua for the shared AdjustSpeedModFromDisplay /
-- SpeedModHotkeyInputHandler implementation. No modslevel is passed here:
-- the engine's ModsLevel_Preferred PlayerOptions object isn't guaranteed to
-- be synced with what's displayed on this screen, so we read/write the SL
-- display table directly instead (see AdjustSpeedModFromDisplay).

local InputHandler = SpeedModHotkeyInputHandler()

return Def.Actor{
	OnCommand=function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
	end,
	OffCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
}
