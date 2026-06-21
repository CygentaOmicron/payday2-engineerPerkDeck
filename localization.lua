-- =====================================================================
--  The Engineer - localization (inline; no external file)
-- =====================================================================

Hooks:Add("LocalizationManagerPostInit", "EngineerDeck_Localization", function(loc)
	loc:add_localized_strings({
		["eng_title"] = "The Engineer",
		["eng_desc"] = "You don't win fights, your machines do. Set up a Sentry Gun, drop a Dispenser to keep the team fed, and dig in. A defensive deck: the more you invest, the tougher you get, and you take even less damage while standing in your own Dispenser field.\n\n##Equip a Sentry Gun (or Silenced Sentry Gun) as your deployable to get the most from this deck.##",

		["eng_1"] = "Set Up Shop",
		["eng_1_desc"] = "You pack a portable Dispenser instead of a grenade.\n\nReplaces your throwable with the ##Dispenser##: a deployable field that heals and resupplies you and nearby teammates. Recharges on a cooldown.",

		["eng_2"] = "Helmet Popping",
		["eng_2_desc"] = "Increases your headshot damage by ##25%##.\nYou take ##10%## less damage from all sources.",

		["eng_3"] = "Auto-Wrench",
		["eng_3_desc"] = "Your gear looks after itself.\n\nWhen your sentry gun is destroyed, it is ##refunded to your inventory## so you can redeploy it.\nYour sentry guns carry ##100x## their normal ammunition.\nHit a sentry with the ##Monkey Wrench## to fully repair and reload it.\nSpend ##Scrap## - earned from ammo pickups, ammo bags and your Dispenser - to ##upgrade## a sentry you hit (Lv1 to Lv3), raising its damage, fire rate and ammo. A sentry's level and your scrap show when you look at it.",

		["eng_4"] = "Blending In",
		["eng_4_desc"] = "You gain ##+1## concealment.\nWhen wearing armor, your movement speed is ##15%## less affected.\nYou gain ##45%## more experience when you complete days and jobs.\nYour damage resistance rises to ##18%##.",

		["eng_5"] = "Dispenser Mk.II",
		["eng_5_desc"] = "An upgraded support module.\n\nYour ##Dispenser## field covers a larger area and lasts longer.",

		["eng_6"] = "Scavenger",
		["eng_6_desc"] = "Increases your ammo pickup to ##135%## of the normal rate.\nYour damage resistance rises to ##25%##.",

		["eng_7"] = "Frontier Justice",
		["eng_7_desc"] = "Your sentries' work pays off.\n\nWhen one of your sentries is destroyed or recalled, you gain refilled ammo and a short damage surge based on how many kills it scored.",

		["eng_8"] = "Hard Wired",
		["eng_8_desc"] = "You do ##5%## more damage. Does not apply to melee, throwables, grenade launchers or the HRL-7.\nIncreases your doctor bag interaction speed by ##20%##.\nYour damage resistance rises to ##30%##.",

		["eng_9"] = "Move Out!",
		["eng_9_desc"] = "A good Engineer never stays put.\n\nYou can ##recall## a deployed sentry into your inventory and redeploy it anywhere with no cooldown.",

		["bm_ability_eng_dispenser"] = "Dispenser",
		["bm_ability_eng_dispenser_desc"] = "A deployable support field that heals and resupplies nearby teammates. Recharges on a cooldown. While standing in it you also take less damage.",
		-- shown as the throwable's "lock" reason: it's an ability granted by the deck, not a purchasable throwable
		["bm_menu_skill_locked_eng_dispenser"] = "Granted by The Engineer perk deck.",

		-- Engineer's Sentry deployable (custom loadout item, deck-gated)
		["bm_equipment_eng_sentry_gun"] = "Engineer's Sentry",
		["bm_equipment_eng_sentry_gun_desc"] = "A reinforced sentry gun tuned by the Engineer, with its own stats. Only available while running The Engineer perk deck.",

		-- sentry hover prompt: adds turret Level and your Scrap alongside ammo %
		["hud_interact_pickup_sentry_gun"] = "Pick Up Sentry  ##Lv $ENG_LEVEL$##   Ammo $AMMO_LEFT$%   Scrap $ENG_SCRAP$%",
	})
end)
