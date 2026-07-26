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

    -- Every category and line renders through L: the English text from
    -- CHANGELOG.md is the key, translations live in the normal locale files
    -- (added per release together with the changelog itself).
    for _, v in ipairs(data) do
        items[#items + 1] = { type = "header", text = "|cffffffff" .. tostring(v.version or "?") .. "|r" }
        for _, sec in ipairs(v.sections or {}) do
            if sec.category and sec.category ~= "" then
                items[#items + 1] = { type = "desc", text = accent(L[sec.category]) }
            end
            for _, line in ipairs(sec.lines or {}) do
                local text = tostring(line)
                local rest = text:match("^NEW:%s*(.+)$")
                if rest then
                    text = "|cff66ff66" .. L["NEW:"] .. "|r " .. L[rest]
                else
                    text = L[text]
                end
                items[#items + 1] = { type = "desc", text = "|cffb0b0b0\226\128\162|r " .. text }
            end
        end
        items[#items + 1] = { type = "spacer", height = 12 }
    end
    return items
end
