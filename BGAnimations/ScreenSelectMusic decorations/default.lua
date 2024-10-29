local t = LoadFallbackB();

if not GAMESTATE:IsCourseMode() and not GAMESTATE:IsEventMode() then
	t[#t+1] = StandardDecorationFromFileOptional("StageDisplay","StageDisplay");
end

return t
