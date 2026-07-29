## 1.42.0
**Action Bars:**
- Switching the module off used to leave the bag bar, the latency bar and Action Bar 1's twelve buttons behind until a /reload. All three come back on their own now.

**Cooldown Manager:**
- **NEW: Watch this unit** – A group can follow your target, your focus or your pet instead of you
- **NEW: Only what I cast myself** – A group can require the aura to be your own, not anyone's
- **NEW: Order** – Sort a group by the time left instead of the order you added things in
- Conditions belong to the individual entry now, not only to the kind of group it sits in. One entry can ask for a stack count or for the last few seconds while its neighbours ask for nothing.

**Languages:**
- The twist is now called twist in every language, the word paladins use themselves. German called it Siegelwechsel; the helper and its window are named after the twist instead.

**Nameplates:**
- **NEW: Cast bars in front of other plates** – So the cast you are watching is not hidden behind the plate beside it
- **NEW: Darken enemies out of combat** – With its own strength, so an idle mob reads as idle at a glance
- **NEW: Highlight strength** – How far the plate under your cursor lifts out of the row
- The clickable area is measured from the plate now instead of assumed, so the width and height settings land where your cursor really is.

**Paladin:**
- **NEW: Practice** – A swing clock that runs on its own, with your own keys and a verdict on every swing
- **NEW: Next action** – An icon of the one thing to press, wherever you put it
- **NEW: Latency** – Calibrate the delay a twist has to beat, with its own multiplier and offset
- **NEW: Shade the deadzone** – The tail of the swing a cast can no longer cross
- **NEW: Show the global cooldown bar** – A strip reaching to the moment the cooldown frees up
- **NEW: When to show the bar** – Always, in combat, while a seal is up, or either
- **NEW: Colour the bar by** – The zone the swing is in, or the seal you are carrying
- **NEW: Detach from the bar** – The seal icons take their own position, with a cooldown sweep
- **NEW: Suggest Judgement** – Offered only with room to re-seal afterwards, and off until you ask
- The cue for a landed twist no longer guesses. It used to fire the moment a seal went out inside the window, which is a prediction the server can disagree with. Now the combat log has to show a swing landing with both seals up and the held seal's own damage behind it. Without that, nothing sounds.
- Textures, border, font, frame layer, marker width and the two readouts inside the bar are yours to set, and every seal has its own colour.

**Settings:**
- Rows that span the page now start their control where their neighbours do, instead of each sizing its own label.
- A dropdown with more entries than fit on screen scrolls instead of running off the bottom, and a label that had grown too long fits its row again.
