local player = ...
local pn = ToEnumShortString(player)

if (not SL[pn].ActiveModifiers.DisplayScorebox or
		not IsServiceAllowed(SL.GrooveStats.GetScores) or
		SL[pn].ApiKey == "") then
	return
end

local n = player==PLAYER_1 and "1" or "2"
local IsUltraWide = (GetScreenAspectRatio() > 21/9)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)
-- Eight dense rows, matched to the song wheel's own scorebox
-- (BGAnimations/ScreenSelectMusic overlay/PerPlayer/Scorebox.lua) and to LocalLeaderboard,
-- so one leaderboard reads the same on both screens instead of being five large rows here
-- and eight small ones there. Both cards are 80px tall, so the metrics port straight over.
local NumEntries = 8

-- A hairline, not the old 5px slab: the HUD idiom carries a panel edge as a thin rule and
-- lets the fill do the work. It still takes the per-style colour, which is load-bearing --
-- that colour is what says whether you are looking at GrooveStats, SRPG or ITL.
local border = 2
local width = 162
local height = 80

-- A Miso line's visible band at 0.55 is 8.25px, leaving ~1.8px of leading in a 10px row.
local row_zoom = 0.55
local ROW_H    = height / NumEntries

-- Column anchors from the card's centre, replacing the raw "-width/2 + 27" literals that
-- used to sit inline in every row actor.
local RANK_X  = -width/2 + 18   -- right-aligned
local NAME_X  = -width/2 + 21   -- left-aligned
local SCORE_X =  width/2 - 3    -- right-aligned
local CROWN_X = -width/2 + 10

-- maxwidth is in UNZOOMED font units, so the screen budget is divided by the zoom.
-- SCORE_PX is the room kept clear for the widest score string at row_zoom.
local SCORE_PX = 34
local NAME_MAXWIDTH = ((SCORE_X - SCORE_PX) - NAME_X) / row_zoom

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
		all_data[#all_data + 1] = data
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
	if not SCREENMAN:GetTopScreen():GetChild("Underlay") then return end
	local gsBox = SCREENMAN:GetTopScreen():GetChild("Underlay"):GetChild("StepStatsPane" .. pn):GetChild("BannerAndData"):GetChild("ScoreBox" .. pn)
	if boogie then
		style_color[0] = BoogieStatsPurple
		style_color[1] = BoogieStatsPurple
		gsBox:queuecommand("BoogieStats")
	end

	-- First check to see if the leaderboard even exists.
	if data and data[playerStr] then
		-- These will get overwritten if we have any entries in the leaderboard below.
		SetScoreData(1, 1, "", "No Scores", "", false, false, false, false)
		SetScoreData(2, 1, "", "No Scores", "", false, false, false, false)
		
		all_data[1].has_data = false
		all_data[2].has_data = false
		
		local showITG = SL["P"..n].ActiveModifiers.SBITGScore
		local showEX = SL["P"..n].ActiveModifiers.SBEXScore
		local showEvents = SL["P"..n].ActiveModifiers.SBEvents

		local numEntries = 0
		if SL["P"..n].ActiveModifiers.ShowEXScore then
			-- If the player is using EX scoring, then we want to display the EX leaderboard first.
			if showEX then
				if data[playerStr]["exLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["exLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(1, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										true
									)
					end
				end
			end

			if showITG then
				if data[playerStr]["gsLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["gsLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(2, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										boogie_ex
									)
					end
				end
			end
		else
			-- Display the main GrooveStats leaderboard first if player is not using EX scoring.
			if showITG then
				if data[playerStr]["gsLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["gsLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(1, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										boogie_ex
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(1, i, "", "", "", "", "", "", true)
					end
				end
			end

			if showEX then
				if data[playerStr]["exLeaderboard"] then
					numEntries = 0
					for entry in ivalues(data[playerStr]["exLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(2, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										true
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(2, i, "", "", "", "", "", "", true)
					end
				end
			end
		end

		-- Display event boxes first if they are applicable
		if showEvents then
			if data[playerStr]["rpg"] then
				cur_style = 3
				local numEntries = 0
				SetScoreData(3, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["rpg"]["rpgLeaderboard"] then
					for entry in ivalues(data[playerStr]["rpg"]["rpgLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(3, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										false
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(3, i, "", "", "", "", "", "", true)
					end
				end
			end

			if data[playerStr]["itl"] then
				cur_style = 4
				local numEntries = 0
				SetScoreData(4, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["itl"]["itlLeaderboard"] then
					for entry in ivalues(data[playerStr]["itl"]["itlLeaderboard"]) do
						numEntries = numEntries + 1
						SetScoreData(4, numEntries,
										tostring(entry["rank"]),
										entry["name"],
										string.format("%.2f", entry["score"]/100),
										entry["isSelf"],
										entry["isRival"],
										entry["isFail"],
										true
									)
					end
					numEntries = numEntries + 1
					for i=math.max(2,numEntries),5,1 do
						SetScoreData(4, i, "", "", "", "", "", "", true)
					end
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
		self:xy(70 * (player==PLAYER_1 and 1 or -1), -115)
		-- offset a bit more when NoteFieldIsCentered
		if NoteFieldIsCentered and IsUsingWideScreen() then
			self:addx( 2 * (player==PLAYER_1 and 1 or -1) )
		end

		-- ultrawide and both players joined
		if IsUltraWide and #GAMESTATE:GetHumanPlayers() > 1 then
			self:x(self:GetX() * -1)
		end
		self.isFirst = true
	end,
	CheckScoreboxCommand=function(self)
		self:queuecommand("LoopScorebox")
	end,
	LoopScoreboxCommand=function(self)
		if #all_data == 0 then return end

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
		end,
		CurrentSongChangedMessageCommand=function(self)
				if not self.isFirst then
						ResetAllData()
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
				self:GetParent():GetChild("Name1"):settext("Loading...")
				self:GetParent():GetChild("Name2"):settext("")
				self:GetParent():GetChild("Name3"):settext("")
				self:GetParent():GetChild("Name4"):settext("")
				self:GetParent():GetChild("Name5"):settext("")
				self:GetParent():GetChild("Score1"):settext("")
				self:GetParent():GetChild("Score2"):settext("")
				self:GetParent():GetChild("Score3"):settext("")
				self:GetParent():GetChild("Score4"):settext("")
				self:GetParent():GetChild("Score5"):settext("")
				self:GetParent():GetChild("Rank1"):diffusealpha(0)
				self:GetParent():GetChild("Rank2"):settext("")
				self:GetParent():GetChild("Rank3"):settext("")
				self:GetParent():GetChild("Rank4"):settext("")
				self:GetParent():GetChild("Rank5"):settext("")
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
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds):diffuse(style_color[cur_style])
		end
	},
	-- Main body, in the shared HUD panel ink rather than pure black, so this card matches
	-- the ones down the left column of the song wheel. HUDPanel applies both the colour and
	-- the alpha (Scripts/SL-Helpers-WheelPlate.lua).
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			HUDPanel(self):setsize(width, height)
		end,
	},

	-- Corner brackets: the device that marks a panel as a HUD card everywhere else in the
	-- theme. Repaints itself on ColorSelected, like every other HUDCardDecor.
	HUDCardDecor(width, height, 0, 0)..{ Name="CardDecor" },
	-- GrooveStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "GrooveStats.png"),
		Name="GrooveStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8):diffusealpha(0.5)
		end,
		BoogieStatsCommand=function(self)
			self:Load(THEME:GetPathG("", "BoogieStats.png"))
		end,
		BoogieStatsEXCommand=function(self)
			self:Load(THEME:GetPathG("", "BoogieStatsEX.png"))
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end
	},
	-- EX Text
	Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="EX",
		InitCommand=function(self)
			self:diffusealpha(0.3):x(2):y(-5)
		end,
		LoopScoreboxCommand=function(self)
			if (cur_style == 1 and not SL["P"..n].ActiveModifiers.ShowEXScore) or (cur_style == 0 and SL["P"..n].ActiveModifiers.ShowEXScore) then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.3)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end
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
		end
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
		end
	},
}

for i=1,NumEntries do
	local y = -height/2 + ROW_H*i - ROW_H/2
	local zoom = row_zoom

	-- Band marking your own entry. Eight rows leave no headroom for a header, so "which row
	-- is me" is carried by a filled band behind the row rather than by a label -- the same
	-- device the wheel's scorebox uses, reading the same isSelf flag as the text below.
	af[#af+1] = Def.Quad{
		Name="SelfBand"..i,
		InitCommand=function(self)
			self:setsize(width - 4, ROW_H - 1):xy(0, y)
			self:diffuse(self_color):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			if score.isSelf then
				self:linear(transition_seconds/2):diffusealpha(0.16)
			end
		end
	}

	-- Rank 1 gets a crown.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoomto(ROW_H - 2, ROW_H - 2):xy(CROWN_X, y):diffusealpha(0)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				if score.rank ~= "" then
					self:linear(transition_seconds/2):diffusealpha(1)
				end
			end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="Rank"..i,
			Text="",
			InitCommand=function(self)
				self:diffuse(HUD_LABEL):xy(RANK_X, y):maxwidth(30):horizalign(right):zoom(zoom)
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
			end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(HUD_TEXT):xy(NAME_X, y):maxwidth(NAME_MAXWIDTH):horizalign(left):zoom(zoom)
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
		end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Score"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(HUD_TEXT):xy(SCORE_X, y):horizalign(right):zoom(zoom)
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
		end
	}
end
return af
