-- =========================================================
-- VuloClassicUI / Modules / EliteVuloFrame
-- Gives the player frame the elite/rare dragon border known from
-- target frames. Technique: swap PlayerFrameTexture for the (wider)
-- horizontally-flipped target-frame texture, re-anchor it with the
-- 2.5.5 Anniversary layout offsets, then re-align the level text and
-- rest icon and lift pet/totem/group frames above the bigger art.
-- All original values are captured before the first change so the
-- default look can be restored exactly (style "off" / module off).
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("elitevuloframe", {
    name        = "EliteVuloFrame",
    group       = "Unit Frames",
    description = "Gives your player frame the elite dragon border (elite, rare-elite or rare style).",
    defaults    = {
        enabled = true,
        style   = "elite",   -- "elite" | "rareelite" | "rare" | "off"
    },
})

-- =========================================================
-- Texture data (target-frame art, flipped horizontally for the
-- mirrored player frame). Anniversary 2.5.5 moved player frame
-- elements directly, hence the -17.5 / -3.5 normalisation offsets.
-- =========================================================
-- The Anniversary 2.5.5 client shifted the player-frame elements, so the (wider)
-- elite texture needs this -17.5/-3.5 normalisation to sit right. Classic Era keeps
-- the original (un-shifted) layout, so on Era the same offset would push the dragon
-- art + level badge ~17px off — there it needs no shift.
local BASE_X, BASE_Y = -17.5, -3.5
if ns.isEra then BASE_X, BASE_Y = 0, 0 end
local LEVEL_X, LEVEL_Y = 52.5 + BASE_X, -67 + BASE_Y
-- Era's player frame is sized slightly differently, so the level number lands a
-- touch too far left over the elite art; nudge it right (tune this value if needed).
if ns.isEra then LEVEL_X = LEVEL_X + 8 end

local STYLES = {
    elite = {
        file = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
        w = 232, h = 101, l = 256 / 256, r = 24 / 256, t = 0, b = 101 / 128,
        ox = 0, oy = 0,
    },
    rareelite = {
        file = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
        w = 232, h = 101, l = 256 / 256, r = 24 / 256, t = 0, b = 101 / 128,
        ox = 0, oy = 0,
    },
    rare = {
        file = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
        w = 226, h = 101, l = 250 / 256, r = 24 / 256, t = 0, b = 101 / 128,
        ox = 6, oy = 0,
    },
}

-- Frames lifted above the enlarged border art (original levels restored)
local RAISE_FRAMES = {
    { name = "PlayerFrameGroupIndicator", lift = 1 },
    { name = "PetFrame",                  lift = 2 },
    { name = "TotemFrame",                lift = 3 },
}

-- =========================================================
-- Capture / restore the default look
-- =========================================================
local captured  -- nil until the first apply

local function capturePoints(frame)
    local pts = {}
    for i = 1, frame:GetNumPoints() do
        pts[i] = { frame:GetPoint(i) }
    end
    return pts
end

local function restorePoints(frame, pts)
    if not pts or #pts == 0 then return end
    frame:ClearAllPoints()
    for _, p in ipairs(pts) do
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

local function captureDefaults()
    if captured then return true end
    local tex   = _G.PlayerFrameTexture
    local level = _G.PlayerLevelText
    if not tex or not level then return false end

    captured = {
        tex = {
            points   = capturePoints(tex),
            file     = tex:GetTexture(),
            texCoord = { tex:GetTexCoord() },
            width    = tex:GetWidth(),
            height   = tex:GetHeight(),
        },
        levelPoints = capturePoints(level),
        restPoints  = _G.PlayerRestIcon and capturePoints(_G.PlayerRestIcon) or nil,
        levels      = {},
    }
    for _, def in ipairs(RAISE_FRAMES) do
        local f = _G[def.name]
        if f then captured.levels[def.name] = f:GetFrameLevel() end
    end
    return true
end

local function restoreDefaults()
    if not captured then return end
    local tex = _G.PlayerFrameTexture
    if tex then
        restorePoints(tex, captured.tex.points)
        if captured.tex.file then tex:SetTexture(captured.tex.file) end
        local tc = captured.tex.texCoord
        if tc and #tc == 8 then tex:SetTexCoord(unpack(tc)) end
        tex:SetSize(captured.tex.width, captured.tex.height)
    end
    if _G.PlayerLevelText then restorePoints(_G.PlayerLevelText, captured.levelPoints) end
    if _G.PlayerRestIcon and captured.restPoints then
        restorePoints(_G.PlayerRestIcon, captured.restPoints)
    end
    for _, def in ipairs(RAISE_FRAMES) do
        local f = _G[def.name]
        local lvl = captured.levels[def.name]
        if f and lvl then f:SetFrameLevel(lvl) end
    end
end

-- =========================================================
-- Apply the chosen style
-- =========================================================
local function styleActive()
    return mod._enabled and mod.db.style ~= "off" and STYLES[mod.db.style] ~= nil
end

-- Level text + rest icon: normalised positions for the bigger art.
-- Also re-run from the Blizzard anchor hook (it resets the anchor).
local function applyTextPositions()
    if not styleActive() or not captured then return end
    local level = _G.PlayerLevelText
    if level then
        level:ClearAllPoints()
        level:SetPoint("CENTER", _G.PlayerFrame, "TOPLEFT", LEVEL_X, LEVEL_Y)
    end
    local rest = _G.PlayerRestIcon
    if rest and level then
        rest:ClearAllPoints()
        rest:SetPoint("CENTER", level, "CENTER", 0, 1)
    end
end

local function applyStyle()
    if not captureDefaults() then return end
    local s = STYLES[mod.db.style]
    if not s then
        restoreDefaults()
        return
    end

    local tex = _G.PlayerFrameTexture
    if not tex then return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", _G.PlayerFrame, "TOPLEFT", BASE_X + s.ox, BASE_Y + s.oy)
    tex:SetTexture(s.file)
    tex:SetTexCoord(s.l, s.r, s.t, s.b)
    tex:SetSize(s.w, s.h)

    applyTextPositions()

    local base = tex:GetParent():GetFrameLevel()
    for _, def in ipairs(RAISE_FRAMES) do
        local f = _G[def.name]
        if f then f:SetFrameLevel(base + def.lift) end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local anchorHooked = false

local function onWorldEnter()
    if mod._enabled then applyStyle() end
end

function mod:OnEnable()
    applyStyle()
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)

    -- Blizzard re-anchors the level text (e.g. on level-up); follow it.
    -- hooksecurefunc is permanent, so install once and gate on state.
    if not anchorHooked and _G.PlayerFrame_UpdateLevelTextAnchor then
        anchorHooked = true
        hooksecurefunc("PlayerFrame_UpdateLevelTextAnchor", applyTextPositions)
    end
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onWorldEnter)
    restoreDefaults()
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["EliteVuloFrame"] },
        { type = "desc",
          text = L["|cffaaaaaaPuts the golden elite dragon (or the rare variants) around your player portrait — the look elite mobs have on the target frame.|r"] },
        { type = "spacer", height = 4 },
        { type = "dropdown", label = L["Frame style"], width = 240,
          values = {
              { value = "elite",     text = L["Elite (golden dragon)"] },
              { value = "rareelite", text = L["Rare-Elite (silver dragon)"] },
              { value = "rare",      text = L["Rare (silver)"] },
              { value = "off",       text = L["Off (default frame)"] },
          },
          get = function() return mod.db.style end,
          set = function(_, v)
              mod.db.style = v
              applyStyle()
          end },
    }
end
