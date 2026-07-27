-- Choosing WHICH rows of a long leaderboard a short box should show.
--
-- A leaderboard is routinely longer than the box drawing it: the machine profile keeps ten
-- scores per chart, and GrooveStats returns as many as it is asked for. Taking the first N
-- throws away precisely the rows a player looks for -- their own, and their rivals' -- and
-- keeps a run of strangers instead.
--
-- So the box gets a selection rather than a prefix: the leader, the player and up to three
-- rivals are kept whatever their rank, the slots left over go to the next best rows, and
-- the result is put back in rank order so it still reads as a leaderboard.
--
-- `entries` must already be in rank order, best first, and each entry may carry .isSelf
-- and .isRival. Entry 1 is taken to be the leader: if the source returned a window that
-- does not begin at rank 1 then there is no rank 1 to keep, and the best row it did return
-- is the closest thing to it.
--
-- Returns a new array of at most `max` entries. The entries themselves are not copied.

-- GrooveStats allows three.
local MAX_RIVALS = 3

SelectLeaderboardRows = function(entries, max)
	if #entries <= max then return entries end

	local taken = {}
	local keep = {}

	local function pin(i)
		if not taken[i] and #keep < max then
			taken[i] = true
			keep[#keep+1] = i
		end
	end

	-- Pinned in priority order, so a box too small to hold all of them still keeps the
	-- leader, then the player, then as many rivals as fit.
	pin(1)

	for i, e in ipairs(entries) do
		-- the player's best row only; a board can hold several of their scores
		if e.isSelf then pin(i); break end
	end

	local rivals = 0
	for i, e in ipairs(entries) do
		if e.isRival and rivals < MAX_RIVALS then
			pin(i)
			rivals = rivals + 1
		end
	end

	-- fill what remains from the top of the board
	for i = 1, #entries do pin(i) end

	table.sort(keep)

	local out = {}
	for _, i in ipairs(keep) do out[#out+1] = entries[i] end
	return out
end
