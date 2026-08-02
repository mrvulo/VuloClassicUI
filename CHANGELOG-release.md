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
