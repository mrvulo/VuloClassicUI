## 1.62.0
**Auras:**
- **NEW: Auras** – Your buffs and debuffs as rows of dark icons with the time left underneath, in place of the game's own frames; right-click cancels a buff, weapon enchants ride along, and the two rows move in edit mode
- Built on the game's own secure aura rows, so cancelling works in combat too. The module ships disabled: switch it on under HUD.

**Combat Meter:**
- **NEW: Enemies** – A tenth mode that lists what the group hit: each enemy with the damage it took, every mob of a kind folded into one row, and the attackers behind it in the tooltip
- **NEW: Keep your own bar in view** – When your bar scrolls out of the window it stays pinned at the top or bottom edge with its real rank
- **NEW: Back to the current fight on pull** – A window parked on a previous fight returns to the running one when the next fight starts
- The death tooltip ends with a death recap: the last hits and heals before the newest death, each with the seconds before it, the amount, the health left afterwards and the overkill of the killing blow. Healing received counts, so a death shows what came in as well as what took it.
- A keybinding under VuloClassicUI in the game's key bindings shows and hides every meter window at once; the hidden state is never saved, so a reload brings the windows back.
- **NEW: Mode follows your talents** – The first window opens on healing while your talents make you a healer and on damage otherwise, switching with your spec
- A left-click on a bar turns the window into that player's ability list for the current mode, sorted by value with the share of their total; right-click or a click on the title goes back. The list is not saved, and a mode or segment change leaves it.

**Quest Tracker:**
- **NEW: Quest Tracker** – The quest watch list in the addon font with accent titles and green finished objectives, movable in edit mode once you drag it; until then it keeps the game's own place

**Settings Window:**
- Every module row in the sidebar carries its own glyph now. The combat meter, the action ring, the trackbars, the talent window, the nameplate role fix and the new auras and quest tracker used to show the placeholder.

**Trackbars:**
- **NEW: Vertical** – A bar can stand upright: full height on the left or right screen edge or free-standing, with its blocks stacked top-down
- **NEW: Professions** – One icon per profession with its skill rank; a crafting icon opens its window, and the secondary skills are optional
- **NEW: Hearthstone** – A button that uses the hearthstone, with the inn it is bound to beside it and the cooldown while it runs
- **NEW: Combat timer** – How long the current fight has been running, and the last fight's length out of combat
- A fifth template, Side bar, puts professions, hearthstone, combat timer and clock on the left screen edge.
- The professions block expands the Professions and Secondary Skills headers of the skills window if they were collapsed: the game hides collapsed lines from addons. Other headers keep their state.
