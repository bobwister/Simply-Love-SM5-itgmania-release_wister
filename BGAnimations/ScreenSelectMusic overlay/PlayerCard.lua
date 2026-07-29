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
local ITL_LABEL_ZOOM = 0.34
local ITL_VALUE_ZOOM = 0.46

-- The event block holds up to MAX_EVENT_ROWS rows, and however many the active event
-- actually has are centred in it -- ITL has three, Stamina RPG two. Positions are worked
-- out per refresh rather than fixed at init, so switching events re-centres the block
-- instead of leaving a hole where the third row used to be.
local MAX_EVENT_ROWS = 3
local ROW_BLOCK_CY   = 21
local ROW_SPACING    = 13

local function RowY(i, count)
	return ROW_BLOCK_CY + (i - (count + 1)/2) * ROW_SPACING
end

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
local ITL_ROWS = {
	{ key="ItlRankingPoints", fmt=function(s) return Commas(s.rp)     end },
	{ key="ItlTotalPoints",   fmt=function(s) return Commas(s.tp)     end },
	{ key="ItlChartsPassed",  fmt=function(s) return Commas(s.passed) end },
}

-- The equivalent rows during a Stamina RPG season. Two, not three: SRPG has no points to
-- show. Its API node carries a per-chart leaderboard, a result string, and quest/stat
-- progress that arrives once in the submit response and is never persisted -- there is no
-- equivalent of itl2024.json.
--
-- All three are records of things that happened, not statistics derived from them: the
-- best rate you cleared at, the hardest chart and fastest song you got through, and how
-- many songs are in the record. An average rate briefly sat here and has been taken out --
-- nothing in SRPG defines such a figure, so it was a number of my own invention sitting
-- among official ones.
--
-- The middle row prints two figures, which is why fmt takes the whole stats table.
--
-- Only these rows swap. The star tally and the cleared count below the rule are read off
-- the profile's own scores and mean the same thing whichever event is running.
local SRPG_ROWS = {
	{ key="SrpgBestRate", fmt=function(s) return ("%.2fx"):format(s.best) end },
	-- Two labelled figures on one line. `composite` tells the generic row loop to leave
	-- this slot alone -- it is drawn by the chained frame further down instead, which the
	-- usual label-left/value-right pair cannot express.
	{ composite=true },
	{ key="SrpgSongsCleared", fmt=function(s) return Commas(s.cleared) end },
}

-- Which set of rows the card is showing, and the SRPG season if that is the one.
-- Re-asked on every Refresh rather than settled at load, so swapping to a profile with a
-- different history moves the card with it.
--
-- Declared BEFORE CompositeRow, and that order matters: a `local function` is only in
-- scope from its own declaration onward, so a caller written above it would bind the
-- name to a nil global instead. The row actors further down escape this because their
-- commands are closures created after both declarations.
local function ActiveRows()
	if SRPGIsActiveEvent() then
		local event = SRPGCurrentEvent()
		if event then return SRPG_ROWS, event end
	end
	return ITL_ROWS, nil
end

-- Where the composite row sits in the active set, if it is showing at all.
-- Returns index, row count, event -- or nil.
local function CompositeRow()
	local rows, event = ActiveRows()
	for i, row in ipairs(rows) do
		if row.composite then return i, #rows, event end
	end
	return nil
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

-- The event block: one labelled figure per row, label left, figure right. How many rows
-- there are, and what they say, depends on the season -- see ActiveRows. Rows past the
-- active event's count hide themselves.
for i = 1, MAX_EVENT_ROWS do
	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="EventLabel"..i,
		InitCommand=function(self)
			self:horizalign(left):x(ITL_LABEL_X):zoom(ITL_LABEL_ZOOM)
			self:maxwidth((W - 2*PAD - 34) / ITL_LABEL_ZOOM):diffuse(HUD_LABEL)
		end,
		RefreshCommand=function(self)
			local rows = ActiveRows()
			if i > #rows or rows[i].composite then self:visible(false) return end

			self:visible(true):y( RowY(i, #rows) )
			self:settext( THEME:GetString("ScreenSelectMusic", rows[i].key) )
		end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="EventValue"..i,
		InitCommand=function(self)
			self:horizalign(right):x(ITL_VALUE_X):zoom(ITL_VALUE_ZOOM)
			self:diffuse(HUD_TEXT)
		end,
		-- "--" rather than 0 in both branches: no event file loaded is not the same as a
		-- record of nothing.
		RefreshCommand=function(self)
			local rows, event = ActiveRows()
			if i > #rows or rows[i].composite then self:visible(false) return end

			self:visible(true):y( RowY(i, #rows) )

			if event then
				local best, cleared = SRPGProfileStats(player, event)
				if not best then self:settext("--") return end

				-- only asked for once there is something to report; it walks the season's
				-- packs, so there is no point paying for it on an empty record
				local meter, bpm = SRPGPassedPeaks(player, event)
				self:settext( rows[i].fmt{ best=best, cleared=cleared, meter=meter, bpm=bpm } )
			else
				local rp, tp, passed = GetItlStats()
				self:settext( rp and rows[i].fmt{ rp=rp, tp=tp, passed=passed } or "--" )
			end
		end
	}
end

-- The composite row: "<label> : <value> | <label> : <value>", laid out as a chain rather
-- than as one string with AddAttribute. Character offsets into a settext'd string index
-- characters, not bytes, so an accented label would shift them -- the chain keeps the
-- dim-label/bright-value contrast without that trap.
--
-- TWEAK: everything on this row shares PEAKS_ZOOM. It has to: the English line measures
-- 110px of the card's 118 at 0.34, so the figures cannot be set at the 0.46 the other
-- rows use for their values. Raising it means shortening the labels.
local PEAKS_ZOOM = 0.34
local PEAKS_PARTS = { "Label1", "Value1", "Sep", "Label2", "Value2" }

local peaks = Def.ActorFrame{
	Name="EventPeaks",
	InitCommand=function(self) self:visible(false) end,

	RefreshCommand=function(self)
		local index, count, event = CompositeRow()
		if not index or not event then self:visible(false) return end

		-- Shown with "--" when there is nothing to report, exactly like the rows either
		-- side of it. Hiding it instead left a gap in the middle of a three-row block.
		--
		-- And it is deliberately NOT gated on there being a .rpg record: these two come
		-- from the profile's own scores, so a season played before the theme kept rates
		-- -- or on a machine that never wrote the file -- still has a level and a bpm to
		-- show. Gating them on the rate file hid figures that existed.
		local meter, bpm = SRPGPassedPeaks(player, event)

		-- The separators live here rather than in the language files, which trim
		-- surrounding whitespace out of their values.
		self:GetChild("Label1"):settext( THEME:GetString("ScreenSelectMusic", "SrpgHighestLevel") .. " : " )
		self:GetChild("Value1"):settext( meter and tostring(meter) or "--" )
		self:GetChild("Sep"):settext("  |  ")
		self:GetChild("Label2"):settext( THEME:GetString("ScreenSelectMusic", "SrpgHighestBpm") .. " : " )
		self:GetChild("Value2"):settext( bpm and ("%.0f BPM"):format(bpm) or "-- BPM" )

		-- Chain them left to right off their own drawn widths, so the line closes up
		-- around a one-digit level or a four-digit bpm instead of sitting on fixed anchors.
		local x = -W/2 + PAD
		for _, name in ipairs(PEAKS_PARTS) do
			local part = self:GetChild(name)
			part:x(x)
			x = x + part:GetZoomedWidth()
		end

		self:visible(true):y( RowY(index, count) )
	end,
}

for _, name in ipairs(PEAKS_PARTS) do
	local bright = (name:match("^Value") ~= nil)

	peaks[#peaks+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name=name,
		Text="",
		InitCommand=function(self)
			self:horizalign(left):zoom(PEAKS_ZOOM)
			self:diffuse( bright and HUD_TEXT or HUD_LABEL )
		end
	}
end

af[#af+1] = peaks

af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:zoomto(W - PAD*2, 1):y(RULE_Y)
		self:playcommand("Paint")
	end,
	PaintCommand=function(self) self:diffuse( DimColor(Accent(), 1.0, 0.20) ) end,
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
