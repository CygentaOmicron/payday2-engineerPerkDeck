-- The Engineer - Frontier Justice damage surge (card 7).
-- Hooked onto NewRaycastWeaponBase. While the surge is active, scale the
-- local player's outgoing weapon damage by EngineerDeck._surge_mul.
-- fire(from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit)
EngineerDeck = EngineerDeck or {}

if NewRaycastWeaponBase and NewRaycastWeaponBase.fire then
	local orig_fire = NewRaycastWeaponBase.fire
	function NewRaycastWeaponBase:fire(from_pos, direction, dmg_mul, ...)
		local until_t = EngineerDeck._surge_until
		if until_t and TimerManager:game():time() < until_t then
			local user = self._setup and self._setup.user_unit
			if user and managers.player and user == managers.player:player_unit() then
				dmg_mul = (dmg_mul or 1) * (EngineerDeck._surge_mul or 1)
			end
		end
		return orig_fire(self, from_pos, direction, dmg_mul, ...)
	end
end
