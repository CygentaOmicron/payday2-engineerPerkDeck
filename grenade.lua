-- The Engineer - grant the Dispenser throwable while the deck is active.
-- Hooked onto BlackMarketManager so the class exists when we override.
-- We override BOTH equipped_grenade (cooldown/HUD lookups) and
-- equipped_projectile (the throw/ability router in PlayerStandard), so the
-- game's ability system manages the Dispenser - including its cooldown.
EngineerDeck = EngineerDeck or {}

local function dispenser_active()
	return EngineerDeck.is_active and EngineerDeck.is_active(1) and EngineerDeck.dispenser_id
end

if BlackMarketManager and BlackMarketManager.equipped_grenade then
	local orig = BlackMarketManager.equipped_grenade
	function BlackMarketManager:equipped_grenade()
		if dispenser_active() then return EngineerDeck.dispenser_id, 1 end
		return orig(self)
	end
end

if BlackMarketManager and BlackMarketManager.equipped_projectile then
	local orig = BlackMarketManager.equipped_projectile
	function BlackMarketManager:equipped_projectile()
		if dispenser_active() then return EngineerDeck.dispenser_id end
		return orig(self)
	end
end
