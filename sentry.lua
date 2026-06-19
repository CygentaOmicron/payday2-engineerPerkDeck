-- =====================================================================
--  The Engineer - sentry registration  (hooked onto SentryGunBase)
-- =====================================================================
--  Only job here is to register the player's own sentries so Recall can
--  find them. The refund-on-destruction logic now lives in sentry_death.lua
--  (hooked onto SentryGunDamage), because destruction goes through the
--  damage extension, not SentryGunBase:die/destroy.
--
--  The Dispenser is a neutered sentry (see engineer.lua). While it spawns,
--  EngineerDeck._spawning_dispenser is set; we tag that unit _eng_dispenser
--  and skip it here so it never counts as one of the player's turrets.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

local function safe(fn)
	local ok, err = pcall(fn)
	if not ok then log("[EngineerDeck] sentry register warning: " .. tostring(err)) end
end

local function is_local_owner(self)
	local owner_id = (self.get_owner_id and self:get_owner_id()) or self._owner_id
	local sess = managers.network and managers.network:session()
	local local_id = sess and sess:local_peer() and sess:local_peer():id() or nil
	return owner_id == nil or local_id == nil or owner_id == local_id
end

if SentryGunBase then
	local setup_fn = (SentryGunBase.setup and "setup") or (SentryGunBase.sync_setup and "sync_setup")
	if setup_fn then
		Hooks:PostHook(SentryGunBase, setup_fn, "EngineerDeck_SentrySetup", function(self, ...)
			safe(function()
				-- the Engineer's Dispenser chassis: tag and ignore it
				if EngineerDeck._spawning_dispenser or self._eng_dispenser then
					self._eng_dispenser = true
					return
				end
				if EngineerDeck.is_active and EngineerDeck.is_active(1) and is_local_owner(self) then
					if EngineerDeck.register_sentry then EngineerDeck.register_sentry(self._unit) end
				end
			end)
		end)
	end
end
