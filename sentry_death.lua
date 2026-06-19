-- =====================================================================
--  The Engineer - refund on destruction  (hooked onto SentryGunDamage)
-- =====================================================================
--  When a sentry's HP hits 0 it goes through SentryGunDamage:_apply_damage,
--  which sets self._dead. We refund the charge there (Auto-Wrench, card 3).
--  This path is ONLY reached by actual damage death - pickup and recall do
--  not call it - so there is no double refund.
--  A per-unit flag (_eng_refunded) guards against repeat calls.
--
--  The Dispenser chassis (_eng_dispenser) is excluded: its death stops the
--  aura (handled in engineer.lua's tick) and must NOT refund a sentry charge.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

if SentryGunDamage and SentryGunDamage._apply_damage then
	Hooks:PostHook(SentryGunDamage, "_apply_damage", "EngineerDeck_SentryRefund", function(self, ...)
		pcall(function()
			if not self._dead then return end
			-- ignore the Dispenser chassis - no refund for it
			if self._unit and self._unit:base() and self._unit:base()._eng_dispenser then return end
			if self._eng_refunded then return end
			self._eng_refunded = true

			if not (EngineerDeck.is_active and EngineerDeck.is_active(3)) then return end

			local base = self._unit and self._unit:base()
			local owner_id = base and ((base.get_owner_id and base:get_owner_id()) or base._owner_id)
			local sess = managers.network and managers.network:session()
			local local_id = sess and sess:local_peer() and sess:local_peer():id()
			if owner_id ~= nil and local_id ~= nil and owner_id ~= local_id then return end

			local kills = base and ((base.get_kills and base:get_kills()) or base._kills) or 0
			if EngineerDeck.forget_sentry then EngineerDeck.forget_sentry(self._unit) end
			if EngineerDeck.on_sentry_lost then EngineerDeck.on_sentry_lost(kills) end
			if EngineerDeck.refund_deployable then EngineerDeck.refund_deployable() end
		end)
	end)
end
