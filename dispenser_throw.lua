-- =====================================================================
--  The Engineer - Dispenser throwable  (hooked onto PlayerStandard)
-- =====================================================================
--  Ability throwables route through _check_action_use_ability, and using one
--  starts the game's single cooldown. We deploy ONLY when the game actually
--  consumes the ability this frame (grenade amount drops), so deploy and the
--  HUD cooldown stay in lockstep.
--
--  Using the ability was also costing weapon ammo (it could read negative),
--  so we snapshot the player's ammo right before activation and restore it
--  right after - the Dispenser costs nothing to use.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

local function grenade_amount()
	local n
	pcall(function()
		if not managers.player.get_grenade_amount then return end
		local sess = managers.network and managers.network:session()
		local pid = sess and sess:local_peer() and sess:local_peer():id()
		n = managers.player:get_grenade_amount(pid)
	end)
	return n
end

local function snapshot_ammo(unit)
	local snap = {}
	if not (alive(unit) and unit:inventory()) then return snap end
	for index, sel in pairs(unit:inventory():available_selections()) do
		pcall(function()
			local wb = sel.unit and alive(sel.unit) and sel.unit:base()
			local ab = wb and (wb.ammo_base and wb:ammo_base() or wb)
			if ab and ab.get_ammo_total then
				snap[index] = {
					wb = wb, ab = ab,
					total = ab:get_ammo_total(),
					clip = ab.get_ammo_remaining_in_clip and ab:get_ammo_remaining_in_clip() or nil,
				}
			end
		end)
	end
	return snap
end

local function restore_ammo(snap)
	for _, e in pairs(snap) do
		pcall(function()
			if e.ab.set_ammo_total then e.ab:set_ammo_total(e.total) end
			if e.clip and e.ab.set_ammo_remaining_in_clip then e.ab:set_ammo_remaining_in_clip(e.clip) end
			if managers.hud and e.wb.selection_index and e.wb.ammo_info then
				managers.hud:set_ammo_amount(e.wb:selection_index(), e.wb:ammo_info())
			end
		end)
	end
end

local function is_dispenser_active()
	return EngineerDeck.is_active and EngineerDeck.is_active(1)
		and managers.blackmarket:equipped_projectile() == (EngineerDeck.dispenser_id or "eng_dispenser")
end

if PlayerStandard and PlayerStandard._check_action_use_ability then
	local orig = PlayerStandard._check_action_use_ability
	function PlayerStandard:_check_action_use_ability(t, input, ...)
		local is_disp = is_dispenser_active()
		local before = is_disp and grenade_amount() or nil
		local snap = is_disp and snapshot_ammo(self._unit) or nil

		local r = orig(self, t, input, ...)

		pcall(function()
			if not is_disp then return end
			local after = grenade_amount()
			if before and after and before > after then
				-- ability was used this frame: undo any ammo cost, then deploy
				if snap then restore_ammo(snap) end
				local u = self._unit
				if alive(u) and EngineerDeck.deploy_dispenser then
					EngineerDeck.deploy_dispenser(u:position())
				end
			end
		end)

		return r
	end
end
