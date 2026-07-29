local player = ...
local pn = ToEnumShortString(player)

local year = Year()
local month = MonthOfYear()+1
local day = DayOfMonth()

local IsEventActive = function()
	-- The file is only written to while the event is active.
	-- These are just placeholder dates.
	local startTimestamp = 202406017
	local endTimestamp = 20250301

	local today = year * 10000 + month * 100 + day

	return startTimestamp <= today and today <= endTimestamp
end

local style = GAMESTATE:GetCurrentStyle()
local game = GAMESTATE:GetCurrentGame()

if (SL.Global.GameMode == "Casual" or
		GAMESTATE:IsCourseMode() or
		--not IsEventActive() or -- This event lasts forever it seems, lol
		game:GetName() ~= "dance" or
		(style:GetName() ~= "single" and style:GetName() ~= "versus")) then
	return
end

-- Reading the file, writing it, and working out which event a pack belongs to all live in
-- Scripts/SL-Helpers-SRPG.lua now. This file used to carry its own copy of the format and
-- its own hardcoded "STAMINA RPG 8" / "SRPG8.rpg", while the song wheel carried a second
-- copy of both -- so supporting a new season meant editing two files in step, and the
-- write path corrupted any song whose key was a substring of another's.

local t = Def.ActorFrame {
	OnCommand=function(self)
		local song = GAMESTATE:GetCurrentSong()
		if not song then return end

		local event = SRPGEventFromGroupName( song:GetGroupName() )
		if not event then return end

		local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)

		-- Do the same validation as GrooveStats.
		-- This checks important things like timing windows, addition/removal of arrows, etc.
		local _, valid = ValidForGrooveStats(player)

		-- Get the rate mod
		local so = GAMESTATE:GetSongOptionsObject("ModsLevel_Song")
		local rate = so:MusicRate()

		if (GAMESTATE:IsHumanPlayer(player) and
			valid and
			rate >= 1.0 and
			not stats:GetFailed()) then

			-- no-ops unless this beats what is stored, and requires a persistent profile
			SRPGRecordRate(player, song, event, rate)
		end
	end
}

return t