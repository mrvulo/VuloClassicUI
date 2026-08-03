## 1.52.0
**Chat:**
- The own background for the input line is offered on every client. It was limited to one client generation, and the code already said it would work everywhere.

**Cooldown Manager:**
- The icon borders are pixel-exact. The border there is not a texture of its own but the rim of a plate behind the icon, so the two have to sit on the same pixel grid, the thickness has to be counted in pixels rather than frame units, and the icon size and spacing have to begin on whole pixels. None of the three was true, which is why a rim came out two pixels on one edge and none on the opposite.

**Nameplates:**
- **NEW: Apply this arrangement** – Puts the unit name and the health value inside the bar, crowd control left of it, incoming debuffs above that and buffs to its right, with the cast bar carrying its icon, its remaining time and its target
- The unit name was hidden behind the health bar fill as soon as a text slot put it inside the bar. The name and the health value hang from different parents: the value is created on the bar, the name on the plate, and the bar is a child of the plate — so it draws over anything the plate draws. While the name only ever sat above the bar this never showed. It has its own layer now, above the bar but not attached to it, because name-only mode hides that bar and a text parented to a hidden frame would go with it.
- The health text has its controls back: what it shows, and which mark goes between the two numbers. Both were still being read and had been unreachable since the page was rebuilt.

**Talent Window:**
- The active talent group was always reported as the first one on clients that do not carry the newer interface for it. Everything behind that believed group one was running: the header called the group you were standing in not active, the activate button offered to switch to the one already on, and the switch reported success while changing nothing. Five files ask that same question, so profile overrides and bar setups were reading it too.
- The glyph page stands permanently beside the window. It is lifted out of Blizzard's talent frame, where it lives inside the scroll area of the very window we replace, and handed back when ours closes.
- The separate glyph button is gone with it. Its only job was to send you to the page that now stands in front of you.
- A band under the header carries the activate button and the name of the talent group on screen. Until now switching existed only as a right-click on the small side icons, and nothing announced it.
