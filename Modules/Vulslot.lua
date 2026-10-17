-- Vulslot: named snapshots of action bars, macros and keybindings. Spells match by ID with name fallback, macros by name, so snapshots survive relogs and macro reshuffles.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("vulslot", {
    name        = "Bar Setups",
    -- "Account" is a sidebar-hidden group: this page is reached through the
    -- Bars tab of Global Settings, the same way the profile manager is reached
    -- through the Profile tab. It was under "Bags & Items" as "Vulslot", where
    -- neither the group nor the name said what it does.
    group       = "Account",
    noToggle    = true,   -- nothing to switch off: OnEnable/OnDisable are empty
    description = "Saves named snapshots of your action bars, macros and keybindings, and restores them with one click.",
    defaults    = {
        enabled         = true,
        restoreMacros   = true,
        restoreBindings = true,
        -- The snapshots themselves are NOT here -- see library() below.
    },
})

-- Appear as a TAB of Global Settings instead of a sidebar row. The framework
-- reads this field in four places: the sidebar skips the row, the dashboard
-- skips the toggle, clicking through to this module opens the container and
-- selects the tab, and -- the one that matters most here -- BuildOptionsPage
-- redirects "vulslot" to ("globalsettings", "vulslot"). That last one is why
-- rebuildPage() below still refreshes the right page after a save or a delete
-- without knowing it moved. The tab id in GlobalSettings must therefore stay
-- equal to this module's key.
mod.parentTab = "globalsettings"

-- name -> snapshot, account-wide.
--
-- These used to live in mod.db, which meant once per account profile. A new
-- class profile is copied from Default, so the whole library was duplicated the
-- first time each class logged in: seven byte-identical copies of 17 KB, 37 % of
-- the saved file. They were never per-class data -- a snapshot records the class
-- it was taken on and loadProfile only warns when it does not match, which is
-- exactly the behaviour of something meant to be shared.
--
-- The two restore switches above stay per profile: those really are preferences.
local function library()
    local g = ns.db and ns.db.global
    if not g then return {} end          -- before InitDB: no store, no crash
    g.vulslotProfiles = g.vulslotProfiles or {}
    return g.vulslotProfiles
end

local MAX_SLOTS = 120

local function accountMacroCap()
    return _G.MAX_ACCOUNT_MACROS or 36
end
local function characterMacroCap()
    return _G.MAX_CHARACTER_MACROS or 18
end

local function snapshotActions()
    local out = {}
    for slot = 1, MAX_SLOTS do
        local t, id = GetActionInfo(slot)
        if t == "spell" and id then
            out[slot] = { type = "spell", id = id, name = GetSpellInfo(id) }
        elseif t == "macro" and id then
            local name = GetMacroInfo(id)
            if name then out[slot] = { type = "macro", name = name } end
        elseif t == "item" and id then
            out[slot] = { type = "item", id = id, name = GetItemInfo(id) }
        end
    end
    return out
end

local function snapshotMacros()
    local out = {}
    local cap = accountMacroCap() + characterMacroCap()
    for i = 1, cap do
        local name, icon, body = GetMacroInfo(i)
        if name then
            out[#out + 1] = {
                name    = name,
                icon    = icon,
                body    = body,
                perchar = i > accountMacroCap(),
            }
        end
    end
    return out
end

local function snapshotBindings()
    local out = {}
    for i = 1, (GetNumBindings and GetNumBindings() or 0) do
        local command = GetBinding(i)
        if command and type(command) == "string" then
            local k1, k2 = GetBindingKey(command)
            if k1 or k2 then
                out[#out + 1] = { command = command, k1 = k1, k2 = k2 }
            end
        end
    end
    return out
end

-- The counterpart to the three snapshots above, for data that did NOT come from
-- this client. An imported setup was written by a stranger, and every step of
-- the restore INDEXES its entries -- saved.type, m.name, b.command. A number
-- where a table belongs throws in the middle of the run, with part of the bars
-- already changed and no way back.
--
-- Bad entries are DROPPED, not the whole setup: one broken row is no reason to
-- refuse the other hundred, and the load report shows the gap as skipped slots.
local VALID_ACTION = { spell = true, item = true, macro = true }

-- The longest macro body and name the client stores; longer ones from a string
-- are cut here rather than half-created by CreateMacro. The name matters twice:
-- CreateMacro would shorten it on its own, and GetMacroIndexByName(full name)
-- would then never find it -- so every load of an approved import created one
-- more copy.
local MACRO_BODY_MAX = 255
local MACRO_NAME_MAX = 16

-- Cuts to at most n BYTES without splitting a multi-byte character: when the
-- byte right after the cut continues a sequence (10xxxxxx), the cut moves back
-- to the start of that character.
local function cutBytes(s, n)
    if #s <= n then return s end
    while n > 0 do
        local b = s:byte(n + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        n = n - 1
    end
    return s:sub(1, n)
end

-- Which binding commands a FOREIGN setup may set. Built-in commands are plain
-- tokens (ACTIONBUTTON1, MULTIACTIONBAR1BUTTON3, MOVEFORWARD, our own
-- VULO_ACTIONRING1). The four with an argument -- MACRO <name>, SPELL <name>,
-- ITEM <name>, CLICK <frame> -- point a key at something the string itself
-- named, a stranger's macro or any clickable frame, so an import never brings
-- them. A setup saved on this client keeps all of its bindings.
local function bindingAllowed(command, foreign)
    if not foreign then return true end
    return type(command) == "string" and #command <= 64
        and command:find("^[%u%d_]+$") ~= nil
end

-- Text that came from a string and ends up in chat, a dropdown or a dialog:
-- no UI escapes, no control characters, capped.
local function cleanText(s, maxLen)
    s = (type(s) == "string" and s or ""):gsub("|", ""):gsub("%c", "")
    return cutBytes(s, maxLen)
end

-- foreign: the setup came out of a string, not out of this client.
local function sanitizeSetup(d, foreign)
    if type(d) ~= "table" then return nil end
    local out = { actions = {}, macros = {}, bindings = {} }

    -- a class token is upper-case letters (WARRIOR, DEATHKNIGHT); anything else
    -- would be drawn as markup beside the name
    if type(d.class) == "string" and d.class:match("^%u+$") and #d.class <= 16 then
        out.class = d.class
    end

    if type(d.actions) == "table" then
        for slot, e in pairs(d.actions) do
            if type(slot) == "number" and slot == math.floor(slot)
                and slot >= 1 and slot <= MAX_SLOTS
                and type(e) == "table" and VALID_ACTION[e.type] then
                out.actions[slot] = {
                    type = e.type,
                    id   = type(e.id) == "number" and e.id or nil,
                    name = type(e.name) == "string" and e.name or nil,
                }
            end
        end
    end

    if type(d.macros) == "table" then
        for _, m in ipairs(d.macros) do
            if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
                -- The icon is a file id on some clients and a path on others,
                -- so both shapes are legal here; anything else is dropped and
                -- restoreMacros falls back to its question mark.
                local icon = (type(m.icon) == "string" or type(m.icon) == "number") and m.icon or nil
                local body = type(m.body) == "string" and m.body or ""
                local name = m.name
                if foreign then
                    body = cutBytes(body, MACRO_BODY_MAX)
                    name = cutBytes(name, MACRO_NAME_MAX)
                end
                out.macros[#out.macros + 1] = {
                    name    = name,
                    icon    = icon,
                    body    = body,
                    perchar = m.perchar and true or false,
                }
            end
        end
    end

    if type(d.bindings) == "table" then
        for _, b in ipairs(d.bindings) do
            if type(b) == "table" and type(b.command) == "string" and b.command ~= "" then
                local k1 = type(b.k1) == "string" and b.k1 or nil
                local k2 = type(b.k2) == "string" and b.k2 or nil
                -- A command whose keys did not survive the check is DROPPED, not
                -- kept keyless. restoreBindings frees every listed command's
                -- CURRENT keys in its first pass and binds back only what the
                -- entry carries -- so a keyless entry out of a hand-made or
                -- damaged string would strip the player's own key for that
                -- command and then save it that way, permanently. Nothing
                -- legitimate is lost by dropping it: snapshotBindings only ever
                -- stores entries that have a key, so this shape cannot come out
                -- of a setup saved here.
                if (k1 or k2) and bindingAllowed(b.command, foreign) then
                    out.bindings[#out.bindings + 1] = {
                        command = b.command,
                        k1 = k1,
                        k2 = k2,
                    }
                end
            end
        end
    end

    return out
end

local function saveProfile(name)
    local _, class = UnitClass("player")
    local actions  = snapshotActions()
    local macros   = snapshotMacros()
    local bindings = snapshotBindings()
    library()[name] = {
        class    = class,
        actions  = actions,
        macros   = macros,
        bindings = bindings,
    }

    -- Say what went IN, not just that something did. snapshotBindings walks
    -- `1, (GetNumBindings and GetNumBindings() or 0)`: where that global is
    -- missing the loop runs zero times, the setup is stored with an empty key
    -- list, and nobody finds out until a restore quietly brings no keys back --
    -- which is exactly how it was reported (02.08.2026).
    --
    -- Counting the slots here rather than trusting a length: actions is keyed by
    -- slot number and full of holes, so # would answer nonsense.
    local slots = 0
    for _ in pairs(actions) do slots = slots + 1 end
    ns:Print(L["Bar setup '%s' saved: %d slots, %d macros, %d key bindings."],
        name, slots, #macros, #bindings)
    if #bindings == 0 then
        ns:Print(L["|cffff8800No key bindings were captured.|r This client may not report them."])
    end
end

local function restoreMacros(list, keepExisting)
    local edited, created, failed, kept = 0, 0, 0, 0
    ClearCursor()
    for _, m in ipairs(list or {}) do
        local idx = GetMacroIndexByName(m.name) or 0
        if idx > 0 then
            -- An IMPORTED setup never rewrites a macro that is already there.
            -- Macros are matched by NAME, and names like Pull or Burst belong to
            -- everyone -- a stranger's setup would otherwise replace the BODY of
            -- yours, with the switch on by default and not a word about it. Your
            -- own setups keep overwriting: there the match is exactly the point.
            if keepExisting then
                kept = kept + 1
            else
                local ok = pcall(EditMacro, idx, m.name, m.icon, m.body)
                if ok then edited = edited + 1 else failed = failed + 1 end
            end
        else
            local ok, newId = pcall(CreateMacro, m.name,
                m.icon or "INV_MISC_QUESTIONMARK", m.body, m.perchar)
            if ok and newId then created = created + 1 else failed = failed + 1 end
        end
    end
    return edited + created, failed, kept
end

local function restoreSlot(slot, saved, counts)
    local curType, curId = GetActionInfo(slot)

    if not saved then
        if curType then
            PickupAction(slot)
            ClearCursor()
            counts.cleared = counts.cleared + 1
        end
        return
    end

    -- Skip when the slot already matches (no flicker, no churn)
    if saved.type == "spell" and curType == "spell" and curId == saved.id then return end
    if saved.type == "item"  and curType == "item"  and curId == saved.id then return end
    if saved.type == "macro" and curType == "macro" and curId then
        local curName = GetMacroInfo(curId)
        if curName == saved.name then return end
    end

    ClearCursor()
    if saved.type == "spell" then
        pcall(PickupSpell, saved.id)
        if not GetCursorInfo() and saved.name then
            pcall(PickupSpell, saved.name)  -- rank/ID changed -> try by name
        end
    elseif saved.type == "macro" then
        local idx = saved.name and (GetMacroIndexByName(saved.name) or 0) or 0
        if idx > 0 then PickupMacro(idx) end
    elseif saved.type == "item" then
        pcall(PickupItem, saved.id)
    end

    if GetCursorInfo() then
        PlaceAction(slot)   -- previous content lands on the cursor
        ClearCursor()
        counts.placed = counts.placed + 1
    else
        -- spell unknown / item not owned / macro missing: keep what's there
        counts.skipped = counts.skipped + 1
    end
end

local function restoreBindings(list)
    list = list or {}
    -- Pass 1 (free): clear each managed command's CURRENT keys *and* every key the
    -- snapshot wants — whoever currently holds it. This makes the restore exact
    -- and order-independent: nothing foreign keeps a snapshot key, and no managed
    -- command keeps a stale extra key. (Keys outside the snapshot are left alone.)
    for _, b in ipairs(list) do
        local c1, c2 = GetBindingKey(b.command)
        if c1 then SetBinding(c1) end
        if c2 then SetBinding(c2) end
        if b.k1 then SetBinding(b.k1) end
        if b.k2 then SetBinding(b.k2) end
    end
    -- Pass 2 (bind): apply the snapshot's key -> command map onto the now-free keys
    local n = 0
    for _, b in ipairs(list) do
        if b.k1 then SetBinding(b.k1, b.command) end
        if b.k2 then SetBinding(b.k2, b.command) end
        n = n + 1
    end
    if SaveBindings then
        SaveBindings((GetCurrentBindingSet and GetCurrentBindingSet()) or 2)
    end
    return n
end

-- Imports from before the review existed are in the library unfiltered; the
-- rule is applied again on the way out, not only on the way in.
local function importedBindings(p)
    local out = {}
    for _, b in ipairs(p.bindings or {}) do
        if bindingAllowed(b.command, true) then out[#out + 1] = b end
    end
    return out
end

local function doLoadProfile(name)
    local p = library()[name]
    if not p then return end
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not in combat — bars can't be changed while fighting."])
        return
    end

    local _, class = UnitClass("player")
    local saved = type(p.class) == "string" and p.class:match("^%u+$")
    if saved and saved ~= class then
        ns:Print(L["Note: profile '%s' was saved on another class (%s)."], name, saved)
    end

    -- Order matters: macros first so slots can resolve them by name
    --
    -- Both restore steps used to run in silence: restoreMacros COUNTS what it
    -- edited, created and failed, and every one of those numbers was thrown
    -- away. A setup whose macros all failed looked exactly like one that had
    -- none -- which is precisely how it was reported (02.08.2026, macros and
    -- keys missing after an import, with nothing on screen to say why).
    --
    -- A switch that is off is said out loud too. "Nothing happened" is not an
    -- answer anyone can act on; "you asked me not to" is.
    --
    -- An imported setup brings its macros and keys only when the player ticked
    -- them in the review (reviewImport); that answer is kept on the setup.
    if p.macros and #p.macros > 0 then
        if not mod.db.restoreMacros then
            ns:Print(L["Macros left alone: the switch above is off."])
        elseif p.imported and not p.applyMacros then
            -- only worth a line when something would have been CREATED; a
            -- macro of yours under the same name is kept either way
            local missing = 0
            for _, m in ipairs(p.macros) do
                if (GetMacroIndexByName(m.name) or 0) == 0 then missing = missing + 1 end
            end
            if missing > 0 then
                ns:Print(L["Macros left alone: not ticked when this import was reviewed."])
            end
        else
            -- An import creates only the macros the review showed: one that
            -- was yours at review time and deleted since was never shown.
            local list = p.macros
            if p.imported then
                list = {}
                local ok = type(p.approvedMacros) == "table" and p.approvedMacros or {}
                for _, m in ipairs(p.macros) do
                    if ok[m.name] or (GetMacroIndexByName(m.name) or 0) > 0 then
                        list[#list + 1] = m
                    end
                end
            end
            local done, failed, kept = restoreMacros(list, p.imported)
            if (failed or 0) > 0 then
                ns:Print(L["Macros: %d restored, |cffff8800%d failed|r -- the macro list may be full."],
                    done or 0, failed)
            elseif (kept or 0) > 0 then
                -- One line, not two: the kept ones are the whole story here.
                ns:Print(L["Macros: %d restored, %d of your own kept (an import does not rewrite them)."],
                    done or 0, kept)
            else
                ns:Print(L["Macros: %d restored."], done or 0)
            end
        end
    end

    local counts = { placed = 0, cleared = 0, skipped = 0 }
    for slot = 1, MAX_SLOTS do
        restoreSlot(slot, p.actions and p.actions[slot], counts)
    end

    if p.bindings and #p.bindings > 0 then
        if not mod.db.restoreBindings then
            ns:Print(L["Key bindings left alone: the switch above is off."])
        elseif p.imported and not p.applyBindings then
            ns:Print(L["Key bindings left alone: not ticked when this import was reviewed."])
        else
            ns:Print(L["Key bindings: %d applied."], restoreBindings(p.imported
                and importedBindings(p) or p.bindings) or 0)
        end
    end

    if counts.skipped > 0 then
        ns:Print(L["Bar setup '%s' loaded: %d slots set, %d cleared, |cffff8800%d skipped|r (unknown spell / missing item or macro)."],
            name, counts.placed, counts.cleared, counts.skipped)
    else
        ns:Print(L["Bar setup '%s' loaded: %d slots set, %d cleared."],
            name, counts.placed, counts.cleared)
    end
end

-- Loading is a write with no way back: 120 slots are set, and every slot the
-- setup does not carry is CLEARED. One click in a dropdown was enough for that,
-- and the only warning there ever was -- a setup saved on another class -- was a
-- chat line that arrived after the damage.
--
-- The NAME is remembered, not the table: the list can be imported into or
-- deleted from while the dialog stands, and a name that is gone by then simply
-- does nothing. Armed only once the dialog IS up -- a second question reuses the
-- same dialog, and the reuse wipes a record armed before the call.
local pendingLoad

ns.OnLocaleReady(function()
    StaticPopupDialogs["VCUI_VULSLOT_LOAD"] = {
        text           = L["Load '%s'? Every button on your bars is overwritten or cleared."],
        button1        = YES or "Yes",
        button2        = NO or "No",
        timeout        = 0,
        whileDead      = true,
        hideOnEscape   = true,
        preferredIndex = 3,
        OnAccept = function()
            local n = pendingLoad
            pendingLoad = nil
            if n then doLoadProfile(n) end
        end,
        OnCancel = function() pendingLoad = nil end,
        OnHide   = function() pendingLoad = nil end,
    }
end)

-- The first load of an IMPORTED setup is a review, not the plain question:
-- the string was written by someone else, and what it will do -- create
-- macros that run on a button press, put keys on commands -- has to be on
-- screen before it happens, not counted in chat afterwards. Both parts start
-- unticked; the answer is stored on the setup, so the review comes once.
local SCRIPT_SLASH = { "/run", "/script", "/console", "/click", "/dump" }
local function scriptCommands()
    local set = {}
    for _, c in ipairs(SCRIPT_SLASH) do set[c] = true end
    -- the localized spellings the client registers for the same commands
    for _, base in ipairs({ "SLASH_SCRIPT", "SLASH_CONSOLE", "SLASH_CLICK", "SLASH_DUMP" }) do
        for i = 1, 8 do
            local v = _G[base .. i]
            if type(v) == "string" then set[v:lower()] = true end
        end
    end
    return set
end

local function hasScript(body, set)
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local cmd = line:match("^%s*(/%S+)")
        if cmd and set[cmd:lower()] then return true end
    end
    return false
end

-- | doubled: a body or a name is shown as written, never as markup
local function shown(s)
    return (tostring(s or ""):gsub("|", "||"))
end

local function reviewImport(name, p)
    local newMacros, kept = {}, {}
    for _, m in ipairs(p.macros or {}) do
        if (GetMacroIndexByName(m.name) or 0) == 0 then
            newMacros[#newMacros + 1] = m
        else
            kept[#kept + 1] = shown(m.name)
        end
    end
    local binds = importedBindings(p)
    if #newMacros == 0 and #binds == 0 then return false end

    local scripts = scriptCommands()
    local lines = {
        L["Load '%s'? Every button on your bars is overwritten or cleared."]:format(shown(name)),
        "",
        L["This setup was imported from a string. Check what it brings before you allow it:"],
    }
    if #newMacros > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffffd100" .. L["New macros (%d):"]:format(#newMacros) .. "|r"
        for _, m in ipairs(newMacros) do
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cffffd100" .. shown(m.name) .. "|r"
            if hasScript(m.body or "", scripts) then
                lines[#lines + 1] = "|cffff5555" .. L["Runs script commands: this macro can do anything you can type."] .. "|r"
            end
            lines[#lines + 1] = shown(m.body)
        end
    end
    if #kept > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L["Your own macros with these names stay as they are: %s"]:format(table.concat(kept, ", "))
    end
    if #binds > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cffffd100" .. L["Key bindings (%d), each key is first taken off what it does now:"]:format(#binds) .. "|r"
        for _, b in ipairs(binds) do
            local keys = shown(b.k1 or "") .. ((b.k1 and b.k2) and ", " or "") .. shown(b.k2 or "")
            lines[#lines + 1] = keys .. "  ->  " .. shown(b.command)
        end
    end

    local choice = { macros = false, bindings = false }
    local toggles = {}
    if #newMacros > 0 then
        toggles[#toggles + 1] = { label = L["Create these macros"],
            get = function() return choice.macros end,
            set = function(_, v) choice.macros = v and true or false end }
    end
    if #binds > 0 then
        toggles[#toggles + 1] = { label = L["Set these key bindings"],
            get = function() return choice.bindings end,
            set = function(_, v) choice.bindings = v and true or false end }
    end
    ns.UI:ShowReviewDialog({
        title   = L["Bar Setups"],
        text    = table.concat(lines, "\n"),
        accept  = L["Load profile"],
        toggles = toggles,
        onAccept = function()
            -- the same table, not just the same name: the list may have been
            -- re-imported or deleted while the window stood
            if library()[name] ~= p then return end
            p.reviewed      = true
            p.applyMacros   = choice.macros or nil
            if choice.macros then
                p.approvedMacros = {}
                for _, m in ipairs(newMacros) do p.approvedMacros[m.name] = true end
            end
            p.applyBindings = choice.bindings or nil
            doLoadProfile(name)
        end,
    })
    return true
end

local function loadProfile(name)
    local p = library()[name]
    if not p then return end
    -- Refused before the question, not after it: a fight is no state to ask in.
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not in combat — bars can't be changed while fighting."])
        return
    end
    if p.imported and not p.reviewed and ns.UI and ns.UI.ShowReviewDialog
        and reviewImport(name, p) then
        return
    end
    if not (StaticPopupDialogs and StaticPopupDialogs["VCUI_VULSLOT_LOAD"]
        and StaticPopup_Show) then
        doLoadProfile(name)
        return
    end
    local dialog = StaticPopup_Show("VCUI_VULSLOT_LOAD", name)
    if not dialog then return end
    pendingLoad = name
end

-- Pure on-demand module: nothing to wire up in lifecycle
function mod:OnEnable() end
function mod:OnDisable() end

local newName  = ""
local selected = nil

local function sortedProfileNames()
    local names = {}
    for n in pairs(library()) do names[#names + 1] = n end
    table.sort(names)
    return names
end

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("vulslot")
    end
end

function mod:GetOptions()
    local names = sortedProfileNames()
    if selected and not library()[selected] then selected = nil end
    if not selected and names[1] then selected = names[1] end

    local values = {}
    for _, n in ipairs(names) do
        local p = library()[n]
        -- a class from an import made before the check is shown only if it
        -- is a class token, never as whatever text it carried
        local cls = p and type(p.class) == "string" and p.class:match("^%u+$")
        local suffix = cls and (" |cff888888(" .. cls .. ")|r") or ""
        values[#values + 1] = { value = n, text = shown(n) .. suffix }
    end

    local function doSave()
        local n = newName:gsub("^%s+", ""):gsub("%s+$", "")
        if n == "" then
            ns:Print(L["Please enter a profile name first."])
            return
        end
        saveProfile(n)
        newName  = ""
        selected = n
        rebuildPage()
    end

    local items = {
        { type = "header", text = L["Bar Setups"] },
        { type = "desc",
          text = L["|cffaaaaaaSaves your complete bar setup (all action slots, macros, keybindings) as a named profile and restores it with one click — e.g. PvP and Raid layouts, or to copy a setup to a twink (account-wide storage).|r"] },
        { type = "spacer", height = 6 },

        { type = "header", text = L["Save"] },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "editbox", label = L["Name"], width = 260, editWidth = 180,
              commitOnFocusLost = true,
              get = function() return newName end,
              set = function(_, v) newName = tostring(v or "") end,
              onEnter = function() doSave() end },
            { type = "button", label = L["Save current setup"], width = 180, primary = true,
              onClick = function() doSave() end },
        } },
        { type = "spacer", height = 8 },

        { type = "header", text = L["Load"] },
    }

    if #values == 0 then
        items[#items + 1] = { type = "desc",
            text = L["|cff888888No profiles saved yet.|r"] }
    else
        items[#items + 1] = { type = "dropdown", label = L["Profile"], width = 260,
            values = values,
            get = function() return selected end,
            set = function(_, v) selected = v end }
        items[#items + 1] = { type = "toggle", label = L["Also restore macros"],
            tooltip = L["Rewrites saved macros by name (existing ones are updated, missing ones created)."],
            get = function() return mod.db.restoreMacros end,
            set = function(_, v) mod.db.restoreMacros = v end }
        items[#items + 1] = { type = "toggle", label = L["Also restore keybindings"],
            get = function() return mod.db.restoreBindings end,
            set = function(_, v) mod.db.restoreBindings = v end }
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Load profile"], width = 150, primary = true,
              onClick = function()
                  if selected then loadProfile(selected) end
              end },
            { type = "button", label = L["Overwrite with current setup"], width = 220,
              tooltip = L["Replaces the selected profile with your current bars/macros/bindings."],
              onClick = function()
                  if selected then saveProfile(selected) end
              end },
            { type = "button", label = L["Delete"], width = 110,
              onClick = function()
                  if selected then
                      library()[selected] = nil
                      ns:Print(L["Bar setup '%s' deleted."], selected)
                      selected = nil
                      rebuildPage()
                  end
              end },
        } }
        items[#items + 1] = { type = "spacer", height = 4 }
        items[#items + 1] = {
            type = "button", label = L["Export as string"], width = 180,
            tooltip = L["Packs the selected bar setup into a string you can pass on. Slots, macros and key bindings travel with it."],
            onClick = function()
                if not selected then return end
                local setup = library()[selected]
                if not setup then return end
                -- Its own prefix pair, not the profile's: the two strings must
                -- never be mistakable for one another. The reader is owed a
                -- clear "that is not a bar setup" rather than a half-import.
                local str = ns:EncodeShareString("!VBAR1", "!VBAR2",
                    { v = 1, n = selected, d = setup })
                if str and ns.UI and ns.UI.ShowProfileExportDialog then
                    ns.UI:ShowProfileExportDialog(str)
                end
            end }
    end

    -- Import stands OUTSIDE the "is there anything saved" branch: an empty
    -- library is exactly when someone wants to read a setup in.
    items[#items + 1] = {
        type = "button", label = L["Import from string"], width = 180,
        tooltip = L["Reads a bar setup string into your library. Putting it onto your bars stays a separate step."],
        onClick = function()
            if not (ns.UI and ns.UI.ShowStringImportDialog) then return end
            ns.UI:ShowStringImportDialog(L["Import from string"], function(text)
                local payload, why = ns:DecodeShareString("!VBAR1", "!VBAR2", text)
                if not payload then
                    -- The framework says WHY in one word; the sentence is ours,
                    -- because only we know a bar setup was expected.
                    if why == "toolarge" then return L["The string is too large to import."] end
                    return (why == "damaged") and L["The bar setup string is damaged."]
                        or L["This is not a bar setup string."]
                end
                -- Nothing from the string is stored as it arrived: sanitizeSetup
                -- rebuilds it entry by entry, so the restore can only ever walk
                -- shapes it knows.
                local d = sanitizeSetup(payload.d, true)
                if not d or (not next(d.actions)
                    and #d.macros == 0 and #d.bindings == 0) then
                    return L["The bar setup string is damaged."]
                end
                -- Marked as foreign, and it stays marked: restoreMacros reads
                -- this to leave macros of your own alone, loadProfile to show
                -- the review before the first load. Saving over the setup
                -- later builds a fresh table without the flag, which is right --
                -- from then on it is yours.
                d.imported = true
                -- the name is shown in chat, the dropdown and the review:
                -- whatever markup it carried is gone before it is stored
                local name = cleanText(payload.n, 48):match("^%s*(.-)%s*$")
                if name == "" then name = L["Imported"] end
                -- Never overwrite silently. Someone else's setup arriving under
                -- a name you already use must not eat yours.
                local base, n = name, 2
                while library()[name] do
                    name = base .. " " .. n
                    n = n + 1
                end
                library()[name] = d
                selected = name
                ns:Print(L["Bar setup '%s' imported."], name)
                rebuildPage()
            end)
        end }

    return items
end
