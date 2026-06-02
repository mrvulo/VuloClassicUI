-- =========================================================
-- VuloClassicUI / Modules / SpamFilter
-- Hides (and optionally ignores) chat spammers whose names spell "casino" & co.
-- using look-alike letters (Gãsïnô, Casinòbâbe, ...). The name is normalized to
-- plain ASCII (accents + common Cyrillic/Greek homoglyphs -> a/c/s/i/n/o/...),
-- then matched against a keyword list.
--
-- Note: Blizzard does not allow add-ons to file spam reports (anti-abuse), so
-- we hide the messages (reliable, no limit) and can optionally /ignore the
-- sender (limited to ~50 slots, and spammers rotate names — hence off by
-- default; hiding is the effective part).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("spamfilter", {
    name        = "Spam Filter",
    group       = "QoL",
    description = "Hide (and optionally ignore) chat spammers whose names spell 'casino' & co. with look-alike letters.",
    defaults = {
        enabled       = true,
        hide          = true,   -- swallow their chat messages
        autoIgnore    = false,  -- also add them to the ignore list (~50 slot limit)
        scanMessage   = false,  -- also match against the message text, not just the name
        blockLinks    = false,  -- also hide messages that contain a web link
        extraKeywords = "",     -- comma-separated extra keywords
        whitelist     = "",     -- comma-separated names that are never filtered
    },
})

-- =========================================================
-- Look-alike normalization
-- Map accented / Cyrillic / Greek look-alike letters to plain ASCII so an
-- obfuscated name collapses to a comparable form (Gãsïnô -> gasino).
-- =========================================================
local CONFUSABLES = {
    -- a
    ["á"]="a",["à"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",["ā"]="a",["ă"]="a",["ą"]="a",
    ["Á"]="a",["À"]="a",["Â"]="a",["Ä"]="a",["Ã"]="a",["Å"]="a",["Ā"]="a",["а"]="a",["А"]="a",["α"]="a",
    -- b
    ["в"]="b",["Β"]="b",["ß"]="b",["Ь"]="b",["ḅ"]="b",
    -- c
    ["ç"]="c",["ć"]="c",["č"]="c",["ċ"]="c",["Ç"]="c",["Ć"]="c",["Č"]="c",["с"]="c",["С"]="c",["ϲ"]="c",
    -- e
    ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",["ē"]="e",["ė"]="e",["ę"]="e",["ě"]="e",
    ["É"]="e",["È"]="e",["Ê"]="e",["Ë"]="e",["е"]="e",["Е"]="e",["ё"]="e",["Ё"]="e",["є"]="e",
    -- g
    ["ğ"]="g",["ǧ"]="g",["ġ"]="g",["ģ"]="g",["Ğ"]="g",
    -- i
    ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",["ī"]="i",["į"]="i",["ı"]="i",["і"]="i",["Í"]="i",["Ì"]="i",
    ["Î"]="i",["Ï"]="i",["İ"]="i",["І"]="i",["ї"]="i",["ι"]="i",
    -- k
    ["ķ"]="k",["к"]="k",["К"]="k",["κ"]="k",
    -- n
    ["ñ"]="n",["ń"]="n",["ň"]="n",["ņ"]="n",["Ñ"]="n",["Ń"]="n",["п"]="n",["И"]="n",["и"]="n",
    -- o
    ["ó"]="o",["ò"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ø"]="o",["ō"]="o",["ŏ"]="o",["ő"]="o",
    ["Ó"]="o",["Ò"]="o",["Ô"]="o",["Ö"]="o",["Õ"]="o",["Ø"]="o",["о"]="o",["О"]="o",["ο"]="o",["σ"]="o",
    -- s
    ["ś"]="s",["š"]="s",["ş"]="s",["ș"]="s",["Ś"]="s",["Š"]="s",["Ş"]="s",["ѕ"]="s",["Ѕ"]="s",
    -- u
    ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",["ū"]="u",["ů"]="u",["Ú"]="u",["Ù"]="u",["Û"]="u",["Ü"]="u",
    -- t / r / l filler look-alikes
    ["т"]="t",["Т"]="t",["р"]="r",["Р"]="r",["ł"]="l",["Ł"]="l",
}

local DEFAULT_KEYWORDS = { "asino", "casino", "kasino", "gasino" }

-- normalize(str) -> ascii-lower, letters only, look-alikes folded
local function normalize(s)
    if not s or s == "" then return "" end
    for from, to in pairs(CONFUSABLES) do
        s = s:gsub(from, to)
    end
    s = s:lower()
    s = s:gsub("[^a-z]", "")
    return s
end

-- Active keyword list = defaults + user extras (each normalized). Cached.
local cachedKeywords
local function buildKeywords()
    local list, seen = {}, {}
    local function add(kw)
        kw = normalize(kw)
        if kw ~= "" and not seen[kw] then seen[kw] = true; list[#list + 1] = kw end
    end
    for _, kw in ipairs(DEFAULT_KEYWORDS) do add(kw) end
    for kw in tostring(mod.db.extraKeywords or ""):gmatch("[^,%s]+") do add(kw) end
    cachedKeywords = list
    return list
end

local function matches(s)
    if not s then return false end
    local n = normalize(s)
    if n == "" then return false end
    for _, kw in ipairs(cachedKeywords or buildKeywords()) do
        if n:find(kw, 1, true) then return true end
    end
    return false
end

-- =========================================================
-- Actions
-- =========================================================
local ignoredThisSession = {}

local function maybeIgnore(author)
    if not (mod.db.autoIgnore and author and author ~= "") then return end
    if ignoredThisSession[author] then return end
    ignoredThisSession[author] = true
    local numIgnores = (C_FriendList and C_FriendList.GetNumIgnores and C_FriendList.GetNumIgnores()) or 0
    if numIgnores >= 50 then return end  -- ignore list is full; hiding still works
    if C_FriendList and C_FriendList.AddIgnore then
        pcall(C_FriendList.AddIgnore, author)
    elseif _G.AddIgnore then
        pcall(_G.AddIgnore, author)
    end
end

mod._blocked = 0  -- session counter (shown in options)

-- Whitelist: names that are never filtered (cached set, rebuilt on change).
local cachedWhitelist
local function buildWhitelist()
    local set = {}
    for n in tostring(mod.db and mod.db.whitelist or ""):gmatch("[^,]+") do
        n = normalize(n)
        if n ~= "" then set[n] = true end
    end
    cachedWhitelist = set
    return set
end
local function isWhitelisted(name)
    local set = cachedWhitelist or buildWhitelist()
    return set[normalize(name)] == true
end

-- Toggle a name on/off the whitelist (used by /vcui spam <name>).
function mod.ToggleWhitelist(name)
    if not (name and name ~= "" and mod.db) then return end
    local key = normalize(name)
    if key == "" then return end
    local kept, removed = {}, false
    for n in tostring(mod.db.whitelist or ""):gmatch("[^,]+") do
        local t = n:gsub("^%s+", ""):gsub("%s+$", "")
        if normalize(t) == key then removed = true else kept[#kept + 1] = t end
    end
    if not removed then kept[#kept + 1] = name end
    mod.db.whitelist = table.concat(kept, ", ")
    buildWhitelist()
    if removed then
        ns:Print(string.format(L["Spam filter: '%s' removed from the whitelist."], name))
    else
        ns:Print(string.format(L["Spam filter: '%s' added to the whitelist (never filtered)."], name))
    end
end

-- Web-link detection for the optional link blocker.
local TLDS = { "com","net","org","io","gg","ru","xyz","info","vip","club","online","shop","site","top","live","biz" }
local function hasLink(s)
    s = (s or ""):lower()
    if s:find("https?://") or s:find("www%.") then return true end
    for _, tld in ipairs(TLDS) do
        if s:find("[%w%-]%." .. tld .. "%f[%A]") then return true end  -- domain.tld at a word boundary
    end
    return false
end

-- Chat message filter: return true to swallow the message.
local function chatFilter(_, _, msg, author)
    if not (mod._enabled and mod.db) then return false end
    local name = author and author:gsub("%-.*$", "") or ""   -- drop -Realm
    if isWhitelisted(name) then return false end
    local nameHit = matches(name)
    local hit = nameHit
        or (mod.db.scanMessage and matches(msg))
        or (mod.db.blockLinks and hasLink(msg))
    if not hit then return false end
    if nameHit then maybeIgnore(author) end  -- only ignore confirmed spammer names
    mod._blocked = mod._blocked + 1
    if mod.db.hide then return true end
    return false
end

-- =========================================================
-- Lifecycle
-- =========================================================
local FILTER_EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",  -- /emote spam
}
local installed = false

function mod:OnEnable()
    buildKeywords()
    buildWhitelist()
    if installed then return end
    installed = true
    if ChatFrame_AddMessageEventFilter then
        for _, ev in ipairs(FILTER_EVENTS) do
            ChatFrame_AddMessageEventFilter(ev, chatFilter)
        end
    end
end

function mod:OnDisable()
    -- The filters stay registered but no-op via the mod._enabled gate in
    -- chatFilter, so disabling takes effect immediately without a /reload.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "header", text = L["Spam Filter"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaHides chat from gold/casino spammers whose names use look-alike letters (e.g. Gãsïnô, Casinòbâbe). The name is folded to plain letters, then matched against the keywords below. Applies to whisper, channels, say, yell and emotes — not guild/party/raid.|r"] })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, {
        type = "toggle", label = L["Hide their chat messages"],
        get = function() return mod.db.hide end,
        set = function(_, v) mod.db.hide = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Also add them to your ignore list"],
        tooltip = L["Adds matched senders to /ignore too. The ignore list holds only ~50 names and spammers keep changing names, so hiding is usually enough — leave this off unless you want it."],
        get = function() return mod.db.autoIgnore end,
        set = function(_, v) mod.db.autoIgnore = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Also match the message text"],
        tooltip = L["Also checks the message body for the keywords, not just the sender's name. Catches more spam but can have false positives."],
        get = function() return mod.db.scanMessage end,
        set = function(_, v) mod.db.scanMessage = v end,
    })
    table.insert(items, {
        type = "toggle", label = L["Block messages with web links"],
        tooltip = L["Hides any message containing a web link (http://, www., domain.tld) in the filtered channels. Whitelisted names are exempt. Opt-in — can catch the occasional legit link."],
        get = function() return mod.db.blockLinks end,
        set = function(_, v) mod.db.blockLinks = v end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Keywords"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaBuilt-in: casino / asino / gasino / kasino. Add your own below, comma-separated (look-alike letters are handled automatically).|r"] })
    table.insert(items, {
        type = "editbox", label = L["Extra keywords"],
        get = function() return mod.db.extraKeywords or "" end,
        set = function(_, v) mod.db.extraKeywords = v or ""; buildKeywords() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Whitelist"] })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaNames here are never filtered. Comma-separated, or use |r|cff9b6cff/vcui spam <name>|r|cffaaaaaa to toggle one.|r"] })
    table.insert(items, {
        type = "editbox", label = L["Never filter these names"],
        get = function() return mod.db.whitelist or "" end,
        set = function(_, v) mod.db.whitelist = v or ""; buildWhitelist() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "desc",
        text = string.format(L["|cff9b6cffBlocked this session: %d|r"], mod._blocked or 0) })

    return items
end
