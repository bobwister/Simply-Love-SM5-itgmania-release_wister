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
		self:horizalign(left):visible(false):zoom(0.375)
		self:x( _screen.w/(WideScale(2.15, 2.14)) - self:GetWidth()*self:GetZoom() - 8 )

		if DarkUI() then self:diffuse(0,0,0,1) end
	end,
	SetCommand=function(self, params)
		self:visible(params.Song and params.Song:HasEdits(stepstype) or false)
	end
}

for player in ivalues(PlayerNumber) do
	af[#af+1] = LoadActor("GetLamp.lua", player)
	af[#af+1] = LoadActor("Favorites.lua", player)

	-- Add ITL EX scores to the song wheel as well.
	-- It will be centered to the item if only one player is enabled, and stacked otherwise.
	af[#af+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small" or "Mega/_mega font",
		Text="",
		InitCommand=function(self)
			self:visible(false)
			self:zoom(0.2)
			self:x( _screen.w/(WideScale(2.15, 2.14)) - self:GetWidth()*self:GetZoom() - 40 )
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
			-- in 1 player mode, it will show the details for the opposite player
			local otherplayer = player == PLAYER_1 and PLAYER_2 or PLAYER_1
			local pn = ToEnumShortString(player)

			if GAMESTATE:GetNumSidesJoined() == 1 then
				if PROFILEMAN:IsPersistentProfile(player) or PROFILEMAN:IsPersistentProfile(otherplayer) then
					self:visible(true)
					if PROFILEMAN:IsPersistentProfile(otherplayer) then 
						pn = pn == "P1" and "P2" or "P1"
					end
				end
			else
				self:visible(PROFILEMAN:IsPersistentProfile(player))
			end

			if player == PLAYER_1 then
				self:y(-7)
			else
				self:y(7)
			end
			
			if params.Song ~= nil then
				local song = params.Song
				local song_dir = song:GetSongDir()
				if song_dir ~= nil and #song_dir ~= 0 then
					if SL[pn].ITLData["pathMap"][song_dir] ~= nil then
						local hash = SL[pn].ITLData["pathMap"][song_dir]
						if SL[pn].ITLData["hashMap"][hash] ~= nil then
							self:settext(tostring(("%.2f"):format(SL[pn].ITLData["hashMap"][hash]["ex"] / 100)))
							 if (GAMESTATE:GetNumSidesJoined() == 1 and PROFILEMAN:IsPersistentProfile(player)) then 
							 	self:settext(SL[pn].ITLData["hashMap"][hash]["points"])
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

	-- Global ITL points (top line) + global ITL rank (bottom line), at the
	-- same spot the local top-N "Song Rank" used to occupy. Points are
	-- color-coded by the song's LOCAL top-N standing (green = top75,
	-- yellow = top150, white otherwise); rank is the GLOBAL ITL leaderboard
	-- rank, fetched on demand (see Scripts/SL-Helpers-ITLRank.lua and
	-- BGAnimations/ScreenSelectMusic overlay/ITLRankManager.lua).
	af[#af+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small" or "Mega/_mega font",
		Text="",
		InitCommand=function(self)
			self:visible(false)
			self:zoom(IsNotWide and 0.2 or 0.3)
			-- TWEAK: top line of the pair, above the rank line below
			self:y(-9)
		end,
		PlayerJoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		PlayerUnjoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		SetCommand=function(self, params)
			self:visible(false)

			if not GAMESTATE:IsPlayerEnabled(player) or not PROFILEMAN:IsPersistentProfile(player) then return end
			if GAMESTATE:GetNumSidesJoined() ~= 1 then return end
			if params.Song == nil then return end

			local pn = ToEnumShortString(player)
			self:x(THEME:GetMetric("MusicWheelItem", "GradeP"..(pn == "P1" and 2 or 1).."X")-WideScale(28,33))

			local song_dir = params.Song:GetSongDir()
			if not song_dir or #song_dir == 0 then return end
			local hash = SL[pn].ITLData["pathMap"][song_dir]
			if not hash then return end
			local data = SL[pn].ITLData["hashMap"][hash]
			if not data then return end

			local points = data["points"] or 0
			if points == 0 then return end

			local localRank = data["rank"]
			if type(localRank) == "number" and localRank <= 75 then
				self:diffuse(Color.Green)
			elseif type(localRank) == "number" and localRank <= 150 then
				self:diffuse(Color.Yellow)
			else
				self:diffuse(Color.White)
			end
			self:settext( ("%dpts"):format(points) ):visible(true)
		end,
	}

	af[#af+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small" or "Mega/_mega font",
		Text="",
		Name="ITLGlobalRank",
		InitCommand=function(self)
			self:visible(false)
			self:zoom(IsNotWide and 0.2 or 0.3)
			-- TWEAK: bottom line of the pair, below the points line above
			self:y(9)
			self.hash = nil
		end,
		PlayerJoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		PlayerUnjoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		SetCommand=function(self, params)
			self:visible(false)
			self.hash = nil

			if not GAMESTATE:IsPlayerEnabled(player) or not PROFILEMAN:IsPersistentProfile(player) then return end
			if GAMESTATE:GetNumSidesJoined() ~= 1 then return end
			if params.Song == nil then return end

			local pn = ToEnumShortString(player)
			self:x(THEME:GetMetric("MusicWheelItem", "GradeP"..(pn == "P1" and 2 or 1).."X")-WideScale(28,33))

			local song_dir = params.Song:GetSongDir()
			if not song_dir or #song_dir == 0 then return end
			local hash = SL[pn].ITLData["pathMap"][song_dir]
			if not hash then return end
			self.hash = hash

			local rank = ITLRankGet(hash)
			if type(rank) == "number" then
				self:settext(ITLRankOrdinal(rank)):diffuse(ITLRankColor(rank)):visible(true)
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
		ITLRankResolvedMessageCommand=function(self, params)
			if self.hash and params.hash == self.hash then
				local rank = ITLRankGet(self.hash)
				if type(rank) == "number" then
					self:settext(ITLRankOrdinal(rank)):diffuse(ITLRankColor(rank)):visible(true)
				else
					self:visible(false)
				end
			end
		end,
	}
end

return af