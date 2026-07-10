-- =========================================================
-- VuloClassicUI / Modules / DarkMode
-- Darkens + desaturates Blizzard's DEFAULT UI artwork (unit frames, minimap,
-- action bars) to a neutral dark tone, pointed at Blizzard's own textures
-- because VuloClassicUI keeps the default frames instead of reskinning them.
--
-- Technique: texture:SetDesaturated(true) + :SetVertexColor(grey).
-- Purely cosmetic vertex recolour on existing regions -> no taint, no secure
-- actions, fully reversible (restore to white / not-desaturated on disable).
--
-- Everything is guarded with _G[name] existence checks so a region that only
-- exists on one client (e.g. FocusFrame, tracking border) simply no-ops on the
-- other. Blizzard re-tints some textures on redraw, so we re-apply on the
-- relevant events + hooks.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("darkmode", {
    name        = "Dark Mode",
    group       = "UI Reskin",
    description = "Darkens and desaturates Blizzard's default UI artwork (unit frames, minimap, action bars) to a neutral dark tone. Keeps Blizzard's frames — it just re-tints them.",
    defaults = {
        enabled       = false,                         -- opt-in: it restyles the whole default UI
        desaturate    = true,                          -- strip colour before tinting (true greyscale)
        color         = { r = 0.40, g = 0.40, b = 0.40 },  -- neutral grey
        unitframes    = true,
        minimap       = true,
        actionbars    = true,
        actionButtons = false,                         -- opt-in (tints the button border art)
        actionBarBorder = true,                        -- drive Button Skin's dark bar border with Dark Mode
        bags          = false,                         -- opt-in
    },
})

-- ---------------------------------------------------------
-- Paint helpers
-- ---------------------------------------------------------
local function colorRGB()
    local c = mod.db and mod.db.color
    if not c then return 0.4, 0.4, 0.4 end
    return c.r or 0.4, c.g or 0.4, c.b or 0.4
end

-- on=true  -> desaturate (optional) + tint to the chosen colour
-- on=false -> restore Blizzard's default (full colour, white vertex)
local function paint(tex, on)
    if not tex or not tex.SetVertexColor then return end
    if on then
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, mod.db.desaturate and true or false) end
        tex:SetVertexColor(colorRGB())
    else
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, false) end
        tex:SetVertexColor(1, 1, 1)
    end
end

local function paintGlobals(names, on)
    for _, n in ipairs(names) do paint(_G[n], on) end
end

-- Tint a button's NormalTexture (the metal border ring around the icon).
local function paintNormal(btnName, on)
    local b = _G[btnName]
    if not b or not b.GetNormalTexture then return end
    paint(b:GetNormalTexture(), on)
end

-- ---------------------------------------------------------
-- Region tables (Classic-era FrameXML names; valid on TBC 2.5.x + Era 1.15)
-- ---------------------------------------------------------
-- Gold metal borders of the standard unit frames.
local UNIT_BORDERS = {
    "PlayerFrameTexture",
    "TargetFrameTextureFrameTexture",
    "FocusFrameTextureFrameTexture",          -- TBC only (absent on Era -> guarded no-op)
    "PetFrameTexture",
    "PartyMemberFrame1Texture", "PartyMemberFrame2Texture",
    "PartyMemberFrame3Texture", "PartyMemberFrame4Texture",
    "TargetFrameToTTextureFrameTexture",      -- target-of-target
    "FocusFrameToTTextureFrameTexture",
}

-- Round minimap chrome. (Tracking/World/LFG border names differ by flavor;
-- all are guarded so the ones absent on a given client simply no-op.)
local MINIMAP_REGIONS = {
    "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag",
    "MiniMapTrackingButtonBorder", "MiniMapTrackingBorder",
    "MiniMapMailBorder", "MiniMapBattlefieldBorder",
    "MiniMapWorldBorder", "MiniMapLFGBorder",          -- TBC-only extras
}
local MINIMAP_BUTTONS = { "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton" }

-- Main action bar artwork: the gryphons + the metal bar background pieces.
local ACTIONBAR_ART = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",     -- the gryphons
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarTextureExtender",
}

-- Button bars whose NormalTexture (border) we optionally tint.
local ACTION_BUTTON_BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton",
}
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "KeyRingButton",
}

-- Button Skin owns the action-button NormalTexture when it's actively skinning
-- the bars; our greyscale tint of that same region would just fight it (and lose,
-- since Button Skin hides the texture), so we skip it in that case.
local function buttonSkinOwnsBars()
    local bs = ns.modules and ns.modules.buttonskin
    return (ns:IsModuleEnabled("buttonskin") and bs and bs.db and bs.db.skinBars) and true or false
end

-- ---------------------------------------------------------
-- Per-area apply / restore
-- ---------------------------------------------------------
local function applyUnitframes(on) paintGlobals(UNIT_BORDERS, on) end

local function applyMinimap(on)
    paintGlobals(MINIMAP_REGIONS, on)
    for _, n in ipairs(MINIMAP_BUTTONS) do paintNormal(n, on) end
end

local function applyActionbars(on) paintGlobals(ACTIONBAR_ART, on) end

local function applyActionButtons(on)
    if on and buttonSkinOwnsBars() then return end   -- Button Skin owns these buttons' border
    for _, bar in ipairs(ACTION_BUTTON_BARS) do
        for i = 1, 12 do paintNormal(bar .. i, on) end
    end
end

local function applyBags(on)
    for _, n in ipairs(BAG_BUTTONS) do paintNormal(n, on) end
end

-- Our own active flag. We can't use mod._enabled here: the core sets that to
-- true only AFTER OnEnable returns (ns:SafeEnable), so during the initial
-- apply in OnEnable it is still false. We flip `active` ourselves at the top of
-- OnEnable / in OnDisable so the very first applyAll() (and a manual toggle-on,
-- which has no following loading screen) takes effect immediately.
local active = false

-- An area is "on" only while the module is active AND that area's toggle is set;
-- otherwise we paint it back to default, so flipping a toggle off restores it.
local function isOn(area)
    return (active and mod.db[area]) and true or false
end

local function applyAll()
    applyUnitframes(isOn("unitframes"))
    applyMinimap(isOn("minimap"))
    applyActionbars(isOn("actionbars"))
    applyActionButtons(isOn("actionButtons"))
    applyBags(isOn("bags"))
end

local function restoreAll()
    applyUnitframes(false)
    applyMinimap(false)
    applyActionbars(false)
    applyActionButtons(false)
    applyBags(false)
end

-- ---------------------------------------------------------
-- Action-bar dark border — driven through the Button Skin module so it's the
-- exact same look as before (and Button Skin stays independently usable: you can
-- switch the border on with Dark Mode OFF straight from Button Skin's options).
-- Dark Mode remembers the border's PRIOR state and restores it on disable, so it
-- never clobbers a border you turned on yourself.
-- ---------------------------------------------------------
local _dmPrevSkinBars, _dmTouchedBars = false, false

local function driveBars(on)
    local bs = ns.modules and ns.modules.buttonskin
    if not (bs and bs.SetBarsSkinned and bs.db and ns:IsModuleEnabled("buttonskin")) then
        return false   -- Button Skin module off/absent -> nothing to drive
    end
    bs.db.skinBars = on and true or false
    bs.SetBarsSkinned(on and true or false)
    return true
end

-- want=true  -> show the bar border (after saving what it was)
-- want=false -> release it back to the pre-Dark-Mode state
local function syncBarBorder(want)
    if want then
        -- already DM-driven: do NOT re-force, so a manual OFF via Button Skin sticks
        -- (and the PLAYER_ENTERING_WORLD re-assert becomes a no-op once driven).
        if _dmTouchedBars then return end
        local bs = ns.modules and ns.modules.buttonskin
        local prev = (bs and bs.db and bs.db.skinBars) and true or false
        -- only commit the snapshot if the drive actually applied (Button Skin
        -- present + enabled) — a no-op drive must not record a bogus prior state.
        if driveBars(true) then
            _dmPrevSkinBars = prev
            _dmTouchedBars  = true
        end
    elseif _dmTouchedBars then
        driveBars(_dmPrevSkinBars)
        _dmTouchedBars = false
    end
end

-- Button Skin calls this when the user toggles "Skin the action bars" directly,
-- so our remembered prior tracks their explicit choice — Dark Mode then never
-- re-forces (above) nor restores a stale value over their manual change.
function mod.NotifyUserSetBars(v)
    if _dmTouchedBars then _dmPrevSkinBars = v and true or false end
end

-- ---------------------------------------------------------
-- Re-apply hooks (Blizzard resets some textures on redraw)
-- ---------------------------------------------------------
local hooked = false
local function installHooks()
    if hooked then return end
    hooked = true

    -- Target/Focus border texture is swapped on classification changes.
    if _G.TargetFrame_CheckClassification then
        hooksecurefunc("TargetFrame_CheckClassification", function(self)
            if not isOn("unitframes") then return end
            local n = self and self.GetName and self:GetName()
            if n then paint(_G[n .. "TextureFrameTexture"], true) end
        end)
    end

    -- Action button NormalTexture is reset when the slot's contents update.
    if _G.ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(btn)
            if not isOn("actionButtons") or buttonSkinOwnsBars() then return end
            if btn and btn.GetNormalTexture then paint(btn:GetNormalTexture(), true) end
        end)
    end
end

-- ---------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------
local eventsWired = false
local function wireEvents()
    if eventsWired then return end
    eventsWired = true

    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        applyAll()
        -- re-assert (also covers the login case where Button Skin enables after us)
        syncBarBorder(active and mod.db.actionBarBorder)
    end)
    ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        if isOn("unitframes") then paint(_G.TargetFrameTextureFrameTexture, true) end
    end)
    ns:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
        if isOn("unitframes") then paint(_G.FocusFrameTextureFrameTexture, true) end
    end)
    ns:RegisterEvent("UNIT_PET", function()
        if isOn("unitframes") then paint(_G.PetFrameTexture, true) end
    end)
    ns:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        if isOn("unitframes") then
            paintGlobals({ "PartyMemberFrame1Texture", "PartyMemberFrame2Texture",
                           "PartyMemberFrame3Texture", "PartyMemberFrame4Texture" }, true)
        end
    end)
end

function mod:OnEnable()
    active = true
    installHooks()   -- once-only (guarded); hooks stay and are gated by isOn()
    wireEvents()     -- once-only (guarded); ns:RegisterEvent has no dedupe, so we
                     -- must NOT re-register on re-enable -> the guard is intentional
    applyAll()
    syncBarBorder(mod.db.actionBarBorder)   -- drive Button Skin's dark bar border on
end

function mod:OnDisable()
    active = false
    restoreAll()
    syncBarBorder(false)   -- release the bar border back to its pre-Dark-Mode state
    -- Hooks/events stay installed but are gated by isOn() (active=false now);
    -- a /reload reverts everything cleanly.
end

-- ---------------------------------------------------------
-- Options
-- ---------------------------------------------------------
function mod:GetOptions()
    local function apply() applyAll() end
    local function areaToggle(key, label, tooltip)
        return {
            type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v) mod.db[key] = v; apply() end,
        }
    end

    return {
        { type = "header", text = L["Dark Mode"] },
        { type = "desc",   text = L["|cffaaaaaaDarkens and desaturates Blizzard's default artwork — unit frames, minimap and action bars — to a neutral dark tone. Reversible: turn it off and the gold look returns.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Look"] },
        { type = "toggle", label = L["Desaturate (greyscale)"],
          tooltip = L["Strips the colour out of the artwork before tinting, for a true greyscale look. Off keeps a hint of the original hue."],
          get = function() return mod.db.desaturate end,
          set = function(_, v) mod.db.desaturate = v; apply() end },
        { type = "color", label = L["Tint colour"], width = 160,
          get = function() return mod.db.color end,
          set = function(r, g, b) mod.db.color = { r = r, g = g, b = b }; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Apply to"] },
        areaToggle("unitframes", L["Unit frames"],
            L["Player, target, focus, pet and party frame borders."]),
        areaToggle("minimap", L["Minimap"],
            L["Minimap border, compass, zoom and tracking buttons."]),
        areaToggle("actionbars", L["Action bar artwork"],
            L["The gryphons and the metal action-bar background."]),
        areaToggle("actionButtons", L["Action button borders"],
            L["Also tints the border ring around every action button. Optional — leave off if it looks too flat."]),
        { type = "toggle", label = L["Action bar dark border"],
          tooltip = L["Adds the dark Button Skin border to the action bars while Dark Mode is on (and removes it when Dark Mode turns off). You can also switch it on with Dark Mode off in the Button Skin module."],
          get = function() return mod.db.actionBarBorder end,
          set = function(_, v) mod.db.actionBarBorder = v; syncBarBorder(active and v) end },
        areaToggle("bags", L["Bag slots"],
            L["Tints the backpack, bag and keyring button borders."]),

        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaNote: if the Player & Target Frame module's |cffffffffThreat glow|r is on, threat colouring takes over the target/focus border while you have aggro — that's intended.|r"] },
        { type = "desc", text = L["|cffaaaaaaAction button borders are also managed by the Button Skin module — if that's on, it controls the buttons instead.|r"] },
    }
end
