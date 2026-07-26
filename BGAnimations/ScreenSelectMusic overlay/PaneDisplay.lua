-- get the machine_profile now at file init; no need to keep fetching with each SetCommand
local machine_profile = PROFILEMAN:GetMachineProfile()

-- the height of the footer is defined in ./Graphics/_footer.lua, but we'll
-- use it here when calculating where to position the PaneDisplay
local footer_height = 32

-- height of the PaneDisplay in pixels
local pane_height = 60

local text_zoom = WideScale(0.58, 0.65)

-- "Technique HUD": the pane is a dark card now rather than a difficulty-colored
-- slab, so its text is light. Kept as constants because this file sets the
-- color in ~20 places, including from the GrooveStats response processor.
local PANE_TEXT = color("#E8F1F4")
local PANE_TEXT_HEX = "#E8F1F4"

-- -----------------------------------------------------------------------
-- Convenience function to return the SongOrCourse and StepsOrTrail for a
-- for a player.
local GetSongAndSteps = function(player)
	local SongOrCourse = (GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse()) or GAMESTATE:GetCurrentSong()
	local StepsOrTrail = (GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player)) or GAMESTATE:GetCurrentSteps(player)
	return SongOrCourse, StepsOrTrail
end

-- -----------------------------------------------------------------------
local GetScoreFromProfile = function(profile, SongOrCourse, StepsOrTrail)
	-- if we don't have everything we need, return nil
	if not (profile and SongOrCourse and StepsOrTrail) then return nil end

	return profile:GetHighScoreList(SongOrCourse, StepsOrTrail):GetHighScores()[1]
end

local GetScoreForPlayer = function(player)
	local highScore
	if PROFILEMAN:IsPersistentProfile(player) then
		local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
		highScore = GetScoreFromProfile(PROFILEMAN:GetProfile(player), SongOrCourse, StepsOrTrail)
	end
	return highScore
end

-- -----------------------------------------------------------------------
local SetNameAndScore = function(name, score, nameActor, scoreActor, textColor)
	if not scoreActor or not nameActor then return end
	scoreActor:settext(score):diffuse(color(textColor))
	nameActor:settext(name):diffuse(color(textColor))
end

local GetMachineTag = function(gsEntry)
	if not gsEntry then return end
	if gsEntry["machineTag"] then
		-- Make sure we only use up to 4 characters for space concerns.
		return gsEntry["machineTag"]:sub(1, 4):upper()
	end

	-- User doesn't have a machineTag set. We'll "make" one based off of
	-- their name.
	if gsEntry["name"] then
		-- 4 Characters is the "intended" length.
		return gsEntry["name"]:sub(1,4):upper()
	end

	return ""
end

local GetScoresRequestProcessor = function(res, params)
	local master = params.master
	if master == nil then return end
	-- If we're not hovering over a song when we get the request, then we don't
	-- have to update anything. We don't have to worry about courses here since
	-- we don't run the RequestResponseActor in CourseMode.
	if GAMESTATE:GetCurrentSong() == nil then return end
	
	local data = res.statusCode == 200 and JsonDecode(res.body) or nil
	local requestCacheKey = params.requestCacheKey
	-- If we have data, and the requestCacheKey is not in the cache, cache it.
	if data ~= nil and SL.GrooveStats.RequestCache[requestCacheKey] == nil then
		SL.GrooveStats.RequestCache[requestCacheKey] = {
			Response=res,
			Timestamp=GetTimeSinceStart()
		}
	end

	for i=1,2 do
		local paneDisplay = master:GetChild("PaneDisplayP"..i)
		local machineScore = paneDisplay:GetChild("MachineHighScore")
		local machineName = paneDisplay:GetChild("MachineHighScoreName")

		local playerScore = paneDisplay:GetChild("PlayerHighScore")
		local playerName = paneDisplay:GetChild("PlayerHighScoreName")

		local loadingText = paneDisplay:GetChild("Loading")

		local playerStr = "player"..i
		local rivalNum = 1
		local worldRecordSet = false
		local personalRecordSet = false
		local foundLeaderboard = false

		-- First check to see if the leaderboard even exists.
		if data and data[playerStr] then
			local showExScore = SL["P"..i].ActiveModifiers.ShowEXScore and data[playerStr]["exLeaderboard"] ~= nil
			local leaderboardData = nil
			if showExScore then
				leaderboardData = data[playerStr]["exLeaderboard"]
			elseif data[playerStr]["gsLeaderboard"] then
				leaderboardData = data[playerStr]["gsLeaderboard"]
			end

			if leaderboardData then
				foundLeaderboard = true
			end

			-- And then also ensure that the chart hash matches the currently parsed one.
			-- It's better to just not display anything than display the wrong scores.
			if SL["P"..i].Streams.Hash == data[playerStr]["chartHash"] and leaderboardData then
				for gsEntry in ivalues(leaderboardData) do
					if gsEntry["rank"] == 1 then
						SetNameAndScore(
							GetMachineTag(gsEntry),
							string.format("%.2f%%", gsEntry["score"]/100),
							machineName,
							machineScore,
							PANE_TEXT_HEX
						)
						worldRecordSet = true
					end

					if gsEntry["isSelf"] then
						-- Always display personal EX score from the site if it's available.
						-- TODO(teejusb): Grab white count from stats and calculate it to compare local score.
						if showExScore then
							SetNameAndScore(
								GetMachineTag(gsEntry),
								string.format("%.2f%%", gsEntry["score"]/100),
								playerName,
								playerScore,
								PANE_TEXT_HEX
							)
							personalRecordSet = true
						else
							-- Let's check if the GS high score is higher than the local high score
							local player = PlayerNumber[i]
							local localScore = GetScoreForPlayer(player)
							-- GS's score entry is a value like 9823, so we need to divide it by 100 to get 98.23
							local gsScore = gsEntry["score"] / 100

							-- GetPercentDP() returns a value like 0.9823, so we need to multiply it by 100 to get 98.23
							if not localScore or gsScore >= localScore:GetPercentDP() * 100 then
								-- It is! Let's use it instead of the local one.
								SetNameAndScore(
									GetMachineTag(gsEntry),
									string.format("%.2f%%", gsScore),
									playerName,
									playerScore,
									PANE_TEXT_HEX
								)
								personalRecordSet = true
							end
						end
					end

					if gsEntry["isRival"] then
						local rivalScore = paneDisplay:GetChild("Rival"..rivalNum.."Score")
						local rivalName = paneDisplay:GetChild("Rival"..rivalNum.."Name")
						SetNameAndScore(
							GetMachineTag(gsEntry),
							string.format("%.2f%%", gsEntry["score"]/100),
							rivalName,
							rivalScore,
							PANE_TEXT_HEX
						)
						rivalNum = rivalNum + 1
					end
				end
			end
		elseif data and data[playerStr] and data[playerStr]["itl"] and data[playerStr]["itl"]["itlLeaderboard"] then
			
			-- And then also ensure that the chart hash matches the currently parsed one.
			-- It's better to just not display anything than display the wrong scores.
			if SL["P"..i].Streams.Hash == data[playerStr]["chartHash"] then
				for gsEntry in ivalues(data[playerStr]["itl"]["itlLeaderboard"]) do
					if gsEntry["rank"] == 1 then
						SetNameAndScore(
							GetMachineTag(gsEntry),
							string.format("%.2f%%", gsEntry["score"]/100),
							machineName,
							machineScore,
							"#21CCE8"
						)
						worldRecordSet = true
					end

					if gsEntry["isRival"] then
						local rivalScore = paneDisplay:GetChild("Rival"..rivalNum.."Score")
						local rivalName = paneDisplay:GetChild("Rival"..rivalNum.."Name")
						SetNameAndScore(
							GetMachineTag(gsEntry),
							string.format("%.2f%%", gsEntry["score"]/100),
							rivalName,
							rivalScore,
							"#21CCE8"
						)
						rivalNum = rivalNum + 1
					end
				end
			end
		end

		-- Fall back to to using the machine profile's record if we never set the world record.
		-- This chart may not have been ranked, or there is no WR, or the request failed.
		if not worldRecordSet then
			machineName:queuecommand("SetDefault")
			machineScore:queuecommand("SetDefault")
		end

		-- Fall back to to using the personal profile's record if we never set the record.
		-- This chart may not have been ranked, or we don't have a score for it, or the request failed.
		if not personalRecordSet then
			playerName:queuecommand("SetDefault")
			playerScore:queuecommand("SetDefault")
		end

		-- Iterate over any remaining rivals and hide them.
		-- This also handles the failure case as rivalNum will never have been incremented.
		for j=rivalNum,3 do
			local rivalScore = paneDisplay:GetChild("Rival"..j.."Score")
			local rivalName = paneDisplay:GetChild("Rival"..j.."Name")
			rivalScore:settext("??.??%")
			rivalName:settext("----")
		end

		if res.error or res.statusCode ~= 200 then
			local error = res.error and ToEnumShortString(res.error) or nil
			if error == "Timeout" then
				loadingText:settext("Timed Out")
			elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
				loadingText:settext("Failed")
			end
		else
			if data and data[playerStr] then
				local headers = res.headers
				local boogie = false
				local boogie_ex = false
				if headers["bs-leaderboard-player-" .. i] == "BS" then
					boogie = true
				elseif headers["bs-leaderboard-player-" .. i] == "BS-EX" then
					boogie_ex = true
				end
				
				if foundLeaderboard then
					if boogie then
						loadingText:settext("BoogieStats")
					elseif boogie_ex then
						loadingText:settext("Boogie EX")
					elseif SL["P"..i].ActiveModifiers.ShowEXScore then
						loadingText:settext("EX Score")
					else
						loadingText:settext("GrooveStats")
					end
				else
					if boogie then
						loadingText:settext("No Boogie Data")
					elseif boogie_ex then
						loadingText:settext("No Boogie EX")
					elseif SL["P"..i].ActiveModifiers.ShowEXScore then
						loadingText:settext("No EX Data")
					else
						loadingText:settext("No Data")
					end
				end
			else
				-- Just hide the text
				loadingText:queuecommand("Set")
			end
		end
	end
end

-- -----------------------------------------------------------------------
-- define the x positions of four columns, and the y positions of three rows of PaneItems
-- Column anchors, as fractions of the pane's half width so 4:3 and 16:9 both fall
-- out of one set of numbers rather than two hand-tuned WideScale pairs.
--
-- Every stat prints as "<value> <label>": the value is right-aligned ON its anchor and
-- the label starts 3px after it. Values are bright, labels dim -- a dozen numbers in a
-- 60px strip only reads if the words recede behind the figures.
local pane_hw = (_screen.w/2 - 10) / 2

local pos = {
	row = { 13, 31, 49 },

	-- chart counts: two sub-columns over three rows
	radar = { -0.72 * pane_hw, -0.355 * pane_hw },
	-- technical counts: two sub-columns, five slots used
	tech  = { -0.03 * pane_hw,  0.22 * pane_hw },
	-- total stream sits alone on the last row, so it can be as wide as it needs
	stream = 0.72 * pane_hw,
	-- the two high scores
	sc_label = 0.335 * pane_hw,
	sc_name  = 0.58  * pane_hw,
	sc_pct   = 0.985 * pane_hw,
	-- GrooveStats rivals borrow the technical columns' space -- see show_rivals below
	rv_name = -0.03 * pane_hw,
	rv_pct  =  0.30 * pane_hw,
}

-- The pane cannot hold both the technical counts and three rival scores. Rivals only
-- exist in "Pane" mode, where the two scores are GrooveStats data rather than local
-- machine/profile bests, so that mode gets the rivals and this one gets the counts.
local show_rivals = (ThemePrefs.Get("MusicWheelGS") == "Pane")

-- Two-letter abbreviations for the technical counts, keyed by their SL[pn].Streams
-- field. These used to live in a separate PatternInfo panel tucked under the density
-- graph, spelled out in full; they are folded in here so the difficulty picker can have
-- that band instead.
-- TWEAK: the labels printed in the pane.
local TECH_STATS = {
	{ key="Crossovers",   label="XO" },
	{ key="Footswitches", label="FS" },
	{ key="Sideswitches", label="SS" },
	{ key="Jacks",        label="JA" },
	{ key="Brackets",     label="BR" },
}

local num_rows = 3
local num_cols = 2

-- HighScores handled as special cases for now until further refactoring
local PaneItems = {
	-- first row
	{ name=THEME:GetString("RadarCategory","Taps"),  rc='RadarCategory_TapsAndHolds'},
	{ name=THEME:GetString("RadarCategory","Mines"), rc='RadarCategory_Mines'},
	-- { name=THEME:GetString("ScreenSelectMusic","NPS") },

	-- second row
	{ name=THEME:GetString("RadarCategory","Jumps"), rc='RadarCategory_Jumps'},
	{ name=THEME:GetString("RadarCategory","Hands"), rc='RadarCategory_Hands'},
	-- { name=THEME:GetString("RadarCategory","Lifts"), rc='RadarCategory_Lifts'},

	-- third row
	{ name=THEME:GetString("RadarCategory","Holds"), rc='RadarCategory_Holds'},
	{ name=THEME:GetString("RadarCategory","Rolls"), rc='RadarCategory_Rolls'},
	-- { name=THEME:GetString("RadarCategory","Fakes"), rc='RadarCategory_Fakes'},
}

-- -----------------------------------------------------------------------
local af = Def.ActorFrame{ Name="PaneDisplayMaster" }

af[#af+1] = RequestResponseActor(17, 50)..{
	Name="GetScoresRequester",
	OnCommand=function(self)
		-- Create variables for both players, even if they're not currently active.
		self.IsParsing = {false, false}
	end,
	-- Broadcasted from ./PerPlayer/DensityGraph.lua
	P1ChartParsingMessageCommand=function(self)	self.IsParsing[1] = true end,
	P2ChartParsingMessageCommand=function(self)	self.IsParsing[2] = true end,
	P1ChartParsedMessageCommand=function(self)
		self.IsParsing[1] = false
		self:queuecommand("ChartParsed")
	end,
	P2ChartParsedMessageCommand=function(self)
		self.IsParsing[2] = false
		self:queuecommand("ChartParsed")
	end,
	ChartParsedCommand=function(self)
		local master = self:GetParent()

		if not IsServiceAllowed(SL.GrooveStats.GetScores) then
			if SL.GrooveStats.IsConnected then
				-- loadingText is made visible when requests complete.
				-- If we disable the service from a previous request, surface it to the user here.
				for i=1,2 do
					local loadingText = master:GetChild("PaneDisplayP"..i):GetChild("Loading")
					loadingText:settext("Disabled")
					loadingText:visible(true)
				end
			end
			return
		end

		-- Make sure we're still not parsing either chart.
		if self.IsParsing[1] or self.IsParsing[2] then return end

		-- This makes sure that the Hash in the ChartInfo cache exists.
		local sendRequest = false
		local headers = {}
		local query = {
			maxLeaderboardResults=NumEntries,
		}
		local requestCacheKey = ""

		if ThemePrefs.Get("MusicWheelGS") == "Pane" then
			for i=1,2 do
				local pn = "P"..i
				if IsItlSong(PlayerNumber[i]) then
					UpdatePathMap(PlayerNumber[i], SL[pn].Streams.Hash)
				end
				if SL[pn].ApiKey ~= "" and SL[pn].Streams.Hash ~= "" then
					query["chartHashP"..i] = SL[pn].Streams.Hash
					headers["x-api-key-player-"..i] = SL[pn].ApiKey
					requestCacheKey = requestCacheKey .. SL[pn].Streams.Hash .. SL[pn].ApiKey .. pn
					local loadingText = master:GetChild("PaneDisplayP"..i):GetChild("Loading")
					loadingText:visible(true)
					loadingText:settext("Loading ..."):diffuse(PANE_TEXT)
					sendRequest = true
				end
			end
		end

		-- Only send the request if it's applicable.
		if sendRequest then
			requestCacheKey = CRYPTMAN:SHA256String(requestCacheKey.."-player-scores")
			local params = {requestCacheKey=requestCacheKey, master=master}
			RemoveStaleCachedRequests()
			-- If the data is still in the cache, run the request processor directly
			-- without making a request with the cached response.
			if SL.GrooveStats.RequestCache[requestCacheKey] ~= nil then
				local res = SL.GrooveStats.RequestCache[requestCacheKey].Response
				GetScoresRequestProcessor(res, params)
			else
				self:playcommand("MakeGrooveStatsRequest", {
					endpoint="player-scores.php?"..NETWORK:EncodeQueryParameters(query),
					method="GET",
					headers=headers,
					timeout=10,
					callback=GetScoresRequestProcessor,
					args=params,
				})
			end
		end
	end
}

for player in ivalues(PlayerNumber) do
	local pn = ToEnumShortString(player)

	af[#af+1] = Def.ActorFrame{ Name="PaneDisplay"..ToEnumShortString(player) }

	local af2 = af[#af]

	af2.InitCommand=function(self)
		self:visible(GAMESTATE:IsHumanPlayer(player))

		if player == PLAYER_1 then
			self:x(_screen.w * 0.25 - 5)
		elseif player == PLAYER_2 then
			self:x(_screen.w * 0.75 + 5)
		end

		self:y(_screen.h - footer_height - pane_height)
	end

	af2.PlayerJoinedMessageCommand=function(self, params)
		if player==params.Player then
			-- ensure the difficulty rule is colored before the pane is made visible
			self:GetChild("DifficultyRule"):playcommand("Set")
			self:visible(true)
				:zoom(0):croptop(0):bounceend(0.3):zoom(1)
				:playcommand("Update")
		end
	end

	af2.PlayerUnjoinedMessageCommand=function(self, params)
		if player==params.Player then
			self:accelerate(0.3):croptop(1):sleep(0.01):zoom(0):queuecommand("Hide")
		end
	end

	af2.PlayerProfileSetMessageCommand=function(self, params)
		if player == params.Player then
			self:playcommand("Set")
		end
	end

	af2.HideCommand=function(self) self:visible(false) end

	af2.OnCommand=function(self)                                    self:playcommand("Set") end
	af2.SLGameModeChangedMessageCommand=function(self)              self:playcommand("Set") end
	af2.CurrentCourseChangedMessageCommand=function(self)			self:playcommand("Set") end
	af2.CurrentSongChangedMessageCommand=function(self)				self:playcommand("Set") end
	af2["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self) self:playcommand("Set") end
	af2["CurrentTrail"..pn.."ChangedMessageCommand"]=function(self) self:playcommand("Set") end

	-- -----------------------------------------------------------------------
	-- colored background Quad

	af2[#af2+1] = Def.Quad{
		Name="BackgroundQuad",
		InitCommand=function(self)
			self:zoomtowidth(_screen.w/2-10)
			self:zoomtoheight(pane_height)
			self:vertalign(top)
			HUDPanel(self)
		end
	}

	-- vertalign(top) above means the pane hangs below the frame origin, so the
	-- bracket is offset by half its height to line up with it. Bottom-right only:
	-- the DifficultyRule below already rules this card's whole top edge.
	af2[#af2+1] = HUDCardDecor(_screen.w/2-10, pane_height, 0, pane_height/2, "br")

	-- The difficulty color now reads as a rule along the card's top edge rather
	-- than flooding the whole pane, so the stats printed on it stay legible.
	af2[#af2+1] = Def.Quad{
		Name="DifficultyRule",
		InitCommand=function(self)
			self:zoomtowidth(_screen.w/2-10):zoomtoheight(2):vertalign(top)
		end,
		SetCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			if GAMESTATE:IsHumanPlayer(player) then
				if StepsOrTrail then
					self:diffuse( DifficultyColor(StepsOrTrail:GetDifficulty()) )
				else
					self:diffuse( PlayerColor(player) )
				end
			end
		end
	}

	-- -----------------------------------------------------------------------
	-- loop through the six sub-tables in the PaneItems table
	-- add one BitmapText as the label and one BitmapText as the value for each PaneItem

	for i, item in ipairs(PaneItems) do

		local col = ((i-1)%num_cols) + 1
		local row = math.floor((i-1)/num_cols) + 1

		af2[#af2+1] = Def.ActorFrame{

			Name=item.name,

			-- numerical value
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				InitCommand=function(self)
					self:zoom(text_zoom):diffuse(PANE_TEXT):horizalign(right)
					self:x(pos.radar[col])
					self:y(pos.row[row])
				end,

				SetCommand=function(self)
					local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
					if not SongOrCourse then self:settext("?"); return end
					if not StepsOrTrail then self:settext("");  return end

					if item.rc then
						local val = StepsOrTrail:GetRadarValues(player):GetValue( item.rc )
						-- the engine will return -1 as the value for autogenerated content; show a question mark instead if so
						self:settext( val >= 0 and val or "?" )
					end
				end
			},

			-- label
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				Text=item.name,
				InitCommand=function(self)
					self:zoom(text_zoom):diffuse(HUD_LABEL):horizalign(left)
					self:x(pos.radar[col]+3)
					self:y(pos.row[row])
				end
			},
		}
	end

	-- Machine/World Record Machine Tag
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="MachineHighScoreName",
		InitCommand=function(self)
			self:zoom(text_zoom):diffuse(PANE_TEXT):maxwidth(34):horizalign(left)
			self:x(pos.sc_name)
			self:y(pos.row[1])
		end,
		SetCommand=function(self)
			-- We overload this actor to work both for GrooveStats and also offline.
			-- If we're connected, we let the ResponseProcessor set the text
			if IsServiceAllowed(SL.GrooveStats.GetScores) and ThemePrefs.Get("MusicWheelGS") == "Pane" then
				self:settext("----"):diffuse(PANE_TEXT)
			else
				self:queuecommand("SetDefault")
			end
		end,
		SetDefaultCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			local machineScore = GetScoreFromProfile(machine_profile, SongOrCourse, StepsOrTrail)
			self:settext(machineScore and machineScore:GetName() or "----"):diffuse(PANE_TEXT)
			DiffuseEmojis(self:ClearAttributes())
		end
	}

	-- Machine/World Record HighScore
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="MachineHighScore",
		InitCommand=function(self)
			self:zoom(text_zoom):diffuse(PANE_TEXT):horizalign(right)
			self:x(pos.sc_pct)
			self:y(pos.row[1])
		end,
		SetCommand=function(self)
			-- We overload this actor to work both for GrooveStats and also offline.
			-- If we're connected, we let the ResponseProcessor set the text
			if IsServiceAllowed(SL.GrooveStats.GetScores) and ThemePrefs.Get("MusicWheelGS") == "Pane" then
				self:settext("??.??%"):diffuse(PANE_TEXT)
			else
				self:queuecommand("SetDefault")
			end
		end,
		SetDefaultCommand=function(self)
			local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
			local machineScore = GetScoreFromProfile(machine_profile, SongOrCourse, StepsOrTrail)
			if machineScore ~= nil then
				self:settext(FormatPercentScore(machineScore:GetPercentDP())):diffuse(PANE_TEXT)
			else
				self:settext("??.??%"):diffuse(PANE_TEXT)
			end
		end
	}

	-- Player Profile/GrooveStats Machine Tag
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="PlayerHighScoreName",
		InitCommand=function(self)
			self:zoom(text_zoom):diffuse(PANE_TEXT):maxwidth(34):horizalign(left)
			self:x(pos.sc_name)
			self:y(pos.row[2])
		end,
		SetCommand=function(self)
			-- We overload this actor to work both for GrooveStats and also offline.
			-- If we're connected, we let the ResponseProcessor set the text
			if IsServiceAllowed(SL.GrooveStats.GetScores) and ThemePrefs.Get("MusicWheelGS") == "Pane" then
				self:settext("----")
			else
				self:queuecommand("SetDefault")
			end
		end,
		SetDefaultCommand=function(self)
			local playerScore = GetScoreForPlayer(player)
			self:settext(playerScore and playerScore:GetName() or "----"):diffuse(PANE_TEXT)
			DiffuseEmojis(self:ClearAttributes())
		end
	}

	-- Player Profile/GrooveStats HighScore
	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="PlayerHighScore",
		InitCommand=function(self)
			self:zoom(text_zoom):diffuse(PANE_TEXT):horizalign(right)
			self:x(pos.sc_pct)
			self:y(pos.row[2])
		end,
		SetCommand=function(self)
			-- We overload this actor to work both for GrooveStats and also offline.
			-- If we're connected, we let the ResponseProcessor set the text
			if IsServiceAllowed(SL.GrooveStats.GetScores) and ThemePrefs.Get("MusicWheelGS") == "Pane" then
				self:settext("??.??%")
			else
				self:queuecommand("SetDefault")
			end
		end,
		SetDefaultCommand=function(self)
			local playerScore = GetScoreForPlayer(player)
			if playerScore ~= nil then
				self:settext(FormatPercentScore(playerScore:GetPercentDP())):diffuse(PANE_TEXT)
			else
				self:settext("??.??%"):diffuse(PANE_TEXT)
			end
		end
	}

	af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Loading",
		Text="Loading ... ",
		InitCommand=function(self)
			self:zoom(text_zoom):diffuse(PANE_TEXT)
			self:x(pos.sc_label)
			self:y(pos.row[3])
			self:visible(false)
		end,
		SetCommand=function(self)
			self:settext("Loading ...")
			self:visible(false)
		end
	}

	-- The chart's difficulty meter used to be printed here as a large Wendy number.
	-- It is gone: the difficulty picker (StepsDisplayList/Grid.lua) now shows all five
	-- meters as chips a few pixels above this pane, so this was the same number twice.

	-- Labels for the two score rows. The pane used to print two anonymous
	-- "---- ??.??%" pairs with nothing to say which was the machine's and which the
	-- player's own profile.
	for i, key in ipairs({"MachineScore", "ProfileScore"}) do
		af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Text=THEME:GetString("ScreenSelectMusic", key),
			InitCommand=function(self)
				self:zoom(text_zoom):diffuse(HUD_LABEL):horizalign(left)
				self:xy(pos.sc_label, pos.row[i])
			end
		}
	end

	-- Technical counts, folded in from the PatternInfo panel that used to sit under the
	-- density graph. Five slots: two per row for the first two rows, one on the third,
	-- which leaves the third row's second column clear for the stream ratio.
	--
	-- These come from the chart parser rather than from radar values, and parsing is
	-- deferred (DensityGraph.lua stalls 0.4s before it runs) -- so they refresh on the
	-- parser's own <pn>ChartParsed broadcast, not on the pane's generic Set. Listening
	-- to Set would read SL[pn].Streams before it had been filled in.
	if not show_rivals and not GAMESTATE:IsCourseMode() then

		af2[pn.."ChartParsingMessageCommand"] = function(self) self:playcommand("ClearTech") end
		af2[pn.."ChartParsedMessageCommand"]  = function(self) self:playcommand("SetTech") end

		for i, stat in ipairs(TECH_STATS) do
			local col = ((i-1) % 2) + 1
			local row = math.floor((i-1)/2) + 1

			af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				Name=stat.key.."Value",
				Text="",
				InitCommand=function(self)
					self:zoom(text_zoom):diffuse(PANE_TEXT):horizalign(right)
					self:xy(pos.tech[col], pos.row[row])
				end,
				ClearTechCommand=function(self) self:settext("") end,
				SetTechCommand=function(self)
					self:settext( SL[pn].Streams[stat.key] or 0 )
				end
			}

			af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				Text=stat.label,
				InitCommand=function(self)
					self:zoom(text_zoom):diffuse(HUD_LABEL):horizalign(left)
					self:xy(pos.tech[col]+3, pos.row[row])
				end
			}
		end

		-- Total stream: measures of stream over total measures, with the percentage.
		af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="TotalStreamValue",
			Text="",
			InitCommand=function(self)
				self:zoom(text_zoom):diffuse(PANE_TEXT):horizalign(right)
				self:xy(pos.stream, pos.row[3])
			end,
			ClearTechCommand=function(self) self:settext("") end,
			SetTechCommand=function(self)
				local streamMeasures, breakMeasures = GetTotalStreamAndBreakMeasures(pn)
				local total = streamMeasures + breakMeasures
				if streamMeasures == 0 or total == 0 then
					self:settext("0%")
				else
					self:settext( ("%d/%d %.1f%%"):format(streamMeasures, total, streamMeasures/total*100) )
				end
			end
		}

		af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Text=THEME:GetString("ScreenSelectMusic", "TotalStream"),
			InitCommand=function(self)
				self:zoom(text_zoom):diffuse(HUD_LABEL):horizalign(left)
				self:xy(pos.stream+3, pos.row[3])
			end
		}
	end

	-- Add actors for Rival score data. Hidden by default
	-- We position relative to column 3 for spacing reasons.
	if show_rivals then
		for i=1,3 do
			-- Rival Machine Tag
			af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				Name="Rival"..i.."Name",
				InitCommand=function(self)
					self:zoom(text_zoom):diffuse(PANE_TEXT):maxwidth(30)
					self:x(pos.rv_name)
					self:y(pos.row[i])
				end,
				OnCommand=function(self)
					self:visible(IsServiceAllowed(SL.GrooveStats.GetScores))
				end,
				SetCommand=function(self)
					self:settext("----"):diffuse(PANE_TEXT)
				end
			}
	
			-- Rival HighScore
			af2[#af2+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				Name="Rival"..i.."Score",
				InitCommand=function(self)
					self:zoom(text_zoom):diffuse(PANE_TEXT):horizalign(right)
					self:x(pos.rv_pct)
					self:y(pos.row[i])
				end,
				OnCommand=function(self)
					self:visible(IsServiceAllowed(SL.GrooveStats.GetScores))
				end,
				SetCommand=function(self)
					self:settext("??.??%"):diffuse(PANE_TEXT)
				end
			}
		end
	end
end

return af