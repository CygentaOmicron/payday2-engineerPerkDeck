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
--  --- FIRE AUDIO (TF2 looping minigun, SuperBLT XAudio) --------------------
--  Goal: our TF2 turrets play the TF2 sentry sound and NOTHING vanilla.
--
--  1) SILENCE VANILLA. The vanilla fire sound is a looping Wwise "autofire"
--     event: SentryGunWeapon:start_autofire -> _sound_autofire_start posts it,
--     and stop_autofire -> _sound_autofire_end/_end_empty/_end_cooldown stop it
--     and post stop/cooldown/empty cues. We override those four methods so that
--     on a TF2-skinned sentry they do nothing (and drop any lingering handle).
--     Non-TF2 sentries keep their vanilla sound.
--
--  2) PLAY THE TF2 LOOP. The TF2 shoot file is a ~0.705s LOOP (not a one-shot),
--     so per-shot playback would stack dozens of overlapping copies. Instead we
--     re-trigger the clip on a timer: fire() runs once per shot, so on each shot
--     we check whether LOOP_RETRIGGER seconds have elapsed since the last clip
--     and, if so, start the next one. While the turret is firing this produces a
--     continuous loop; when it stops firing the re-triggers stop and the last
--     clip tails off on its own (a natural spin-down). Re-trigger is decoupled
--     from fire rate, so even a very fast sentry only starts ~1 clip per 0.7s.
--
--  Clips are MONO OGG (XAudio is OGG-only, and stereo ignores 3D position), so
--  the sound attenuates with distance from the turret. Gated to TF2-skinned
--  sentries via base._eng_tf_skinned (same marker as the visual skin), so this
--  only ever touches the local Engineer's own turrets.
--
--  SAFETY: blt.xaudio.loadbuffer raises a FATAL, pcall-proof error on a
--  missing/empty/bad file, so we (1) verify the file is a real OggS container
--  with io.open BEFORE loading, and (2) only attempt to load the buffer ONCE.
--  A bad/missing file means silence, never a crash/freeze.
--
--  The Dispenser chassis (_eng_dispenser) is a neutered sentry - it never fires,
--  but we short-circuit it here anyway so no ammo/audio logic ever touches it.
--
--  --- TF2 LASER (disabled) -------------------------------------------------
--  TF2 sentries have no laser sight. The visible beam is a separate peqbox unit
--  the engine spawns/links when it calls SentryGunWeapon:set_laser_enabled with
--  a non-nil mode; we override that to force the "off" path for our turrets, so
--  the beam never spawns. (The laser MESH is hidden in sentry.lua.)
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

-- Converged-fire aim: how far forward (cm) along the gun's aim line to START the
-- centerline raycast. a_gun sits at the unit origin (ground level, at the base),
-- so a ray from exactly there skims the floor and snags props sitting next to the
-- turret (a fallen riot shield, a dropped bag). Starting AIM_SKIP forward ALONG
-- the same aim line clears the base footprint without moving off the line (which
-- is what matters - see tf_aim_point). Raise if base clutter still steals fire;
-- lower if very close targets get missed.
local AIM_SKIP = 200

-- BLT resolves paths from the PD2 root; ModPath is this mod's folder.
local SND_DIR        = (ModPath or "mods/PD2 Perkdeck Mod/") .. "Sounds/Sentry/"
local FIRE_CLIP      = "sentry_shoot.ogg"  -- mono OGG; the looping TF2 fire (swap to "sentry_shoot.ogg" for the non-mini sentry)
local SHOT_VOLUME    = 0.40      -- 0..1; this is now the ONLY fire sound, so louder than the old layered cue
local SHOT_MIN_DIST  = 350      -- cm: full volume within this range
local SHOT_MAX_DIST  = 6000     -- cm: inaudible beyond this
local LOOP_RETRIGGER = 0.06     -- s: start the next clip this long after the last one. Slightly under the
                                -- ~0.705s clip length so the loop has no audible gap. Tune up/down to taste.

-- single shared buffer for the fire loop; loaded lazily, cached, tried once
local fire_buf = { buffer = nil, tried = false }

local function ammo_total(w)
	if w.ammo_total then return w:ammo_total() end
	if w.get_ammo_total then return w:get_ammo_total() end
	return nil
end

local function set_total(w, n)
	if w.set_ammo_total then w:set_ammo_total(n)
	elseif w.set_ammo then w:set_ammo(n) end
end

local function is_dispenser(self)
	local d
	pcall(function() d = self._unit and self._unit:base() and self._unit:base()._eng_dispenser end)
	return d and true or false
end

-- true only for the local Engineer's TF2-skinned turrets (same marker the visual
-- skin sets). Gates the vanilla-sound silencing, the laser kill and the TF2 loop,
-- so other players' / non-Engineer sentries are left completely vanilla.
local function is_modded_sentry(self)
	local m
	pcall(function() m = self._unit and self._unit:base() and self._unit:base()._eng_tf_skinned end)
	return m and true or false
end

-- true only if the file exists and begins with the "OggS" magic. This gates the
-- buffer load so we never hand XAudio a missing/empty/non-ogg file (which fatals).
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

-- load the fire buffer ONCE (cached). Never retries, so a bad file can't loop.
local function ensure_fire_buffer()
	if fire_buf.buffer then return true end
	if fire_buf.tried then return false end
	fire_buf.tried = true
	if not (blt and blt.xaudio and XAudio and XAudio.Buffer and XAudio.Source) then return false end
	pcall(function() blt.xaudio.setup() end)
	local path = SND_DIR .. FIRE_CLIP
	if not is_valid_ogg(path) then
		log("[EngineerDeck] TF2 fire clip missing/empty/not-ogg: " .. tostring(path))
		return false
	end
	pcall(function() fire_buf.buffer = XAudio.Buffer:new(path) end)
	return fire_buf.buffer ~= nil
end

-- start one positional instance of the fire loop at the turret
local function play_fire_loop(sentry)
	if not ensure_fire_buffer() then return end
	pcall(function()
		local src = XAudio.Source:new(fire_buf.buffer)   -- auto-plays and auto-closes when done
		if not src then return end
		if src.set_position and alive(sentry) then src:set_position(sentry:position()) end
		if src.set_min_distance then src:set_min_distance(SHOT_MIN_DIST) end
		if src.set_max_distance then src:set_max_distance(SHOT_MAX_DIST) end
		if src.set_volume then src:set_volume(SHOT_VOLUME) end
	end)
end

-- runs once per real shot; re-triggers the loop clip on a fixed cadence (NOT per
-- shot), so it stays continuous at any fire rate and tails off when firing stops.
local function fire_audio(self, fired)
	if not fired then return end
	if not is_modded_sentry(self) then return end
	local now = TimerManager:game():time()
	if self._eng_loop_next and now < self._eng_loop_next then return end
	self._eng_loop_next = now + LOOP_RETRIGGER
	play_fire_loop(self._unit)
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
	-- the off-centerline barrels can converge on it.
	--
	-- a_gun is the pitch object. After the model export its ROTATION still carries
	-- the true aim, but its POSITION collapsed to the unit origin (ground level).
	-- The movement aims a_gun so that a ray FROM the origin along its forward hits
	-- the target's center mass - so the centerline ray MUST stay on that line
	-- (origin + t*dir). (An earlier attempt started the ray at the barrels' height
	-- to dodge base clutter; that moved it off the aim line and the shots flew high
	-- by the barrel height - don't do that.)
	--
	-- The only real problem is that starting exactly at the origin makes the ray
	-- skim the floor, so a prop right next to the turret intercepts it at point-
	-- blank range. So we start the ray AIM_SKIP forward ALONG the same line: still
	-- on the aim line (the found point is still the true target), just past the
	-- base footprint. Targets sit well beyond this; a closer enemy still gets hit
	-- (worst case is the small barrel offset at point-blank). Fully guarded -
	-- returns nil on any trouble so the caller falls back to straight fire.
	local function tf_aim_point(self)
		local aim
		pcall(function()
			local a_gun = self._unit:get_object(Idstring("a_gun"))
			if not a_gun then return end
			local c_dir = a_gun:rotation():y()
			local c_from = a_gun:position() + c_dir * AIM_SKIP   -- on the aim line, just past the base
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

-- Silence the vanilla Wwise fire sound on our TF2 turrets. These four methods
-- are the only places the sentry posts its autofire start/stop/cooldown/empty
-- cues; for a TF2-skinned sentry we drop them entirely (the TF2 loop plays
-- instead). Every other sentry keeps its vanilla sound untouched.
if SentryGunWeapon then
	local SILENCE = {
		"_sound_autofire_start",
		"_sound_autofire_end",
		"_sound_autofire_end_empty",
		"_sound_autofire_end_cooldown",
	}
	for _, mname in ipairs(SILENCE) do
		local orig = SentryGunWeapon[mname]
		if orig then
			SentryGunWeapon[mname] = function(self, ...)
				if is_modded_sentry(self) then
					if self._autofire_sound_event then
						pcall(function() self._autofire_sound_event:stop() end)
						self._autofire_sound_event = nil
					end
					return
				end
				return orig(self, ...)
			end
		end
	end
end

-- Kill the laser sight on our TF2 turrets. set_laser_enabled is the single gate
-- the engine uses to toggle the beam (a separate spawned peqbox unit linked to
-- the laser bone). For a TF2 sentry we force the "off" path (mode = nil), so the
-- beam never spawns and any existing one is despawned. update_laser calls this
-- every tick, so it stays off. Cosmetic only - targeting/firing don't use it.
if SentryGunWeapon and SentryGunWeapon.set_laser_enabled then
	local orig_set_laser_enabled = SentryGunWeapon.set_laser_enabled
	function SentryGunWeapon:set_laser_enabled(mode, blink)
		if is_modded_sentry(self) then
			return orig_set_laser_enabled(self, nil, nil)
		end
		return orig_set_laser_enabled(self, mode, blink)
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
