local af, num_panes = unpack(...)

if not af
or type(num_panes) ~= "number"
then
	return
end

-- -----------------------------------------------------------------------
-- local variables

local panes, active_pane, active_graph = {}, {}, {}

local style = ToEnumShortString(GAMESTATE:GetCurrentStyle():GetStyleType())
local players = GAMESTATE:GetHumanPlayers()

local mpn = GAMESTATE:GetMasterPlayerNumber()

-- The count the caller passed in is the size of the manifest, not the number of panes that
-- actually loaded -- several return nil depending on game mode, modifiers, preferences and
-- whether GrooveStats is reachable. That mismatch is what the old FIXME here was about, and
-- it is why panes are now addressed by id: Panes/default.lua names actors by their compacted
-- position and publishes the surviving order, so this count and those names always agree.
num_panes = EvalPaneCount(ToEnumShortString(mpn))

-- EvalPanePrimary/Secondary hold pane ids. A stored id can be absent from this run -- the
-- EX pane does not exist in Casual -- so fall back to the first pane rather than to a
-- position that would mean something different every time.
local primary_i   = EvalPaneIndex(ToEnumShortString(mpn), SL[ToEnumShortString(mpn)].EvalPanePrimary)   or 1
local secondary_i = EvalPaneIndex(ToEnumShortString(mpn), SL[ToEnumShortString(mpn)].EvalPaneSecondary) or 1

-- -----------------------------------------------------------------------
-- initialize local tables (panes, active_pane) for the the input handling function to use

for controller=1,2 do

	panes[controller] = {}
	active_graph[controller] = 1

	-- Iterate through all potential panes, and only add the non-nil ones to the
	-- list of panes we want to consider.
	for i=1,num_panes do

		local pane = af:GetChild("Panes"):GetChild( ("Pane%i_SideP%i"):format(i, controller) )

		if pane ~= nil then
			-- single, double
			-- initialize the side ("controller") the player is joined as to their profile's EvalPanePrimary
			-- and the other side as their profile's EvalPaneSecondary
			if #players==1 then
				if ("P"..controller)==ToEnumShortString(mpn) then
					pane:visible(i == primary_i)
					active_pane[controller] = primary_i

				elseif ("P"..controller)==ToEnumShortString(OtherPlayer[mpn]) then
					pane:visible(i == secondary_i)
					active_pane[controller] = secondary_i

				end

			-- versus
			else
				-- initialize this player's active_pane to their profile's EvalPanePrimary
				-- will be 1 if no profile/"Guest" profile
				local p = EvalPaneIndex("P"..controller, SL["P"..controller].EvalPanePrimary) or 1
				pane:visible(i == p)
				active_pane[controller] = p
			end

		 	table.insert(panes[controller], pane)
		end
	end
end

-- -----------------------------------------------------------------------
-- don't allow double to initialize into a configuration like
-- EvalPanePrimary=3
-- EvalPaneSecondary=4
-- because Pane3 is full-width in double and the other pane is supposed to be hidden when it is visible

if style == "OnePlayerTwoSides" then
	local cn  = PlayerNumber:Reverse()[mpn] + 1
	local ocn = (cn % 2) + 1

	-- if the player wanted their primary pane to be something that is full-width in double
	if panes[cn][active_pane[cn]]:GetChild(""):GetCommand("ExpandForDouble") then
		-- hide all panes for the other controller
		for pane in ivalues(panes[ocn]) do
			pane:visible(false)
		end
		-- and only show the one full-width pane
		panes[cn][active_pane[cn]]:visible(true):diffusealpha(1)
	end

	-- if the player wanted their secondary pane to be something that is full-width in double
	if panes[cn][active_pane[ocn]]:GetChild(""):GetCommand("ExpandForDouble") then
		-- arbitrarily opt to hide the secondary pane
		panes[ocn][active_pane[ocn]]:visible(false)

		-- and show the next available pane that doesn't match primary and isn't also full-width
		for i=1,#panes[ocn] do
			active_pane[ocn] = (active_pane[ocn] % #panes[ocn]) + 1

			if active_pane[ocn] ~= active_pane[cn]
			and not panes[cn][active_pane[ocn]]:GetChild(""):GetCommand("ExpandForDouble")
			then
				panes[ocn][active_pane[ocn]]:visible(true):diffusealpha(1)
				break
			end
		end
	end
end

-- -----------------------------------------------------------------------
-- Pane numbering for the header.
--
-- The loaded pane count is NOT the number of pages you can reach. The navigation below
-- refuses to stop on a pane for three separate reasons, so the header is numbered against
-- the panes the cursor will actually land on, applying those same rules:
--
--   * the QR pane once there is nothing left to upload;
--   * a leaderboard that came back empty -- the GrooveStats panes load whenever the service
--     is switched on in the theme options, which says nothing about whether the machine is
--     actually online, so with no network they are present but empty;
--   * with one player joined, the pane the OTHER side is already showing. Both columns are
--     on screen at once and the duplicate check below steps past it, so it is visible
--     without being a page of this side's series.
--
-- The first two alone gave "1/5, 2/5, 3/5, 5/5" for what were really four pages.

local function PaneIsSkippable(pane)
	local root = pane:GetChild("")
	if root == nil then return false end

	-- the QR pane, once there is nothing left to upload
	local help = root:GetChild("HelpText")
	if help ~= nil and help:GetText() == "Score has already been submitted :)" then
		return true
	end

	-- a leaderboard whose first row is still the placeholder, i.e. one that came back
	-- empty -- or has not come back at all yet
	local list = root:GetChild("HighScoreList")
	if list ~= nil then
		local entry = list:GetChild("HighScoreEntry1")
		local name  = entry and entry:GetChild("Name")
		if name ~= nil and name:GetText() == "----" then return true end
	end

	return false
end

-- Position of `index` among the reachable panes, and how many there are.
--
-- Recomputed on every announcement rather than cached, because a leaderboard that was
-- empty at load stops being skippable the moment its response lands: the total is allowed
-- to grow during the screen's life.
local function PaneNumbering(cn, index)
	local ocn = (cn % 2) + 1

	-- The pane the other side is holding, which this side cannot land on. Never applied to
	-- `index` itself: whatever is being announced has to come out with a number, even if a
	-- profile somehow starts both sides on the same pane.
	local held = nil
	if #players == 1 and active_pane[ocn] ~= index then
		held = active_pane[ocn]
	end

	local shown, total = 1, 0

	for i=1, #panes[cn] do
		if i ~= held and not PaneIsSkippable(panes[cn][i]) then
			total = total + 1
			if i == index then shown = total end
		end
	end

	return shown, math.max(total, 1)
end

local function AnnouncePane(cn)
	local shown, total = PaneNumbering(cn, active_pane[cn])

	MESSAGEMAN:Broadcast("EvalPaneChanged", {
		Controller = cn,
		Index      = active_pane[cn],
		Display    = shown,
		Total      = total,
	})
end

-- The opening state. Done here rather than from the header actor itself, which has no way
-- to see the panes and so could not tell a reachable one from a skipped one.
AnnouncePane(PlayerNumber:Reverse()[mpn] + 1)

-- -----------------------------------------------------------------------
-- input handling function

local OtherController = {
	GameController_1 = "GameController_2",
	GameController_2 = "GameController_1"
}

return function(event)


	if not (event and event.PlayerNumber and event.button) then return false end

	-- get a "controller number" and an "other controller number"
	-- if the input event came from GameController_1, cn will be 1 and ocn will be 2
	-- if the input event came from GameController_2, cn will be 2 and ocn will be 1
	--
	-- we'll use these integers to index the active_pane table, which keeps track
	-- of which pane is currently showing on each side
	local  cn = tonumber(ToEnumShortString(event.controller))
	local ocn = tonumber(ToEnumShortString(OtherController[event.controller]))

	if event.type == "InputEventType_FirstPress" and panes[cn] then

		if event.GameButton == "MenuUp" or event.GameButton == "MenuDown" then
			if event.GameButton == "MenuUp" then
				active_graph[cn] = (active_graph[cn] - 1) % 3
				if active_graph[cn] == 0 then active_graph[cn] = 3 end
			else
				active_graph[cn] = (active_graph[cn] % 3) + 1
			end
			
			if #players==1 then
				af:GetChild(ToEnumShortString(mpn) .. "_AF_Lower"):GetChild("JudgeGraph"):visible(active_graph[cn] == 1)
				af:GetChild(ToEnumShortString(mpn) .. "_AF_Lower"):GetChild("ArrowGraph"):visible(active_graph[cn] > 1)
				af:GetChild(ToEnumShortString(mpn) .. "_AF_Lower"):GetChild("ArrowGraph"):GetChild("ArrowPlot"):visible(active_graph[cn] == 2)
				af:GetChild(ToEnumShortString(mpn) .. "_AF_Lower"):GetChild("ArrowGraph"):GetChild("FootPlot"):visible(active_graph[cn] == 3)
				af:GetChild(ToEnumShortString(mpn) .. "_AF_Lower"):GetChild("ArrowGraph"):GetChild("Feet"):visible(active_graph[cn] == 3)
				panes[ocn][3]:playcommand("Graph", {graph=active_graph[cn]})
			else
				af:GetChild("P" .. cn .. "_AF_Lower"):GetChild("JudgeGraph"):visible(active_graph[cn] == 1)
				af:GetChild("P" .. cn .. "_AF_Lower"):GetChild("ArrowGraph"):visible(active_graph[cn] > 1)
				af:GetChild("P" .. cn .. "_AF_Lower"):GetChild("ArrowGraph"):GetChild("ArrowPlot"):visible(active_graph[cn] == 2)
				af:GetChild("P" .. cn .. "_AF_Lower"):GetChild("ArrowGraph"):GetChild("FootPlot"):visible(active_graph[cn] == 3)
				af:GetChild("P" .. cn .. "_AF_Lower"):GetChild("ArrowGraph"):GetChild("Feet"):visible(active_graph[cn] == 3)
			end
			panes[cn][2]:playcommand("Graph", {graph=active_graph[cn]})
			panes[cn][3]:playcommand("Graph", {graph=active_graph[cn]})
		end
		
		if event.GameButton == "MenuRight" or event.GameButton == "MenuLeft" then
			if event.GameButton == "MenuRight" then
				active_pane[cn] = (active_pane[cn] % #panes[cn]) + 1
				-- don't allow duplicate panes to show in single/double
				-- if the above change would result in duplicate panes, increment again
				
				-- Skip QR code pane if it has already been submitted
				-- Is there any other instances we want to skip?
				QRPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HelpText")
				if QRPane ~= nil and QRPane:GetText() == "Score has already been submitted :)" then
					active_pane[cn] = ((active_pane[cn]) % #panes[cn]) + 1
				end

				-- Only show the leaderboard panes (GS/RPG/ITL) if they contain any entries.
				-- Can't check the results when the screen loads because of response times,
				-- so we have to check when we change panes.

				-- Originally I made it to remove the actor if it doesn't return results
				-- but the only way I could get that to work was using global variables.
				-- This seems to work for now, until the pane system is revamped.

				-- Check if the next pane is a leaderboard pane
				-- I don't know why the pane numbers are different to the actor names but this works
				local checkskip = false
				if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") ~= nil then checkskip = true end

				while checkskip do
					local leaderboardPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList"):GetChild("HighScoreEntry1"):GetChild("Name")
					-- If there are no results, the first place name would not have changed from "----"
					if leaderboardPane:GetText() == "----" then 
						active_pane[cn] = (active_pane[cn] % #panes[cn]) + 1 
					else
						-- If the text has changed, that means there is results. Don't skip this pane. Exit loop.
						checkskip = false
					end
					-- If the next pane is not a high score pane, also exit loop
					if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") == nil then checkskip = false end
				end
				
				if #players==1 and active_pane[cn] == active_pane[ocn] then
					active_pane[cn] = (active_pane[cn] % #panes[cn]) + 1

					
					-- Skip QR code pane if it has already been submitted
					-- Is there any other instances we want to skip?
					QRPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HelpText")
					if QRPane ~= nil and QRPane:GetText() == "Score has already been submitted :)" then
						active_pane[cn] = ((active_pane[cn]) % #panes[cn]) + 1
					end

					-- Only show the leaderboard panes (GS/RPG/ITL) if they contain any entries.
					-- Can't check the results when the screen loads because of response times,
					-- so we have to check when we change panes.

					-- Originally I made it to remove the actor if it doesn't return results
					-- but the only way I could get that to work was using global variables.
					-- This seems to work for now, until the pane system is revamped.

					-- Check if the next pane is a leaderboard pane
					-- I don't know why the pane numbers are different to the actor names but this works
					local checkskip = false
					if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") ~= nil then checkskip = true end

					while checkskip do
						local leaderboardPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList"):GetChild("HighScoreEntry1"):GetChild("Name")
						-- If there are no results, the first place name would not have changed from "----"
						if leaderboardPane:GetText() == "----" then 
							active_pane[cn] = (active_pane[cn] % #panes[cn]) + 1 
						else
							-- If the text has changed, that means there is results. Don't skip this pane. Exit loop.
							checkskip = false
						end
						-- If the next pane is not a high score pane, also exit loop
						if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") == nil then checkskip = false end
					end

				end

			elseif event.GameButton == "MenuLeft" then
				active_pane[cn] = ((active_pane[cn] - 2) % #panes[cn]) + 1
				-- don't allow duplicate panes to show in single/double
				-- if the above change would result in duplicate panes, decrement again

				-- Only show the leaderboard panes (GS/RPG/ITL) if they contain any entries.
				-- Can't check the results when the screen loads because of response times,
				-- so we have to check when we change panes.

				-- Originally I made it to remove the actor if it doesn't return results
				-- but the only way I could get that to work was using global variables.
				-- This seems to work for now, until the pane system is revamped.

				-- Check if the next pane is a leaderboard pane
				-- I don't know why the pane numbers are different to the actor names but this works
				local checkskip = false
				if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") ~= nil then checkskip = true end

				while checkskip do
					local leaderboardPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList"):GetChild("HighScoreEntry1"):GetChild("Name")
					-- If there are no results, the first place name would not have changed from "----"
					if leaderboardPane:GetText() == "----" then 
						active_pane[cn] = (active_pane[cn] -2 % #panes[cn]) + 1 
					else
						-- If the text has changed, that means there is results. Don't skip this pane. Exit loop.
						checkskip = false
					end
					-- If the next pane is not a high score pane, also exit loop
					if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") == nil then checkskip = false end
				end
				
				-- Skip QR code pane if it has already been submitted
				-- Is there any other instances we want to skip?
				QRPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HelpText")
				if QRPane ~= nil and QRPane:GetText() == "Score has already been submitted :)" then
					active_pane[cn] = ((active_pane[cn] - 2) % #panes[cn]) + 1
				end
					
				if #players==1 and active_pane[cn] == active_pane[ocn] then
					active_pane[cn] = ((active_pane[cn] - 2) % #panes[cn]) + 1

					-- Check if the next pane is a leaderboard pane
					-- I don't know why the pane numbers are different to the actor names but this works
					local checkskip = false
					if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") ~= nil then checkskip = true end

					while checkskip do
						local leaderboardPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList"):GetChild("HighScoreEntry1"):GetChild("Name")
						-- If there are no results, the first place name would not have changed from "----"
						if leaderboardPane:GetText() == "----" then 
							active_pane[cn] = (active_pane[cn] -2 % #panes[cn]) + 1 
						else
							-- If the text has changed, that means there is results. Don't skip this pane. Exit loop.
							checkskip = false
						end
						-- If the next pane is not a high score pane, also exit loop
						if panes[cn][active_pane[cn]]:GetChild(""):GetChild("HighScoreList") == nil then checkskip = false end
					end
					
					-- Skip QR code pane if it has already been submitted
					-- Is there any other instances we want to skip?
					QRPane = panes[cn][active_pane[cn]]:GetChild(""):GetChild("HelpText")
					if QRPane ~= nil and QRPane:GetText() == "Score has already been submitted :)" then
						active_pane[cn] = ((active_pane[cn] - 2) % #panes[cn]) + 1
					end


				end
			end


			-- double
			if style == "OnePlayerTwoSides" then
				-- if this controller is switching to Pane3 or Pane6, both of which take over both pane widths
				if panes[cn][active_pane[cn]]:GetChild(""):GetCommand("ExpandForDouble") then

					-- hide all panes for both controllers
					for controller=1,2 do
						for pane in ivalues(panes[controller]) do
							pane:visible(false)
						end
					end
					-- and only show the one full-width pane
					panes[cn][active_pane[cn]]:visible(true):diffusealpha(1)


				-- if this controller is switching panes while the OTHER controller was viewing Pane3 or Pane6
				elseif panes[ocn][active_pane[ocn]]:GetChild(""):GetCommand("ExpandForDouble") then
					panes[ocn][active_pane[ocn]]:visible(false)
					panes[cn][active_pane[cn]]:visible(true):diffusealpha(1)
					-- atribitarily choose to decrement other controller pane
					active_pane[ocn] = ((active_pane[ocn] - 2) % #panes[ocn]) + 1
					if active_pane[cn] == active_pane[ocn] then
						active_pane[ocn] = ((active_pane[ocn] - 2) % #panes[ocn]) + 1
					end
					panes[ocn][active_pane[ocn]]:visible(true):diffusealpha(1)

				else

					-- hide all panes for this side
					for i=1,#panes[cn] do
						panes[cn][i]:visible(false)
					end
					-- show the panes we want on both sides
					panes[cn][active_pane[cn]]:visible(true):diffusealpha(1)
					panes[ocn][active_pane[ocn]]:visible(true):diffusealpha(1)
				end


			-- single, versus
			else
				-- hide all panes for this side
				for i=1,#panes[cn] do
					panes[cn][i]:visible(false)
				end
				-- only show the pane we want on this side
				panes[cn][active_pane[cn]]:visible(true):diffusealpha(1)
			end

			af:queuecommand("PaneSwitch")

			-- PaneSwitch says only "something moved"; the title needs to know WHERE. Sent
			-- for both sides because a double-mode switch can move the other side too --
			-- but the ACTING side goes last, because the title can only name one and the
			-- last announcement wins. Announcing the other side last would have made the
			-- header describe the pane the player did not just move.
			AnnouncePane(ocn)
			AnnouncePane(cn)
		end
	end

	if PREFSMAN:GetPreference("OnlyDedicatedMenuButtons") and event.type ~= "InputEventType_Repeat" then
		MESSAGEMAN:Broadcast("TestInputEvent", event)
	end

	return false
end
