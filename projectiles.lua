-- =====================================================================
--  The Engineer - Dispenser ability throwable
-- =====================================================================
--  Modelled on the base game's perk-deck ability grenades (e.g. the Kingpin
--  injector): no thrown unit, an `ability` field, cooldown-based. This routes
--  through BlackMarketManager:_setup_grenades' ABILITY branch, which skips the
--  managers.upgrades:get_value() lookup that crashed when we cloned frag (a
--  normal grenade needs a matching upgrade definition; an ability one does not).
--
--  Because it's an ability (activated, not physically thrown), the heal field
--  is triggered on activation - test keybind works now; activation hook next.
--  clbk_impact (dispenser_impact.lua) stays inert for this form.
-- =====================================================================

local orig_init = BlackMarketTweakData.init
function BlackMarketTweakData:init(...)
	orig_init(self, ...)

	EngineerDeck = EngineerDeck or {}
	EngineerDeck.dispenser_id = "eng_dispenser"

	self.projectiles = self.projectiles or {}
	self.projectiles.eng_dispenser = {
		name_id = "bm_ability_eng_dispenser",
		desc_id = "bm_ability_eng_dispenser_desc",
		ability = "eng_dispenser",      -- routes through the safe ability branch
		ignore_statistics = true,
		icon = "frag",                  -- placeholder icon (Tier 3: custom)
		max_amount = 1,
		base_cooldown = 30,
		sounds = {
			activate = "perkdeck_activate",
			cooldown = "perkdeck_cooldown_over",
		},
	}
end