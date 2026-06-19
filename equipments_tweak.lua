-- =====================================================================
--  The Engineer - "Engineer's Sentry" deployable: equipment definition
--  (hooked onto EquipmentsTweakData)
-- =====================================================================
--  STAGE 1: just make the item EXIST. Clones the vanilla sentry_gun equipment
--  as eng_sentry_gun, reusing the normal sentry unit (sentry_id_strings[1]) so
--  no new asset is needed. use_function_name stays "use_sentry_gun", so for now
--  it deploys exactly like a normal sentry. Unique values + a deck-gated deploy
--  that tags the unit come in a later stage.
-- =====================================================================

if EquipmentsTweakData then
	Hooks:PostHook(EquipmentsTweakData, "init", "EngineerDeck_EngSentryEquip", function(self, ...)
		pcall(function()
			if self.eng_sentry_gun or not self.sentry_gun then return end
			local clone = deep_clone(self.sentry_gun)
			clone.unit = 1                    -- sentry_id_strings index (normal sentry unit)
			clone.icon = "equipment_sentry"   -- reuse the vanilla sentry icon (no custom texture)
			self.eng_sentry_gun = clone
		end)
	end)
end
