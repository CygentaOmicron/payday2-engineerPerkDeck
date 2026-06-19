-- =====================================================================
--  The Engineer - Wrench Repair & Upgrade  (hooked onto PlayerStandard melee)
-- =====================================================================
--  Swing your repair melee at one of your own sentries to either:
--    * UPGRADE it (Lv1 -> Lv2 -> Lv3) if you can afford the scrap cost. An
--      upgrade also fully refurbishes the sentry (heal + reload) for free.
--    * otherwise REPAIR it: full health + reload, costing weapon ammo in
--      proportion to how much it needed.
--  Gated to tier 3 (Auto-Wrench). Scrap is earned via ammo pickups / bag use
--  / the Dispenser (see scrap.lua, engineer.lua). The sentry's level and your
--  scrap show in its hover prompt (see sentry_hud.lua, localization.lua).
--
--  WRENCH_IDS lists which melee weapons count. If you swing near a sentry
--  holding a melee that isn't listed, its id is written to the BLT log.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

local WRENCH_IDS  = {
	shock        = true,   -- electric baton / Buzzer (your tested melee)
	wrench       = true,   -- guesses for the Monkey Wrench id...
	monkeywrench = true,
	monkey_wrench= true,
}
local MELEE_RANGE = 260    -- cm, how close you must be to your sentry
local DEPLOY_COST = 0.30   -- fraction of current ammo spent on a FULL repair
local MIN_SEVERITY= 0.02   -- skip a plain repair if the sentry is pristine
local COOLDOWN    = 0.4    -- s, anti double-trigger

local function ratio(getter_owner, getter)
	local r = 1
	pcall(function() if getter_owner and getter then r = getter(getter_owner) end end)
	return r or 1
end

local function hint(text)
	pcall(function()
		if managers.hud and managers.hud.show_hint then managers.hud:show_hint({ text = text }) end
	end)
end

-- Sentry HP lives on the SentryGunDamage extension, NOT in tweak_data.weapon.
-- init() hardcodes _HEALTH_INIT/_SHIELD_HEALTH_INIT = 10000 and damage only
-- ever lowers _health, so cd._HEALTH_INIT is always the true spawn max.
local function full_heal(s)
	pcall(function()
		local cd = s:character_damage()
		if cd and cd.set_health then
			cd:set_health(cd._HEALTH_INIT or 10000, cd._SHIELD_HEALTH_INIT or 10000)
		end
	end)
end

-- Refill ammo AND wake the sentry. When a sentry runs dry the game fires
-- on_out_of_ammo and the brain deactivates (tilts down, stops scanning);
-- just bumping _ammo_total leaves it dead. The vanilla refill path uses
-- weapon:change_ammo (which networks the new ammo + refreshes the readout)
-- and brain:switch_on (which reactivates it), so we do exactly that. We also
-- fire on_sync_ammo so status/contour mods (which colour the outline red on
-- out-of-ammo) re-check the now-full ammo and revert to green/blue.
local function full_ammo(s)
	pcall(function()
		local w = s:weapon()
		if w then
			local maxa = w.ammo_max and w:ammo_max()
			local cur  = w.ammo_total and w:ammo_total()
			if maxa and cur and w.change_ammo and maxa > cur then
				w:change_ammo(maxa - cur)          -- proper add: syncs HUD/network
			elseif maxa and w.set_ammo then
				w:set_ammo(maxa)
			end
			w._eng_shots = 0   -- refresh the finite-ammo pool
		end
	end)
	pcall(function()
		if s:base() and s:base().set_waiting_for_refill then s:base():set_waiting_for_refill(false) end
	end)
	pcall(function()
		if s:brain() and s:brain().switch_on then s:brain():switch_on() end   -- reactivate an emptied sentry
	end)
	pcall(function()
		if s:event_listener() then s:event_listener():call("on_sync_ammo") end  -- nudge contour/status mods to revert red->green
	end)
	pcall(function()
		if s:interaction() then s:interaction():set_dirty(true) end
	end)
end

local function deduct_player_ammo(unit, frac)
	if frac <= 0 or not (alive(unit) and unit:inventory()) then return end
	for _, sel in pairs(unit:inventory():available_selections()) do
		pcall(function()
			local wb = sel.unit and alive(sel.unit) and sel.unit:base()
			local ab = wb and (wb.ammo_base and wb:ammo_base() or wb)
			if ab and ab.get_ammo_total and ab.set_ammo_total then
				ab:set_ammo_total(math.max(0, math.floor(ab:get_ammo_total() * (1 - frac))))
				if managers.hud and wb.selection_index and wb.ammo_info then
					managers.hud:set_ammo_amount(wb:selection_index(), wb:ammo_info())
				end
			end
		end)
	end
end

local function find_target(self)
	local pu = self._unit
	if not alive(pu) then return nil end
	local ppos = pu:position()
	local fwd
	pcall(function() fwd = self._ext_camera and self._ext_camera:forward() end)
	local best, best_d
	for _, s in ipairs(EngineerDeck._my_sentries or {}) do
		if alive(s) then
			local to = s:position() - ppos
			local d = mvector3.length(to)
			if d <= MELEE_RANGE then
				local infront = true
				if fwd then
					mvector3.normalize(to)
					infront = mvector3.dot(fwd, to) > 0.2
				end
				if infront and (not best_d or d < best_d) then best, best_d = s, d end
			end
		end
	end
	return best
end

local function try_repair(self)
	if not (EngineerDeck.is_active and EngineerDeck.is_active(3)) then return end
	local now = TimerManager:game():time()
	if EngineerDeck._wrench_cd_until and now < EngineerDeck._wrench_cd_until then return end

	local s = find_target(self)
	if not s then return end

	local melee_id = managers.blackmarket and managers.blackmarket:equipped_melee_weapon()
	if not WRENCH_IDS[melee_id] then
		log("[EngineerDeck] wrench-repair: equipped melee id is '" .. tostring(melee_id) ..
			"' - add it to WRENCH_IDS to enable repair with this melee.")
		return
	end

	EngineerDeck._wrench_cd_until = now + COOLDOWN

	-- 1) try to UPGRADE first (spends scrap; full refurbish, no ammo cost)
	local level = EngineerDeck.get_sentry_level(s)
	if level < 3 then
		local cost = EngineerDeck.upgrade_cost(level + 1)
		if cost and EngineerDeck.spend_scrap(cost) then
			EngineerDeck.apply_sentry_level(s, level + 1)
			full_heal(s)
			full_ammo(s)
			hint("Sentry upgraded to Level " .. tostring(level + 1))
			return
		end
	end

	-- 2) otherwise REPAIR (heal + reload, costs weapon ammo by severity)
	local h = ratio(s:character_damage(), s:character_damage() and s:character_damage().health_ratio)
	local a = ratio(s:weapon(), s:weapon() and s:weapon().ammo_ratio)
	local severity = math.max(1 - h, 1 - a)
	if severity >= MIN_SEVERITY then
		full_heal(s)
		full_ammo(s)
		deduct_player_ammo(self._unit, DEPLOY_COST * severity)
		hint("Sentry repaired")
	elseif level < 3 then
		local cost = EngineerDeck.upgrade_cost(level + 1) or 0
		hint("Need " .. tostring(cost) .. " scrap to upgrade (have " ..
			tostring(math.floor(EngineerDeck._scrap or 0)) .. ")")
	end
end

if PlayerStandard then
	local fn = (PlayerStandard._do_action_melee and "_do_action_melee")
		or (PlayerStandard._do_melee_damage and "_do_melee_damage")
	if fn then
		Hooks:PostHook(PlayerStandard, fn, "EngineerDeck_WrenchRepair", function(self, ...)
			pcall(function() try_repair(self) end)
		end)
	end
end
