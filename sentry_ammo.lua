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
--  --- TF2 SOUND SUITE (SuperBLT XAudio, all mono OGG, positional) ----------
--  Goal: our TF2 turrets play TF2 sentry sounds and NOTHING vanilla. Every clip
--  is loaded through one shared cache (ensure_clip) and played as a positional
--  XAudio source so it attenuates with distance from the turret. Everything is
--  gated to TF2-skinned sentries via base._eng_tf_skinned (the visual-skin
--  marker), so other players' / non-Engineer sentries stay fully vanilla.
--
--  Events and where each is triggered:
--    * FIRE  (looping minigun) - here, fire() -> fire_audio (see below)
--    * SPOT  (target acquired) - here, _sound_autofire_start (debounced)
--    * EMPTY (out of ammo)      - here, _sound_autofire_end_empty
--    * SCAN  (idle sweep, loop) - sentry.lua SentryGunBase:update -> sentry_idle_scan
--    * FINISH(deploy complete)  - sentry.lua setup hook
--    * EXPLODE (destroyed)      - sentry_death.lua _apply_damage (on death)
--  play_sentry_sound / sentry_idle_scan are exposed on EngineerDeck so the
--  base + death files can fire one-shots without duplicating the XAudio plumbing.
--
--  FIRE detail: the TF2 shoot file is a ~0.7s LOOP, so we re-trigger it on a
--  timer rather than per-shot (fire() runs once per shot; we start the next clip
--  once LOOP_RETRIGGER has elapsed). Continuous while firing, tails off when it
--  stops. SILENCE: the vanilla fire sound is a looping Wwise "autofire" event
--  posted by _sound_autofire_start/_end/_end_empty/_end_cooldown - we override
--  all four so a TF2 sentry drops the vanilla handle (and two of them now post a
--  TF2 cue instead). Non-TF2 sentries keep their vanilla sound.
--
--  SAFETY: blt.xaudio.loadbuffer raises a FATAL, pcall-proof error on a
--  missing/empty/bad file, so we (1) verify each file is a real OggS container
--  with io.open BEFORE loading, and (2) only attempt to load any given buffer
--  ONCE (cached). A bad/missing file means that one clip is silent, never a
--  crash/freeze. The Dispenser chassis (_eng_dispenser) is short-circuited so no
--  ammo/audio logic ever touches it.
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

-- --- the other TF2 event clips (mono OGG, placed alongside the fire clip) -----
-- File names are on EngineerDeck so sentry.lua / sentry_death.lua can reference
-- them. Volumes/ranges are local tunables. Missing files just stay silent.
EngineerDeck.SND = EngineerDeck.SND or {}
EngineerDeck.SND.FINISH  = "sentry_finish.ogg"   -- deploy complete
EngineerDeck.SND.SPOT    = "sentry_spot.ogg"     -- target acquired
EngineerDeck.SND.EMPTY   = "sentry_empty.ogg"    -- out of ammo
EngineerDeck.SND.SCAN    = "sentry_scan.ogg"     -- idle sweep (looped via retrigger)
EngineerDeck.SND.EXPLODE = "sentry_explode.ogg"  -- destroyed

local FINISH_VOLUME  = 0.60
local SPOT_VOLUME    = 0.50
local EMPTY_VOLUME   = 0.55
local EXPLODE_VOLUME = 0.85
local SCAN_VOLUME    = 0.22     -- subtle; it loops constantly while idle

local SPOT_COOLDOWN  = 3.0      -- s: don't re-beep "spotted" more often than this per turret
local SCAN_RETRIGGER = 3.20     -- s: spacing of the idle scan loop (~just under the 3.25s clip, no gap)
local FIRE_RECENCY   = 0.35     -- s: treat the turret as "engaging" (no idle scan) for this long after a shot

EngineerDeck.play_sentry_sound = EngineerDeck.play_sentry_sound  -- fwd ref (defined below)

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

-- shared clip cache: file name -> { buffer = <XAudio.Buffer>|nil, tried = bool }.
-- Each clip is verified + loaded at most ONCE; a bad/missing file is logged and
-- stays nil (silent) forever after, so it can never loop on a failing load.
local clip_cache = {}

local function ensure_clip(file)
	local c = clip_cache[file]
	if not c then c = { buffer = nil, tried = false }; clip_cache[file] = c end
	if c.buffer then return c.buffer end
	if c.tried then return nil end
	c.tried = true
	if not (blt and blt.xaudio and XAudio and XAudio.Buffer and XAudio.Source) then return nil end
	pcall(function() blt.xaudio.setup() end)
	local path = SND_DIR .. file
	if not is_valid_ogg(path) then
		log("[EngineerDeck] TF2 sentry clip missing/empty/not-ogg: " .. tostring(path))
		return nil
	end
	pcall(function() c.buffer = XAudio.Buffer:new(path) end)
	return c.buffer
end

-- play ONE positional instance of a clip at a unit. Returns the source (or nil).
-- The source auto-plays and auto-closes when the clip finishes.
function EngineerDeck.play_sentry_sound(unit, file, volume, min_dist, max_dist)
	local buf = ensure_clip(file)
	if not buf then return nil end
	local src
	pcall(function()
		src = XAudio.Source:new(buf)
		if not src then return end
		if src.set_position and unit and alive(unit) then src:set_position(unit:position()) end
		if src.set_min_distance then src:set_min_distance(min_dist or SHOT_MIN_DIST) end
		if src.set_max_distance then src:set_max_distance(max_dist or SHOT_MAX_DIST) end
		if src.set_volume then src:set_volume(volume or SHOT_VOLUME) end
	end)
	return src
end

-- start one positional instance of the fire loop at the turret
local function play_fire_loop(sentry)
	local buf = ensure_clip(FIRE_CLIP)
	if not buf then return end
	pcall(function()
		local src = XAudio.Source:new(buf)   -- auto-plays and auto-closes when done
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

-- IDLE SCAN: called every frame for a sentry (from sentry.lua's SentryGunBase
-- :update hook). Plays the TF2 scan sweep on a loop while the turret is idle -
-- alive, TF2-skinned, not the Dispenser chassis, and not firing (we treat a shot
-- in the last FIRE_RECENCY seconds as "engaging" so scan never plays over fire).
-- `base` is the SentryGunBase extension; `t` is the update game time.
function EngineerDeck.sentry_idle_scan(base, t)
	if not base or not base._eng_tf_skinned then return end
	if base._eng_dispenser or base._eng_dead then return end
	local unit = base._unit
	if not (unit and alive(unit)) then return end
	t = t or (TimerManager and TimerManager:game() and TimerManager:game():time())
	if not t then return end
	-- engaging? (fired very recently) -> let the fire loop own the audio
	local w = base._weapon
	if w and w._eng_loop_next and t < (w._eng_loop_next + FIRE_RECENCY) then return end
	if base._eng_scan_next and t < base._eng_scan_next then return end
	base._eng_scan_next = t + SCAN_RETRIGGER
	EngineerDeck.play_sentry_sound(unit, EngineerDeck.SND.SCAN, SCAN_VOLUME)
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

-- Replace the vanilla Wwise fire cues on our TF2 turrets. These four methods are
-- the only places the sentry posts its autofire start/stop/cooldown/empty cues.
-- For a TF2-skinned sentry we always drop the lingering vanilla handle; two of
-- them additionally post a TF2 cue (SPOT on engage, EMPTY on running dry). Every
-- non-TF2 sentry keeps its vanilla sound untouched.
if SentryGunWeapon then
	local function drop_vanilla_handle(self)
		if self._autofire_sound_event then
			pcall(function() self._autofire_sound_event:stop() end)
			self._autofire_sound_event = nil
		end
	end

	-- engage -> "spotted" beep (debounced per turret so re-engaging doesn't spam)
	local orig_start = SentryGunWeapon._sound_autofire_start
	if orig_start then
		SentryGunWeapon._sound_autofire_start = function(self, ...)
			if is_modded_sentry(self) then
				drop_vanilla_handle(self)
				pcall(function()
					local now = TimerManager:game():time()
					if not self._eng_spot_next or now >= self._eng_spot_next then
						self._eng_spot_next = now + SPOT_COOLDOWN
						EngineerDeck.play_sentry_sound(self._unit, EngineerDeck.SND.SPOT, SPOT_VOLUME)
					end
				end)
				return
			end
			return orig_start(self, ...)
		end
	end

	-- ran dry -> "empty" click
	local orig_empty = SentryGunWeapon._sound_autofire_end_empty
	if orig_empty then
		SentryGunWeapon._sound_autofire_end_empty = function(self, ...)
			if is_modded_sentry(self) then
				drop_vanilla_handle(self)
				pcall(function()
					EngineerDeck.play_sentry_sound(self._unit, EngineerDeck.SND.EMPTY, EMPTY_VOLUME)
				end)
				return
			end
			return orig_empty(self, ...)
		end
	end

	-- plain stop / cooldown -> just silence the vanilla loop (the fire clip tails
	-- off on its own; the idle scan resumes once FIRE_RECENCY has elapsed)
	for _, mname in ipairs({ "_sound_autofire_end", "_sound_autofire_end_cooldown" }) do
		local orig = SentryGunWeapon[mname]
		if orig then
			SentryGunWeapon[mname] = function(self, ...)
				if is_modded_sentry(self) then
					drop_vanilla_handle(self)
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
