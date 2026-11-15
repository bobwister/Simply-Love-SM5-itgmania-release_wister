-- BGAnimations/ScreenSelectMusic overlay/SongSearchHotkey.lua
-- ctrl+F opens the Song Search text entry directly, as if "Song Search" had been
-- picked in the SortMenu. Same availability rules as that SortMenu entry: only with
-- the KeyboardFeatures theme pref on, and never in course mode.
--
-- The "DirectInputToEngineForSongSearch" command (SortMenu/default.lua) redirects
-- input back to the engine and pushes ScreenTextEntry on top of this screen, so all
-- we do here is detect the chord and queue it on the overlay.
--
-- The engine's own ctrl+<letter> handling on this screen jumps the wheel to the
-- first song starting with that letter, and it runs BEFORE our Lua callback (its
-- result can't be vetoed, see the note in PackRail.lua). So by the time we see
-- ctrl+F the wheel has already moved to the "F" songs. We therefore keep track of
-- the song selected before each change and put the wheel back on it when the search
-- opens.

local holdingCtrl = false

-- previous / current wheel song, and when the current one was selected
local prevSong, curSong, changeTime = nil, nil, -1

local function RestoreWheel(now)
	-- If the song changed during this very key press, it is the engine's letter
	-- jump: go back to what was selected before it.
	local target = (now - changeTime < 0.05) and prevSong or nil
	if not target then return end

	local wheel = SCREENMAN:GetTopScreen():GetMusicWheel()
	if wheel then wheel:SelectSong(target) end
end

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
			RestoreWheel(GetTimeSinceStart())
			overlay:queuecommand("DirectInputToEngineForSongSearch")
		end
	end

	return false
end

return Def.Actor{
	OnCommand=function(self)
		holdingCtrl = false
		prevSong, curSong, changeTime = nil, GAMESTATE:GetCurrentSong(), -1
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
	end,
	OffCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
	CurrentSongChangedMessageCommand=function(self)
		prevSong, curSong = curSong, GAMESTATE:GetCurrentSong()
		changeTime = GetTimeSinceStart()
	end,
}
