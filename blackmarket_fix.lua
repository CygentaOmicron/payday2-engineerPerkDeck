-- =====================================================================
--  The Engineer - blackmarket display safety net (BlackMarketManager)
-- =====================================================================
--  The vanilla loadout-overview builder (player_loadout_data, ~line 3863)
--  indexes display data keyed by the deployable id that only exists for the
--  built-in deployables (e.g. a menu icon texture). Our custom eng_sentry_gun
--  has no such entry, so the builder errors and the inventory screen crashes.
--
--  For the duration of this display call ONLY, we mask eng_sentry_gun as the
--  vanilla sentry by overriding the equipped_deployable METHOD (the builder
--  reads the deployable through the method, not a raw field). The builder then
--  never sees our id, so it never errors - no log, no crash. The overview slot
--  shows a generic sentry icon/name; the selection screen still shows
--  "Engineer's Sentry". Gameplay is unaffected (this function is display-only).
--
--  A proper custom overview icon would need a real menu texture added for the
--  id (BeardLib AddFile of a .texture) - a later polish step.
-- =====================================================================

if BlackMarketManager and BlackMarketManager.player_loadout_data then
	local orig = BlackMarketManager.player_loadout_data
	function BlackMarketManager:player_loadout_data(...)
		local orig_ed = self.equipped_deployable
		self.equipped_deployable = function(s, slot)
			local v = orig_ed(s, slot)
			return v == "eng_sentry_gun" and "sentry_gun" or v
		end

		local ok, res = pcall(orig, self, ...)

		self.equipped_deployable = nil   -- restore class method
		return ok and res or nil
	end
end
