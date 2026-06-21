-- =====================================================================
--  The Engineer - deck-swap transitions  (hooked onto SkillTreeManager)
-- =====================================================================
--  Drives the deck's two deck-gated loadout items when the current
--  specialization changes:
--
--   ENTER the Engineer deck:
--     - grant the Dispenser throwable and restore your last saved throwable
--       pick for this deck (defaults to the Dispenser the first time). You can
--       still swap it for anything; the swap is remembered (grenade.lua).
--
--   LEAVE the Engineer deck:
--     - revert the deployable from the Engineer's Sentry back to the vanilla
--       sentry (it's a real saved deployable, so it would otherwise persist).
--     - re-lock the Dispenser throwable, reverting it to a normal grenade if
--       it was still equipped (mirrors how vanilla drops deck-bound gear). This
--       runs with the deck already switched away, so it does NOT overwrite the
--       saved Engineer throwable pick.
--
--  Grant/restore/persist helpers live in grenade.lua; deployable revert here.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

if SkillTreeManager and SkillTreeManager.set_current_specialization then
	Hooks:PostHook(SkillTreeManager, "set_current_specialization", "EngineerDeck_DeckSwapTransition", function(self, ...)
		pcall(function()
			local bm = managers.blackmarket
			local on_engineer = EngineerDeck.is_current_deck and EngineerDeck.is_current_deck()

			if on_engineer then
				-- entered the Engineer deck: grant + restore your saved throwable pick
				if EngineerDeck.restore_deck_throwable then
					EngineerDeck.restore_deck_throwable()
				elseif EngineerDeck.unlock_dispenser then
					-- fallback if grenade.lua somehow isn't loaded yet
					EngineerDeck.unlock_dispenser(true)
					if EngineerDeck.default_equip_dispenser then EngineerDeck.default_equip_dispenser() end
				end
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
