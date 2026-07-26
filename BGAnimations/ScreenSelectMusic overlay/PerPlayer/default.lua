local t = Def.ActorFrame{
	Name="PerPlayer"
}

-- Always add these elements for both players, even if only one is joined right now
-- If the other player suddenly latejoins, we can't dynamically add more actors to the screen
-- We can only unhide hidden actors that were there all along
for player in ivalues( PlayerNumber ) do
	t[#t+1] = LoadActor("./DensityGraph.lua", player)
	-- AuthorCredit, Description, and ChartName associated with the current stepchart
	t[#t+1] = LoadActor("./StepArtist.lua", player)
	t[#t+1] = LoadActor("./FolderStats.lua", player)
	t[#t+1] = LoadActor("./ScoreBox.lua", player)
end

-- The per-player difficulty cursor used to be loaded here. It lives inside the
-- difficulty picker's own frame now (StepsDisplayList/Grid.lua) because it became a
-- highlight ring drawn around the selected chip: it has to land between that card's
-- opaque background and the chips themselves, and everything in this file draws
-- underneath the whole StepsDisplayList.

return t
