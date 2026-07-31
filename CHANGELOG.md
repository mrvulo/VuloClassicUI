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
