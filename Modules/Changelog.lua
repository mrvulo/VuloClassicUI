-- =========================================================
-- VuloClassicUI / Modules / Changelog
-- "Patch Notes" page — shows every version's changes from ns.CHANGELOG
-- (auto-generated from CHANGELOG.md by tools/gen_changelog.js). Reached from
-- its own sidebar row directly under "Overview" (see UI/Sidebar.lua); it lives
-- in the hidden group so it doesn't also appear as a normal group row.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("changelog", {
    name        = "Patch Notes",
    group       = "_hidden",
    noToggle    = true,
    description = "",
    defaults    = { enabled = true },
})

-- Wrap text in the current accent colour (theme-aware); plain if unavailable.
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

    for _, v in ipairs(data) do
        items[#items + 1] = { type = "header", text = "|cffffffff" .. tostring(v.version or "?") .. "|r" }
        for _, sec in ipairs(v.sections or {}) do
            if sec.category and sec.category ~= "" then
                items[#items + 1] = { type = "desc", text = accent(sec.category) }
            end
            for _, line in ipairs(sec.lines or {}) do
                local text = tostring(line)
                -- highlight a leading "NEW:" marker in green
                local rest = text:match("^NEW:%s*(.+)$")
                if rest then text = "|cff66ff66NEW:|r " .. rest end
                items[#items + 1] = { type = "desc", text = "|cffb0b0b0\226\128\162|r " .. text }
            end
        end
        items[#items + 1] = { type = "spacer", height = 12 }
    end
    return items
end
