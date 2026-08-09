## 1.52.6
**Cooldown Manager:**
- **NEW: X Offset / Y Offset** – Nudge the stack and reagent numbers away from their chosen corner; both sit behind the gear of the position row

**Edit Mode:**
- Opening Edit Mode no longer hands the party and raid frames to the addon for the rest of the session. Merely opening it drove the client's frame editor through the addon, and in combat the client then refused to update those frames, naming the addon in the message. Only really moving one of Blizzard's frames still writes to the editor, and a frame that is hidden, like the focus frame while nothing is focused, never does.
- Opening Edit Mode closes the options window. It sat exactly on top of the boxes it had just unlocked.

**Loadouts:**
- The equipment list steps aside for the rune engraving panel. That panel opens on the right side of the character sheet, exactly where the list docks, so the two stood on top of each other. The list now follows the panel's edge, and where the screen is too narrow for sheet, panel and list together, it moves to the left side of the sheet.

**Nameplates:**
- The role fix ships switched off. What it fixes is a silent error that truncates one update when a nameplate appears; what it costs is that the party and raid frames count as touched by the addon for the whole session and refuse to resize in combat, with the addon named in the message. That price was reaching players who never chose it, so now only whoever switches the fix on pays it.
- The status line of the role fix tells the whole truth. With the fix off it used to claim it was not needed on this client, even for players who do have the error; it now says whether the fix is applied, not needed, or simply not switched on while the error is firing.

**Power Bar:**
- The bar ships switched off. A second resource bar is a strong opinion to hand someone who never asked for one, and the client already draws its own. Installations that already exist keep the bar exactly as it was.

**UI Reskin:**
- The dark skin keeps Blizzard's rim off the stance buttons for good. Their updates write the button art back directly, past the hook that guards the action bars, so the rim used to return the first time you switched.
