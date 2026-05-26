-- =========================================================
-- VuloClassicUI / Modules / FixLFGBrowseNil
-- Fixes a bug in the Anniversary GroupFinder (Vanilla-style) where
-- LFGBrowseSearchEntry_Update is called with stale resultIDs:
--   C_LFGList.GetSearchResultInfo(resultID) returns nil because the
--   result was already removed from the server — Blizzard's update function
--   then indexes into nil and crashes (Blizzard_LFGVanilla_Browse.lua:267).
-- Wraps LFGBrowseSearchEntry_Update in xpcall — broken entries remain
-- visible with their old state until Blizzard's refresh redraws them.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixlfgbrowsenil", {
    name        = L["LFG Browse Nil Fix"],
    group       = "Bugfixes",
    description = L["Catches Lua errors in the Anniversary Group Finder (LFGBrowseSearchEntry_Update with stale resultIDs). Prevents chat spam and broken browse lists."],
    defaults = {
        enabled    = true,
        showReport = true,  -- report once per session
    },
})

local unpack = unpack or table.unpack

-- =========================================================
-- Installation
-- =========================================================
local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.LFGBrowseSearchEntry_Update) ~= "function" then return end

    local Original = _G.LFGBrowseSearchEntry_Update

    _G.LFGBrowseSearchEntry_Update = function(button, ...)
        if not mod._enabled then
            return Original(button, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        -- Known Anniversary bug: searchResultInfo becomes nil because the server
        -- result is stale. Silent return — Blizzard's next refresh cleans up.
        if errText:find("searchResultInfo") or errText:find("attempt to index") then
            if mod.db.showReport and not _G.VCUI_LFGBrowseNilFix_Reported then
                _G.VCUI_LFGBrowseNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    L["|cffffff00[VuloClassicUI]|r Blizzard LFG browse error caught (stale entry skipped)."])
            end
            return
        end

        -- Pass other errors through so BugSack & co. see them
        error(errText)
    end

    wrappedAlready = true
end

-- =========================================================
-- Lifecycle
-- =========================================================
local installFrame

function mod:OnEnable()
    if not installFrame then
        installFrame = CreateFrame("Frame")
        installFrame:RegisterEvent("ADDON_LOADED")
        installFrame:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_GroupFinder_VanillaStyle" then
                installPatch()
            end
        end)
    end

    -- Try directly (in case addon is already loaded)
    installPatch()
    -- Plus a delayed retry for edge cases
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["Behavior"] },
        {
            type = "toggle", label = L["Chat message on first error"],
            tooltip = L["Shows a brief message once per session in chat when an LFG browse error was caught."],
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = L["This fix wraps Blizzard's |cffffffffLFGBrowseSearchEntry_Update|r function in a protected call (xpcall). When the entry crashes due to a stale resultID (\"searchResultInfo nil\"), the error is swallowed — Blizzard's next refresh automatically cleans up the list entry."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            wrappedAlready and L["|cff66ff66Hook active|r"] or L["waiting for Blizzard_GroupFinder_VanillaStyle"]) },
    }
end
