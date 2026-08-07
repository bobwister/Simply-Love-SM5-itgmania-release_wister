-- Horizontal layout of one song row in the music wheel, shared by the row's data columns
-- (Graphics/MusicWheelItem Song NormalPart/default.lua) and the song title, whose maxwidth
-- has to stop just short of them. Kept in one place because the two were literals in two
-- files and had drifted apart at both aspect ratios.
--
-- Row, left to right:  lamp | P1 grade | P2 grade | title ..... | PTS | EX  |
--                                                               | ITL | ITG |

-- TWEAK: sizes the text AND the column offsets together, the only safe way to resize the
-- group. The title's maxwidth follows on its own.
local COLUMN_SCALE = 1.4

-- Clearance between the end of the title and the first column past it.
local TITLE_GAP = 10

-- Computed on first use: this file loads before SL-Helpers.lua and must not depend on
-- load order.
local geometry = nil

WheelRowColumns = function()
	if geometry then return geometry end

	-- the row plate spans 0 .. item_width from the NormalPart frame's origin
	local item_width = _screen.w / 2.125
	local anchor = item_width - 14

	geometry = {
		scale  = COLUMN_SCALE,
		zoom   = 0.40 * COLUMN_SCALE,
		anchor = anchor,

		col_score = anchor - 24 * COLUMN_SCALE,  -- EX over ITG, left-aligned
		col_event = anchor - 38 * COLUMN_SCALE,  -- PTS over ITL (or SRPG rate), right-aligned

		-- where the title has to stop. 40 * scale is the widest either event line gets
		-- ("10000 PTS", "10000th ITL"); with no event column it runs on to col_event.
		block_left          = anchor - 78 * COLUMN_SCALE,
		block_left_no_event = anchor - 38 * COLUMN_SCALE,

		-- the NormalPart frame's own offset inside the wheel item; the columns above are
		-- in that frame's space, the title is in the item's
		frame_x = WideScale(28, 33),

		label_color = color("#5A6166"),  -- the "PTS"/"ITL"/"EX" micro-labels
	}
	return geometry
end

-- -----------------------------------------------------------------------
-- Does this row carry an event column at all? ITL points/rank and the SRPG rate share one
-- column, and none can appear unless a single player with a profile is on an event pack.
--
-- The same predicate the column actors gate themselves on, so the title and the columns
-- can never disagree about who owns that space. Errs toward "yes": an unknown row keeps
-- the narrow title, which costs width but can never overlap.
WheelRowHasEventColumn = function(song)
	if not song then return true end

	local humans = GAMESTATE:GetHumanPlayers()
	if #humans ~= 1 then return false end
	if not PROFILEMAN:IsPersistentProfile(humans[1]) then return false end

	local group = song:GetGroupName()
	if SRPGEventFromGroupName(group) then return true end
	if ITLSeasonFromGroupName(group) then return true end

	-- an ITL chart in a pack that isn't NAMED like one
	local itl = SL[ ToEnumShortString(humans[1]) ].ITLData
	local song_dir = song:GetSongDir()
	if itl and itl["pathMap"] and song_dir and itl["pathMap"][song_dir] then return true end

	return false
end

-- -----------------------------------------------------------------------
-- Where the title starts: after the two grade columns ([MusicWheelItem] GradeP1X/GradeP2X
-- in metrics.ini). With no player 2 there is no second grade, so the title takes that lane
-- too. Keyed on player 2 rather than on "is this solo" because a solo game on the P2 side
-- still fills the second slot -- only the first goes empty, which buys the title nothing.
local function TitleX()
	local x = WideScale(75, 111)
	if not GAMESTATE:IsPlayerEnabled(PLAYER_2) then
		x = x - (WideScale(54, 80) - WideScale(38, 50))
	end
	return x
end

local function Fit(actor, song)
	-- Set can land before the actor's On command has run; zoom is still 1 then, and On
	-- re-fits with the real one a moment later.
	local zoom = actor.wheel_row_zoom or 1

	local g = WheelRowColumns()
	local x = TitleX()
	local block_left = WheelRowHasEventColumn(song) and g.block_left or g.block_left_no_event

	-- maxwidth caps the UNZOOMED width, hence the division
	actor:halign(0):zoom(zoom):x(x)
	actor:maxwidth( ((g.frame_x + block_left) - TITLE_GAP - x) / zoom )
end

-- [TextBanner] Title/SubtitleOnCommand. No song in hand, so the conservative width; the
-- per-row call below refines it.
WheelRowFitText = function(actor, zoom)
	actor.wheel_row_zoom = zoom
	Fit(actor, nil)
end

-- [MusicWheelItem] SongNameSetCommand, once per row. `banner` is the TextBanner frame.
WheelRowFitTitle = function(banner, song)
	if not (banner and banner.GetChild) then return end

	local title = banner:GetChild("Title")
	if title then Fit(title, song) end

	local subtitle = banner:GetChild("Subtitle")
	if subtitle then Fit(subtitle, song) end
end
