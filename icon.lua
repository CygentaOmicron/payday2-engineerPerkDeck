-- =====================================================================
--  The Engineer - placeholder menu icon for the Dispenser throwable
-- =====================================================================
--  The throwables menu builds a grenade's icon path straight from its id
--  (guis/textures/pd2/blackmarket/icons/grenades/<id>), so our custom
--  eng_dispenser shows no icon. We register a placeholder .texture at that
--  path via BeardLib's File Manager (textures "don't need load", so simply
--  registering makes the icon resolve everywhere the menu builds that path).
--
--  PLACEHOLDER: points at a cooked texture we already ship (an ATM prop
--  diffuse) purely so the slot isn't blank - it WILL look like a tiny ATM.
--  To use a real icon later, drop your own cooked .texture somewhere in the
--  mod and change SRC below to point at it (or tell me and I'll switch it).
-- =====================================================================

if BeardLib and BeardLib.Managers and BeardLib.Managers.File then
	local DB_PATH = "guis/textures/pd2/blackmarket/icons/grenades/eng_dispenser"
	local SRC = ModPath .. "Stuff/gen_prop_bank_atm_standing/gen_prop_bank_atm_standing_df.texture"
	pcall(function()
		BeardLib.Managers.File:AddFile("texture", DB_PATH, SRC)
	end)
end
