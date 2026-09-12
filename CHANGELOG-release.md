## 1.60.1
**Combat Meter:**
- Environmental damage counts as damage taken: falling, drowning, lava and the like land on the victim under their kind, appear in the breakdown and can be the killing blow. A fall used to leave no trace, and the death line named the spell before it instead. A death without a source shows only the amount.
- The window rows on the options page no longer take part in talent overrides. Every window carries the same row label, so an override for one window switched the mode of all of them.

**Profiles:**
- A partial export keeps a chosen module that stands entirely on its default values. Stripping the defaults used to remove the whole module table, and the import, which replaces module by module, then kept the receiving profile's own values instead. An empty table now means: this module, on defaults.

**Settings:**
- Talent overrides survive a language change. Their identifiers carried the translated label, so after switching the game language the saved settings were no longer found and nothing was applied. They carry the English key now, and identifiers saved earlier are converted once on load in every profile.
