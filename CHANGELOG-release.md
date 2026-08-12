## 1.53.0
**Character Panel:**
- Every row of the stats sheet now explains itself when you point at it, and spell haste has joined the sheet.

**Global Settings:**
- Custom class colours moved into the addon's own colour book. Writing them into the client's shared tables marked the party and raid frames as touched by the addon at every login, and the client then refused to resize them in combat. The clean-up has a price: the client's own windows and other addons show the standard class colours again, while the custom ones colour everything this addon draws.

**Nameplates:**
- **NEW: Edit spell lists** – Every aura row carries an always-show and a never-show spell ID list, kept in its own editing window behind the slot's fine tuning
- **NEW: Low-health glow** – Marks plates below a chosen health percentage, as a thin ring or a soft pulsing glow, in a colour of your choice
- The pulsing glow ships as a new texture file, so it takes one full client restart to appear; a reload is not enough.

**Paladin:**
- The seal-twist helper no longer counts a swing ahead on parries or when attacking starts; its window used to point at a swing that never came.

**Profiles:**
- The import preview no longer sits on top of the paste step of the import dialog.

**Swing Timer:**
- The clock keeps ticking through abilities that replace the swing, Heroic Strike and Cleave among them: they write their own combat log line instead of a swing line, so the bar used to stand still exactly for the classes that queue such an ability on every swing.
- Swing-resetting spells that deal no damage, parried special attacks and extra attacks now reach the clock too.

**UI Reskin:**
- **NEW: WeakAuras style** – A separate icon style for WeakAuras, independent of the action bars, with five Shadow aura sets
- **NEW: Border color** – Tints the frame of the Shadow and shape styles; resetting it restores each style's built-in colouring
- The bar style now starts at Blizzard's own untouched look, and the masked shapes circle, square and hexagon bring their own frames.
