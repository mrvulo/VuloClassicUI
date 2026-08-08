## 1.52.5
**Arena:**
- Diminishing returns and interrupts recognise every rank of a spell. Both lists carried one identifier per spell, usually the one for rank one, so what is really cast at level seventy fell through: no icon for the polymorph, no bar for the kick. All ranks share their name, and the client knows the name behind every identifier already in the list, so one pass builds a name index that covers every rank at once, in the client's own language, which is the one the combat log speaks.

**Bar Setups:**
- Loading a setup asks first. It sets a hundred and twenty slots and empties the ones the setup has nothing for, and a single click in the dropdown was enough. The only warning, for a setup belonging to another class, was a chat line that arrived after the damage was done.
- Importing a setup leaves your own macros and keybindings alone. Macros are matched by name, and a name like Pull belongs to everyone, so a foreign setup replaced the contents of your own macro of that name with the switch on by default and without a word about it. Imported setups are marked as foreign now and keep what is already there, and the message says how many were kept. A backup entry carrying no keys at all no longer gets restored either, which used to clear the keys of that command and save the result.

**Character Panel:**
- The enchant text of a weapon sits above its slot. Beside a weapon there is the next weapon, and to the left the whole text column, so the line had nowhere to go; above the weapon row the paper doll is empty. It is centred over its own slot and wraps upward, so two enchanted weapons no longer write across each other.
- The enchant text of the wrist slot sits under its slot instead of beside it. The wrist is the last slot of the left column, and to the right of it lies the weapon row, which is where the line was writing.
- The question before overwriting a gem is only armed once the dialog is really standing. If one was already open the client reuses it, and rebuilding it cleared the note that had just been made, so the second question answered nothing at all and said nothing about it. The recheck now compares the item as well, and an open window on its own no longer counts as proof that it is the right one.
- The item level of a piece the client has not cached yet appears once it arrives. The retry ran into the very gate that had excluded it and drew nothing, ever. It is capped at twenty attempts per item so it cannot turn into a loop that runs every tenth of a second.

**Cooldown Manager:**
- Deleting an entry removes the one you clicked. It went by the position the row was built with, and the list is rewritten behind the open page whenever the trinket matching adds or removes entries after an equipment change, so the neighbour disappeared instead.

**Edit Mode:**
- Logging in no longer opens the edit mode behind your back. Restoring frame positions used to apply the layout by showing the client's own edit mode manager, and that rebuilds every system the editor owns out of our call stack, which hands them to the addon for the rest of the session. Measured in game: one such call three seconds after login, and twenty seconds later 1593 refused actions in combat, party and raid frames among them. The layout is still written, and the client applies it the next time it does so itself. A frame you drag by hand still settles immediately.
- A frame dropped after a fight has started keeps the spot you dropped it at. A drag can only begin out of combat but it can end in one, and letting go wrote the anchor onto a protected frame without asking. The position was already saved by then, so the saved value and the frame on screen would have disagreed for the rest of the session. The write now waits for the fight to end and is made good afterwards.

**Fishing:**
- The client settings the fishing mode borrows survive a crash. The backup of your own values lived in memory only, so a reload, a disconnect or a crash while fishing mode was running took it along, and music, ambience, auto loot and soft targeting stayed on the fishing values for good with nothing left anywhere to say what they had been.

**General:**
- Switching the camera zoom option off returns the zoom to the client's default. The comment promised as much and the code did nothing of the sort, so with the option already on from an earlier session there was no value of ours to fall back to and the maximum stayed for every session after. It is only reset while the value still is our maximum, so anything you have set yourself since then stays.
- Unit tooltips no longer throw a Lua error on a unit without an identifier. The fallback one line above did the arithmetic on the missing identifier itself and handed the result to the very call that cannot take it.

**Loadouts:**
- A set finds its own piece when two items share an identifier, the way the owl's ring and the bear's ring do. Sets store the full reference but searched by the bare identifier; the search goes by identifier and suffix now, while enchants and gems stay out of it because those change during an item's life and would make a set report its own piece as missing.

**Nameplates:**
- The name comes back after a cast the same way the interrupt flash already decides it. A retired field was still being asked, although the options page says it is read nowhere any more.
- The click area of a plate returns to its measured size. The value that means the client's own size was only right as long as the setter had never run, so afterwards the old area stood until a reload and the sliders went up without ever coming back.

**Profession Window:**
- **NEW: Search field in the enchanting window** – Leaves only the recipes whose name or reagents match what you type
- The enchanting window is the one profession window that never had a search box. The field sits between the title and the slot dropdown: type into it and only the recipes whose name or one of their reagents matches stay, with the scroll bar shortening along with the list instead of leaving empty rows under the last hit. Recipes you starred still float to the top of what is left, and closing the window clears the text — otherwise the next visit would open on a list with most of the recipes missing and nothing on screen to explain it.

**Profiles:**
- An installation from before the schema stamp runs its migrations instead of skipping them. No stamp meant two opposite things, a fresh installation with nothing to migrate or one older than the stamp with everything still pending, and both were stamped current and skipped, so the older one silently lost every migration, its bar setups in their old storage place among them. The two are told apart now by whether there is any module data at all.

**Slot Picker:**
- The strip for the weapon slots opens downward instead of sideways. The three weapons are the only slots standing in a row rather than a column, at the bottom of the paper doll, where sideways always runs into their own neighbour. It grows away from the middle of the screen so it cannot pass the near edge, and it tips upward when the window sits at the bottom of the screen.
- A click in the picker can no longer hit whatever has moved into that bag slot in the meantime. It remembered bag and slot from the moment it was filled and listened to no bag event, so after a sort run a click hit what was lying there by then, which with a merchant window open would have been a sale. It follows bag changes now, and every click checks the item in place against the one the button was built for.

**Trinkets:**
- The merchant lock covers both trinket slots. A mixed-up condition left it applying to the lower one only.

**Unit Frames:**
- The addon no longer stamps the client's own health text and target classification with its taint. Both called the client's updaters from our call stack, the very thing the same file forbids two hundred lines further down in writing and with a reason, which makes the client's next pass over those frames unsafe. Both write what they need themselves now. The standard border returns the moment the client next classifies your target.
