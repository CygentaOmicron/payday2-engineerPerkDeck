-- =====================================================================
--  The Engineer - refund on destruction  (hooked onto SentryGunDamage)
-- =====================================================================
--  When a sentry's HP hits 0 it goes through SentryGunDamage:_apply_damage,
--  which sets self._dead. We do two things there:
--    1. Play the TF2 "explode" cue for our TF2-skinned turrets (local only,
--       once), and mark the base dead so the idle scan loop stops immediately
--       (belt-and-suspenders: on_death also disables the base update tick).
--    2. Refund the charge (Auto-Wrench, card 3). This path is ONLY reached by
--       actual damage death - pickup and recall do not call it - so there is no
--       double refund. A per-unit flag (_eng_refunded) guards repeat calls.
--
--  The Dispenser chassis (_eng_dispenser) is excluded: its death stops the
--  aura (handled in engineer.lua's tick), gets no explode cue, and must NOT
--  refund a sentry charge.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

if SentryGunDamage and SentryGunDamage._apply_damage then
	Hooks:PostHook(SentryGunDamage, "_apply_damage", "EngineerDeck_SentryRefund", function(self, ...)
		pcall(function()
			if not self._dead then return end
			local base = self._unit and self._unit:base()
			-- ignore the Dispenser chassis - no explode, no refund for it
			if base and base._eng_dispenser then return end

			-- stop the idle scan loop right away
			if base then base._eng_dead = true end

			-- TF2 explode cue (local TF2 turrets only, once). Plays regardless of
			-- tier - any TF2-skinned turret that dies booms. (Explode volume
			-- tunable: keep in sync with EXPLODE_VOLUME in sentry_ammo.lua.)
			if base and base._eng_tf_skinned and not self._eng_explode_played then
				self._eng_explode_played = true
				if EngineerDeck.play_sentry_sound and EngineerDeck.SND then
					EngineerDeck.play_sentry_sound(self._unit, EngineerDeck.SND.EXPLODE, 0.85, nil, 9000)
				end
			end

			-- --- charge refund (tier 3, local owner) -------------------------
			if self._eng_refunded then return end
			self._eng_refunded = true

			if not (EngineerDeck.is_active and EngineerDeck.is_active(3)) then return end

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
