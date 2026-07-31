-- Changelog: "Patch Notes" page showing ns.CHANGELOG (auto-generated from CHANGELOG.md by tools/gen_changelog.js).
-- Reached from its own sidebar row under "Overview" (UI/Sidebar.lua); lives in the hidden group so it doesn't also appear as a normal group row.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("changelog", {
    name        = "Patch Notes",
    group       = "_hidden",
    noToggle    = true,
    description = "",
    defaults    = { enabled = true },
})

local function accent(text)
    local a = ns.C and ns.C.accent
    if a then return a .. text .. "|r" end
    return text
end

function mod:GetOptions()
    local items = {}
    items[#items + 1] = { type = "header", text = L["Patch Notes"] }
    items[#items + 1] = { type = "desc",   text = L["|cffaaaaaaAll changes from recent versions — newest first.|r"] }
    items[#items + 1] = { type = "spacer", height = 6 }

    local data = ns.CHANGELOG or {}
    if #data == 0 then
        items[#items + 1] = { type = "desc", text = L["|cffaaaaaaNo changelog data.|r"] }
        return items
    end

    -- Only the newest five versions build widgets (user request, 31.07.2026):
    -- the full list is ~25 versions with ~300 lines, and every line is a
    -- fontstring the page has to lay out and measure on each build. The rest
    -- stays one click away instead of being paid on every visit.
    local SHOWN = 5
    local last = #data
    if not mod._showAllNotes and last > SHOWN then last = SHOWN end

    -- Every category and line renders through L: the English text from
    -- CHANGELOG.md is the key, translations live in the normal locale files
    -- (added per release together with the changelog itself).
    for vi = 1, last do
        local v = data[vi]
        items[#items + 1] = { type = "header", text = "|cffffffff" .. tostring(v.version or "?") .. "|r" }
        for _, sec in ipairs(v.sections or {}) do
            if sec.category and sec.category ~= "" then
                items[#items + 1] = { type = "desc", text = accent(L[sec.category]) }
            end
            for _, line in ipairs(sec.lines or {}) do
                local text = tostring(line)
                local rest = text:match("^NEW:%s*(.+)$")
                if rest then
                    -- A NEW line reads "Feature Name <en dash> what it does".
                    -- The name is the part a reader scans for, so it gets the
                    -- bright colour. Translations keep the dash, so this splits
                    -- the same way in every language; a line without one falls
                    -- through unchanged.
                    local shown = L[rest]
                    local name, desc = shown:match("^(.-)%s*\226\128\147%s*(.+)$")
                    if name and name ~= "" then
                        shown = "|cffffffff" .. name .. "|r \226\128\147 " .. desc
                    end
                    text = "|cff66ff66" .. L["NEW:"] .. "|r " .. shown
                else
                    text = L[text]
                end
                items[#items + 1] = { type = "desc", text = "|cffb0b0b0\226\128\162|r " .. text }
            end
        end
        items[#items + 1] = { type = "spacer", height = 12 }
    end

    -- Session state, deliberately not saved: the archive stays open while
    -- you read it, and the next session starts cheap again.
    if last < #data then
        items[#items + 1] = { type = "button", label = L["Show older versions"], width = 260,
            onClick = function()
                mod._showAllNotes = true
                if ns.UI then ns.UI:RebuildCurrentPage() end
            end }
    end
    return items
end
