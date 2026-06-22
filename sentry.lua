-- =====================================================================
--  The Engineer - sentry registration  (hooked onto SentryGunBase)
-- =====================================================================
--  Jobs here:
--   1. Register the player's own sentries so Recall can find them. The
--      refund-on-destruction logic lives in sentry_death.lua (hooked onto
--      SentryGunDamage), because destruction goes through the damage ext.
--   2. Apply the TF2 sentry reskin to the local player's own sentries:
--      our combined unit (loaded via BeardLib AddFiles -> main.xml) carries
--      both the vanilla meshes (visible by default) and the tf_* meshes
--      (hidden by default). Here we locally hide the vanilla visible set
--      and show the tf_* set, so only THIS player's Engineer sentries look
--      like TF2 turrets. Networked unit name is unchanged, so non-modded
--      peers still draw a vanilla sentry. (MP peer broadcast: TODO.)
--   3. TF2 sound events: play the "deploy finished" cue when a TF2 sentry
--      spawns, and drive the idle SCAN loop every frame via SentryGunBase
--      :update (the base ext's update is enabled in setup, disabled on death,
--      so this ticks exactly while the turret is live). The actual audio +
--      gating live in sentry_ammo.lua (EngineerDeck.play_sentry_sound /
--      sentry_idle_scan); the fire / spot / empty / explode cues are wired at
--      their own triggers (sentry_ammo.lua / sentry_death.lua).
--
--  The Dispenser is a neutered sentry (see engineer.lua). While it spawns,
--  EngineerDeck._spawning_dispenser is set; we tag that unit _eng_dispenser
--  and skip it here so it never counts as one of the player's turrets (and so
--  it gets no skin, no deploy cue and no idle scan).
--
--  LASER: TF2 sentries have no laser sight, so we don't show it at all. The
--  emitter MESH is handled here (g_laser stays hidden, tf_g_laser is never
--  shown). The visible BEAM is a separate spawned unit the engine toggles via
--  SentryGunWeapon:set_laser_enabled - that's forced off in sentry_ammo.lua.
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

-- --- TF2 reskin ------------------------------------------------------
-- Vanilla objects that show on a default sentry, and their tf_* counterparts.
-- This is pure visibility (set_visibility), which works on meshes.
--
-- The shield is FOUR meshes - g_shield (graphic), s_shield (shadow),
-- dm_metal_shield (metal plate) and c_shield (collision). The visible ones
-- are the first three, so all three get swapped; c_shield is collision-only
-- (not rendered) and is left alone. State-driven meshes (g_gun_dmg / g_supp /
-- g_ap_comp and their shadows) only appear when damaged / suppressed / AP and
-- are left for later.
--
-- LASER: g_laser (the vanilla laser-sight mesh) is hidden, and we deliberately
-- do NOT show tf_g_laser - TF2 sentries have no laser sight, so the emitter mesh
-- stays hidden. (The beam unit is killed in sentry_ammo.lua.)
local TF_SKIN_HIDE = {
	"g_laser", "g_gun", "g_base", "s_base", "s_gun",
	"g_shield", "s_shield", "dm_metal_shield",
}
local TF_SKIN_SHOW = {
	"tf_g_gun", "tf_g_base", "tf_s_base", "tf_s_gun",
	"tf_g_shield", "tf_s_shield", "tf_dm_metal_shield",
}

local function set_obj_visible(unit, name, visible)
	local o = unit:get_object(Idstring(name))
	if o then o:set_visibility(visible) end
end

function EngineerDeck.apply_tf_skin(unit)
	if not (unit and alive(unit)) then return end
	local base = unit:base()
	if base and base._eng_tf_skinned then return end
	for _, name in ipairs(TF_SKIN_HIDE) do set_obj_visible(unit, name, false) end
	for _, name in ipairs(TF_SKIN_SHOW) do set_obj_visible(unit, name, true) end
	if base then base._eng_tf_skinned = true end
end

-- --- TF2 dual-barrel muzzles -----------------------------------------
-- SentryGunWeapon keeps a 2-slot muzzle setup (_effect_align /
-- _muzzle_effect_table) and ALREADY alternates between the two slots every
-- shot via _interleaving_fire (see trigger_held). We point BOTH the bullet
-- origin (_effect_align) and the muzzle flash (_muzzle_effect_table) at the
-- two barrel locators (tf_fire1 / tf_fire2), so the flash, the tracer
-- (_spawn_trail_effect reads _effect_align) and the bullet all leave from the
-- barrels and alternate between them.
--
-- The catch: the engine fires straight along the muzzle's forward axis, and
-- the barrels sit off the gun's centerline - so firing them "straight" sends
-- the shot parallel to the aim line and it sails over/beside the target. The
-- actual per-shot fire DIRECTION is therefore computed in sentry_ammo.lua's
-- fire override: it raycasts the gun's centerline to find what it's aimed at,
-- then aims each barrel at that point (real converging fire) so off-centerline
-- barrels still land. This stays necessary no matter how the model is exported,
-- because the barrels are physically off-centre. Here we only set up origins.
--
-- POSITIONING: the converter reads node translation/rotation/scale, so the
-- model already places tf_fire1/tf_fire2 (currently at ~25.9, 67.4, 61.2). We
-- leave them as the model gives them and only fall back to the hardcoded values
-- below if a locator comes in flattened at the origin (length < FLAT_EPS) -
-- e.g. an older export that lost its transforms. Since tf_fire1/tf_fire2 are
-- locators (empties), set_local_position genuinely moves what the flash/bullet
-- read from, which is why this fallback works at all.
local TF_FIRE1_POS = Vector3(25.86, 67.42, 56.72)
local TF_FIRE2_POS = Vector3(-26.44, 67.42, 56.73)
local FLAT_EPS = 1.0   -- cm; a locator closer than this to its parent origin is "flattened"

function EngineerDeck.apply_tf_muzzles(w)
	if not w or w._eng_muzzles_done then return end
	local unit = w._unit
	if not (unit and alive(unit)) then return end
	local l = unit:get_object(Idstring("tf_fire1"))
	local r = unit:get_object(Idstring("tf_fire2"))
	if not (l and r) then return end          -- locators not present: stay single-point
	-- only place the locators if the model flattened them; otherwise trust the model
	pcall(function()
		if l:local_position():length() < FLAT_EPS then l:set_local_position(TF_FIRE1_POS) end
		if r:local_position():length() < FLAT_EPS then r:set_local_position(TF_FIRE2_POS) end
	end)
	w._effect_align = { l, r }
	if w._muzzle_effect_table then
		if w._muzzle_effect_table[1] then w._muzzle_effect_table[1].parent = l end
		if w._muzzle_effect_table[2] then w._muzzle_effect_table[2].parent = r end
	end
	w._eng_muzzles_done = true
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
					EngineerDeck.apply_tf_skin(self._unit)
					-- TF2 "deploy finished" cue. Hold the idle scan off briefly so
					-- the deploy sound and the first scan sweep don't stack on the
					-- same frame. (Finish volume tunable: keep in sync with
					-- FINISH_VOLUME in sentry_ammo.lua.)
					if EngineerDeck.play_sentry_sound and EngineerDeck.SND then
						EngineerDeck.play_sentry_sound(self._unit, EngineerDeck.SND.FINISH, 0.60)
					end
					pcall(function()
						local now = TimerManager and TimerManager:game() and TimerManager:game():time()
						if now then self._eng_scan_next = now + 1.8 end
					end)
				end
			end)
		end)
	end

	-- Idle SCAN loop: base-ext update ticks every frame while the turret is live
	-- (enabled in setup, disabled in on_death). sentry_idle_scan does all the
	-- gating (TF2-only, not the Dispenser, not dead, not currently firing) and
	-- the retrigger timing, so this stays a thin per-frame poke.
	if SentryGunBase.update then
		Hooks:PostHook(SentryGunBase, "update", "EngineerDeck_SentryScanTick", function(self, unit, t, dt)
			if EngineerDeck.sentry_idle_scan then
				pcall(EngineerDeck.sentry_idle_scan, self, t)
			end
		end)
	end
end
