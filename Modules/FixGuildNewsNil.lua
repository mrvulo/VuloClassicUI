-- =========================================================
-- VuloClassicUI / Modules / FixGuildNewsNil
-- Fixes a bug in Blizzard_Communities where broken guild news entries
-- throw ("formatString") errors that make the guild news panel unusable.
-- Wraps GuildNewsButton_SetNews with xpcall and shows a fallback text
-- for broken entries.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixguildnews", {
    name        = "Guild News Nil Fix",
    group       = "Bugfixes",
    description = "Catches Lua errors in guild news entries (typically \"formatString\" or \"GuildUtil\") and replaces broken entries with a fallback text instead of letting the whole panel break.",
    defaults = {
        enabled    = true,
        showReport = true,  -- shows once in chat when the fix has been triggered
    },
})

local unpack = unpack or table.unpack

-- =========================================================
-- Helpers
-- =========================================================
local function safeSetText(obj, text)
    if obj and obj.SetText then obj:SetText(text or "") end
end

local function safeHide(obj)
    if obj and obj.Hide then obj:Hide() end
end

local function safeShow(obj)
    if obj and obj.Show then obj:Show() end
end

local function applyFallbackToButton(button)
    if not button then return end

    safeSetText(button.Name, "|cffff8080Invalid guild news entry|r")
    safeSetText(button.Header, "")
    safeSetText(button.Time, "")
    safeSetText(button.Description, "")

    if button.Icon and button.Icon.SetTexture then button.Icon:SetTexture(nil) end
    if button.icon and button.icon.SetTexture then button.icon:SetTexture(nil) end

    safeHide(button.Highlight)
    safeHide(button.NewMarker)
    safeHide(button.newsTypeIcon)

    safeShow(button)
    if button.Enable then button:Enable() end
end

-- =========================================================
-- Installation
-- =========================================================
local wrappedAlready = false

local function installPatch()
    if wrappedAlready then return end
    if type(_G.GuildNewsButton_SetNews) ~= "function" then return end

    local Original = _G.GuildNewsButton_SetNews

    _G.GuildNewsButton_SetNews = function(button, newsInfo, ...)
        if not mod._enabled then
            return Original(button, newsInfo, ...)
        end

        local args = { ... }
        local ok, err = xpcall(function()
            return Original(button, newsInfo, unpack(args))
        end, function(e) return e end)

        if ok then return end

        local errText = tostring(err or "")
        if errText:find("formatString") or errText:find("GuildUtil") then
            applyFallbackToButton(button)
            if mod.db.showReport and not _G.VCUI_GuildNewsNilFix_Reported then
                _G.VCUI_GuildNewsNilFix_Reported = true
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffffff00[VuloClassicUI]|r Blizzard guild news error caught (fallback applied).")
            end
            return
        end

        -- Pass other errors through
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
            if addonName == "Blizzard_Communities" then
                installPatch()
            end
        end)
    end

    -- Try directly (in case Blizzard_Communities is already loaded)
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
        { type = "header", text = "Behavior" },
        {
            type = "toggle", label = "Chat message on first error",
            tooltip = "Shows a brief message once per session in chat when a guild news error was caught.",
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = "This fix wraps Blizzard's |cffffffffGuildNewsButton_SetNews|r function in a protected call (xpcall). When an entry throws a known error (\"formatString\" or \"GuildUtil\"), the entry is replaced with a fallback text \"Invalid guild news entry\" — the panel remains usable." },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaStatus: %s|r",
            wrappedAlready and "|cff66ff66Hook active|r" or "waiting for Blizzard_Communities") },
    }
end
