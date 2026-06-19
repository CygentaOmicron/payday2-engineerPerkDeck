-- =====================================================================
--  The Engineer - "Engineer's Sentry" deployable: blackmarket entry
--  (hooked onto BlackMarketTweakData)
-- =====================================================================
--  Adds the loadout entry (name/desc) so the deployable can be shown and
--  selected in the blackmarket. Availability is gated to the Engineer deck
--  via PlayerManager:availible_equipment (see engineer.lua).
-- =====================================================================

if BlackMarketTweakData then
	Hooks:PostHook(BlackMarketTweakData, "_init_deployables", "EngineerDeck_EngSentryDeployable", function(self, ...)
		pcall(function()
			self.deployables = self.deployables or {}
			self.deployables.eng_sentry_gun = {
				name_id = "bm_equipment_eng_sentry_gun",
				desc_id = "bm_equipment_eng_sentry_gun_desc",
			}
		end)
	end)
end
