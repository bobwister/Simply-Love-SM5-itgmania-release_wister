-- The selected chart's leaderboard, taken from the machine profile.
--
-- This fills the right half of the left column's bottom card whenever the GrooveStats
-- scorebox cannot -- no API key on the profile, GrooveStats unreachable or switched off,
-- course mode, or MusicWheelGS set to something other than "Scorebox". That is most of the
-- time on a home cabinet, and it was leaving that half of the card blank.
--
-- The machine profile keeps up to MaxHighScoresPerListForMachine scores per chart (10 by
-- default), which already IS a leaderboard for that chart: everyone who has played it here,
-- best first. Nothing has to be fetched or computed.
--
-- Rows use the same anchors, scale and colours as PerPlayer/Scorebox.lua, so whichever of
-- the two owns the card it looks like the same panel.

local player = GAMESTATE:GetMasterPlayerNumber() or PLAYER_1

-- The GrooveStats box has first claim; see SSM_GrooveStatsBoxActive.
if SSM_GrooveStatsBoxActive(player) then return Def.Actor{} end

local W = SSM.scorebox.w
local H = SSM.scorebox.h

-- Eight rows at 0.55 rather than five at 0.87.
--
-- The machine keeps ten scores per chart (MaxHighScoresPerListForMachine), so five rows
-- were throwing half the board away for no reason other than the type size inherited from
-- the GrooveStats box -- which is capped at five by its own request and cannot use the
-- extra rows. A Miso line's visible band at 0.55 is 8.25px, so ROW_H leaves ~1.8px of
-- leading, which is what a dense HUD table wants.
-- TWEAK: NUM_ROWS and ROW_ZOOM trade rows against legibility; they have to stay in step.
local NUM_ROWS = 8
local ROW_H    = H / NUM_ROWS
local ROW_ZOOM = 0.55
local BORDER   = 2

-- Column anchors, from the card's centre.
local RANK_X  = -W/2 + 18   -- right-aligned
local NAME_X  = -W/2 + 21   -- left-aligned
local SCORE_X =  W/2 - 3    -- right-aligned
local CROWN_X = -W/2 + 10

-- Widest score string at ROW_ZOOM ("100.00%" measures 30.8px), which is what the name has
-- to stop short of.
local SCORE_PX = 32
local NAME_MAXWIDTH = math.floor(((SCORE_X - SCORE_PX - 3) - NAME_X) / ROW_ZOOM)

local body_color = color("#0B1116")
local body_alpha = 0.94
local self_color = color("#a1ff94")

local machine = PROFILEMAN:GetMachineProfile()

-- Rebuilt on every song/steps change and read by the row actors, which redraw from it
-- rather than each looking the list up again.
local rows = {}
local have_chart = false

-- The name the player's own scores are saved under, so their row can be picked out of the
-- board the way the GrooveStats box picks out isSelf. nil when playing on a guest profile.
local function MyScoreName()
	if not PROFILEMAN:IsPersistentProfile(player) then return nil end
	local profile = PROFILEMAN:GetProfile(player)
	local name = profile:GetLastUsedHighScoreName()
	if name and name ~= "" then return name end
	name = profile:GetDisplayName()
	return (name ~= "" and name or nil)
end

local function Gather()
	rows = {}
	have_chart = false

	local song  = GAMESTATE:GetCurrentSong()
	local steps = GAMESTATE:GetCurrentSteps(player)
	-- no song or no chart means the wheel is sitting on a group row
	if not song or not steps then return end
	have_chart = true

	local list = machine:GetHighScoreListIfExists(song, steps)
	if not list then return end

	local me = MyScoreName()

	-- The whole board first, then the rows worth showing. The machine keeps ten scores
	-- per chart and there are eight slots, so the last two would otherwise be dropped
	-- blind -- including the player's own row if they sit ninth on a busy chart.
	-- There are no rivals on a local board; SelectLeaderboardRows keeps the leader and
	-- the player.
	local all = {}
	for i, score in ipairs(list:GetHighScores()) do
		local name = score:GetName()
		all[i] = {
			rank   = i,
			name   = (name ~= "" and name or "----"),
			pct    = FormatPercentScore( score:GetPercentDP() ),
			failed = (score:GetGrade() == "Grade_Failed"),
			isSelf = (me ~= nil and name == me),
		}
	end

	rows = SelectLeaderboardRows(all, NUM_ROWS)
end

local af = Def.ActorFrame{
	Name="LocalLeaderboard",
	InitCommand=function(self)
		self:xy(SSM.scorebox.cx, SSM.cards.bottom.cy)
	end,

	-- Everything below redraws off "Redraw", which only the parent's Set fires -- so the
	-- list is gathered once per change rather than once per row.
	OnCommand=function(self)                            self:playcommand("Set") end,
	CurrentSongChangedMessageCommand=function(self)     self:playcommand("Set") end,
	CurrentCourseChangedMessageCommand=function(self)   self:playcommand("Set") end,
	CurrentStepsP1ChangedMessageCommand=function(self)  self:playcommand("Set") end,
	CurrentStepsP2ChangedMessageCommand=function(self)  self:playcommand("Set") end,
	PlayerProfileSetMessageCommand=function(self)       self:playcommand("Set") end,
	-- The footer retries the GrooveStats handshake on this screen, so the reason this
	-- board gives for being empty can change while it is on screen.
	GrooveStatsSessionResolvedMessageCommand=function(self) self:playcommand("Redraw") end,
	SetCommand=function(self)
		Gather()
		self:playcommand("Redraw")
	end,

	-- Hairline border, the same device as the GrooveStats box: drawn behind the body so
	-- only BORDER/2 of it shows on each side.
	Def.Quad{
		InitCommand=function(self)
			self:setsize(W + BORDER, H + BORDER)
			self:diffuse( DimColor(PlayerColor(PLAYER_1), 1.0, 0.45) )
		end
	},

	Def.Quad{
		InitCommand=function(self)
			self:setsize(W, H):diffuse(body_color):diffusealpha(body_alpha)
		end
	},
}

af[#af+1] = HUDCardDecor(W, H, 0, 0)

-- Why the board is empty.
--
-- "No scores yet" is only the answer when GrooveStats is working: with an online board
-- there would be somebody's scores to show whether or not this player has any. So when the
-- board comes up blank, say which link in the chain is missing instead -- that is the
-- actionable part, and it is the same chain the footer's connection light reports.
local function EmptyReason()
	if not ThemePrefs.Get("EnableGrooveStats") then return "GrooveStatsOff"    end
	if not SL.GrooveStats.IsConnected          then return "GrooveStatsOffline" end
	if SL[ToEnumShortString(player)].ApiKey == "" then return "GrooveStatsNoKey" end
	return "LocalBoardEmpty"
end

-- Shown only when a chart is selected and there is nothing to list. On a group row the
-- card stays blank rather than claiming there are no scores for a chart nobody picked.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	InitCommand=function(self)
		self:zoom(0.7):diffuse(HUD_LABEL):maxwidth((W - 12)/0.7):visible(false)
	end,
	RedrawCommand=function(self)
		local show = have_chart and #rows == 0
		self:visible(show)
		if show then
			self:settext( THEME:GetString("ScreenSelectMusic", EmptyReason()) )
		end
	end
}

for i = 1, NUM_ROWS do
	local y = -H/2 + ROW_H*i - ROW_H/2

	-- Band marking the player's own entry. Eight rows leave no headroom for a header, so
	-- "which row is me" is carried by a filled band rather than by a label.
	af[#af+1] = Def.Quad{
		InitCommand=function(self)
			self:setsize(W - 4, ROW_H - 1):xy(0, y)
			self:diffuse(self_color):diffusealpha(0)
		end,
		RedrawCommand=function(self)
			self:diffusealpha( (rows[i] and rows[i].isSelf) and 0.16 or 0 )
		end
	}

	-- Rank 1 gets a crown, the rest a number. Sized to the row rather than to the old
	-- 16px one, which would have overflowed two rows either side.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoomto(ROW_H - 2, ROW_H - 2):xy(CROWN_X, y):visible(false)
			end,
			RedrawCommand=function(self) self:visible( rows[i] ~= nil ) end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Text="",
			InitCommand=function(self)
				self:xy(RANK_X, y):horizalign(right):zoom(ROW_ZOOM):maxwidth(30)
				self:diffuse(HUD_LABEL)
			end,
			-- the entry's own rank, not the slot it landed in: the board can skip ranks
			-- now that it keeps the player's row wherever it sits
			RedrawCommand=function(self) self:settext( rows[i] and (rows[i].rank..".") or "" ) end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="",
		InitCommand=function(self)
			self:xy(NAME_X, y):horizalign(left):zoom(ROW_ZOOM):maxwidth(NAME_MAXWIDTH)
		end,
		RedrawCommand=function(self)
			local row = rows[i]
			self:settext( row and row.name or "" )
			self:diffuse( (row and row.isSelf) and self_color or HUD_TEXT )
		end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="",
		InitCommand=function(self)
			self:xy(SCORE_X, y):horizalign(right):zoom(ROW_ZOOM)
		end,
		RedrawCommand=function(self)
			local row = rows[i]
			self:settext( row and row.pct or "" )
			if row and row.failed then
				self:diffuse(Color.Red)
			elseif row and row.isSelf then
				self:diffuse(self_color)
			else
				self:diffuse(HUD_TEXT)
			end
		end
	}
end

return af
