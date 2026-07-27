-- Player card: the player's ITL standing and their star-lamp tally.
--
-- It is the left half of the left column's bottom card, sharing that band with the
-- leaderboard (SSM.playercard in Scripts/SL-Layout-SelectMusic.lua).
--
-- The avatar and the profile name used to head this card. They are gone: the engine's
-- CreditDisplay already prints both at the bottom left of the footer, a few pixels below,
-- and they were costing 46 of the card's 80px to say it a second time. The ITL figures
-- took that space, as a labelled column rather than the single ranking-points line the
-- card had room for before.
--
-- Solo only: this theme is single player, event mode, so there is one card and it belongs
-- to the master player.

local player = GAMESTATE:GetMasterPlayerNumber() or PLAYER_1
local pn = ToEnumShortString(player)

local W = SSM.playercard.w
local H = SSM.playercard.h

-- TWEAK: the card's two blocks -- ITL figures above the rule, the star tally below.
-- Everything vertical is measured DOWN from the card's top edge, which is this frame's
-- origin. Labels sit on the left edge, figures right-aligned on the right one.
local PAD = 4

local ITL_LABEL_X = -W/2 + PAD
local ITL_VALUE_X =  W/2 - PAD
local ITL_ROW_Y   = { 8, 21, 34 }
local ITL_LABEL_ZOOM = 0.34
local ITL_VALUE_ZOOM = 0.46

local RULE_Y = 44

-- Star tally: five tiers, best first, in a 3+2 grid.
--
-- The icons are the wheel's own -- the star tiers off the grade sheet, and quint.png for
-- the fifth -- rather than N copies of a star glyph, so a row here and a row in the wheel
-- say the same thing with the same picture. Grade tiers 01..04 ARE the four star grades
-- in Simply Love (see the GradePercentTier comments in Metrics.ini), so their sprite
-- states are 0..3, best first.
-- TWEAK: ICON_SIZE has to leave the count room on the right of its cell -- a four-digit
-- count is the widest a cell ever gets.
local CELL_W     = (W - 2*PAD) / 3
local STAR_ROW_Y = { 54, 68 }
local ICON_SIZE  = 14
local ICON_X     = 2 + ICON_SIZE/2      -- from the cell's left edge
local COUNT_ZOOM = 0.42

local GRADE_SHEET = THEME:GetPathG("MusicWheelItem", "Grades/grades 1x18.png")
local QUINT_ICON  = THEME:GetPathG("MusicWheelItem", "Grades/quint.png")

-- The walk over the profile is O(songs on the machine), so it is kicked off a beat after
-- the screen has settled rather than during load -- see StarCountsCompute.
local SCAN_DELAY = 0.6

local accent = PlayerColor(player)

-- 12480 -> "12,480". There is no commify() in this theme or the fallback.
local function Commas(n)
	local out = tostring(n)
	while true do
		local replaced
		out, replaced = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return out
end

-- The player's ITL standing: ranking points (best 75 charts), total points (all charts)
-- and how many charts they have passed this season.
--
-- The third figure is charts PASSED, not charts played: UpdateItlData only writes a
-- chart into the hashMap on a run that didn't fail (see the not stats:GetFailed()
-- condition in Scripts/SL_ITL.lua), so a failed attempt leaves no entry behind and is
-- never counted.
--
-- It also does NOT come from CalculateITLStats, whose third return value is the length
-- of itlData["points"] -- a list built from the whole hashMap, so it pools 2024, 2025
-- and 2026 into one number. ITL is a fresh competition each season, so "charts passed"
-- is only a meaningful figure scoped to one; CountITLChartsPassedInSeason filters on the
-- season each entry already records.
--
-- TP and RP are deliberately left pooled: they are what CalculateITLStats has always
-- reported, and narrowing them would silently change two figures nobody asked about.
local function GetItlStats()
	local data = SL[pn].ITLData
	if not data or not data["points"] or #data["points"] == 0 then return nil end
	local tp, rp = CalculateITLStats(player)
	return rp, tp, CountITLChartsPassedInSeason(player, ITLCurrentSeason())
end

-- label key -> which of the three figures it prints
local ITL_ROWS = {
	{ key="ItlRankingPoints", pick=function(rp, tp, passed) return rp     end },
	{ key="ItlTotalPoints",   pick=function(rp, tp, passed) return tp     end },
	{ key="ItlChartsPassed",  pick=function(rp, tp, passed) return passed end },
}

local af = Def.ActorFrame{
	Name="PlayerCard",
	InitCommand=function(self)
		self:xy(SSM.playercard.cx, SSM.cards.bottom.top)
		self:visible( GAMESTATE:IsHumanPlayer(player) )
	end,
	OnCommand=function(self)
		self:playcommand("Refresh")
		-- deferred so the profile walk cannot show up as a hitch on screen entry
		self:sleep(SCAN_DELAY):queuecommand("Scan")
	end,
	ScanCommand=function(self)
		StarCountsCompute(player)
		self:playcommand("Refresh")
	end,
	PlayerProfileSetMessageCommand=function(self, params)
		if params.Player == player then
			-- a different profile means a different tally and different ITL figures
			StarCountsInvalidate(player)
			self:playcommand("Refresh")
			self:stoptweening():sleep(SCAN_DELAY):queuecommand("Scan")
		end
	end,
	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == player then self:visible(true):playcommand("Refresh") end
	end,

	Def.Quad{
		Name="Card",
		InitCommand=function(self)
			HUDPanel(self):zoomto(W, H):vertalign(top)
		end
	},
}

af[#af+1] = HUDCardDecor(W, H, 0, H/2)

-- The ITL block: one labelled figure per row, label left, figure right.
for i, row in ipairs(ITL_ROWS) do
	local y = ITL_ROW_Y[i]

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=THEME:GetString("ScreenSelectMusic", row.key),
		InitCommand=function(self)
			self:horizalign(left):xy(ITL_LABEL_X, y):zoom(ITL_LABEL_ZOOM)
			self:maxwidth((W - 2*PAD - 34) / ITL_LABEL_ZOOM):diffuse(HUD_LABEL)
		end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Itl"..i,
		InitCommand=function(self)
			self:horizalign(right):xy(ITL_VALUE_X, y):zoom(ITL_VALUE_ZOOM)
			self:diffuse(HUD_TEXT)
		end,
		RefreshCommand=function(self)
			local rp, tp, passed = GetItlStats()
			-- "--" rather than 0: no ITL file loaded is not the same as a score of nothing
			self:settext( rp and Commas(row.pick(rp, tp, passed)) or "--" )
		end
	}
end

af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:zoomto(W - PAD*2, 1):y(RULE_Y)
		self:diffuse( DimColor(accent, 1.0, 0.20) )
	end
}

-- Left edge and centre line of grid slot `slot` (1..6), in reading order.
local function SlotXY(slot)
	return -W/2 + PAD + ((slot - 1) % 3) * CELL_W,
	       STAR_ROW_Y[ math.floor((slot - 1) / 3) + 1 ]
end

-- The count in a slot, right-aligned against its right edge.
local function SlotCount(name, slot, get)
	local cell_x, y = SlotXY(slot)
	return LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name=name,
		Text="",
		InitCommand=function(self)
			self:horizalign(right):xy(cell_x + CELL_W - 3, y):zoom(COUNT_ZOOM)
			self:diffuse(HUD_TEXT)
		end,
		RefreshCommand=function(self)
			local counts = StarCountsGet(player)
			-- blank until the deferred walk has run, so the card never shows a wrong zero
			self:settext( counts and get(counts) or "" )
		end
	}
end

-- The tally itself: one icon per tier, then how many charts are at that tier. The icon
-- carries the meaning, so there is no legend to fit anywhere.
for tier = 5, 1, -1 do
	local slot = 6 - tier                      -- 1..5, reading order
	local cell_x, y = SlotXY(slot)

	if tier == 5 then
		af[#af+1] = Def.Sprite{
			Texture=QUINT_ICON,
			InitCommand=function(self)
				self:zoomto(ICON_SIZE, ICON_SIZE):xy(cell_x + ICON_X, y)
			end
		}
	else
		af[#af+1] = Def.Sprite{
			Texture=GRADE_SHEET,
			InitCommand=function(self)
				-- state 0 is Grade_Tier01 (four stars), so a 4-star tier is state 0
				self:animate(false):setstate(4 - tier)
				self:zoomto(ICON_SIZE, ICON_SIZE):xy(cell_x + ICON_X, y)
			end
		}
	end

	af[#af+1] = SlotCount("StarCount"..tier, slot, function(counts) return counts[tier] end)
end

-- Sixth slot: charts cleared at all, star or no star.
--
-- A tick rather than the word CLEARED: the cell is 39px wide and the five beside it are
-- icons, so a label would have to be too small to read AND out of step with its row.
--
-- It is the same tick the title screen puts beside "GrooveStats" once the connection is
-- up (BGAnimations/ScreenSystemLayer overlay.lua) -- U+2714, which lives in the theme's
-- emoji page, Fonts/16px fonts/_emoji 16px. Every font here inherits it: Fonts/Common
-- default.ini imports "16px fonts/_16px fonts", which imports the emoji page in turn, and
-- the engine loads Common default as a fallback for every top-level font.
--
-- That page's cells are 24 units square, so CHECK_ZOOM is the tick's height in pixels
-- over 24. TWEAK: half an icon box, which is what the tick wants -- it reads heavier than
-- the star glyphs at the same size.
local CHECK_ZOOM = (ICON_SIZE * 0.5) / 24

do
	local cell_x, y = SlotXY(6)

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text="✔",
		InitCommand=function(self)
			self:xy(cell_x + ICON_X, y):zoom(CHECK_ZOOM)
			-- keeps the glyph its own colour instead of taking a diffuse, the way every
			-- other emoji in this theme is drawn
			DiffuseEmojis(self)
		end
	}

	af[#af+1] = SlotCount("ClearedCount", 6, function(counts) return counts.cleared end)
end

return af
