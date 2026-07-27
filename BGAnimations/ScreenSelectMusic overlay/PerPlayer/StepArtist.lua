local player = ...
local pn = ToEnumShortString(player)
local p = PlayerNumber:Reverse()[player]

local text_table, marquee_index

-- Card geometry, from Scripts/SL-Layout-SelectMusic.lua. This frame's origin is the
-- card's TOP-LEFT corner, so every offset below is measured from there -- the old
-- 120/18 pair was measured from a frame origin that sat outside the card entirely.
--
-- APPEAR_LIFT: the AppearP1 tween lifts this frame 30px on entry, so the frame has to
-- start 30px below where it settles.
local CARD_W = SSM.column.w
local CARD_H = SSM.cards.artist.h
local APPEAR_LIFT = 30

-- TWEAK: text size in the card, and where the STEPS label and the credit sit.
--
-- CREDIT_Y is the top of the text block, so it is also the card's top margin -- the text
-- used to start 1px in, which read as no margin at all on the common one-line credit. A
-- Miso line at 0.55 is 13.2px, so three credit lines from CREDIT_Y need 40px of CARD_H.
local CARD_ZOOM   = 0.55
local LABEL_X     = 10
local CREDIT_X    = 50
local CREDIT_Y    = 4
local CREDIT_MAXW = 330

-- The difficulty hue over the card, as a vertical gradient rather than a flat wash:
-- strongest along the top edge, almost gone by the bottom. Same idea as the difficulty
-- rule along the top of the stats pane, just spread over the card.
-- TWEAK: the two ends of the gradient.
local DIFFICULTY_TINT_TOP    = 0.32
local DIFFICULTY_TINT_BOTTOM = 0.04

-- EX score is a number like 92.67
local GetPointsForSong = function(maxPoints, exScore)
	local thresholdEx = 50.0
	local percentPoints = 40.0

	-- Helper function to take the logarithm with a specific base.
	local logn = function(x, y)
		return math.log(x) / math.log(y)
	end

	-- The first half (logarithmic portion) of the scoring curve.
	local first = logn(
		math.min(exScore, thresholdEx) + 1,
		math.pow(thresholdEx + 1, 1 / percentPoints)
	)

	-- The seconf half (exponential portion) of the scoring curve.
	local second = math.pow(
		100 - percentPoints + 1,
		math.max(0, exScore - thresholdEx) / (100 - thresholdEx)
	) - 1

	-- Helper function to round to a specific number of decimal places.
	-- We want 100% EX to actually grant 100% of the points.
	-- We don't want to  lose out on any single points if possible. E.g. If
	-- 100% EX returns a number like 0.9999999999999997 and the chart points is
	-- 6500, then 6500 * 0.9999999999999997 = 6499.99999999999805, where
	-- flooring would give us 6499 which is wrong.
	local roundPlaces = function(x, places)
		local factor = 10 ^ places
		return math.floor(x * factor + 0.5) / factor
	end

	local percent = roundPlaces((first + second) / 100.0, 6)
	return math.floor(maxPoints * percent)
end

return Def.ActorFrame{
	Name="StepArtistAF_" .. pn,

	-- song and course changes
	OnCommand=function(self) self:queuecommand("Reset") end,
	["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self) self:queuecommand("Reset") end,
	CurrentSongChangedMessageCommand=function(self) self:queuecommand("Reset") end,
	CurrentCourseChangedMessageCommand=function(self) self:queuecommand("Reset") end,

	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Appear" .. pn)
		end
	end,

	-- Simply Love doesn't support player unjoining (that I'm aware of!) but this
	-- animation is left here as a reminder to a future me to maybe look into it.
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:ease(0.5, 275):addy(scale(p,0,1,1,-1) * 30):diffusealpha(0)
		end
	end,

	-- depending on the value of pn, this will either become
	-- an AppearP1Command or an AppearP2Command when the screen initializes
	["Appear"..pn.."Command"]=function(self) self:visible(true):ease(0.5, 275):addy(scale(p,0,1,-1,1) * 30):diffusealpha(1) end,

	InitCommand=function(self)
		self:visible( false ):halign( p )

		if player == PLAYER_1 then

			if GAMESTATE:IsCourseMode() then
				self:x( SSM.column.left )
				self:y(_screen.cy + 32)
			else
				self:x( SSM.column.left )
				self:y( SSM.cards.artist.top + APPEAR_LIFT )
			end

		elseif player == PLAYER_2 then

			if GAMESTATE:IsCourseMode() then
				self:x( _screen.cx - 210)
				self:y(_screen.cy + 85)
			else
				self:x( _screen.cx - 260)
				self:y(_screen.cy + 40)
			end
		end

		if GAMESTATE:IsHumanPlayer(player) then
			self:queuecommand("Appear" .. pn)
		end
	end,

	-- The card's own ink, the same HUD_PANEL_COLOR every other panel in this column uses,
	-- so the stack reads as one set of cards.
	--
	-- This used to be a single quad diffused with a dimmed difficulty colour, which meant
	-- the difficulty hue REPLACED the shared ink instead of sitting on it -- and a
	-- fadebottom scaled to the credit line count erased most of the fill (80% of it for a
	-- one-line credit). The hue is now a separate translucent layer below, and there is no
	-- fade: the card is sized to its content, so it has nothing to fade out.
	Def.Quad{
		Name="BackgroundQuad",
		InitCommand=function(self)
			if #GAMESTATE:GetHumanPlayers() == 1 then
				self:zoomto(CARD_W, CARD_H):x(CARD_W/2):y(CARD_H/2)
			else
				self:zoomto(175, _screen.h/28):x(113):y(0)
			end
			HUDPanel(self)
		end
	},

	-- The difficulty hue, over the ink.
	--
	-- diffusetopedge / diffusebottomedge set the quad's two pairs of vertex colours
	-- independently, which is what makes the gradient -- so this must NOT be followed by a
	-- diffuse() or diffusealpha(), either of which would flatten all four corners again.
	Def.Quad{
		Name="DifficultyTint",
		InitCommand=function(self)
			if #GAMESTATE:GetHumanPlayers() == 1 then
				self:zoomto(CARD_W, CARD_H):x(CARD_W/2):y(CARD_H/2)
			else
				self:zoomto(175, _screen.h/28):x(113):y(0)
			end
			self:diffusealpha(0)
		end,
		ResetCommand=function(self)
			local StepsOrTrail = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player) or GAMESTATE:GetCurrentSteps(player)
			local hue = StepsOrTrail and DifficultyColor(StepsOrTrail:GetDifficulty()) or PlayerColor(player)
			self:diffusetopedge(    { hue[1], hue[2], hue[3], DIFFICULTY_TINT_TOP    } )
			self:diffusebottomedge( { hue[1], hue[2], hue[3], DIFFICULTY_TINT_BOTTOM } )
		end
	},

	HUDCardDecor(CARD_W, CARD_H, CARD_W/2, CARD_H/2),

	--STEPS label
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=GAMESTATE:IsCourseMode() and Screen.String("SongNumber"):format(1) or Screen.String("STEPS"),
		InitCommand=function(self)
			self:diffuse(HUD_LABEL):halign(0):valign(0):xy(LABEL_X, CREDIT_Y):maxwidth(60/CARD_ZOOM):zoom(CARD_ZOOM)
		end,
		UpdateTrailTextMessageCommand=function(self, params)
			self:settext( THEME:GetString("ScreenSelectCourse", "SongNumber"):format(params.index) )
		end
	},

	--stepartist text
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		InitCommand=function(self)
			-- valign(0) here and on the STEPS label above: both line boxes then start on the
			-- same y, which is the only way to be sure the two line up.
			self:diffuse(HUD_TEXT):halign(0):valign(0):y(CREDIT_Y):zoom(CARD_ZOOM)
			if GAMESTATE:IsCourseMode() then
				self:x(70):maxwidth(138)
			else
				self:x(CREDIT_X):diffuse(HUD_TEXT)
				if #GAMESTATE:GetHumanPlayers() == 1 then 
					self:maxwidth(CREDIT_MAXW)
				else
					self:maxwidth(160)
				end
			end
		end,
		ResetCommand=function(self)

			local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()
			local StepsOrTrail = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player) or GAMESTATE:GetCurrentSteps(player)

			-- always stop tweening when steps change in case a MarqueeCommand is queued
			self:stoptweening()

			if SongOrCourse and StepsOrTrail then

				text_table = GetStepsCredit(player)
				marquee_index = 0

				-- don't queue a Marquee in CourseMode
				-- each TrailEntry text change will be broadcast from CourseContentsList.lua
				-- to ensure it stays synced with the scrolling list of songs
				if not GAMESTATE:IsCourseMode() then
					-- only queue a Marquee if there are things in the text_table to display
					self:x(CREDIT_X):diffuse(HUD_TEXT)
					if #GAMESTATE:GetHumanPlayers() == 1 then 
						self:maxwidth(CREDIT_MAXW)
					else
						self:maxwidth(160)
					end

					if #text_table > 0 then
						if #GAMESTATE:GetHumanPlayers() > 1 then self:queuecommand("Marquee") end
						local fulldesc = ""
						for i=1,#text_table do
							local curText = text_table[i]
							fulldesc = fulldesc .. curText .. "\n"
						end
						self:vertalign("VertAlign_Top"):settext(fulldesc):y(CREDIT_Y)
					else
						-- no credit information was specified in the simfile for this stepchart, so just set to an empty string
						self:settext("")
					end
				end
			else
				-- there wasn't a song/course or a steps object, so the MusicWheel is probably hovering
				-- on a group title, which means we want to set the stepartist text to an empty string for now
				self:settext("")
			end
		end,
		ITLCommand=function(self)
			if #GAMESTATE:GetHumanPlayers() == 1 then
				local SongOrCourse = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse() or GAMESTATE:GetCurrentSong()
				local StepsOrTrail = GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player) or GAMESTATE:GetCurrentSteps(player)

				-- always stop tweening when steps change in case a MarqueeCommand is queued
				self:stoptweening()

				if SongOrCourse and StepsOrTrail then

					text_table = GetStepsCredit(player)
					marquee_index = 0

					-- don't queue a Marquee in CourseMode
					-- each TrailEntry text change will be broadcast from CourseContentsList.lua
					-- to ensure it stays synced with the scrolling list of songs
					if not GAMESTATE:IsCourseMode() then
						-- only queue a Marquee if there are things in the text_table to display
						if #text_table > 0 then
							-- self:queuecommand("Marquee")
							local fulldesc = ""
							for i=1,#text_table do
								local curText = text_table[i]
								if string.sub(curText, string.len(curText) - 3, string.len(curText)) == " pts" then
									local max_points = string.sub(curText, 1, string.len(curText) - 4)
									local exscore = tonumber(SL[pn].itlScore)/100
									local max_point_multiplier = 0
									if exscore then
										local points = GetPointsForSong(max_points, exscore)
										local pointsPercent = string.format("%.2f%%", points / max_points * 100)
										curText = points .. "/" .. curText .. " ("..pointsPercent..")"
									end
								end
								fulldesc = fulldesc .. curText .. "\n"
							end
							self:vertalign("VertAlign_Top"):settext(fulldesc):y(CREDIT_Y)
						else
							-- no credit information was specified in the simfile for this stepchart, so just set to an empty string
							self:settext("")
						end
					end
				else
					-- there wasn't a song/course or a steps object, so the MusicWheel is probably hovering
					-- on a group title, which means we want to set the stepartist text to an empty string for now
					self:settext("")
				end
			end
		end,
		MarqueeCommand=function(self)
			-- increment the marquee_index, and keep it in bounds
			marquee_index = (marquee_index % #text_table) + 1
			-- retrieve the text we want to display
			local text = text_table[marquee_index]

			-- set this BitmapText actor to display that text
			self:settext( text )

			-- check for emojis; they shouldn't be diffused to Color.Black
			DiffuseEmojis(self, text)

			if not GAMESTATE:IsCourseMode() then
				-- sleep 2 seconds before queueing the next Marquee command to do this again
				if #text_table > 1 then
					self:sleep(2):queuecommand("Marquee")
				end
			else
				self:sleep(0.5):queuecommand("m")
			end
		end,
		UpdateTrailTextMessageCommand=function(self, params)
			if text_table then
				self:settext( text_table[params.index] or "" )
			end
		end,
		OffCommand=function(self) self:stoptweening() end
	}
}