-- =========================================================
-- VuloClassicUI / Modules / ChangelogData
-- AUTO-GENERATED from CHANGELOG.md by tools/gen_changelog.js.
-- Do NOT edit by hand — edit CHANGELOG.md and re-run the generator.
-- =========================================================
local _, ns = ...

ns.CHANGELOG = {
    { version = "1.60.0", sections = {
        { category = "Combat Meter", lines = {
            "NEW: Combat Meter – A lightweight damage and healing meter as its own HUD module: who did how much, per fight and overall",
            "The engine reads your own combat log and counts, per group member, damage, healing, damage taken, interrupts, dispels and deaths, with a per-ability breakdown behind each. Pets, totems and guardians credit their owner, overhealing stays apart from effective healing, and a feigning hunter is not a death. A fight is group-wide: it opens on your own combat or on the first damage a group member deals, takes the boss name from the encounter events, and closes once nobody in the group is fighting any more. The overall total survives a reload and starts fresh when you join a new group.",
            "The bars come in class colours with the class icon, rank and name on the left and the total with the per-second value in brackets on the right. Hovering a bar lists the strongest abilities with icon, value and share; the interrupt and dispel modes list what was stopped or removed, and the death mode lists each death with its time and killing blow. Left-click on the title opens the menu, the mouse wheel on the title cycles the eight modes, the wheel over the bars scrolls, the gear opens the options. Right-drag the title to move a window, resize it in edit mode.",
            "Open as many windows as you need: the title menu adds a window for any mode and closes one again, and every window keeps its own mode, segment, position and size while the look and the visibility rules are shared. The padlock in the title bar frees a window for dragging or pins it in place, and the anchor entry in the title menu docks a window to any side of another so the two move as one.",
            "Options cover bar height, font size, texture, the class icon, how many abilities the tooltip lists, which parts of the bar text to show, the visibility rules (only in a group, in combat, out of combat with a delay) and the window list.",
        } },
        { category = "Languages", lines = {
            "Patch notes of versions that have left the in-game list are gone from all nine languages; nothing the interface shows was affected.",
        } },
    } },
    { version = "1.59.0", sections = {
        { category = "Languages", lines = {
            "Texts that nothing in the interface looks up any more are gone from all nine languages: option labels from before the nameplate options were rebuilt, and patch notes of versions that have left the in-game list.",
        } },
        { category = "Nameplates", lines = {
            "Aura icons no longer flicker. Every aura event on a unit rebuilt each icon from scratch, so the countdown went blank until the next tick, the expiry pulse snapped back to full, and the cooldown sweep restarted. An icon now keeps its state until a genuinely different aura takes its place, and a new aura shows its number in the same frame it appears.",
        } },
        { category = "Trackbars", lines = {
            "NEW: Broker plugin – A block that shows another addon's data object with its icon and text, reacts to clicks and shows its tooltip, with switches to strip the plugin's color codes and cap the width",
        } },
    } },
    { version = "1.58.3", sections = {
        { category = "Loadouts", lines = {
            "The icon picker offers the client's complete icon library in a mouse-wheel scrollable grid; the automatic choice and the set's own pieces stay in front.",
            "Stripping pieces into the bags claims an empty slot for every piece before anything moves, so switching to a set with bare slots no longer fails with red bag-is-full errors from stale free-space counts or special bags that cannot hold armor.",
        } },
        { category = "Nameplates", lines = {
            "NEW: Show level – The unit's level at the name's left edge, colored by difficulty, with an elite and rare tag, text size and offsets behind its gear",
            "NEW: Growth direction – Decide where an aura row extends as more icons arrive: left or right for a horizontal row, up or down for a column beside the plate",
        } },
    } },
    { version = "1.58.2", sections = {
        { category = "Loadouts", lines = {
            "Empty slots are now part of a set: saving records deliberately bare slots, and equipping strips those pieces into the bags, with a single notice when the bags are too full. Sets saved before this change keep their old behavior, so save a set once more to pick up its empty slots.",
        } },
    } },
    { version = "1.58.1", sections = {
        { category = "Character Panel", lines = {
            "The resistance tooltips now rate the value: how much matching spell damage you resist on average against boss enemies, by the game's own formula, plus a colored verdict from Low to Maximum.",
        } },
        { category = "Loadouts", lines = {
            "Two copies of the same item that differ only in their gems or enchants now swap correctly when switching sets. A regemmed single copy still counts as equipped and is never reported missing. If a set was saved before the gems went in, save it once more while wearing the right copy.",
        } },
        { category = "Performance", lines = {
            "A sweep over thirteen files cuts memory churn and idle work in hot paths: timer texts only rebuild when their value changes, the trinket queue checks once per second instead of every frame, the arena binds its aura events per zone, and the dark skin, bags, tooltips and class trackers reuse what they already computed.",
        } },
    } },
    { version = "1.58.0", sections = {
        { category = "Trackbars", lines = {
            "NEW: Trackbars – Build your own info bars from blocks: clock, gold, XP, latency, micro menu and more",
            "Bars are created from templates: start empty, a full-width info bar pinned to the top or bottom edge, a compact minimap companion, or a micro menu strip. Every bar stays fully editable afterwards.",
            "Ten blocks to stack and order: clock, gold, XP and reputation, FPS, latency, durability, free bag slots, zone with coordinates, micro menu, and a spacer.",
            "The gold block tracks what the current session earned and spent, and its tooltip lists the gold of every character on the account, richest first.",
            "The XP block renders a real progress bar with the rested bonus overlaid, and a right-click switches it to the tracked reputation.",
            "The micro menu opens the spellbook, talents and friends through the game's own buttons, so it works safely in combat and never blocks spell casting.",
            "The module ships disabled: switch it on under HUD in the options window.",
        } },
    } },
    { version = "1.57.1", sections = {
        { category = "Action Bars", lines = {
            "The form-paging section shows up in Standard mode too. The switch itself already reached the standard main bar; the row that flips it was only drawn in Modern mode, so nobody running the standard bars could find it.",
        } },
        { category = "Performance", lines = {
            "Seven hot paths allocate less memory: unit-frame health text, nameplate number formatting and health smoothing, cooldown-manager scan keys, combat-text throttling, bag refreshes, the arena bar-text hook and the reminder pass all reuse what they used to rebuild, so the garbage collector has less to clean up in combat.",
        } },
        { category = "UI Reskin", lines = {
            "The red auto-attack blink sits on the icon in every button style now, the untouched standard button included. The game defines that blink with retail-sized frame art and a single corner anchor, so on the classic button art it hung past the button to the right and bottom.",
        } },
    } },
    { version = "1.57.0", sections = {
        { category = "Bags & Bank", lines = {
            "NEW: Item counts in tooltips – Item tooltips show how many you carry in your bags and how many sit in the bank, as last seen at a banker",
            "The bank mirror is taken on every banker visit now, with the default bank window and with the bags module switched off alike; it used to fill only while the replacement window was on.",
        } },
        { category = "Character Panel", lines = {
            "The melee section shows expertise the way the game's own sheet does, with both weapons when dual wielding; the tooltip names the dodge and parry reduction in percent along with the rating. Only on clients whose game has the stat.",
        } },
        { category = "Global Settings", lines = {
            "NEW: Module Fonts – Give single modules their own font: action bars, nameplates, cooldown manager, chat and the stats sheet each take a face of their own, everything else follows the global font",
            "Fonts and colors live on two separate tabs now; the class and resource colors moved to their own Colors tab unchanged.",
            "An imported look string carries the module fonts along, and the action bar buttons keep the game's own lettering until a module font is chosen for them.",
        } },
    } },
    { version = "1.56.0", sections = {
        { category = "Action Bars", lines = {
            "Keeping the main bar on its page in every form now also holds the standard main bar, even while the whole module is off. The keys fire exactly what the buttons show, and switching to bars 2 to 6 by hand still works.",
        } },
        { category = "Character Panel", lines = {
            "The stats sheet shows resilience under Defense, with the rating and its percent effect in the tooltip.",
            "The enchant text on the equipment slots no longer falls onto the green armor line of pieces with built-in bonus armor; that line only stands in when no real enchant follows.",
        } },
        { category = "Loadouts", lines = {
            "NEW: Helm / Cloak – Each set can show, hide or leave untouched the helm and the cloak as it is equipped, chosen in the row's right-click menu, and the row tooltip names the choice",
            "The set rows can be reordered with the left mouse button held down: a translucent ghost follows the pointer, a line in the accent colour marks where the row will land, and letting go outside the list cancels. Existing sets keep their alphabetical order as the starting point, new ones join at the end.",
        } },
        { category = "UI Reskin", lines = {
            "The red auto-attack blink sits exactly on the icon in the skinned button styles and is cut to the same shape; it used to be drawn for the standard button art and blinked beside the icon.",
            "Popup dialogs measure their frame with the font that is really drawn; with long texts the buttons used to hang below the border.",
        } },
    } },
    { version = "1.55.0", sections = {
        { category = "Action Bars", lines = {
            "Switching the module off now hands the micro buttons and the bag buttons back to their exact Blizzard positions, and a dialog offers the reload right away; the addon's row layout used to survive into the default bars until the next reload.",
        } },
        { category = "Cooldown Manager", lines = {
            "NEW: Sound when ready – Every icon can announce the end of its cooldown with a sound from the shared media list, auditioned right in the menu with every click",
            "NEW: Custom icon... – Any entry can wear an icon of your choice, named by spell or item ID or a texture path",
            "Right-clicking an icon in the preview strip opens a settings menu for that one entry: glow while ready with its own colour, the ready flash, the dimming, the cooldown swipe and the countdown text can each override the bar's setting, and the glow editor, parking and removing live in the same place. Removing is no longer the bare right-click itself, so a stray click cannot shorten the bar.",
        } },
        { category = "General", lines = {
            "Long popup menus, the module list on the minimap button among them, now show a window that scrolls with the mouse wheel instead of growing past the screen edge.",
        } },
    } },
    { version = "1.54.0", sections = {
        { category = "Action Ring", lines = {
            "NEW: Action Ring – Hold a keybind to open a ring of actions, aim at an entry and release to use it, spells, items and macros alike, in and out of combat",
            "Choose between a ring, a grid and a mouse-wheel strip, run up to 16 rings with their own keys, entries and look, and start from ready-made templates such as raid marks, teleports, potions or shapeshifts.",
            "The options page shows a live preview of the selected ring that redraws while you drag a slider, and a plus button right in the picture adds entries.",
        } },
        { category = "Cooldown Manager", lines = {
            "NEW: Colour while a swing attack is queued – The resource bar shows a colour of your choice while an on-next-swing attack waits for the hit, so you can see that the resource is already spoken for",
        } },
        { category = "Nameplates", lines = {
            "The low-health glow now reaches further past the plate and rounds its corners more generously; before, it hugged the frame so tightly that it read as a border instead of a glow.",
            "The glow texture changed on disk, so it takes one full client restart to show its new shape; a reload is not enough.",
        } },
        { category = "Swing Timer", lines = {
            "The bar colour opens a full colour picker instead of a short list of presets; existing profiles keep the colour they had.",
        } },
    } },
    { version = "1.53.0", sections = {
        { category = "Character Panel", lines = {
            "Every row of the stats sheet now explains itself when you point at it, and spell haste has joined the sheet.",
        } },
        { category = "Global Settings", lines = {
            "Custom class colours moved into the addon's own colour book. Writing them into the client's shared tables marked the party and raid frames as touched by the addon at every login, and the client then refused to resize them in combat. The clean-up has a price: the client's own windows and other addons show the standard class colours again, while the custom ones colour everything this addon draws.",
        } },
        { category = "Nameplates", lines = {
            "NEW: Edit spell lists – Every aura row carries an always-show and a never-show spell ID list, kept in its own editing window behind the slot's fine tuning",
            "NEW: Low-health glow – Marks plates below a chosen health percentage, as a thin ring or a soft pulsing glow, in a colour of your choice",
            "The pulsing glow ships as a new texture file, so it takes one full client restart to appear; a reload is not enough.",
        } },
        { category = "Paladin", lines = {
            "The seal-twist helper no longer counts a swing ahead on parries or when attacking starts; its window used to point at a swing that never came.",
        } },
        { category = "Profiles", lines = {
            "The import preview no longer sits on top of the paste step of the import dialog.",
        } },
        { category = "Swing Timer", lines = {
            "The clock keeps ticking through abilities that replace the swing, Heroic Strike and Cleave among them: they write their own combat log line instead of a swing line, so the bar used to stand still exactly for the classes that queue such an ability on every swing.",
            "Swing-resetting spells that deal no damage, parried special attacks and extra attacks now reach the clock too.",
        } },
        { category = "UI Reskin", lines = {
            "NEW: WeakAuras style – A separate icon style for WeakAuras, independent of the action bars, with five Shadow aura sets",
            "NEW: Border color – Tints the frame of the Shadow and shape styles; resetting it restores each style's built-in colouring",
            "The bar style now starts at Blizzard's own untouched look, and the masked shapes circle, square and hexagon bring their own frames.",
        } },
    } },
    { version = "1.52.6", sections = {
        { category = "Cooldown Manager", lines = {
            "NEW: X Offset / Y Offset – Nudge the stack and reagent numbers away from their chosen corner; both sit behind the gear of the position row",
        } },
        { category = "Edit Mode", lines = {
            "Opening Edit Mode no longer hands the party and raid frames to the addon for the rest of the session. Merely opening it drove the client's frame editor through the addon, and in combat the client then refused to update those frames, naming the addon in the message. Only really moving one of Blizzard's frames still writes to the editor, and a frame that is hidden, like the focus frame while nothing is focused, never does.",
            "Opening Edit Mode closes the options window. It sat exactly on top of the boxes it had just unlocked.",
        } },
        { category = "Loadouts", lines = {
            "The equipment list steps aside for the rune engraving panel. That panel opens on the right side of the character sheet, exactly where the list docks, so the two stood on top of each other. The list now follows the panel's edge, and where the screen is too narrow for sheet, panel and list together, it moves to the left side of the sheet.",
        } },
        { category = "Nameplates", lines = {
            "The role fix ships switched off. What it fixes is a silent error that truncates one update when a nameplate appears; what it costs is that the party and raid frames count as touched by the addon for the whole session and refuse to resize in combat, with the addon named in the message. That price was reaching players who never chose it, so now only whoever switches the fix on pays it.",
            "The status line of the role fix tells the whole truth. With the fix off it used to claim it was not needed on this client, even for players who do have the error; it now says whether the fix is applied, not needed, or simply not switched on while the error is firing.",
        } },
        { category = "Power Bar", lines = {
            "The bar ships switched off. A second resource bar is a strong opinion to hand someone who never asked for one, and the client already draws its own. Installations that already exist keep the bar exactly as it was.",
        } },
        { category = "UI Reskin", lines = {
            "The dark skin keeps Blizzard's rim off the stance buttons for good. Their updates write the button art back directly, past the hook that guards the action bars, so the rim used to return the first time you switched.",
        } },
    } },
    { version = "1.52.5", sections = {
        { category = "Arena", lines = {
            "Diminishing returns and interrupts recognise every rank of a spell. Both lists carried one identifier per spell, usually the one for rank one, so what is really cast at level seventy fell through: no icon for the polymorph, no bar for the kick. All ranks share their name, and the client knows the name behind every identifier already in the list, so one pass builds a name index that covers every rank at once, in the client's own language, which is the one the combat log speaks.",
        } },
        { category = "Bar Setups", lines = {
            "Loading a setup asks first. It sets a hundred and twenty slots and empties the ones the setup has nothing for, and a single click in the dropdown was enough. The only warning, for a setup belonging to another class, was a chat line that arrived after the damage was done.",
            "Importing a setup leaves your own macros and keybindings alone. Macros are matched by name, and a name like Pull belongs to everyone, so a foreign setup replaced the contents of your own macro of that name with the switch on by default and without a word about it. Imported setups are marked as foreign now and keep what is already there, and the message says how many were kept. A backup entry carrying no keys at all no longer gets restored either, which used to clear the keys of that command and save the result.",
        } },
        { category = "Character Panel", lines = {
            "The enchant text of a weapon sits above its slot. Beside a weapon there is the next weapon, and to the left the whole text column, so the line had nowhere to go; above the weapon row the paper doll is empty. It is centred over its own slot and wraps upward, so two enchanted weapons no longer write across each other.",
            "The enchant text of the wrist slot sits under its slot instead of beside it. The wrist is the last slot of the left column, and to the right of it lies the weapon row, which is where the line was writing.",
            "The question before overwriting a gem is only armed once the dialog is really standing. If one was already open the client reuses it, and rebuilding it cleared the note that had just been made, so the second question answered nothing at all and said nothing about it. The recheck now compares the item as well, and an open window on its own no longer counts as proof that it is the right one.",
            "The item level of a piece the client has not cached yet appears once it arrives. The retry ran into the very gate that had excluded it and drew nothing, ever. It is capped at twenty attempts per item so it cannot turn into a loop that runs every tenth of a second.",
        } },
        { category = "Cooldown Manager", lines = {
            "Deleting an entry removes the one you clicked. It went by the position the row was built with, and the list is rewritten behind the open page whenever the trinket matching adds or removes entries after an equipment change, so the neighbour disappeared instead.",
        } },
        { category = "Edit Mode", lines = {
            "Logging in no longer opens the edit mode behind your back. Restoring frame positions used to apply the layout by showing the client's own edit mode manager, and that rebuilds every system the editor owns out of our call stack, which hands them to the addon for the rest of the session. Measured in game: one such call three seconds after login, and twenty seconds later 1593 refused actions in combat, party and raid frames among them. The layout is still written, and the client applies it the next time it does so itself. A frame you drag by hand still settles immediately.",
            "A frame dropped after a fight has started keeps the spot you dropped it at. A drag can only begin out of combat but it can end in one, and letting go wrote the anchor onto a protected frame without asking. The position was already saved by then, so the saved value and the frame on screen would have disagreed for the rest of the session. The write now waits for the fight to end and is made good afterwards.",
        } },
        { category = "Fishing", lines = {
            "The client settings the fishing mode borrows survive a crash. The backup of your own values lived in memory only, so a reload, a disconnect or a crash while fishing mode was running took it along, and music, ambience, auto loot and soft targeting stayed on the fishing values for good with nothing left anywhere to say what they had been.",
        } },
        { category = "General", lines = {
            "Switching the camera zoom option off returns the zoom to the client's default. The comment promised as much and the code did nothing of the sort, so with the option already on from an earlier session there was no value of ours to fall back to and the maximum stayed for every session after. It is only reset while the value still is our maximum, so anything you have set yourself since then stays.",
            "Unit tooltips no longer throw a Lua error on a unit without an identifier. The fallback one line above did the arithmetic on the missing identifier itself and handed the result to the very call that cannot take it.",
        } },
        { category = "Loadouts", lines = {
            "A set finds its own piece when two items share an identifier, the way the owl's ring and the bear's ring do. Sets store the full reference but searched by the bare identifier; the search goes by identifier and suffix now, while enchants and gems stay out of it because those change during an item's life and would make a set report its own piece as missing.",
        } },
        { category = "Nameplates", lines = {
            "The name comes back after a cast the same way the interrupt flash already decides it. A retired field was still being asked, although the options page says it is read nowhere any more.",
            "The click area of a plate returns to its measured size. The value that means the client's own size was only right as long as the setter had never run, so afterwards the old area stood until a reload and the sliders went up without ever coming back.",
        } },
        { category = "Profession Window", lines = {
            "NEW: Search field in the enchanting window – Leaves only the recipes whose name or reagents match what you type",
            "The enchanting window is the one profession window that never had a search box. The field sits between the title and the slot dropdown: type into it and only the recipes whose name or one of their reagents matches stay, with the scroll bar shortening along with the list instead of leaving empty rows under the last hit. Recipes you starred still float to the top of what is left, and closing the window clears the text — otherwise the next visit would open on a list with most of the recipes missing and nothing on screen to explain it.",
        } },
        { category = "Profiles", lines = {
            "An installation from before the schema stamp runs its migrations instead of skipping them. No stamp meant two opposite things, a fresh installation with nothing to migrate or one older than the stamp with everything still pending, and both were stamped current and skipped, so the older one silently lost every migration, its bar setups in their old storage place among them. The two are told apart now by whether there is any module data at all.",
        } },
        { category = "Slot Picker", lines = {
            "The strip for the weapon slots opens downward instead of sideways. The three weapons are the only slots standing in a row rather than a column, at the bottom of the paper doll, where sideways always runs into their own neighbour. It grows away from the middle of the screen so it cannot pass the near edge, and it tips upward when the window sits at the bottom of the screen.",
            "A click in the picker can no longer hit whatever has moved into that bag slot in the meantime. It remembered bag and slot from the moment it was filled and listened to no bag event, so after a sort run a click hit what was lying there by then, which with a merchant window open would have been a sale. It follows bag changes now, and every click checks the item in place against the one the button was built for.",
        } },
        { category = "Trinkets", lines = {
            "The merchant lock covers both trinket slots. A mixed-up condition left it applying to the lower one only.",
        } },
        { category = "Unit Frames", lines = {
            "The addon no longer stamps the client's own health text and target classification with its taint. Both called the client's updaters from our call stack, the very thing the same file forbids two hundred lines further down in writing and with a reason, which makes the client's next pass over those frames unsafe. Both write what they need themselves now. The standard border returns the moment the client next classifies your target.",
        } },
    } },
    { version = "1.52.4", sections = {
        { category = "Character Panel", lines = {
            "NEW: Ask before overwriting a gem – A click on a socket that already holds a gem asks first, because putting a gem in destroys the one that comes out",
            "Pointing at an occupied socket says what a click on it costs. Clicking one was always allowed, nothing ever said so, and the gem that comes out is destroyed. The question names both gems in their quality colours, and it drops the action when the gear moved while it was standing — otherwise a swap under the open dialog would answer for a socket you never looked at.",
        } },
        { category = "Loadouts", lines = {
            "Equipping a set at the bank takes the pieces that are lying in the bank, as long as the bank window is open. Until now they counted as missing, so you could stand at the bank and be told the set was not equippable. The message says how many of them came out of the bank, and the piece that comes off goes into the bank slot the new one came from. With the bank closed, a missing piece in there no longer only names its place, it says to open the bank window.",
            "The line that tells you which sets an item belongs to appears in item tooltips. It was built and hooked up from the start, but it went in through the one tooltip mechanism this client offers and never uses, so no line was ever drawn and nothing complained.",
        } },
        { category = "Nameplates", lines = {
            "NEW: Reverse the swipe – The shade grows back as the aura runs out, so a nearly clear icon means it is nearly gone",
            "The cooldown swipe on the aura icons has a control of its own. It was read from the start and could not be changed anywhere.",
            "The raid target marker is visible at all. The eight marks live on one sheet, and the call that picks a tile out of it was working on a frame that never got the sheet — a cut-out of nothing, on every plate and in the preview, since the module was built.",
            "The raid target marker takes one of the six named slots, like the four aura rows. It had three positions of its own and could land on top of a row, which is the very collision the slots exist for. The old choice moves into the matching slot once and then goes, so there is no second control for the same question. Its room is reserved as soon as it is switched on, not only once a unit really carries a mark, so the rows do not jump every time somebody sets a skull.",
            "The marker's own offset and spacing sliders take effect again. They were writing two fields of their own while the plate read the slot, so the visible control was the one without an effect. The old values move across once.",
            "A mark set between two aura passes lands where it belongs. Where the marker goes is worked out in the aura pass, because only that knows how far the rows on its side reach, and the plate now remembers that point for the event that shows the marker on its own.",
            "The cast time and the cast target show something in the preview. Both only exist for a cast that is really running on a real unit, so both stayed empty while their switches, colours and side settings stood next to them with nothing to show.",
        } },
    } },
    { version = "1.52.3", sections = {
        { category = "Nameplates", lines = {
            "NEW: Match the health bar height – Makes the crowd-control icon a square exactly as tall as the health bar, in place of its own size sliders",
            "NEW: Border around aura icons – Switches the rim around debuff, damage-over-time, buff and crowd-control icons on or off, with its colour beside it",
            "NEW: Text size – Sets how large the unit name and the health value are drawn, in the panel behind each of those two rows",
            "A long unit name is trimmed with three dots instead of running through the health value. The two share the bar as soon as both sit inside it, so the name now gets the width that is actually free — and only a health value at the other end takes room away, because sharing one slot is something you did on purpose. Only a name that would overflow is capped at all, which is what keeps the level number glued to the name instead of hanging off an oversized box.",
            "The aura border can also take the colour of the aura's own school. That switch was read from the start and had no control anywhere.",
        } },
        { category = "Settings Window", lines = {
            "NEW: Settings Window Scale – Scales this settings window on its own, from 70 to 130 per cent, while the game's interface keeps the size it has",
            "Making the window smaller now gives it back its full size on a screen that was cutting it off. The fitting measured the room in the game's units and the window in its own, so scaling it down changed nothing about what it was allowed to be.",
        } },
    } },
    { version = "1.52.2", sections = {
        { category = "Action Bars", lines = {
            "Casting out of the spell book keeps working after the book was opened from the micro menu. Our micro buttons are stand-ins that hand the click on to the default button behind them, which runs everything that follows inside our own call — and for the spell book that ends in the book writing down which half of itself it is showing. That note then counted as ours, the book reads it on every click on a spell, and so every cast from the book was refused as coming from an addon. Out of combat as well, for the rest of the session, until the interface was reloaded. Opening the book by its key was never affected. The micro menu now carries the default button itself, wearing our icon, so nothing is handed through us any more.",
        } },
        { category = "Bags", lines = {
            "Pointing at a bag slot shows the tooltip of the bag itself — quality colour, how much it holds, everything the item carries — with the click hints under it, instead of the bare name. In the inventory window as well as at the bank, which had drifted apart although the two bars are the same thing.",
            "The bar in the inventory window takes bags now, the way the one at the bank already did: drag a bag onto a slot to put it there, or left-click a slot with a bag on the cursor. Right-click with an empty hand takes the bag off again, and left-click with an empty hand still shows and hides it. The backpack and the keyring are not slotted bags, so they accept nothing and are not offered the right-click line in the first place.",
        } },
        { category = "Character Panel", lines = {
            "The enchant on the wrist slot sits closer to the rows around it, and the enchant on the weapon sits six pixels lower.",
        } },
        { category = "Trainer", lines = {
            "The trainer tab is a button of its own now. It used to be a spare tab of the spell book that we wrote on with every update, and the book reads those tabs back in the middle of its own pass. It also goes away with the pet book, where it used to stay behind.",
        } },
    } },
    { version = "1.52.1", sections = {
        { category = "Action Bars", lines = {
            "NEW: Keep the main bar on its page in every form – Cat, bear, stealth, stances and Shadowform stop swapping action bar 1 to a page of their own",
            "The ticker that paints cooldown dimming and range colouring no longer walks switched-off bars. It read and repainted every action bar five times a second, including the ones whose buttons nobody can see, so running two bars cost as much as running all of them.",
            "Leaving a button no longer builds a fresh check each time. The check only ever reads the bar, not the button, so it is built once per bar and shared by all of its buttons.",
        } },
        { category = "Arena", lines = {
            "The opponent frames are left alone unless you actually asked for a different arrangement. They are protected frames: anchoring one from our side is allowed outside a fight, but it marks the frame for the rest of the session, and the next time the default interface repositions it during a round its own call is refused and the block is reported against us. There is no way to anchor a protected frame without leaving that mark, so an untouched setup now keeps the default stacking. Order, spacing, grow direction and slot offsets all still work — the message becomes the price of a feature you asked for rather than something every arena hands out for free.",
        } },
        { category = "Bags", lines = {
            "Move up and move down work again on a category you switched off and back on. The order list was filled once, while it was still empty, so anything that did not exist at that moment never got an entry, and its arrows then did nothing at all for the rest of the session without saying so.",
        } },
        { category = "Under the hood", lines = {
            "Switching a module off releases its event handlers again. The note recording which module owns a handler stayed behind when the handler was unregistered, and that note kept a hard reference to every handler the module had ever registered.",
        } },
    } },
    { version = "1.52.0", sections = {
        { category = "Chat", lines = {
            "The own background for the input line is offered on every client. It was limited to one client generation, and the code already said it would work everywhere.",
        } },
        { category = "Cooldown Manager", lines = {
            "The icon borders are pixel-exact. The border there is not a texture of its own but the rim of a plate behind the icon, so the two have to sit on the same pixel grid, the thickness has to be counted in pixels rather than frame units, and the icon size and spacing have to begin on whole pixels. None of the three was true, which is why a rim came out two pixels on one edge and none on the opposite.",
        } },
        { category = "Nameplates", lines = {
            "NEW: Apply this arrangement – Puts the unit name and the health value inside the bar, crowd control left of it, incoming debuffs above that and buffs to its right, with the cast bar carrying its icon, its remaining time and its target",
            "The unit name was hidden behind the health bar fill as soon as a text slot put it inside the bar. The name and the health value hang from different parents: the value is created on the bar, the name on the plate, and the bar is a child of the plate — so it draws over anything the plate draws. While the name only ever sat above the bar this never showed. It has its own layer now, above the bar but not attached to it, because name-only mode hides that bar and a text parented to a hidden frame would go with it.",
            "The health text has its controls back: what it shows, and which mark goes between the two numbers. Both were still being read and had been unreachable since the page was rebuilt.",
        } },
        { category = "Talent Window", lines = {
            "The active talent group was always reported as the first one on clients that do not carry the newer interface for it. Everything behind that believed group one was running: the header called the group you were standing in not active, the activate button offered to switch to the one already on, and the switch reported success while changing nothing. Five files ask that same question, so profile overrides and bar setups were reading it too.",
            "The glyph page stands permanently beside the window. It is lifted out of Blizzard's talent frame, where it lives inside the scroll area of the very window we replace, and handed back when ours closes.",
            "The separate glyph button is gone with it. Its only job was to send you to the page that now stands in front of you.",
            "A band under the header carries the activate button and the name of the talent group on screen. Until now switching existed only as a right-click on the small side icons, and nothing announced it.",
        } },
    } },
    { version = "1.51.0", sections = {
        { category = "Character Panel", lines = {
            "NEW: Socket strip under the window – A row of every socket on your equipped gear, hung under the character window; click a socket to put a gem from your bags into it",
            "The enchant text on armour slots reads the enchant again instead of the item's difficulty tag. The filter took the first green line of the tooltip, and where an item carries a tag that tag stands above the enchant — so every such slot showed the tag, while a weapon two rows down showed its enchant correctly because nothing stood in front of it. The tag and the client's bracketed hints are both recognised now, in every language rather than only in English and German.",
        } },
        { category = "Loadouts", lines = {
            "The set list no longer casts a shadow past its own frame. What looked like the background standing out over the border was a drop shadow: not an outline but four filled rectangles reaching up to seven pixels beyond the frame on every side, and behind Blizzard's dialog frame there was nothing for it to fall on. It is gone in both looks.",
            "In the Classic+ look the dark ground stopped short of the ornate line instead of ending on it, and so showed past the frame on every side.",
        } },
    } },
    { version = "1.50.0", sections = {
        { category = "Bar Setups", lines = {
            "NEW: Export as string – Packs the selected setup into a string you can pass on, with its slots, macros and key bindings",
            "NEW: Import from string – Reads someone else's setup into your library; a name you already use gets a number rather than being overwritten",
            "An imported setup is rebuilt entry by entry before it is stored. The restore walks every entry, so a malformed one would have thrown in the middle of a run with part of your bars already changed. Broken entries are dropped, the rest still arrives.",
            "Saving and loading say what they did. Both had been counting their work all along and throwing the numbers away, so a setup whose macros all failed looked exactly like one that had none, and a save that captured no key bindings said nothing at all.",
        } },
        { category = "Edit Mode", lines = {
            "The character window can be placed by hand on the Wrath client. Blizzard's editor does not own that window, so it takes the same direct route the loot window already uses; one box moves the character, reputation and skills tabs together, and the stats panel and set list travel with it.",
        } },
        { category = "Friends List", lines = {
            "The window starts wide on the Wrath client. The slider has always gone to 400 — it simply started at nothing, so the extra room only ever reached whoever went looking for it.",
        } },
        { category = "Talent Window", lines = {
            "The glyph page opens from a button under the talent group buttons, and it is dark now. The rune circle is dimmed rather than removed, because it is what makes that page recognisable; the sockets take the accent colour, and the glyph artwork and the pickup highlight stay as they are.",
            "The talent group button shows its tree's icon instead of a question mark. It asked for that icon through an interface that does not answer on every client, and fell back to the placeholder; the answer is now worked out from the ranks themselves, which cannot be misread.",
        } },
        { category = "Unit Frames", lines = {
            "The level number on the player frame sits where the client puts it on the Wrath client. Our two anchors are measured against one frame sheet, and where a different one ships, the number landed beside the portrait — the client keeps that anchor itself there anyway, moving it as the rest and PvP icons come and go.",
        } },
    } },
    { version = "1.49.0", sections = {
        { category = "Action Bars", lines = {
            "NEW: Hide The Gryphons – Takes the two beasts off the ends of Blizzard's main bar without dimming anything else",
        } },
        { category = "Arena Frames", lines = {
            "Switching the module off now switches it off. Its handlers are registered when the addon loads, so a module that was already off at login never ran its shutdown: being stunned in a battleground still popped the loss-of-control display, and the interrupt bar filled up and never emptied again, because the ticker that clears its icons only starts when the module is switched on.",
            "The interrupt bar no longer reads the whole world's combat log. It registered on load and never unregistered, so every combat line anywhere — several thousand a second in a raid — was taken apart for a bar whose own default is arena and battlegrounds only. It uses the same zone filter as the display beside it now.",
            "Switching the module on inside an arena counts as arriving. The zone decision used to live in the loading screen alone, so anyone who enabled it while already in there got no diminishing-returns ticker until the next one.",
        } },
        { category = "Character Panel", lines = {
            "The item level text size slider works again. It looked for the numbers in two places it hoped they would be, and where a client parents its paper doll buttons elsewhere it found none and quietly did nothing — which from the outside is indistinguishable from the text simply being too small.",
        } },
        { category = "Chat", lines = {
            "NEW: Input Line Above The Chat – Puts the input line over the message area instead of under it, with the panel and the tab bar following it; Wrath client only",
            "NEW: Own Background For The Input Line – Draws the input line on its own dark background instead of Blizzard's, which is what you saw once the dark panel was off; Wrath client only",
        } },
        { category = "Cooldown Manager", lines = {
            "Icon zoom is now called Icon crop and reads in percent. It is the same question the nameplate sliders ask, and it was answering in hundredths while they answered in percent.",
        } },
        { category = "Friends List", lines = {
            "The extra width belongs to the friends tab alone now. The row texts there stretch with the window, but the column headers on the who, guild and raid tabs sit at fixed offsets and stay put, so every point of width you added landed in an empty right half. Those three tabs go back to Blizzard's own proportions, which is what their columns were measured for.",
        } },
        { category = "Loadouts", lines = {
            "The set list and the icon picker take the character panel's style. In the classic style they used to be a flat dark surface with a purple edge holding Blizzard's red buttons — two materials in a hand's width. They now carry Blizzard's dialog frame there and stand in the same material as the window they hang off, while the modern style keeps the flat look.",
            "The character panel no longer breaks when the sidebar builds its first set row. The marker bar on the row still reached for an accent colour that had been removed, so the list stayed empty and the panel came up bare.",
        } },
        { category = "Minimap", lines = {
            "NEW: Addon Buttons – Choose where other addons' buttons sit: around the map, hidden until you mouse over it, or gathered in one box below it; Wrath client only",
        } },
        { category = "Nameplates", lines = {
            "NEW: Icon Crop (%) – How much of the border the game bakes into its icons is cut away, set per aura row and for the cast bar icon",
            "The rounded bar style no longer leaves dead space at both ends. The round shape does not fill its own image — a transparent border runs all the way round it — and stretching that border across a wide, short bar put roughly eleven points of empty bar at each end and barely one above and below, which is why it showed up sideways and not upright.",
            "The options page is cut by question instead of by mechanism. Sixteen sections had settings that belong together lying far apart, with the bar texture under one heading and the cast bar's texture under another; eight settings were reachable from two sections at once.",
            "Every text on the plate sits in a slot now, the way the aura rows already did: top, left, right or centred, filled with the unit name or the health text. Four on/off switches became position pickers, each starting on the place its text already had.",
            "The stacking dropdown had no readable value at all. It was reading a setting this client does not have; the one it does have is now read and written, measured in the running game.",
        } },
        { category = "Options", lines = {
            "A gear icon on a half-width row opens a small floating window instead of unfolding inside the cell. Half a cell has no room for a slider, and six of them had been squeezed into stubs.",
            "Colour swatches, eyes, gears and arrows sit directly beside the control they belong to rather than in the icon strip on the right, which stays reserved for the gear and the info dot.",
        } },
        { category = "Profession Window", lines = {
            "On the Wrath client the module stands down completely and the client keeps its own window. Our restyle addresses Blizzard's widgets by name and by region number, and behind those names that client has a different anatomy: black holes where the hidden regions used to be, a stretched title bar, dropdowns over the recipe list — and no error, because nothing throws, it simply lands on the wrong widgets.",
        } },
        { category = "Talent Window", lines = {
            "Talent group buttons run down the right edge, one for each group you have bought. Left-click shows a group, right-click activates it, the same split Blizzard's own window uses. Talents can only be learned in the active group, so a click in the preview does nothing and the tooltip says so beforehand.",
        } },
        { category = "Trainer", lines = {
            "The tab carries a book instead of a question mark. That mark is Blizzard's placeholder for a missing icon and read like a defect.",
        } },
    } },
    { version = "1.48.0", sections = {
        { category = "Arena", lines = {
            "NEW: Loss of Control – Shows the stun, fear, root, silence or lockout holding you, with its icon, its name and the time left",
            "NEW: Interrupts – Tracks enemy interrupts from the combat log, one icon per caster, bordered in the caster's class colour",
            "NEW: Timer Text On The Icons – Seconds left on the interrupt icons, with their own font, outline and colour",
            "NEW: Cooldown Swipe On The Icons – Drop the sweeping shade and keep only the number",
            "The icon strip beside the enemy frames has a live preview on the General tab. Those frames exist only inside an arena, so its sliders used to move something you could not see.",
            "An unlocked mover box no longer vanished a moment after the button put it there. The box and a running preview now ignore the zone filter: you place a bar where you are standing, and that is rarely an arena.",
        } },
        { category = "Cooldown Manager", lines = {
            "The pinned icon strip also appears on the Layout tab, where icon size, spacing, shape and zoom read back off it while the slider moves.",
        } },
        { category = "Edit Mode", lines = {
            "Moving Blizzard frames no longer marks every Edit Mode window as touched by this addon, which had the pet frame refused in combat. Selecting a layout caused it, and that ran on every editor entry even when nothing had been placed.",
        } },
        { category = "Equipment Sets", lines = {
            "The icon picker has a close button, and no longer floats over the game after the character sheet is shut.",
        } },
        { category = "Fishing", lines = {
            "NEW: Only Take Over The Key While A Fishing Pole Is Worn – Without a pole the key keeps whatever you bound it to",
        } },
        { category = "Options Window", lines = {
            "The mouse wheel scrolls the sidebar and the page. The window also shrinks to fit a screen smaller than itself, which is what left it undraggable on a high interface scale.",
        } },
        { category = "Profiles", lines = {
            "NEW: Profile Keybind – Put a profile on a key and switch to it out of combat",
        } },
        { category = "Reminders", lines = {
            "The bag sweep behind the food, flask and weapon oil reminders is kept until the bags change, instead of walking every bag three times over twice a second.",
        } },
        { category = "Unit Frames", lines = {
            "The modern player frame style no longer reaches into the pet and totem frames.",
        } },
    } },
    { version = "1.47.0", sections = {
        { category = "Edit Mode", lines = {
            "The boxes now cover their window exactly, in the same dark look as the rest of the interface, with the name centred and shown in orange when the window is docked to another one",
            "Outside the editor the small drag handle stays, so an unlocked cooldown bar still accepts dropped spells and test previews stay visible",
        } },
        { category = "Languages", lines = {
            "The cloak equipment slot was translated with the navigation word for back in six languages and now reads correctly everywhere",
        } },
        { category = "Nameplates", lines = {
            "NEW: Pixel-true plate size – Sizes the plates in screen pixels, so height 27 is 27 pixels on any monitor and interface scale",
            "Plate sizes now mean exactly what the sliders say: the game no longer secretly enlarges the target's plate or shrinks distant ones, and the live preview matches the game — making the target larger is now solely the job of the target plate scale option",
        } },
        { category = "Profiles", lines = {
            "NEW: Save a backup copy – One click keeps a dated copy of the active profile as a restore point",
            "Exporting opens a proper window with the string already selected, and importing shows a preview first: rename the profile and untick the parts you do not want before anything is written",
            "Export strings are compressed to a fraction of their old length and fit in a chat message; strings from older versions still import",
        } },
        { category = "Talent Window", lines = {
            "On the Wrath client the talent tooltip showed a placeholder instead of the description, and the talent key would open the window but not close it — both fixed",
        } },
    } },
    { version = "1.46.0", sections = {
        { category = "Action Bars", lines = {
            "The page opens with two modes: Standard keeps Blizzard's bars with the skin rows, Modern runs the addon's own bars with a live preview, a per-bar background, button press and hover tints and an XP bar texture",
        } },
        { category = "Cast Bar", lines = {
            "NEW: Modern – Third player cast bar style: flat look with name and timer on the bar, plus bar texture, border, a coloured last tick and a latency readout",
            "The options page carries a live preview; clicking its icon or bar jumps to the matching section",
        } },
        { category = "Character Panel", lines = {
            "Enchant and gem displays no longer displace each other on non-English clients, and Chinese enchant text is no longer cut mid-character",
        } },
        { category = "Cooldown Manager", lines = {
            "Tracked entries sit two per row, each with a gear: park an entry without deleting it, move or remove it, set conditions, and override Only what I cast myself for that entry alone",
        } },
        { category = "Edit Mode", lines = {
            "NEW: See-through – Hides the box fill and labels while editing, so you can see the interface you are aligning",
            "Coordinates appear on the box while dragging or nudging, and the window being snapped to pulses white",
            "The loot window can be moved on Wrath clients",
        } },
        { category = "Friends List", lines = {
            "NEW: Widen window – Extra width so long names, notes and zones fit on one line",
        } },
        { category = "General", lines = {
            "The close glyph of every window is larger now",
        } },
        { category = "Nameplates", lines = {
            "Three tabs with a pinned live preview, a name-in-bar option and thousands separators on health numbers",
        } },
        { category = "Options", lines = {
            "Gear rows open inside their own column, aura rows align per row, helper tools share one tab, and the pinned page header of the last visited tab is cleared on switching",
        } },
        { category = "Patch Notes", lines = {
            "Only the last five versions build at once; a button loads the older ones",
        } },
        { category = "Power Bar", lines = {
            "Orientation, fill opacity, frame strata and a live preview on the options page",
        } },
        { category = "Profiles", lines = {
            "A profile string can carry a selection: chosen modules, the window layout, talent overrides, and the account-wide fonts and colours",
        } },
        { category = "Reminders", lines = {
            "Per-rule switches with class-coloured names, a group scan for missing buffs, preferred food, flask and weapon oil, raid and dungeon thresholds, glow styles, scale and a live preview; middle-click hides a reminder until the next loading screen",
        } },
        { category = "Settings", lines = {
            "Broken numeric values are removed before saving and reported at the next login. A single such value used to reset every setting of the account to defaults",
        } },
        { category = "Shaman", lines = {
            "Totemic Recall stands as its own button after the elements on Wrath clients",
        } },
        { category = "Talents", lines = {
            "NEW: Talent Window – All three talent trees side by side with live ranks and click-to-learn on Wrath clients; glyphs stay one button away",
        } },
    } },
}
