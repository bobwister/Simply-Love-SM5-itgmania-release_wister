-- Per-profile EX scores for every chart, not just the ITL ones.
--
-- WHY THIS FILE HAS TO EXIST. An EX score cannot be recomputed from a stored HighScore.
-- The calculation needs the W0/W1 split -- Fantastic+ at 15ms as against Fantastic -- and
-- the engine's HighScore keeps a single TapNoteScore_W1 bucket with no way to tell the two
-- apart. That split exists only live, during gameplay, where
-- BGAnimations/ScreenGameplay overlay/TrackExScoreJudgments.lua counts it; even
-- Scripts/SL-CustomScores.lua flattens it back into one W1 number when it writes its own
-- files. So an EX score has to be captured at the moment it is earned or it is gone for
-- good. CalculateExScore compounds this: it reads radar totals off
-- GAMESTATE:GetCurrentSteps, so it is written for the stage being played, not for an
-- arbitrary row of the wheel.
--
-- ITL already does exactly this into its own hashMap, which is why an ITL song could show
-- an EX in the wheel and nothing else could. This is the same trick generalised: one small
-- file per profile, written at evaluation. It follows ITL's file conventions on purpose --
-- RageFile plus JsonEncode, keyed off PROFILEMAN:GetProfileDir, Close() then destroy()
-- outside the guard -- so the two behave alike around memory cards and profile switches.
--
-- CHARTS ARE KEYED by song directory + steps type + difficulty, not by chart hash. That is
-- precisely how the wheel already resolves a row to a chart (see GetItgPercentForSong in
-- Graphics/MusicWheelItem Song NormalPart/default.lua), so a lookup costs nothing while
-- scrolling. Hashing every visible row instead would cost far more than the feature is
-- worth -- and note ITL only affords hashes by keeping a pathMap to dodge the same problem.
-- The trade is that moving a song's folder loses its EX, which is the cheaper failure.
--
-- LIMIT, worth stating plainly: this can only ever know about runs played after it was
-- added. Existing history cannot be backfilled, for the reason in the first paragraph.
--
-- NOTE: this Scripts file is loaded before SL_Init.lua, so nothing here may touch SL at
-- load time. Every function below runs later, from a profile hook or an actor command.

local FILENAME = "ExScores.json"

local PROFILE_SLOT = {
	[PLAYER_1] = "ProfileSlot_Player1",
	[PLAYER_2] = "ProfileSlot_Player2",
}

local function PathFor(player)
	local dir = PROFILEMAN:GetProfileDir(PROFILE_SLOT[player])
	-- An explicit profile is required; a guest has nowhere to write.
	if not dir or #dir == 0 then return nil end
	return dir .. FILENAME
end

-- A song directory already ends in a slash and the two enum strings cannot contain "|",
-- so no two distinct charts can produce the same key.
ExScoreKey = function(song, steps)
	if not song or not steps then return nil end
	local dir = song:GetSongDir()
	if not dir or #dir == 0 then return nil end
	return dir .. "|" .. steps:GetStepsType() .. "|" .. steps:GetDifficulty()
end

ExScoresInit = function(player)
	local pn = ToEnumShortString(player)
	SL[pn].ExScores = SL[pn].ExScores or {}
end

-- Call AFTER SL[pn]:initialize(), which would otherwise wipe the table -- the same
-- ordering constraint ReadItlFile has in LoadProfileCustom.
ExScoresRead = function(player)
	local pn = ToEnumShortString(player)
	SL[pn].ExScores = {}

	local path = PathFor(player)
	if not path or not FILEMAN:DoesFileExist(path) then return end

	local f = RageFileUtil:CreateRageFile()
	local existing = ""
	if f:Open(path, 1) then
		existing = f:Read()
		f:Close()
	end
	f:destroy()

	if existing == "" then return end

	-- pcall because this file sits in the profile where a player can edit or truncate it,
	-- and a JsonDecode error here would otherwise take the whole profile load down with it.
	local ok, data = pcall(JsonDecode, existing)
	if ok and type(data) == "table" then
		SL[pn].ExScores = data
	end
end

ExScoresWrite = function(player)
	local pn = ToEnumShortString(player)
	local data = SL[pn].ExScores
	-- Nothing recorded yet: leave the profile alone rather than writing "{}" into it.
	if not data or next(data) == nil then return end

	local path = PathFor(player)
	if not path then return end

	local f = RageFileUtil:CreateRageFile()
	if f:Open(path, 2) then
		f:Write(JsonEncode(data))
		f:Close()
	end
	f:destroy()
end

-- Best EX on one chart, as a percent number (92.67), or nil if never recorded.
ExScoreGet = function(player, song, steps)
	local pn = ToEnumShortString(player)
	local data = SL[pn].ExScores
	if not data then return nil end

	local key = ExScoreKey(song, steps)
	if not key then return nil end

	local ex = data[key]
	-- Guarded because the file is user-editable, and a string here would reach a "%.2f"
	-- format further down the line.
	return type(ex) == "number" and ex or nil
end

-- Keeps the best of what is stored and what was just played. Returns true when the stored
-- value actually changed, so callers can skip a disk write.
ExScoreRecord = function(player, song, steps, ex)
	if type(ex) ~= "number" then return false end

	local key = ExScoreKey(song, steps)
	if not key then return false end

	ExScoresInit(player)
	local pn = ToEnumShortString(player)

	local prev = SL[pn].ExScores[key]
	if type(prev) == "number" and prev >= ex then return false end

	SL[pn].ExScores[key] = ex
	return true
end
