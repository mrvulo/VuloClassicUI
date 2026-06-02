-- =========================================================
-- VuloClassicUI / Modules / ButtonSkin
-- Built-in dark drop-shadow skin for Blizzard action buttons + WeakAuras
-- icons — no external skinning framework required:
--   - icons cropped so the ugly default border is gone
--   - chunky NormalTexture border removed
--   - rounded icon shape (mask) + a soft black rim around each icon
--   - several styles: shadow / rounded / square / accent / circle / minimal
-- Everything is drawn by VuloClassicUI itself. No external library, no
-- secure-frame writes (only textures/regions are touched), fully toggleable.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("buttonskin", {
    name        = "Button Skin",
    group       = "UI Reskin",
    description = "Built-in dark drop-shadow skin for action buttons and WeakAuras icons: black, rounded, soft rim. Several styles, no extra addons needed.",
    defaults = {
        enabled       = true,
        style         = "shadow",  -- action bars: shadow | rounded | square | accent | circle | minimal
        waStyle       = "shadow",  -- WeakAuras icons: same set, configured separately
        skinPetStance = true,      -- also skin pet + stance buttons
        skinBars      = true,      -- skin the action bars
        skinWeakAuras = true,      -- skin WeakAuras icons
        hideWABorder  = true,      -- hide WeakAuras' own border subregions when skinning
    },
})

-- Action button name prefixes × 12 ids
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
}
local EXTRA_PREFIXES = { "PetActionButton", "StanceButton" }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- Bundled textures (shipped under Media\Masks\, load reliably in Classic).
local MASK_ROUNDED = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\csquare_mask.tga"  -- rounded square
local MASK_CIRCLE  = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\circle_mask.tga"
local MASK_SQUARE  = "Interface\\Buttons\\WHITE8X8"                                      -- plain square
local TEX_BACKDROP = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\Backdrop.tga"      -- filled rounded fill
local TEX_BORDER   = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\Normal.tga"        -- black rounded border + soft shadow

-- The rim is created by insetting the icon's MASK (icon reads smaller, the dark
-- backdrop shows around it). The inset is a FRACTION of the icon size so the
-- rim looks the same on small and large icons (a fixed px rim is too thick on
-- small icons, too thin on big ones). RIM_OUTSET is a small fixed bleed for the
-- soft shadow past the frame edge. Shrinking via the mask survives game updates.
local RIM_OUTSET  = 2
local SHRINK_PCT  = 0.12   -- icon shows at ~76% of the frame (reference proportion)

-- The shadow layers behind the icon: filled dark backdrop + black rounded
-- border with a soft drop-shadow (the real "Shadow" look), both bleeding a
-- few px past the frame edge.
local function attachShadow(frame, store, outset)
    if not frame then return end
    store = store or frame
    outset = outset or RIM_OUTSET

    if not store._vcuiBack then
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        back:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        back:SetTexture(TEX_BACKDROP)
        back:SetVertexColor(0.03, 0.03, 0.04, 1)   -- near-black, merges with the border
        store._vcuiBack = back

        local ring = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        ring:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        ring:SetTexture(TEX_BORDER)
        ring:SetVertexColor(0, 0, 0, 1)
        store._vcuiRing = ring
    end
end

-- Style table: how each style draws a button
--   border = "black" | "accent" | nil (none)
--   bg     = dark backdrop behind the icon
--   mask   = mask texture (rounds the icon + backdrop) or nil
--   shadow = dark rounded rim (masked backdrop) around a rounded icon
local STYLES = {
    -- Default: rounded icon with a soft dark rounded rim around it.
    shadow   = { border = nil,      bg = true,  mask = nil,          shadow = true  },  -- rounded icon + dark rim
    rounded  = { border = nil,      bg = true,  mask = MASK_ROUNDED, shadow = false },  -- icon corners masked round
    square   = { border = "black",  bg = true,  mask = nil,          shadow = false },  -- crisp square, black 1px edge
    accent   = { border = "accent", bg = true,  mask = nil,          shadow = false },  -- square, purple edge
    circle   = { border = nil,      bg = true,  mask = MASK_CIRCLE,  shadow = false },  -- circular
    minimal  = { border = nil,      bg = false, mask = nil,          shadow = false },  -- cropped icon only
}

-- Style for the action bars (key="style") or WeakAuras (key="waStyle")
local function currentStyle(forWA)
    local key = mod.db and (forWA and mod.db.waStyle or mod.db.style)
    return STYLES[key] or STYLES.shadow
end

-- =========================================================
-- Skin a single button
-- =========================================================
local function getRegion(button, suffix, fallback)
    local name = button:GetName()
    return (name and _G[name .. suffix]) or fallback
end

local function hideNormalTexture(button)
    -- Action buttons expose the chunky gold border as NormalTexture
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        nt:SetTexture(nil)
        nt:SetAlpha(0)
    end
    -- Empty-slot grid border (shown when "always show buttons" is on)
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(0) end
end

-- Blizzard re-applies the NormalTexture on state changes and this client has
-- no reliable global ActionButton_Update, so hook each button's setter once.
local function lockNormalTexture(button)
    if button._vcuiNTHook or not button.SetNormalTexture then return end
    button._vcuiNTHook = true
    hooksecurefunc(button, "SetNormalTexture", function(self)
        if mod._enabled and self._vcuiSkinned then
            local n = self.GetNormalTexture and self:GetNormalTexture()
            if n and n.GetAlpha and n:GetAlpha() ~= 0 then
                n:SetTexture(nil); n:SetAlpha(0)
            end
        end
    end)
end

-- Lazily create the button's reusable icon mask texture
local function ensureMask(button)
    if not button._vcuiMask and button.CreateMaskTexture then
        button._vcuiMask = button:CreateMaskTexture()
    end
    return button._vcuiMask
end

-- Mask the icon. `pct` insets the mask by that fraction of the icon size, so
-- the icon reads smaller and the dark backdrop shows as a rim around it. Using
-- a fraction keeps the rim proportional on small and large icons. Done via mask
-- size (survives game updates), not by re-anchoring the icon.
local function setMasked(button, icon, on, maskTex, pct)
    if on then
        local m = ensureMask(button)
        if not m then return end
        m:ClearAllPoints()
        pct = pct or 0
        if pct > 0 then
            local w = icon:GetWidth() or 0
            if w < 1 then w = (button.GetWidth and button:GetWidth()) or 32 end
            local inset = math.max(1, w * pct)
            m:SetPoint("TOPLEFT",     icon, "TOPLEFT",      inset, -inset)
            m:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset,  inset)
        else
            m:SetAllPoints(icon)
        end
        m:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:Show()
        if not button._vcuiMaskOn then
            if icon.AddMaskTexture then pcall(icon.AddMaskTexture, icon, m) end
            button._vcuiMaskOn = true
        end
    elseif button._vcuiMaskOn and button._vcuiMask then
        local m = button._vcuiMask
        if icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, m) end
        m:Hide()
        button._vcuiMaskOn = false
    end
end

-- Apply the current style's look to an already-prepared button
local function applyStyle(button)
    local st   = currentStyle()
    local icon = getRegion(button, "Icon", button.icon or button.Icon)

    -- Always crop away the icon's built-in border ring
    if icon and icon.SetTexCoord then icon:SetTexCoord(unpack(ICON_CROP)) end

    -- Eckiger Fallback-Backdrop nur ohne Shadow-Style
    if button._vcuiBg then
        button._vcuiBg:SetShown((st.bg and not st.shadow) and true or false)
    end

    -- Shadow style: filled backdrop + black rounded border behind the icon
    local showShadow = st.shadow and true or false
    if button._vcuiBack then button._vcuiBack:SetShown(showShadow) end
    if button._vcuiRing then button._vcuiRing:SetShown(showShadow) end

    -- Icon mask. Shadow = square mask inset a few px (icon reads smaller, the
    -- backdrop shows as a rim around it). Rounded/Circle = full mask.
    if icon then
        local maskTex = st.mask or (st.shadow and MASK_SQUARE) or nil
        local pct     = st.shadow and SHRINK_PCT or 0
        setMasked(button, icon, maskTex ~= nil, maskTex, pct)
    end

    -- Border
    if button._vcuiBorder then
        if st.border then
            button._vcuiBorder:Show()
            if st.border == "accent" then
                local a = ns.COLORS.accent
                button._vcuiBorder:SetBackdropBorderColor(a.r, a.g, a.b, 1)
            else
                button._vcuiBorder:SetBackdropBorderColor(0, 0, 0, 1)
            end
        else
            button._vcuiBorder:Hide()
        end
    end
end

local function skinButton(button)
    if not button then return end
    if not button._vcuiSkinned then
        button._vcuiSkinned = true

        -- Dark rounded rim (masked backdrop) one size larger than the icon,
        -- created once here and shown/hidden per style in applyStyle.
        attachShadow(button, button)

        -- Keep Blizzard's gold border from coming back
        lockNormalTexture(button)

        -- Dark backdrop behind the icon (created once; shown/hidden per style)
        local bg = button:CreateTexture(nil, "BACKGROUND", nil, -2)
        bg:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.04, 0.04, 0.05, 0.9)
        button._vcuiBg = bg

        -- Thin 1px border frame (created once; colored/shown per style)
        local border = CreateFrame("Frame", nil, button,
            BackdropTemplateMixin and "BackdropTemplate")
        border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
        if border.SetBackdrop then
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        end
        local lvl = button:GetFrameLevel() or 1
        border:SetFrameLevel(math.max(0, lvl - 1))
        button._vcuiBorder = border
    end

    hideNormalTexture(button)
    applyStyle(button)
end

-- =========================================================
-- Skin all buttons
-- =========================================================
local function forEachButton(fn)
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then fn(b) end
        end
    end
    if mod.db.skinPetStance then
        for _, prefix in ipairs(EXTRA_PREFIXES) do
            for i = 1, 12 do
                local b = _G[prefix .. i]
                if b then fn(b) end
            end
        end
    end
end

local function skinAll()
    if not mod._enabled or not mod.db or not mod.db.skinBars then return end
    forEachButton(skinButton)
end

-- Re-apply the active style without re-creating frames
local function refreshAll()
    if not mod._enabled or not mod.db then return end
    forEachButton(function(b)
        if b._vcuiSkinned then
            hideNormalTexture(b)
            applyStyle(b)
        end
    end)
end

-- =========================================================
-- WeakAuras icon skinning — VuloClassicUI's own skin, configured separately
-- from the bars (its own style dropdown). The backdrop/border are textures and
-- the icon is masked (no re-anchoring), so it survives WeakAuras' updates.
-- =========================================================
-- Size the cooldown to match the (masked) icon — like the reference skin sizes
-- Cooldown to the icon, so the sweep/number sit on the icon, not overhang it.
local function insetCooldown(region, icon, pct)
    local cd = region.cooldown
    if not (cd and cd.ClearAllPoints) then return end
    cd:ClearAllPoints()
    if pct and pct > 0 then
        local w = (icon and icon:GetWidth()) or 0
        if w < 1 then w = (region.GetWidth and region:GetWidth()) or 32 end
        local inset = math.max(1, w * pct)
        cd:SetPoint("TOPLEFT",     icon, "TOPLEFT",      inset, -inset)
        cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset,  inset)
    else
        cd:SetAllPoints(icon)
    end
end

local function styleWAIcon(region)
    if not region or region.regionType ~= "icon" then return end
    local icon = region.icon
    if not icon then return end

    attachShadow(region, region, 1)             -- create backdrop once
    local st = currentStyle(true)               -- WeakAuras style
    local showShadow = st.shadow and true or false

    -- Reference construction (icon 32 / backdrop 42 / base 36): the icon is only
    -- shrunk a little (~89%) and the dark backdrop + border bleed OUTWARD (~117%)
    -- past the frame to form the rim + soft shadow. A bit wider + darker here.
    local WA_SHRINK = 0.08    -- icon ~84% (a touch more inset than the 89% reference)
    local WA_RIM    = 0.12    -- backdrop/border bleed outward (a bit wider than 117%)

    local w = (icon and icon:GetWidth()) or 0
    if w < 1 then w = (region.GetWidth and region:GetWidth()) or 32 end
    local out = w * WA_RIM

    for _, t in ipairs({ region._vcuiBack, region._vcuiRing }) do
        if t then
            t:SetShown(showShadow)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     region, "TOPLEFT",     -out,  out)
            t:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT",  out, -out)
        end
    end
    if region._vcuiBack then region._vcuiBack:SetVertexColor(0.02, 0.02, 0.03, 1) end  -- near-black

    local maskTex = st.mask or (st.shadow and MASK_SQUARE) or nil
    local pct     = st.shadow and WA_SHRINK or 0
    setMasked(region, icon, maskTex ~= nil, maskTex, pct)

    -- Inset the cooldown to the masked icon (centres the number on it) and make
    -- the GCD/cooldown SWEEP transparent — we can't reliably resize the sweep to
    -- the framed icon in WeakAuras without Masque, and full-size it overhangs.
    -- The countdown number still shows. Re-applied via SetCooldown (WeakAuras
    -- re-draws the sweep when a cooldown starts).
    local function fixCD(cd)
        insetCooldown(region, icon, pct)
        if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0) end
    end
    if region.cooldown then
        fixCD(region.cooldown)
        if not region.cooldown._vcuiCDHook then
            region.cooldown._vcuiCDHook = true
            hooksecurefunc(region.cooldown, "SetCooldown", function(self)
                if mod._enabled and mod.db and mod.db.skinWeakAuras then fixCD(self) end
            end)
        end
    end

    -- Hide WeakAuras' own "Border" sub-regions — our rim replaces them, and a
    -- second light border on top looks wrong. (Border subregions are the ones
    -- exposing a SetBorderColor method; we leave Background/Glow/etc. alone.)
    if mod.db.hideWABorder and region.subRegions then
        for _, sub in ipairs(region.subRegions) do
            if type(sub) == "table" and sub.SetBorderColor and sub.Hide then
                sub:Hide()
            end
        end
    end
end

local function skinWAById(id)
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local ok, region = pcall(WeakAuras.GetRegion, id)
    if ok and region then styleWAIcon(region) end
    -- Also skin any currently-active CLONES (one aura showing multiple icons).
    -- GetRegion(id) only returns the base region, so these were missed before.
    if WeakAuras.clones and type(WeakAuras.clones[id]) == "table" then
        for _, cloneRegion in pairs(WeakAuras.clones[id]) do
            if type(cloneRegion) == "table" then pcall(styleWAIcon, cloneRegion) end
        end
    end
end

-- Scan all currently-existing icon regions (lazy: only auras that exist now)
local function skinAllWAIcons()
    if not mod._enabled or not mod.db or not mod.db.skinWeakAuras then return end
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local saved = _G.WeakAurasSaved
    if not (saved and saved.displays) then return end
    for id, data in pairs(saved.displays) do
        if type(data) == "table" and data.regionType == "icon" then
            skinWAById(id)
        end
    end
end

-- Hook WeakAuras.Add so future / edited / re-loaded icon auras get skinned too.
-- (Private is not reachable externally; Add is the public per-aura entry point.)
local waHooked = false
local function hookWeakAuras()
    if waHooked or not WeakAuras then return end
    waHooked = true

    -- Primary, most reliable catch: WeakAuras calls regionTypes.icon.modify() for
    -- EVERY icon region it builds — including dynamic-group CLONES (one aura that
    -- shows multiple instances), which GetRegion(id) never returns. That gap was
    -- why some auras had no rim.
    if WeakAuras.regionTypes and WeakAuras.regionTypes.icon
       and type(WeakAuras.regionTypes.icon.modify) == "function" then
        hooksecurefunc(WeakAuras.regionTypes.icon, "modify", function(_, region)
            if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() pcall(styleWAIcon, region) end)  -- after sizing
            else
                pcall(styleWAIcon, region)
            end
        end)
    end

    -- Fallback for the base region on definition / edit / reload.
    if WeakAuras.Add then
        hooksecurefunc(WeakAuras, "Add", function(data)
            if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
            if type(data) ~= "table" or data.regionType ~= "icon" or not data.id then return end
            local id = data.id
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function() skinWAById(id) end)  -- let the region build
            else
                skinWAById(id)
            end
        end)
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
local hookInstalled = false

local function skinEverything()
    skinAll()
    skinAllWAIcons()
end

function mod:OnEnable()
    if not mod.db then return end

    -- Skin everything ourselves. Deferred so all frames exist.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, skinEverything)
        C_Timer.After(2.0, skinEverything)
        C_Timer.After(5.0, skinAllWAIcons)   -- WeakAuras icons often load late
    else
        skinEverything()
    end

    -- Catch future / edited / lazily-built WeakAuras icons
    hookWeakAuras()

    -- Blizzard rebuilds NormalTexture on button updates — re-hide it after.
    if not hookInstalled then
        hookInstalled = true
        if _G.ActionButton_Update then
            hooksecurefunc("ActionButton_Update", function(button)
                if mod._enabled and button and button._vcuiSkinned then
                    hideNormalTexture(button)
                end
            end)
        end
    end

    -- Re-skin when bars / auras show or refresh
    ns:RegisterEvent("PLAYER_ENTERING_WORLD",     skinEverything)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS",   skinAll)
    ns:RegisterEvent("PET_BAR_UPDATE",            skinAll)
    ns:RegisterEvent("PLAYER_REGEN_DISABLED",     skinAllWAIcons)  -- procs appearing in combat
    ns:RegisterEvent("PLAYER_REGEN_ENABLED",      skinAllWAIcons)
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD",   skinEverything)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", skinAll)
    ns:UnregisterEvent("PET_BAR_UPDATE",          skinAll)
    ns:UnregisterEvent("PLAYER_REGEN_DISABLED",   skinAllWAIcons)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED",    skinAllWAIcons)
    -- Note: existing skins stay until /reload (we don't tear down the borders
    -- to avoid touching buttons in combat). A /reload fully removes them.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local STYLE_VALUES = {
        { value = "shadow",  text = L["Shadow (dark rounded rim)"] },
        { value = "rounded", text = L["Rounded icon (masked corners)"] },
        { value = "square",  text = L["Square (black edge)"] },
        { value = "accent",  text = L["Square (accent edge)"] },
        { value = "circle",  text = L["Circle"] },
        { value = "minimal", text = L["Minimal (icon only)"] },
    }

    return {
        { type = "header", text = L["Button Skin"] },
        { type = "desc", text = L["|cffaaaaaaBuilt-in dark drop-shadow skin. Action bars and WeakAuras icons are configured separately below.|r"] },

        -- ---- Action bars ----
        { type = "header", text = L["Action Bars"] },
        { type = "toggle", label = L["Skin the action bars"],
          get = function() return mod.db.skinBars end,
          set = function(_, v) mod.db.skinBars = v; skinAll(); refreshAll() end },
        { type = "dropdown", label = L["Bar style"],
          tooltip = L["Pick how the action buttons look. Rounded/Circle use an icon mask; Minimal is just the cropped icon."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.style or "shadow" end,
          set = function(_, v) mod.db.style = v; refreshAll() end },
        { type = "toggle", label = L["Also skin pet & stance buttons"],
          get = function() return mod.db.skinPetStance end,
          set = function(_, v) mod.db.skinPetStance = v; skinAll() end },

        { type = "spacer", height = 8 },

        -- ---- WeakAuras ----
        { type = "header", text = L["WeakAuras Icons"] },
        { type = "toggle", label = L["Skin WeakAuras icons"],
          get = function() return mod.db.skinWeakAuras end,
          set = function(_, v) mod.db.skinWeakAuras = v; skinAllWAIcons() end },
        { type = "dropdown", label = L["WeakAuras style"],
          tooltip = L["Style for WeakAuras icons, independent of the action bars."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.waStyle or "shadow" end,
          set = function(_, v) mod.db.waStyle = v; skinAllWAIcons() end },
        { type = "toggle", label = L["Hide WeakAuras' own border"],
          tooltip = L["Hides the light border WeakAuras draws on icons, so only our dark rim shows. /reload to fully restore it."],
          get = function() return mod.db.hideWABorder end,
          set = function(_, v) mod.db.hideWABorder = v; skinAllWAIcons() end },

        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaNote: turning a skin off fully reverts after a /reload.|r"] },
    }
end
