-- =========================================================
-- VuloClassicUI / Modules / FixGuildNewsNil
-- Behebt einen Bug in Blizzard_Communities wo defekte Guild-News-Einträge
-- ("formatString")-Fehler werfen, die das Guild-News-Panel unbrauchbar machen.
-- Wrappt GuildNewsButton_SetNews mit xpcall und zeigt einen Fallback-Text
-- für defekte Einträge an.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("fixguildnews", {
    name        = "Guild News Nil Fix",
    group       = "Bugfixes",
    description = "Fängt Lua-Fehler in den Gilden-News-Einträgen ab (typisch \"formatString\" oder \"GuildUtil\") und ersetzt defekte Einträge durch einen Fallback-Text statt das ganze Panel kaputtgehen zu lassen.",
    defaults = {
        enabled    = true,
        showReport = true,  -- zeigt einmalig im Chat dass der Fix angesprungen ist
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
                    "|cffffff00[VuloClassicUI]|r Blizzard Guild-News-Fehler abgefangen (Fallback eingesetzt).")
            end
            return
        end

        -- Andere Fehler durchreichen
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

    -- Direkt versuchen (falls Blizzard_Communities schon geladen ist)
    installPatch()
    -- Plus ein delayed retry für Edge-Cases
    if C_Timer and C_Timer.After then
        C_Timer.After(1, installPatch)
    end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Verhalten" },
        {
            type = "toggle", label = "Chat-Nachricht beim ersten Fehler",
            tooltip = "Zeigt einmalig pro Session eine kurze Nachricht im Chat wenn ein Gilden-News-Fehler abgefangen wurde.",
            get = function() return mod.db.showReport end,
            set = function(_, v) mod.db.showReport = v end,
        },
        { type = "spacer", height = 8 },
        { type = "desc", text = "Dieser Fix wickelt Blizzards |cffffffffGuildNewsButton_SetNews|r-Funktion in einen geschützten Aufruf (xpcall) ein. Wenn ein Eintrag einen bekannten Fehler wirft (\"formatString\" oder \"GuildUtil\"), wird der Eintrag durch einen Fallback-Text \"Invalid guild news entry\" ersetzt — das Panel bleibt benutzbar." },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format("|cffaaaaaaStatus: %s|r",
            wrappedAlready and "|cff66ff66Hook aktiv|r" or "wartet auf Blizzard_Communities") },
    }
end
