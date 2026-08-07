local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2

local item_width = _screen.w / 2.125

-- the MusicWheelItem for CourseMode contains the basic colored Quads,
-- use that as a common base
local af = LoadActor("../MusicWheelItem Course NormalPart.lua")

local IsNotWide = (GetScreenAspectRatio() < 16/9)

-- Two right-aligned stacks at the end of the row: EX over ITG score, and -- event packs
-- only -- ITL points over ITL rank (or an SRPG rate). Geometry in
-- Scripts/SL-Helpers-WheelRow.lua, which the song title's maxwidth reads from too.
local cols = WheelRowColumns()

local ITL_ZOOM        = cols.zoom
local ITL_COL_EX      = cols.col_score
local ITL_COL_EVENT   = cols.col_event
local ITL_LABEL_COLOR = cols.label_color

-- The chart a wheel row resolves to: this row's song, at the difficulty and steps type the
-- player currently has selected. Shared by the ITG score column and the EX one below, so
-- the two can never end up describing different charts on the same row.
local function StepsForRow(player, song)
	if not song then return nil end

	local curSteps = GAMESTATE:GetCurrentSteps(player)
	if not curSteps then return nil end

	local difficulty = curSteps:GetDifficulty()
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()

	for check in ivalues(song:GetAllSteps()) do
		if check:GetDifficulty() == difficulty and check:GetStepsType() == steps_type then
			return check
		end
	end
	return nil
end

-- Best ITG percent for a row's song at the difficulty currently selected on the wheel,
-- taking the better of the profile's own passing scores and anything imported from
-- GrooveStats. The wheel only tracks one difficulty at a time, so a row's score is the
-- score on that difficulty's chart -- the same resolution GetLamp.lua does for the clear
-- lamp. Returns nil when there is no profile, no matching chart, or nothing recorded.
local function GetItgPercentForSong(player, song)
	if not song then return nil end
	if not PROFILEMAN:IsPersistentProfile(player) then return nil end

	local steps = StepsForRow(player, song)
	if not steps then return nil end

	-- NOT an early return when there is no local list. A chart you have never played on
	-- this machine is exactly the case an imported GrooveStats score exists to cover, so the
	-- local lookup has to be allowed to come back empty and still fall through to the
	-- online one below.
	local scores = nil
	local list = PROFILEMAN:GetProfile(player):GetHighScoreListIfExists(song, steps)
	if list then scores = list:GetHighScores() end

	-- The best PASSING score, not scores[1].
	--
	-- A failed run is still written to the high score list, so taking the top entry showed
	-- a bailed attempt as the song's score -- right next to the clear lamp, which is
	-- simultaneously reporting that same run as a failure. This profile currently holds
	-- five such entries (three at 0.00% on 3y3s, plus Esperanza, Anubis, Nocturne and one
	-- 39.70% on Young Birds), every one of which printed as that song's ITG score.
	--
	-- The list's own order is not something to lean on here either: it ranks by score, so
	-- a high-percentage fail can sit above a genuine lower pass.
	--
	-- nil when nothing has been passed, which hides the column -- the same as never having
	-- played the chart. An unfinished run is not a score.
	local best = nil
	for score in ivalues(scores or {}) do
		if score:GetGrade() ~= "Grade_Failed" then
			local pct = score:GetPercentDP() * 100
			if best == nil or pct > best then best = pct end
		end
	end

	-- Then the score imported from GrooveStats, if the player has one there. The better of
	-- the two wins, which is how a score set on another machine reaches this row: the theme
	-- cannot write into the profile's own high scores at all, so the two stores are merged
	-- here at draw time instead. See Scripts/SL-Helpers-OnlineScores.lua.
	local online = OnlineScoreField(player, song, steps, "itg")
	if online and (best == nil or online > best) then best = online end

	return best
end

if ThemePrefs.Get("SongSelectBG") ~= "Off" then
	af[#af+1] = Def.Sprite{
		InitCommand=function(self)
			self:horizalign(right):addx(item_width):scaletoclipped(item_width-50, _screen.h/num_visible_items-2):visible(true)
			self:diffusealpha(0.25):fadeleft(1):SetDecodeMovie(false)
		end,
		SetCommand=function(self, params)
			local Song = params.Song
			local Course = params.Course
			local Path = nil
			
			if Song then
				if Song:GetBackgroundPath() ~= nil then
					Path = Song:GetBackgroundPath()
				end
				if Song:GetBannerPath() ~= nil then
					if Path == nil or ThemePrefs.Get("SongSelectBG") == "Banner" then
						Path = Song:GetBannerPath()
					end
				end
					
				if Path ~= nil then
					self:Load( Path ):visible(true)
				else
					self:visible(false)
				end
			elseif Course then
				if Course:GetBackgroundPath() ~= nil then
					Path = Course:GetBackgroundPath()
				end
				if Course:GetBannerPath() ~= nil then
					if Path == nil or ThemePrefs.Get("SongSelectBG") == "Banner" then
						Path = Course:GetBannerPath()
					end
				end
					
				if Path ~= nil then
					self:Load( Path ):visible(true)
				else
					self:visible(false)
				end
			else
				self:visible(false)
			end
		end,
	}
end

-- The "Has Edit" badge that sat here is gone; the title uses that strip now.

for player in ivalues(PlayerNumber) do
	af[#af+1] = LoadActor("GetLamp.lua", player)
	af[#af+1] = LoadActor("Favorites.lua", player)

	-- EX score, top line of the score column (ITG sits below it). Versus stacks P1 above P2
	-- in those same two lines.
	af[#af+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="",
		InitCommand=function(self)
			self:visible(false):horizalign(left)
			self:zoom(ITL_ZOOM)
			self:x( ITL_COL_EX )
			self:diffuse(SL.JudgmentColors["FA+"][player == "PlayerNumber_P1" and 1 or 2])
		end,
		-- Both players actors are always visible now
		-- PlayerJoinedMessageCommand=function(self)
		-- 	--self:visible(GAMESTATE:IsPlayerEnabled(player))
		-- end,
		-- PlayerUnjoinedMessageCommand=function(self)
		-- 	--self:visible(GAMESTATE:IsPlayerEnabled(player))
		-- end,
		SetCommand=function(self, params)
			-- Only display EX score if a profile is found for an enabled player.
			local pn = ToEnumShortString(player)

			-- Kept for the difficulty-change replays below. Stored ahead of the early
			-- returns, so a row that bails out still knows its song next time.
			self.song = params and params.Song

			if GAMESTATE:GetNumSidesJoined() == 1 then
				-- Solo: only the P1 actor draws, reading from whichever side
				-- actually holds the profile. Both actors used to render the same
				-- profile's score, one at y=-10 and one at y=10, so the number
				-- appeared twice. One line only.
				if player ~= PLAYER_1 then self:visible(false) return end

				if PROFILEMAN:IsPersistentProfile(PLAYER_1) then
					pn = "P1"
				elseif PROFILEMAN:IsPersistentProfile(PLAYER_2) then
					pn = "P2"
				else
					self:visible(false)
					return
				end
				self:y(0)
			else
				-- Versus keeps its own stacking: one line per player, and the ITG
				-- score hides itself entirely (it early-outs on #humans ~= 1), so
				-- there is no swap to make here.
				self:visible(PROFILEMAN:IsPersistentProfile(player))
				self:y(player == PLAYER_1 and -10 or 10)
			end

			-- The PlayerNumber matching the pn resolved above. The solo branch picks pn by
			-- which side actually holds the profile, which need not be this actor's own
			-- `player`, and the lookups below take a PlayerNumber rather than a short name.
			local owner = (pn == "P1") and PLAYER_1 or PLAYER_2

			if params.Song ~= nil then
				local song = params.Song
				local song_dir = song:GetSongDir()
				if song_dir ~= nil and #song_dir ~= 0 then
					if SL[pn].ITLData["pathMap"][song_dir] ~= nil then
						local hash = SL[pn].ITLData["pathMap"][song_dir]
						if SL[pn].ITLData["hashMap"][hash] ~= nil then
							-- Always the EX score here; points now live in the dedicated,
							-- rank-tier-colored event column to the left.
							--
							-- ITL wins over the theme's own record when both exist: it is
							-- the figure the event itself scored you on, and it is what the
							-- points and rank on the same row were computed from.
							local ex = ("%.2f"):format(SL[pn].ITLData["hashMap"][hash]["ex"] / 100)
							self:settext(ex .. " EX")
							self:AddAttribute(#ex, { Length=3, Diffuse=ITL_LABEL_COLOR })
							self:visible(true)
							return
						end
					end
				end

				-- No ITL entry, so fall back to the EX this theme recorded itself. This is
				-- what makes the column appear on every song rather than only inside an ITL
				-- pack; see Scripts/SL-Helpers-ExScores.lua for why it has to be recorded at
				-- play time instead of derived from the saved score here.
				-- Two sources, better wins: the EX this theme recorded when you played the
				-- chart here, and the EX imported from GrooveStats for a run you set
				-- elsewhere. Both are keyed the same way, so this costs one extra table
				-- lookup per row.
				local steps = StepsForRow(owner, song)
				local ex = steps and ExScoreGet(owner, song, steps)
				local online_ex = steps and OnlineScoreField(owner, song, steps, "ex")
				if online_ex and (ex == nil or online_ex > ex) then ex = online_ex end
				if ex then
					local val = ("%.2f"):format(ex)
					self:settext(val .. " EX")
					self:AddAttribute(#val, { Length=3, Diffuse=ITL_LABEL_COLOR })
					self:visible(true)
					return
				end
			end
			self:visible(false)
		end,
		-- The chart this column describes now depends on the selected difficulty, because
		-- the fallback resolves a chart through StepsForRow. The ITL branch never needed
		-- this -- its hashMap is keyed by song directory alone -- so the actor had no
		-- refresh at all and would have kept showing the previous difficulty's EX.
		-- Both sides are handled because solo can be played from either.
		CurrentStepsP1ChangedMessageCommand=function(self)
			self:playcommand("Set", { Song=self.song })
		end,
		CurrentStepsP2ChangedMessageCommand=function(self)
			self:playcommand("Set", { Song=self.song })
		end,
		-- A score just arrived from GrooveStats for this row's song. Same shape as the
		-- ITLRankResolved handler further down: an async fetch lands after the row was
		-- drawn, so the row redraws itself rather than waiting for the next selection.
		OnlineScoresUpdatedMessageCommand=function(self, params)
			if params and params.Song == self.song then
				self:playcommand("Set", { Song=self.song })
			end
		end,
	}
	--[[ Song Rank (local top-N rank among this profile's ITL songs).
	-- Superseded by the global ITL rank + points display below; kept here
	-- commented out in case we want to bring it back.
	af[#af+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small" or "Mega/_mega font",
		Text="",
		InitCommand=function(self)
			self:visible(false)
			if IsNotWide then
				self:zoom(0.2)
			else
				self:zoom(0.3)
			end

		end,
		PlayerJoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		PlayerUnjoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		SetCommand=function(self, params)
			-- Only display EX score if a profile is found for an enabled player.
			if not GAMESTATE:IsPlayerEnabled(player) or not PROFILEMAN:IsPersistentProfile(player) then
				self:visible(false)
				return
			end

			local pn = ToEnumShortString(player)

			self:x(THEME:GetMetric("MusicWheelItem", "GradeP"..(pn == "P1" and 2 or 1).."X")-WideScale(28,33))

			if params.Song ~= nil and GAMESTATE:GetNumSidesJoined() == 1 then
				local song = params.Song
				local song_dir = song:GetSongDir()
				if song_dir ~= nil and #song_dir ~= 0 then
					if SL[pn].ITLData["pathMap"][song_dir] ~= nil then
						local hash = SL[pn].ITLData["pathMap"][song_dir]
						if SL[pn].ITLData["hashMap"][hash] ~= nil then
							if SL[pn].ITLData["hashMap"][hash]["rank"] ~= nil then
								if SL[pn].ITLData["hashMap"][hash]["rank"] ~= nil then
									local rank = SL[pn].ITLData["hashMap"][hash]["rank"]

									self:settext(tostring(rank))
									local style = GAMESTATE:GetCurrentStyle():GetName()
									if 		rank <=	(style == "single" and 10 or 5) 	then self:diffuse(SL.JudgmentColors["FA+"][1])
									elseif	rank <= (style == "single" and 25 or 20)	then self:diffuse(SL.JudgmentColors["FA+"][2])
									elseif	rank <= (style == "single" and 50 or 40) 	then self:diffuse(SL.JudgmentColors["FA+"][3])
									elseif	rank <= (style == "single" and 75 or 50) 	then self:diffuse(SL.JudgmentColors["FA+"][4])
									elseif	rank <= (style == "single" and 85 or 55)	then self:diffuse(SL.JudgmentColors["FA+"][5])
									else self:diffuse(Color.Red)
									end
								end
							end
							self:visible(true)
							return
						end
					end
				end
			end
			self:visible(false)
		end,
	}
	]]

end

-- Global ITL points, top line of the event column (the ITL rank sits below it). Solo,
-- persistent-profile player only. Color-coded by the song's LOCAL top-N standing
-- (green = top75, yellow = top150, white otherwise).
af[#af+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text="",
	InitCommand=function(self)
		self:visible(false):horizalign(right):zoom(ITL_ZOOM):y(0)
		self:x( ITL_COL_EVENT )
		self.hash = nil
	end,
	SetCommand=function(self, params)
		self:visible(false)
		self.hash = nil

		-- Same gate the title's maxwidth uses: on a row it turns down, the title has
		-- already been widened across this column, so nothing may draw here.
		if not WheelRowHasEventColumn(params.Song) then return end

		local player = GAMESTATE:GetHumanPlayers()[1]
		local pn = ToEnumShortString(player)

		-- An SRPG pack takes this column over entirely: no ITL hash is resolved, so no
		-- rank is fetched for a song that has no ITL standing to fetch.
		local event = params.Song and SRPGEventFromGroupName( params.Song:GetGroupName() )
		if event then
			self:playcommand("SetRate", { player=player, song=params.Song, event=event })
			return
		end

		-- Resolves from pathMap, or computes+caches the hash on the fly if this
		-- row's song has never been visited/fetched before (see
		-- Scripts/SL-Helpers-ITLRank.lua). Gives on-screen songs priority over
		-- the background prefetcher in ITLRankManager.lua.
		local hash = ITLResolveHashForSong(pn, params.Song)
		if not hash then return end
		self.hash = hash
		self.song = params.Song

		self:playcommand("RefreshPoints")
	end,
	-- Points come from local data only (see ITLGetPoints) so they render right
	-- away; no need to wait on the leaderboard fetch, which is only for ranks.
	-- Stamina RPG packs are scored on the highest music rate you have cleared a chart at,
	-- not on ITL points, so in one of those this column carries the rate instead. It is
	-- the same column rather than a number of its own: the two events never overlap on a
	-- pack, and a row has one slot for "how am I doing on this chart in the event".
	--
	-- This replaces Graphics/MusicWheelItem RPGRate.lua, which drew the figure separately
	-- at hand-tuned per-aspect-ratio coordinates and re-read the whole .rpg file from disk
	-- on every row of every scroll tick.
	SetRateCommand=function(self, params)
		self:visible(false)

		local rate = SRPGBestRate(params.player, params.song, params.event)
		if not rate then return end

		local val = ("%.2f"):format(rate)
		self:settext( val .. "x RATE" )
		self:AddAttribute(#val + 1, { Length=5, Diffuse=ITL_LABEL_COLOR })
		-- white at 1.0x through to red at 1.5x, the ramp the old actor used
		local heat = clamp(scale(rate, 1.0, 1.5, 1, 0), 0, 1)
		self:diffuse(1, heat, heat, 1)
		self:visible(true)
	end,

	RefreshPointsCommand=function(self)
		self:visible(false)
		if not self.hash then return end

		local humans = GAMESTATE:GetHumanPlayers()
		if #humans ~= 1 then return end
		local pn = ToEnumShortString(humans[1])

		local points = ITLGetPoints(pn, self.song, self.hash)
		if points == 0 then return end

		local localRank = SL[pn].ITLData["hashMap"][self.hash]["rank"]
		if type(localRank) == "number" and localRank <= 75 then
			self:diffuse(Color.Green)
		elseif type(localRank) == "number" and localRank <= 150 then
			self:diffuse(Color.Yellow)
		else
			self:diffuse(Color.White)
		end
		local val = tostring(points)
		self:settext( val .. " PTS" )
		self:AddAttribute(#val, { Length=4, Diffuse=ITL_LABEL_COLOR })
		self:visible(true)
	end,
	-- A fetch can raise our EX (and so our points) for this chart; re-read.
	ITLRankResolvedMessageCommand=function(self, params)
		if self.hash and params.hash == self.hash then
			self:playcommand("RefreshPoints")
		end
	end,
}

-- ITG score, sitting directly BELOW the EX score in the same right-hand column.
-- Unlike points/rank/EX this is not ITL data: it is the profile's own best
-- PercentDP on the row's chart, so it shows on every song, ITL pack or not.
af[#af+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text="",
	Name="ITGScore",
	InitCommand=function(self)
		self:visible(false):horizalign(left):zoom(ITL_ZOOM):y(10)
		self:x( ITL_COL_EX )
		self:diffuse(Color.White)
	end,
	SetCommand=function(self, params)
		self:visible(false)
		self.song = params.Song

		local humans = GAMESTATE:GetHumanPlayers()
		if #humans ~= 1 then return end

		local percent = GetItgPercentForSong(humans[1], params.Song)
		if not percent then return end

		local val = ("%.2f"):format(percent)
		self:settext( val .. " ITG" )
		self:AddAttribute(#val, { Length=4, Diffuse=ITL_LABEL_COLOR })
		self:visible(true)
	end,
	-- the wheel keeps one difficulty selected at a time, so every row's score
	-- changes when the player switches difficulty. Both sides are handled
	-- because solo can be played on either.
	CurrentStepsP1ChangedMessageCommand=function(self)
		self:playcommand("Set", { Song=self.song })
	end,
	CurrentStepsP2ChangedMessageCommand=function(self)
		self:playcommand("Set", { Song=self.song })
	end,
	-- See the EX column above: an imported score lands after the row was drawn, so the
	-- row redraws instead of waiting for the selection to move.
	OnlineScoresUpdatedMessageCommand=function(self, params)
		if params and params.Song == self.song then
			self:playcommand("Set", { Song=self.song })
		end
	end,
}

af[#af+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text="",
	Name="ITLGlobalRank",
	InitCommand=function(self)
		-- bottom line of the event column, under the points
		self:visible(false):horizalign(right):zoom(ITL_ZOOM):y(10)
		self:x( ITL_COL_EVENT )
		self.hash = nil
	end,
	SetCommand=function(self, params)
		self:visible(false)
		self.hash = nil

		-- See the points column above: same gate, same reason.
		if not WheelRowHasEventColumn(params.Song) then return end

		local player = GAMESTATE:GetHumanPlayers()[1]
		local pn = ToEnumShortString(player)

		-- An SRPG song has no ITL standing, so don't resolve a hash for it and above all
		-- don't enqueue a leaderboard fetch that can only come back empty. ITLRankManager
		-- is rate-limited and backs off on HTTP 429; feeding it songs from the wrong event
		-- would spend that budget for nothing.
		if params.Song and SRPGEventFromGroupName( params.Song:GetGroupName() ) then return end

		local hash = ITLResolveHashForSong(pn, params.Song)
		if not hash then return end
		self.hash = hash

		local rank = ITLRankGet(hash)
		if type(rank) == "number" then
			self:playcommand("ShowRank", { rank=rank })
		elseif rank == false then
			self:visible(false)
		else
			-- not fetched yet: ask the manager, but only if it can actually fetch
			-- (mirror ITLRankManager's gate) so we don't accumulate hashes that
			-- will never be drained. Updates arrive via ITLRankResolved.
			if SL[pn].ApiKey ~= "" and IsServiceAllowed(SL.GrooveStats.GetScores) then
				ITLRankEnqueue(hash)
			end
		end
	end,
	ShowRankCommand=function(self, params)
		local val = ITLRankOrdinal(params.rank)
		self:settext( val .. " ITL" ):diffuse(ITLRankColor(params.rank))
		self:AddAttribute(#val, { Length=4, Diffuse=ITL_LABEL_COLOR })
		self:visible(true)
	end,
	ITLRankResolvedMessageCommand=function(self, params)
		if self.hash and params.hash == self.hash then
			local rank = ITLRankGet(self.hash)
			if type(rank) == "number" then
				self:playcommand("ShowRank", { rank=rank })
			else
				self:visible(false)
			end
		end
	end,
}

return af