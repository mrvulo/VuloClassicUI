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
