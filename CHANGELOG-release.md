## 1.43.0
**Character Panel:**
- The character window stayed empty on clients we had never named. The panel asked whether the client called itself one of two specific versions and refused every other one, including clients that have exactly the frames it needs. It now asks for the one thing it cannot work without. Enchants, sockets and item stats were missing for the same reason and return with it.
- Hit rating, haste rating and spell hit rating appear on Wrath-based clients too. They were tied to a single version by name, although the game there has those stats.
- The stat rows Wrath draws in pages with two dropdowns are hidden underneath our own panel now, instead of showing through it.

**Compatibility:**
- **NEW: Titan Reforged** – The addon no longer reports itself out of date on the Chinese client, whose build is listed now
- Version detection falls back to the build number whenever a client reports an identifier we have no name for. Such a client used to end up with every version flag false, which left it worse off than a client with no identifier at all, because that one at least fell back to something.

**Languages:**
- 242 texts that nothing in the interface looks up any more are gone from all nine language files, roughly eight percent of each. Renamed settings left them behind: the action bars were given clearer names a while ago and the old entries simply stayed. A check now asks the reverse question after every change, whether every translated text is still in use, so they cannot pile up again.

**Shaman:**
- **NEW: Call button** – A fifth totem button for the spells that summon a whole saved totem set, shown only to characters who know one
