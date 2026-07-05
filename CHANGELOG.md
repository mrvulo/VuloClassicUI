# VuloClassicUI — Changelog

<!--
  HOW THIS WORKS
  On every `v*` tag, .github/workflows/discord.yml posts the TOP "## <version>"
  section below to the Discord changelog channel (with the @updates role ping).
  For each release: add a NEW "## <version>" block at the very top, in this style:

  ## 1.17.0
  **Category:**
  - **NEW:** a brand-new feature.
  - a change or fix.

  Category labels are bold (**...:**), items are "- " bullets, and "**NEW:**"
  marks additions. Discord renders this markdown as-is. Keep a version under
  ~1900 characters or it gets truncated with a link to the full notes.
-->

## 1.16.0
**Quality of Life:**
- **NEW:** The Loadouts sidebar on the character window can now be moved. Turn on edit mode, then drag the purple box (arrow keys fine-tune, right-click to reset its position).

**Unit Frames:**
- Classic Era: fixed the elite player-frame border alignment and moved the level badge into place.

## 1.15.0
**Compatibility:**
- **NEW:** Full **Classic Era (1.15.8)** support alongside Burning Crusade Classic (2.5.5). TBC-only content (Arena frames, gem sockets) auto-disables on Era; everything else runs on both.

**UI Reskin:**
- The Character Panel enhancements (item level per slot, shortened enchant text, average item level) now work on Classic Era as well.

**Bug Fixes:**
- Fishing: muted the reel error spam ("Unknown unit" / "Out of range") while fishing.
- Mail: "Open All" is faster and now reliably empties the whole mailbox in a single click, even past the 50-mail batch limit.
