-- "Technique HUD" density-graph palette.
--
-- Monochrome: a single hue across the whole graph. The stock graph ramped
-- blue -> purple by measure height, but the contour's own shape already conveys
-- density, so the hue ramp was redundant decoration. Alpha still falls off
-- toward the baseline so the area reads as a fill beneath a bright top edge
-- (the "liseret", drawn by NPS_Histogram_Stroke below) rather than a solid
-- block of colour.
--
-- Opt-in: only callers passing hud=true get this. Gameplay's scrolling graph
-- and the evaluation graphs keep the stock blue/purple until asked, since
-- gen_vertices is shared by all of them.
--
-- TWEAK: HUD_FILL is the graph's colour; the two alphas are its vertical fade.
local HUD_FILL       = color("#00C8DE")
local HUD_ALPHA_TOP  = 0.72
local HUD_ALPHA_BASE = 0.10
-- thickness of the liseret, in the graph's own pixel units
local HUD_STROKE_PX    = 1.5
local HUD_STROKE_ALPHA = 0.95

local function gen_vertices(player, width, height, Steps, desaturation, hud)
	local Song
	local first_step_has_occurred = false
	local pn = ToEnumShortString(player)

	if not Steps then 
		if GAMESTATE:IsCourseMode() then
			local TrailEntry = GAMESTATE:GetCurrentTrail(player):GetTrailEntry(GAMESTATE:GetCourseSongIndex())
			Steps = TrailEntry:GetSteps()
		else
			Steps = GAMESTATE:GetCurrentSteps(player)
		end
	end
	Song = SONGMAN:GetSongFromSteps(Steps)
	
	if not Steps or not Song then return {} end

	-- This function does no work if we already have the data in SL.Streams cache.
	ParseChartInfo(Steps, pn)
	PeakNPS = SL[pn].Streams.PeakNPS
	NPSperMeasure = SL[pn].Streams.NPSperMeasure 
	-- store the PeakNPS in GAMESTATE:Env()[pn.."PeakNPS"] in case both players are joined
	-- their charts may have different peak densities, and if they both want histograms,
	-- we'll need to be able to compare densities and scale one of the graphs vertically
	GAMESTATE:Env()[pn.."PeakNPS"] = PeakNPS

	-- use MESSAGEMAN to broadcast that the peak NPS has been calculated (and/or updated in CourseMode)
	-- and is available.  actors on the current screen can listen for this via something like:
	--
	-- PeakNPSUpdatedMessageCommand=function(self)
	--   local p1peak = GAMESTATE:Env()["P1PeakNPS"]
	-- end
	MESSAGEMAN:Broadcast("PeakNPSUpdated")

	local verts = {}
	local x, y, t

	if (PeakNPS and NPSperMeasure and #NPSperMeasure > 1) then
		local TimingData = Steps:GetTimingData()
		local FirstSecond = math.min(TimingData:GetElapsedTimeFromBeat(0), 0)
		local LastSecond = Song:GetLastSecond()

		-- magic numbers obtained from Photoshop's Eyedrop tool in rgba percentage form (0 to 1)
		local blue   = {0,    0.678, 0.753, 1}
		local purple = {0.51, 0,     0.631, 1}

		-- HUD palette: one hue everywhere, fading out toward the baseline. Both
		-- ends of the ramp get the same colour so the lerp below is a no-op and
		-- the graph comes out monochrome. See the constants at the top.
		-- Separate tables, not two references to one, so the Desaturate() calls
		-- below cannot apply twice to the same values.
		local base_alpha = 1
		if hud then
			blue   = {HUD_FILL[1], HUD_FILL[2], HUD_FILL[3], HUD_ALPHA_TOP}
			purple = {HUD_FILL[1], HUD_FILL[2], HUD_FILL[3], HUD_ALPHA_TOP}
			base_alpha = HUD_ALPHA_BASE
		end

		if desaturation ~= nil then
			local function Desaturate(color, desaturation)
				local luma = 0.3 * color[1] + 0.59 * color[2] + 0.11 * color[3]
				color[1] = color[1] + desaturation * (luma - color[1])
				color[2] = color[2] + desaturation * (luma - color[2])
				color[3] = color[3] + desaturation * (luma - color[3])
				return color
			end
			blue = Desaturate(blue, desaturation)
			purple = Desaturate(purple, desaturation)
		end

		-- baseline colour: the low-density hue, faded out in HUD mode so the fill
		-- reads as a gradient. Identical to `blue` in stock mode.
		local lower = {blue[1], blue[2], blue[3], base_alpha}

		local upper

		for i, nps in ipairs(NPSperMeasure) do

			if nps > 0 then first_step_has_occurred = true end

			if first_step_has_occurred then
				-- i will represent the current measure number but will be 1 larger than
				-- it should be (measures in SM start at 0; indexed Lua tables start at 1)
				-- subtract 1 from i now to get the actual measure number to calculate time
				t = TimingData:GetElapsedTimeFromBeat((i-1)*4)

				x = scale(t, FirstSecond, LastSecond, 0, width)
				y = round(-1 * scale(nps, 0, PeakNPS, 0, height))

				-- if the height of this measure is the same as the previous two measures
				-- we don't need to add two more points (bottom and top) to the verts table,
				-- we can just "extend" the previous two points by updating their x position
				-- to that of the current measure.  For songs with long streams, this should
				-- cut down on the overall size of the verts table significantly.
				if #verts > 2 and verts[#verts][1][2] == y and verts[#verts-2][1][2] == y then
					verts[#verts][1][1] = x
					verts[#verts-1][1][1] = x
				else
					-- lerp_color() is a global function defined by the SM engine that takes three arguments:
					--    a float between [0,1]
					--    color1
					--    color2
					-- and returns a color that has been linearly interpolated by that percent between the two colors provided
					-- for example, lerp_color(0.5, yellow, orange) will return the color that is halfway between yellow and orange
					upper = lerp_color(math.abs(y/height), blue, purple )

					verts[#verts+1] = {{x, 0, 0}, lower} -- baseline
					verts[#verts+1] = {{x, y, 0}, upper}  -- top of graph (somewhere between the two hues)
				end
			end
		end

		-- Insert a 0 NPS datapoint at the end of the graph, otherwise
		-- the last measure will not have a nice downwards slope like
		-- all the other measures but end abruptly at the start of the
		-- measure.
		if NPSperMeasure[#NPSperMeasure] ~= 0 then
			verts[#verts+1] = {{width, 0, 0}, lower}
			verts[#verts+1] = {{width, 0, 0}, lower}
		end
	end

	return verts
end

local function TotalCourseLength(player)
    -- utility for graph stuff because i ended up doing this a lot
    -- i use this method instead of TrailUtil.GetTotalSeconds because that leaves unused time at the end in graphs
    local trail = GAMESTATE:GetCurrentTrail(player)
    local t = 0
    for te in ivalues(trail:GetTrailEntries()) do
        t = t + te:GetSong():GetLastSecond()
    end

    return t
end

-- This function interpolates between two vertices based on a given offset
function interpolate_vert(v1, v2, offset)
    -- Calculate the ratio of the offset to the difference in x-coordinates of the two vertices
    local ratio = (offset - v1[1][1]) / (v2[1][1] - v1[1][1])
    -- Interpolate the y-coordinate based on the ratio
    local y = v1[1][2] * (1 - ratio) + v2[1][2] * ratio
    -- Interpolate the color based on the ratio
    local color = lerp_color(ratio, v1[2], v2[2])
    -- Return the interpolated vertex and color as a table
    return {{offset, y, 0}, color}
end

function NPS_Histogram(player, width, height, desaturation, hud)
	local pn = ToEnumShortString(player)
	local amv = Def.ActorMultiVertex{
		InitCommand=function(self)
			self:SetDrawState({Mode="DrawMode_QuadStrip"})
		end,
		["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self)
			self:queuecommand("Redraw")
		end,
		RedrawCommand=function(self)
			-- we've reached a new song, so reset the vertices for the density graph
			-- this will occur at the start of each new song in CourseMode
			-- and at the start of "normal" gameplay
			local verts = gen_vertices(player, width, height, nil, desaturation, hud)
			self:SetNumVertices(#verts):SetVertices(verts)
		end
	}

	return amv
end

-- The bright top edge ("liseret") that traces the density graph's contour.
--
-- Drawn as its own thin QuadStrip rather than a DrawMode_LineStrip: line
-- thickness there depends on the graphics driver's minimum line width, so a
-- 1.5px request is not portable. Two vertices per contour point, offset
-- downward into the fill, give an exact and consistent thickness.
--
-- Meant to be layered directly over NPS_Histogram with the same width/height
-- and the same positioning, so the two stay registered.
function NPS_Histogram_Stroke(player, width, height, desaturation)
	local pn = ToEnumShortString(player)
	local amv = Def.ActorMultiVertex{
		InitCommand=function(self)
			self:SetDrawState({Mode="DrawMode_QuadStrip"})
		end,
		["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self)
			self:queuecommand("Redraw")
		end,
		RedrawCommand=function(self)
			-- Derive from the fill's own vertices so the two can never disagree
			-- about the contour. gen_vertices emits [baseline, top, baseline, top,
			-- ...], so the tops are the even indices.
			local fill = gen_vertices(player, width, height, nil, desaturation, true)
			local verts = {}

			for i=2, #fill, 2 do
				local x, y = fill[i][1][1], fill[i][1][2]
				local c = fill[i][2]
				-- same hue as the fill, at near-full strength so the contour reads
				-- as a bright edge on top of it
				local edge = {c[1], c[2], c[3], HUD_STROKE_ALPHA}
				-- y is negative upward, so +thickness moves down into the fill.
				-- Clamped at the baseline: measures with no notes sit at y=0, and
				-- without this the edge would poke below the graph there (and at
				-- the closing vertex) instead of vanishing into it.
				local y2 = math.min(y + HUD_STROKE_PX, 0)
				verts[#verts+1] = {{x, y, 0}, edge}
				verts[#verts+1] = {{x, y2, 0}, edge}
			end

			self:SetNumVertices(#verts):SetVertices(verts)
		end
	}

	return amv
end

-- set of density graphs for a course
-- one little issue here is that varying nps per song isn't reflected by the relative height of each chart
-- honestly too big of a hassle for me to mess with right now
function NPS_Histogram_Static_Course(player, width, height, desaturation)
	local pn = ToEnumShortString(player)
	local af = Def.ActorFrame{}
	local trail = GAMESTATE:GetCurrentTrail(pn)
	
	-- first get the total time
	local totaltime = TotalCourseLength(player) / SL.Global.ActiveModifiers.MusicRate
	
	-- build a table of offsets and widths (doing one loop with everything in InitCommand will just use
	-- the last value whatever local variable in the loop was once the actors execute)
	local curx = 0
	local ptable = {}
	for te in ivalues(trail:GetTrailEntries()) do
		local w = (te:GetSong():GetLastSecond() / SL.Global.ActiveModifiers.MusicRate / totaltime) * width
		table.insert(ptable, {curx, w, te:GetSteps()})
		curx = curx + w
	end
	for i, pos in ipairs(ptable) do
		-- add density graph amv
		af[#af+1] = Def.ActorMultiVertex{
			InitCommand = function(self)
				self:x(pos[1])
				self:SetDrawState({Mode="DrawMode_QuadStrip"})
				self:queuecommand("SetVertices")
			end,
			SetVerticesCommand = function(self)
				local verts = gen_vertices(player, pos[2], height, pos[3], desaturation)
				self:SetNumVertices(#verts):SetVertices(verts)
			end
		}
	end

	return af
end


function Scrolling_NPS_Histogram(player, width, height, desaturation)
	local verts, visible_verts
	local left_idx, right_idx

	local amv = Def.ActorMultiVertex{
		InitCommand=function(self)
			self:SetDrawState({Mode="DrawMode_QuadStrip"})
		end,
		UpdateCommand=function(self)
			if visible_verts ~= nil then
				self:SetNumVertices(#visible_verts):SetVertices(visible_verts)
				visible_verts = nil
			end
		end,

		LoadCurrentSong=function(self, scaled_width)
			verts = gen_vertices(player, scaled_width, height, nil, desaturation)

			left_idx = 1
			right_idx = 2
			self:SetScrollOffset(0)
		end,
		SetScrollOffset=function(self, offset)
			local left_offset = offset
			local right_offset = offset + width

			for i = left_idx, #verts, 2 do
				if verts[i][1][1] >= left_offset then
					left_idx = i
					break
				end
			end

			for i = right_idx, #verts, 2 do
				if verts[i][1][1] <= right_offset then
					right_idx = i
				else
					break
				end
			end

			if left_idx == 1 and right_idx == #verts then
				-- All vertices are visible.
				-- This saves memory as the assignment here isn't a copy unlike unpack().
				-- This is necessary for songs like "Blue (Da Ba Dee)" from Crapyard Scent.
				visible_verts = verts
			else
				-- Pick ther vertices to display.
				visible_verts = {unpack(verts, left_idx, right_idx)}

				if left_idx > 1 then
					local prev1, prev2, cur1, cur2 = unpack(verts, left_idx-2, left_idx+1)
					table.insert(visible_verts, 1, interpolate_vert(prev1, cur1, left_offset))
					table.insert(visible_verts, 2, interpolate_vert(prev2, cur2, left_offset))
				end

				if right_idx < #verts then
					local cur1, cur2, next1, next2 = unpack(verts, right_idx-1, right_idx+2)
					table.insert(visible_verts, interpolate_vert(cur1, next1, right_offset))
					table.insert(visible_verts, interpolate_vert(cur2, next2, right_offset))
				end
			end
		end
	}

	return amv
end
