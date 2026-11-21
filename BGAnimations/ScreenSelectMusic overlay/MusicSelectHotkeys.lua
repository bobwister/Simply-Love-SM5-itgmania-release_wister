-- BGAnimations/ScreenSelectMusic overlay/MusicSelectHotkeys.lua
-- Keyboard shortcuts of the music select screen that involve a letter key:
--
--   ctrl+F   switch between the current sort and the Favorites sort (and back)
--   ctrl+R   open the Song Search text entry (same as "Song Search" in the SortMenu)
--
-- It also neutralises the engine's own ctrl+<letter> shortcut, which jumps the wheel
-- to the first song starting with that letter. That jump runs BEFORE our Lua callbacks
-- and its result cannot be vetoed (see the note in PackRail.lua), and the redirect
-- trick PackRail uses for the arrows doesn't cover letters, which map to no player
-- button. So instead we undo it: we keep track of the song selected before each wheel
-- change, and when a ctrl+letter lands on a wheel change made by that very key press,
-- the wheel is put back on the previous song.
--
-- ctrl+shift+R is the engine's "reload current song" and is left alone.
--
-- Song Search follows the SortMenu entry's rules: KeyboardFeatures theme pref on, not
-- course mode. The favorites toggle needs no pref, but is also off in course mode.

local holdingCtrl, holdingShift = false, false

-- previous / current wheel song, and when the current one was selected
local prevSong, curSong, changeTime = nil, nil, -1

local function IsCtrl(b)  return b == "DeviceButton_left ctrl"  or b == "DeviceButton_right ctrl"  end
local function IsShift(b) return b == "DeviceButton_left shift" or b == "DeviceButton_right shift" end
local function IsLetter(b) return b:match("^DeviceButton_%l$") ~= nil end

local function GetWheel()
	local screen = SCREENMAN:GetTopScreen()
	return screen and screen.GetMusicWheel and screen:GetMusicWheel() or nil
end

-- If the song changed during this very key press, it is the engine's letter jump:
-- go back to what was selected before it.
local function UndoLetterJump()
	if GetTimeSinceStart() - changeTime >= 0.05 or not prevSong then return end
	local wheel = GetWheel()
	if wheel then wheel:SelectSong(prevSong) end
end

-- -----------------------------------------------------------------------
-- ctrl+F

-- The player whose favorites feed the Favorites sort: the first joined one that has any.
local function FavoritesPlayer()
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		local favorites = SL[ToEnumShortString(player)].Favorites
		if favorites and #favorites > 0 then return player end
	end
	return nil
end

local function ToggleFavoritesSort()
	local wheel = GetWheel()
	if not wheel then return end

	local PREFERRED = "SortOrder_Preferred"
	local current   = GAMESTATE:GetSortOrder()

	if current == PREFERRED then
		-- already in Favorites: back to whatever was used before
		wheel:ChangeSort(SL.Global.SortBeforeFavorites or "SortOrder_Group")
		return
	end

	local player = FavoritesPlayer()
	if not player then
		SM("No Favorites Available")
		return
	end

	SONGMAN:SetPreferredSongs(getFavoritesPath(player), --[[isAbsolute=]]true)
	if SONGMAN:GetPreferredSortSongs() then
		SL.Global.SortBeforeFavorites = current
		wheel:ChangeSort(PREFERRED)
	else
		SM(ToEnumShortString(player).." has no favorites!")
	end
end

-- -----------------------------------------------------------------------

local InputHandler = function(event)
	if not event or not event.DeviceInput then return false end

	local button = event.DeviceInput.button

	if IsCtrl(button) then
		holdingCtrl = (event.type ~= "InputEventType_Release")
		return false
	end
	if IsShift(button) then
		holdingShift = (event.type ~= "InputEventType_Release")
		return false
	end

	if not (holdingCtrl and IsLetter(button)) then return false end
	if event.type == "InputEventType_Release" then return false end

	-- ctrl+shift+R: engine reload of the current song, hands off
	if holdingShift and button == "DeviceButton_r" then return false end

	-- Undo the engine's letter jump, on repeats too (it reacts to those as well).
	UndoLetterJump()

	if event.type ~= "InputEventType_FirstPress" or GAMESTATE:IsCourseMode() then
		return false
	end

	if button == "DeviceButton_f" then
		ToggleFavoritesSort()

	elseif button == "DeviceButton_r" and ThemePrefs.Get("KeyboardFeatures") then
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
		holdingCtrl, holdingShift = false, false
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
