-- =====================================================================
--  The Engineer - deck-swap transitions  (hooked onto SkillTreeManager)
-- =====================================================================
--  Drives the deck's two deck-gated loadout items when the current
--  specialization changes:
--
--   ENTER the Engineer deck:
--     - grant + default-equip the Dispenser throwable (eng_dispenser), so it's
--       the default but you can still swap it for any other throwable.
--
--   LEAVE the Engineer deck:
--     - revert the deployable from the Engineer's Sentry back to the vanilla
--       sentry (it's a real saved deployable, so it would otherwise persist).
--     - re-lock the Dispenser throwable, reverting it to a normal grenade if
--       it was still equipped (mirrors how vanilla drops deck-bound gear).
--
--  Grant/revoke helpers live in grenade.lua; deployable revert is done here.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

if SkillTreeManager and SkillTreeManager.set_current_specialization then
	Hooks:PostHook(SkillTreeManager, "set_current_specialization", "EngineerDeck_DeckSwapTransition", function(self, ...)
		pcall(function()
			local bm = managers.blackmarket
			local on_engineer = EngineerDeck.is_current_deck and EngineerDeck.is_current_deck()

			if on_engineer then
				-- entered the Engineer deck: hand over the Dispenser as the default throwable
				if EngineerDeck.unlock_dispenser then EngineerDeck.unlock_dispenser(true) end
				if EngineerDeck.default_equip_dispenser then EngineerDeck.default_equip_dispenser() end
				return
			end

			-- left the Engineer deck: drop both deck-bound items
			-- 1) deployable: Engineer's Sentry -> vanilla sentry
			if bm and bm.equipped_deployable and bm:equipped_deployable() == "eng_sentry_gun" and bm.equip_deployable then
				bm:equip_deployable({ name = "sentry_gun", target_slot = 1 })
			end
			-- 2) throwable: re-lock the Dispenser (reverts it if still equipped)
			if EngineerDeck.unlock_dispenser then EngineerDeck.unlock_dispenser(false) end
		end)
	end)
end
