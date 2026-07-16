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
