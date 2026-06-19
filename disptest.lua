-- Keybind: drop a Dispenser field at your feet. For testing the heal field
-- independently of the throwable plumbing.
pcall(function()
	local u = managers.player and managers.player:player_unit()
	if u and EngineerDeck and EngineerDeck.deploy_dispenser then
		EngineerDeck.deploy_dispenser(u:position())
	end
end)
