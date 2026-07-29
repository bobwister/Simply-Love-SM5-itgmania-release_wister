local MusicWheel, SelectedType
local group_durations = LoadActor("./GroupDurations.lua")

-- width of background quad -- the shared column width, so this card lines up with the
-- banner above it and the density graph below (Scripts/SL-Layout-SelectMusic.lua)
local _w = SSM.column.w

-- TWEAK: text size and the two text rows inside the card. The card's height comes from
-- SSM.cards.song; these have to fit inside it. At 0.62 a Miso line's visible band is
-- 9.3px, so two rows 16px apart clear each other by ~7px, which is where the hairline
-- between them goes.
local DESC_ZOOM = 0.62
local ROW1_Y = -8
local ROW2_Y =  8
-- where the LENGTH pair sits, relative to the inner frame's origin
local LENGTH_X = 214
-- Peak NPS and eBPM, between BPM and LENGTH on the second row, same anchor convention.
-- TWEAK: NPS_X has to leave room to its left for a wide BPM range like "100-400".
local NPS_X  = 72
local EBPM_X = 138

-- Peak NPS for the master player, already scaled by the active music rate. nil until the
-- chart parser has run, and for a chart with no notes.
local function GetPeakNPS()
	local player = GAMESTATE:GetMasterPlayerNumber()
	if not player then return nil end
	local streams = SL[ToEnumShortString(player)].Streams
	if not streams or (streams.PeakNPS or 0) == 0 then return nil end
	return streams.PeakNPS * SL.Global.ActiveModifiers.MusicRate
end

local af = Def.ActorFrame{
	OnCommand=function(self)
		self:xy(SSM.column.cx, SSM.cards.song.cy)
	end,

	CurrentSongChangedMessageCommand=function(self)    self:playcommand("Set") end,
	CurrentCourseChangedMessageCommand=function(self)  self:playcommand("Set") end,
	CurrentStepsP1ChangedMessageCommand=function(self) self:playcommand("Set") end,
	CurrentTrailP1ChangedMessageCommand=function(self) self:playcommand("Set") end,
	CurrentStepsP2ChangedMessageCommand=function(self) self:playcommand("Set") end,
	CurrentTrailP2ChangedMessageCommand=function(self) self:playcommand("Set") end,
}

-- background Quad for Artist, BPM, and Song Length
af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:setsize( _w, SSM.cards.song.h )
		HUDPanel(self)

		if ThemePrefs.Get("RainbowMode") then self:diffusealpha(0.9) end
	end
}

af[#af+1] = HUDCardDecor(_w, SSM.cards.song.h)

-- Hairline splitting the card into its two rows: who wrote the song above, how it
-- plays below. The two text rows straddle the card's centre at ROW1_Y and ROW2_Y, so
-- y=0 lands in the gap between them.
af[#af+1] = Def.Quad{
	Name="DescriptionRule",
	InitCommand=function(self)
		self:zoomto(_w - 24, 1):y(0)
		self:playcommand("Paint")
	end,
	PaintCommand=function(self) self:diffuse( DimColor(PlayerColor(PLAYER_1), 1.0, 0.20) ) end,
	ColorSelectedMessageCommand=function(self) self:playcommand("Paint") end,
}

-- ActorFrame for Artist, BPM, and Song length
af[#af+1] = Def.ActorFrame{
	InitCommand=function(self) self:xy(-118, 0) end,

	-- Peak NPS and eBPM come from the chart parser rather than from the song, and parsing is
	-- deferred (DensityGraph.lua stalls 0.4s before it runs) -- so they refresh on the
	-- parser's own broadcast, not on this card's Set, which fires long before
	-- SL[pn].Streams has been filled in.
	P1ChartParsingMessageCommand=function(self) self:playcommand("ClearNPS") end,
	P2ChartParsingMessageCommand=function(self) self:playcommand("ClearNPS") end,
	P1ChartParsedMessageCommand=function(self)  self:playcommand("SetNPS") end,
	P2ChartParsedMessageCommand=function(self)  self:playcommand("SetNPS") end,

	-- ----------------------------------------
	-- Artist Label
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=THEME:GetString("SongDescription", GAMESTATE:IsCourseMode() and "NumSongs" or "Artist"):upper(),
		InitCommand=function(self) self:align(1,0.5):y(ROW1_Y):zoom(DESC_ZOOM):maxwidth(70/DESC_ZOOM):diffuse(HUD_LABEL) end,
	},

	-- Song Artist (or number of Songs in this Course, if CourseMode)
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self) self:align(0,0.5):xy(4,ROW1_Y):zoom(DESC_ZOOM):diffuse(HUD_TEXT) end,
		SetCommand=function(self)
			local maxwidth = (_w - 60)/DESC_ZOOM

			if GAMESTATE:IsCourseMode() then
				local course = GAMESTATE:GetCurrentCourse()
				self:settext( course and #course:GetCourseEntries() or "" )
			else
				local song = GAMESTATE:GetCurrentSong()
				self:settext( song and song:GetDisplayArtist() or "" )

				if not GAMESTATE:IsEventMode() and song and (song:IsLong() or song:IsMarathon()) then
					-- make room for the "COUNTS AS 2/3 ROUNDS" bubble
					maxwidth = maxwidth - 120/DESC_ZOOM
				end
			end

			self:maxwidth(maxwidth)
		end
	},

	-- ----------------------------------------
	-- BPM Label
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=THEME:GetString("SongDescription", "BPM"):upper(),
		InitCommand=function(self)
			self:align(1,0.5):y(ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_LABEL)
		end
	},

	-- BPM value
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self)
			-- vertical align has to be middle for BPM value in case of split BPMs having a line break
			self:align(0, 0.5)
			self:xy(4,ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_TEXT):vertspacing(-8)
		end,
		SetCommand=function(self)

			if MusicWheel then SelectedType = MusicWheel:GetSelectedType() end

			-- we only want to try to show BPM values for Songs and Courses
			-- not Section, Roulette, Random, Portal, Sort, or Custom
			-- (aside: what is "WheelItemDataType_Custom"?  I need to look into that.)
			if not (SelectedType=="WheelItemDataType_Song" or SelectedType=="WheelItemDataType_Course") then
				self:settext("")
				return
			end

			-- if only one player is joined, stringify the DisplayBPMs and return early
			if #GAMESTATE:GetHumanPlayers() == 1 then
				-- StringifyDisplayBPMs() is defined in ./Scipts/SL-BPMDisplayHelpers.lua
				self:settext(StringifyDisplayBPMs() or ""):zoom(DESC_ZOOM)
				return
			end

			-- otherwise there is more than one player joined and the possibility of split BPMs
			local p1bpm = StringifyDisplayBPMs(PLAYER_1)
			local p2bpm = StringifyDisplayBPMs(PLAYER_2)

			-- it's likely that BPM range is the same for both charts
			-- no need to show BPM ranges for both players if so
			if p1bpm == p2bpm then
				self:settext(p1bpm):zoom(DESC_ZOOM)

			-- different BPM ranges for the two players
			else
				-- show the range for both P1 and P2 split by a newline character, shrunk slightly to fit the space
				self:settext( "P1 ".. p1bpm .. "\n" .. "P2 " .. p2bpm ):zoom(DESC_ZOOM*0.8)
				-- the "P1 " and "P2 " segments of the string should be grey
				self:AddAttribute(0,             {Length=3, Diffuse=HUD_LABEL})
				self:AddAttribute(3+p1bpm:len(), {Length=3, Diffuse=HUD_LABEL})

				if GAMESTATE:IsCourseMode() then
					-- P1 and P2's BPM text in CourseMode is white until I have time to figure CourseMode out
					self:AddAttribute(3,             {Length=p1bpm:len(), Diffuse={1,1,1,1}})
					self:AddAttribute(7+p1bpm:len(), {Length=p2bpm:len(), Diffuse={1,1,1,1}})

				else
					-- P1 and P2's BPM text is the color of their difficulty
					if GAMESTATE:GetCurrentSteps(PLAYER_1) then
						self:AddAttribute(3,             {Length=p1bpm:len(), Diffuse=DifficultyColor(GAMESTATE:GetCurrentSteps(PLAYER_1):GetDifficulty())})
					end
					if GAMESTATE:GetCurrentSteps(PLAYER_2) then
						self:AddAttribute(7+p1bpm:len(), {Length=p2bpm:len(), Diffuse=DifficultyColor(GAMESTATE:GetCurrentSteps(PLAYER_2):GetDifficulty())})
					end
				end
			end
		end
	},

	-- ----------------------------------------
	-- Peak NPS and Peak eBPM. Labels are literals: both are untranslatable acronyms, like
	-- the XO/FS pairs in the stats pane.
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="NPS",
		InitCommand=function(self)
			self:align(1,0.5):xy(NPS_X, ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_LABEL)
		end,
		ClearNPSCommand=function(self) self:visible(false) end,
		SetNPSCommand=function(self) self:visible(GetPeakNPS() ~= nil) end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="PeakNPS",
		Text="",
		InitCommand=function(self)
			self:align(0,0.5):xy(NPS_X + 4, ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_TEXT)
		end,
		ClearNPSCommand=function(self) self:settext("") end,
		SetNPSCommand=function(self)
			local nps = GetPeakNPS()
			self:settext( nps and ("%.1f"):format(nps) or "" )
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="eBPM",
		InitCommand=function(self)
			self:align(1,0.5):xy(EBPM_X, ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_LABEL)
		end,
		ClearNPSCommand=function(self) self:visible(false) end,
		SetNPSCommand=function(self) self:visible(GetPeakNPS() ~= nil) end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="PeakEBPM",
		Text="",
		InitCommand=function(self)
			self:align(0,0.5):xy(EBPM_X + 4, ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_TEXT)
		end,
		ClearNPSCommand=function(self) self:settext("") end,
		SetNPSCommand=function(self)
			local nps = GetPeakNPS()
			self:settext( nps and ("%.0f"):format(nps * 15) or "" )
		end
	},

	-- ----------------------------------------
	-- Song Duration Label
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=THEME:GetString("SongDescription", "Length"):upper(),
		InitCommand=function(self)
			self:align(1,0.5):zoom(DESC_ZOOM):diffuse(HUD_LABEL)
			self:xy(LENGTH_X, ROW2_Y)
		end
	},

	-- Song Duration Value
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self) self:align(0,0.5):xy(LENGTH_X + 4, ROW2_Y):zoom(DESC_ZOOM):diffuse(HUD_TEXT) end,
		SetCommand=function(self)
			if MusicWheel == nil then MusicWheel = SCREENMAN:GetTopScreen():GetMusicWheel() end

			SelectedType = MusicWheel:GetSelectedType()
			local seconds

			if SelectedType == "WheelItemDataType_Song" then
				-- GAMESTATE:GetCurrentSong() can return nil here if we're in pay mode on round 2 (or later)
				-- and we're returning to SSM to find that the song we'd just played is no longer available
				-- because it exceeds the 2-round or 3-round time limit cutoff.
				local song = GAMESTATE:GetCurrentSong()
				if song then
					seconds = song:GetLastSecond()
				end

			elseif SelectedType == "WheelItemDataType_Section" then
				-- MusicWheel:GetSelectedSection() will return a string for the text of the currently active WheelItem
				-- use it here to look up the overall duration of this group from our precalculated table of group durations
				seconds = group_durations[MusicWheel:GetSelectedSection()]

			elseif SelectedType == "WheelItemDataType_Course" then
				-- is it possible for 2 Trails within the same Course to have differing durations?
				-- I can't think of a scenario where that would happen, but hey, this is StepMania.
				-- In any case, I'm opting to display the duration of the MPN's current trail.
				local trail = GAMESTATE:GetCurrentTrail(GAMESTATE:GetMasterPlayerNumber())
				if trail then
					seconds = TrailUtil.GetTotalSeconds(trail)
				end
			end

			-- r21 lol
			if seconds == 105.0 then self:settext(THEME:GetString("SongDescription", "r21")); return end

			if seconds then
				seconds = seconds / SL.Global.ActiveModifiers.MusicRate

				-- longer than 1 hour in length
				if seconds > 3600 then
					-- format to display as H:MM:SS
					self:settext(math.floor(seconds/3600) .. ":" .. SecondsToMMSS(seconds%3600))
				else
					-- format to display as M:SS
					self:settext(SecondsToMSS(seconds))
				end
			else
				self:settext("")
			end
		end
	}
}

if not GAMESTATE:IsEventMode() then

	-- long/marathon version bubble graphic and text
	af[#af+1] = Def.ActorFrame{
		InitCommand=function(self)
			self:x( IsUsingWideScreen() and 98 or 92 )
			self:y(-12)
		end,
		SetCommand=function(self)
			local song = GAMESTATE:GetCurrentSong()
			self:visible( song and (song:IsLong() or song:IsMarathon()) or false )
		end,


		Def.ActorMultiVertex{
			InitCommand=function(self)
				-- these coordinates aren't neat and tidy, but they do create three triangles
				-- that fit together to approximate hurtpiggypig's original png asset
				local verts = {
					--   x   y  z    r,g,b,a
					{{-113, -15, 0}, {1,1,1,1}},
					{{ 113, -15, 0}, {1,1,1,1}},
					{{ 113, 16, 0}, {1,1,1,1}},

					{{ 113, 16, 0}, {1,1,1,1}},
					{{-113, 16, 0}, {1,1,1,1}},
					{{-113, -15, 0}, {1,1,1,1}},

					{{ -98, 16, 0}, {1,1,1,1}},
					{{ -78, 16, 0}, {1,1,1,1}},
					{{ -88, 29, 0}, {1,1,1,1}},
				}
				self:SetDrawState({Mode="DrawMode_Triangles"}):SetVertices(verts)
				self:diffuse(GetCurrentColor())
				self:xy(0,0):zoom(0.5)
			end
		},

		LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			InitCommand=function(self) self:diffuse(Color.Black):zoom(0.8) end,
			SetCommand=function(self)
				local song = GAMESTATE:GetCurrentSong()
				if not song then self:settext(""); return end

				if song:IsMarathon() then
					self:settext(THEME:GetString("SongDescription", "IsMarathon"))
				elseif song:IsLong() then
					self:settext(THEME:GetString("SongDescription", "IsLong"))
				else
					self:settext("")
				end
			end
		}
	}
end

return af
