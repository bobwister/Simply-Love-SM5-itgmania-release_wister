-- Currently the Density Graph in SSM doesn't work for Courses.
-- Disable the functionality.
if GAMESTATE:IsCourseMode() then return end


local player = ...
local pn = ToEnumShortString(player)

-- Height and width of the density graph, both from Scripts/SL-Layout-SelectMusic.lua.
--
-- The height was a hardcoded 64 while only the y came from the layout table, so the graph
-- kept its old size when the card around it changed and spilled over the cards above and
-- below. This card is the one that absorbs the stack's slack, so its height is not a
-- constant -- see the density_h comment in the layout table.
local height = SSM.cards.density.h
local width = SSM.column.w

-- The stream breakdown caption along the graph's bottom edge.
--
-- Same text scale as the chart counts in the stats pane (PaneDisplay.lua), so the two
-- read as one HUD rather than as two panels with their own ideas about type size -- it
-- used to be 0.8, noticeably larger than anything else in the column. The strip is
-- 4px shorter to match, which the histogram above it gets back.
-- TWEAK: keep BREAKDOWN_ZOOM in step with text_zoom in PaneDisplay.lua.
local BREAKDOWN_ZOOM = WideScale(0.58, 0.65)
local BREAKDOWN_H    = 13

local marquee_index

local text_table = {}
local leaving_screen = false
local breakdown_table = {}

local function CloseFolder()
	local wheel = SCREENMAN:GetTopScreen():GetMusicWheel()
	local section = wheel:GetSelectedSection()
	wheel:SetOpenSection(""):SetOpenSection(section):SetOpenSection("")
	wheel:Move(1)
	wheel:Move(-1)
	wheel:Move(0)
end
-- In 2-players mode, whether the DensityGraph or PatternInfo is shown
-- Can be toggled by the code "ToggleChartInfo" in metrics.ini
local showPatternInfo = false

local af = Def.ActorFrame{
	InitCommand=function(self)
		self:visible( GAMESTATE:IsHumanPlayer(player) )
		self:x(SSM.column.cx)
		if #GAMESTATE:GetHumanPlayers() == 1 then 
			self:y(SSM.cards.density.cy)
		else
			self:y(_screen.cy+23)
		end

		if player == PLAYER_2 then
			self:addy(height+24)
		end

	end,
	PlayerJoinedMessageCommand=function(self, params)
		self:x(SSM.column.cx)
		if #GAMESTATE:GetHumanPlayers() == 1 then 
			self:y(SSM.cards.density.cy)

		else
			self:y(_screen.cy+23)
		end
		if player == PLAYER_2 then
			self:addy(height+24)
		end

		if params.Player == player then
			self:visible(true)
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		self:x(SSM.column.cx)
		self:y(SSM.cards.density.cy)
		if player == PLAYER_2 then
			self:addy(height+24)
		end

		if params.Player == player then
			self:visible(false)
		end
	end,
	PlayerProfileSetMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Redraw")
		end
	end,
	CodeMessageCommand=function(self, params)
		-- The TogglePatternInfo code used to swap the density graph out for the pattern
		-- counts. Those are permanently visible in the stats pane now, so there is
		-- nothing left to swap to and the code is ignored. showPatternInfo stays false
		-- forever, which is what the visible(not showPatternInfo) calls below rely on.
		if (params.Name == "CloseFolder1" or params.Name == "CloseFolder2" or params.Name == "CloseFolder3") and params.Name == ThemePrefs.Get("CloseFolderCodes") then
			CloseFolder()
		end
	end,
}

-- Background quad for the density graph
af[#af+1] = Def.Quad{
	InitCommand=function(self)
		HUDPanel(self):zoomto(width, height)
		if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.9)
		end
	end
}

af[#af+1] = HUDCardDecor(width, height)

af[#af+1] = Def.ActorFrame{
	Name="ChartParser",
	-- Hide when scrolling through the wheel. This also handles the case of
	-- going from song -> folder. It will get unhidden after a chart is parsed
	-- below.
	CurrentSongChangedMessageCommand=function(self)
		self:queuecommand("Hide")
	end,
	["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self)
		self:queuecommand("Hide")
		self:stoptweening()
		self:sleep(0.4)
		self:queuecommand("ParseChart")
	end,
	ParseChartCommand=function(self)
		local steps = GAMESTATE:GetCurrentSteps(player)
		if steps then
			MESSAGEMAN:Broadcast(pn.."ChartParsing")
			ParseChartInfo(steps, pn)
			self:queuecommand("Show")
		end
	end,
	ShowCommand=function(self)
		if GAMESTATE:GetCurrentSong() and
				GAMESTATE:GetCurrentSteps(player) then
			MESSAGEMAN:Broadcast(pn.."ChartParsed")
			self:queuecommand("Redraw")
		else
			self:queuecommand("Hide")
		end
	end
}

local af2 = af[#af]

-- The Density Graph itself. It already has a "RedrawCommand".
-- The trailing `true` selects the monochrome Technique HUD palette (one hue,
-- fading toward the baseline); see Scripts/SL-Histogram.lua.
af2[#af2+1] = NPS_Histogram(player, width, height, nil, true)..{
	Name="DensityGraph",
	OnCommand=function(self)
		self:addx(-width/2):addy(height/2)
	end,
	HideCommand=function(self)
		self:visible(false)
	end,
	RedrawCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end
}
-- Don't let the density graph parse the chart.
-- We do this in parent actorframe because we want to "stall" before we parse.
af2[#af2]["CurrentSteps"..pn.."ChangedMessageCommand"] = nil

-- The bright edge tracing the graph's contour. Same width/height and the same
-- positioning as the fill above so the two stay registered, and it mirrors the
-- fill's visibility so Pattern Info hides both together.
af2[#af2+1] = NPS_Histogram_Stroke(player, width, height)..{
	Name="DensityGraphStroke",
	OnCommand=function(self)
		self:addx(-width/2):addy(height/2)
	end,
	HideCommand=function(self)
		self:visible(false)
	end,
	RedrawCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end
}
af2[#af2]["CurrentSteps"..pn.."ChangedMessageCommand"] = nil

-- The Peak NPS / eBPM readout used to be drawn here. It moved into the song description
-- card, between BPM and LENGTH, where it reads as part of the chart's vital statistics --
-- see SongDescription.lua, which picks it up off the <pn>ChartParsed broadcast above.

-- Breakdown
af2[#af2+1] = Def.ActorFrame{
	Name="Breakdown",
	InitCommand=function(self)
		self:addy(height/2 - BREAKDOWN_H/2)
	end,
	HideCommand=function(self)
		self:visible(false)
	end,
	RedrawCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	Def.Quad{
		InitCommand=function(self)
			-- caption strip under the graph; kept a touch darker than the panels
			-- behind it so the breakdown text reads against the histogram
			self:diffuse(color("#05080A")):zoomto(width, BREAKDOWN_H):diffusealpha(0.75)
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="",
		Name="BreakdownText",
		InitCommand=function(self)
			self:maxwidth(width/BREAKDOWN_ZOOM):zoom(BREAKDOWN_ZOOM)
		end,
		HideCommand=function(self)
			self:settext("")
		end,
		RedrawCommand=function(self)
			if leaving_screen then return end
			breakdown_table = {}
			marquee_index = 0
			self:settext(GenerateBreakdownText(pn, 0))
			breakdown_table[1] = GenerateBreakdownText(pn, 0)
			local minimization_level = 1
			while self:GetWidth() > (width/BREAKDOWN_ZOOM*(1+minimization_level*0.1)) and minimization_level < 4 do
				if self:GetWidth() < (width/BREAKDOWN_ZOOM*(1.7)) then
					breakdown_table[2] = GenerateBreakdownText(pn, minimization_level-1)
				end
				self:settext(GenerateBreakdownText(pn, minimization_level))
				breakdown_table[1] = GenerateBreakdownText(pn, minimization_level)
				minimization_level = minimization_level + 1
			end
			self:finishtweening():playcommand("Marquee",{breakdown_table=breakdown_table})
		end,
		MarqueeCommand=function(self)
			marquee_index = (marquee_index % #breakdown_table) + 1
			self:settext(breakdown_table[marquee_index])
			self:sleep(5):queuecommand("Marquee")
		end,
		OffCommand=function(self)
			self:stoptweening()
		end,
	}
}

-- The PatternInfo panel used to sit here: a 320x54 card holding Crossovers,
-- Footswitches, Sideswitches, Jacks, Brackets and Total Stream, occupying y 333..387.
-- Those six stats moved into the merged stats pane (PaneDisplay.lua), which frees this
-- band for the difficulty picker -- there was no free space in the column otherwise.
-- The pane refreshes them off the <pn>ChartParsed broadcast above.

return af