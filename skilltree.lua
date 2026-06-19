-- =====================================================================
--  The Engineer - perk deck layout (9 cards)
-- =====================================================================
--  All of the deck's sentry/engineer effects are now CODE-DRIVEN (dispenser,
--  refund, surge, recall, ammo), gated by deck + tier - none of them ride
--  the sentry upgrade-value system, which crashed when fed custom values
--  (skill_data returned nil -> sentrygunbase:setup arithmetic on nil).
--
--  Odd cards therefore carry no upgrade entries; even cards keep the proven
--  base-game "mutual" perks.
-- =====================================================================

local orig_init = SkillTreeTweakData.init
function SkillTreeTweakData:init(tweak_data)
	orig_init(self, tweak_data)

	EngineerDeck = EngineerDeck or {}

	local card2 = { upgrades = { "weapon_passive_headshot_damage_multiplier" },
		cost = 300, icon_xy = {1, 0}, name_id = "eng_2", desc_id = "eng_2_desc" }
	local card4 = { upgrades = { "passive_player_xp_multiplier",
		"player_passive_suspicion_bonus", "player_passive_armor_movement_penalty_multiplier" },
		cost = 600, icon_xy = {3, 0}, name_id = "eng_4", desc_id = "eng_4_desc" }
	local card6 = { upgrades = { "player_pick_up_ammo_multiplier" },
		cost = 1600, icon_xy = {5, 0}, name_id = "eng_6", desc_id = "eng_6_desc" }
	local card8 = { upgrades = { "weapon_passive_damage_multiplier",
		"passive_doctor_bag_interaction_speed_multiplier" },
		cost = 3200, icon_xy = {7, 0}, name_id = "eng_8", desc_id = "eng_8_desc" }

	table.insert(self.specializations, {
		name_id = "eng_title",
		desc_id = "eng_desc",
		{ upgrades = {}, cost = 200,  icon_xy = {1, 2}, name_id = "eng_1", desc_id = "eng_1_desc" },  -- Dispenser (code)
		card2,
		{ upgrades = {}, cost = 400,  icon_xy = {5, 5}, name_id = "eng_3", desc_id = "eng_3_desc" },  -- Refund (code)
		card4,
		{ upgrades = {}, cost = 1000, icon_xy = {1, 6}, name_id = "eng_5", desc_id = "eng_5_desc" },  -- Dispenser Mk.II + ammo (code)
		card6,
		{ upgrades = {}, cost = 2400, icon_xy = {0, 4}, name_id = "eng_7", desc_id = "eng_7_desc" },  -- Frontier Justice (code)
		card8,
		{ upgrades = {}, cost = 4000, icon_xy = {1, 4}, name_id = "eng_9", desc_id = "eng_9_desc" },  -- Move Out (code)
	})

	EngineerDeck.spec_index = #self.specializations
end
