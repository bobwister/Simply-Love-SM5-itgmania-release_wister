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
-- One size for every label and figure: the heading names the event, so no label repeats it
-- and none is width-bound. Height binds instead. Not SL_LowRes'd -- the card does not grow.
local ROW_ZOOM   = 0.56
local TITLE_ZOOM = 0.38
local TITLE_Y    = 4

local RULE_Y = 44

-- A line can carry two figures, so lines ~= figures: SRPG uses two, ITL three. Lines are
-- spread through the band between heading and rule rather than pitched fixed, so a two-line
-- layout gets the room a three-line one cannot. LINE_MAX_PITCH caps how far they spread.
local MAX_EVENT_ROWS  = 3
local LINE_MAX_PITCH  = 14
local LINE_BAND_TOP   = TITLE_Y  + 7*TITLE_ZOOM + 2 + 8*ROW_ZOOM   -- first line's centre
local LINE_BAND_BOT   = RULE_Y   - 8*TITLE_ZOOM - 2 - 7*ROW_ZOOM   -- last line's centre

local function LineY(line, count)
	if count < 2 then return (LINE_BAND_TOP + LINE_BAND_BOT) / 2 end

	local pitch = math.min(LINE_MAX_PITCH, (LINE_BAND_BOT - LINE_BAND_TOP) / (count - 1))
	return (LINE_BAND_TOP + LINE_BAND_BOT)/2 + (line - (count + 1)/2) * pitch
end

-- Just right of centre: the left half carries the two longest labels, the right a short one.
local SPLIT_X   = 2
local SPLIT_GAP = 6

local SLOT_X = {
	full  = { label = ITL_LABEL_X,              value = ITL_VALUE_X },
	left  = { label = ITL_LABEL_X,              value = SPLIT_X - SPLIT_GAP/2 },
	right = { label = SPLIT_X + SPLIT_GAP/2,    value = ITL_VALUE_X },
}

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
local STAR_ROW_Y = { 56, 70 }
local ICON_SIZE  = 14
local ICON_X     = 2 + ICON_SIZE/2      -- from the cell's left edge
-- 0.58 is where a four-digit count stops fitting beside the icon.
local COUNT_ZOOM = SL_LowRes(0.50, 0.58)

local GRADE_SHEET = THEME:GetPathG("MusicWheelItem", "Grades/grades 1x18.png")
local QUINT_ICON  = THEME:GetPathG("MusicWheelItem", "Grades/quint.png")

-- The walk over the profile is O(songs on the machine), so it is kicked off a beat after
-- the screen has settled rather than during load -- see StarCountsCompute.
local SCAN_DELAY = 0.6

-- Read at paint time, not captured: a profile switch from the wheel changes the Simply
-- Love color without a screen reload, and the actors below repaint on ColorSelected.
local function Accent() return PlayerColor(player) end

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

-- label key -> which of the figures it prints. `fmt` is handed one table of everything
-- the active event knows, so a row can print more than one figure without the caller
-- having to know which rows do.
-- `line` is the block line, `slot` how it shares that line, `fig` the room its value needs
-- (the label's maxwidth is the rest of the slot). `fig` is per-figure, not per-slot: "11" and
-- "1.30x" share the left half, and one reserve for both would squeeze the level's label.
local ITL_ROWS = {
	{ key="ItlRankingPoints", line=1, slot="full", fig=34, fmt=function(s) return Commas(s.rp)     end },
	{ key="ItlTotalPoints",   line=2, slot="full", fig=34, fmt=function(s) return Commas(s.tp)     end },
	{ key="ItlChartsPassed",  line=3, slot="full", fig=34, fmt=function(s) return Commas(s.passed) end },
}

-- Stamina RPG: three personal records. No average rate -- SRPG defines no such figure -- and
-- no songs-cleared, which duplicated the ✔ tally below the rule. The rate takes the LEFT
-- slot so its figure lands under the level's, which makes the two lines read as one table.
local SRPG_ROWS = {
	{ key="SrpgMaxLevel", line=1, slot="left",  fig=11, fmt=function(s) return s.meter and tostring(s.meter) or "--" end },
	{ key="SrpgMaxBpm",   line=1, slot="right", fig=18, fmt=function(s) return s.bpm and ("%.0f"):format(s.bpm) or "--" end },
	{ key="SrpgMaxRate",  line=2, slot="left",  fig=21, fmt=function(s) return s.best and ("%.2fx"):format(s.best) or "--" end },
}

-- Rows, the SRPG event if active, the heading key, and the season it quotes. Re-asked every
-- Refresh so a profile switch moves the card. The season is named because both helpers return
-- only the NEWEST installed one, so the figures are scoped to it.
local function ActiveRows()
	if SRPGIsActiveEvent() then
		local event = SRPGCurrentEvent()
		if event then return SRPG_ROWS, event, "SrpgCardTitle", event end
	end
	return ITL_ROWS, nil, "ItlCardTitle", ITLCurrentSeason()
end

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

-- Names the event once, so no label below repeats it. Accent-coloured like the rule, so the
-- two read as the frame around the figures rather than as data.
af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	Name="EventTitle",
	InitCommand=function(self)
		self:horizalign(left):xy(ITL_LABEL_X, TITLE_Y):zoom(TITLE_ZOOM)
		self:maxwidth((W - 2*PAD) / TITLE_ZOOM)
		self:playcommand("Paint")
	end,
	PaintCommand=function(self) self:diffuse( DimColor(Accent(), 1.0, 0.90) ) end,
	ColorSelectedMessageCommand=function(self) self:playcommand("Paint") end,
	-- {n} is the season, placed by the language file's own word order. gsub, not format: with
	-- no event pack installed the slot collapses -- along with its space -- instead of "nil".
	RefreshCommand=function(self)
		local _, _, title, season = ActiveRows()

		local text = THEME:GetString("ScreenSelectMusic", title)
		if season then
			text = text:gsub("{n}", tostring(season))
		else
			text = text:gsub("%s*{n}", "")
		end

		self:settext(text)
	end
}

-- Read off the rows, so a row list stays the single description of its own layout.
local function LineCount(rows)
	local n = 0
	for _, row in ipairs(rows) do n = math.max(n, row.line) end
	return n
end

-- x and maxwidth are settled per refresh, not at init: the same actor is a full-width slot
-- under ITL and a half-width one under SRPG.
for i = 1, MAX_EVENT_ROWS do
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="EventLabel"..i,
		InitCommand=function(self)
			self:horizalign(left):zoom(ROW_ZOOM):diffuse(HUD_LABEL)
		end,
		RefreshCommand=function(self)
			local rows = ActiveRows()
			if i > #rows then self:visible(false) return end

			local row  = rows[i]
			local slot = SLOT_X[row.slot]

			self:visible(true):xy( slot.label, LineY(row.line, LineCount(rows)) )
			self:maxwidth( (slot.value - slot.label - row.fig) / ROW_ZOOM )
			self:settext( THEME:GetString("ScreenSelectMusic", row.key) )
		end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="EventValue"..i,
		InitCommand=function(self)
			self:horizalign(right):zoom(ROW_ZOOM):diffuse(HUD_TEXT)
		end,
		-- "--" rather than 0, decided per figure: the level and bpm come off the profile's
		-- scores, so gating them on the .rpg rate would hide figures that exist without it.
		RefreshCommand=function(self)
			local rows, event = ActiveRows()
			if i > #rows then self:visible(false) return end

			local row = rows[i]
			self:visible(true):xy( SLOT_X[row.slot].value, LineY(row.line, LineCount(rows)) )

			if event then
				local best   = SRPGProfileStats(player, event)
				local meter, bpm = SRPGPassedPeaks(player, event)
				self:settext( row.fmt{ best=best, meter=meter, bpm=bpm } )
			else
				local rp, tp, passed = GetItlStats()
				self:settext( rp and row.fmt{ rp=rp, tp=tp, passed=passed } or "--" )
			end
		end
	}
end

-- The rule between the two blocks, captioned at its left end.
--
-- The caption is load-bearing: everything BELOW the rule is profile-wide, not event-scoped
-- (StarCountsCompute walks SONGMAN:GetAllSongs()), so under an "SRPG"-headed block those
-- figures would read as SRPG ones. Styled like the event heading because it is the same kind
-- of thing. It rides the rule because there is no line to take -- the star rows already touch.
--
-- CAPTION_W is its reserve, the rule takes the rest.
local CAPTION_ZOOM = TITLE_ZOOM
local CAPTION_W    = 50
local CAPTION_GAP  = 4

af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:horizalign(left)
		self:zoomto(W - PAD*2 - CAPTION_W - CAPTION_GAP, 1)
		self:xy(ITL_LABEL_X + CAPTION_W + CAPTION_GAP, RULE_Y)
		self:playcommand("Paint")
	end,
	PaintCommand=function(self) self:diffuse( DimColor(Accent(), 1.0, 0.20) ) end,
	ColorSelectedMessageCommand=function(self) self:playcommand("Paint") end,
}

af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
	Name="ScopeCaption",
	Text=THEME:GetString("ScreenSelectMusic", "PlayerCardAllSongs"),
	InitCommand=function(self)
		self:horizalign(left):zoom(CAPTION_ZOOM)
		self:xy(ITL_LABEL_X, RULE_Y)
		self:maxwidth(CAPTION_W / CAPTION_ZOOM)
		self:playcommand("Paint")
	end,
	PaintCommand=function(self) self:diffuse( DimColor(Accent(), 1.0, 0.90) ) end,
	ColorSelectedMessageCommand=function(self) self:playcommand("Paint") end,
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
