local num_items = THEME:GetMetric("MusicWheel", "NumWheelItems")
-- subtract 2 from the total number of MusicWheelItems
-- one MusicWheelItem will be offsceen above, one will be offscreen below
local num_visible_items = num_items - 2

local item_width = _screen.w / 2.125

-- the MusicWheelItem for CourseMode contains the basic colored Quads
-- use that as a common base, and add in a Sprite for "Has Edit"
local af = LoadActor("../MusicWheelItem Course NormalPart.lua")

local stepstype = GAMESTATE:GetCurrentStyle():GetStepsType()

local IsNotWide = (GetScreenAspectRatio() < 16/9)

-- Right-aligned data columns at the end of each row, reading left to right:
-- points, global ITL rank, EX score.
--
-- The row plate spans 0 .. item_width from the frame origin, so anchoring to
-- item_width puts the group hard against the row's right edge instead of
-- leaving the ~36px of dead margin the old _screen.w/2.14 anchor did.
--
-- TWEAK: ITL_ZOOM is the size of these numbers. Enlarging them eats into the
-- song title, whose maxwidth is set in metrics.ini under [TextBanner] and has
-- to stay clear of ITL_BLOCK_LEFT below -- the two are a trade-off.
local ITL_ZOOM = 0.28
local ITL_ANCHOR   = item_width - 14
local ITL_COL_EX   = ITL_ANCHOR
local ITL_COL_RANK = ITL_ANCHOR - 38
local ITL_COL_PTS  = ITL_ANCHOR - 80
-- Left edge of the whole group, i.e. where the title has to stop.
local ITL_BLOCK_LEFT = ITL_COL_PTS - 40
-- Dim gray for the "PTS"/"ITL"/"EX" micro-labels, matching the leading-zero
-- treatment already used on the evaluation screen.
local ITL_LABEL_COLOR = color("#5A6166")

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

-- using a png in a Sprite ties the visual to a specific rasterized font (currently Miso),
-- but Sprites are cheaper than BitmapTexts, so we should use them where dynamic text is not needed
af[#af+1] = Def.Sprite{
	Texture=THEME:GetPathG("", "Has Edit (doubleres).png"),
	InitCommand=function(self)
		-- sits immediately left of the points/rank/EX group, which now runs to
		-- the row's right edge
		self:horizalign(right):visible(false):zoom(0.375)
		self:x( ITL_BLOCK_LEFT - 6 )

		if DarkUI() then self:diffuse(0,0,0,1) end
	end,
	SetCommand=function(self, params)
		self:visible(params.Song and params.Song:HasEdits(stepstype) or false)
	end
}

for player in ivalues(PlayerNumber) do
	af[#af+1] = LoadActor("GetLamp.lua", player)
	af[#af+1] = LoadActor("Favorites.lua", player)

	-- EX score column at the end of the row. Solo draws one line level with the
	-- points/rank columns; versus stacks P1 above P2.
	af[#af+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="",
		InitCommand=function(self)
			self:visible(false):horizalign(right)
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

			if GAMESTATE:GetNumSidesJoined() == 1 then
				-- Solo: only the P1 actor draws, reading from whichever side
				-- actually holds the profile. Both actors used to render the same
				-- profile's score, one at y=-7 and one at y=7, so the number
				-- appeared twice. One line, level with the points/rank columns.
				if player ~= PLAYER_1 then self:visible(false) return end

				if PROFILEMAN:IsPersistentProfile(PLAYER_1) then
					pn = "P1"
				elseif PROFILEMAN:IsPersistentProfile(PLAYER_2) then
					pn = "P2"
				else
					self:visible(false)
					return
				end
				self:y(7)
			else
				self:visible(PROFILEMAN:IsPersistentProfile(player))
				self:y(player == PLAYER_1 and -7 or 7)
			end

			if params.Song ~= nil then
				local song = params.Song
				local song_dir = song:GetSongDir()
				if song_dir ~= nil and #song_dir ~= 0 then
					if SL[pn].ITLData["pathMap"][song_dir] ~= nil then
						local hash = SL[pn].ITLData["pathMap"][song_dir]
						if SL[pn].ITLData["hashMap"][hash] ~= nil then
							-- Always the EX score here; points now live in the dedicated,
							-- rank-tier-colored points/rank subtitle line below.
							local ex = ("%.2f"):format(SL[pn].ITLData["hashMap"][hash]["ex"] / 100)
							self:settext(ex .. " EX")
							self:AddAttribute(#ex, { Length=3, Diffuse=ITL_LABEL_COLOR })
							self:visible(true)
							return
						end
					end
				end
			end
			self:visible(false)
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

-- Global ITL points + global ITL rank, as a subtitle line reading (left to
-- right) "points, rank, ITG score": same vertical level (y=7) and font size
-- (zoom 0.2) as the ITG/EX score at the end of the line (see the BitmapText
-- above, inside the per-player loop), positioned just to its left. Solo,
-- persistent-profile player only. Points are color-coded by the song's LOCAL
-- top-N standing (green = top75, yellow = top150, white otherwise); rank is
-- the GLOBAL ITL leaderboard rank, fetched on demand (see
-- Scripts/SL-Helpers-ITLRank.lua and
-- BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua).
af[#af+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text="",
	InitCommand=function(self)
		self:visible(false):horizalign(right):zoom(ITL_ZOOM):y(7)
		self:x( ITL_COL_PTS )
		self.hash = nil
	end,
	SetCommand=function(self, params)
		self:visible(false)
		self.hash = nil

		local humans = GAMESTATE:GetHumanPlayers()
		if #humans ~= 1 then return end
		local player = humans[1]
		if not PROFILEMAN:IsPersistentProfile(player) then return end
		local pn = ToEnumShortString(player)

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

af[#af+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text="",
	Name="ITLGlobalRank",
	InitCommand=function(self)
		self:visible(false):horizalign(right):zoom(ITL_ZOOM):y(7)
		self:x( ITL_COL_RANK )
		self.hash = nil
	end,
	SetCommand=function(self, params)
		self:visible(false)
		self.hash = nil

		local humans = GAMESTATE:GetHumanPlayers()
		if #humans ~= 1 then return end
		local player = humans[1]
		if not PROFILEMAN:IsPersistentProfile(player) then return end
		local pn = ToEnumShortString(player)

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