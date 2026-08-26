## 1.57.1
**Action Bars:**
- The form-paging section shows up in Standard mode too. The switch itself already reached the standard main bar; the row that flips it was only drawn in Modern mode, so nobody running the standard bars could find it.

**Performance:**
- Seven hot paths allocate less memory: unit-frame health text, nameplate number formatting and health smoothing, cooldown-manager scan keys, combat-text throttling, bag refreshes, the arena bar-text hook and the reminder pass all reuse what they used to rebuild, so the garbage collector has less to clean up in combat.

**UI Reskin:**
- The red auto-attack blink sits on the icon in every button style now, the untouched standard button included. The game defines that blink with retail-sized frame art and a single corner anchor, so on the classic button art it hung past the button to the right and bottom.
