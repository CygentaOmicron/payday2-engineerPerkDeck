-- =====================================================================
--  The Engineer - sentry registration  (hooked onto SentryGunBase)
-- =====================================================================
--  Two jobs here:
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
local TF_SKIN_HIDE = {
	"g_laser", "g_gun", "g_base", "s_base", "s_gun",
	"g_shield", "s_shield", "dm_metal_shield",
}
local TF_SKIN_SHOW = {
	"tf_g_laser", "tf_g_gun", "tf_g_base", "tf_s_base", "tf_s_gun",
	"tf_g_shield", "tf_s_shield", "tf_dm_metal_shield",
}

local function set_obj_visible(unit, name, visible)
	local o = unit:get_object(Idstring(name))
	if o then o:set_visibility(visible) end
end

-- --- TF2 laser -------------------------------------------------------
-- The visible laser sight is NOT the g_laser mesh - it's a separate peqbox
-- unit that SentryGunWeapon spawns and LINKS to the object named by
-- _laser_align_name (vanilla "g_laser"):
--     spawn_pos = self._laser_align:position()
--     self._laser_unit = World:spawn_unit("...peqbox...", spawn_pos, spawn_rot)
--     self._unit:link(self._laser_align:name(), self._laser_unit)
-- So the beam rides the g_laser bone. Hiding the g_laser mesh doesn't move it,
-- and moving the g_laser bone after the unit is already linked doesn't move it
-- either (confirmed in game). To put the beam on tf_g_laser we repoint
-- _laser_align to tf_g_laser - which fixes any FUTURE spawn - and, if a laser
-- unit is already up, despawn it and respawn onto tf_g_laser, replicating the
-- engine's own spawn sequence verbatim (including its "set_max_distace"
-- misspelling, which is the real method name). A flag keeps the setup-time and
-- first-fire callers from doubling up.
local LASER_UNIT = "units/payday2/weapons/wpn_npc_upg_fl_ass_smg_sho_peqbox/wpn_npc_upg_fl_ass_smg_sho_peqbox"

function EngineerDeck.repoint_laser(w, unit)
	if not w or w._eng_laser_repointed then return end
	if not (unit and alive(unit)) then return end
	local tf = unit:get_object(Idstring("tf_g_laser"))
	if not tf then return end
	w._laser_align = tf
	w._laser_align_name = "tf_g_laser"
	-- if the beam is already up (linked to the old g_laser bone), respawn it
	if alive(w._laser_unit) then
		pcall(function()
			w._laser_unit:base():set_off()
			w._laser_unit:set_slot(0)
			w._laser_unit = nil
			local spawn_pos = tf:position()
			local spawn_rot = tf:rotation()
			w._laser_unit = World:spawn_unit(Idstring(LASER_UNIT), spawn_pos, spawn_rot)
			unit:link(tf:name(), w._laser_unit)
			w._laser_unit:base():set_npc()
			w._laser_unit:base():set_on()
			w._laser_unit:base():set_max_distace(10000)
			w._laser_unit:base():add_ray_ignore_unit(unit)
			w._laser_unit:set_visible(false)
		end)
	end
	w._eng_laser_repointed = true
end

function EngineerDeck.apply_tf_skin(unit)
	if not (unit and alive(unit)) then return end
	local base = unit:base()
	if base and base._eng_tf_skinned then return end
	for _, name in ipairs(TF_SKIN_HIDE) do set_obj_visible(unit, name, false) end
	for _, name in ipairs(TF_SKIN_SHOW) do set_obj_visible(unit, name, true) end
	-- put the laser beam on tf_g_laser (see repoint_laser). The weapon ext holds
	-- the laser state; grab it here so the beam is right from deploy. If the ext
	-- isn't ready yet, the first-fire path (apply_tf_muzzles) covers it.
	pcall(function()
		local w = unit:weapon()
		if w then EngineerDeck.repoint_laser(w, unit) end
	end)
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
	-- backup laser repoint, in case the weapon ext wasn't ready at setup
	EngineerDeck.repoint_laser(w, unit)
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
				end
			end)
		end)
	end
end
