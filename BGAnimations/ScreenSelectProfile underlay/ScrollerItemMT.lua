-- the metatable for an item in ScreenSelectProfile's sick_wheel scroller
-- for the scrollers in ScreenSelectProfile, this is each profile's DisplayName preceded by
-- a small square in that profile's own Simply Love color

-- TWEAK: the color swatch. SWATCH is the square's side in px, GAP the space between it and
-- the name. NAME_MAXWIDTH is the text's own cap and is used twice -- once to set it, once
-- to measure against it -- so the two cannot drift apart.
local SWATCH = 9
local SWATCH_GAP = 5
local NAME_MAXWIDTH = 115

return {
	__index = {
		create_actors = function(self, name)
			self.name=name

			local af = Def.ActorFrame{
				Name=name,
				InitCommand=function(subself)
					self.container = subself
					subself:diffusealpha(0):visible(false)
				end,
				OnCommand=function(subself) subself:sleep(0.2):queuecommand("Appear") end,
				AppearCommand=function(subself) subself:visible(true):linear(0.15):diffusealpha(1) end,
			}

			local txt = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
				InitCommand=function(subself)
					self.bmt = subself
					subself:maxwidth(NAME_MAXWIDTH):MaskDest():shadowlength(0.5)
				end,
			}

			if ThemePrefs.Get("RainbowMode") then
				txt.GainFocusCommand=function(subself) subself:diffusealpha(1) end
				txt.LoseFocusCommand=function(subself) subself:diffusealpha(0.8) end
			end

			af[#af+1] = txt

			-- The profile's own color, so a player can find their profile by color rather
			-- than by reading down the list.
			--
			-- MaskDest() is not optional here. PlayerFrame.lua parks two MaskSource() quads
			-- above and below this list to clip the names that scroll out of the band, and
			-- an unmasked actor would carry on drawing straight past them.
			af[#af+1] = Def.Quad{
				InitCommand=function(subself)
					self.swatch = subself
					subself:setsize(SWATCH, SWATCH):MaskDest():visible(false)
				end,
			}

			return af
		end,
		transform = function(self, item_index, num_items, has_focus)
			self.container:finishtweening()

			if item_index <= 1 or item_index >= num_items then
				self.container:diffusealpha(0)
			else
				self.container:diffusealpha(1)
			end

			if has_focus then
				self.bmt:playcommand("GainFocus")
			else
				self.bmt:playcommand("LoseFocus")
			end

			self.container:linear(0.15):y(35 * item_index)
		end,
		set = function(self, info)
			if not info then self.bmt:settext(""); self.swatch:visible(false); return end
			self.info = info
			self.bmt:settext(info.displayname or "")

			-- Hidden for [GUEST] and for the empty padding entries, which carry no color,
			-- and for a profile that has never saved one -- see ProfileColorIndex in
			-- PlayerProfileData.lua.
			if info.colorindex == nil then
				self.swatch:visible(false)
				return
			end

			self.swatch:visible(true):diffuse( GetHexColor(info.colorindex) )

			-- The name is centred, so the swatch hangs off its measured left edge rather
			-- than sitting at a fixed x, where a short name would leave it floating away on
			-- its own.
			--
			-- Clamped to NAME_MAXWIDTH because GetZoomedWidth reports the text's NATURAL
			-- width and knows nothing about maxwidth: a name long enough to be squeezed
			-- would otherwise measure wider than it draws and push the swatch off-screen.
			local w = math.min(self.bmt:GetZoomedWidth(), NAME_MAXWIDTH)
			self.swatch:x( -w/2 - SWATCH_GAP - SWATCH/2 )
		end
	}
}