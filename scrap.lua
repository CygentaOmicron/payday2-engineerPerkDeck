-- =====================================================================
--  The Engineer - scrap accrual  (hooked onto weapon ammo gains)
-- =====================================================================
--  Ammo you pick up is partly converted into Scrap (one-way): ammo-box
--  pickups (add_ammo) and ammo-bag use (add_ammo_from_bag) both raise the
--  weapon's ammo_total, so we measure the gain around each call and bank
--  a slice of it. The Dispenser also yields scrap (see engineer.lua).
--  Scrap is spent to level up sentries with the wrench (see wrench_repair.lua).
--
--  Gated to the deck being equipped. Tune SCRAP_PER_ROUND to taste.
-- =====================================================================

EngineerDeck = EngineerDeck or {}

local SCRAP_PER_ROUND = 1.0   -- scrap banked per round of ammo gained

-- Pre/Post around an ammo-gaining method: snapshot total, then bank the delta.
-- rawget so we only wrap the class that actually DEFINES the method (subclasses
-- that merely inherit it are covered automatically through the wrapped parent).
local function hook_gain(klass, method, tag)
	if not (klass and rawget(klass, method)) then return end
	Hooks:PreHook(klass, method, "EngineerDeck_ScrapPre_" .. tag, function(self, ...)
		self._eng_ammo_pre = nil
		pcall(function() if self.get_ammo_total then self._eng_ammo_pre = self:get_ammo_total() end end)
	end)
	Hooks:PostHook(klass, method, "EngineerDeck_ScrapPost_" .. tag, function(self, ...)
		pcall(function()
			if self._eng_ammo_pre and self.get_ammo_total
				and EngineerDeck.is_active and EngineerDeck.is_active(1) then
				local gained = self:get_ammo_total() - self._eng_ammo_pre
				if gained > 0 then EngineerDeck.add_scrap(gained * SCRAP_PER_ROUND) end
			end
			self._eng_ammo_pre = nil
		end)
	end)
end

hook_gain(RaycastWeaponBase,    "add_ammo",          "rwb_box")
hook_gain(RaycastWeaponBase,    "add_ammo_from_bag", "rwb_bag")
hook_gain(NewRaycastWeaponBase, "add_ammo",          "nrwb_box")
hook_gain(NewRaycastWeaponBase, "add_ammo_from_bag", "nrwb_bag")
