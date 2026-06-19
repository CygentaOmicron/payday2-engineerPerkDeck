local text_original = LocalizationManager.text
function LocalizationManager:text(string_id, ...)
return string_id == "all_2" and "Helmet Popping"
or string_id =="all_2_desc" and "Increases your headshot damage by ##25%##."
or string_id =="all_4" and "Blending In"
or string_id =="all_4_desc" and "You gain ##+1## increased concealment.\n\nWhen wearing armor, your movement speed is ##15%## less affected. \n\nYou gain ##45%## more experience when you complete days and jobs."
or string_id =="all_6" and "Walk-in Closet"
or string_id =="all_6_desc" and "Unlocks an armor bag equipment for you to use. The armor bag can be used to change your armor during a heist.\n\nIncreases your ammo pickup to ##135%## of the normal rate. "
or string_id =="all_8" and "Fast and Furious"
or string_id =="all_8_desc" and "You do ##5%## more damage. Does not apply to melee damage, throwables, grenade launchers and the HRL-7 Rocket Launcher.\n\nIncreases your doctor bag interaction speed by ##20%##. "

or string_id == "Joat_title" and "Jack of all trades"
or string_id == "Joat_desc" and "Jack of all trades, master of none\nYou are a heister that is competent with many skills, but no particular one."
or string_id == "Joat_1" and "Bullet-Time"
or string_id == "Joat_1_desc" and "Your impressive speed enables you to dodge incomming bullets.\n\nYou gain ##25%## dodge chance."
or string_id == "Joat_3" and "Junkie"
or string_id == "Joat_3_desc" and "Your keen eye detects more ammunition on dead enemies.\n\nYou pickup ##25%## more ammo.\n\nDoes not stack with fully loaded."
or string_id == "Joat_5" and "Wolverine"
or string_id == "Joat_5_desc" and "Your experience in the battlefield has taught you to endure more pain, and heal your own wounds over time.\n\nYour health is increased by ##15%##.\nYour armor is increased by ##15%##.\nYou regenerate ##5%## health per ##4## seconds."
or string_id == "Joat_7" and "Agent 47"
or string_id == "Joat_7_desc" and "Nobody will notice, if there's nobody to notice.\nYou carry more body bags and bag bodies faster.\n\nYou gain ##+1## body bag.\nYou bag bodies ##15%## faster."
or string_id == "Joat_9" and "Thief"
or string_id == "Joat_9_desc" and "Your nimble fingers and silver tounge makes you able to pick locks and answer pagers faster.\nYour ninja like movement makes it easier to avoid detection.\n\nYou pick locks ##15%## faster.\nYou answer pagers ##10%## faster.\nYou gain ##+2## increased concealment.\n\nDeck Completion Bonus: Your chance of getting a higher quality item during a PAYDAY is increased by ##10%##."

or text_original(self, string_id, ...)
end