-- =====================================================================
--  The Engineer - sentry combat buff  (hooked onto WeaponTweakData)
-- =====================================================================
--  Sentries are weak/slow by default (DAMAGE 3, auto.fire_rate 0.15).
--  Moderate bump: ~2x damage and a faster cadence. Tuned to be careful -
--  adjust DMG_MUL / FIRE_RATE below to taste.
--
--  NOTE: tweak_data is global, so this affects every sentry when YOU host
--  (it is not gated to the deck). Acceptable for a host-side personal mod;
--  say the word if you'd rather gate it per-sentry.
-- =====================================================================

-- local DMG_MUL   = 2.0     -- 3 -> 6
-- local FIRE_RATE = 0.10    -- from 0.15 (lower = faster)
-- local DMG_MUL   = 0.5     -- 
-- local FIRE_RATE = 0.02    -- from 0.15 (lower = faster)
local DMG_MUL   = 1.0    -- 
local FIRE_RATE = 0.15    -- from 0.15 (lower = faster)

if WeaponTweakData then
	Hooks:PostHook(WeaponTweakData, "init", "EngineerDeck_SentryBuff", function(self, ...)
		pcall(function()
			local sg = self.sentry_gun
			if not sg then return end
			sg.DAMAGE = (sg.DAMAGE or 3) * DMG_MUL
			if sg.auto then sg.auto.fire_rate = FIRE_RATE end
		end)
	end)
end
