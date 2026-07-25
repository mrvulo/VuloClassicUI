-- General helpers used by multiple modules.
local _, ns = ...

function ns:Print(msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. ": " .. tostring(msg))
end

function ns:Debug(msg, ...)
    if not (ns.db and ns.db.global) or not ns.db.global.debug then return end
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[VCUI debug]|r " .. tostring(msg))
end

function ns:InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- 1 physical pixel == (768 / physicalScreenHeight) coord units at scale 1.0, divided by the frame's effective scale.
function ns:Pixel(frame, n)
    local _, physH = GetPhysicalScreenSize()
    if not physH or physH <= 0 then physH = 1080 end
    local es = (frame and frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if es <= 0 then es = 1 end
    return (n or 1) * (768 / physH) / es
end

function ns:PixelSnap(value, frame)
    local px = ns:Pixel(frame, 1)
    if px <= 0 then return value end
    return math.floor(value / px + 0.5) * px
end

-- Snap a CENTER offset so the frame's leading EDGE lands on the physical pixel
-- grid. Going through the edge rather than the centre keeps odd-width frames on
-- their half pixel automatically — snapping the centre itself rounds that .5
-- away and the frame creeps a pixel on every save/reload cycle.
function ns:PixelSnapCenter(value, dim, frame)
    local px = ns:Pixel(frame, 1)
    if px <= 0 then return value end
    local half = (dim or 0) / 2
    return math.floor((value - half) / px + 0.5) * px + half
end

-- Blizzard reads UIPanelWindows from inside its own secure panel code, so
-- replacing an entry from Lua taints that whole system. The visible symptom is
-- not being able to open the character sheet or the spellbook while in combat.
-- SetUIPanelAttribute is the sanctioned route and keeps the taint off the
-- shared table. Returns false when the client has no such API, in which case
-- the caller must leave the panel alone rather than fall back to the raw write.
function ns:SetPanelLayout(frame, attrs)
    if not (frame and type(attrs) == "table") then return false end
    if type(_G.SetUIPanelAttribute) ~= "function" then return false end
    for k, v in pairs(attrs) do
        pcall(_G.SetUIPanelAttribute, frame, k, v)
    end
    return true
end

-- Class icons come out of Blizzard's character-creation atlas, so there is no
-- art to ship and no client restart to wait for. The coordinates are cut for
-- exactly that texture; any other class-icon sheet uses a different grid.
local CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_ICON_FALLBACK = {
    WARRIOR     = { 0,    0.25, 0,    0.25 },
    MAGE        = { 0.25, 0.49, 0,    0.25 },
    ROGUE       = { 0.49, 0.73, 0,    0.25 },
    DRUID       = { 0.73, 0.97, 0,    0.25 },
    HUNTER      = { 0,    0.25, 0.25, 0.5  },
    SHAMAN      = { 0.25, 0.49, 0.25, 0.5  },
    PRIEST      = { 0.49, 0.73, 0.25, 0.5  },
    WARLOCK     = { 0.73, 0.97, 0.25, 0.5  },
    PALADIN     = { 0,    0.25, 0.5,  0.75 },
    DEATHKNIGHT = { 0.25, 0.49, 0.5,  0.75 },
}

-- Returns texture, {left, right, top, bottom} — or nil for an unknown class.
function ns:GetClassIcon(classToken)
    if not classToken then return nil end
    local token = classToken:upper()
    local coords = (_G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[token])
        or CLASS_ICON_FALLBACK[token]
    if not coords then return nil end
    return CLASS_ICON_TEXTURE, coords
end

function ns:DeepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = ns:DeepCopy(v)
    end
    return copy
end

function ns:ApplyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            -- never clobber a saved scalar with a fresh table (drops the user's value)
            if target[k] == nil or type(target[k]) == "table" then
                target[k] = ns:ApplyDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

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
