-- =====================================================================
--  The Engineer - sentry ammo & fire audio  (hooked onto SentryGunWeapon)
-- =====================================================================
--  Finite ammo (not infinite): we refund every shot EXCEPT every AMMO_MULT-th
--  one, so the pool drains AMMO_MULT times slower - effectively AMMO_MULT x the
--  stock capacity, and it still runs out eventually. set_ammo() is absolute, so
--  we just restore the pre-shot total. Gated to tier 3 (Auto-Wrench).
--
--  Also re-applies the scrap-upgrade fire-rate multiplier: the game resets
--  _fire_rate_reduction whenever fire mode is switched (normal<->AP), so we
--  re-multiply by the sentry's stored _eng_fire_mult after each switch.
--
--  --- FIRE AUDIO (SuperBLT XAudio, positional) -----------------------------
--  A clip plays on EVERY actual shot, so the audio cadence equals the real fire
--  rate - which is driven by sentry_buff.lua's base auto.fire_rate and
--  engineer.lua's per-level fire multiplier (and AP fire-mode, automatically).
--  No hardcoded interval, so it stays in sync through any rebalancing.
--  SHOT_DIVISOR > 1 plays every Nth shot (still proportional to fire rate) if
--  you want to thin the density at very high rates.
--
--  Clip SET depends on turret type: SentryGunBase:get_type() returns
--  "sentry_gun_silent" for the suppressed deployable, so suppressed sentries
--  use the Singlesuppressed_* clips and normal sentries use the single_* clips.
--  Cue starts at MIN_LEVEL.
--
--  SAFETY: blt.xaudio.loadbuffer raises a FATAL, pcall-proof error on a
--  missing/empty/bad file, so we (1) verify each file is a real OggS container
--  with io.open BEFORE loadbuffer, and (2) only attempt loading each set ONCE.
--  A bad file means silence for that set, never a crash/freeze.
--
--  NOTE: XAudio loads standard-libVorbis OGG only; STEREO tracks ignore 3D
--  position (export MONO if you want sentry-positional audio with falloff).
--
--  The Dispenser chassis (_eng_dispenser) is a neutered sentry - it never fires,
--  but we short-circuit it here anyway so no ammo/audio logic ever touches it.
--
--  --- TF2 DUAL-BARREL CONVERGING FIRE --------------------------------------
--  On the first shot of a TF2-skinned sentry we call EngineerDeck.apply_tf_muzzles
--  (sentry.lua) to put both muzzle slots on the model's tf_fire1 / tf_fire2 barrel
--  locators, so the flash, tracer and bullet all leave from the barrels and the
--  engine alternates between them every shot.
--
--  But the engine fires straight along the muzzle's own forward axis, and the
--  barrels sit OFF the gun's centerline - fired straight, the shot runs parallel
--  to the aim line and sails over/beside the target. So for set-up TF2 sentries
--  we replace fire() with tf_converged_fire(): it raycasts the gun's centerline
--  to find what it's actually aimed at, then aims the active barrel at that point.
--  Off-centerline barrels converge onto the target and land, while flash + tracer
--  still come from the barrel. Anything unexpected -> we fall back to vanilla fire.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

local AMMO_MULT = 2

-- BLT resolves paths from the PD2 root; ModPath is this mod's folder.
local SND_DIR        = (ModPath or "mods/PD2 Perkdeck Mod/") .. "Sounds/"
local SHOT_VOLUME    = 0.35
local SHOT_MIN_DIST  = 350     -- cm: full volume within this range (mono files only)
local SHOT_MAX_DIST  = 6000    -- cm: inaudible beyond this (mono files only)
local SHOT_DIVISOR   = 1        -- play every Nth shot (1 = every shot = exact fire-rate sync)
local MIN_LEVEL      = 1        -- play the cue at this sentry level or above (set 1 for all)

-- one clip set per turret type; buffers load lazily and are cached
local SETS = {
	normal = {
		files = { "single_1.ogg", "single_2.ogg", "single_3.ogg", "single_4.ogg",
		          "single_5.ogg", "single_6.ogg", "single_7.ogg", "single_8.ogg" },
		buffers = nil, tried = false,
	},
	silent = {
		files = { "Singlesuppressed_1.ogg", "Singlesuppressed_2.ogg", "Singlesuppressed_3.ogg",
		          "Singlesuppressed_4.ogg", "Singlesuppressed_5.ogg", "Singlesuppressed_6.ogg",
		          "Singlesuppressed_7.ogg", "Singlesuppressed_8.ogg", "Singlesuppressed_9.ogg" },
		buffers = nil, tried = false,
	},
}

local function ammo_total(w)
	if w.ammo_total then return w:ammo_total() end
	if w.get_ammo_total then return w:get_ammo_total() end
	return nil
end

local function set_total(w, n)
	if w.set_ammo_total then w:set_ammo_total(n)
	elseif w.set_ammo then w:set_ammo(n) end
end

local function sentry_level(self)
	return (EngineerDeck.get_sentry_level and EngineerDeck.get_sentry_level(self._unit)) or 1
end

local function is_dispenser(self)
	local d
	pcall(function() d = self._unit and self._unit:base() and self._unit:base()._eng_dispenser end)
	return d and true or false
end

local function sentry_is_silenced(unit)
	local t
	pcall(function() t = unit:base() and unit:base().get_type and unit:base():get_type() end)
	return t == "sentry_gun_silent"
end

-- true only if the file exists and begins with the "OggS" magic. This gates
-- loadbuffer so we never hand it a missing/empty/non-ogg file (which fatals).
local function is_valid_ogg(path)
	local ok, valid = pcall(function()
		local f = io.open(path, "rb")
		if not f then return false end
		local magic = f:read(4)
		f:close()
		return magic == "OggS"
	end)
	return ok and valid == true
end

-- load a set's buffers ONCE (cached). Never retries, so a bad file can't loop.
local function ensure_set(set)
	if set.buffers then return true end
	if set.tried then return false end
	set.tried = true
	if not (blt and blt.xaudio and XAudio and XAudio.Buffer and XAudio.Source) then return false end
	pcall(function() blt.xaudio.setup() end)
	local loaded = {}
	for _, f in ipairs(set.files) do
		local path = SND_DIR .. f
		if is_valid_ogg(path) then
			pcall(function()
				local b = XAudio.Buffer:new(path)
				if b then table.insert(loaded, b) end
			end)
		else
			log("[EngineerDeck] minigun sound skipped (missing/empty/not-ogg): " .. tostring(path))
		end
	end
	if #loaded > 0 then set.buffers = loaded end
	return set.buffers ~= nil
end

local function play_shot(sentry)
	local set = sentry_is_silenced(sentry) and SETS.silent or SETS.normal
	if not ensure_set(set) then return end
	pcall(function()
		local buf = set.buffers[math.random(#set.buffers)]
		local src = XAudio.Source:new(buf)   -- auto-plays and auto-closes when done
		if not src then return end
		if src.set_position and alive(sentry) then src:set_position(sentry:position()) end
		if src.set_min_distance then src:set_min_distance(SHOT_MIN_DIST) end
		if src.set_max_distance then src:set_max_distance(SHOT_MAX_DIST) end
		if src.set_volume then src:set_volume(SHOT_VOLUME) end
	end)
end

-- fires once per real shot, so the audio cadence == the actual fire rate
local function fire_audio(self, fired)
	if not fired then return end
	if sentry_level(self) < MIN_LEVEL then return end
	if SHOT_DIVISOR > 1 then
		self._eng_snd_count = (self._eng_snd_count or 0) + 1
		if self._eng_snd_count % SHOT_DIVISOR ~= 0 then return end
	end
	play_shot(self._unit)
end

-- set up a TF2-skinned sentry's two muzzle slots onto the model's barrels.
-- Runs before the first real fire; self-no-ops afterwards (and is inert if the
-- tf_fire1/tf_fire2 locators are absent).
local function ensure_tf_muzzles(self)
	if not (self._unit and alive(self._unit)) then return end
	local base = self._unit:base()
	if not (base and base._eng_tf_skinned) then return end
	if EngineerDeck.apply_tf_muzzles then EngineerDeck.apply_tf_muzzles(self) end
end

if SentryGunWeapon and SentryGunWeapon.fire then
	local orig_fire = SentryGunWeapon.fire

	-- Raycast the gun's centerline to find the point it's actually aimed at, so
	-- the off-centerline barrels can converge on it. a_gun is the pitch object;
	-- after the export flattening it sits at the unit origin with the aim baked
	-- into its rotation, so a ray from a_gun:position() along a_gun:rotation():y()
	-- is the true aim line (the same line vanilla fires along). Fully guarded -
	-- returns nil on any trouble so the caller falls back to straight fire.
	local function tf_aim_point(self)
		local aim
		pcall(function()
			local a_gun = self._unit:get_object(Idstring("a_gun"))
			if not a_gun then return end
			local c_from = a_gun:position()
			local c_dir = a_gun:rotation():y()
			local td = tweak_data.weapon[self._name_id]
			local rng = (td and td.FIRE_RANGE) or 10000
			local c_to = c_from + c_dir * rng
			local ignore = self._setup and self._setup.ignore_units
			local ray = World:raycast("ray", c_from, c_to, "slot_mask", self._bullet_slotmask, "ignore_unit", ignore)
			aim = ray and ray.position or c_to
		end)
		return aim
	end

	-- Replica of SentryGunWeapon:fire, but the active barrel aims at the
	-- centerline's target point instead of firing straight along its own forward,
	-- so an off-centerline barrel converges onto the target and hits. Flash,
	-- tracer and bullet all originate at the barrel (_effect_align[slot]).
	local function tf_converged_fire(self, blanks, expend_ammo, shoot_player, target_unit)
		if expend_ammo then
			if self._ammo_total <= 0 then return end
			self:change_ammo(-1)
		end
		local slot = self._interleaving_fire
		local fire_obj = self._effect_align[slot]
		local from_pos = fire_obj:position()
		local direction
		local aim = tf_aim_point(self)
		if aim then
			direction = (aim - from_pos):normalized()
		else
			direction = fire_obj:rotation():y()   -- fallback: straight barrel forward
		end
		mvector3.spread(direction, tweak_data.weapon[self._name_id].SPREAD * self._spread_mul)
		World:effect_manager():spawn(self._muzzle_effect_table[slot])
		if self._use_shell_ejection_effect then
			World:effect_manager():spawn(self._shell_ejection_effect_table)
		end
		if self._unit:damage() and self._unit:damage():has_sequence("anim_fire_seq") then
			self._unit:damage():run_sequence_simple("anim_fire_seq")
		end
		local ray_res = self:_fire_raycast(from_pos, direction, shoot_player, target_unit)
		if self._alert_events and ray_res and ray_res.rays then
			RaycastWeaponBase._check_alert(self, ray_res.rays, from_pos, direction, self._unit)
		end
		self._unit:movement():give_recoil()
		self._unit:event_listener():call("on_fire")
		return ray_res
	end

	function SentryGunWeapon:fire(blanks, expend_ammo, shoot_player, target_unit)
		-- Dispenser chassis: neutered, never apply ammo/audio logic
		if is_dispenser(self) then
			return orig_fire(self, blanks, expend_ammo, shoot_player, target_unit)
		end
		pcall(function() ensure_tf_muzzles(self) end)   -- dual-barrel setup (first shot)
		local boosted = EngineerDeck.is_active and EngineerDeck.is_active(3)
		local pre = boosted and ammo_total(self) or nil

		-- converging dual-barrel fire for set-up TF2 sentries; vanilla otherwise
		local base = self._unit and self._unit:base()
		local use_tf = base and base._eng_tf_skinned and self._eng_muzzles_done and not self._eng_converge_failed
		local r
		if use_tf then
			local ok, res = pcall(tf_converged_fire, self, blanks, expend_ammo, shoot_player, target_unit)
			if ok then
				r = res
			else
				-- one failure -> stop trying to converge on this weapon and let it
				-- fall back to vanilla from here on (no re-fire this frame, so we
				-- never double-shoot or double-spend ammo on the failing shot).
				self._eng_converge_failed = true
				log("[EngineerDeck] converged fire disabled (error): " .. tostring(res))
				r = nil
			end
		else
			r = orig_fire(self, blanks, expend_ammo, shoot_player, target_unit)
		end

		if boosted and pre then
			pcall(function()
				self._eng_shots = (self._eng_shots or 0) + 1
				if self._eng_shots % AMMO_MULT ~= 0 then
					set_total(self, pre)   -- refund this shot
				end
			end)
		end
		pcall(function() fire_audio(self, r) end)
		return r
	end
end

-- keep an upgraded sentry's faster cadence through AP/normal fire-mode toggles
if SentryGunWeapon and SentryGunWeapon._set_fire_mode then
	Hooks:PostHook(SentryGunWeapon, "_set_fire_mode", "EngineerDeck_ReapplyFireMult", function(self, ...)
		pcall(function()
			if self._eng_fire_mult and self._fire_rate_reduction then
				self._fire_rate_reduction = self._fire_rate_reduction * self._eng_fire_mult
			end
		end)
	end)
end
