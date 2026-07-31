## 1.45.0
**Chat:**
- The item level on equipment links sits after the link now, not inside its brackets. Some clients re-check link text against their own data, and the changed text turned the link into the name of whatever quest carried that number.

**Cooldown Manager:**
- A spell no longer shows up on another class just because that class owns a different spell with the same name. Entries respect their class stamp on the bars, and old entries are adopted by spell ID instead of by name.

**Download:**
- The bundled media library silently dropped font registrations when no other addon shipped a newer copy of it; the addon font now registers on every install.

**Equipment Sets:**
- **NEW: Rename...** – In the set's right-click menu and on the sets page; icon, contents and talent binding move along with the name

**Global Settings:**
- **NEW: Optimize My FPS and Graphics** – A proven set of graphics settings with a one-time backup; the restore button next to it brings your old values back
- **NEW: Fonts & Colors** – A new tab: global font with outline mode, optionally for all game texts, plus class and resource colors with a reset on every row
- **NEW: Developer** – Suppress Lua errors, switch tooltip IDs and reset all settings from a new section on the General tab
- The General tab is organised in sections on a two-column grid like the rest of the window. The new tab ships a texture file: restart the client once after updating, a /reload alone will not show the reset arrows.

**Quest Log:**
- The enlargement stays off on Wrath-based clients (Titan Reforged): their quest log is already the wide two-pane frame, and enlarging it pushed the detail pane into the button row.

**Settings Window:**
- Long dropdown lists open upwards when there is no room below. They used to run off the bottom edge of the screen, where the last entries could never be scrolled into view.
