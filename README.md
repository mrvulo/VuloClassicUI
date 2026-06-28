# VuloClassicUI

**A modular UI & quality-of-life suite for WoW Classic — Burning Crusade Classic
(2.5.5) and Classic Era (1.15.8).**

One config panel, 30+ small enhancements — turn on what you want, leave the rest
off. No dependencies, everything is built in.

Type **`/vcui`** to open the options. Every module has its own on/off switch and
settings, a search box up top filters the list, and **`/vcui help`** lists every
slash command.

> **Compatibility:** Works on TBC Classic **2.5.5** (Anniversary) and Classic Era
> **1.15.8**. Content that only exists in TBC — Arena enemy frames, gem sockets —
> auto-disables on Era; everything else runs on both.

---

## ✨ Highlights

- **One window, 30+ modules** — searchable, with per-class **profiles** and a
  fully independent on/off switch for every feature.
- **Built-in button skin** — dark, rounded drop-shadow for action bars *and*
  WeakAuras icons. No Masque required.
- **Built-in edit mode** — drag movable frames (castbar, power bar, cooldown bars,
  loadouts sidebar…) into place; arrow keys fine-tune.
- **Arena tools, cooldown manager, loadouts, one-key fishing** and a deep pile of
  quality-of-life — see below.

---

## 🖥️ Unit Frames & Display

- **Player Castbar** — two modes: an extended Blizzard bar (time text, ticks,
  channel coloring) or a custom VUI castbar with icon and spell name.
- **Target & Focus Frame** — adds a numeric threat %, a colored threat glow and
  the winged rare-elite border the default UI leaves out.
- **Power Bar** — a movable resource bar that follows your class automatically
  (Mana / Rage / Energy), and switches with Druid forms.
- **Elite Player Frame** — gives your portrait the elite, rare-elite or rare
  dragon border.
- **Cooldown Pulse** — flashes an ability's icon in the center of the screen the
  moment its cooldown is ready.
- **Font Bars** — smaller, cleaner fonts on Player / Target / Pet health & mana.

## ⚔️ Action Bars & Icons

- **Button Skin** — built-in dark drop-shadow skin for the action bars and
  WeakAuras icons: several styles (shadow / rounded / square / accent / circle /
  minimal), adjustable icon size, and bundled bar textures. No extra add-on needed.

## 🎯 HUD & Combat

- **Cooldown Manager** — movable cooldown bars grouped however you like (procs,
  defensives, burst), in the style of the retail cooldown manager.
- **Combat Text** — custom floating combat text for combat start/end, interrupts,
  dispels, misses and low durability, with per-event color, size, outline & shadow.
- **Swing Timer** — main-hand / off-hand weapon swing bars for melee auto-attacks
  (on by default for melee classes), with color, texture and transparency options.
- **Class Specific** — Shadow Priest: Vampiric Touch mana-return tracker.

## 🏹 PvP & Arena

- **Arena Frames** *(TBC)* — move & scale the enemy frames, class colors + class
  icons, PvP-trinket cooldown, diminishing-returns tracking, enemy castbars and a
  drag & drop layout.
- **Trinkets** — two on-screen trinket slots with cooldown display, a selection
  dropdown and auto-queue.
- **Queue Timer** — a countdown on the PvP/PvE queue-pop dialog, with an optional
  sound warning.

## 🧰 Quality of Life

- **General** — auto-accept quests / resurrects / summons, auto-sell junk,
  auto-repair, hide UI spam (zone text, portrait numbers, stack counts,
  keybind/macro text), text-size tweaks.
- **Loadouts** — save and quick-equip gear sets (per character), with auto-switch
  on spec / stance / form, a movable character-frame sidebar and a minimap button.
- **Action Bar Profiles** — snapshot and restore your action bars, macros and
  keybindings on demand.
- **Fishing** — one key casts, reels and applies a lure, then auto-loots your catch.
- **Mail: Open All** — collect every attachment and coin from your mailbox in a
  single click.
- **Group Board** — scans chat for people forming groups and lists them by
  Classic / TBC instance in its own window.
- **Trainer Tab** — adds a tab to your spellbook listing every ability you can
  still learn from your class trainer, grouped by level.
- **Disenchant Queue** — one window, one button: disenchant your bags item by item.
- **Slot Picker** — Shift + Right-click an equipment slot to equip a compatible
  item straight from your bags.
- **Spam Filter** — hides gold/casino chat spammers whose names use look-alike
  letters (e.g. *Gãsïnô*, *Casinòbâbe*), including `/emote` spam. Optional web-link
  block and a per-name whitelist (`/vcui spam <name>`).
- **Gold Tracker** — shows how much gold you've gained or spent since the last
  reset, right in the bag tooltip (per character).
- **Auto Item Buy** — automatically buys configured items at configured vendors
  (hold Shift when opening a merchant = emergency stop).
- **Character Panel** — item level per slot, socket display and shortened enchant
  text.
- **Tooltip IDs** — spell / item / NPC (and more) IDs on every tooltip.

## 🎨 UI Reskins

- **Profession Window** — enlarges and themes the tradeskill & craft windows: the
  detail pane sits beside the recipe list, with a Parchment or Dark theme.
- **Quest Log** — quest levels (and optional quest IDs) in the titles, a larger
  frame, and a Parchment or Dark theme.
- **Friends List** — class-colored names, class icons, status dots, inline notes,
  faction tint and optional auto-accept.

## 🩹 Bug Fixes

Small, targeted catches for known client issues so a single broken entry doesn't
spam your chat or break a whole panel (these target the Anniversary 2.5.5 client
and stay inert where the bug doesn't exist):

- Stuck player inspects (auto-reset + `/inspectreset`)
- LFG / Group Finder browse crashes
- Guild News nil errors
- Missing socket-bind confirmation dialog
- Missing "in combat" glow on the player frame
- German Auction House price-dropdown nil error

---

## 🔧 Installation

1. Extract into `Interface\AddOns\`
2. `/reload` (or restart the game)
3. Type **`/vcui`** and enable the modules you want

## ⌨️ Handy slash commands

`/vcui` options · `/vcui help` command list · `/lo` loadouts · `/vlfg` group board ·
`/trinket` trinkets · `/swingtest` swing-timer mover · `/rl` reload

## 🔗 Links

- Source & bug reports: **github.com/mrvulo/VuloClassicUI**
