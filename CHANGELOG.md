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
