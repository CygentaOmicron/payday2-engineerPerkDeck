-- The Engineer - spawn the Dispenser field where the throwable lands.
-- Hooked onto ProjectileBase: when our cloned-frag dispenser impacts, drop a
-- heal field at the impact position. clbk_impact(tag, unit, body, other_unit,
-- other_body, position, ...) - position is arg #6.
EngineerDeck = EngineerDeck or {}

if ProjectileBase and ProjectileBase.clbk_impact then
	Hooks:PostHook(ProjectileBase, "clbk_impact", "EngineerDeck_DispenserImpact",
		function(self, tag, unit, body, other_unit, other_body, position, ...)
			if self._projectile_entry ~= "eng_dispenser" then return end
			if EngineerDeck.deploy_dispenser then
				EngineerDeck.deploy_dispenser(position or (alive(self._unit) and self._unit:position()))
			end
		end)
end
