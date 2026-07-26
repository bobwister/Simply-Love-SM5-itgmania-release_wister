-- Pack Rail: which pack you are in, what sits either side of it, and Ctrl+Left /
-- Ctrl+Right to jump between them.
--
-- Lives in the header's centre band, which is free since the session clocks
-- moved down to the footer (see Footer.lua and Graphics/ScreenSelectMusic
-- header.lua).
--
-- Navigation note: "jump to pack" is done by selecting that pack's first song,
-- which expands the right section whatever the active sort order. MusicWheel's
-- own bindings are ChangeSort, GetSelectedSection, IsRouletting, IsLocked,
-- SelectSong, SelectCourse, Move and GetCurrentSections; SetOpenSection,
-- GetCurrentIndex and GetNumItems come from WheelBase, which MusicWheel derives
-- from. SetOpenSection is deliberately not used here -- it takes a section name
-- only, so it would drop the parent section on nested groups, whereas SelectSong
-- routes through SetOpenSections() and keeps the parent intact.

-- Every pack on the machine, in SONGMAN's own order.
--
-- No early return if this comes back empty: this frame also draws the header
-- band now, so bailing out would leave the header with no background at all.
-- IndexOfPack, JumpToPack and RefreshCommand all tolerate an empty list, and the
-- rail simply renders blank.
local packs = SONGMAN:GetSongGroupNames() or {}

local accent = PlayerColor(PLAYER_1)
-- TWEAK: rail text brightness. These sat well against the old see-through header
-- but read as muddy on the opaque band, so they are pitched brighter here: the
-- flanking pack names stay clearly subordinate to the accent-coloured current
-- pack without disappearing into the background.
local dim = color("#C2D2DA")    -- chevrons
local faint = color("#96AAB4")  -- previous / next pack names
local quiet = color("#6E838D")  -- the n/total counter, the least important thing here

-- TWEAK: rail geometry. Positions are relative to the rail's own frame, which
-- is centred in the header band.
local RAIL_Y        = 16
local CURRENT_ZOOM  = 0.62
local NEIGHBOUR_X   = 104   -- where the flanking pack names sit
local NEIGHBOUR_ZOOM= 0.45
local CHEVRON_X     = 92
local COUNTER_X     = 232

-- Shortcut legend under each chevron. It sits a row below everything else, which is
-- what lets it be this wide without colliding with the pack names either side of it.
--
-- Screen.String resolves against the screen currently being loaded, so it is only
-- valid here at file scope / in InitCommand -- not from a later command. Same idiom
-- as the STEPS label in PerPlayer/StepArtist.lua. Strings live under
-- [ScreenSelectMusic] in Languages/en.ini and fr.ini; the other seven language
-- files fall back to English.
local LEGEND_Y      = 9
local LEGEND_ZOOM   = 0.26
local LEGEND_PREV   = Screen.String("PackRailPrev")
local LEGEND_NEXT   = Screen.String("PackRailNext")

-- Which pack the wheel is sitting in. Prefer the current song's group, which is
-- correct whatever the sort order; fall back to the wheel's own section name for
-- rows that aren't songs (a group header, for instance).
local function CurrentPackName()
	local song = GAMESTATE:GetCurrentSong()
	if song then return song:GetGroupName() end

	local screen = SCREENMAN:GetTopScreen()
	if screen then
		local wheel = screen:GetMusicWheel()
		if wheel then return wheel:GetSelectedSection() end
	end
	return nil
end

local function IndexOfPack(name)
	if not name then return nil end
	for i, pack in ipairs(packs) do
		if pack == name then return i end
	end
	return nil
end

-- Mirror of SongUtil::MakeSortString (SongUtil.cpp:450). Uppercase, drop a single
-- leading '.' (for songs like ".59"), then shove anything that still doesn't begin
-- with A-Z or 0-9 to the very end of the alphabet by prefixing chr(126), '~' --
-- which sits above every alphanumeric in ASCII. That last step is precisely why the
-- wheel lists a title like "(Reprise)" LAST in its pack, not first.
local function MakeSortString(s)
	s = (s or ""):upper()
	if #s > 0 then
		if s:sub(1,1) == "." then s = s:sub(2) end
		-- an empty string here matches nothing and gets the '~' too, which is what
		-- the C++ does as well: indexing an emptied std::string yields '\0' < 'A'
		if not s:sub(1,1):match("^[A-Z0-9]$") then s = string.char(126) .. s end
	end
	return s
end

-- Mirror of SongUtil::CompareSongPointersByTitle (SongUtil.cpp:466). Note the
-- equality test is on the RAW main titles, before MakeSortString is applied -- and
-- the final tiebreak is the song's file path, compared case-insensitively.
--
-- Lua's `<` on strings goes through strcoll rather than strcmp, but MakeSortString
-- has already uppercased everything, so the two agree over the ASCII range.
local function ComesFirstInWheel(a, b)
	local s1, s2 = a:GetTranslitMainTitle(), b:GetTranslitMainTitle()
	if s1 == s2 then
		s1, s2 = a:GetTranslitSubTitle(), b:GetTranslitSubTitle()
	end

	s1, s2 = MakeSortString(s1), MakeSortString(s2)
	if s1 ~= s2 then return s1 < s2 end

	return a:GetSongFilePath():lower() < b:GetSongFilePath():lower()
end

-- The song the wheel actually shows at the top of `group`.
--
-- SONGMAN:GetSongsInGroup hands back SongManager's own ordering for the group,
-- which is NOT the wheel's: the wheel sorts each group's contents with
-- CompareSongPointersByTitle (via CompareSongPointersByGroupAndTitle, which falls
-- through to it once both songs are in the same group). So pick the minimum under
-- the engine's own comparator rather than trusting index 1.
--
-- This is title order, which is what every group-based sort shows. Under a sort
-- whose sections aren't packs at all (BPM, artist, genre, meter) the wheel orders
-- rows by that key instead, so we may not land on the section's literal first row
-- -- but we still land inside the target pack, which is what the jump is for.
local function FirstSongInWheelOrder(group)
	local songs = SONGMAN:GetSongsInGroup(group)
	if not songs or #songs == 0 then return nil end

	local first = songs[1]
	for i = 2, #songs do
		if ComesFirstInWheel(songs[i], first) then first = songs[i] end
	end
	return first
end

-- Move `offset` packs from wherever we are and select that pack's first song.
local function JumpToPack(offset)
	local screen = SCREENMAN:GetTopScreen()
	if not screen then return end

	local wheel = screen:GetMusicWheel()
	if not wheel then return end
	-- Don't fight the wheel mid-roulette or while it's locked (course/event rules)
	if wheel:IsRouletting() or wheel:IsLocked() then return end

	local index = IndexOfPack(CurrentPackName())
	if not index then return end

	-- wrap, so the rail is a loop rather than a dead end at either extreme
	local target = ((index - 1 + offset) % #packs) + 1

	local first_song = FirstSongInWheelOrder(packs[target])
	if not first_song then return end

	-- Clear the wheel's remembered open section.
	--
	-- Under SORT_PREFERRED or SORT_METER, MusicWheel::SelectSong ignores the song
	-- it is handed and re-opens GAMESTATE->sLastOpenSection instead. That field
	-- has no Lua binding, but ChangeSort() clears it as its very first statement,
	-- before any early return, so re-applying the active sort resets it.
	--
	-- Skip it on SORT_PREFERRED though: that one sort is deliberately exempt from
	-- the "same sort changes nothing" early return (MusicWheel.cpp:1585), so the
	-- call would kick off a real re-sort and fly the wheel off screen.
	local sort = GAMESTATE:GetSortOrder()
	if sort ~= "SortOrder_Preferred" then
		wheel:ChangeSort(sort)
	end

	if not wheel:SelectSong(first_song) then return end

	-- Now force the wheel to redraw around the song we just selected.
	--
	-- SelectSong expands the target section via SetOpenSections(), which ends by
	-- calling RebuildWheelItems() -- and only THEN does SelectSong assign
	-- m_iSelection (MusicWheel.cpp:385-389). So the selection is right internally
	-- but the visible rows were already built around the index SetOpenSections
	-- had left behind: 0, the very first item in the list. That is exactly the
	-- reported "the pack opens but the selector sits on the first pack", and it
	-- is also why the rail itself never moved -- SelectSong posts no
	-- SM_SongChanged, so GAMESTATE's current song never changed and the
	-- CurrentSongChanged message the rail listens for never fired.
	--
	-- Move(+1) then Move(-1) each run ChangeMusic(), which rebuilds the items AND
	-- posts SM_SongChanged (MusicWheel.cpp:1565-1569); they cancel out, so the
	-- net selection is unchanged and no scroll sound plays (IsMoving() is true
	-- throughout). Move(0) then clears the moving state. Same nudge the sort menu
	-- already uses to refresh the favourite icons.
	wheel:Move(1)
	wheel:Move(-1)
	wheel:Move(0)
end

-- -----------------------------------------------------------------------
-- Ctrl+Left / Ctrl+Right.
--
-- An input callback cannot veto the event: for the topmost screen the engine
-- runs Screen::Input() BEFORE the Lua callbacks and then discards their return
-- value (ScreenManager::Input). Left/Right are bound to MenuLeft/MenuRight here,
-- which change difficulty, and they also feed the "Left-Right" code that opens
-- the sort menu -- so without help, ctrl+Left would jump packs AND step the
-- difficulty.
--
-- The fix is the one the sort menu and song search already use: redirect input
-- while ctrl is held. Redirected input skips Screen::Input() entirely but still
-- reaches Lua callbacks, so the arrows become ours alone for as long as ctrl is
-- down, and ctrl+Up/Down (SpeedModHotkey.lua) stops nudging the wheel as a side
-- effect too.
local redirected = false

local function SetRedirect(on)
	if on == redirected then return end
	redirected = on
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		SCREENMAN:set_input_redirected(player, on)
	end
end

local function PackRailInputHandler()
	return function(event)
		if not event then return false end

		if event.DeviceInput and event.DeviceInput.button == "DeviceButton_left ctrl" then
			SetRedirect(event.type ~= "InputEventType_Release")
			return false
		end

		if event.type ~= "InputEventType_FirstPress" then return false end

		if redirected and event.DeviceInput then
			if event.DeviceInput.button == "DeviceButton_left" then
				JumpToPack(-1)
			elseif event.DeviceInput.button == "DeviceButton_right" then
				JumpToPack(1)
			end
		end

		return false
	end
end

local InputHandler = PackRailInputHandler()

-- -----------------------------------------------------------------------

local af = Def.ActorFrame{
	Name="PackRail",
	InitCommand=function(self) self:xy(_screen.cx, RAIL_Y) end,
	OnCommand=function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		self:playcommand("Refresh")
	end,
	OffCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
		-- Safety net: if the ctrl release was never seen (focus loss, alt-tab)
		-- the redirect would otherwise persist and leave the next screen deaf.
		SetRedirect(false)
		self:linear(0.1):diffusealpha(0)
	end,
	CurrentSongChangedMessageCommand=function(self) self:playcommand("Refresh") end,
	MusicWheelSortMessageCommand=function(self) self:playcommand("Refresh") end,

	-- The header band itself, matching the footer's treatment exactly (see
	-- Footer.lua). Drawn here rather than by the screen-level header quad
	-- (Graphics/_header.lua, disabled for this screen) because that quad is
	-- forced to draw order 101 by the metrics, above the overlay, and the engine
	-- only sorts screen children once at Init -- so it would paint over this
	-- rail. As the rail's own first child it is reliably underneath it.
	--
	-- The header's "Select Music" / "ITG" / pad actors are siblings of the quad
	-- we disabled, still at 101, so they draw above this band.
	Def.Quad{
		InitCommand=function(self)
			self:zoomto(_screen.w, 32):vertalign(top)
			self:xy(0, -RAIL_Y)
			self:diffuse(color("#05080A")):diffusealpha(0.97)
		end
	},

	-- accent hairline along the band's lower edge
	Def.Quad{
		InitCommand=function(self)
			self:zoomto(_screen.w, 1):vertalign(top)
			self:xy(0, 32 - RAIL_Y)
			self:diffuse(DimColor(accent, 1.0, 0.45))
		end
	},

	-- previous pack, dimmed
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Prev",
		InitCommand=function(self)
			self:horizalign(right):zoom(NEIGHBOUR_ZOOM):x(-NEIGHBOUR_X)
			self:maxwidth(150/NEIGHBOUR_ZOOM):diffuse(faint)
		end,
		SetRailCommand=function(self, params)
			self:settext(params and params.prev or "")
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="ChevronLeft",
		Text="◀",
		InitCommand=function(self)
			self:zoom(0.4):x(-CHEVRON_X):diffuse(dim)
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="LegendLeft",
		Text=LEGEND_PREV,
		InitCommand=function(self)
			self:zoom(LEGEND_ZOOM):xy(-CHEVRON_X, LEGEND_Y):diffuse(quiet)
		end
	},

	-- current pack
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Current",
		InitCommand=function(self)
			self:zoom(CURRENT_ZOOM):maxwidth(170/CURRENT_ZOOM):diffuse(accent)
		end,
		SetRailCommand=function(self, params)
			self:settext(params and params.current or "")
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="ChevronRight",
		Text="▶",
		InitCommand=function(self)
			self:zoom(0.4):x(CHEVRON_X):diffuse(dim)
		end
	},

	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="LegendRight",
		Text=LEGEND_NEXT,
		InitCommand=function(self)
			self:zoom(LEGEND_ZOOM):xy(CHEVRON_X, LEGEND_Y):diffuse(quiet)
		end
	},

	-- next pack, dimmed
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Next",
		InitCommand=function(self)
			self:horizalign(left):zoom(NEIGHBOUR_ZOOM):x(NEIGHBOUR_X)
			self:maxwidth(150/NEIGHBOUR_ZOOM):diffuse(faint)
		end,
		SetRailCommand=function(self, params)
			self:settext(params and params.next or "")
		end
	},

	-- position in the full pack list, so "all packs" stays meaningful when there
	-- are dozens of them
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Counter",
		InitCommand=function(self)
			self:horizalign(right):zoom(0.4):x(COUNTER_X):diffuse(quiet)
		end,
		SetRailCommand=function(self, params)
			self:settext(params and params.counter or "")
		end
	},
}

-- One place computes the strings, then hands them to every child, so the five
-- actors can't disagree about which pack is current.
af.RefreshCommand=function(self)
	local index = IndexOfPack(CurrentPackName())

	if not index then
		self:playcommand("SetRail", { prev="", current="", next="", counter="" })
		return
	end

	local prev_i = ((index - 2) % #packs) + 1
	local next_i = (index % #packs) + 1

	self:playcommand("SetRail", {
		prev    = #packs > 1 and packs[prev_i] or "",
		current = packs[index],
		next    = #packs > 1 and packs[next_i] or "",
		counter = ("%d/%d"):format(index, #packs),
	})
end

return af
