-- BGAnimations/ScreenSelectMusic overlay/SongSearchHotkey.lua
-- ctrl+F opens the Song Search text entry directly, as if "Song Search" had been
-- picked in the SortMenu. Same availability rules as that SortMenu entry: only with
-- the KeyboardFeatures theme pref on, and never in course mode.
--
-- The "DirectInputToEngineForSongSearch" command (SortMenu/default.lua) redirects
-- input back to the engine and pushes ScreenTextEntry on top of this screen, so all
-- we do here is detect the chord and queue it on the overlay.

local holdingCtrl = false

local InputHandler = function(event)
	if not event or not event.DeviceInput then return false end

	local button = event.DeviceInput.button

	if button == "DeviceButton_left ctrl" then
		holdingCtrl = (event.type ~= "InputEventType_Release")
		return false
	end

	if holdingCtrl
	and button == "DeviceButton_f"
	and event.type == "InputEventType_FirstPress"
	and ThemePrefs.Get("KeyboardFeatures")
	and not GAMESTATE:IsCourseMode() then
		local overlay = SCREENMAN:GetTopScreen():GetChild("Overlay")
		if overlay then
			-- ScreenTextEntry will swallow the ctrl release, so forget the chord now.
			holdingCtrl = false
			overlay:queuecommand("DirectInputToEngineForSongSearch")
		end
	end

	return false
end

return Def.Actor{
	OnCommand=function(self)
		holdingCtrl = false
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
	end,
	OffCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
}
