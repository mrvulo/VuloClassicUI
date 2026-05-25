-- =========================================================
-- VuloClassicUI / Core / Utils
-- General helpers used by multiple modules.
-- =========================================================
local _, ns = ...

function ns:Print(msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. ": " .. tostring(msg))
end

function ns:Debug(msg, ...)
    if not ns.db or not ns.db.global.debug then return end
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[VCUI debug]|r " .. tostring(msg))
end

function ns:InCombat()
    return InCombatLockdown and InCombatLockdown()
end

function ns:Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Safe deep copy (for defaults -> DB)
function ns:DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = ns:DeepCopy(v)
    end
    return copy
end

-- Recursively insert defaults into an existing table, without overwriting existing values
function ns:ApplyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            target[k] = ns:ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- =========================================================
-- Font helper (used by VuloFontBars and ArenaEnemyEdit)
-- =========================================================
function ns:SafeGetFontString(bar, suffix)
    if not bar or not bar.GetName then return nil end
    local n = bar:GetName()
    if not n or n == "" then return nil end
    return _G[n .. suffix]
end

function ns:ApplyFontSize(fs, size)
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local font, _, flags = fs:GetFont()
    if font then
        fs:SetFont(font, size, flags)
    end
end

function ns:SetBarTextFontSize(bar, size)
    if not bar then return end
    local center = bar.TextString or ns:SafeGetFontString(bar, "Text")
    local left   = bar.LeftText   or ns:SafeGetFontString(bar, "TextLeft")
    local right  = bar.RightText  or ns:SafeGetFontString(bar, "TextRight")
    ns:ApplyFontSize(center, size)
    ns:ApplyFontSize(left, size)
    ns:ApplyFontSize(right, size)
end
