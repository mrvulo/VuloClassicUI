## 1.61.0
**Combat Meter:**
- **NEW: Threat** – A ninth mode that shows the threat list of your current target live: the tank on top, everyone else in percent of the tank, pets as their own rows
- **NEW: Previous fights** – The title menu keeps the last finished fights, named by their boss and duration, and any window can be pinned to one of them
- **NEW: Report** – Send the top rows of a window to a chat channel from its title menu: say, party, raid, guild, officer or a whisper to a name you type
- The threat mode reads the game's own threat list and updates only while a window shows it; a target change redraws at once. It ignores the segment choice and the bracket switches, and it exists only on clients that expose the threat list.
- A window pinned to a previous fight stays there when the next fight begins and drops back to its saved segment when that fight leaves the list. The list lives until a reload; the number of fights kept is an option, and a fight in which nobody scored is not listed.
- The report carries a header with mode, segment and duration, then one line per row with the value, the per-second value and the share; the number of rows is an option. An empty window sends nothing.
- The overall total moves during the fight: every hit lands in the running fight and in the overall at once, so an overall window no longer waits for the fight to end, and a reload or crash mid-fight keeps what was already counted.
- Hovering a damage or healing bar also lists the targets the damage went to or the players the healing went to, with value and share, below the abilities.
- The interrupt and dispel modes carry their own German titles now instead of the arena verbs.
- Every change made from the title menu, such as a new mode or a closed window, ended in a silent Lua error after the visible work, and the options page did not follow the change. The helper that refreshes the page was called before it was defined.

**Languages:**
- Patch notes of versions that have left the in-game list are gone from all nine languages; nothing the interface shows was affected.

**Setup:**
- **NEW: First-time setup** – A fresh install opens a three-step window after the first login: pick a template, set font and scale, reload
- Four templates to start from: Standard as the addon ships, Minimal with only the dark look and no HUD modules, Healer with the meter on healing plus power bar and reminders, and PvP with the arena frames, the trinket tracker, power bar and reminders. A template switches modules for the class profile and for classes rolled later; every setting stays editable, and nothing is switched live: the template is written when the window is finished and the reload applies it.
- The setup is there again any time through the command below and a button under Global Settings, and it starts from the template chosen last time: /vcui setup

**Swing Timer:**
- **NEW: Show ranged bar** – A third bar for the auto shot or wand shoot while a bow, gun or wand is equipped, with the aim window marked at its end
- The ranged clock starts on each shot the client reports and stops with auto-repeat. Moving or casting inside the aim window holds the shot back, and the bar holds at the edge of that window until you stand still or finish the cast; weapon haste rescales the bar except inside the window. The module now also serves hunters and wand users, who used to be turned away at login as no melee spec.
