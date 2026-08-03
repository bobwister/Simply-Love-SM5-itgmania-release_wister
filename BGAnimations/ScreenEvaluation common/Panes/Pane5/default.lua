-- Pane5 displays an aggregate histogram of judgment offsets
-- as well as the mean timing error, median, and mode of those offsets.

local player, _, ComputedData = unpack(...)
local pn = ToEnumShortString(player)

-- table of offset values obtained during this song's playthrough
-- obtained via ./BGAnimations/ScreenGameplay overlay/JudgmentOffsetTracking.lua
local sequential_offsets = SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].sequential_offsets
local pane_width, pane_height = 300, 180
local topbar_height = 26
local bottombar_height = 13

-- Determine timing windows that need to be covered in the histogram based on worst judgment hit during gameplay
local num_judgments_available = math.max(3, GetWorstJudgment(sequential_offsets))
local worst_window = GetTimingWindow(num_judgments_available)

-- ---------------------------------------------

local abbreviations = {
	ITG = { "Fan", "Ex", "Gr", "Dec", "WO" },
	["FA+"] = { "Fan", "Fan", "Ex", "Gr", "Dec" },
}

local colors = {}
for w=num_judgments_available,1,-1 do
	if SL[pn].ActiveModifiers.TimingWindows[w]==true then
		colors[w] = DeepCopy(SL.JudgmentColors[SL.Global.GameMode][w])
	else
		abbreviations[SL.Global.GameMode][w] = abbreviations[SL.Global.GameMode][w+1]
		colors[w] = DeepCopy(colors[w+1] or SL.JudgmentColors[SL.Global.GameMode][w+1])
	end
end

-- ---------------------------------------------
-- sequential_offsets is a table of all timing offsets in the order they were earned.
-- The sequence is important for the Scatter Plot, but irrelevant here; we are only really
-- interested in how many +0.001 offsets were earned, how many -0.001, how many +0.002, etc.
-- So, we loop through sequential_offsets, and tally offset counts into a new offsets table.
local offsets = {}
local sum_timing_error = 0
local avg_timing_error = 0
local sum_timing_offset = 0
local avg_offset = 0
local std_dev = 0
local max_error = 0
local count = 0

local max_error = 0 -- Temporary fix for non rounded max error until mainline SL fixes it

for t in ivalues(sequential_offsets) do
	-- the first value in t is CurrentMusicSeconds when the offset occurred, which we don't need here
	-- the second value in t is the offset value or the string "Miss"
	local val = t[2]

	if val ~= "Miss" then
		count = count + 1

		-- check if this is the highest error amount
		-- if higher, it's the new max
		if math.abs(val) > max_error then
			max_error = math.abs(val)
		end

		sum_timing_offset = sum_timing_offset + val
		sum_timing_error = sum_timing_error + math.abs(val)

		val = (math.floor(val*1000))/1000

		if not offsets[val] then
			offsets[val] = 1
		else
			offsets[val] = offsets[val] + 1
		end
	end
end

if count > 0 then
	avg_timing_error = sum_timing_error / count
	avg_offset = sum_timing_offset / count
	-- standard deviation needs at least two values otherwise we'd divide by 0
	if count > 1 then
		local sum_diff_squared = 0
		for t in ivalues(sequential_offsets) do
			local val = t[2]
			if val ~= "Miss" then
				sum_diff_squared = sum_diff_squared + math.pow((val - avg_offset), 2)
			end
		end
		std_dev = math.sqrt(sum_diff_squared / (count - 1))
	end

	-- convert seconds to ms
	avg_timing_error = avg_timing_error * 1000
	avg_offset = avg_offset * 1000
	std_dev = std_dev * 1000
	max_error = max_error * 1000
end

-- ---------------------------------------------
-- Actors

local pane = Def.ActorFrame{
	InitCommand=function(self)
		self:xy(-pane_width*0.5, pane_height*1.95)
	end
}

-- ---------------------------------------------
-- Axis furniture.
--
-- The histogram had no scale at all: a bar's horizontal position was readable only against
-- the judgment abbreviations along the bottom, which tell you WHICH window you landed in
-- but never by how much. These add the millisecond ruler that was missing.
--
-- The window boundaries are drawn BEFORE the histogram is added below, so the bars sit on
-- top of them rather than being cut by them: they are backdrop, and a bar's height is the
-- thing being read. The two lines that describe the RUN -- dead centre and the bias -- are
-- the opposite case and are added last, at the bottom of this file.

-- Height of the histogram body: bars are scaled to pane_height*0.75 in Calculations.lua.
local body_height = pane_height * 0.75

-- x of the mean-offset line, in pane coordinates. Computed with the rest of the summary
-- below, but drawn at the very end of the file, so it has to outlive that block.
local mean_x = nil

-- TWEAK: RULER_Y is where the millisecond numbers sit. It lines up with the existing
-- "Early"/"Late" texts so the top of the body reads as one ruler line rather than two
-- rows of stray text. Bars are shortest out at the window boundaries, which is exactly
-- where these numbers go, so collisions are rare.
local RULER_Y    = -125
local RULER_ZOOM = 0.4

-- TWEAK: the mean marker's colour. Deliberately outside the judgment palette -- it is not
-- a timing window, it is a property of the run -- and shared by the line and the hotkey
-- hint so the two read as one statement.
local MEAN_COLOR = color("#FFB000")

-- Maps a timing offset in SECONDS onto the pane's x axis. GetTimingWindow returns
-- seconds, and this is the same mapping the judgment labels along the bottom already use.
local function XForOffset(seconds)
	return scale(seconds, -worst_window, worst_window, 0, pane_width)
end

-- A guide line at each timing-window boundary, plus the boundary's value in ms. Drawn for
-- both the early and the late side of each window.
for i=1, num_judgments_available do
	local window = GetTimingWindow(i)

	-- The outermost boundary IS the edge of the pane, where a line would just thicken the
	-- border and the number would be clipped.
	if window < worst_window then
		for _, sign in ipairs({-1, 1}) do
			local x = XForOffset(sign * window)

			pane[#pane+1] = Def.Quad{
				InitCommand=function(self)
					self:vertalign(bottom):xy(x, 0)
						:zoomto(1, body_height)
						:diffuse( DimColor(colors[i], 1.0, 0.22) )
				end,
			}

			pane[#pane+1] = Def.BitmapText{
				Font=ThemePrefs.Get("ThemeFont") .. " Normal",
				Text=("%+d"):format(sign * window * 1000),
				InitCommand=function(self)
					self:xy(x, RULER_Y):zoom(RULER_ZOOM)
						:diffuse( DimColor(colors[i], 1.0, 0.75) )
				end,
			}
		end
	end
end

-- ---------------------------------------------
-- The three summary numbers along the top bar describe the SHAPE of this histogram, but
-- nothing tied them to it -- you had to picture what "mean -4.20ms" or "std dev * 3"
-- looked like against the bars. These draw them.
--
-- Only worth doing when there were offsets to summarise; with no hits, avg_offset and
-- std_dev are both still 0 and a line at dead centre would be a lie.
if count > 0 then
	-- The +/- 3 sigma band, which is the "std dev * 3" readout made visible: on a normal
	-- distribution it is where about 99.7% of the hits fall, so its width is a direct
	-- picture of consistency. Drawn first, so the mean line lands on top of it.
	if std_dev > 0 then
		local lo = XForOffset( (avg_offset - std_dev*3) / 1000 )
		local hi = XForOffset( (avg_offset + std_dev*3) / 1000 )

		-- Clamped: three sigma on a scattered run runs off both ends of the pane, and an
		-- unclamped quad would spill over the border and the neighbouring pane.
		lo = clamp(lo, 0, pane_width)
		hi = clamp(hi, 0, pane_width)

		if hi > lo then
			pane[#pane+1] = Def.Quad{
				InitCommand=function(self)
					self:vertalign(bottom):horizalign(left):xy(lo, 0)
						:zoomto(hi - lo, body_height)
						:diffuse(1, 1, 1, 0.07)
				end,
			}
		end
	end

	-- The mean offset itself. Only the position is settled here; the line is drawn at the
	-- end of the file so it lands on top of the bars.
	local x = XForOffset(avg_offset / 1000)
	if x >= 0 and x <= pane_width then mean_x = x end

	-- Ctrl+F6 resyncs the song's #OFFSET to cancel this very mean, and nothing on the
	-- screen said so -- the feature was discoverable only by reading ResyncHandler.lua.
	--
	-- Shown only when it would actually do something, and only when it would actually
	-- work. The conditions mirror ResyncHandler.lua exactly (solo, not course mode);
	-- advertising a hotkey that is wired to nothing would be worse than saying nothing.
	-- TWEAK: RESYNC_HINT_MS is how far off centre the mean has to be before this is worth
	-- suggesting. Below a few ms the resync is noise, not a correction.
	local RESYNC_HINT_MS = 3

	if math.abs(avg_offset) >= RESYNC_HINT_MS
		and #GAMESTATE:GetHumanPlayers() == 1
		and not GAMESTATE:IsCourseMode()
	then
		-- Anchored to the far LEFT edge of the body, not the centre. Two reasons: the
		-- centre is where the tallest bars are, and everything above y=-body_height is
		-- covered by the top bar's background quad, which is added further down this file
		-- and therefore draws on top. The left edge is the worst-judgment end of the
		-- scale, where there is essentially never a bar to collide with.
		--
		-- Sits BELOW the "Early" label rather than beside it: that label is also
		-- left-anchored (x=10, y=-125, zoom 0.5, further down this file), so the two
		-- shared the same corner and overlapped.
		pane[#pane+1] = Def.BitmapText{
			Font=ThemePrefs.Get("ThemeFont") .. " Normal",
			Text=ScreenString("ResyncHint"),
			InitCommand=function(self)
				self:horizalign(left):xy(4, -body_height + 27):zoom(0.38)
					:diffuse(MEAN_COLOR):diffusealpha(0.9)
					:maxwidth((pane_width - 8) / 0.38)
			end,
		}
	end
end

-- "Early" text
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Bold",
	Text=ScreenString("Early"),
	InitCommand=function(self)
		self:addx(10):addy(-125)
			:zoom(0.5)
			:horizalign(left)
		--if ThemePrefs.Get("VisualStyle") == "Technique" then
		--	self:diffusealpha(0.5)
		--end
	end,
}

-- "Late" text
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Bold",
	Text=ScreenString("Late"),
	InitCommand=function(self)
		self:addx(pane_width-10):addy(-125)
			:zoom(0.5)
			:horizalign(right)
	end,
}

-- --------------------------------------------------------

-- darkened quad behind bottom judgment labels
pane[#pane+1] = Def.Quad{
	InitCommand=function(self)
		self:vertalign(top)
			:zoomto(pane_width, bottombar_height )
			:xy(pane_width/2, 0)
			:diffuse(color("#101519"))
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0.5)
		end
	end,
}

-- centered text for W1
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text=abbreviations[SL.Global.GameMode][1],
	InitCommand=function(self)
		local x = pane_width/2

		self:diffuse( colors[1] )
			:addx(x):addy(7)
			:zoom(0.8)
	end,
}

-- loop from W2 to the worst_window and add judgment text
-- underneath that portion of the histogram
for i=2,num_judgments_available do

	-- early (left) judgment text
	pane[#pane+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text=abbreviations[SL.Global.GameMode][i],
		InitCommand=function(self)
			local window = -1 * GetTimingWindow(i)
			local better_window = -1 * GetTimingWindow(i - 1)

			local x = scale(window, -worst_window, worst_window, 0, pane_width )
			local x_better = scale(better_window, -worst_window, worst_window, 0, pane_width)
			local x_avg = (x+x_better)/2

			self:diffuse( colors[i] )
				:addx(x_avg):addy(7)
				:zoom(0.8)
			-- Hide the text if it's the same as the previous window.
			if abbreviations[SL.Global.GameMode][i] == abbreviations[SL.Global.GameMode][i-1] then
				self:visible(false)
			end
		end,
	}

	-- late (right) judgment text
	pane[#pane+1] = Def.BitmapText{
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text=abbreviations[SL.Global.GameMode][i],
		InitCommand=function(self)
			local window = GetTimingWindow(i)
			local better_window = GetTimingWindow(i - 1)

			local x = scale(window, -worst_window, worst_window, 0, pane_width )
			local x_better = scale(better_window, -worst_window, worst_window, 0, pane_width)
			local x_avg = (x+x_better)/2

			self:diffuse( colors[i] )
				:addx(x_avg):addy(7)
				:zoom(0.8)
			-- Hide the text if it's the same as the previous window.
			if abbreviations[SL.Global.GameMode][i] == abbreviations[SL.Global.GameMode][i-1] then
				self:visible(false)
			end
		end,
	}

end

-- --------------------------------------------------------
-- TOPBAR feat. mean timing error, median, mode, and Ryu☆

-- topbar background quad
pane[#pane+1] = Def.Quad{
	InitCommand=function(self)
		self:vertalign(top)
			:zoomto(pane_width, topbar_height )
			:xy(pane_width/2, -pane_height + topbar_height/2)
			:diffuse(color("#101519"))
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0.5)
		end
	end,
}

-- only bother crunching the numbers and adding extra BitmapText actors if there are
-- valid offset values to analyze; (MISS has no numerical offset and can't be analyzed)
if next(offsets) ~= nil then

	local histogram
	-- don't re-run the calculations if only one player is joined
	-- and we've already run them for a previous pane
	if ComputedData and ComputedData.Histogram then
		histogram = ComputedData.Histogram
	else
		histogram = LoadActor(
				"./Calculations.lua",
				{
					pn,
					offsets,
					worst_window,
					pane_width,
					pane_height,
					colors,
					sum_timing_error,
					avg_timing_error,
					sum_timing_offset,
					avg_offset,
					std_dev,
					max_error
				})
		if ComputedData then ComputedData.Histogram = histogram end
	end

	pane[#pane+1] = histogram
end

-- --------------------------------------------------------
-- Reference lines: dead centre, and the bias.
--
-- Added after the histogram, and therefore drawn over it. These two are not backdrop like
-- the window boundaries above: the whole point of the bias line is to be read AGAINST the
-- bars -- how far the mass of them sits from zero -- and a line hidden behind the tallest
-- bars is hidden exactly where the mass is.

-- the line in the middle indicating where truly flawless timing (0ms offset) is
pane[#pane+1] = Def.Quad{
	InitCommand=function(self)
		self:vertalign(bottom):xy(pane_width/2, 0)
			:zoomto(1, pane_height - (topbar_height+bottombar_height) )
			:diffuse(1,1,1,0.666)
	end,
}

if mean_x ~= nil then
	-- Dashed, so that it reads as an annotation rather than as part of the histogram: it
	-- now sits over the bars, and a second solid vertical line among them would be one
	-- more thing to tell apart from the boundaries at a glance.
	--
	-- Drawn as a column of short quads, because there is no dash style to ask for -- the
	-- engine only draws solid rectangles, so the dashes have to BE the rectangles.
	-- TWEAK: dash and gap length in pixels. Roughly 15 dashes over the body at 5/4.
	local DASH_LEN, DASH_GAP = 5, 4

	local dashes = Def.ActorFrame{
		InitCommand=function(self) self:xy(mean_x, 0) end,
	}

	local y = 0
	while y < body_height do
		local top = y
		local len = math.min(DASH_LEN, body_height - y)

		dashes[#dashes+1] = Def.Quad{
			InitCommand=function(self)
				self:vertalign(bottom):xy(0, -top)
					:zoomto(1, len)
					:diffuse(MEAN_COLOR)
					:diffusealpha(0.9)
			end,
		}

		y = y + DASH_LEN + DASH_GAP
	end

	pane[#pane+1] = dashes
end

local label = {}
label.y = -pane_height+19
label.zoom = 0.7
label.padding = 3

-- Cleanly positioning the labels for "mean timing error", "median", and "mode"
-- can be tricky because some languages use very few characters to express these ideas
-- while other languages use many.  This max_width calculation works for now.
label.max_width = ((pane_width/3)/label.zoom) - ((label.padding/label.zoom)*3)

-- avg_timing_error label
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text=ScreenString("MeanTimingError"),
	InitCommand=function(self)
		self:x(40):y(label.y)
			:zoom(label.zoom):maxwidth(label.max_width)

		if self:GetWidth() > label.max_width then
			self:horizalign(left):x(label.padding)
		end
	end,
}

-- avg_timing_error label
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text=ScreenString("MeanOffset"),
	InitCommand=function(self)
		self:x(40 + (pane_width-80)/3):y(label.y)
			:zoom(label.zoom):maxwidth(label.max_width)

		if self:GetWidth() > label.max_width then
			self:horizalign(left):x(label.padding)
		end
	end,
}

-- std_dev label
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text=ScreenString("StdDev"),
	InitCommand=function(self)
		self:x(40 + (pane_width-80)/3 * 2):y(label.y)
			:zoom(label.zoom):maxwidth(label.max_width)
	end,
}

-- max_error label
pane[#pane+1] = Def.BitmapText{
	Font=ThemePrefs.Get("ThemeFont") .. " Normal",
	Text=ScreenString("MaxError"),
	InitCommand=function(self)
		self:x(pane_width-40):y(label.y)
			:zoom(label.zoom):maxwidth(label.max_width)

		if self:GetWidth() > label.max_width then
			self:horizalign(right):x(pane_width - label.padding)
		end
	end,
}

return pane
