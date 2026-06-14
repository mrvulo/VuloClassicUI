-- =========================================================
-- VuloClassicUI / Modules / PowerBar
-- A movable HUD resource bar (mana / rage / energy / focus).
--
-- The power type follows the character AUTOMATICALLY: UnitPowerType("player")
-- already returns the active resource, so we never special-case classes.
--   * Casters / Healers / Hunter -> Mana   (blue)
--   * Warrior                    -> Rage   (red)
--   * Rogue                      -> Energy (yellow)
--   * Druid: switches live with form — Bear = Rage, Cat = Energy, otherwise
--            (no form / Moonkin / Tree of Life) = Mana. UNIT_DISPLAYPOWER fires
--            on every shapeshift, so the bar recolours itself.
--
-- Size, position (mover + arrow keys) and the bar text are all configurable.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("powerbar", {
    name        = "Power Bar",
    group       = "HUD",
    description = "A movable resource bar for your character. The power type follows your class automatically (Mana / Rage / Energy) — and for Druids it switches with your form: Bear = Rage, Cat = Energy, otherwise Mana.",
    defaults = {
        enabled  = true,
        width    = 220,
        height   = 20,
        x        = 0,
        y        = -200,
        unlocked = false,
        texture  = "Atrocity",
        textMode = "currentmax",   -- none | current | currentmax | percent | full
        fontSize = 12,
    },
})

local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local format, floor = string.format, math.floor

-- =========================================================
-- Power-type colours (keyed by the UnitPowerType token)
-- =========================================================
local POWER_COLORS = {
    MANA        = { r = 0.25, g = 0.45, b = 0.95 },
    RAGE        = { r = 0.85, g = 0.22, b = 0.22 },
    ENERGY      = { r = 0.95, g = 0.85, b = 0.25 },
    FOCUS       = { r = 0.95, g = 0.55, b = 0.25 },
    RUNIC_POWER = { r = 0.30, g = 0.70, b = 0.90 },
}
local DEFAULT_COLOR = POWER_COLORS.MANA

-- =========================================================
-- Bundled bar textures (same set the Swing Timer offers)
-- =========================================================
local BUNDLED_TEXTURES = {
    "Atrocity", "Beautiful", "Divide", "Fade", "Glass", "Gradient",
    "Matte", "Melli", "Plating", "Sheer", "Soft Line",
}
local DEFAULT_TEXTURE = "Atrocity"

local function lsmStatusbar(name)
    if ns.LSM and name then
        local hash = ns.LSM:HashTable("statusbar")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end
local function isBundledTexture(name)
    for _, n in ipairs(BUNDLED_TEXTURES) do if n == name then return true end end
    return false
end
local function textureValues()
    local v = {}
    for _, n in ipairs(BUNDLED_TEXTURES) do v[#v + 1] = { value = n, text = n } end
    return v
end

local function textModeValues()
    return {
        { value = "none",       text = L["No text"] },
        { value = "current",    text = L["Current value"] },
        { value = "currentmax", text = L["Current / Max"] },
        { value = "percent",    text = L["Percent"] },
        { value = "full",       text = L["Current / Max (%)"] },
    }
end

-- =========================================================
-- Frame
-- =========================================================
local frame, bar, barText

local function applyFont()
    if not barText then return end
    if ns.UI and ns.UI.Font then
        ns.UI.Font(barText, mod.db.fontSize, "OUTLINE")
    else
        barText:SetFont(STANDARD_TEXT_FONT, mod.db.fontSize, "OUTLINE")
    end
end

local function currentColor()
    local _, token = UnitPowerType("player")
    return POWER_COLORS[token] or DEFAULT_COLOR
end

local function applyAppearance()
    if not bar then return end
    bar:SetStatusBarTexture(lsmStatusbar(mod.db.texture))
    local t = bar:GetStatusBarTexture()
    if t and t.SetHorizTile then t:SetHorizTile(false); t:SetVertTile(false) end
    local c = currentColor()
    bar:SetStatusBarColor(c.r, c.g, c.b)
    applyFont()
end

local function applySize()
    if frame then frame:SetSize(mod.db.width, mod.db.height) end
end

local function applyPos()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
end

local function updateValue()
    if not bar then return end
    local cur = UnitPower("player") or 0
    local max = UnitPowerMax("player") or 0
    if max <= 0 then max = 1 end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    if not barText then return end
    local mode = mod.db.textMode
    if mode == "none" then
        barText:SetText("")
    elseif mode == "current" then
        barText:SetText(tostring(cur))
    elseif mode == "percent" then
        barText:SetText(floor(cur / max * 100 + 0.5) .. "%")
    elseif mode == "full" then
        barText:SetText(format("%d / %d  (%d%%)", cur, max, floor(cur / max * 100 + 0.5)))
    else -- currentmax
        barText:SetText(format("%d / %d", cur, max))
    end
end

local function updatePowerType()
    applyAppearance()  -- recolour for the new resource (Druid form switch)
    updateValue()
end

local function addBorder(f)
    local function edge()
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 0.9)
        return t
    end
    local top = edge(); top:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1); top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1); top:SetHeight(1)
    local bot = edge(); bot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -1, -1); bot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1); bot:SetHeight(1)
    local lft = edge(); lft:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1); lft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -1, -1); lft:SetWidth(1)
    local rgt = edge(); rgt:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1); rgt:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1); rgt:SetWidth(1)
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "VCUIPowerBar", UIParent)
    frame:SetSize(mod.db.width, mod.db.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    frame:SetFrameStrata("MEDIUM")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.85)

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    addBorder(frame)

    barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    barText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    applyFont()

    frame.mover = ns:CreateMover(frame, {
        label  = L["|cffffffffPOWER BAR|r\n|cffaaaaaaDrag or arrow keys|r"],
        db     = mod.db,
        width  = math.max(mod.db.width + 20, 140),
        height = math.max(mod.db.height + 24, 44),
    })
    return frame
end

-- =========================================================
-- Unlock / move
-- =========================================================
local function setUnlocked(state)
    mod.db.unlocked = state and true or false
    build()
    if mod.db.unlocked then
        frame:Show()
        frame.mover:Show()
        ns:Print(L["Power Bar mover active. |cff9b6cffDrag the purple box|r or use |cff9b6cffarrow keys|r (SHIFT = 5px). Click 'Unlock / Move' again to finish."])
    else
        frame.mover:Hide()
        ns:Print(L["Power Bar mover disabled."])
    end
end

-- =========================================================
-- Events
-- =========================================================
local ev
local function registerEvents()
    if ev then return end
    ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "UNIT_DISPLAYPOWER" then
            updatePowerType()
        elseif event == "PLAYER_ENTERING_WORLD" then
            applyAppearance(); updateValue()
        else
            updateValue()
        end
    end)
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    if not isBundledTexture(mod.db.texture) then mod.db.texture = DEFAULT_TEXTURE end
    build()
    applySize(); applyPos(); applyAppearance(); updateValue()
    registerEvents()
    frame:Show()
end

function mod:OnDisable()
    if ev then ev:UnregisterAllEvents() end
    if frame then frame:Hide() end
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local items = {}

    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaResource bar that follows your class automatically (Mana / Rage / Energy). Druids switch with their form: Bear = Rage, Cat = Energy, otherwise Mana.|r"] })

    table.insert(items, {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", label = L["Unlock / Move"], width = 130,
              onClick = function() setUnlocked(not mod.db.unlocked) end },
            { type = "button", label = L["Center Position"], width = 150,
              onClick = function() mod.db.x, mod.db.y = 0, -200; applyPos() end },
        },
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Size"] })
    table.insert(items, {
        type = "slider", label = L["Width"], min = 80, max = 600, step = 2,
        get = function() return mod.db.width end,
        set = function(_, v) mod.db.width = v; applySize() end,
    })
    table.insert(items, {
        type = "slider", label = L["Height"], min = 6, max = 60, step = 1,
        get = function() return mod.db.height end,
        set = function(_, v) mod.db.height = v; applySize() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Text"] })
    table.insert(items, {
        type = "dropdown", label = L["Bar text"], width = 240, values = textModeValues(),
        get = function() return mod.db.textMode end,
        set = function(_, v) mod.db.textMode = v; updateValue() end,
    })
    table.insert(items, {
        type = "slider", label = L["Font size"], min = 8, max = 24, step = 1,
        get = function() return mod.db.fontSize end,
        set = function(_, v) mod.db.fontSize = v; applyFont() end,
    })

    table.insert(items, { type = "spacer", height = 6 })
    table.insert(items, { type = "header", text = L["Appearance"] })
    table.insert(items, {
        type = "dropdown", label = L["Bar texture"], width = 240, values = textureValues(),
        get = function() return mod.db.texture end,
        set = function(_, v) mod.db.texture = v; applyAppearance() end,
    })
    table.insert(items, { type = "desc",
        text = L["|cffaaaaaaThe bar colour follows your current power type automatically (Mana = blue, Rage = red, Energy = yellow).|r"] })

    return items
end
