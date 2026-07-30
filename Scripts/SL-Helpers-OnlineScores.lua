-- Scores pulled down from GrooveStats for charts this machine has never seen you play.
--
-- WHY A THEME-SIDE STORE AND NOT THE PROFILE. Lua cannot write a score into a profile.
-- Profile exposes only readers to Lua (GetHighScoreListIfExists, GetHighScoreList,
-- GetCategoryHighScoreList), every method bound on HighScore is a getter, and
-- Profile::AddStepsHighScore is never given an ADD_METHOD. So "overwrite the value in the
-- profile" is not something a theme can do at all -- it would take an engine change. This
-- keeps its own file instead and the wheel takes the better of the two when it draws, which
-- reaches the same visible answer without pretending to be an engine score. These will
-- therefore never show up in machine records or engine leaderboards.
--
-- WHEN IT FILLS. Not by sweeping the library: player-scores.php and player-leaderboards.php
-- each take ONE chart hash per player per request, and a hash costs a full simfile parse,
-- so a 6500-song library would mean tens of thousands of parses and requests against an API
-- that rate-limits. Instead this rides the request the wheel ALREADY makes when you select
-- a song -- the hash is already computed and the response already fetched, so importing
-- costs nothing extra on top of what the scorebox was doing anyway.
--
-- PASSES ONLY. The capture in ScreenSelectMusic's Scorebox drops any leaderboard entry
-- flagged isFail before it gets here, so the mere presence of an entry means the run was
-- passed. Three tallies now lean on that invariant -- the folder progress, the player
-- card's cleared count and the wheel's clear lamp -- so nothing may ever record a failed
-- run here without giving them a way to tell the difference.
--
-- HASH EXACTNESS is not our own check: the callers only reach this after comparing the
-- response's chartHash against the locally parsed one and bailing out otherwise, which is
-- what stops two different charts that merely share a title from being confused. The hash
-- is stored alongside the score as a record of what was verified at write time.
--
-- Keys match Scripts/SL-Helpers-ExScores.lua (ExScoreKey is reused verbatim) so a wheel row
-- resolves both stores with one identity and no extra work while scrolling.
--
-- NOTE: loaded before SL_Init.lua, so nothing here may touch SL at load time.

local FILENAME = "OnlineScores.json"

local PROFILE_SLOT = {
	[PLAYER_1] = "ProfileSlot_Player1",
	[PLAYER_2] = "ProfileSlot_Player2",
}

local function PathFor(player)
	local dir = PROFILEMAN:GetProfileDir(PROFILE_SLOT[player])
	if not dir or #dir == 0 then return nil end
	return dir .. FILENAME
end

OnlineScoresInit = function(player)
	local pn = ToEnumShortString(player)
	SL[pn].OnlineScores = SL[pn].OnlineScores or {}
end

-- Call AFTER SL[pn]:initialize(), which would otherwise wipe what this fills.
OnlineScoresRead = function(player)
	local pn = ToEnumShortString(player)
	SL[pn].OnlineScores = {}

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

	-- pcall: this file lives in the profile where it can be hand-edited or truncated, and a
	-- decode error would otherwise take the whole profile load down with it.
	local ok, data = pcall(JsonDecode, existing)
	if ok and type(data) == "table" then
		SL[pn].OnlineScores = data
	end
end

OnlineScoresWrite = function(player)
	local pn = ToEnumShortString(player)
	local data = SL[pn].OnlineScores
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

-- The stored entry for a chart, or nil. Shape: { itg=<percent>, ex=<percent>, hash=<string> }
OnlineScoreGet = function(player, song, steps)
	local pn = ToEnumShortString(player)
	local data = SL[pn].OnlineScores
	if not data then return nil end

	local key = ExScoreKey(song, steps)
	if not key then return nil end

	local entry = data[key]
	return type(entry) == "table" and entry or nil
end

-- One field of it, guarded, since the file is user-editable and these values reach a
-- "%.2f" format on the wheel.
OnlineScoreField = function(player, song, steps, field)
	local entry = OnlineScoreGet(player, song, steps)
	if not entry then return nil end
	local v = entry[field]
	return type(v) == "number" and v or nil
end

-- Has this chart been passed according to what we imported? See the PASSES ONLY note at
-- the top: an entry only exists for a run that was passed, so this is simply "is there
-- one, and does it carry a figure".
OnlineScorePassed = function(player, song, steps)
	local entry = OnlineScoreGet(player, song, steps)
	if not entry then return false end
	return type(entry.itg) == "number" or type(entry.ex) == "number"
end

-- Record one figure for a chart, keeping the best. `field` is "itg" or "ex", `percent` is
-- already divided down from the API's integer form (9823 -> 98.23). `hash` is the verified
-- chart hash, stored as the record of what the caller matched on.
--
-- Returns true when something actually changed, so callers can skip a disk write.
OnlineScoreRecord = function(player, song, steps, field, percent, hash)
	if type(percent) ~= "number" then return false end
	if field ~= "itg" and field ~= "ex" then return false end

	local key = ExScoreKey(song, steps)
	if not key then return false end

	OnlineScoresInit(player)
	local pn = ToEnumShortString(player)

	local entry = SL[pn].OnlineScores[key]
	if type(entry) ~= "table" then
		entry = {}
		SL[pn].OnlineScores[key] = entry
	end

	entry.hash = hash or entry.hash

	local prev = entry[field]
	if type(prev) == "number" and prev >= percent then return false end

	entry[field] = percent
	return true
end
