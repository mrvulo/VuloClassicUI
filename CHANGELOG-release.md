## 1.39.0
**Arena:**
- **NEW: Diminishing Returns Position** – Put the DR row on either side of the frame, with its own X and Y offset
- The DR row no longer lands on top of the trinket or racial icon. It used to hang at a fixed distance on the right edge, exactly where the side icon sits, so switching it on stacked the two. The new default clears it, and on the left edge the row grows outward instead of across the frame.
- The trinket and racial icons sit further out from the enemy frame and are a little smaller, so the health and mana bars read as the middle of the frame instead of competing with an icon at each shoulder. Both are sliders, so your own values are kept.

**Download:**
- The addon folder no longer ships build tools and source files that no player needs. The licence files stay where they are.
- The release notes on the distribution pages are written in English now.

**Languages:**
- Six languages were missing seven texts that existed in German only. All nine are complete again.
- The keyword help for the item search was misleading in Chinese: it gave an English type name as the example, which a Chinese client would never have matched. The example is written in the reader's own language now.

**Paladin:**
- **NEW: Seal Twist Helper** – A swing bar with the twist window marked, plus the next sensible action
- The bar counts down to your next auto attack with two marks: green is the last moment the second seal can still land, purple is how long a Judgement still fits in front of it. The next action is worked out live from your swing timer, the global cooldown and the seals actually on you — not from a fixed rotation. Crusader Strike is only suggested while there is room for it and the holding seal afterwards. Judgement deliberately gets none: it consumes the seal, and a wrong hint costs more there than no hint. Off by default.
