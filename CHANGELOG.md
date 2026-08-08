# VuloClassicUI — Changelog

<!--
  HOW THIS WORKS
  On every `v*` tag, .github/workflows/discord.yml posts the TOP "## <version>"
  section below to the Discord changelog channel (with the @updates role ping).
  For each release: add a NEW "## <version>" block at the very top, in this style:

  ## 1.17.0
  **Category:**
  - **NEW:** a brand-new feature.
  - a change or fix.

  Category labels are bold (**...:**), items are "- " bullets, and "**NEW:**"
  marks additions. Discord renders this markdown as-is. Keep a version under
  ~1900 characters or it gets truncated with a link to the full notes.
-->

## 1.52.5
**Character Panel:**
- The enchant text of the wrist slot sits under its slot instead of beside it. The wrist is the last slot of the left column, and to the right of it lies the weapon row, which is where the line was writing.

**Profession Window:**
- **NEW: Search field in the enchanting window** – Leaves only the recipes whose name or reagents match what you type
- The enchanting window is the one profession window that never had a search box. The field sits between the title and the slot dropdown: type into it and only the recipes whose name or one of their reagents matches stay, with the scroll bar shortening along with the list instead of leaving empty rows under the last hit. Recipes you starred still float to the top of what is left, and closing the window clears the text — otherwise the next visit would open on a list with most of the recipes missing and nothing on screen to explain it.

## 1.52.4
**Character Panel:**
- **NEW: Ask before overwriting a gem** – A click on a socket that already holds a gem asks first, because putting a gem in destroys the one that comes out
- Pointing at an occupied socket says what a click on it costs. Clicking one was always allowed, nothing ever said so, and the gem that comes out is destroyed. The question names both gems in their quality colours, and it drops the action when the gear moved while it was standing — otherwise a swap under the open dialog would answer for a socket you never looked at.

**Loadouts:**
- Equipping a set at the bank takes the pieces that are lying in the bank, as long as the bank window is open. Until now they counted as missing, so you could stand at the bank and be told the set was not equippable. The message says how many of them came out of the bank, and the piece that comes off goes into the bank slot the new one came from. With the bank closed, a missing piece in there no longer only names its place, it says to open the bank window.
- The line that tells you which sets an item belongs to appears in item tooltips. It was built and hooked up from the start, but it went in through the one tooltip mechanism this client offers and never uses, so no line was ever drawn and nothing complained.

**Nameplates:**
- **NEW: Reverse the swipe** – The shade grows back as the aura runs out, so a nearly clear icon means it is nearly gone
- The cooldown swipe on the aura icons has a control of its own. It was read from the start and could not be changed anywhere.
- The raid target marker is visible at all. The eight marks live on one sheet, and the call that picks a tile out of it was working on a frame that never got the sheet — a cut-out of nothing, on every plate and in the preview, since the module was built.
- The raid target marker takes one of the six named slots, like the four aura rows. It had three positions of its own and could land on top of a row, which is the very collision the slots exist for. The old choice moves into the matching slot once and then goes, so there is no second control for the same question. Its room is reserved as soon as it is switched on, not only once a unit really carries a mark, so the rows do not jump every time somebody sets a skull.
- The marker's own offset and spacing sliders take effect again. They were writing two fields of their own while the plate read the slot, so the visible control was the one without an effect. The old values move across once.
- A mark set between two aura passes lands where it belongs. Where the marker goes is worked out in the aura pass, because only that knows how far the rows on its side reach, and the plate now remembers that point for the event that shows the marker on its own.
- The cast time and the cast target show something in the preview. Both only exist for a cast that is really running on a real unit, so both stayed empty while their switches, colours and side settings stood next to them with nothing to show.

## 1.52.3
**Nameplates:**
- **NEW: Match the health bar height** – Makes the crowd-control icon a square exactly as tall as the health bar, in place of its own size sliders
- **NEW: Border around aura icons** – Switches the rim around debuff, damage-over-time, buff and crowd-control icons on or off, with its colour beside it
- **NEW: Text size** – Sets how large the unit name and the health value are drawn, in the panel behind each of those two rows
- A long unit name is trimmed with three dots instead of running through the health value. The two share the bar as soon as both sit inside it, so the name now gets the width that is actually free — and only a health value at the other end takes room away, because sharing one slot is something you did on purpose. Only a name that would overflow is capped at all, which is what keeps the level number glued to the name instead of hanging off an oversized box.
- The aura border can also take the colour of the aura's own school. That switch was read from the start and had no control anywhere.

**Settings Window:**
- **NEW: Settings Window Scale** – Scales this settings window on its own, from 70 to 130 per cent, while the game's interface keeps the size it has
- Making the window smaller now gives it back its full size on a screen that was cutting it off. The fitting measured the room in the game's units and the window in its own, so scaling it down changed nothing about what it was allowed to be.

## 1.52.2
**Action Bars:**
- Casting out of the spell book keeps working after the book was opened from the micro menu. Our micro buttons are stand-ins that hand the click on to the default button behind them, which runs everything that follows inside our own call — and for the spell book that ends in the book writing down which half of itself it is showing. That note then counted as ours, the book reads it on every click on a spell, and so every cast from the book was refused as coming from an addon. Out of combat as well, for the rest of the session, until the interface was reloaded. Opening the book by its key was never affected. The micro menu now carries the default button itself, wearing our icon, so nothing is handed through us any more.

**Bags:**
- Pointing at a bag slot shows the tooltip of the bag itself — quality colour, how much it holds, everything the item carries — with the click hints under it, instead of the bare name. In the inventory window as well as at the bank, which had drifted apart although the two bars are the same thing.
- The bar in the inventory window takes bags now, the way the one at the bank already did: drag a bag onto a slot to put it there, or left-click a slot with a bag on the cursor. Right-click with an empty hand takes the bag off again, and left-click with an empty hand still shows and hides it. The backpack and the keyring are not slotted bags, so they accept nothing and are not offered the right-click line in the first place.

**Character Panel:**
- The enchant on the wrist slot sits closer to the rows around it, and the enchant on the weapon sits six pixels lower.

**Trainer:**
- The trainer tab is a button of its own now. It used to be a spare tab of the spell book that we wrote on with every update, and the book reads those tabs back in the middle of its own pass. It also goes away with the pet book, where it used to stay behind.

## 1.52.1
**Action Bars:**
- **NEW: Keep the main bar on its page in every form** – Cat, bear, stealth, stances and Shadowform stop swapping action bar 1 to a page of their own
- The ticker that paints cooldown dimming and range colouring no longer walks switched-off bars. It read and repainted every action bar five times a second, including the ones whose buttons nobody can see, so running two bars cost as much as running all of them.
- Leaving a button no longer builds a fresh check each time. The check only ever reads the bar, not the button, so it is built once per bar and shared by all of its buttons.

**Arena:**
- The opponent frames are left alone unless you actually asked for a different arrangement. They are protected frames: anchoring one from our side is allowed outside a fight, but it marks the frame for the rest of the session, and the next time the default interface repositions it during a round its own call is refused and the block is reported against us. There is no way to anchor a protected frame without leaving that mark, so an untouched setup now keeps the default stacking. Order, spacing, grow direction and slot offsets all still work — the message becomes the price of a feature you asked for rather than something every arena hands out for free.

**Bags:**
- Move up and move down work again on a category you switched off and back on. The order list was filled once, while it was still empty, so anything that did not exist at that moment never got an entry, and its arrows then did nothing at all for the rest of the session without saying so.

**Under the hood:**
- Switching a module off releases its event handlers again. The note recording which module owns a handler stayed behind when the handler was unregistered, and that note kept a hard reference to every handler the module had ever registered.

## 1.52.0
**Chat:**
- The own background for the input line is offered on every client. It was limited to one client generation, and the code already said it would work everywhere.

**Cooldown Manager:**
- The icon borders are pixel-exact. The border there is not a texture of its own but the rim of a plate behind the icon, so the two have to sit on the same pixel grid, the thickness has to be counted in pixels rather than frame units, and the icon size and spacing have to begin on whole pixels. None of the three was true, which is why a rim came out two pixels on one edge and none on the opposite.

**Nameplates:**
- **NEW: Apply this arrangement** – Puts the unit name and the health value inside the bar, crowd control left of it, incoming debuffs above that and buffs to its right, with the cast bar carrying its icon, its remaining time and its target
- The unit name was hidden behind the health bar fill as soon as a text slot put it inside the bar. The name and the health value hang from different parents: the value is created on the bar, the name on the plate, and the bar is a child of the plate — so it draws over anything the plate draws. While the name only ever sat above the bar this never showed. It has its own layer now, above the bar but not attached to it, because name-only mode hides that bar and a text parented to a hidden frame would go with it.
- The health text has its controls back: what it shows, and which mark goes between the two numbers. Both were still being read and had been unreachable since the page was rebuilt.

**Talent Window:**
- The active talent group was always reported as the first one on clients that do not carry the newer interface for it. Everything behind that believed group one was running: the header called the group you were standing in not active, the activate button offered to switch to the one already on, and the switch reported success while changing nothing. Five files ask that same question, so profile overrides and bar setups were reading it too.
- The glyph page stands permanently beside the window. It is lifted out of Blizzard's talent frame, where it lives inside the scroll area of the very window we replace, and handed back when ours closes.
- The separate glyph button is gone with it. Its only job was to send you to the page that now stands in front of you.
- A band under the header carries the activate button and the name of the talent group on screen. Until now switching existed only as a right-click on the small side icons, and nothing announced it.

## 1.51.0
**Character Panel:**
- **NEW: Socket strip under the window** – A row of every socket on your equipped gear, hung under the character window; click a socket to put a gem from your bags into it
- The enchant text on armour slots reads the enchant again instead of the item's difficulty tag. The filter took the first green line of the tooltip, and where an item carries a tag that tag stands above the enchant — so every such slot showed the tag, while a weapon two rows down showed its enchant correctly because nothing stood in front of it. The tag and the client's bracketed hints are both recognised now, in every language rather than only in English and German.

**Loadouts:**
- The set list no longer casts a shadow past its own frame. What looked like the background standing out over the border was a drop shadow: not an outline but four filled rectangles reaching up to seven pixels beyond the frame on every side, and behind Blizzard's dialog frame there was nothing for it to fall on. It is gone in both looks.
- In the Classic+ look the dark ground stopped short of the ornate line instead of ending on it, and so showed past the frame on every side.

## 1.50.0
**Bar Setups:**
- **NEW: Export as string** – Packs the selected setup into a string you can pass on, with its slots, macros and key bindings
- **NEW: Import from string** – Reads someone else's setup into your library; a name you already use gets a number rather than being overwritten
- An imported setup is rebuilt entry by entry before it is stored. The restore walks every entry, so a malformed one would have thrown in the middle of a run with part of your bars already changed. Broken entries are dropped, the rest still arrives.
- Saving and loading say what they did. Both had been counting their work all along and throwing the numbers away, so a setup whose macros all failed looked exactly like one that had none, and a save that captured no key bindings said nothing at all.

**Edit Mode:**
- The character window can be placed by hand on the Wrath client. Blizzard's editor does not own that window, so it takes the same direct route the loot window already uses; one box moves the character, reputation and skills tabs together, and the stats panel and set list travel with it.

**Friends List:**
- The window starts wide on the Wrath client. The slider has always gone to 400 — it simply started at nothing, so the extra room only ever reached whoever went looking for it.

**Talent Window:**
- The glyph page opens from a button under the talent group buttons, and it is dark now. The rune circle is dimmed rather than removed, because it is what makes that page recognisable; the sockets take the accent colour, and the glyph artwork and the pickup highlight stay as they are.
- The talent group button shows its tree's icon instead of a question mark. It asked for that icon through an interface that does not answer on every client, and fell back to the placeholder; the answer is now worked out from the ranks themselves, which cannot be misread.

**Unit Frames:**
- The level number on the player frame sits where the client puts it on the Wrath client. Our two anchors are measured against one frame sheet, and where a different one ships, the number landed beside the portrait — the client keeps that anchor itself there anyway, moving it as the rest and PvP icons come and go.

## 1.49.0
**Action Bars:**
- **NEW: Hide The Gryphons** – Takes the two beasts off the ends of Blizzard's main bar without dimming anything else

**Arena Frames:**
- Switching the module off now switches it off. Its handlers are registered when the addon loads, so a module that was already off at login never ran its shutdown: being stunned in a battleground still popped the loss-of-control display, and the interrupt bar filled up and never emptied again, because the ticker that clears its icons only starts when the module is switched on.
- The interrupt bar no longer reads the whole world's combat log. It registered on load and never unregistered, so every combat line anywhere — several thousand a second in a raid — was taken apart for a bar whose own default is arena and battlegrounds only. It uses the same zone filter as the display beside it now.
- Switching the module on inside an arena counts as arriving. The zone decision used to live in the loading screen alone, so anyone who enabled it while already in there got no diminishing-returns ticker until the next one.

**Character Panel:**
- The item level text size slider works again. It looked for the numbers in two places it hoped they would be, and where a client parents its paper doll buttons elsewhere it found none and quietly did nothing — which from the outside is indistinguishable from the text simply being too small.

**Chat:**
- **NEW: Input Line Above The Chat** – Puts the input line over the message area instead of under it, with the panel and the tab bar following it; Wrath client only
- **NEW: Own Background For The Input Line** – Draws the input line on its own dark background instead of Blizzard's, which is what you saw once the dark panel was off; Wrath client only

**Cooldown Manager:**
- Icon zoom is now called Icon crop and reads in percent. It is the same question the nameplate sliders ask, and it was answering in hundredths while they answered in percent.

**Friends List:**
- The extra width belongs to the friends tab alone now. The row texts there stretch with the window, but the column headers on the who, guild and raid tabs sit at fixed offsets and stay put, so every point of width you added landed in an empty right half. Those three tabs go back to Blizzard's own proportions, which is what their columns were measured for.

**Loadouts:**
- The set list and the icon picker take the character panel's style. In the classic style they used to be a flat dark surface with a purple edge holding Blizzard's red buttons — two materials in a hand's width. They now carry Blizzard's dialog frame there and stand in the same material as the window they hang off, while the modern style keeps the flat look.
- The character panel no longer breaks when the sidebar builds its first set row. The marker bar on the row still reached for an accent colour that had been removed, so the list stayed empty and the panel came up bare.

**Minimap:**
- **NEW: Addon Buttons** – Choose where other addons' buttons sit: around the map, hidden until you mouse over it, or gathered in one box below it; Wrath client only

**Nameplates:**
- **NEW: Icon Crop (%)** – How much of the border the game bakes into its icons is cut away, set per aura row and for the cast bar icon
- The rounded bar style no longer leaves dead space at both ends. The round shape does not fill its own image — a transparent border runs all the way round it — and stretching that border across a wide, short bar put roughly eleven points of empty bar at each end and barely one above and below, which is why it showed up sideways and not upright.
- The options page is cut by question instead of by mechanism. Sixteen sections had settings that belong together lying far apart, with the bar texture under one heading and the cast bar's texture under another; eight settings were reachable from two sections at once.
- Every text on the plate sits in a slot now, the way the aura rows already did: top, left, right or centred, filled with the unit name or the health text. Four on/off switches became position pickers, each starting on the place its text already had.
- The stacking dropdown had no readable value at all. It was reading a setting this client does not have; the one it does have is now read and written, measured in the running game.

**Options:**
- A gear icon on a half-width row opens a small floating window instead of unfolding inside the cell. Half a cell has no room for a slider, and six of them had been squeezed into stubs.
- Colour swatches, eyes, gears and arrows sit directly beside the control they belong to rather than in the icon strip on the right, which stays reserved for the gear and the info dot.

**Profession Window:**
- On the Wrath client the module stands down completely and the client keeps its own window. Our restyle addresses Blizzard's widgets by name and by region number, and behind those names that client has a different anatomy: black holes where the hidden regions used to be, a stretched title bar, dropdowns over the recipe list — and no error, because nothing throws, it simply lands on the wrong widgets.

**Talent Window:**
- Talent group buttons run down the right edge, one for each group you have bought. Left-click shows a group, right-click activates it, the same split Blizzard's own window uses. Talents can only be learned in the active group, so a click in the preview does nothing and the tooltip says so beforehand.

**Trainer:**
- The tab carries a book instead of a question mark. That mark is Blizzard's placeholder for a missing icon and read like a defect.

## 1.48.0
**Arena:**
- **NEW: Loss of Control** – Shows the stun, fear, root, silence or lockout holding you, with its icon, its name and the time left
- **NEW: Interrupts** – Tracks enemy interrupts from the combat log, one icon per caster, bordered in the caster's class colour
- **NEW: Timer Text On The Icons** – Seconds left on the interrupt icons, with their own font, outline and colour
- **NEW: Cooldown Swipe On The Icons** – Drop the sweeping shade and keep only the number
- The icon strip beside the enemy frames has a live preview on the General tab. Those frames exist only inside an arena, so its sliders used to move something you could not see.
- An unlocked mover box no longer vanished a moment after the button put it there. The box and a running preview now ignore the zone filter: you place a bar where you are standing, and that is rarely an arena.

**Cooldown Manager:**
- The pinned icon strip also appears on the Layout tab, where icon size, spacing, shape and zoom read back off it while the slider moves.

**Edit Mode:**
- Moving Blizzard frames no longer marks every Edit Mode window as touched by this addon, which had the pet frame refused in combat. Selecting a layout caused it, and that ran on every editor entry even when nothing had been placed.

**Equipment Sets:**
- The icon picker has a close button, and no longer floats over the game after the character sheet is shut.

**Fishing:**
- **NEW: Only Take Over The Key While A Fishing Pole Is Worn** – Without a pole the key keeps whatever you bound it to

**Options Window:**
- The mouse wheel scrolls the sidebar and the page. The window also shrinks to fit a screen smaller than itself, which is what left it undraggable on a high interface scale.

**Profiles:**
- **NEW: Profile Keybind** – Put a profile on a key and switch to it out of combat

**Reminders:**
- The bag sweep behind the food, flask and weapon oil reminders is kept until the bags change, instead of walking every bag three times over twice a second.

**Unit Frames:**
- The modern player frame style no longer reaches into the pet and totem frames.

## 1.47.0
**Edit Mode:**
- The boxes now cover their window exactly, in the same dark look as the rest of the interface, with the name centred and shown in orange when the window is docked to another one
- Outside the editor the small drag handle stays, so an unlocked cooldown bar still accepts dropped spells and test previews stay visible

**Languages:**
- The cloak equipment slot was translated with the navigation word for back in six languages and now reads correctly everywhere

**Nameplates:**
- **NEW: Pixel-true plate size** – Sizes the plates in screen pixels, so height 27 is 27 pixels on any monitor and interface scale
- Plate sizes now mean exactly what the sliders say: the game no longer secretly enlarges the target's plate or shrinks distant ones, and the live preview matches the game — making the target larger is now solely the job of the target plate scale option

**Profiles:**
- **NEW: Save a backup copy** – One click keeps a dated copy of the active profile as a restore point
- Exporting opens a proper window with the string already selected, and importing shows a preview first: rename the profile and untick the parts you do not want before anything is written
- Export strings are compressed to a fraction of their old length and fit in a chat message; strings from older versions still import

**Talent Window:**
- On the Wrath client the talent tooltip showed a placeholder instead of the description, and the talent key would open the window but not close it — both fixed

## 1.46.0
**Action Bars:**
- The page opens with two modes: Standard keeps Blizzard's bars with the skin rows, Modern runs the addon's own bars with a live preview, a per-bar background, button press and hover tints and an XP bar texture

**Cast Bar:**
- **NEW: Modern** – Third player cast bar style: flat look with name and timer on the bar, plus bar texture, border, a coloured last tick and a latency readout
- The options page carries a live preview; clicking its icon or bar jumps to the matching section

**Character Panel:**
- Enchant and gem displays no longer displace each other on non-English clients, and Chinese enchant text is no longer cut mid-character

**Cooldown Manager:**
- Tracked entries sit two per row, each with a gear: park an entry without deleting it, move or remove it, set conditions, and override Only what I cast myself for that entry alone

**Edit Mode:**
- **NEW: See-through** – Hides the box fill and labels while editing, so you can see the interface you are aligning
- Coordinates appear on the box while dragging or nudging, and the window being snapped to pulses white
- The loot window can be moved on Wrath clients

**Friends List:**
- **NEW: Widen window** – Extra width so long names, notes and zones fit on one line

**General:**
- The close glyph of every window is larger now

**Nameplates:**
- Three tabs with a pinned live preview, a name-in-bar option and thousands separators on health numbers

**Options:**
- Gear rows open inside their own column, aura rows align per row, helper tools share one tab, and the pinned page header of the last visited tab is cleared on switching

**Patch Notes:**
- Only the last five versions build at once; a button loads the older ones

**Power Bar:**
- Orientation, fill opacity, frame strata and a live preview on the options page

**Profiles:**
- A profile string can carry a selection: chosen modules, the window layout, talent overrides, and the account-wide fonts and colours

**Reminders:**
- Per-rule switches with class-coloured names, a group scan for missing buffs, preferred food, flask and weapon oil, raid and dungeon thresholds, glow styles, scale and a live preview; middle-click hides a reminder until the next loading screen

**Settings:**
- Broken numeric values are removed before saving and reported at the next login. A single such value used to reset every setting of the account to defaults

**Shaman:**
- Totemic Recall stands as its own button after the elements on Wrath clients

**Talents:**
- **NEW: Talent Window** – All three talent trees side by side with live ranks and click-to-learn on Wrath clients; glyphs stay one button away

## 1.45.0
**Chat:**
- The item level on equipment links sits after the link now, not inside its brackets. Some clients re-check link text against their own data, and the changed text turned the link into the name of whatever quest carried that number.

**Cooldown Manager:**
- A spell no longer shows up on another class just because that class owns a different spell with the same name. Entries respect their class stamp on the bars, and old entries are adopted by spell ID instead of by name.

**Download:**
- The bundled media library silently dropped font registrations when no other addon shipped a newer copy of it; the addon font now registers on every install.

**Equipment Sets:**
- **NEW: Rename...** – In the set's right-click menu and on the sets page; icon, contents and talent binding move along with the name

**Global Settings:**
- **NEW: Optimize My FPS and Graphics** – A proven set of graphics settings with a one-time backup; the restore button next to it brings your old values back
- **NEW: Fonts & Colors** – A new tab: global font with outline mode, optionally for all game texts, plus class and resource colors with a reset on every row
- **NEW: Developer** – Suppress Lua errors, switch tooltip IDs and reset all settings from a new section on the General tab
- The General tab is organised in sections on a two-column grid like the rest of the window. The new tab ships a texture file: restart the client once after updating, a /reload alone will not show the reset arrows.

**Quest Log:**
- The enlargement stays off on Wrath-based clients (Titan Reforged): their quest log is already the wide two-pane frame, and enlarging it pushed the detail pane into the button row.

**Settings Window:**
- Long dropdown lists open upwards when there is no room below. They used to run off the bottom edge of the screen, where the last entries could never be scrolled into view.

## 1.44.0
**Arena:**
- **NEW: Icon Strip** – Racial, trinket and the diminishing-returns row share one edge of the frame in a fixed order, with one set of controls — they can no longer land on top of each other
- The frame layout — order, spacing, grow direction — never actually applied: its hooks were installed before the arena interface had loaded. The frames now report their own moves and the layout follows; during a fight they are protected, so a move mid-round is corrected when it ends.
- The default gap between frames clears the opponent's pet bar, and the drag box in edit mode covers the whole stack instead of a fixed area.

**Cooldown Manager:**
- **NEW: Bar Glows** – Any icon can glow while a buff of yours is active or missing: three styles, gold, class or custom color, and one click watches the spell's own buff
- The page is built around a preview that stays put while you scroll: the bar picker with rename, delete and drag-to-reorder on top, under it every icon of the bar at its real size and shape with the real cooldown sweep. Drag reorders, right-click removes.
- The page is split into tabs, and the resource bar moved in as one of them. Spells you add belong to the class that added them and no longer show up on your other characters.

**Fishing:**
- The third extra-item slot no longer stretches across the page with its box flung to the far edge.

**Languages:**
- The interface no longer compares itself with the other game version anywhere; a check keeps such wording out for good.

**Settings Window:**
- Modules with several pages show them as a tab row along the top; when the tabs outgrow the row, two arrows page through it instead of wrapping into a second line.
- The sidebar got shorter: player and target frames, font bars, castbar and cooldown pulse are one entry now, and a new General entry under Reminders collects the former Extras, Character and Bug Fixes rows — the bug fixes as a single tab.
- Typing into an add field and then clicking the button beside it silently did nothing; the typed text only counted after pressing Enter. Buttons now take the field's text with them.

## 1.43.0
**Character Panel:**
- The character window stayed empty on clients we had never named. The panel asked whether the client called itself one of two specific versions and refused every other one, including clients that have exactly the frames it needs. It now asks for the one thing it cannot work without. Enchants, sockets and item stats were missing for the same reason and return with it.
- Hit rating, haste rating and spell hit rating appear on Wrath-based clients too. They were tied to a single version by name, although the game there has those stats.
- The stat rows Wrath draws in pages with two dropdowns are hidden underneath our own panel now, instead of showing through it.

**Compatibility:**
- **NEW: Titan Reforged** – The addon no longer reports itself out of date on the Chinese client, whose build is listed now
- Version detection falls back to the build number whenever a client reports an identifier we have no name for. Such a client used to end up with every version flag false, which left it worse off than a client with no identifier at all, because that one at least fell back to something.

**Languages:**
- 242 texts that nothing in the interface looks up any more are gone from all nine language files, roughly eight percent of each. Renamed settings left them behind: the action bars were given clearer names a while ago and the old entries simply stayed. A check now asks the reverse question after every change, whether every translated text is still in use, so they cannot pile up again.

**Shaman:**
- **NEW: Call button** – A fifth totem button for the spells that summon a whole saved totem set, shown only to characters who know one

## 1.42.0
**Action Bars:**
- Switching the module off used to leave the bag bar, the latency bar and Action Bar 1's twelve buttons behind until a /reload. All three come back on their own now.

**Cooldown Manager:**
- **NEW: Watch this unit** – A group can follow your target, your focus or your pet instead of you
- **NEW: Only what I cast myself** – A group can require the aura to be your own, not anyone's
- **NEW: Order** – Sort a group by the time left instead of the order you added things in
- Conditions belong to the individual entry now, not only to the kind of group it sits in. One entry can ask for a stack count or for the last few seconds while its neighbours ask for nothing.

**Languages:**
- The twist is now called twist in every language, the word paladins use themselves. German called it Siegelwechsel; the helper and its window are named after the twist instead.

**Nameplates:**
- **NEW: Cast bars in front of other plates** – So the cast you are watching is not hidden behind the plate beside it
- **NEW: Darken enemies out of combat** – With its own strength, so an idle mob reads as idle at a glance
- **NEW: Highlight strength** – How far the plate under your cursor lifts out of the row
- The clickable area is measured from the plate now instead of assumed, so the width and height settings land where your cursor really is.

**Paladin:**
- **NEW: Practice** – A swing clock that runs on its own, with your own keys and a verdict on every swing
- **NEW: Next action** – An icon of the one thing to press, wherever you put it
- **NEW: Latency** – Calibrate the delay a twist has to beat, with its own multiplier and offset
- **NEW: Shade the deadzone** – The tail of the swing a cast can no longer cross
- **NEW: Show the global cooldown bar** – A strip reaching to the moment the cooldown frees up
- **NEW: When to show the bar** – Always, in combat, while a seal is up, or either
- **NEW: Colour the bar by** – The zone the swing is in, or the seal you are carrying
- **NEW: Detach from the bar** – The seal icons take their own position, with a cooldown sweep
- **NEW: Suggest Judgement** – Offered only with room to re-seal afterwards, and off until you ask
- The cue for a landed twist no longer guesses. It used to fire the moment a seal went out inside the window, which is a prediction the server can disagree with. Now the combat log has to show a swing landing with both seals up and the held seal's own damage behind it. Without that, nothing sounds.
- Textures, border, font, frame layer, marker width and the two readouts inside the bar are yours to set, and every seal has its own colour.

**Settings:**
- Rows that span the page now start their control where their neighbours do, instead of each sizing its own label.
- A dropdown with more entries than fit on screen scrolls instead of running off the bottom, and a label that had grown too long fits its row again.

## 1.41.0
**Fixes:**
- Moving a frame could throw a blocked-action error if you happened to be in combat while the frames were built. The keyboard is only taken over once a mover is on screen.
- The trinket window's settings were being written to the saved file a second time under their old names. They are stored once now.

**Languages:**
- 42 texts existed in German only, among them the whole talent override interface and the trinket queue. All nine languages are complete again.

**Nameplates:**
- **NEW: Main positions** – Six slots around the plate, each holding one thing: debuffs, buffs, crowd control or your own damage-over-time
- **NEW: Glow when low on health** – A coloured ring once the unit drops past your mark
- **NEW: Arrows beside your target** – Two arrows pointing in at the bar
- **NEW: Mark on the focus plate** – A short text, so target and focus stay apart at a glance
- **NEW: Preset** – One click for a wide, flat, dark look, and one to put the small plates back
- Two of the six slots sit beside the plate as a column, which was not possible before. And two rows can no longer land on top of each other: giving a slot something takes it away from the slot that had it.
- The cast bar can name who the cast is aimed at, your own name coloured.

**Paladin:**
- **NEW: Twist zones** – The swing bar answers what you may press now instead of counting down
- **NEW: Rotation helper** – A short sequence rather than a single next step, worked out from your weapon and cast speed
- The seal you twist into may be any other seal, not only the two that arrive at level 64.

**Settings:**
- Sections no longer fold away. Long pages fold at the gear on a row instead, which says something a section expander never could: the rows behind it belong to the switch it sits on.
- Controls line up down a page now, and a switch sits in the middle of its row.

## 1.40.0
**Bar Setups:**
- Moved out of the sidebar into Global Settings, as its own tab beside Profiles. Your saved setups were kept.
- They were stored once per class profile — seven copies of one macro library. Stored once now, which cut the settings file by a third. Identical copies are merged, ones that differ are kept side by side.

**Fixes:**
- The chat window no longer jumps back the moment you open the edit mode. Switching layouts re-anchors every window the game knows about, including ones we place ourselves.
- A dropdown with a long entry no longer wraps into the row below it.

**Overview:**
- The first page is a picture of your interface instead of a second sidebar: modules running, frame time and memory, windows you moved, pages you last visited.

**Settings:**
- **NEW: Talent Overrides** – Named groups hold their own value for individual settings and apply when you switch talent specs
- A group can also name a situation — raid, dungeon, arena, battleground, in a group, alone. Anything you change while a group is active is recorded into it, and every overridden row is marked.
- Sliders are one row like every other setting, their number can be typed into, and labels line up in a measured column across the page. A long translation no longer pushes a value box into the next column or a button off its card.
- Every section starts closed, so a long page opens as a list of headings.

**Trinkets:**
- The automatic swap queue has controls again — order, delay and the stop marker, on the trinket page. They only ever existed in a window this addon hides.
- Trinket icons show up again: on the buttons, on the queue marker, and on your worn trinkets right after login instead of only once you click them.

## 1.39.0
**Arena:**
- **NEW: Diminishing Returns Position** – Put the DR row on either side of the frame, with its own X and Y offset
- The DR row no longer lands on top of the trinket or racial icon. It used to hang at a fixed distance on the right edge, exactly where the side icon sits, so switching it on stacked the two. The new default clears it, and on the left edge the row grows outward instead of across the frame.
- The trinket and racial icons sit further out from the enemy frame and are a little smaller, so the health and mana bars read as the middle of the frame instead of competing with an icon at each shoulder. Both are sliders, so your own values are kept.

**Download:**
- The addon folder no longer ships build tools and source files that no player needs. The licence files stay where they are.
- The release notes on the distribution pages are written in English now.

**Languages:**
- Six languages were missing seven texts that existed in German only. All nine are complete again.
- The keyword help for the item search was misleading in Chinese: it gave an English type name as the example, which a Chinese client would never have matched. The example is written in the reader's own language now.

**Paladin:**
- **NEW: Seal Twist Helper** – A swing bar with the twist window marked, plus the next sensible action
- The bar counts down to your next auto attack with two marks: green is the last moment the second seal can still land, purple is how long a Judgement still fits in front of it. The next action is worked out live from your swing timer, the global cooldown and the seals actually on you — not from a fixed rotation. Crusader Strike is only suggested while there is room for it and the holding seal afterwards. Judgement deliberately gets none: it consumes the seal, and a wrong hint costs more there than no hint. Off by default.

## 1.38.0
**Languages:**
- **NEW:** Simplified Chinese and Traditional Chinese. Both are complete: every interface text, every option and every patch note, 2528 entries each. They are separate translations, not one converted into the other. Pick yours under General, or leave the setting on Auto and it follows your game client.

## 1.37.4
**Fixes:**
- Clicking a trinket button while that trinket slot is empty no longer throws an error. The game's own shortcut for "use the item in slot N" stopped tolerating an empty slot with July's interface update, so the button now takes a different route to the same action.

**Performance:**
- Fixed a stutter of almost two frames every time you entered or left combat, if you use WeakAuras and have the WeakAuras skin switched on. Every combat change repainted every aura you have ever saved — including the ones not on screen — with a look that had not changed. Auras are now only repainted when the settings or their size actually changed. Measured: 28 ms down to under 2 ms. The skin itself is unchanged.

## 1.37.3
**Class Trainer page:**
- Fixed the page being thrown away again a moment after you opened it, dropping you back on a class tab. The spell book resets its own page whenever your spells change, and our page sits past the last real tab, so it was always the one discarded. Most noticeable on Season of Discovery, where engraving changes spells constantly.

**Under the hood:**
- **NEW:** `/vcuiprof` measures how much frame time each part of the addon costs, then prints a list. It ships switched off and costs nothing while it is — the measuring code is only put in place when you turn it on. Type it once to start, once more to read.

## 1.37.2
**Classic Era, Hardcore and Season of Discovery:**
- The addon loads again without ticking "Load out of date AddOns". Blizzard's July interface update moved these realms to a new version number.
- Fixed a crash that switched the whole Class Trainer page off on Season of Discovery: one ability the realm does not know took the entire module down with it.
- The elite border on your player frame sits correctly again. It was placed against the old frame layout, which that same update replaced.

**Fixes:**
- Fixed a rare error storm at the end of a fight. Cleanup work in nineteen files could be skipped and the chat filled with error lines.
- Combat log features (swing timer, cooldown pulse, combat text, arena tracker, nameplates, mana display) no longer depend on a setting a player can switch off.
- An interrupted enemy cast now really shows INTERRUPTED for a moment.
- **NEW:** Items that start a quest you have not accepted yet are marked with a yellow exclamation mark, in bags, bank and keyring.

**Performance:**
- Seven of the eight shipped translations no longer build their lookup table at all. Only the language you actually read is assembled, which frees about a megabyte on every login.
- Edit Mode: three background drivers no longer run permanently, dragging a window allocates far less, and finding a window is a direct lookup instead of a search.
- Disabling a module now detaches it completely — several used to leave listeners running for the rest of the session.

**Under the hood:**
- The performance readout in the header uses your client's own always-on measurement, so it needs no setting and no reload.

## 1.37.1
**Languages:**
- The language option under General now actually applies. It silently never took effect — the addon read the client language before your saved choice was loaded. After a /reload every label, dropdown and popup follows your choice.
- **NEW:** The Patch Notes page is translated into all languages, including every past version.
- The trinket panel, its queue window and the /trinket help are translated too.
- German: sixteen duplicated translations cleaned up, five of which contradicted each other.

**Performance:**
- Third pass over the busiest code paths: nameplate auras scan once instead of four times, combat-log and aura events skip a safety wrapper, timer texts only redraw when the shown number changes, and several background listeners now sleep while their feature is off or hidden. Less stutter in raids and arenas.

**Arena:**
- The frames can be turned off again without leftovers.
- An interrupted enemy cast now shows INTERRUPTED briefly — it used to vanish the same instant.
- Diminishing-returns icons clean up correctly after toggling the tracker mid-arena.

**Fixes:**
- Seven working settings that were invisible in the options are shown again, and several switches that did nothing are wired up.
- Modules tidy up after themselves when disabled: totem range dimming, the inspect window, queue timer, quest log and font bars no longer leave stale pieces behind.

**Visuals:**
- Three modules got their own sidebar icons instead of the placeholder, and Reminders got a nicer bell.

## 1.37.0
**Languages:**
- **NEW:** Spanish, French, Italian, Portuguese, Russian and Korean. All six are complete — every one of the 2244 texts is translated, nothing falls back to English. Spanish also serves Latin American clients. Choose your language under General, or leave it on Auto.

**Reminders (new module):**
- **NEW:** Shows what you are missing before a pull: weapon oils and stones, blessings, food and flask buffs, the aura or stance you forgot to set. Click a reminder to cast or use it. Off by default, found under Quality of Life.

**Nameplates:**
- **NEW:** A spark at the bar's fill point, rounded corners, aura rows you can assign freely, and your own damage-over-time effects on a row of their own.
- **NEW:** Aura borders take the colour of their spell school, and an aura flashes shortly before it runs out.
- **NEW:** Level and elite text, plus overall scale and vertical offset per plate.

**Edit Mode:**
- **NEW:** A window can take its width or height from another window and keep it.
- **NEW:** Save button. While dragging, hold Shift to lock one axis.

**Arena:**
- **NEW:** Trinket and racial cooldowns, Shadow Sight timer, a ring on the class icon for the most important aura, and range checking.

**Totems:**
- Totem icons grey out once you leave the totem's range and regain their colour when you come back.

**Fixes:**
- The character sheet and spellbook open in combat again. The action bars no longer set a protected field from our own code, which was the real cause.
- The melee swing timer is off by default and only loads for melee classes and specialisations.
- Sliders got a proper look: soft edges, an inner shadow and a smoother hover.
- Own icons for the three collection pages, and class icons on the class tabs.

## 1.36.0
**Edit Mode:**
- **NEW:** Anchor a window to another one's edge (left/right/top/bottom) — the gap is kept edge-to-edge, so it survives either window being resized.
- **NEW:** Click-to-anchor: press "Anchor to window..." in a window's panel, then click the target window. Loop and self-anchor are blocked.
- **NEW:** While dragging, alignment lines now also show the pixel distance to the window you line up with.
- **NEW:** Discard button — snapshots the layout when you open Edit Mode and restores it (positions, scale, anchors and links) if you discard.

**Chat:**
- The drag area now covers the whole dark chat panel down to the edit box, not just the narrow message strip.
- Fixed right-click on the chat window not opening its settings panel in Edit Mode.

## 1.35.0
**Nameplates:**
- **NEW:** Interrupt help on the cast bar: own colours while your interrupt is on cooldown or ready, a tick marking where it comes back mid-cast, a shield on uninterruptible casts and an interrupt flash that can show who landed the kick.
- **NEW:** Cast bar suite: icon side and scale, remaining time, own background, channel colour, a warning colour when the cast aims at YOU — and on your target the cast bar lines up flush with the health bar including its border.
- **NEW:** Execute line, target and mouseover effects, crowd control section, combo point shapes and placement, per-element position, size and text-size controls plus a font picker.
- **NEW:** The options page carries a clickable live preview that stays pinned while you scroll — click any element to jump to its settings.
- **NEW:** Smooth health movement with a damage trail, value plus percent text layouts with short numbers, and a decimal toggle for aura timers.

**Action Bars:**
- **NEW:** Per-bar visibility conditions (instances, mounted, target, group), modifier paging, quick keybind mode (/vkb), a sixth bar, growth directions, button text styling and cooldown look options.
- **NEW:** Micro menu and bag bar modern style: flat dark strips with an own monochrome icon set, plus world map, friends list, group finder, shop and key ring buttons.
- The experience bar width now adjusts in single steps.

**Resource Bar:**
- **NEW:** Visibility conditions, colour modes with gradient, background and border colours, smooth value changes, hash marks and threshold colouring.

**Fixes:**
- Character sheet stats panel no longer bleeds into other tabs; loadout sidebar aligns with the modern character sheet.
- Arena points calculator panel and button wear the addon look and dock beside the character sheet.

## 1.34.3
**Game Menu:**
- **NEW:** The Escape menu now wears the dark addon look — flat buttons, accent title — and gains a VuloClassicUI button that opens the options window. Both have their own toggles under General.

**Friends List:**
- The add friend dialog is skinned to match: dark panel, accent headline, dark input field and flat buttons.
- Guild roster column header hover and click no longer stick out past the flat header row.

**Chat:**
- The combat log filter bar now shares the exact width and height of the chat tab row, flush with the panel edge.

## 1.34.2
**Settings Window:**
- **NEW:** After an update, a pulsing dot on the "Patch Notes" entry points at the new notes until you open them once — account wide, per version.

**Character Window:**
- With the Modern style, the equipment set sidebar now docks to the right of the stats panel at exactly the window's height, instead of overlapping it. Switching styles with the window open moves it immediately.

**Action Bars:**
- Micro menu buttons that the game hides situationally are shown again, so the row no longer has a gap.

## 1.34.1
**Nameplates:**
- The default nameplate no longer shows through as a faint transparent bar under the custom plate — it is now hidden outright and kept hidden while the custom plate is active.

**Action Bars:**
- All micro menu buttons open their windows again — the emptied default micro menu shell was invisibly swallowing clicks on the relocated buttons.
- Fixed a blocked-action error when the stance bar updated during combat; stance button visibility now only changes out of combat, while icon tint, cooldown and the active marker keep updating live.

## 1.34.0
**Action Bars:**
- **NEW:** An Action Bars module puts every action bar on its own movable frame — action bars 1 to 5, the stance bar and the pet bar — each placed and scaled in Edit Mode and configured on its own.
- The main bar pages correctly with druid, rogue, warrior and priest forms, and your keybinds keep working on every bar, with the key shown on the buttons.
- Per bar: visibility (always, mouseover, in or out of combat), opacity, icon size, buttons per row, spacing, vertical layout, reverse order, and hiding the keybind or macro text — with adjustable text sizes for keybind, macro, count and cooldown numbers.
- Empty slots can be hidden and reappear automatically while you drag an ability onto the bar, and a bar can be made click-through.
- Cooldown and look settings for all bars: cooldown sweep darkness, desaturating icons on cooldown, colouring icons while the target is out of range, and hiding button tooltips always or only in combat.
- **NEW:** An own experience bar with adjustable width, height and colour, rested overlay and progress text — it replaces the default bar while enabled and hides at the level cap.
- The micro menu, the bag bar and the performance bar sit on movable holders, and each of them can be hidden — as can the default experience bar.
- Off by default: the standard bars stay untouched until you enable the module, and disabling hands everything back (a reload fully restores the default bars).

**Dark Skin:**
- The dark button skin now also covers the new action-bar buttons.

## 1.33.0
**Nameplates (German: Namensplaketten):**
- **NEW:** A custom Nameplates module draws its own health bar, cast bar, name and health text over enemy and NPC nameplates — fully configurable, with a live preview that updates as you change each option.
- Health bar with your choice of texture, width, height, background, and a border drawn as thin lines or a texture, all in your own colours.
- Colouring by reaction (hostile, neutral, friendly, tapped) and by class for players, plus role-based threat colouring for tanks and damage dealers.
- Target and focus highlight rings, and an optional fade for plates that are not your target.
- Cast bar with spell icon, spell name, and a separate colour for casts that cannot be interrupted.
- Aura rows: your debuffs (or all of them), enemy buffs, and a separate prominent row for crowd control such as Polymorph, Fear and Sap. A glow marks enemy buffs you can steal or dispel.
- Combo point pips on your target for Rogues and Druids in cat form.
- Raid target markers (skull, cross, and the rest) with adjustable size and position.
- Friendly plates can show name only, the full plate, or nothing — set separately for players and NPCs — and can show a friendly NPC's subtitle under its name.

## 1.32.0
**Interface Skins:**
- **NEW:** A single "Dark Skin" module now covers the dark action-button and WeakAuras skin plus the optional Dark Mode that darkens Blizzard's default frames — those used to be two separate modules. Your existing settings carry over.
- The reskin modules (skins, character panel, chat, friends list, minimap) are now one tabbed entry, matching how the other groups are already organised.

**Settings Window:**
- Consolidated groups now list their modules as a vertical, icon-labelled column instead of a wrapping row of tabs — easier to scan when there are many.
- **NEW:** A "Patch Notes" page under Overview shows every version's changes right in the game.

**German client:**
- Cleaner tab names for a few tools: Training, Leisten-Profile, Apexis-Minispiel, Gruppensuche.

## 1.31.0
**Unit Frames:**
- The target-frame extras and the elite player-frame border are now a single module called "Player & Target Frame". Your existing settings and per-character on and off state carry over automatically.

**Profiles:**
- **NEW:** Settings now default to a separate profile per class, so what you set on one class no longer changes another. Your current settings are copied into each class profile, and you can still share or pin profiles as before.

**Combat Text:**
- Scrolling messages that fire at the same moment now stack with a gap instead of overlapping.

**Fishing:**
- Fixed an error that could appear when combat started while your line was cast. The sound and interact settings now restore after combat ends instead.

**Performance:**
- Lighter cast bar time text, cooldown bars that batch their refreshes during busy moments, a cheaper combat-log check for the cooldown pulse, and a lighter minimap hover check.

**Character Panel:**
- The spell stats are ordered spell power, healing, spell crit, then spell hit.

**German client:**
- The Fishing and Mail tabs now read "Angeln" and "Post".

## 1.30.1
**Character Panel:**
- **NEW:** A style dropdown at the top of the module options. Classic+ keeps the current look; Modern is a new dark, single-window style.
- Modern reskins the whole character window dark with an accent border and a stats panel on the right: a big equipped item level, then collapsible categories — attributes, melee, spell, defense and resistances — with per-stat hover breakdowns and mouse-wheel scrolling.
- Under Modern the built-in stats, resistance icons and the model rotate arrows are hidden, and the reputation, skills and player-versus-player sub-tabs plus the bottom tabs are skinned to match. Everything switches back to Classic+ live, and adapts per client (rating stats only where they exist).

**UI Reskin:**
- **NEW:** Dark skin for a world-map options window, with its own on and off switch in the Addon Skins options.

**Minimap:**
- The clock now sits on the same line as the date and zone instead of floating higher.

## 1.30.0
**UI Reskin:**
- **NEW:** Dark skin for a loot-distribution addon — its award and roll windows, its settings and overview windows, and the two always-visible roll and bid bars get the house panel, accent border and flat close button.
- **NEW:** Dark skin for an attunement tracker — the main window and its buttons match the dark look; the colored status rows stay as they are so the state colors remain readable.
- Both are separate on and off switches in the Addon Skins options, next to the others.

## 1.29.0
**Equipment Sets:**
- Fixed: an expanded set sometimes would not collapse on the second click of its arrow. The arrow is also easier to hit now.
- The slot flyout can now equip not-yet-bound items too — with the game's own "this will bind to you" confirmation before it soulbinds.

**Chat:**
- Item levels in links now only show on uncommon (green) and better gear — grey and white trash no longer gets a number.
- No double number when another loot addon already tagged the item with its item level.

## 1.28.0
**Minimap:**
- **NEW:** The date now shows next to the clock in the zone panel — click it to open the calendar, hover for the full date. Optional in the minimap settings.
- The zone panel is a touch wider so the zone name, clock and date sit more comfortably.

## 1.27.0
**Equipment Sets:**
- **NEW:** Hover an equipment slot in the character window for a compact flyout of matching items from your bags — click one to equip it. The modifier-click picker is still there for a larger, pinnable window.

## 1.26.0
**Bags:**
- Item levels on gear are now tinted in the item's quality color, matching the rest of the window (toggle in the options).
- Section headers gained a thin divider line and a collapse control — click a category header to fold it away. The state is remembered per category.
- The window title now shows the used and total item count.

## 1.25.0
**Global:**
- **NEW:** Theme color — pick the accent color in the global settings (presets or your own). Everything purple follows it, saved per profile.
- **NEW:** Pin a profile to a single character; at login it beats the class assignment and the account-wide selection.

**Cooldown Manager:**
- **NEW:** Track your own debuffs on the target, or set up a missing-buff reminder group (icon shows while the buff is absent).
- Icons tint blue when you are out of mana and red when the target is out of range; ready-only groups now pack without gaps.
- **NEW:** Auto-track your equipped trinkets, duplicate a whole group, and optional hover tooltips.

**UI Reskin:**
- **NEW:** Dark skin for the guild & communities window — flat tabs, list cards, roster and chat panels.

## 1.24.0
**Player Castbar:**
- **NEW:** Pushback readout, a latency window on casts (the spell-queue moment), a crafting-series counter (e.g. 3/20), timer format options, accent/class fill colors and smoother fill on time jumps.

**Combat Text:**
- Reworked with inline spell icons and bracketed spell names; separate purge, incoming-dispel, buff-given/received and spell-reflect messages, with anti-spam throttling.
- **NEW:** Death announcements for group members with class-colored names.

**Bank:**
- **NEW:** A per-character snapshot of your bank contents, viewable anywhere from the bag window — with tooltips and smart search.

## 1.23.0
**NEW — Guild Bank:**
- A dark guild bank window with tabs, search, a money log, deposit/withdraw and engine-based sorting.

**Friends & Reskins:**
- Full dark reskin of the friends window with class crests, row layout, tabs and a battletag pill.
- **NEW:** Addon Skins module — matches supported third-party windows to the dark look, including a quest tracker with accent headers.

**Bags & Bank:**
- **NEW:** Smart search keywords (quality, type, item level) that also search an open bank and guild bank.
- Bind-on-equip and junk markers, keyring separation, and a fixed-slot OneBag layout.

**Equipment Sets:**
- Availability markers, set-preview tooltips, true partial sets, and an item-level/set warning in the disenchant queue.

## 1.22.0
**Quality of Life:**
- Rebuilt sort engine (bags, bank and guild bank) that keeps materials and gear apart.
- Minimap and totem-bar improvements, plus framework hardening for the current clients.

## 1.21.0
**NEW — Bags & Bank:**
- A single unified inventory window: search, sort, categories, custom groups, pinned & recent items, keyring, quick-drop, item levels and quality borders.
- A new bank window with slot purchasing.

**Quality of Life:**
- Friends counter in the chat, a gold overview tooltip, and taint-free Edit Mode movers.

## 1.20.1
**Fixes:**
- Chat module polish and localization fixes.

## 1.20.0
**NEW — Chat:**
- A reworked chat: timestamps, class-colored names, clickable links, short channel names, a dark panel with an icon sidebar, idle fade and history that survives a reload. Every part is optional.

## 1.19.0
**Edit Mode:**
- **NEW:** Per-frame free-move and an anchor toggle, with panel polish.
- Dark border on the action bars; fixed a compat-frame taint issue.

## 1.18.0
**NEW — Dark Mode:**
- A dark-mode module, plus German localization fixes.

## 1.17.0
**Quality of Life:**
- General fixes and polish.

## 1.16.0
**Quality of Life:**
- **NEW:** The Loadouts sidebar on the character window can now be moved. Turn on edit mode, then drag the purple box (arrow keys fine-tune, right-click to reset its position).

**Unit Frames:**
- Classic Era: fixed the elite player-frame border alignment and moved the level badge into place.

## 1.15.0
**Compatibility:**
- **NEW:** Full **Classic Era (1.15.8)** support alongside Burning Crusade Classic (2.5.5). TBC-only content (Arena frames, gem sockets) auto-disables on Era; everything else runs on both.

**UI Reskin:**
- The Character Panel enhancements (item level per slot, shortened enchant text, average item level) now work on Classic Era as well.

**Bug Fixes:**
- Fishing: muted the reel error spam ("Unknown unit" / "Out of range") while fishing.
- Mail: "Open All" is faster and now reliably empties the whole mailbox in a single click, even past the 50-mail batch limit.
