-- =====================================================================
--  The Engineer - sentry hover readout  (hooked onto interactionext)
-- =====================================================================
--  The prompt you see when looking at your own sentry is the SentryGun
--  pickup interaction, whose text the game builds via _add_string_macros
--  (it fills $AMMO_LEFT$). We add $ENG_LEVEL$ and $ENG_SCRAP$ macros, and
--  localization.lua rewrites that prompt's string to display them. So the
--  same menu now reads the turret's level and your current scrap.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

if SentryGunInteractionExt and SentryGunInteractionExt._add_string_macros then
	Hooks:PostHook(SentryGunInteractionExt, "_add_string_macros", "EngineerDeck_SentryMacros", function(self, macros)
		pcall(function()
			macros.ENG_LEVEL = (EngineerDeck.get_sentry_level and EngineerDeck.get_sentry_level(self._unit)) or 1
			macros.ENG_SCRAP = (EngineerDeck.scrap_percent and EngineerDeck.scrap_percent()) or 0
		end)
	end)
end
