-- Ctrl+Shift+R on ScreenEvaluation: resync the just-played song's #OFFSET to
-- cancel the (solo) player's systematic timing bias — their signed mean offset.
-- The math + file IO live in ResyncSongOffsetFromMean() (Scripts/SL-Helpers.lua);
-- this actor wires up the hotkey (solo only, KeyboardFeatures, not course mode)
-- and renders a brief confirmation of the old/new sync and the applied shift.

local Players = GAMESTATE:GetHumanPlayers()

-- Solo-only: the file #OFFSET is a single global value, so only allow this when
-- exactly one human player is joined; that player's mean drives the resync.
local player = (#Players == 1) and Players[1] or nil

-- modifier state for the Ctrl+Shift+R combo, plus a debounce while feedback shows
local holdingCtrl  = false
local holdingShift = false
local busy = false

local ResyncInputHandler = function(event)
	if not event or not player then return end

	if event.type == "InputEventType_FirstPress" then
		local btn = event.DeviceInput.button
		if btn == "DeviceButton_left ctrl" or btn == "DeviceButton_right ctrl" then
			holdingCtrl = true
		elseif btn == "DeviceButton_left shift" or btn == "DeviceButton_right shift" then
			holdingShift = true
		elseif btn == "DeviceButton_r" then
			if holdingCtrl and holdingShift and not busy then
				busy = true
				local result, reason = ResyncSongOffsetFromMean(player)
				MESSAGEMAN:Broadcast("SongResynced", { result=result, reason=reason })
			end
		end

	elseif event.type == "InputEventType_Release" then
		local btn = event.DeviceInput.button
		if btn == "DeviceButton_left ctrl" or btn == "DeviceButton_right ctrl" then
			holdingCtrl = false
		elseif btn == "DeviceButton_left shift" or btn == "DeviceButton_right shift" then
			holdingShift = false
		end
	end
end

local NormalFont = ThemePrefs.Get("ThemeFont") .. " Normal"
local BoldFont   = ThemePrefs.Get("ThemeFont") .. " Bold"
local ERROR_COLOR = color("#ffb266")
local LATER_COLOR = color("#89ffa2")

local t = Def.ActorFrame{
	Name="ResyncHandler",
	OnCommand=function(self)
		if player
		and ThemePrefs.Get("KeyboardFeatures")
		and not GAMESTATE:IsCourseMode() then
			SCREENMAN:GetTopScreen():AddInputCallback(ResyncInputHandler)
		end
	end,
}

-- feedback overlay: hidden until a resync is attempted, then shown ~4s and faded
t[#t+1] = Def.ActorFrame{
	Name="ResyncFeedback",
	InitCommand=function(self)
		self:xy(_screen.cx, _screen.cy):draworder(200):visible(false):diffusealpha(0)
	end,
	SongResyncedMessageCommand=function(self)
		self:stoptweening():visible(true):diffusealpha(0)
		self:linear(0.15):diffusealpha(1):sleep(4):linear(0.3):diffusealpha(0):queuecommand("Hide")
	end,
	HideCommand=function(self)
		self:visible(false)
		busy = false
	end,

	-- backdrop
	Def.Quad{
		InitCommand=function(self) self:zoomto(380, 104):diffuse(color("#101519")):diffusealpha(0.92) end
	},

	-- title / error line
	LoadFont(BoldFont)..{
		InitCommand=function(self) self:y(-32):zoom(0.55) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				self:settext(THEME:GetString("ScreenEvaluation", "SongResynced")):diffuse(Color.White)
			else
				local key = (params.reason == "no-data" and "SongResyncNoData")
						or (params.reason == "no-song" and "SongResyncNoSong")
						or "SongResyncWriteFailed"
				self:settext(THEME:GetString("ScreenEvaluation", key)):diffuse(ERROR_COLOR)
			end
		end,
	},

	-- old -> new offset line
	LoadFont(NormalFont)..{
		InitCommand=function(self) self:y(-8):zoom(0.5) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				self:settext(THEME:GetString("ScreenEvaluation", "SongResyncOffset"):format(params.result.old, params.result.new))
			else
				self:settext("")
			end
		end,
	},

	-- applied shift line (colored: green = later, orange = earlier)
	LoadFont(NormalFont)..{
		InitCommand=function(self) self:y(14):zoom(0.6) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				local word = THEME:GetString("ScreenEvaluation",
					params.result.direction == "later" and "SongResyncLater" or "SongResyncEarlier")
				self:settext(THEME:GetString("ScreenEvaluation", "SongResyncShift"):format(math.abs(params.result.delta * 1000), word))
				self:diffuse(params.result.direction == "later" and LATER_COLOR or ERROR_COLOR)
			else
				self:settext("")
			end
		end,
	},

	-- mean recap line
	LoadFont(NormalFont)..{
		InitCommand=function(self) self:y(34):zoom(0.42):diffuse(color("#888888")) end,
		SongResyncedMessageCommand=function(self, params)
			if params.result then
				self:settext(THEME:GetString("ScreenEvaluation", "SongResyncMean"):format(params.result.mean_ms))
			else
				self:settext("")
			end
		end,
	},
}

return t
