-- =====================================================================
--  The Engineer - survivability  (hooked onto PlayerDamage)
-- =====================================================================
--  The Engineer is a defensive "hold the line" deck, so it gains flat damage
--  resistance that scales as you invest (even cards, tiers 2/4/6/8), plus a
--  bonus while standing in your own Dispenser field. Implemented by trimming
--  incoming attack_data.damage - no fragile upgrade-value keys involved.
--
--  Tune the numbers below to taste. DR is capped so it never trivialises play.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

local DR_BY_TIER = { [2] = 0.10, [4] = 0.18, [6] = 0.25, [8] = 0.30 } -- cumulative target at each tier
local DISPENSER_BONUS = 0.12   -- extra DR while in your own Dispenser field
local DR_CAP          = 0.50   -- hard ceiling on total damage resistance

local function current_dr()
	local tier = EngineerDeck.tier and EngineerDeck.tier() or 0
	if tier < 2 then return 0 end
	local dr = 0
	for t, v in pairs(DR_BY_TIER) do
		if tier >= t then dr = math.max(dr, v) end
	end
	if EngineerDeck.in_dispenser_zone and EngineerDeck.in_dispenser_zone() then
		dr = dr + DISPENSER_BONUS
	end
	return math.min(dr, DR_CAP)
end

local function reduce(self, attack_data)
	if not (attack_data and attack_data.damage) then return end
	local dr = current_dr()
	if dr > 0 then
		attack_data.damage = attack_data.damage * (1 - dr)
	end
end

if PlayerDamage then
	for _, fn in ipairs({ "damage_bullet", "damage_explosion", "damage_melee", "damage_fire", "damage_killzone" }) do
		if PlayerDamage[fn] then
			Hooks:PreHook(PlayerDamage, fn, "EngineerDeck_DR_" .. fn, reduce)
		end
	end
end
