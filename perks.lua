-- =====================================================================
--  The Engineer - custom sentry upgrade values/definitions
-- =====================================================================
--  CONFIRMED against sentrygunbase.lua: the sentry reads its stats at spawn
--  via player_skill.skill_data("sentry_gun", <key>, default, owner). Valid
--  keys: extra_ammo_multiplier, armor_multiplier(/2), spread_multiplier,
--  rot_speed_multiplier, and the booleans ap_bullets / shield.
--  There is NO sentry damage multiplier - damage only changes via AP rounds.
--
--  We APPEND to the existing value arrays (never overwrite) so base-game
--  Technician skills keep working, and store each index in EngineerDeck.
-- =====================================================================

local orig_init = UpgradesTweakData.init
function UpgradesTweakData:init(tweak_data)
	orig_init(self, tweak_data)

	EngineerDeck = EngineerDeck or {}

	local function add(category, key, value)
		self.values[category] = self.values[category] or {}
		local arr = self.values[category][key]
		if not arr then arr = {} self.values[category][key] = arr end
		arr[#arr + 1] = value
		return #arr
	end

	-- { def_name, top_category, value_category, value_key, magnitude, loc_id }
	local CFG = {
		{ "eng_sentry_ammo",   "feature", "sentry_gun", "extra_ammo_multiplier", 100,  "menu_eng_sentry_ammo" },   -- 100x ammo
		{ "eng_sentry_armor",  "feature", "sentry_gun", "armor_multiplier",      1.60, "menu_eng_sentry_armor" },
		{ "eng_sentry_acc",    "feature", "sentry_gun", "spread_multiplier",     0.50, "menu_eng_sentry_acc" },    -- lower = tighter
		{ "eng_sentry_rot",    "feature", "sentry_gun", "rot_speed_multiplier",  1.50, "menu_eng_sentry_rot" },
		{ "eng_sentry_shield", "feature", "sentry_gun", "shield",                1,    "menu_eng_sentry_shield" }, -- boolean (has_skill)
		{ "eng_sentry_ap",     "feature", "sentry_gun", "ap_bullets",            1,    "menu_eng_sentry_ap" },     -- boolean (has_skill)
		-- read only by our own dispenser code, safe to invent
		{ "eng_disp_resist",   "feature", "player",     "eng_dispenser_damage_resist", 0.25, "menu_eng_disp_resist" },
	}

	for _, c in ipairs(CFG) do
		local def_name, top_cat, val_cat, val_key, mag, loc_id = c[1], c[2], c[3], c[4], c[5], c[6]
		local index = add(val_cat, val_key, mag)
		EngineerDeck[def_name] = index
		self.definitions[def_name] = {
			category = top_cat,
			name_id = loc_id,
			upgrade = { category = val_cat, upgrade = val_key, value = index },
		}
	end
end
