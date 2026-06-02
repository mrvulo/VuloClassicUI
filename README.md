# VuloClassicUI

**A modular UI & quality-of-life suite for WoW Classic Anniversary (TBC 2.5.5).**

One config panel, lots of small enhancements — turn on what you want, leave the
rest off. No dependencies, everything is built in.

Type **`/vcui`** to open the options. Every module has its own on/off switch and
settings; a search box up top filters the list, and **`/vcui help`** lists every
slash command.

---

## ✨ Highlights

- **One window, ~25 modules** — searchable, per-class **profiles**, each toggle
  independent.
- **Built-in button skin** — dark, rounded drop-shadow for action bars *and*
  WeakAuras icons. No Masque needed.
- **Arena tools, swing timer, loadouts, spam filter** and a pile of QoL — see below.

---

## 🖥️ Display & Unit Frames

- **Player Castbar** — two modes: an extended Blizzard bar (time text, ticks,
  channel coloring) or a custom VUI castbar with icon and spell name.
- **Cooldown Pulse** — flashes an ability's icon in the center of the screen the
  moment its cooldown is ready.
- **Combat Text** — custom floating combat text for combat start/end, interrupts,
  dispels, misses and low durability, with per-event color, size, outline & shadow.
- **Font Bars** — smaller, cleaner fonts on Player / Target / Pet health & mana.

## ⚔️ Action Bars & Icons

- **Button Skin** — built-in dark drop-shadow skin for the action bars and
  WeakAuras icons: several styles (shadow / rounded / square / accent / circle /
  minimal), adjustable icon size, and bundled bar textures. No extra add-on needed.

## 🛡️ Class & Combat

- **Swing Timer** — main-hand / off-hand weapon swing bars for melee auto-attacks
  (on by default for melee classes), with color, texture and transparency options.
- **Class Specific** — Priest (Shadow): Vampiric Touch mana-return tracker.

## 🏹 PvP

- **Arena Frames** — move & scale the enemy frames, class colors + class icons,
  PvP-trinket cooldown, diminishing-returns tracking, enemy castbars, drag & drop
  layout.
- **Queue Timer** — countdown on the PvP/PvE queue-pop dialog, with an optional
  sound warning.

## 🧰 Quality of Life

- **General** — auto-accept quests / resurrects / summons, auto-sell junk,
  auto-repair, hide UI spam (zone text, portrait numbers, stack counts,
  keybind/macro text), text-size tweaks.
- **Loadouts** — save and quick-equip gear sets (per character), with auto-switch
  on spec / stance / form, a character-frame sidebar and a minimap button.
- **Slot Picker** — Shift + Right-click an equipment slot to pick a compatible
  item straight from your bags.
- **Spam Filter** — hides gold/casino chat spammers whose names use look-alike
  letters (e.g. *Gãsïnô*, *Casinòbâbe*), including `/emote` spam. Optional web-link
  block and a per-name whitelist (`/vcui spam <name>`).
- **Gold Tracker** — shows how much gold you've gained or spent since the last
  reset, right in the bag tooltip (per character).
- **Auto Item Buy** — automatically buys configured items at configured vendors
  (hold Shift when opening a merchant = emergency stop).
- **Trinkets** — two on-screen trinket slots with cooldown display, a selection
  dropdown and auto-queue.
- **Character Panel** — item level per slot, socket display, shortened enchant text.
- **Tooltip IDs** — spell / item / NPC (and more) IDs on every tooltip.

## 🩹 Anniversary Bug Fixes

Small, targeted catches for known 2.5.5 issues so a single broken entry doesn't
spam your chat or break a whole panel:

- Stuck player inspects (auto-reset + `/inspectreset`)
- LFG / Group Finder browse crashes
- Guild News nil errors
- ItemRack auto-equip "action blocked" crash
- German Auction House price-dropdown nil error

---

## 🔧 Installation

1. Extract into `Interface\AddOns\`
2. `/reload` (or restart the game)
3. Type **`/vcui`** and enable the modules you want

## ⌨️ Handy slash commands

`/vcui` options · `/vcui help` command list · `/lo` loadouts ·
`/swingtest` swing-timer mover · `/trinket` trinkets · `/rl` reload

## 🔗 Links

- Source & bug reports: **github.com/mrvulo/VuloClassicUI**
