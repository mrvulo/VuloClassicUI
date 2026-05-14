-- =========================================================
-- VuloClassicUI / Modules / Profiles
-- Profil-Manager als eigenes "Modul" in der Sidebar.
-- Erlaubt: Profil wechseln, erstellen, kopieren, löschen, umbenennen, pro-Klasse zuordnen.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("profiles", {
    name        = "Profiles",
    group       = "Account",
    description = "Verwalte Profile mit unterschiedlichen Settings. Pro Klasse kann ein Standard-Profil zugewiesen werden, das beim Login automatisch geladen wird.",
    noToggle    = true,  -- kein Power-Button in der Sidebar
    defaults    = {
        enabled = true,
    },
})

-- Dieses "Modul" hat keine eigene Lifecycle-Logik
function mod:OnEnable() end

-- =========================================================
-- Daten für UI
-- =========================================================
local CLASS_LIST = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local CLASS_LABELS = {
    WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke",
    PRIEST = "Priester", SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister",
    DRUID = "Druide",
}

-- Buffer für UI-Eingaben (nicht in der DB gespeichert)
local newProfileNameBuffer = ""
local copyFromBuffer       = nil
local renameNewBuffer      = ""

-- Hilfsfunktionen
local function getProfileValues()
    local values = {}
    for _, name in ipairs(ns:GetProfileNames()) do
        table.insert(values, { value = name, text = name })
    end
    return values
end

local function getProfileValuesWithNone()
    local values = { { value = "", text = "— keine —" } }
    for _, name in ipairs(ns:GetProfileNames()) do
        table.insert(values, { value = name, text = name })
    end
    return values
end

local function refreshUI()
    if ns.UI and ns.UI.currentModule == "profiles" then
        ns.UI:BuildOptionsPage("profiles", "default")
    end
end

-- =========================================================
-- Options-Page
-- =========================================================
function mod:GetOptions()
    local items = {}
    local activeName = ns:GetActiveProfileName()
    local myClass    = ns:GetMyClassKey()

    -- =========================================================
    -- Sektion: Aktives Profil
    -- =========================================================
    table.insert(items, { type = "header", text = "Aktives Profil" })

    table.insert(items, {
        type = "desc",
        text = string.format("Du benutzt gerade: |cff9b6cff%s|r  (Klasse: %s)",
            activeName, CLASS_LABELS[myClass] or myClass)
    })

    table.insert(items, {
        type = "dropdown", label = "Profil wechseln",
        width = 220,
        values = getProfileValues(),
        get = function() return ns:GetActiveProfileName() end,
        set = function(_, v)
            ns:SwitchProfile(v)
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Sektion: Profil erstellen
    -- =========================================================
    table.insert(items, { type = "header", text = "Neues Profil erstellen" })

    table.insert(items, {
        type = "editbox", label = "Name",
        width = 220,
        get = function() return newProfileNameBuffer end,
        set = function(_, v) newProfileNameBuffer = v end,
    })

    table.insert(items, {
        type = "dropdown", label = "Settings kopieren von",
        width = 220,
        values = (function()
            local v = { { value = "", text = "— leeres Profil (Defaults) —" } }
            for _, name in ipairs(ns:GetProfileNames()) do
                table.insert(v, { value = name, text = name })
            end
            return v
        end)(),
        get = function() return copyFromBuffer or "" end,
        set = function(_, v) copyFromBuffer = (v ~= "" and v) or nil end,
    })

    table.insert(items, {
        type = "button", label = "Profil erstellen", width = 160,
        onClick = function()
            local name = (newProfileNameBuffer or ""):match("^%s*(.-)%s*$")
            if not name or name == "" then
                ns:Print("|cffff5555Bitte einen Namen eingeben.|r")
                return
            end
            local ok, err = ns:CreateProfile(name, copyFromBuffer)
            if not ok then
                ns:Print("|cffff5555%s|r", err or "Fehler.")
            else
                newProfileNameBuffer = ""
                copyFromBuffer = nil
                refreshUI()
            end
        end,
    })

    table.insert(items, { type = "spacer", height = 12 })

    -- =========================================================
    -- Sektion: Aktives Profil verwalten
    -- =========================================================
    table.insert(items, { type = "header", text = "Aktuelles Profil verwalten" })

    table.insert(items, {
        type = "group", layout = "row", gap = 6,
        items = {
            {
                type = "editbox", label = "Umbenennen zu",
                width = 180,
                get = function() return renameNewBuffer end,
                set = function(_, v) renameNewBuffer = v end,
            },
            {
                type = "button", label = "Umbenennen", width = 110,
                onClick = function()
                    local newName = (renameNewBuffer or ""):match("^%s*(.-)%s*$")
                    if not newName or newName == "" then
                        ns:Print("|cffff5555Bitte neuen Namen eingeben.|r")
                        return
                    end
                    local ok, err = ns:RenameProfile(ns:GetActiveProfileName(), newName)
                    if not ok then
                        ns:Print("|cffff5555%s|r", err or "Fehler.")
                    else
                        renameNewBuffer = ""
                        refreshUI()
                    end
                end,
            },
        },
    })

    table.insert(items, {
        type = "button", label = "Aktives Profil löschen", width = 200,
        onClick = function()
            local active = ns:GetActiveProfileName()
            if active == "Default" then
                ns:Print("|cffff5555Default-Profil kann nicht gelöscht werden.|r")
                return
            end
            local ok, err = ns:DeleteProfile(active)
            if not ok then ns:Print("|cffff5555%s|r", err or "Fehler.") end
            refreshUI()
        end,
    })

    table.insert(items, {
        type = "button", label = "Auf aktive Klasse anwenden", width = 220,
        tooltip = string.format("Setzt das aktuelle Profil als Standard für %s.",
            CLASS_LABELS[myClass] or myClass),
        onClick = function()
            ns:AssignClassToProfile(myClass, ns:GetActiveProfileName())
            ns:Print("'%s' ist jetzt Standard-Profil für %s.",
                ns:GetActiveProfileName(), CLASS_LABELS[myClass] or myClass)
            refreshUI()
        end,
    })

    table.insert(items, { type = "spacer", height = 14 })

    -- =========================================================
    -- Sektion: Klassen-Zuordnungen
    -- =========================================================
    table.insert(items, { type = "header", text = "Profil-Zuordnung pro Klasse" })

    table.insert(items, {
        type = "desc",
        text = "Wähle für jede Klasse ein Standard-Profil. Beim Login mit einem Charakter dieser Klasse wird das Profil automatisch geladen.",
    })

    local values = getProfileValuesWithNone()

    for _, classKey in ipairs(CLASS_LIST) do
        table.insert(items, {
            type = "dropdown", label = CLASS_LABELS[classKey] or classKey,
            width = 200,
            values = values,
            get = function() return ns:GetClassAssignment(classKey) or "" end,
            set = function(_, v) ns:AssignClassToProfile(classKey, v) end,
        })
    end

    return items
end
