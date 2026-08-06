## 1.52.4
**Character Panel:**
- **NEW: Ask before overwriting a gem** – A click on a socket that already holds a gem asks first, because putting a gem in destroys the one that comes out
- Pointing at an occupied socket says what a click on it costs. Clicking one was always allowed, nothing ever said so, and the gem that comes out is destroyed. The question names both gems in their quality colours, and it drops the action when the gear moved while it was standing — otherwise a swap under the open dialog would answer for a socket you never looked at.

**Loadouts:**
- Equipping a set at the bank takes the pieces that are lying in the bank, as long as the bank window is open. Until now they counted as missing, so you could stand at the bank and be told the set was not equippable. The message says how many of them came out of the bank, and the piece that comes off goes into the bank slot the new one came from. With the bank closed, a missing piece in there no longer only names its place, it says to open the bank window.
- The line that tells you which sets an item belongs to appears in item tooltips. It was built and hooked up from the start, but it went in through the one tooltip mechanism this client offers and never uses, so no line was ever drawn and nothing complained.

**Nameplates:**
- **NEW: Reverse the swipe** – The shade grows back as the aura runs out, so a nearly clear icon means it is nearly gone
- The cooldown swipe on the aura icons has a control of its own. It was read from the start and could not be changed anywhere.
- The raid target marker is visible at all. The eight marks live on one sheet, and the call that picks a tile out of it was working on a frame that never got the sheet — a cut-out of nothing, on every plate and in the preview, since the module was built.
- The raid target marker takes one of the six named slots, like the four aura rows. It had three positions of its own and could land on top of a row, which is the very collision the slots exist for. The old choice moves into the matching slot once and then goes, so there is no second control for the same question. Its room is reserved as soon as it is switched on, not only once a unit really carries a mark, so the rows do not jump every time somebody sets a skull.
- The marker's own offset and spacing sliders take effect again. They were writing two fields of their own while the plate read the slot, so the visible control was the one without an effect. The old values move across once.
- A mark set between two aura passes lands where it belongs. Where the marker goes is worked out in the aura pass, because only that knows how far the rows on its side reach, and the plate now remembers that point for the event that shows the marker on its own.
- The cast time and the cast target show something in the preview. Both only exist for a cast that is really running on a real unit, so both stayed empty while their switches, colours and side settings stood next to them with nothing to show.
