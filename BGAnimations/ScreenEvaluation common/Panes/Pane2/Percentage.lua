local player, controller = unpack(...)
local pn = ToEnumShortString(player)
local mods = SL[pn].ActiveModifiers

local HEX_COLOR = color("#FF4FCB")
local show10 = true       -- toggle state for the score number marquee
local show10_label = true -- toggle state for the score type label marquee

local percent = nil
local diffuse = nil
-- when EX is the displayed score, precompute both EX and H.EX for the SmallerWhite marquee
local ex_percent, hex_percent
local marquee = false

if mods.ShowEXScore then
	local counts = GetExJudgmentCounts(player)
	ex_percent  = CalculateExScore(player, counts)
	hex_percent = CalculateSuperExScore(player, counts)
	percent = ex_percent
	diffuse = SL.JudgmentColors[SL.Global.GameMode][1]
	marquee = mods.SmallerWhite or false
else
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	local PercentDP = stats:GetPercentDancePoints()
	percent = FormatPercentScore(PercentDP):gsub("%%", "")
	-- Format the Percentage string, removing the % symbol
	percent = tonumber(percent)
	diffuse = Color.White
end

-- text label shown to the LEFT of the big score, matching its type/color
local score_label = mods.ShowEXScore and "EX" or "ITG"

return Def.ActorFrame{
	Name="PercentageContainer"..ToEnumShortString(player),
	OnCommand=function(self)
		self:y( _screen.cy-26 )
	end,

	-- dark background quad behind player percent score
	Def.Quad{
		InitCommand=function(self)
			self:diffuse(color("#101519")):zoomto(158.5, SL.Global.GameMode == "Casual" and 60 or 88)
			self:horizalign(controller==PLAYER_1 and left or right)
			self:x(150 * (controller == PLAYER_1 and -1 or 1))
			if SL.Global.GameMode ~= "Casual" then
				self:y(14)
			end
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0.5)
			end
		end
	},

	-- score type label ("ITG" / "EX" / "H. EX") to the LEFT of the big score.
	-- Uses the same font/color scheme as the secondary label in JudgmentLabels.lua.
	LoadFont(ThemePrefs.Get("ThemeFont") == "Common" and "Wendy/_wendy small"
			or ThemePrefs.Get("ThemeFont") == "Mega" and "Mega/_mega font"
			or ThemePrefs.Get("ThemeFont") == "Unprofessional" and "Unprofessional/_unprofessional small")..{
		Name="ScoreTypeLabel",
		Text=score_label,
		InitCommand=function(self)
			self:horizalign(right):zoom(0.5)
			-- TWEAK: horizontal position of the type label, to the left of the big number
			self:x( controller == PLAYER_1 and -95 or 45 )
			self:diffuse(diffuse)
		end,
		BeginCommand=function(self)
			if marquee then self:playcommand("Marquee") end
		end,
		MarqueeCommand=function(self)
			if show10_label then
				self:settext("H. EX"):diffuse(HEX_COLOR)
				show10_label = false
			else
				self:settext("EX"):diffuse(diffuse)
				show10_label = true
			end
			self:sleep(2):queuecommand("Marquee")
		end,
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
		Name="Percent",
		Text=("%.2f"):format(percent),
		InitCommand=function(self)
			-- Match the secondary score's effective size (JudgmentNumbers.lua: zoom 1.3
			-- inside its own 0.8-zoom parent frame = 1.04), + 10%, so this doesn't
			-- overlap the "ITG"/"EX" label to its left.
			self:horizalign(right):zoom(0.8 * 1.3 * 1.1)
			self:x( (controller == PLAYER_1 and 1.5 or 141))
			self:diffuse(diffuse)
		end,
		BeginCommand=function(self)
			if marquee then self:playcommand("Marquee") end
		end,
		MarqueeCommand=function(self)
			if show10 then
				self:settext(("%.2f"):format(hex_percent)):diffuse(HEX_COLOR)
				show10 = false
			else
				self:settext(("%.2f"):format(ex_percent)):diffuse(diffuse)
				show10 = true
			end
			self:sleep(2):queuecommand("Marquee")
		end,
	}
}
