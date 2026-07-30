local player = ...
local pn = ToEnumShortString(player)

-- No GS scores for courses, none unless Music Wheel GS integration is set to Scorebox,
-- and none without a reachable service and an API key on the profile. That test lives in
-- Scripts/SL-Layout-SelectMusic.lua because LocalLeaderboard.lua has to answer the same
-- question the other way round: it takes this card whenever this box gives it up.
if not SSM_GrooveStatsBoxActive(player) then return end

local n = player==PLAYER_1 and "1" or "2"
local IsNotWide = (GetScreenAspectRatio() < 16/9)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)
-- Rows on the board. GrooveStats is asked for this many (maxLeaderboardResults);
-- AutoSubmitScore.lua already asks for 10, so the server is happy above five.
-- TWEAK: has to stay in step with row_zoom below -- eight rows only fit because the
-- type came down from 0.87.
local NumEntries = 8

-- Technique HUD: a hairline rule rather than a thick frame. The border quad is
-- drawn behind the body, so this is the amount it peeks out on each side, and
-- it stays the per-source tint (GrooveStats blue / RPG yellow / ITL pink) that
-- tells you which leaderboard is currently on screen.
local border = 2
-- Size and position both come from Scripts/SL-Layout-SelectMusic.lua: this leaderboard is
-- the right half of the left column's bottom card now, sharing that band with the player
-- card, rather than a 162px box floating on the wheel side of the screen at cx+80.
local width = SSM.scorebox.w
local height = SSM.scorebox.h

-- Row metrics, matched to LocalLeaderboard.lua so the card looks the same whichever of
-- the two owns it -- eight rows of dense HUD type rather than five large ones.
--
-- A Miso line's visible band at 0.55 is 8.25px, leaving ~1.8px of leading in a row.
local row_zoom = 0.55
local ROW_H    = height / NumEntries

-- Column anchors, from the card's centre.
local RANK_X  = -width/2 + 18   -- right-aligned
local NAME_X  = -width/2 + 21   -- left-aligned
local SCORE_X =  width/2 - 3    -- right-aligned
local CROWN_X = -width/2 + 10

-- maxwidth is in UNZOOMED font units, so the screen-space budget is divided by the zoom.
-- Derived rather than the flat 200 it used to be: that was ~174px of name in a 313px-wide
-- box. SCORE_PX is the widest score string ("100.00", no percent sign here) at row_zoom,
-- which is what the name has to stop short of.
local SCORE_PX = 26
local name_maxwidth = math.floor(((SCORE_X - SCORE_PX - 3) - NAME_X) / row_zoom)

-- Smoked glass rather than flat black, matching the wheel rows and the
-- left-column cards. Used both when the body is built and when it is faded back
-- in after a leaderboard request, which would otherwise restore it to opaque.
local body_color = color("#0B1116")
local body_alpha = 0.94

local cur_style = 0
local num_styles = 4

local GrooveStatsBlue = color("#007b85")
local RpgYellow = color("1,0.972,0.792,1")
local ItlPink = color("1,0.2,0.406,1")
local BoogieStatsPurple = color("#8000ff")

local style_color = {
	[0] = GrooveStatsBlue,  -- Either GrooveStats or GrooveStats EX score
	[1] = GrooveStatsBlue,  -- Either GrooveStats or GrooveStats EX score
	[2] = RpgYellow,
	[3] = ItlPink,
}

local self_color = color("#a1ff94")
local rival_color = color("#c29cff")

local loop_seconds = 5
local transition_seconds = 1

local all_data = {}

local ResetAllData = function()
	all_data = {}
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.EXScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WREXScore = 0
	
	for i=1,num_styles do
		local data = {
			["has_data"]=false,
			["scores"]={}
		}
		local scores = data["scores"]
		for i=1,NumEntries do
			scores[#scores+1] = {
				["rank"]="",
				["name"]="",
				["score"]="",
				["isSelf"]=false,
				["isRival"]=false,
				["isFail"]=false,
				["isEx"]=false,
			}
		end
		all_data[i] = data
	end
end

-- Initialize the all_data object.
ResetAllData()

-- Checks to see if any data is available.
local HasData = function(idx)
	return all_data[idx+1] and all_data[idx+1].has_data
end

local SetScoreData = function(data_idx, score_idx, rank, name, score, isSelf, isRival, isFail, isEx)
	all_data[data_idx].has_data = true

	local score_data = all_data[data_idx]["scores"][score_idx]
	score_data.rank = rank..((#rank > 0) and "." or "")
	score_data.name = name
	score_data.score = score
	score_data.isSelf = isSelf
	score_data.isRival = isRival
	score_data.isFail = isFail
	score_data.isEx = isEx
	
	if not isFail and (isRival or isSelf) then
		if data_idx == 3 then
			if tonumber(score) > SL[pn].Rival.EXScore then
				SL[pn].Rival.EXScore = tonumber(score)
			end
		else
			if tonumber(score) > SL[pn].Rival.Score then
				SL[pn].Rival.Score = tonumber(score)
			end
		end
	end
	
	if score_data.rank == 1 then
		if data_idx == 3 then
			SL[pn].Rival.WREXScore = tonumber(score)
		else
			if tonumber(score) > SL[pn].Rival.WRScore then
				SL[pn].Rival.WRScore = tonumber(score)
			end
		end
	end
end

-- Load one of the four leaderboards into its slots.
--
-- Six near-identical copies of this used to be inlined below, each walking the response
-- straight into consecutive slots -- which meant a board longer than the box lost its tail,
-- taking the player's own row and their rivals' with it. Collect first, let
-- SelectLeaderboardRows (Scripts/SL-Helpers-Leaderboard.lua) decide which rows survive,
-- then write.
--
-- onSelf runs during collection, so the ITL board's side effects still fire for the
-- player's entry whether or not that entry ends up on screen.
local FillBoard = function(data_idx, leaderboard, isEx, onSelf)
	local entries = {}
	for entry in ivalues(leaderboard) do
		if onSelf and entry["isSelf"] then onSelf(entry) end
		entries[#entries+1] = {
			rank    = tostring(entry["rank"]),
			name    = entry["name"],
			score   = string.format("%.2f", entry["score"]/100),
			isSelf  = entry["isSelf"],
			isRival = entry["isRival"],
			isFail  = entry["isFail"],
		}
	end

	local shown = SelectLeaderboardRows(entries, NumEntries)
	for i, e in ipairs(shown) do
		SetScoreData(data_idx, i, e.rank, e.name, e.score, e.isSelf, e.isRival, e.isFail, isEx)
	end
	-- blank the rest, but never slot 1: an empty board keeps its "No Scores" placeholder
	for i = math.max(2, #shown + 1), NumEntries do
		SetScoreData(data_idx, i, "", "", "", false, false, false, isEx)
	end
end

local LeaderboardRequestProcessor = function(res, master)
	if master == nil then return end

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		local text = ""
		if error == "Timeout" then
			text = "Timed Out"
		elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
			text = "Failed to Load 😞"
		end
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		if master ~= nil then
			master:queuecommand("CheckScorebox")
		end
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)

	-- BoogieStats integration
	-- Find out whether this chart is ranked on GrooveStats. 
	-- If it is unranked, alter groovestats logo and the box border color to the BoogieStats theme
	local headers = res.headers
	local boogie = false
	local boogie_ex = false
	if headers["bs-leaderboard-player-" .. n] == "BS" then
		boogie = true
	elseif headers["bs-leaderboard-player-" .. n] == "BS-EX" then
		boogie_ex = true
	end
	if not SCREENMAN:GetTopScreen():GetChild("Overlay") then return end
	local gsBox = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("ScoreBox" .. pn):GetChild("GrooveStatsLogo")
	local bsBox = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("ScoreBox" .. pn):GetChild("BoogieStatsLogo")
	local bsExBox = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("ScoreBox" .. pn):GetChild("BoogieStatsEXLogo")

	if boogie then
		style_color[0] = BoogieStatsPurple
		style_color[1] = BoogieStatsPurple
		bsBox:visible(true)
		bsExBox:visible(false)
		gsBox:visible(false)
	else
		style_color[0] = GrooveStatsBlue
		bsBox:visible(false)
		bsExBox:visible(false)
		gsBox:visible(true)
	end
	

	-- First check to see if the leaderboard even exists.
	if data and data[playerStr] then
		if SL[pn].Streams.Hash ~= data[playerStr]["chartHash"] then return end

		-- Seed the global-ITL-rank cache for the selected song so ITLRankManager
		-- doesn't re-fetch it (see Scripts/SL-Helpers-ITLRank.lua). Runs regardless
		-- of the ITL scorebox display toggle.
		if data[playerStr]["itl"] and data[playerStr]["itl"]["itlLeaderboard"] then
			local selfRank = false
			for entry in ivalues(data[playerStr]["itl"]["itlLeaderboard"]) do
				if entry["isSelf"] then selfRank = entry["rank"]; break end
			end
			ITLRankSet(data[playerStr]["chartHash"], selfRank)
			MESSAGEMAN:Broadcast("ITLRankResolved", { hash=data[playerStr]["chartHash"] })
		end

		-- These will get overwritten if we have any entries in the leaderboard below.
		SetScoreData(1, 1, "", "No Scores", "", false, false, false, false)
		SetScoreData(2, 1, "", "No Scores", "", false, false, false, false)
		
		all_data[1].has_data = false
		all_data[2].has_data = false
		
		-- Keep the player's own online score for this chart, when the operator has left
		-- Auto-Download Online Scores on. This rides the request the scorebox was making
		-- anyway rather than issuing one of its own, which is the whole reason importing is
		-- affordable at all: player-leaderboards.php takes one chart hash per request, and a
		-- hash costs a full simfile parse, so sweeping a library was never viable.
		--
		-- Exactness is already guaranteed above: this code is unreachable unless the
		-- response's chartHash equals the locally parsed one (see the early return), which
		-- is what stops two different charts that merely share a title being confused.
		local capture_song  = GAMESTATE:GetCurrentSong()
		local capture_steps = GAMESTATE:GetCurrentSteps(player)
		local capture_hash  = data[playerStr]["chartHash"]

		local Capture = function(field)
			if not ThemePrefs.Get("AutoDownloadScores") then return nil end
			if not capture_song or not capture_steps then return nil end
			if not PROFILEMAN:IsPersistentProfile(player) then return nil end

			return function(entry)
				-- A failed run is not a score. Same rule the local EX store and the wheel's
				-- ITG column follow, so nothing on that row disagrees about what counts.
				if entry["isFail"] then return end

				local raw = tonumber(entry["score"])
				if not raw then return end

				-- The API sends hundredths (9823), the store keeps percent (98.23).
				if OnlineScoreRecord(player, capture_song, capture_steps, field, raw/100, capture_hash) then
					OnlineScoresWrite(player)
				end
			end
		end

		local showITG = SL["P"..n].ActiveModifiers.SBITGScore
		local showEX = SL["P"..n].ActiveModifiers.SBEXScore
		local showEvents = SL["P"..n].ActiveModifiers.SBEvents
		
		cur_style = 0

		if SL["P"..n].ActiveModifiers.ShowEXScore then
			-- If the player is using EX scoring, then we want to display the EX leaderboard first.		
			if showEX then
				if data[playerStr]["exLeaderboard"] then
					FillBoard(1, data[playerStr]["exLeaderboard"], true, Capture("ex"))
				end
			end

			if showITG then
				if data[playerStr]["gsLeaderboard"] then
					FillBoard(2, data[playerStr]["gsLeaderboard"], boogie_ex, Capture("itg"))
				end
			end
		else
			-- Display the main GrooveStats leaderboard first if player is not using EX scoring.
			if showITG then
				if data[playerStr]["gsLeaderboard"] then
					FillBoard(1, data[playerStr]["gsLeaderboard"], boogie_ex, Capture("itg"))
				end
			end

			if showEX then
				if data[playerStr]["exLeaderboard"] then
					FillBoard(2, data[playerStr]["exLeaderboard"], true, Capture("ex"))
				end
			end
		end

		-- Display event boxes first if they are applicable
		if showEvents then
			if data[playerStr]["rpg"] then
				cur_style = 3
				SetScoreData(3, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["rpg"]["rpgLeaderboard"] then
					FillBoard(3, data[playerStr]["rpg"]["rpgLeaderboard"], false)
				end
			end

			if data[playerStr]["itl"] then
				cur_style = 4
				SetScoreData(4, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["itl"]["itlLeaderboard"] then
					FillBoard(4, data[playerStr]["itl"]["itlLeaderboard"], true, function(entry)
						UpdateItlExScore(player, SL[pn].Streams.Hash, entry["score"], GAMESTATE:GetCurrentSong(), GAMESTATE:GetCurrentSteps(player))
						SL["P"..n].itlScore = entry["score"]
						local stepartist = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("PerPlayer"):GetChild("StepArtistAF_P"..n)
						if stepartist ~= nil then
							stepartist:queuecommand("ITL")
						end
					end)
				end
			end
		end
 	end
	if master ~= nil then
		master:queuecommand("CheckScorebox")
	end
end

local af = Def.ActorFrame{
	Name="ScoreBox"..pn,
	InitCommand=function(self)
		if #GAMESTATE:GetHumanPlayers() == 1 then 
			self:x(SSM.scorebox.cx):y(SSM.cards.bottom.cy)
			if pn == "P2" then
				self:y(_screen.cy*1.65 - 55)
			end
		else
			if pn == "P1" then
				self:zoom(0.65):x(_screen.cx - 65):y(_screen.cy + 178)
				if IsNotWide then
					self:x(_screen.cx - 48)
				end
			else
				self:zoom(0.65):x(_screen.cx + 371):y(_screen.cy + 178)
				if IsNotWide then
					self:x(_screen.cx + 279)
				end
			end
		end
		self.isFirst = true
	end,
	ResetCommand=function(self) self:stoptweening() end,
	OffCommand=function(self) self:stoptweening() end,
	PlayerJoinedMessageCommand=function(self, params)
		if pn == "P1" then
			self:zoom(0.65):x(_screen.cx - 65):y(_screen.cy + 178)
			if IsNotWide then
				self:x(_screen.cx - 48)
			end
		else
			self:zoom(0.65):x(_screen.cx + 371):y(_screen.cy + 178)
			if IsNotWide then
				self:x(_screen.cx + 279)
			end
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:visible(false)
		end
		self:x(SSM.scorebox.cx):y(SSM.cards.bottom.cy):zoom(1)
		if pn == "P2" then
			self:y(_screen.cy*1.65 - 55)
		end
	end,
	CurrentSongChangedMessageCommand=function(self)
		self:finishtweening():visible(false)
		ResetAllData()
		self.isFirst = true
	end,
	CheckScoreboxCommand=function(self)
		if GAMESTATE:GetCurrentSong() and GAMESTATE:GetCurrentSteps(player) then
			self:queuecommand("LoopScorebox")
		end
	end,
	LoopScoreboxCommand=function(self)
		self:visible(true)
		
		local has_data = false
		if #all_data == 0 then return end
		for i=1,num_styles do
			if all_data[i].has_data then
				has_data = true
				break
			end
		end
		if not has_data then return end

		self:finishtweening()
		
		-- one pass over however many rows this box was built with, rather than the
		-- fifteen hardcoded lines that silently ignored rows 6 and up
		for i=1,NumEntries do
			self:GetChild("Name"..i):visible(true)
			self:GetChild("Score"..i):visible(true)
			self:GetChild("Rank"..i):visible(true)
		end
		self:GetChild("GrooveStatsLogo"):stopeffect()
		self:GetChild("BoogieStatsLogo"):stopeffect()
		self:GetChild("BoogieStatsEXLogo"):stopeffect()
		self:GetChild("SRPG8Logo"):visible(true)
		self:GetChild("ITLLogo"):visible(true)
		self:GetChild("Outline"):visible(true)
		self:GetChild("Background"):linear(transition_seconds/2):diffusealpha(body_alpha):visible(true)
		self:GetChild("CardDecor"):linear(transition_seconds/2):diffusealpha(1):visible(true)
		
		local start = cur_style

		cur_style = (cur_style + 1) % num_styles
		if cur_style ~= start or self.isFirst then
			-- Make sure we have the next set of data.
			while cur_style ~= start do
				if HasData(cur_style) then
					-- If this is the first time we're looping, update the start variable
					-- since it may be different than the default
					if self.isFirst then
						start = cur_style
						self.isFirst = false
						-- Continue looping to figure out the next style.
					else
						break
					end
				end
				cur_style = (cur_style + 1) % num_styles
			end
		end

		-- Loop only if there's something new to loop to.
		if start ~= cur_style then
			self:sleep(loop_seconds):queuecommand("LoopScorebox")
		end
	end,

	RequestResponseActor(0, 0)..{
		OnCommand=function(self)
			self:queuecommand("MakeRequest")
			-- Create variables for both players, even if they're not currently active.
			self.IsParsing = {false, false}
		end,
		-- Broadcasted from ./PerPlayer/DensityGraph.lua
		P1ChartParsingMessageCommand=function(self)	self.IsParsing[1] = true end,
		P2ChartParsingMessageCommand=function(self)	self.IsParsing[2] = true end,
		P1ChartParsedMessageCommand=function(self)
			self.IsParsing[1] = false
			if pn == "P1" then
				self:queuecommand("ChartParsed")
			end
		end,
		P2ChartParsedMessageCommand=function(self)
			self.IsParsing[2] = false
			if pn == "P2" then
				self:queuecommand("ChartParsed")
			end
		end,
		ChartParsedCommand=function(self)
			if not self.leaving_screen then
				self:queuecommand("MakeRequest")
			end
		end,
		MakeRequestCommand=function(self)				
			local sendRequest = false
			local headers = {}
			local query = {
				maxLeaderboardResults=NumEntries,
			}

			if SL[pn].ApiKey ~= "" and SL[pn].Streams.Hash ~= "" then
				query["chartHashP"..n] = SL[pn].Streams.Hash
				headers["x-api-key-player-"..n] = SL[pn].ApiKey
				sendRequest = true
			end

			-- We technically will send two requests in ultrawide versus mode since
			-- both players will have their own individual scoreboxes.
			-- Should be fine though.
			if sendRequest then
				if self.IsParsing[1] or self.IsParsing[2] then return end
				
				RemoveStaleCachedRequests()
				ResetAllData()
				
				self:GetParent():visible(true)
				for i=1,NumEntries do
					self:GetParent():GetChild("Name"..i):settext(""):visible(false)
					self:GetParent():GetChild("Score"..i):settext(""):visible(false)
					-- rank 1 is the crown sprite, which has no text to clear
					local rank = self:GetParent():GetChild("Rank"..i)
					if i == 1 then rank:diffusealpha(0) else rank:settext("") end
					rank:visible(false)
				end
				self:GetParent():GetChild("GrooveStatsLogo"):visible(true):diffusealpha(0.5):glowshift({color("#C8FFFF"), color("#6BF0FF")})
				self:GetParent():GetChild("BoogieStatsLogo"):visible(false)
				self:GetParent():GetChild("BoogieStatsEXLogo"):visible(false)
				self:GetParent():GetChild("SRPG8Logo"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("ITLLogo"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Outline"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Background"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("CardDecor"):diffusealpha(0):visible(false)
				
				if IsItlSong(player) then
					UpdatePathMap(player, SL[pn].Streams.Hash)
				end
				
				self:playcommand("MakeGrooveStatsRequest", {
					endpoint="player-leaderboards.php?"..NETWORK:EncodeQueryParameters(query),
					method="GET",
					headers=headers,
					timeout=10,
					callback=LeaderboardRequestProcessor,
					args=self:GetParent(),
				})
			end
		end
	},

	-- Outline
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(GrooveStatsBlue):setsize(width + border, height + border)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width + border - 40, height + border)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width + border - 40, height + border)
			else
				self:setsize(width + border, height + border)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width + border, height + border)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds):diffuse(style_color[cur_style])
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- Main body
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			self:diffuse(body_color):diffusealpha(body_alpha):setsize(width, height)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width - 40, height)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width - 40, height)
			else
				self:setsize(width, height)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width, height)
		end,
	},
	-- GrooveStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "GrooveStats.png"),
		Name="GrooveStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- BoogieStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "BoogieStats.png"),
		Name="BoogieStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- BoogieStats EX Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "BoogieStatsEX.png"),
		Name="BoogieStatsEXLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- EX Text
	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="EX",
		InitCommand=function(self)
			self:diffusealpha(0):x(2):y(-5)
		end,
		LoopScoreboxCommand=function(self)
			if (cur_style == 1 and not SL["P"..n].ActiveModifiers.ShowEXScore) or (cur_style == 0 and SL["P"..n].ActiveModifiers.ShowEXScore) then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.3)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- SRPG Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "_VisualStyles/SRPG8/logo_main (doubleres).png"),
		Name="SRPG8Logo",
		InitCommand=function(self)
			self:diffusealpha(0.4):zoom(0.05):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 2 then
				self:linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- ITL Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "ITL.png"),
		Name="ITLLogo",
		InitCommand=function(self)
			self:diffusealpha(0.2):zoom(0.45):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 3 then
				self:linear(transition_seconds/2):diffusealpha(0.2)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
}

-- Corner brackets, the same device as the left-column cards
-- (HUDCardDecor in Scripts/SL-Helpers-WheelPlate.lua). Added before the rows so
-- it sits over the body but under the text.
-- Shown and hidden in lockstep with Background/Outline below, so the brackets
-- can't be left floating over empty space while a request is in flight.
af[#af+1] = HUDCardDecor(width, height, 0, 0)..{
	Name="CardDecor",
	ResetCommand=function(self) self:stoptweening() end,
	OffCommand=function(self) self:stoptweening() end
}

for i=1,NumEntries do
	local y = -height/2 + ROW_H*i - ROW_H/2
	local zoom = row_zoom

	-- Band marking the player's own entry. The box holds NumEntries rows with no
	-- headroom for a header, so "which row is me" is carried by a filled band behind
	-- the row rather than by a label. Reads the same isSelf flag the name and score
	-- actors use for their text colour.
	af[#af+1] = Def.Quad{
		Name="SelfBand"..i,
		InitCommand=function(self)
			self:setsize(width - 4, ROW_H - 1):xy(0, y)
			self:diffuse(self_color):diffusealpha(0)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width - 44, ROW_H - 1)
			end
		end,
		PlayerJoinedMessageCommand=function(self)
			self:setsize(IsNotWide and (width - 44) or (width - 4), ROW_H - 1)
		end,
		PlayerUnjoinedMessageCommand=function(self)
			self:setsize(width - 4, ROW_H - 1)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			if score.isSelf then
				self:linear(transition_seconds/2):diffusealpha(0.16)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	-- Rank 1 gets a crown. Sized to the row rather than by a fixed zoom, which at the
	-- old 16px pitch was tuned to a row 60% taller than these.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoomto(ROW_H - 2, ROW_H - 2):xy(CROWN_X, y):diffusealpha(0)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(CROWN_X + 18)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				self:x(IsNotWide and (CROWN_X + 18) or CROWN_X)
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(CROWN_X)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				if score.rank ~= "" then
					self:linear(transition_seconds/2):diffusealpha(1)
				end
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="Rank"..i,
			Text="",
			InitCommand=function(self)
				self:diffuse(HUD_LABEL):xy(RANK_X, y):maxwidth(30):horizalign(right):zoom(zoom)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(RANK_X + 18)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				self:x(IsNotWide and (RANK_X + 18) or RANK_X)
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(RANK_X)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				local clr = HUD_LABEL
				if score.isSelf then
					clr = self_color
				elseif score.isRival then
					clr = rival_color
				end
				self:settext(score.rank)
				self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(HUD_TEXT):xy(NAME_X, y):maxwidth(name_maxwidth):horizalign(left):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(NAME_X + 18):maxwidth(70)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(NAME_X + 18):maxwidth(70)
			else
				self:x(NAME_X):maxwidth(name_maxwidth)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(NAME_X):maxwidth(name_maxwidth)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = HUD_TEXT
			if score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.name)
			self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Score"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(HUD_TEXT):xy(SCORE_X, y):horizalign(right):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(SCORE_X - 20)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			self:x(IsNotWide and (SCORE_X - 20) or SCORE_X)
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(SCORE_X)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = HUD_TEXT
			if score.isFail then
				clr = Color.Red
			elseif score.isEx then
				clr = SL.JudgmentColors["FA+"][1]
			elseif score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.score)
			self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}
end
return af
