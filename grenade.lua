-- =====================================================================
--  The Engineer - Dispenser throwable as a deck-granted, SWAPPABLE ability
--  (hooked onto BlackMarketManager)
-- =====================================================================
--  Previously we force-returned eng_dispenser from equipped_grenade /
--  equipped_projectile, which hijacked the throwable slot - you could never
--  pick a different throwable, and the menu couldn't treat it as an owned
--  grenade (so it showed locked). Vanilla ability decks (Stoic flask, Kingpin
--  injector, Sicario ECM) instead GRANT their ability throwable as a normal,
--  unlocked, swappable grenade and auto-equip it by default.
--
--  So we do the same: while the Engineer deck is equipped, eng_dispenser is
--  unlocked (selectable) and equipped by default; you can swap it for anything
--  and swap back. No getter override - when eng_dispenser is the equipped
--  grenade, the ability system + dispenser_throw.lua handle it normally.
--
--  -----------------------------------------------------------------
--  THROWABLE PERSISTENCE (the "plumbing")
--  -----------------------------------------------------------------
--  eng_dispenser is an ABILITY grenade, which the blackmarket unlocks LATE
--  during load. On startup the original aquire_default_weapons runs before our
--  unlock, finds no valid (unlocked) equipped throwable, and falls back to frag
--  - clobbering whatever you actually had equipped. The blackmarket's own save
--  can't be trusted to round-trip our pick, and frag is ambiguous (fallback vs
--  a deliberate choice), so we keep our OWN tiny save file recording the exact
--  throwable you last had while on the Engineer deck, and restore that pick on
--  load / deck-enter:
--
--    * save_throwable_choice / load_throwable_choice  <-> mods/saves JSON
--    * a PostHook on equip_grenade records your pick whenever you change it
--      WHILE on the deck (skipped during our own restore via _restoring).
--    * restore_deck_throwable() unlocks the Dispenser and equips the saved pick
--      (or defaults to the Dispenser the first time / if the pick is no longer
--      owned). It's used by BOTH the load hook here AND deck_swap.lua's enter
--      path, so booting into the deck and swapping into it behave identically.
--
--  set_current_specialization is NOT called on load (the deck is just restored
--  from save), so deck_swap.lua's enter path doesn't run on startup - the
--  aquire_default_weapons hook at the bottom is what restores you on boot.
-- =====================================================================

EngineerDeck = EngineerDeck or {}
EngineerDeck.dispenser_id = "eng_dispenser"
EngineerDeck._restoring = false      -- true while WE equip during a restore (suppresses the save hook)

local FALLBACK_GRENADE = "frag"

-- Capture mod-relative globals at load time. SavePath is SuperBLT's canonical
-- mods/saves dir (the docs' "mods/saves/save_data.json" is literally
-- SavePath .. "save_data.json"); fall back to the literal path / ModPath if a
-- weird context leaves it nil.
local SAVE_DIR  = SavePath or "mods/saves/"
local SAVE_FILE = SAVE_DIR .. "engineer_deck.json"

local function grenades_inv()
	return Global and Global.blackmarket_manager and Global.blackmarket_manager.grenades
end

-- ensure an inventory entry exists so the grenade can be unlocked/equipped
local function ensure_entry()
	local g = grenades_inv()
	if not g then return nil end
	if not g.eng_dispenser then
		g.eng_dispenser = { unlocked = false, equipped = false, amount = 1, skill_based = false, level = 0 }
	end
	return g.eng_dispenser
end

-- can this id actually be equipped right now? (the Dispenser once unlocked, or
-- any normally-owned grenade). Guards against a saved pick the player no longer
-- owns (e.g. a since-removed DLC throwable).
local function is_equippable(id)
	if not id then return false end
	if id == "eng_dispenser" then return true end
	local g = grenades_inv()
	local e = g and g[id]
	return (e and e.unlocked) and true or false
end

-- ---------------------------------------------------------------------
--  persistence: store / read the player's Engineer-deck throwable pick
-- ---------------------------------------------------------------------
function EngineerDeck.save_throwable_choice(id)
	if type(id) ~= "string" then return end
	pcall(function()
		if io and io.save_as_json then
			io.save_as_json({ throwable = id }, SAVE_FILE)
		end
	end)
end

function EngineerDeck.load_throwable_choice()
	local id = nil
	pcall(function()
		if io and io.load_as_json and (not io.file_is_readable or io.file_is_readable(SAVE_FILE)) then
			local data = io.load_as_json(SAVE_FILE)
			if type(data) == "table" and type(data.throwable) == "string" then
				id = data.throwable
			end
		end
	end)
	return id
end

-- ---------------------------------------------------------------------
--  unlock / re-lock the Dispenser grenade entry
-- ---------------------------------------------------------------------
function EngineerDeck.unlock_dispenser(on)
	pcall(function()
		local bm = managers.blackmarket
		local entry = ensure_entry()
		if not entry then return end
		if on then
			entry.unlocked = true
			entry.amount = entry.amount or 1
			-- official unlock API (handles menu bookkeeping); the flag above is the fallback
			if bm and bm.on_aquired_grenade then pcall(function() bm:on_aquired_grenade("eng_dispenser") end) end
		else
			-- revert to a normal grenade if the Dispenser is still equipped
			if bm and bm.equipped_grenade and bm.equip_grenade and bm:equipped_grenade() == "eng_dispenser" then
				bm:equip_grenade(FALLBACK_GRENADE)
			end
			-- re-lock via the flag only. (We deliberately DON'T call on_unaquired_grenade:
			-- that vanilla fn indexes data our lightweight entry doesn't carry and errors.)
			entry.unlocked = false
		end
	end)
end

-- still here for compatibility (test keybinds etc.); restore_deck_throwable is
-- the preferred entry point now.
function EngineerDeck.default_equip_dispenser()
	pcall(function()
		local bm = managers.blackmarket
		if bm and bm.equip_grenade then bm:equip_grenade("eng_dispenser") end
	end)
end

-- ---------------------------------------------------------------------
--  restore the saved deck throwable (load + deck-enter share this)
-- ---------------------------------------------------------------------
function EngineerDeck.restore_deck_throwable()
	local bm = managers.blackmarket
	if not bm or not bm.equip_grenade then return end
	EngineerDeck._restoring = true                 -- suppress the save hook for our own equip
	pcall(function()
		-- the Dispenser must be unlocked to be a valid equip target (and so it
		-- shows as selectable in the throwable list while on the deck)
		EngineerDeck.unlock_dispenser(true)
		local choice = EngineerDeck.load_throwable_choice()
		if not is_equippable(choice) then
			choice = "eng_dispenser"               -- first run, or saved pick no longer owned
		end
		bm:equip_grenade(choice)
	end)
	EngineerDeck._restoring = false
end

-- ---------------------------------------------------------------------
--  hooks
-- ---------------------------------------------------------------------

-- record the player's pick whenever they change throwable WHILE on the deck.
-- (skipped during our own restore, and while off the deck so we never overwrite
--  the saved Engineer pick with another deck's frag revert)
if BlackMarketManager and BlackMarketManager.equip_grenade then
	Hooks:PostHook(BlackMarketManager, "equip_grenade", "EngineerDeck_SaveThrowableChoice", function(self, grenade_id)
		pcall(function()
			if EngineerDeck._restoring then return end
			if grenade_id and EngineerDeck.is_current_deck and EngineerDeck.is_current_deck() then
				EngineerDeck.save_throwable_choice(grenade_id)
			end
		end)
	end)
end

-- load-time restore: when the Engineer deck is current as the blackmarket
-- finishes setting up, restore the saved throwable (or default to the Dispenser).
if BlackMarketManager and BlackMarketManager.aquire_default_weapons then
	Hooks:PostHook(BlackMarketManager, "aquire_default_weapons", "EngineerDeck_DispenserGrenadeSetup", function(self, ...)
		pcall(function()
			if EngineerDeck.is_current_deck and EngineerDeck.is_current_deck() then
				EngineerDeck.restore_deck_throwable()
			end
		end)
	end)
end
