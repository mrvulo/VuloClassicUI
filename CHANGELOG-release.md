## 1.50.0
**Bar Setups:**
- **NEW: Export as string** – Packs the selected setup into a string you can pass on, with its slots, macros and key bindings
- **NEW: Import from string** – Reads someone else's setup into your library; a name you already use gets a number rather than being overwritten
- An imported setup is rebuilt entry by entry before it is stored. The restore walks every entry, so a malformed one would have thrown in the middle of a run with part of your bars already changed. Broken entries are dropped, the rest still arrives.
- Saving and loading say what they did. Both had been counting their work all along and throwing the numbers away, so a setup whose macros all failed looked exactly like one that had none, and a save that captured no key bindings said nothing at all.

**Edit Mode:**
- The character window can be placed by hand on the Wrath client. Blizzard's editor does not own that window, so it takes the same direct route the loot window already uses; one box moves the character, reputation and skills tabs together, and the stats panel and set list travel with it.

**Friends List:**
- The window starts wide on the Wrath client. The slider has always gone to 400 — it simply started at nothing, so the extra room only ever reached whoever went looking for it.

**Talent Window:**
- The glyph page opens from a button under the talent group buttons, and it is dark now. The rune circle is dimmed rather than removed, because it is what makes that page recognisable; the sockets take the accent colour, and the glyph artwork and the pickup highlight stay as they are.
- The talent group button shows its tree's icon instead of a question mark. It asked for that icon through an interface that does not answer on every client, and fell back to the placeholder; the answer is now worked out from the ranks themselves, which cannot be misread.

**Unit Frames:**
- The level number on the player frame sits where the client puts it on the Wrath client. Our two anchors are measured against one frame sheet, and where a different one ships, the number landed beside the portrait — the client keeps that anchor itself there anyway, moving it as the rest and PvP icons come and go.
