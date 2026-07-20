-- Generated from CHANGELOG.md by tools/gen_changelog.js; edit that file, not this one.
local _, ns = ...

ns.CHANGELOG = {
    { version = "1.35.0", sections = {
        { category = "Nameplates", lines = {
            "NEW: Interrupt help on the cast bar: own colours while your interrupt is on cooldown or ready, a tick marking where it comes back mid-cast, a shield on uninterruptible casts and an interrupt flash that can show who landed the kick.",
            "NEW: Cast bar suite: icon side and scale, remaining time, own background, channel colour, a warning colour when the cast aims at YOU — and on your target the cast bar lines up flush with the health bar including its border.",
            "NEW: Execute line, target and mouseover effects, crowd control section, combo point shapes and placement, per-element position, size and text-size controls plus a font picker.",
            "NEW: The options page carries a clickable live preview that stays pinned while you scroll — click any element to jump to its settings.",
            "NEW: Smooth health movement with a damage trail, value plus percent text layouts with short numbers, and a decimal toggle for aura timers.",
        } },
        { category = "Action Bars", lines = {
            "NEW: Per-bar visibility conditions (instances, mounted, target, group), modifier paging, quick keybind mode (/vkb), a sixth bar, growth directions, button text styling and cooldown look options.",
            "NEW: Micro menu and bag bar modern style: flat dark strips with an own monochrome icon set, plus world map, friends list, group finder, shop and key ring buttons.",
            "The experience bar width now adjusts in single steps.",
        } },
        { category = "Resource Bar", lines = {
            "NEW: Visibility conditions, colour modes with gradient, background and border colours, smooth value changes, hash marks and threshold colouring.",
        } },
        { category = "Fixes", lines = {
            "Character sheet stats panel no longer bleeds into other tabs; loadout sidebar aligns with the modern character sheet.",
            "Arena points calculator panel and button wear the addon look and dock beside the character sheet.",
        } },
    } },
    { version = "1.34.3", sections = {
        { category = "Game Menu", lines = {
            "NEW: The Escape menu now wears the dark addon look — flat buttons, accent title — and gains a VuloClassicUI button that opens the options window. Both have their own toggles under General.",
        } },
        { category = "Friends List", lines = {
            "The add friend dialog is skinned to match: dark panel, accent headline, dark input field and flat buttons.",
            "Guild roster column header hover and click no longer stick out past the flat header row.",
        } },
        { category = "Chat", lines = {
            "The combat log filter bar now shares the exact width and height of the chat tab row, flush with the panel edge.",
        } },
    } },
    { version = "1.34.2", sections = {
        { category = "Settings Window", lines = {
            "NEW: After an update, a pulsing dot on the \"Patch Notes\" entry points at the new notes until you open them once — account wide, per version.",
        } },
        { category = "Character Window", lines = {
            "With the Modern style, the equipment set sidebar now docks to the right of the stats panel at exactly the window's height, instead of overlapping it. Switching styles with the window open moves it immediately.",
        } },
        { category = "Action Bars", lines = {
            "Micro menu buttons that the game hides situationally are shown again, so the row no longer has a gap.",
        } },
    } },
    { version = "1.34.1", sections = {
        { category = "Nameplates", lines = {
            "The default nameplate no longer shows through as a faint transparent bar under the custom plate — it is now hidden outright and kept hidden while the custom plate is active.",
        } },
        { category = "Action Bars", lines = {
            "All micro menu buttons open their windows again — the emptied default micro menu shell was invisibly swallowing clicks on the relocated buttons.",
            "Fixed a blocked-action error when the stance bar updated during combat; stance button visibility now only changes out of combat, while icon tint, cooldown and the active marker keep updating live.",
        } },
    } },
    { version = "1.34.0", sections = {
        { category = "Action Bars", lines = {
            "NEW: An Action Bars module puts every action bar on its own movable frame — action bars 1 to 5, the stance bar and the pet bar — each placed and scaled in Edit Mode and configured on its own.",
            "The main bar pages correctly with druid, rogue, warrior and priest forms, and your keybinds keep working on every bar, with the key shown on the buttons.",
            "Per bar: visibility (always, mouseover, in or out of combat), opacity, icon size, buttons per row, spacing, vertical layout, reverse order, and hiding the keybind or macro text — with adjustable text sizes for keybind, macro, count and cooldown numbers.",
            "Empty slots can be hidden and reappear automatically while you drag an ability onto the bar, and a bar can be made click-through.",
            "Cooldown and look settings for all bars: cooldown sweep darkness, desaturating icons on cooldown, colouring icons while the target is out of range, and hiding button tooltips always or only in combat.",
            "NEW: An own experience bar with adjustable width, height and colour, rested overlay and progress text — it replaces the default bar while enabled and hides at the level cap.",
            "The micro menu, the bag bar and the performance bar sit on movable holders, and each of them can be hidden — as can the default experience bar.",
            "Off by default: the standard bars stay untouched until you enable the module, and disabling hands everything back (a reload fully restores the default bars).",
        } },
        { category = "Dark Skin", lines = {
            "The dark button skin now also covers the new action-bar buttons.",
        } },
    } },
    { version = "1.33.0", sections = {
        { category = "Nameplates (German: Namensplaketten)", lines = {
            "NEW: A custom Nameplates module draws its own health bar, cast bar, name and health text over enemy and NPC nameplates — fully configurable, with a live preview that updates as you change each option.",
            "Health bar with your choice of texture, width, height, background, and a border drawn as thin lines or a texture, all in your own colours.",
            "Colouring by reaction (hostile, neutral, friendly, tapped) and by class for players, plus role-based threat colouring for tanks and damage dealers.",
            "Target and focus highlight rings, and an optional fade for plates that are not your target.",
            "Cast bar with spell icon, spell name, and a separate colour for casts that cannot be interrupted.",
            "Aura rows: your debuffs (or all of them), enemy buffs, and a separate prominent row for crowd control such as Polymorph, Fear and Sap. A glow marks enemy buffs you can steal or dispel.",
            "Combo point pips on your target for Rogues and Druids in cat form.",
            "Raid target markers (skull, cross, and the rest) with adjustable size and position.",
            "Friendly plates can show name only, the full plate, or nothing — set separately for players and NPCs — and can show a friendly NPC's subtitle under its name.",
        } },
    } },
    { version = "1.32.0", sections = {
        { category = "Interface Skins", lines = {
            "NEW: A single \"Dark Skin\" module now covers the dark action-button and WeakAuras skin plus the optional Dark Mode that darkens Blizzard's default frames — those used to be two separate modules. Your existing settings carry over.",
            "The reskin modules (skins, character panel, chat, friends list, minimap) are now one tabbed entry, matching how the other groups are already organised.",
        } },
        { category = "Settings Window", lines = {
            "Consolidated groups now list their modules as a vertical, icon-labelled column instead of a wrapping row of tabs — easier to scan when there are many.",
            "NEW: A \"Patch Notes\" page under Overview shows every version's changes right in the game.",
        } },
        { category = "German client", lines = {
            "Cleaner tab names for a few tools: Training, Leisten-Profile, Apexis-Minispiel, Gruppensuche.",
        } },
    } },
    { version = "1.31.0", sections = {
        { category = "Unit Frames", lines = {
            "The target-frame extras and the elite player-frame border are now a single module called \"Player & Target Frame\". Your existing settings and per-character on and off state carry over automatically.",
        } },
        { category = "Profiles", lines = {
            "NEW: Settings now default to a separate profile per class, so what you set on one class no longer changes another. Your current settings are copied into each class profile, and you can still share or pin profiles as before.",
        } },
        { category = "Combat Text", lines = {
            "Scrolling messages that fire at the same moment now stack with a gap instead of overlapping.",
        } },
        { category = "Fishing", lines = {
            "Fixed an error that could appear when combat started while your line was cast. The sound and interact settings now restore after combat ends instead.",
        } },
        { category = "Performance", lines = {
            "Lighter cast bar time text, cooldown bars that batch their refreshes during busy moments, a cheaper combat-log check for the cooldown pulse, and a lighter minimap hover check.",
        } },
        { category = "Character Panel", lines = {
            "The spell stats are ordered spell power, healing, spell crit, then spell hit.",
        } },
        { category = "German client", lines = {
            "The Fishing and Mail tabs now read \"Angeln\" and \"Post\".",
        } },
    } },
    { version = "1.30.1", sections = {
        { category = "Character Panel", lines = {
            "NEW: A style dropdown at the top of the module options. Classic+ keeps the current look; Modern is a new dark, single-window style.",
            "Modern reskins the whole character window dark with an accent border and a stats panel on the right: a big equipped item level, then collapsible categories — attributes, melee, spell, defense and resistances — with per-stat hover breakdowns and mouse-wheel scrolling.",
            "Under Modern the built-in stats, resistance icons and the model rotate arrows are hidden, and the reputation, skills and player-versus-player sub-tabs plus the bottom tabs are skinned to match. Everything switches back to Classic+ live, and adapts per client (rating stats only where they exist).",
        } },
        { category = "UI Reskin", lines = {
            "NEW: Dark skin for a world-map options window, with its own on and off switch in the Addon Skins options.",
        } },
        { category = "Minimap", lines = {
            "The clock now sits on the same line as the date and zone instead of floating higher.",
        } },
    } },
    { version = "1.30.0", sections = {
        { category = "UI Reskin", lines = {
            "NEW: Dark skin for a loot-distribution addon — its award and roll windows, its settings and overview windows, and the two always-visible roll and bid bars get the house panel, accent border and flat close button.",
            "NEW: Dark skin for an attunement tracker — the main window and its buttons match the dark look; the colored status rows stay as they are so the state colors remain readable.",
            "Both are separate on and off switches in the Addon Skins options, next to the others.",
        } },
    } },
    { version = "1.29.0", sections = {
        { category = "Equipment Sets", lines = {
            "Fixed: an expanded set sometimes would not collapse on the second click of its arrow. The arrow is also easier to hit now.",
            "The slot flyout can now equip not-yet-bound items too — with the game's own \"this will bind to you\" confirmation before it soulbinds.",
        } },
        { category = "Chat", lines = {
            "Item levels in links now only show on uncommon (green) and better gear — grey and white trash no longer gets a number.",
            "No double number when another loot addon already tagged the item with its item level.",
        } },
    } },
    { version = "1.28.0", sections = {
        { category = "Minimap", lines = {
            "NEW: The date now shows next to the clock in the zone panel — click it to open the calendar, hover for the full date. Optional in the minimap settings.",
            "The zone panel is a touch wider so the zone name, clock and date sit more comfortably.",
        } },
    } },
    { version = "1.27.0", sections = {
        { category = "Equipment Sets", lines = {
            "NEW: Hover an equipment slot in the character window for a compact flyout of matching items from your bags — click one to equip it. The modifier-click picker is still there for a larger, pinnable window.",
        } },
    } },
    { version = "1.26.0", sections = {
        { category = "Bags", lines = {
            "Item levels on gear are now tinted in the item's quality color, matching the rest of the window (toggle in the options).",
            "Section headers gained a thin divider line and a collapse control — click a category header to fold it away. The state is remembered per category.",
            "The window title now shows the used and total item count.",
        } },
    } },
    { version = "1.25.0", sections = {
        { category = "Global", lines = {
            "NEW: Theme color — pick the accent color in the global settings (presets or your own). Everything purple follows it, saved per profile.",
            "NEW: Pin a profile to a single character; at login it beats the class assignment and the account-wide selection.",
        } },
        { category = "Cooldown Manager", lines = {
            "NEW: Track your own debuffs on the target, or set up a missing-buff reminder group (icon shows while the buff is absent).",
            "Icons tint blue when you are out of mana and red when the target is out of range; ready-only groups now pack without gaps.",
            "NEW: Auto-track your equipped trinkets, duplicate a whole group, and optional hover tooltips.",
        } },
        { category = "UI Reskin", lines = {
            "NEW: Dark skin for the guild & communities window — flat tabs, list cards, roster and chat panels.",
        } },
    } },
    { version = "1.24.0", sections = {
        { category = "Player Castbar", lines = {
            "NEW: Pushback readout, a latency window on casts (the spell-queue moment), a crafting-series counter (e.g. 3/20), timer format options, accent/class fill colors and smoother fill on time jumps.",
        } },
        { category = "Combat Text", lines = {
            "Reworked with inline spell icons and bracketed spell names; separate purge, incoming-dispel, buff-given/received and spell-reflect messages, with anti-spam throttling.",
            "NEW: Death announcements for group members with class-colored names.",
        } },
        { category = "Bank", lines = {
            "NEW: A per-character snapshot of your bank contents, viewable anywhere from the bag window — with tooltips and smart search.",
        } },
    } },
    { version = "1.23.0", sections = {
        { category = "NEW — Guild Bank", lines = {
            "A dark guild bank window with tabs, search, a money log, deposit/withdraw and engine-based sorting.",
        } },
        { category = "Friends & Reskins", lines = {
            "Full dark reskin of the friends window with class crests, row layout, tabs and a battletag pill.",
            "NEW: Addon Skins module — matches supported third-party windows to the dark look, including a quest tracker with accent headers.",
        } },
        { category = "Bags & Bank", lines = {
            "NEW: Smart search keywords (quality, type, item level) that also search an open bank and guild bank.",
            "Bind-on-equip and junk markers, keyring separation, and a fixed-slot OneBag layout.",
        } },
        { category = "Equipment Sets", lines = {
            "Availability markers, set-preview tooltips, true partial sets, and an item-level/set warning in the disenchant queue.",
        } },
    } },
    { version = "1.22.0", sections = {
        { category = "Quality of Life", lines = {
            "Rebuilt sort engine (bags, bank and guild bank) that keeps materials and gear apart.",
            "Minimap and totem-bar improvements, plus framework hardening for the current clients.",
        } },
    } },
    { version = "1.21.0", sections = {
        { category = "NEW — Bags & Bank", lines = {
            "A single unified inventory window: search, sort, categories, custom groups, pinned & recent items, keyring, quick-drop, item levels and quality borders.",
            "A new bank window with slot purchasing.",
        } },
        { category = "Quality of Life", lines = {
            "Friends counter in the chat, a gold overview tooltip, and taint-free Edit Mode movers.",
        } },
    } },
    { version = "1.20.1", sections = {
        { category = "Fixes", lines = {
            "Chat module polish and localization fixes.",
        } },
    } },
    { version = "1.20.0", sections = {
        { category = "NEW — Chat", lines = {
            "A reworked chat: timestamps, class-colored names, clickable links, short channel names, a dark panel with an icon sidebar, idle fade and history that survives a reload. Every part is optional.",
        } },
    } },
    { version = "1.19.0", sections = {
        { category = "Edit Mode", lines = {
            "NEW: Per-frame free-move and an anchor toggle, with panel polish.",
            "Dark border on the action bars; fixed a compat-frame taint issue.",
        } },
    } },
    { version = "1.18.0", sections = {
        { category = "NEW — Dark Mode", lines = {
            "A dark-mode module, plus German localization fixes.",
        } },
    } },
    { version = "1.17.0", sections = {
        { category = "Quality of Life", lines = {
            "General fixes and polish.",
        } },
    } },
    { version = "1.16.0", sections = {
        { category = "Quality of Life", lines = {
            "NEW: The Loadouts sidebar on the character window can now be moved. Turn on edit mode, then drag the purple box (arrow keys fine-tune, right-click to reset its position).",
        } },
        { category = "Unit Frames", lines = {
            "Classic Era: fixed the elite player-frame border alignment and moved the level badge into place.",
        } },
    } },
}
