-- =====================================================================
--  The Engineer - core behaviour  (hooked onto PlayerManager)
-- =====================================================================

EngineerDeck = EngineerDeck or {}
EngineerDeck._dispensers = {}
EngineerDeck._my_sentries = {}
EngineerDeck._banked_kills = 0
EngineerDeck._scrap = EngineerDeck._scrap or 0

local DISPENSER_RADIUS = 500      -- cm, aura radius
local HEAL_RATIO       = 0.05     -- 5% max health per tick
local AMMO_ROUNDS      = 3        -- WHOLE rounds added per tick (no fractions)
local TICK_INTERVAL    = 1        -- s
local SURGE_TIME       = 8        -- s
local SURGE_PER_KILL   = 0.10

-- ---- dispenser --------------------------------------------------------
-- The dispenser is an aura zone marked by a supply prop. We DON'T use a sentry
-- anymore: a passive sentry drew no enemy fire (so it was never really
-- destructible) but still read as a turret in HUD mods and looked like one.
-- Instead we spawn a supply-themed prop purely as a visual marker - and ONLY
-- if that unit is actually loaded for the current heist (PackageManager:has),
-- so an unloaded asset is skipped, never fatal (unlike the ATM/dyn_resource
-- route). If nothing's loaded, the aura still works and the ground ring marks
-- it. The prop has no HP; the dispenser persists until you redeploy.
local MAX_DISPENSERS = 1          -- redeploying removes the oldest
local DRAW_RING      = true       -- ground ring showing the aura radius (set false to hide)

-- supply-themed props, tried in order; first one LOADED this heist is used.
-- gen_equipment_medicbag is the doctor-bag model we reskin (main.xml / TF2
-- Dispenser) - preferred, but it's only loaded when a doctor bag is in the
-- heist's loadout (common in MP, rare in solo where we run the sentry). The
-- rest are fallbacks so the prop still appears when the medicbag isn't loaded.
local MEDICBAG_PATH = "units/payday2/equipment/gen_equipment_medicbag/gen_equipment_medicbag"
local DISP_PROP_CANDIDATES = {
	MEDICBAG_PATH,                                                                      -- TF2 Dispenser (reskinned doctor-bag model)
	"units/payday2/equipment/gen_equipment_ammo/gen_equipment_ammo",                   -- ammo bag
	"units/payday2/equipment/gen_equipment_doctor_bag/gen_equipment_doctor_bag",       -- doctor bag
	"units/payday2/equipment/gen_equipment_grenade_crate/gen_equipment_grenade_crate", -- grenade crate
	"units/payday2/pickups/gen_pku_lootbag/gen_pku_lootbag",                            -- loot bag (often loaded)
}

-- TF2 Dispenser combined-model flip. The reskinned medicbag unit carries BOTH
-- the vanilla bag meshes and the tf_ Dispenser meshes (hidden by default via
-- the .object, so real doctor bags stay vanilla). On the prop WE spawn we hide
-- the vanilla set and show the tf_ set, so only the Engineer's dispenser reads
-- as the Dispenser. Same trick as the sentry skin, applied per-instance.
local DISP_TF_HIDE = { "g_medic_bag", "g_kit_2", "g_kit_3", "g_kit_4" }
local DISP_TF_SHOW = { "tf_g_medic_bag", "tf_g_kit_2", "tf_g_kit_3", "tf_g_kit_4" }

local function apply_dispenser_tf_skin(unit)
	if not alive(unit) then return end
	pcall(function()
		for _, name in ipairs(DISP_TF_HIDE) do
			local o = unit:get_object(Idstring(name)); if o then o:set_visibility(false) end
		end
		for _, name in ipairs(DISP_TF_SHOW) do
			local o = unit:get_object(Idstring(name)); if o then o:set_visibility(true) end
		end
	end)
end

-- ---- scrap economy --------------------------------------------------
EngineerDeck.SCRAP_MAX = 150
local DISPENSER_SCRAP_PER_TICK = 3
local UPGRADE_COST = { [2] = 40, [3] = 100 }

EngineerDeck.LEVELS = {
	[1] = { damage = 1.00, capacity = 1.00, fire = 1.00 },
	[2] = { damage = 1.10, capacity = 3.00, fire = 0.25 },
	[3] = { damage = 1.25, capacity = 10.00, fire = 0.08 },
}

function EngineerDeck.upgrade_cost(to_level) return UPGRADE_COST[to_level] end

function EngineerDeck.add_scrap(amount)
	if not amount or amount <= 0 then return end
	if not EngineerDeck.is_active(1) then return end
	EngineerDeck._scrap = math.min((EngineerDeck._scrap or 0) + amount, EngineerDeck.SCRAP_MAX)
end

function EngineerDeck.spend_scrap(amount)
	amount = amount or 0
	if (EngineerDeck._scrap or 0) >= amount then
		EngineerDeck._scrap = EngineerDeck._scrap - amount
		return true
	end
	return false
end

function EngineerDeck.scrap_percent()
	return math.floor(((EngineerDeck._scrap or 0) / EngineerDeck.SCRAP_MAX) * 100 + 0.5)
end

function EngineerDeck.get_sentry_level(unit)
	if not alive(unit) then return 1 end
	local lv
	pcall(function() lv = unit:base() and unit:base()._eng_level end)
	return lv or 1
end

function EngineerDeck.apply_sentry_level(unit, level)
	if not alive(unit) then return end
	local lv = EngineerDeck.LEVELS[level] or EngineerDeck.LEVELS[1]
	pcall(function() if unit:base() then unit:base()._eng_level = level end end)
	local w
	pcall(function() w = unit:weapon() end)
	if w then
		pcall(function()
			w._eng_base_damage = w._eng_base_damage or w._damage
			if w._eng_base_damage then w._damage = w._eng_base_damage * lv.damage end
			if w._ammo_max then
				w._eng_base_ammo_max = w._eng_base_ammo_max or w._ammo_max
				w._ammo_max = math.floor(w._eng_base_ammo_max * lv.capacity)
				if w._ammo_total then w._ammo_total = w._ammo_max end
			end
			w._eng_fire_mult = lv.fire
			local base_reduction = (w._use_armor_piercing and SentryGunWeapon and SentryGunWeapon._AP_ROUNDS_FIRE_RATE) or 1
			w._fire_rate_reduction = base_reduction * lv.fire
		end)
	end
	pcall(function() if unit:interaction() then unit:interaction():set_dirty(true) end end)
end

-- give a whole number of rounds to every weapon a unit carries, refresh HUD
local function give_ammo(unit, rounds)
	if not (alive(unit) and unit:inventory()) then return end
	local is_local = unit == managers.player:player_unit()
	for index, sel in pairs(unit:inventory():available_selections()) do
		pcall(function()
			local wb = sel.unit and alive(sel.unit) and sel.unit:base()
			if not wb then return end
			local ab = wb.ammo_base and wb:ammo_base() or wb
			if not (ab.get_ammo_total and ab.set_ammo_total and ab.get_ammo_max) then return end
			ab:set_ammo_total(math.min(ab:get_ammo_total() + rounds, ab:get_ammo_max()))
			if is_local and managers.hud and wb.selection_index and wb.ammo_info then
				pcall(function()
					managers.hud:set_ammo_amount(wb:selection_index(), wb:ammo_info())
				end)
			end
		end)
	end
end
EngineerDeck.give_ammo = give_ammo

-- ---- deck detection -------------------------------------------------
function EngineerDeck.tier()
	if not (managers.skilltree and EngineerDeck.spec_index) then return 0 end
	local cur = managers.skilltree:get_specialization_value("current_specialization")
	if cur ~= EngineerDeck.spec_index then return 0 end
	return managers.skilltree:get_specialization_value(cur, "tiers", "current_tier") or 0
end

function EngineerDeck.is_active(min_tier)
	if EngineerDeck.tier() == 0 then return false end
	return not min_tier or EngineerDeck.tier() >= min_tier
end

-- true if the Engineer deck is the currently equipped perk deck (any tier,
-- incl. menu). Used to gate the custom deployable's availability.
function EngineerDeck.is_current_deck()
	if not (managers.skilltree and EngineerDeck.spec_index) then return false end
	return managers.skilltree:get_specialization_value("current_specialization") == EngineerDeck.spec_index
end

-- true if the local player is standing in one of their Dispenser auras
function EngineerDeck.in_dispenser_zone()
	local u = managers.player and managers.player:player_unit()
	if not alive(u) then return false end
	local pos = u:position()
	for _, rec in ipairs(EngineerDeck._dispensers) do
		if mvector3.distance(pos, rec.pos) <= rec.radius then return true end
	end
	return false
end

-- ---- refund a sentry charge -----------------------------------------
function EngineerDeck.refund_deployable()
	pcall(function()
		local pm = managers.player
		local eq = pm and pm._equipment
		if not eq or not eq.selections then return end
		for index, sel in pairs(eq.selections) do
			if sel.equipment == "sentry_gun" or sel.equipment == "sentry_gun_silent" or sel.equipment == "eng_sentry_gun" then
				local cur = Application:digest_value(sel.amount[1], false)
				local newv = cur + 1
				sel.amount[1] = Application:digest_value(newv, true)
				pcall(function() managers.hud:set_item_amount(index, newv) end)
				pcall(function() pm:update_deployable_equipment_amount_to_peers(sel.equipment, newv) end)
				return
			end
		end
	end)
end

-- ---- frontier justice (card 7) --------------------------------------
function EngineerDeck.on_sentry_lost(kills)
	kills = tonumber(kills) or 0
	EngineerDeck._banked_kills = EngineerDeck._banked_kills + kills
	if not EngineerDeck.is_active(7) then return end
	give_ammo(managers.player:player_unit(), 30)
	EngineerDeck._surge_mul = 1 + math.min(EngineerDeck._banked_kills * SURGE_PER_KILL, 1.0)
	EngineerDeck._surge_until = TimerManager:game():time() + SURGE_TIME
	EngineerDeck._banked_kills = 0
end

-- ---- dispenser prop (visual marker only) ----------------------------
-- only spawn a unit that is actually LOADED for this heist; otherwise skip
-- (never force a load - that's what crashed on the ATM).
local function unit_loaded(path)
	local ok, has = pcall(function()
		return PackageManager and PackageManager.has and PackageManager:has(Idstring("unit"), Idstring(path))
	end)
	return ok and has == true
end

local function spawn_dispenser_prop(pos, rot)
	if not (World and World.spawn_unit and pos) then return nil end
	for _, path in ipairs(DISP_PROP_CANDIDATES) do
		if unit_loaded(path) then
			local u
			local ok = pcall(function()
				u = World:spawn_unit(Idstring(path), pos, rot or Rotation(0, 0, 0))
			end)
			if ok and alive(u) then
				-- cosmetic only: no interaction, no base update (we never setup() it)
				pcall(function() if u:interaction() and u:interaction().set_active then u:interaction():set_active(false) end end)
				pcall(function() u:set_extension_update_enabled(Idstring("base"), false) end)
				-- if it's our reskinned medicbag, flip it to the tf_ Dispenser meshes
				if path == MEDICBAG_PATH then apply_dispenser_tf_skin(u) end
				log("[EngineerDeck] dispenser prop spawned: " .. path)
				return u
			end
		end
	end
	log("[EngineerDeck] dispenser: no supply prop loaded this heist; aura + ring only")
	return nil
end

local function destroy_dispenser_record(rec)
	if not rec then return end
	rec.removed = true
	pcall(function() if alive(rec.unit) then rec.unit:set_slot(0) end end)
	rec.unit = nil
end

function EngineerDeck.deploy_dispenser(pos)
	if not pos then return end
	while #EngineerDeck._dispensers >= MAX_DISPENSERS do
		destroy_dispenser_record(table.remove(EngineerDeck._dispensers, 1))
	end
	local big = EngineerDeck.is_active(5)
	local rot
	pcall(function()
		local pu = managers.player:player_unit()
		if alive(pu) then rot = Rotation(pu:rotation():yaw(), 0, 0) end
	end)
	table.insert(EngineerDeck._dispensers, {
		pos = pos,
		radius = big and 700 or DISPENSER_RADIUS,
		next_tick = 0,
		unit = spawn_dispenser_prop(pos, rot),
		removed = false,
	})
	pcall(function()
		if managers.hud and managers.hud.show_hint then managers.hud:show_hint({ text = "Dispenser deployed" }) end
	end)
end

local function tick_dispensers(t)
	for i = #EngineerDeck._dispensers, 1, -1 do
		local rec = EngineerDeck._dispensers[i]
		if t >= rec.next_tick then
			rec.next_tick = t + TICK_INTERVAL
			pcall(function()
				local local_u = managers.player:player_unit()
				for _, u in ipairs(managers.player:players()) do
					if alive(u) and mvector3.distance(u:position(), rec.pos) <= rec.radius then
						local cd = u:character_damage()
						if cd and cd.restore_health then cd:restore_health(HEAL_RATIO, false) end
					end
				end
				if alive(local_u) and mvector3.distance(local_u:position(), rec.pos) <= rec.radius then
					give_ammo(local_u, AMMO_ROUNDS)
					EngineerDeck.add_scrap(DISPENSER_SCRAP_PER_TICK)
				end
			end)
		end
	end
end

-- ground ring marking the aura radius
local function draw_dispensers()
	if not (DRAW_RING and Draw) then return end
	pcall(function()
		local ring = Draw:brush(Color(0.6, 0.8, 1.0):with_alpha(0.06))
		for _, rec in ipairs(EngineerDeck._dispensers) do
			pcall(function() ring:disc(rec.pos + math.UP * 3, rec.radius, math.UP) end)
		end
	end)
end

-- ---- recall (card 9) ------------------------------------------------
function EngineerDeck.register_sentry(unit)
	if alive(unit) then table.insert(EngineerDeck._my_sentries, unit) end
end

function EngineerDeck.forget_sentry(unit)
	for i = #EngineerDeck._my_sentries, 1, -1 do
		if EngineerDeck._my_sentries[i] == unit then table.remove(EngineerDeck._my_sentries, i) end
	end
end

function EngineerDeck.recall_sentry()
	if not EngineerDeck.is_active(9) then return end
	local removed = 0
	for i = #EngineerDeck._my_sentries, 1, -1 do
		local u = EngineerDeck._my_sentries[i]
		if alive(u) then
			local kills = 0
			pcall(function() kills = (u:base().get_kills and u:base():get_kills()) or u:base()._kills or 0 end)
			EngineerDeck.on_sentry_lost(kills)
			EngineerDeck.refund_deployable()
			pcall(function() u:set_slot(0) end)
			removed = removed + 1
		end
		table.remove(EngineerDeck._my_sentries, i)
	end
	pcall(function()
		if managers.hud and managers.hud.show_hint then
			managers.hud:show_hint({ text = removed > 0 and "Sentry recalled" or "No sentry to recall" })
		end
	end)
end

-- ---- custom deployable availability ---------------------------------
-- Surface the "Engineer's Sentry" deployable in the loadout ONLY while the
-- Engineer deck is the equipped perk deck. availible_equipment returns the
-- list of selectable deployable ids; we append ours when the deck is current.
if PlayerManager.availible_equipment then
	local _eng_orig_availible_equipment = PlayerManager.availible_equipment
	function PlayerManager:availible_equipment(slot)
		local list = _eng_orig_availible_equipment(self, slot)
		pcall(function()
			if type(list) == "table" and EngineerDeck.is_current_deck() then
				if not table.contains(list, "eng_sentry_gun") then
					table.insert(list, "eng_sentry_gun")
				end
			end
		end)
		return list
	end
end

-- ---- driver tick ----------------------------------------------------
Hooks:PostHook(PlayerManager, "update", "EngineerDeck_Update", function(self, t, dt)
	if #EngineerDeck._dispensers > 0 then
		tick_dispensers(t)
		draw_dispensers()
	end
end)
