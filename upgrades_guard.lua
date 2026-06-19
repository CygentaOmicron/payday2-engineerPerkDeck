-- =====================================================================
--  The Engineer - make grenade-unlock lookups safe for our ability grenade
-- =====================================================================
--  BlackMarketManager:_setup_grenades calls UpgradesManager:get_value(id, default)
--  for every projectile. Real grenades have an unlock definition; our custom
--  eng_dispenser doesn't, so the stock lookup indexes nil and crashes.
--  We short-circuit just our id, returning (is_default = false, level = 0),
--  which marks it as a skill/deck-based grenade (no purchase needed).
-- =====================================================================

if UpgradesManager and UpgradesManager.get_value then
	local orig_get_value = UpgradesManager.get_value
	function UpgradesManager:get_value(upgrade, ...)
		if upgrade == "eng_dispenser" then
			return false, 0
		end
		return orig_get_value(self, upgrade, ...)
	end
end
