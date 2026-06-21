-- =====================================================================
--  The Engineer - Dispenser throwable as a deck-granted, SWAPPABLE ability
--  (hooked onto BlackMarketManager)
-- =====================================================================
--  Previously we force-returned eng_dispenser from equipped_grenade /
--  equipped_projectile, which hijacked the throwable slot - you could never
--  pick a different throwable, and the menu couldn't treat it as an owned
--  grenade (so it showed locked). Vanilla ability decks (Stoic flask, Kingpin
--  injector, Sicario ECM) instead GRANT their ability throwable as a normal,
--  unlocked, swappable grenade and auto-equip it by default.
--
--  So we do the same: while the Engineer deck is equipped, eng_dispenser is
--  unlocked (selectable) and equipped by default; you can swap it for anything
--  and swap back. No getter override - when eng_dispenser is the equipped
--  grenade, the ability system + dispenser_throw.lua handle it normally.
--  deck_swap.lua drives grant-on-enter / revoke-on-leave.
--
--  Save note: like the Engineer's Sentry, the unlocked flag lives in the
--  blackmarket save; we re-lock it when you leave the deck to keep things tidy.
-- =====================================================================

EngineerDeck = EngineerDeck or {}
EngineerDeck.dispenser_id = "eng_dispenser"

local FALLBACK_GRENADE = "frag"

local function grenades_inv()
	return Global and Global.blackmarket_manager and Global.blackmarket_manager.grenades
end

-- ensure an inventory entry exists so the grenade can be unlocked/equipped
local function ensure_entry()
	local g = grenades_inv()
	if not g then return nil end
	if not g.eng_dispenser then
		g.eng_dispenser = { unlocked = false, equipped = false, amount = 1, skill_based = false, level = 0 }
	end
	return g.eng_dispenser
end

-- unlock (make selectable) or re-lock (and revert if currently equipped)
function EngineerDeck.unlock_dispenser(on)
	pcall(function()
		local bm = managers.blackmarket
		local entry = ensure_entry()
		if not entry then return end
		if on then
			entry.unlocked = true
			entry.amount = entry.amount or 1
			-- official unlock API (handles menu bookkeeping); the flag above is the fallback
			if bm and bm.on_aquired_grenade then pcall(function() bm:on_aquired_grenade("eng_dispenser") end) end
		else
			-- revert to a normal grenade if the Dispenser is still equipped
			if bm and bm.equipped_grenade and bm.equip_grenade and bm:equipped_grenade() == "eng_dispenser" then
				bm:equip_grenade(FALLBACK_GRENADE)
			end
			-- re-lock via the flag only. (We deliberately DON'T call on_unaquired_grenade:
			-- that vanilla fn indexes data our lightweight entry doesn't carry and errors.)
			entry.unlocked = false
		end
	end)
end

-- make it the equipped throwable by default (called once on entering the deck)
function EngineerDeck.default_equip_dispenser()
	pcall(function()
		local bm = managers.blackmarket
		if bm and bm.equip_grenade then bm:equip_grenade("eng_dispenser") end
	end)
end

-- load-time sync: if the Engineer deck is already current when the blackmarket
-- finishes setting up, make sure the Dispenser is unlocked/selectable (we don't
-- force-equip here, so a saved choice of another throwable is respected)
if BlackMarketManager and BlackMarketManager.aquire_default_weapons then
	Hooks:PostHook(BlackMarketManager, "aquire_default_weapons", "EngineerDeck_DispenserGrenadeSetup", function(self, ...)
		pcall(function()
			if EngineerDeck.is_current_deck and EngineerDeck.is_current_deck() then
				EngineerDeck.unlock_dispenser(true)
			end
		end)
	end)
end
