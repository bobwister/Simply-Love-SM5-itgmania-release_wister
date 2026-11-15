-- BGAnimations/ScreenGameplay underlay/PracticeHotkey.lua
-- ctrl+E abandons the current run and opens Practice Mode on the same song and
-- chart, with the cursor on the position the song had reached. The run's stats are
-- discarded (same back-out path as the ctrl+R restart in ./default.lua), and leaving
-- Practice Mode returns to ScreenSelectMusic (see [ScreenPractice] in metrics.ini).
--
-- The position is handed over through SL.Global.PracticeSeekSeconds, which
-- "ScreenPractice overlay.lua" consumes (and clears) once the screen is up.
-- Restricted to EventMode and non-course, mirroring the ctrl+R restart hotkey.

local holdingCtrl = false

local InputHandler = function(event)
	if not event or not event.DeviceInput then return false end

	local button = event.DeviceInput.button

	if button == "DeviceButton_left ctrl" then
		holdingCtrl = (event.type ~= "InputEventType_Release")
		return false
	end

	if holdingCtrl
	and button == "DeviceButton_e"
	and event.type == "InputEventType_FirstPress" then
		local seconds = GAMESTATE:GetSongPosition():GetMusicSeconds()
		SL.Global.PracticeSeekSeconds = math.max(0, seconds or 0)

		SCREENMAN:GetTopScreen():SetPrevScreenName("ScreenPractice"):SetNextScreenName("ScreenPractice"):begin_backing_out()
	end

	return false
end

return Def.Actor{
	OnCommand=function(self)
		holdingCtrl = false
		if PREFSMAN:GetPreference("EventMode") and not GAMESTATE:IsCourseMode() then
			SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		end
	end,
	OffCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
}
