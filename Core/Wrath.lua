-- VuloClassicUI / Core / Wrath
--
-- Everything this addon knows about the Wrath-generation client, which is the
-- one Titan Reforged ships (interface 38001/38002, WOW_PROJECT_ID 11, client
-- 3.80.x). One place to look, one place to extend.
--
-- WHAT BELONGS HERE
--   Facts about that client generation: which features the game has, which
--   numbers differ, which globals only exist there. Written as capabilities --
--   "does the client have X" -- never as "is this Titan".
--
-- WHAT DOES NOT BELONG HERE
--   The feature code itself. The quest log lives in General.lua, the loot mover
--   in UnlockMode.lua, the talent window in Modules/TalentView.lua, and they
--   stay there: a reader looking for the quest log must not have to know that
--   half of it was filed under a client name. They ask this file a question and
--   act on the answer.
--
--   Nor does anything that merely SURFACED on that client. The enchant filter
--   that only knew English and German prefixes, the dropdown that could not
--   scroll to its end, the settings file that died on a non-finite number --
--   all reported from Titan, none of them Titan's fault, all of them fixed for
--   every client. Filing those here would hide from the next reader that they
--   are general.
--
-- HOW TO EXTEND
--   Add a capability below with a one-line reason, then have the module ask for
--   it. If the answer is the same on more than one client generation, say so in
--   the expression (isBCC or isWrath) rather than picking the newest -- the
--   flag names are the vocabulary, the capability is the meaning.
--
--   The register of what has been reported, measured and fixed for this client
--   is docs/titan-reforged.md. Behaviour goes here, history goes there.

local _, ns = ...

ns.Wrath = {}
local W = ns.Wrath

-- Is this the Wrath generation at all. Every capability below is derived, so a
-- module never has to read the raw flag; this one exists for the module gates
-- that switch a WHOLE feature on or off (Modules/TalentView.lua).
W.is = ns.isWrath and true or false

-- The character sheet carries hit and haste rating. NOT Wrath-only: the ratings
-- arrived with The Burning Crusade, so the question is what the GAME has, not
-- what the client could be made to report.
W.hasRatings = ns.isBCC or ns.isWrath

-- The quest log is already the wide two-pane frame. Our enlargement is tuned to
-- the single-pane anatomy and shoved the detail pane into the button row there
-- (reported with screenshots from 3.80.x), so it stands down -- and the option
-- is not offered, because a switch that does nothing reads as a fault.
W.hasWideQuestLog = ns.isWrath or ns.isCata

-- The death knight exists as a playable class, and runic power as a resource.
-- Deliberately NOT extended to Cata here: it would be true there too, but this
-- mirrors exactly what the two colour lists did before this file existed, and
-- changing behaviour is a separate decision from moving a fact. See
-- docs/titan-reforged.md, "Offene Fragen".
W.hasDeathKnight = ns.isWrath
W.hasRunicPower  = ns.isWrath

-- Blizzard's Edit Mode does not own the loot window (HasEditModeSettings says
-- no), so both of our placement paths fall through and the mover box would move
-- nothing. Unprotected, so it can be placed onto UIParent straight from Lua.
W.hasMovableLoot = ns.isWrath

-- Totemic Recall is a real spell with its own button, rather than the
-- middle-click shortcut the earlier clients get.
W.hasTotemicRecall = ns.isWrath

-- Three talent trees side by side, dual specialisation and glyphs. The whole
-- replacement window is a Wrath-only feature and lives in its own module.
W.hasTalentTrees = ns.isWrath
