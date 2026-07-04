local RestartHandler = function(event)
	if not event then return end

	if event.type == "InputEventType_FirstPress" then
		if event.DeviceInput.button == "DeviceButton_left ctrl" then
			holdingCtrl = true
		elseif event.DeviceInput.button == "DeviceButton_left shift"
		    or event.DeviceInput.button == "DeviceButton_right shift" then
			holdingShift = true
		elseif event.DeviceInput.button == "DeviceButton_r" then
			-- Ctrl+R replays. Ctrl+Shift+R is reserved for the mean-based resync
			-- hotkey (see Shared/ResyncHandler.lua), so don't replay when Shift is held.
			if holdingCtrl and not holdingShift then
				SM("Replaying Song")
				SCREENMAN:GetTopScreen():SetNextScreenName("ScreenGameplay"):StartTransitioningScreen("SM_GoToNextScreen")
			end
		end
	elseif event.type == "InputEventType_Release" then
		if event.DeviceInput.button == "DeviceButton_left ctrl" then
			holdingCtrl = false
		elseif event.DeviceInput.button == "DeviceButton_left shift"
		    or event.DeviceInput.button == "DeviceButton_right shift" then
			holdingShift = false
		end
	end
end

local t = Def.ActorFrame{
	Name="GameplayUnderlay",
	OnCommand=function(self)
		if ThemePrefs.Get("KeyboardFeatures") and PREFSMAN:GetPreference("EventMode") and not GAMESTATE:IsCourseMode() then
			SCREENMAN:GetTopScreen():AddInputCallback(RestartHandler)
		end
	end
}

return t