local player = ...
local pn = ToEnumShortString(player)

local mods = SL[pn].ActiveModifiers
local IsUltraWide = (GetScreenAspectRatio() > 21/9)
local NumPlayers = #GAMESTATE:GetHumanPlayers()

-- -----------------------------------------------------------------------
-- first, check for conditions where we might not draw the score actor at all

if mods.HideScore then return end

if NumPlayers > 1
and mods.NPSGraphAtTop
and not IsUltraWide
then
	return
end

-- -----------------------------------------------------------------------
-- positioning setup (unchanged from the previous single-score layout)

local styletype = ToEnumShortString(GAMESTATE:GetCurrentStyle():GetStyleType())

-- scores are not aligned symmetrically around screen.cx for aesthetic reasons
local pos = {
	[PLAYER_1] = { x=(_screen.cx - clamp(_screen.w, 640, 854)/4.3),  y=56 },
	[PLAYER_2] = { x=(_screen.cx + clamp(_screen.w, 640, 854)/2.75), y=56 },
}

local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)

-- -----------------------------------------------------------------------
-- score type -> color and formatted text

local ScoreColor = {
	ITGScore     = color("#ffffff"),          -- white
	EXScore      = SL.JudgmentColors["FA+"][1], -- blue #21CCE8
	SuperEXScore = color("#FF4FCB"),          -- magenta
}

local GetScoreText = function(score_type)
	if score_type == "ITGScore" then
		local dance_points = pss:GetPercentDancePoints()
		return FormatPercentScore(dance_points):sub(1,-2)
	elseif score_type == "EXScore" then
		return ("%.2f"):format(CalculateExScore(player))
	elseif score_type == "SuperEXScore" then
		return ("%.2f"):format(CalculateSuperExScore(player))
	end
	return ""
end

local zoom_primary   = 0.5
local zoom_secondary = 0.25
local secondary_gap  = 3

local font = ThemePrefs.Get("ThemeFont") .. " numbers"

-- -----------------------------------------------------------------------

return Def.ActorFrame{
	Name=pn.."Score",

	BeginCommand=function(self)
		-----------------------------------------------------------------
		-- ultrawide with both players joined is really its own layout
		if IsUltraWide and #GAMESTATE:GetHumanPlayers() > 1 then
			if player==PLAYER_1 then
				self:x(134)
			else
				self:x(_screen.w - 4)
			end
			self:y( 238 )
			return
		end
		-----------------------------------------------------------------

		-- assume "normal" score positioning first
		self:xy( pos[player].x, pos[player].y )

		if mods.NPSGraphAtTop and styletype ~= "OnePlayerTwoSides" then
			-- move the score to where the other player's score would be in versus
			if not NoteFieldIsCentered then
				self:x( pos[ OtherPlayer[player] ].x )
				self:y( pos[ OtherPlayer[player] ].y )
			end
		end
	end,

	-- PRIMARY score: right-aligned at the frame origin (same spot as before)
	LoadFont(font)..{
		Name="Primary",
		Text="0.00",
		InitCommand=function(self)
			self:valign(1):horizalign(right):zoom(zoom_primary)
			self:diffuse(ScoreColor[mods.PrimaryScore] or ScoreColor.ITGScore)
		end,
		BeginCommand=function(self) self:playcommand("Refresh") end,
		JudgmentMessageCommand=function(self) self:playcommand("Refresh") end,
		ExCountsChangedMessageCommand=function(self, params)
			if params.Player ~= player then return end
			self:playcommand("Refresh")
		end,
		RefreshCommand=function(self)
			self:settext( GetScoreText(mods.PrimaryScore) )
		end,
	},

	-- SECONDARY score: half size, just to the right of the primary; hidden when "None"
	LoadFont(font)..{
		Name="Secondary",
		Text="",
		InitCommand=function(self)
			if mods.SecondaryScore == "None" then
				self:visible(false)
				return
			end
			self:valign(1):horizalign(left):zoom(zoom_secondary)
			self:x(secondary_gap)
			self:diffuse(ScoreColor[mods.SecondaryScore] or ScoreColor.ITGScore)
		end,
		BeginCommand=function(self)
			if mods.SecondaryScore ~= "None" then self:playcommand("Refresh") end
		end,
		JudgmentMessageCommand=function(self)
			if mods.SecondaryScore ~= "None" then self:playcommand("Refresh") end
		end,
		ExCountsChangedMessageCommand=function(self, params)
			if mods.SecondaryScore == "None" then return end
			if params.Player ~= player then return end
			self:playcommand("Refresh")
		end,
		RefreshCommand=function(self)
			self:settext( GetScoreText(mods.SecondaryScore) )
		end,
	},
}
