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

local function sanitizeSetup(d)
    if type(d) ~= "table" then return nil end
    local out = { actions = {}, macros = {}, bindings = {} }

    if type(d.class) == "string" then out.class = d.class end

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
                out.macros[#out.macros + 1] = {
                    name    = m.name,
                    icon    = icon,
                    body    = type(m.body) == "string" and m.body or "",
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
                if k1 or k2 then
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

local function restoreMacros(list)
    local edited, created, failed = 0, 0, 0
    ClearCursor()
    for _, m in ipairs(list or {}) do
        local idx = GetMacroIndexByName(m.name) or 0
        if idx > 0 then
            local ok = pcall(EditMacro, idx, m.name, m.icon, m.body)
            if ok then edited = edited + 1 else failed = failed + 1 end
        else
            local ok, newId = pcall(CreateMacro, m.name,
                m.icon or "INV_MISC_QUESTIONMARK", m.body, m.perchar)
            if ok and newId then created = created + 1 else failed = failed + 1 end
        end
    end
    return edited + created, failed
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

local function loadProfile(name)
    local p = library()[name]
    if not p then return end
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not in combat — bars can't be changed while fighting."])
        return
    end

    local _, class = UnitClass("player")
    if p.class and p.class ~= class then
        ns:Print(L["Note: profile '%s' was saved on another class (%s)."], name, p.class)
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
    if p.macros and #p.macros > 0 then
        if not mod.db.restoreMacros then
            ns:Print(L["Macros left alone: the switch above is off."])
        else
            local done, failed = restoreMacros(p.macros)
            if (failed or 0) > 0 then
                ns:Print(L["Macros: %d restored, |cffff8800%d failed|r -- the macro list may be full."],
                    done or 0, failed)
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
        else
            ns:Print(L["Key bindings: %d applied."], restoreBindings(p.bindings) or 0)
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
        local suffix = (p and p.class) and (" |cff888888(" .. p.class .. ")|r") or ""
        values[#values + 1] = { value = n, text = n .. suffix }
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
                    return (why == "damaged") and L["The bar setup string is damaged."]
                        or L["This is not a bar setup string."]
                end
                -- Nothing from the string is stored as it arrived: sanitizeSetup
                -- rebuilds it entry by entry, so the restore can only ever walk
                -- shapes it knows.
                local d = sanitizeSetup(payload.d)
                if not d or (not next(d.actions)
                    and #d.macros == 0 and #d.bindings == 0) then
                    return L["The bar setup string is damaged."]
                end
                local name = (type(payload.n) == "string" and payload.n ~= "")
                    and payload.n or L["Imported"]
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
