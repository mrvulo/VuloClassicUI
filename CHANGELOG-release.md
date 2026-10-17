## 1.62.1
**Action Ring:**
- A ring set up right before a pull could fire its old contents for the whole fight. The update now waits for the fight to end instead of getting lost, and raid marker entries only take a real marker number.

**Arena:**
- Shadow Sight and range fading kept running for the rest of the session when the module was switched off inside an arena, and the Shadow Sight timer no longer starts in battlegrounds.

**Auras:**
- Buffs and debuffs that appear for the first time in a fight now show at full size with their icon right away, instead of staying invisible until the fight ended. Switching the module off and on within one fight no longer leaves the rows hidden.

**Bar Setups:**
- A bar setup imported from a string now shows the macros it would create and the keys it would bind before it is loaded the first time, and only applies them when you tick them. Imported setups no longer carry key bindings that run macros, clicks, spells or items. Your own saved setups load as before.

**Cast History:**
- Pressing a key during the global cooldown or while already casting no longer adds a red icon.

**Chat:**
- Timestamps could not be switched off again after a reload; they now go back to your own setting. Turning off class-coloured names restores what each chat type had before, instead of switching it off everywhere.

**Combat Meter:**
- The bar tooltip shows the spec again; it had been missing all along. A report to chat sends at most as many lines as the option allows.

**Combat Text:**
- Switching the module or its font options off now gives the game's own combat text fonts back.

**Cooldown Manager:**
- Changing options while the module was switched off put a frozen bar on the screen until the next reload.

**Edit Mode:**
- After switching profiles without a reload, moving a window saved its position into the profile you had just left. It now lands in the active profile, for list bars and the game's own frames too, and Discard returns to the active profile's layout.
- A closed meter window or a deleted trackbar no longer leaves an empty box behind.

**Extras:**
- The disenchant window can no longer be opened in combat, where it was blocked, and closing it in a fight takes effect when the fight ends.
- Hidden key, macro and stack texts on the action buttons stay hidden; they came back whenever the game refreshed its bindings.
- Switching the module off brings error messages and zone text back.
- Hovering another player no longer replaces the gear of the player you are inspecting.
- The bank material count for professions is no longer wiped when the bank closes.

**Fishing:**
- Equipping the pole, applying a lure and using the extra items went through a button form this client does not fire; the button now uses the form that it does. The key is only rebound when its target changes instead of three times a second, and switching fishing off in combat frees the key once the fight ends.

**Friends List:**
- Auto-accepting a group invite from a friend sent a decline right after accepting.

**Global Settings:**
- The UI scale can no longer be changed in combat, where the game blocked it.

**Languages:**
- Notes of versions that dropped out of the patch notes list were removed from all language files.

**Loadouts:**
- A set with two identical items, such as the same weapon twice or a pair of rings, equipped only one of them and still reported both as swapped.

**Minimap:**
- Switching the minimap button off now removes it right away, and the button tray no longer rearranges other buttons in combat.

**Nameplates:**
- Border around the cast bar could not be switched back on once it was off.
- Switching the module off gives back the game's nameplate scale settings and only shows the nameplates it hid itself.

**Paladin:**
- The seal twist bar threw errors after a profile switch without a reload.

**Performance:**
- The combat log is read once per line for all modules together instead of once per module, and nameplates now redraw only what actually changed on threat, aura and health updates.

**Player Castbar:**
- The game's own cast bar comes back when the module is switched off or set to the default look, instead of staying gone until a reload.

**Power Bar:**
- Unlocking and locking the bar while the module was off left an empty bar on the screen.

**Profiles:**
- Macro texts in an imported profile string, such as custom action ring commands and fishing extras, are listed in the preview and only imported when you tick them. The auto-accept switches for friend requests, group invites, summons and resurrection always keep your own setting, and damaged or oversized strings are refused.
- Select all in the export no longer includes fonts and colours.

**Reminders:**
- Changing the scale or layer of the reminders in combat now applies after the fight instead of being blocked.

**Settings Window:**
- Escape closes an open menu first and the window only on the next press.
- A dropdown no longer writes into another row when the page rebuilds after a choice, and an open menu closes with the rebuild.
- Greyed-out rows block all their buttons and still show their tooltip, and a typo in a number field keeps the old value.

**Shaman:**
- The totem bar threw errors after a profile switch without a reload, and switching the class tools in combat is applied after the fight instead of being blocked.

**Slot Picker:**
- An open picker no longer switches to another slot when the mouse passes over it, and switching the module off closes it.

**Talent Overrides:**
- Rows with the same name on one page, such as several offset sliders, now each keep their own override. Existing overrides are carried over to every row they used to change.
- Overrides wait for the end of the fight when a reload, a zone change or a talent switch happens in combat.

**Trackbars:**
- Bars with a hearthstone, profession or micro menu block no longer cause blocked actions in combat; their layout updates after the fight.

**Trinkets:**
- The trinket slash command, the size slider and the show option no longer cause blocked actions in combat.
- Switching the module off stops the automatic trinket swaps, and opening its options no longer flashes the trinket menu.
- The charges line in the small tooltips and the engineering check no longer depend on the English client.

**Under the hood:**
- The addon no longer stores its own data on the game's frames, one of the ways its code could get blamed for blocked actions.

**Unit Frames:**
- The health text on the target frame follows the game's status text setting again.
