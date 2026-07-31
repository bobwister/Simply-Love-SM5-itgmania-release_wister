-- if we're in CourseMode, return a blank Actor now
if GAMESTATE:IsCourseMode() then return NullActor end

local player = nil
local pn = nil

local AwardMap = {
	["StageAward_FullComboW1"] = 1,
	["StageAward_FullComboW2"] = 2,
	["StageAward_SingleDigitW2"] = 2,
	["StageAward_OneW2"] = 2,
	["StageAward_FullComboW3"] = 3,
	["StageAward_SingleDigitW3"] = 3,
	["StageAward_OneW3"] = 3,
	["StageAward_100PercentW3"] = 3,
	-- FullComboW4 technically doesn't exist, but we create it on the fly below.
	["StageAward_FullComboW4"] = 4,
}

local ClearLamp = { color("#0000CC"), color("#990000") }

local function GetLamp(song)
	if player == nil then return nil end
	if not song then return nil end
	
	if not GAMESTATE:GetCurrentSteps(pn) then return nil end
	
	local diff = GAMESTATE:GetCurrentSteps(pn):GetDifficulty()
	
	local stepsList = song:GetAllSteps()
	local steps = nil
	
	for check in ivalues(stepsList) do
		if check:GetDifficulty() == diff and check:GetStepsType() == GAMESTATE:GetCurrentStyle():GetStepsType() then
			steps = check
			break
		end
	end
	
	if steps == nil then return nil end
	
	-- Check ITL File
	local itl_lamp = nil
	local song_dir = song:GetSongDir()
	if song_dir ~= nil and #song_dir ~= 0 then
		if SL[pn].ITLData["pathMap"][song_dir] ~= nil then
			local hash = SL[pn].ITLData["pathMap"][song_dir]
			if SL[pn].ITLData["hashMap"][hash] ~= nil then
				if SL[pn].ITLData["hashMap"][hash]["clearType"] == 5 then
					return 0
				end
			end
		end
	end
	
	local profile = PROFILEMAN:GetProfile(player)
	local high_score_list = profile:GetHighScoreListIfExists(song, steps)
			
	-- If no scores then just return.
	if high_score_list == nil or #high_score_list:GetHighScores() == 0 then
		return nil
	end

	local best_lamp = nil

	for score in ivalues(high_score_list:GetHighScores()) do
		local award = score:GetStageAward()
		
		if award and AwardMap[award] ~= nil then
			best_lamp = math.min(best_lamp and best_lamp or 999, AwardMap[award])
		end
		
		if AwardMap[award] == best_lamp and best_lamp == 1 and score:GetScore() == 0 then
			best_lamp = 0
		elseif best_lamp == nil then
			if score:GetGrade() == "Grade_Failed" then best_lamp = 52
			else best_lamp = 51 end
		end
	end

	return best_lamp
end


-- how many GradeTiers are defined in Metrics.ini?
local num_tiers = THEME:GetMetric("PlayerStageStats", "NumGradeTiersUsed")

-- make a grades table, and dynamically fill it with key/value pairs that we'll use in the
-- Def.Sprite below to set the Sprite to the appropriate state on the spritesheet of grades provided
--
-- keys will be in the format of "Grade_Tier01", "Grade_Tier02", "Grade_Tier03", etc.
-- values will start at 0 and go to (num_tiers-1)
local grades = {}
for i=1,num_tiers do
	grades[ ("Grade_Tier%02d"):format(i) ] = i-1
end
-- assign the "Grade_Failed" key a value equal to num_tiers
grades["Grade_Failed"] = num_tiers

-- The chart this row would be played on, at the difficulty currently selected.
--
-- Needed because the engine hands the two halves of a row's identity to two different
-- messages: "SetGrade" carries the grade but no song, "Set" carries the song but no grade.
local function ChartForRow(song)
	if not song or player == nil then return nil end

	local steps = GAMESTATE:GetCurrentSteps(player)
	local style = GAMESTATE:GetCurrentStyle()
	if not steps or not style then return nil end

	return song:GetOneSteps(style:GetStepsType(), steps:GetDifficulty())
end

-- Decide the sprite's state from whichever of the two messages arrived last.
--
-- Both always arrive, in the same call, but NOT in a fixed order: MusicWheelItem.cpp
-- sends "SetGrade" before "Set" when a row is first loaded (RefreshGrades at line 230,
-- the Set message at 331) and after it when the selected steps change (line 499-500).
-- So each message stores its own half and re-runs this, and the second one to land
-- settles it correctly whichever that turns out to be.
local function Decide(self)
	local state = nil
	if self.grade then state = grades[self.grade] end

	-- No local grade means the engine has never seen this chart played here; a local
	-- Grade_Failed means it has, and it didn't go well. A score imported from GrooveStats
	-- answers both: stars are a function of the ITG percentage and nothing else, so the
	-- tier it earns is the tier it earns, and a pass somewhere outranks a fail here --
	-- which is the rule the row's own ITG percentage already follows.
	if (state == nil or self.grade == "Grade_Failed") and player ~= nil then
		local chart = ChartForRow(self.song)
		local grade = chart and GradeFromPercent(OnlineScoreField(player, self.song, chart, "itg"))
		if grade then state = grades[grade] end
	end

	if state == nil then
		self:visible(false)
		return
	end

	-- The quint icon replaces the grade rather than sitting beside it, so it has the last
	-- word. Checked here rather than trusted to ordering: on a row's first load "SetGrade"
	-- arrives before "Set", so this can run while the Quint sprite still shows the
	-- PREVIOUS row's answer -- but its own SetCommand follows and settles both.
	local quint = self:GetParent() and self:GetParent():GetChild("Quint")
	if quint and quint:GetVisible() then
		self:visible(false)
		return
	end

	self:visible(true)
	self:setstate(state)
end

return Def.ActorFrame{
	Def.Sprite{
		Name="Grades",
		Texture=THEME:GetPathG("MusicWheelItem","Grades/grades 1x18.png"),
		InitCommand=function(self) self:zoom( SL_WideScale(0.18, 0.3) ):animate(false) end,

		-- "SetGrade" is broadcast by the engine in MusicWheelItem.cpp.
		-- It will be passed a table with, at minimum, one parameter:
		--     PlayerNumber (PlayerNumber enum as string)
		--
	   -- and potentially two more if the current song/course and steps/trail have a non-null HighScoreList
		--     Grade (GradeTier as number)
		--     NumTimesPlayed (number)
		SetGradeCommand=function(self, params)
			if params.PlayerNumber ~= nil then
				player=params.PlayerNumber
				pn=ToEnumShortString(params.PlayerNumber)
			end

			self.grade = params.Grade
			Decide(self)
		end,

		SetCommand=function(self, params)
			self.song = params.Song
			Decide(self)
		end,

		-- A score just arrived from GrooveStats for this row. Stars are a function of the
		-- ITG percentage, so an import can change this grade -- and without this the new
		-- star only appeared once the selection moved off the song and back.
		OnlineScoresUpdatedMessageCommand=function(self, params)
			if params and params.Song == self.song then Decide(self) end
		end,
	},
	
	Def.Sprite{
		Name="Quint",
		Texture=THEME:GetPathG("MusicWheelItem","Grades/quint.png"),
		InitCommand=function(self) self:zoom( SL_WideScale(0.18, 0.3) ):animate(false):visible(false) end,
		SetCommand=function(self, params)
			if not params.Song then return end
			if pn == nil then return end

			local lamp = GetLamp(params.Song)

			-- An imported EX of 100.00 means every note was a white fantastic, which is a
			-- quint. It is the one thing a bare percentage can prove about a judgment
			-- breakdown, and only because the perfect score has exactly one preimage --
			-- nothing short of 100.00 implies anything of the sort.
			local quinted = (lamp == 0)
			if not quinted then
				local chart = ChartForRow(params.Song)
				local ex = chart and OnlineScoreField(player, params.Song, chart, "ex")
				quinted = (type(ex) == "number" and ex >= 100)
			end

			if quinted then
				self:visible(true)
				self:GetParent():GetChild("Grades"):visible(false)
			else
				self:visible(false)
				if lamp ~= nil then
					self:GetParent():GetChild("Grades"):visible(true)
				end
			end
		end
	},
}
