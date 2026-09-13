## 1.62.0
**Auras:**
- **NEW: Auras** – Your buffs and debuffs as rows of dark icons with the time left underneath, in place of the game's own frames; right-click cancels a buff, weapon enchants ride along, and the two rows move in edit mode
- Built on the game's own secure aura rows, so cancelling works in combat too. The module ships disabled: switch it on under HUD.

**Bar Textures:**
- The bundled bar textures never loaded: fifteen of the seventeen were 256 by 40 pixels, and the client draws only textures whose sides are powers of two, so every choice in a texture dropdown fell back to the same flat fill. They are 256 by 32 now and each one looks like its name. One full client restart is needed; a reload is not enough.

**Cast History:**
- **NEW: Cast History** – A strip of icons for the spells you just cast, newest first, a failed or interrupted cast in red; size, count, direction and fade are options, and the strip moves in edit mode. Ships disabled.

**Combat Meter:**
- **NEW: Enemies** – A tenth mode that lists what the group hit: each enemy with the damage it took, every mob of a kind folded into one row, and the attackers behind it in the tooltip
- **NEW: Keep your own bar in view** – When your bar scrolls out of the window it stays pinned at the top or bottom edge with its real rank
- **NEW: Back to the current fight on pull** – A window parked on a previous fight returns to the running one when the next fight starts
- **NEW: Spec icon** – The bar can show a player's talent tree instead of the class: read from your own talents, from a talent-only spell in the log, or from an inspect in range, with the class icon standing in until then
- **NEW: Hit statistics** – Hovering a row of the ability breakdown shows the hits, the critical hits with their share, and the average, smallest and largest amount
- **NEW: Active time** – The per-second values can divide by the seconds a player was actually casting or hitting instead of the whole fight; the tooltip shows the active time either way
- **NEW: Bar colour and window background** – A custom bar colour instead of the class colour, the window's background colour and opacity, the spacing between bars, bars that grow upwards from a title at the bottom, and a scale per window
- **NEW: Reset on entering an instance** – A new dungeon or raid resets the overall total at once, after a question, or never
- The death tooltip ends with a death recap: the last hits and heals before the newest death, each with the seconds before it, the amount, the health left afterwards and the overkill of the killing blow. Healing received counts, so a death shows what came in as well as what took it.
- A keybinding under VuloClassicUI in the game's key bindings shows and hides every meter window at once; the hidden state is never saved, so a reload brings the windows back.
- **NEW: Mode follows your talents** – The first window opens on healing while your talents make you a healer and on damage otherwise, switching with your spec
- A left-click on a bar turns the window into that player's ability list for the current mode, sorted by value with the share of their total; right-click or a click on the title goes back. The list is not saved, and a mode or segment change leaves it.
- The windows can hide in arenas and battlegrounds, next to the existing switch that hides them outside a group.

**Quest Tracker:**
- **NEW: Quest Tracker** – The quest watch list in the addon font with accent titles and green finished objectives, movable in edit mode once you drag it; until then it keeps the game's own place

**Settings Window:**
- **NEW: Search that lands on the row** – A hit in the settings search opens its page, unfolds the gear or section hiding it, scrolls to the row and lights it up; the list shows the path to each hit, the arrow keys and Enter walk it, tooltips are searched too, and /vcui search <word> opens the window with the word already typed
- **NEW: Changed marker** – A dot on the left edge of every setting that differs from its default; hovering shows the default, a click puts it back. A Changed chip above the page counts them and filters the page down to only those rows
- **NEW: Section chips** – A page with two or more headings carries a row of chips above it: a click scrolls to the heading, and the heading under the top edge is lit while you scroll. Every heading also shows how many settings it groups
- **NEW: Pinned modules** – A pin on each sidebar row, shown on hover, keeps the module in a Pinned group at the top of the sidebar; a filter box above the list narrows it by module, group, tab or the name of a module folded into a container
- **NEW: Recently changed** – The overview lists the last settings you changed with how long ago, each a click away from its row, and lays every sidebar group out with its modules as chips
- **NEW: Settings from the editor** – The edit-mode panel of a selected box carries a gear that closes the editor and opens that element's settings page
- When the tabs outgrow their row, a menu beside the arrows lists them all, and the title bar names where you are: group, module and tab.
- Every module row in the sidebar carries its own glyph now. The combat meter, the action ring, the trackbars, the talent window, the nameplate role fix and the new auras and quest tracker used to show the placeholder.

**Trackbars:**
- **NEW: Vertical** – A bar can stand upright: full height on the left or right screen edge or free-standing, with its blocks stacked top-down
- **NEW: Professions** – One icon per profession with its skill rank; a crafting icon opens its window, and the secondary skills are optional
- **NEW: Hearthstone** – A button that uses the hearthstone, with the inn it is bound to beside it and the cooldown while it runs
- **NEW: Combat timer** – How long the current fight has been running, and the last fight's length out of combat
- A fifth template, Side bar, puts professions, hearthstone, combat timer and clock on the left screen edge.
- The professions block expands the Professions and Secondary Skills headers of the skills window if they were collapsed: the game hides collapsed lines from addons. Other headers keep their state.
