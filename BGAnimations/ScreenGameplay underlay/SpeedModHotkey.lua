-- BGAnimations/ScreenGameplay underlay/SpeedModHotkey.lua
-- ctrl+Up / ctrl+Down nudges the active speedmod (XMod/MMod/CMod) up or
-- down in real time while notes are already scrolling. Restricted to
-- EventMode, mirroring the ctrl+R restart hotkey in ./default.lua.

local increment = {
	XMod = 0.05,
	MMod = 5,
	CMod = 5,
}

local upper_limit = {
	XMod = 10,
	MMod = 2000,
	CMod = 2000,
}

local fmt = {
	XMod = "mod,%.2fx",
	MMod = "mod,m%d",
	CMod = "mod,c%d",
}

local holdingCtrl = false

local AdjustSpeedMod = function(player, direction)
	local playeroptions = GAMESTATE:GetPlayerState(player):GetPlayerOptions('ModsLevel_Song')
	if playeroptions == nil then return end

	local xmod = playeroptions:XMod()
	local mmod = playeroptions:MMod()
	local cmod = playeroptions:CMod()

	local speedmod     = (cmod ~= nil and cmod)   or (mmod ~= nil and mmod)   or (xmod ~= nil and xmod)
	local speedmod_str = (cmod ~= nil and "CMod") or (mmod ~= nil and "MMod") or (xmod ~= nil and "XMod")

	if speedmod == nil or speedmod_str == nil then return end

	if direction == "up" then
		if speedmod + increment[speedmod_str] <= upper_limit[speedmod_str] then
			speedmod = speedmod + increment[speedmod_str]
		end
	else
		if speedmod - increment[speedmod_str] > 0 then
			speedmod = speedmod - increment[speedmod_str]
		end
	end

	-- update SL table with new speed, same as SL-PlayerOptions.lua's MenuLeft/MenuRight handler
	SL[ToEnumShortString(player)].ActiveModifiers.SpeedMod = speedmod

	-- format a GameCommand string like "mod,1.75x" or "mod,c460" or "mod,m900"
	local gcString = fmt[speedmod_str]:format(speedmod)

	-- apply the new speed mod to the player immediately
	GAMESTATE:ApplyGameCommand(gcString, player)

	-- broadcast which player's mods changed so that ScreenGameplay's DisplayMods.lua
	-- can update its BitmapText string to show the player updated text
	MESSAGEMAN:Broadcast("PlayerOptionsChanged", {Player=player})
end

local InputHandler = function(event)
	if not event or not event.DeviceInput then return false end

	if event.DeviceInput.button == "DeviceButton_left ctrl" then
		holdingCtrl = (event.type ~= "InputEventType_Release")
		return false
	end

	if event.type ~= "InputEventType_FirstPress" then return false end
	if not holdingCtrl then return false end

	local direction
	if event.DeviceInput.button == "DeviceButton_up" then
		direction = "up"
	elseif event.DeviceInput.button == "DeviceButton_down" then
		direction = "down"
	else
		return false
	end

	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		AdjustSpeedMod(player, direction)
	end

	return false
end

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
