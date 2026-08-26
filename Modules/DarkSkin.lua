-- Dark button skin plus an opt-in re-tint of Blizzard's default UI artwork.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("darkskin", {
    -- Strict grid: lone last rows of a run stretched across the page (user
    -- report, 31.07.2026). On the grid a lone row keeps its half.
    optionsGrid = true,
    name        = "Dark Skin",
    group       = "UI Reskin",
    description = "The dark look of the UI in one place: a built-in dark skin for action buttons and WeakAuras icons, plus an optional Dark Mode that darkens Blizzard's default frames, minimap and bars.",
    defaults = {
        enabled       = true,
        style         = "standard",  -- standard | minimaldark | circle | csquare | hexagon
        waStyle       = "set1",  -- one of the five aura layer sets (WA_SETS)
        skinPetStance = true,
        skinBars      = true,
        skinWeakAuras = true,
        hideWABorder  = true,
        darkMode        = false,
        dmDesaturate    = true,
        dmColor         = { r = 0.40, g = 0.40, b = 0.40 },
        dmUnitframes    = true,
        dmMinimap       = true,
        dmActionbars    = true,
        dmActionButtons = false,
        dmBags          = false,
        -- Off: the gryphons are what Blizzard's bar looks like, and taking them
        -- away unasked would change every profile that never opted in.
        hideGryphons    = false,
    },
})

local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton", "BonusActionButton",
    "VuloActionButton", "VuloAB_bottomleftB", "VuloAB_bottomrightB",
    "VuloAB_rightB", "VuloAB_leftB", "VuloAB_extraB", "VuloAB_stanceB",
}
local EXTRA_PREFIXES = { "PetActionButton", "StanceButton" }

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- File paths load more reliably than fileIDs in Classic.
local MASK_SQUARE  = "Interface\\Buttons\\WHITE8X8"
local TEX_BACKDROP = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\Backdrop.tga"
local TEX_BORDER   = "Interface\\AddOns\\VuloClassicUI\\Media\\Masks\\Normal.tga"

-- The rim comes from insetting the icon's MASK by a fraction of icon size, so it
-- scales with the icon; RIM_OUTSET is a fixed bleed for the soft shadow.
local RIM_OUTSET  = 3

local function attachShadow(frame, store, outset)
    if not frame then return end
    store = store or frame
    outset = outset or RIM_OUTSET

    if not store._vcuiBack then
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        back:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        back:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        back:SetTexture(TEX_BACKDROP)
        back:SetVertexColor(0.03, 0.03, 0.04, 1)
        store._vcuiBack = back

        local ring = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        ring:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -outset,  outset)
        ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  outset, -outset)
        ring:SetTexture(TEX_BORDER)
        ring:SetVertexColor(0, 0, 0, 1)
        store._vcuiRing = ring
    end
end

-- "standard" is the ships-with default -- Blizzard's button exactly as it
-- comes, the appliers only put back what another style set in the same
-- session. "minimaldark" carries the display name Shadow. The three masked
-- shapes cut the icon with their mask and lay their own rim art over it
-- (Media\Buttons, one _mask/_border pair per shape); migration [5] maps every
-- retired style onto its nearest survivor. The bg/border/shadow flags and the
-- machinery behind them stay as infrastructure; no current style sets them.
local BTN_DIR = "Interface\\AddOns\\VuloClassicUI\\Media\\Buttons\\"
local STYLES = {
    standard = { border = nil,    bg = false, mask = nil, shadow = false, standard = true },
    minimaldark = { border = nil, bg = false, mask = nil, shadow = false, darkenNormal = true },
    circle  = { bg = false, shadow = false,
                mask = BTN_DIR .. "circle_mask.tga",  borderTex = BTN_DIR .. "circle_border.tga" },
    csquare = { bg = false, shadow = false,
                mask = BTN_DIR .. "csquare_mask.tga", borderTex = BTN_DIR .. "csquare_border.tga" },
    hexagon = { bg = false, shadow = false,
                mask = BTN_DIR .. "hexagon_mask.tga", borderTex = BTN_DIR .. "hexagon_border.tga" },
}

local DARK_TINT = 0.12

-- Gates the NormalTexture re-hide hooks; flipped by setBarsSkinned().
local barsSkinned = false

local function currentStyle()
    local key = mod.db and mod.db.style
    return STYLES[key] or STYLES.standard
end

-- Measured: painting the WeakAuras icons cost a 28 ms hitch on EVERY combat
-- edge, because the sweep walked every aura ever saved -- most of them not even
-- on screen -- and re-applied a look that had not changed.
--
-- A region now remembers what it was last painted with. This is a FINGERPRINT
-- of the settings, not a counter that someone has to remember to bump: a
-- profile switch rewrites the settings without going through any of our option
-- setters, and a counter silently missed that -- every icon kept the old
-- profile's look until /reload.
local function waSignature()
    local db = mod.db
    if not db then return "?" end
    local t = db.waBorderTint
    local tint = t and string.format("|%.3f/%.3f/%.3f", t.r or 1, t.g or 1, t.b or 1) or ""
    return (db.waStyle or "set1") .. (db.hideWABorder and "|B" or "|b") .. tint
end

local function getRegion(button, suffix, fallback)
    local name = button:GetName()
    return (name and _G[name .. suffix]) or fallback
end

-- Hide(), not only texture-nil plus alpha 0. Emptying and fading is undone by
-- anyone who later writes a texture and an alpha back onto the region, and the
-- stance bar does exactly that: its updates poke the TEXTURE OBJECT
-- (StanceButton1NormalTexture:SetTexture) instead of the button method, so the
-- SetNormalTexture hook that guards the action bars never fires and Blizzard's
-- rim came back for good (user report with a region dump, 08.08.2026: texture
-- 130841, alpha 1, shown, on a button we had already skinned).
--
-- A hidden region draws nothing whatever is written into it afterwards, so this
-- beats every writer instead of intercepting one of them.
local function hideNormalTexture(button)
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        nt:SetTexture(nil)
        nt:SetAlpha(0)
        if nt.Hide then nt:Hide() end
    end
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(0) end
    button._vcuiNTDirty = true
end

local function applyNormalTexture(button)
    local st = currentStyle()
    if not (st.darkenNormal or st.standard) then
        hideNormalTexture(button)
        return
    end
    -- Standard means hands off: a pristine Blizzard button is never written to
    -- (the client owns rim states like the out-of-mana tint and the grid
    -- half-alpha, and Dark Mode may own the tint) -- only a region a previous
    -- style demonstrably altered gets put back, once.
    if st.standard and not button._vcuiNTDirty then return end
    button._vcuiNTDirty = not st.standard or nil
    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        if st.standard then
            -- Restore only when a previous style emptied the region: on the
            -- SetNormalTexture hook path Blizzard just wrote the CURRENT
            -- texture (stance/page swaps), and the capture must not undo it.
            if button._vcuiNTOrig and nt.GetTexture and not nt:GetTexture() then
                nt:SetTexture(button._vcuiNTOrig)
            end
        elseif button._vcuiNTOrig then
            nt:SetTexture(button._vcuiNTOrig)
        end
        nt:SetAlpha(1)
        -- The mirror of the Hide() above: these styles WANT Blizzard's rim, so
        -- a region hidden by an earlier style has to come back.
        if nt.Show then nt:Show() end
        if nt.SetDesaturated then nt:SetDesaturated(not st.standard) end
        if st.standard then
            nt:SetVertexColor(1, 1, 1, 1)
        else
            local c = mod.db and mod.db.barBorderTint
            if c then
                nt:SetVertexColor(c.r or DARK_TINT, c.g or DARK_TINT, c.b or DARK_TINT, 1)
            else
                nt:SetVertexColor(DARK_TINT, DARK_TINT, DARK_TINT, 1)
            end
        end
    end
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(st.standard and 1 or 0) end
end

-- This client has no reliable global ActionButton_Update, so hook each button's setter.
local function lockNormalTexture(button)
    if button._vcuiNTHook or not button.SetNormalTexture then return end
    button._vcuiNTHook = true
    hooksecurefunc(button, "SetNormalTexture", function(self)
        if mod._enabled and barsSkinned and self._vcuiSkinned then
            applyNormalTexture(self)
        end
    end)
end

local function ensureMask(button)
    if not button._vcuiMask and button.CreateMaskTexture then
        button._vcuiMask = button:CreateMaskTexture()
    end
    return button._vcuiMask
end

-- `pct` insets the mask by that fraction of icon size, revealing the backdrop as a rim.
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

-- The client's auto-attack blink (the Flash region) is BROKEN on this client
-- in every style, not just the skinned ones: the Classic flavor's template
-- gives it the retail atlas at atlas size with a single TOPLEFT anchor
-- (measured in the classic_anniversary source, ActionButtonTemplate.xml), so
-- the retail-sized frame art hangs past the classic button to the right and
-- bottom (user screenshots 22.08. and 26.08.2026). Every style therefore
-- seats the flash on the icon, crops it like the icon and cuts it with the
-- icon's mask where one is active; only unstyle (skin off) hands the client
-- layout back from the one-time capture.
local FLASH_TEX = "Interface\\Buttons\\UI-QuickslotRed"

local function restoreFlash(button, flash)
    local o = button._vcuiFlashOrig
    if not o then return end
    button._vcuiFlashDirty = nil
    flash:SetTexCoord(0, 1, 0, 1)
    if flash.SetBlendMode and o.blend then flash:SetBlendMode(o.blend) end
    if o.atlas then
        flash:SetAtlas(o.atlas, true)
    else
        flash:SetTexture(o.tex)
        flash:SetSize(o.w or 0, o.h or 0)
    end
    flash:ClearAllPoints()
    for _, p in ipairs(o.points) do
        flash:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
    if button._vcuiFlashMasked and button._vcuiMask then
        pcall(flash.RemoveMaskTexture, flash, button._vcuiMask)
        button._vcuiFlashMasked = false
    end
end

local function applyFlash(button, icon)
    local flash = getRegion(button, "Flash", button.Flash)
    if not flash then return end
    local st = currentStyle()
    if not icon then
        if button._vcuiFlashDirty then restoreFlash(button, flash) end
        return
    end
    if not button._vcuiFlashOrig then
        local o = { points = {} }
        o.atlas = flash.GetAtlas and flash:GetAtlas() or nil
        if not o.atlas then
            o.tex = flash.GetTexture and flash:GetTexture() or nil
            o.w, o.h = flash:GetSize()
        end
        o.blend = flash.GetBlendMode and flash:GetBlendMode() or nil
        for i = 1, flash:GetNumPoints() do o.points[i] = { flash:GetPoint(i) } end
        button._vcuiFlashOrig = o
    end
    button._vcuiFlashDirty = true
    flash:SetTexture(FLASH_TEX)
    -- same crop as the icon: standard leaves the icon uncropped
    if st.standard then
        flash:SetTexCoord(0, 1, 0, 1)
    else
        flash:SetTexCoord(unpack(ICON_CROP))
    end
    if flash.SetBlendMode then flash:SetBlendMode("BLEND") end
    flash:ClearAllPoints()
    flash:SetAllPoints(icon)
    -- useAtlasSize leaves an explicit size behind that would beat the anchors
    flash:SetWidth(0); flash:SetHeight(0)
    local m = button._vcuiMask
    if m and button._vcuiMaskOn then
        if not button._vcuiFlashMasked and flash.AddMaskTexture then
            pcall(flash.AddMaskTexture, flash, m)
            button._vcuiFlashMasked = true
        end
    elseif button._vcuiFlashMasked and m then
        pcall(flash.RemoveMaskTexture, flash, m)
        button._vcuiFlashMasked = false
    end
end

local function applyStyle(button)
    local st   = currentStyle()
    local icon = getRegion(button, "Icon", button.icon or button.Icon)

    if icon and icon.SetTexCoord then
        if st.standard then
            icon:SetTexCoord(0, 1, 0, 1)
        else
            icon:SetTexCoord(unpack(ICON_CROP))
        end
    end

    if button._vcuiBg then
        button._vcuiBg:SetShown((st.bg and not st.shadow) and true or false)
    end

    local showShadow = st.shadow and true or false
    if button._vcuiBack then button._vcuiBack:SetShown(showShadow) end
    if button._vcuiRing then button._vcuiRing:SetShown(showShadow) end

    if icon then
        local maskTex = st.mask or (st.shadow and MASK_SQUARE) or nil
        local size = tonumber(mod.db.barIconSize) or 90
        local pct  = st.shadow and ((100 - size) / 200) or 0
        setMasked(button, icon, maskTex ~= nil, maskTex, pct)
    end

    applyFlash(button, icon)

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

    -- The shaped styles bring their own rim art, laid over the masked icon.
    if st.borderTex then
        if not button._vcuiShape then
            local t = button:CreateTexture(nil, "OVERLAY", nil, 1)
            t:SetAllPoints(button)
            button._vcuiShape = t
        end
        button._vcuiShape:SetTexture(st.borderTex)
        local c = mod.db and mod.db.barBorderTint
        if c then
            button._vcuiShape:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, 1)
        else
            button._vcuiShape:SetVertexColor(1, 1, 1, 1)
        end
        button._vcuiShape:Show()
    elseif button._vcuiShape then
        button._vcuiShape:Hide()
    end

    applyNormalTexture(button)
end

local function skinButton(button)
    if not button then return end
    if not button._vcuiSkinned then
        button._vcuiSkinned = true

        local nt0 = button.GetNormalTexture and button:GetNormalTexture()
        if nt0 and nt0.GetTexture then button._vcuiNTOrig = nt0:GetTexture() end

        attachShadow(button, button)
        lockNormalTexture(button)

        local bg = button:CreateTexture(nil, "BACKGROUND", nil, -2)
        bg:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.04, 0.04, 0.05, 0.9)
        button._vcuiBg = bg

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

    applyStyle(button)
end

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

local function refreshAll()
    if not mod._enabled or not mod.db then return end
    forEachButton(function(b)
        if b._vcuiSkinned then
            applyStyle(b)
        end
    end)
end

-- Touches only textures/regions, never secure attributes, so it is combat-safe.
local function unstyleButton(button)
    if not button or not button._vcuiSkinned then return end
    if button._vcuiBg     then button._vcuiBg:Hide()     end
    if button._vcuiBack   then button._vcuiBack:Hide()   end
    if button._vcuiRing   then button._vcuiRing:Hide()   end
    if button._vcuiBorder then button._vcuiBorder:Hide() end
    if button._vcuiShape  then button._vcuiShape:Hide()  end

    local icon = getRegion(button, "Icon", button.icon or button.Icon)
    if icon then
        setMasked(button, icon, false)
        if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
    end

    local flash = getRegion(button, "Flash", button.Flash)
    if flash and button._vcuiFlashDirty then restoreFlash(button, flash) end

    local nt = (button.GetNormalTexture and button:GetNormalTexture())
            or getRegion(button, "NormalTexture", button.NormalTexture)
    if nt then
        if button._vcuiNTOrig then nt:SetTexture(button._vcuiNTOrig) end
        nt:SetAlpha(1)
        -- Undoing the skin has to undo the Hide() too, or a button handed back to
        -- the client keeps an invisible rim for the rest of the session.
        if nt.Show then nt:Show() end
        if nt.SetDesaturated then nt:SetDesaturated(false) end
        nt:SetVertexColor(1, 1, 1)
    end
    local slot = getRegion(button, "SlotBackground", button.SlotBackground)
    if slot then slot:SetAlpha(1) end
    button._vcuiNTDirty = nil
end

local function setBarsSkinned(on)
    barsSkinned = on and true or false
    if on then
        if mod._enabled then forEachButton(skinButton) end
    else
        forEachButton(unstyleButton)
    end
end

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

-- ===== Aura layer sets ====================================================
-- The aura look is a three-layer texture set: a backdrop under the icon, a
-- rim (normal) and a border over it. Scales are the source art's layer size
-- over its icon size; color and blend follow the layer spec. The state
-- layers of a clickable button (pushed, checked, hotkey) have no meaning on
-- a passive aura, and the gloss shine stays out on purpose -- the source
-- framework draws it at user-set alpha with a DEFAULT OF ZERO, so the look
-- everyone knows is the one without it (drawn at full alpha it whitewashes
-- every icon; measured in game, 11.08.2026).
local WA_DIR = "Interface\\AddOns\\VuloClassicUI\\Media\\AuraSkins\\"
local WA_SETS = {
    set1 = { dir = "1",
        back   = { scale = 1.3125, color = {0.3, 0.3, 0.3, 1} },
        normal = { scale = 1.3125, color = {0, 0, 0, 1} },
        border = { scale = 1.3125 },
    },
    set2 = { dir = "2",
        back   = { scale = 1 },
        normal = { scale = 1.25 },
        border = { scale = 1.25, add = true },
    },
    set3 = { dir = "3",
        back   = { scale = 1.3125, color = {0.3, 0.3, 0.3, 1} },
        normal = { scale = 1.3125, color = {0, 0, 0, 1} },
        border = { scale = 1.3125 },
    },
    set4 = { dir = "4",
        back   = { scale = 1, color = {0.3, 0.3, 0.3, 1} },
        normal = { scale = 1, color = {0, 0, 0, 1} },
        border = { scale = 1 },
    },
    set5 = { dir = "5",
        back   = { scale = 1.54 },
        normal = { scale = 1.54, color = {0, 0, 0, 1} },
        border = { scale = 1.62, add = true },
    },
}

local function currentWASet()
    local key = mod.db and mod.db.waStyle
    return WA_SETS[key] or WA_SETS.set1
end

local WA_LAYERS = {
    { key = "_vcuiWaBack",   file = "Backdrop.tga", spec = "back",   layer = "BACKGROUND", sub = -5 },
    { key = "_vcuiWaNormal", file = "Normal.tga",   spec = "normal", layer = "OVERLAY",    sub = 1 },
    { key = "_vcuiWaBorder", file = "Border.tga",   spec = "border", layer = "OVERLAY",    sub = 2 },
}

-- Lays the three set layers around the icon; parent owns the textures, region
-- carries the refs (the same parent/store convention as attachShadow).
local function placeWALayers(region, parent, icon, set, w)
    for _, Ld in ipairs(WA_LAYERS) do
        local spec = set[Ld.spec]
        local t = region[Ld.key]
        if spec then
            if not t then
                t = parent:CreateTexture(nil, Ld.layer, nil, Ld.sub)
                region[Ld.key] = t
            end
            local out = w * (spec.scale - 1) / 2
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -out,  out)
            t:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  out, -out)
            t:SetTexture(WA_DIR .. set.dir .. "\\" .. Ld.file)
            t:SetBlendMode(spec.add and "ADD" or "BLEND")
            local c = spec.color
            -- The user's border tint outranks the set's own border spec;
            -- the other layers keep the set look.
            if Ld.spec == "border" then
                local o = mod.db and mod.db.waBorderTint
                if o then c = { o.r or 1, o.g or 1, o.b or 1, 1 } end
            end
            if c then
                t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
            else
                t:SetVertexColor(1, 1, 1, 1)
            end
            t:Show()
        elseif t then
            t:Hide()
        end
    end
end

local function styleWAIcon(region)
    if not region or region.regionType ~= "icon" then return end
    local icon = region.icon
    if not icon then return end
    local w = icon:GetWidth() or 0
    if w < 1 then w = (region.GetWidth and region:GetWidth()) or 32 end

    -- Hiding WeakAuras' own border must happen on EVERY pass, never memoised:
    -- WeakAuras releases and re-creates all of a region's sub-parts on any edit,
    -- and hands out recycled region tables when an aura gains a stack -- both
    -- give us a fresh, VISIBLE border on a table that still carries our stamp.
    -- It is a handful of table entries, so it is cheap enough to always do.
    if mod.db and mod.db.hideWABorder and region.subRegions then
        for _, sub in ipairs(region.subRegions) do
            if type(sub) == "table" and sub.SetBorderColor and sub.Hide then
                sub:Hide()
            end
        end
    end

    -- The rest is geometry and masks: idempotent for the same settings and the
    -- same size, so it is the part worth skipping. Width is in the test because
    -- every offset is derived from it -- resize an aura and the rim must follow.
    local sig = waSignature()
    if region._vcuiWASig == sig and region._vcuiWAWidth == w then return end
    region._vcuiWASig, region._vcuiWAWidth = sig, w

    placeWALayers(region, region, icon, currentWASet(), w)

    -- Leftovers from the older per-style painting of the same session.
    if region._vcuiBack  then region._vcuiBack:Hide()  end
    if region._vcuiRing  then region._vcuiRing:Hide()  end
    if region._vcuiShape then region._vcuiShape:Hide() end
    setMasked(region, icon, false)

    local function fixCD(cd)
        insetCooldown(region, icon, 0)
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

end

local function styleWAAuraBarIcon(region)
    local icon  = region and region.icon
    local frame = region and region.iconFrame
    if not (icon and frame) then return end

    local w = (icon.GetWidth and icon:GetWidth()) or 0
    if w < 1 then w = (frame.GetWidth and frame:GetWidth()) or 20 end

    -- Same reasoning as the icon variant: settings fingerprint plus size. The
    -- aurabar painter never touched WeakAuras' own border, so there is nothing
    -- to pull out in front of the check here.
    local sig = waSignature()
    if region._vcuiWASig == sig and region._vcuiWAWidth == w then return end
    region._vcuiWASig, region._vcuiWAWidth = sig, w

    placeWALayers(region, frame, icon, currentWASet(), w)

    -- Leftovers from the older per-style painting of the same session.
    if region._vcuiBack  then region._vcuiBack:Hide()  end
    if region._vcuiRing  then region._vcuiRing:Hide()  end
    if region._vcuiShape then region._vcuiShape:Hide() end
    setMasked(frame, icon, false)
end

local function skinWARegion(region)
    if type(region) ~= "table" then return end
    local rt = region.regionType
    if rt == "icon" then
        styleWAIcon(region)
    elseif rt == "aurabar" then
        styleWAAuraBarIcon(region)
    end
end

local function skinWAById(id)
    if not (WeakAuras and WeakAuras.GetRegion) then return end
    local ok, region = pcall(WeakAuras.GetRegion, id)
    if ok then skinWARegion(region) end
end

local function skinFrameTree(frame, depth)
    if not frame or depth > 10 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local rt = frame.regionType
    if rt == "icon" or rt == "aurabar" then pcall(skinWARegion, frame) end
    if not frame.GetChildren then return end
    local packed = { pcall(frame.GetChildren, frame) }
    if packed[1] then
        for i = 2, #packed do skinFrameTree(packed[i], depth + 1) end
    end
end

local function skinAllWAIcons()
    if not mod._enabled or not mod.db or not mod.db.skinWeakAuras then return end
    if WeakAuras and WeakAuras.GetRegion then
        local saved = _G.WeakAurasSaved
        if saved and saved.displays then
            for id, data in pairs(saved.displays) do
                if type(data) == "table"
                   and (data.regionType == "icon" or data.regionType == "aurabar") then
                    skinWAById(id)
                end
            end
        end
    end
    skinFrameTree(UIParent, 0)
end

local function onNamePlateAdded(_, unit)
    if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    if not (unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate then skinFrameTree(plate, 0) end
        end)
    end
end
local function onTargetChangedWA()
    if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function() skinFrameTree(_G.TargetFrame, 0) end)
    end
end

local _waSoonPending = false
local function skinWAFrameOnly()
    if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    skinFrameTree(_G.WeakAurasFrame, 0)
end
local function skinWASoon()
    if _waSoonPending or not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
    if not (C_Timer and C_Timer.After) then return end
    _waSoonPending = true
    C_Timer.After(0.25, function()
        _waSoonPending = false
        skinWAFrameOnly()
    end)
end

local waHooked = false
local function hookWeakAuras()
    if waHooked or not (WeakAuras and WeakAuras.Add) then return end
    waHooked = true
    hooksecurefunc(WeakAuras, "Add", function(data)
        if not (mod._enabled and mod.db and mod.db.skinWeakAuras) then return end
        if type(data) ~= "table" or data.regionType ~= "icon" or not data.id then return end
        local id = data.id
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() skinWAById(id) end)
        else
            skinWAById(id)
        end
    end)
end

local function skinEverything()
    skinAll()
    skinAllWAIcons()
end

local _skinAllPending, _skinEvtPending
local function skinAllSoon()
    if not (C_Timer and C_Timer.After) then return skinAll() end
    if _skinAllPending then return end
    _skinAllPending = true
    C_Timer.After(0.1, function() _skinAllPending = false; if mod._enabled then skinAll() end end)
end

-- Entry point for other modules to re-skin freshly created action buttons.
ns.ReskinActionButtons = skinAllSoon
local function skinEverythingSoon()
    if not (C_Timer and C_Timer.After) then return skinEverything() end
    if _skinEvtPending then return end
    _skinEvtPending = true
    C_Timer.After(0.2, function() _skinEvtPending = false; if mod._enabled then skinEverything() end end)
end

-- Cannot gate on mod._enabled: the core sets it true only AFTER OnEnable returns.
local active = false

local function dmColorRGB()
    local c = mod.db and mod.db.dmColor
    if not c then return 0.4, 0.4, 0.4 end
    return c.r or 0.4, c.g or 0.4, c.b or 0.4
end

local function paint(tex, on)
    if not tex or not tex.SetVertexColor then return end
    if on then
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, mod.db.dmDesaturate and true or false) end
        tex:SetVertexColor(dmColorRGB())
    else
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, false) end
        tex:SetVertexColor(1, 1, 1)
    end
end

local function paintGlobals(names, on)
    for _, n in ipairs(names) do paint(_G[n], on) end
end

local function paintNormal(btnName, on)
    local b = _G[btnName]
    if not b or not b.GetNormalTexture then return end
    paint(b:GetNormalTexture(), on)
end

local UNIT_BORDERS = {
    "PlayerFrameTexture",
    "TargetFrameTextureFrameTexture",
    "FocusFrameTextureFrameTexture",
    "PetFrameTexture",
    "PartyMemberFrame1Texture", "PartyMemberFrame2Texture",
    "PartyMemberFrame3Texture", "PartyMemberFrame4Texture",
    "TargetFrameToTTextureFrameTexture",
    "FocusFrameToTTextureFrameTexture",
}
local MINIMAP_REGIONS = {
    "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag",
    "MiniMapTrackingButtonBorder", "MiniMapTrackingBorder",
    "MiniMapMailBorder", "MiniMapBattlefieldBorder",
    "MiniMapWorldBorder", "MiniMapLFGBorder",
}
local MINIMAP_BUTTONS = { "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton" }
local ACTIONBAR_ART = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarTextureExtender",
}
local ACTION_BUTTON_BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton",
}
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "KeyRingButton",
}

-- The button skin hides or repaints the same NormalTexture, so the tint must
-- stand down -- except under "standard", which by contract leaves Blizzard's
-- rim alone and hands it to whoever wants it, Dark Mode included.
local function buttonSkinOwnsBars()
    return (mod.db.skinBars and barsSkinned and not currentStyle().standard) and true or false
end

local function applyUnitframes(on) paintGlobals(UNIT_BORDERS, on) end
local function applyMinimap(on)
    paintGlobals(MINIMAP_REGIONS, on)
    for _, n in ipairs(MINIMAP_BUTTONS) do paintNormal(n, on) end
end
local function applyActionbars(on) paintGlobals(ACTIONBAR_ART, on) end

-- The two beasts at the ends of the main bar. Their own switch (user request,
-- 02.08.2026), independent of Dark Mode: dark-tinted gryphons are still
-- gryphons, and wanting the bar to end cleanly is a different wish from wanting
-- the artwork darker.
--
-- Textures, not frames -- hiding one is unprotected, so this needs no combat
-- guard and can run from an option setter at any time. The alpha is left alone:
-- Dark Mode paints these same regions, and two owners of one alpha value is how
-- a setting ends up depending on the order the two were last applied.
local GRYPHONS = { "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap" }
local function applyGryphons(hide)
    for _, n in ipairs(GRYPHONS) do
        local t = _G[n]
        if t then
            if hide then t:Hide() else t:Show() end
        end
    end
end
local function applyActionButtons(on)
    if on and buttonSkinOwnsBars() then return end
    for _, bar in ipairs(ACTION_BUTTON_BARS) do
        for i = 1, 12 do paintNormal(bar .. i, on) end
    end
end
local function applyBags(on)
    for _, n in ipairs(BAG_BUTTONS) do paintNormal(n, on) end
end

local function isDMOn(area)
    return (active and mod.db.darkMode and mod.db[area]) and true or false
end

local function applyAllDM()
    -- Not gated on darkMode, unlike everything below it: this one is its own
    -- switch and has to answer even with Dark Mode off. It rides along here
    -- because this is the pass that runs whenever the artwork is re-applied.
    applyGryphons(active and mod.db.hideGryphons and true or false)
    applyUnitframes(isDMOn("dmUnitframes"))
    applyMinimap(isDMOn("dmMinimap"))
    applyActionbars(isDMOn("dmActionbars"))
    applyActionButtons(isDMOn("dmActionButtons"))
    applyBags(isDMOn("dmBags"))
end

local function restoreAllDM()
    applyGryphons(false)      -- the module going away must hand them back
    applyUnitframes(false)
    applyMinimap(false)
    applyActionbars(false)
    applyActionButtons(false)
    applyBags(false)
end

-- Blizzard resets these textures on redraw, so the tint has to be re-applied.
local dmHooked = false
local function installDMHooks()
    if dmHooked then return end
    dmHooked = true

    if _G.TargetFrame_CheckClassification then
        hooksecurefunc("TargetFrame_CheckClassification", function(self)
            if not isDMOn("dmUnitframes") then return end
            local n = self and self.GetName and self:GetName()
            if n then paint(_G[n .. "TextureFrameTexture"], true) end
        end)
    end

    if _G.ActionButton_Update then
        hooksecurefunc("ActionButton_Update", function(btn)
            if not isDMOn("dmActionButtons") or buttonSkinOwnsBars() then return end
            if btn and btn.GetNormalTexture then paint(btn:GetNormalTexture(), true) end
        end)
    end
end

local hookInstalled = false

-- Named handlers registered through the module: they used to be anonymous and
-- latched, so they stayed live for the session once the dark mode had been on
-- even once, and only the isDMOn check kept them from painting.
local PARTY_TEXTURES = { "PartyMemberFrame1Texture", "PartyMemberFrame2Texture",
                         "PartyMemberFrame3Texture", "PartyMemberFrame4Texture" }

local function onFocusChangedDM()
    if isDMOn("dmUnitframes") then paint(_G.FocusFrameTextureFrameTexture, true) end
end
local function onUnitPetDM()
    if isDMOn("dmUnitframes") then paint(_G.PetFrameTexture, true) end
end
local function onRosterUpdateDM()
    if isDMOn("dmUnitframes") then paintGlobals(PARTY_TEXTURES, true) end
end

local function wireDMEvents()
    mod:RegisterEvent("PLAYER_FOCUS_CHANGED", onFocusChangedDM)
    mod:RegisterEvent("UNIT_PET",             onUnitPetDM)
    mod:RegisterEvent("GROUP_ROSTER_UPDATE",  onRosterUpdateDM)
end

local function onWorldEnter()
    skinEverythingSoon()
    -- Unconditional since the gryphon switch joined this pass: gated on darkMode
    -- it would hide them at login and hand them back at the first zone change.
    -- Harmless with Dark Mode off -- every other call in there then re-applies
    -- "not tinted", which is what the artwork already is.
    applyAllDM()
end
local function onTargetChanged()
    onTargetChangedWA()
    if isDMOn("dmUnitframes") then paint(_G.TargetFrameTextureFrameTexture, true) end
end

function mod:OnEnable()
    if not mod.db then return end
    active = true
    barsSkinned = mod.db.skinBars and true or false

    -- Deferred so all frames exist; the late pass catches slow-loading aura icons.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, skinEverything)
        C_Timer.After(2.0, skinEverything)
        C_Timer.After(5.0, skinAllWAIcons)
    else
        skinEverything()
    end

    hookWeakAuras()
    installDMHooks()
    wireDMEvents()

    -- Blizzard rebuilds NormalTexture on button updates, so re-hide it after.
    if not hookInstalled then
        hookInstalled = true
        if _G.ActionButton_Update then
            hooksecurefunc("ActionButton_Update", function(button)
                if mod._enabled and barsSkinned and button and button._vcuiSkinned then
                    applyNormalTexture(button)
                end
            end)
        end
    end

    -- Through the module, not ns: directly -- that is what puts the time on
    -- "darkskin" in the measurement instead of on a bare event name. These were
    -- the entries that showed up anonymous, and the 28 ms hitch hid in them.
    -- It also hands the teardown to the framework.
    mod:RegisterEvent("PLAYER_ENTERING_WORLD",     onWorldEnter)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORMS",   skinAllSoon)
    -- FORMS (plural) only fires when the set of forms itself changes, which for a
    -- paladin means learning an aura. Switching between them, and every usable or
    -- cooldown update, goes through these three -- and each of them is a moment
    -- the client rewrites the button art underneath us.
    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORM",     skinAllSoon)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_USABLE",   skinAllSoon)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN", skinAllSoon)
    mod:RegisterEvent("PET_BAR_UPDATE",            skinAllSoon)
    mod:RegisterEvent("PLAYER_REGEN_DISABLED",     skinAllWAIcons)
    mod:RegisterEvent("PLAYER_REGEN_ENABLED",      skinAllWAIcons)
    mod:RegisterEvent("PLAYER_TARGET_CHANGED",     onTargetChanged)
    mod:RegisterEvent("NAME_PLATE_UNIT_ADDED",     onNamePlateAdded)
    -- registration follows the option: UNIT_AURA fires for every unit
    -- everywhere, and with the skin off the handler would only ever bail
    if mod.db.skinWeakAuras then
        mod:RegisterEvent("UNIT_AURA", skinWASoon)
    end

    applyAllDM()
end

function mod:OnDisable()
    active = false
    -- The events registered through the module are taken back out by the
    -- framework right after this returns; the three dark-mode ones go the same
    -- way. Nothing left to mirror by hand here.
    restoreAllDM()
    -- Button skins and hooks stay until /reload; tearing them down could touch
    -- buttons in combat. Remaining hooks are gated by `active` / mod._enabled.
end

-- Exported for the Action Bars page: its Standard mode mirrors the bar-style
-- and Dark Mode rows there, writing into THIS module's db, and needs the
-- appliers -- they are file-locals here on purpose.
function mod.BarStyleValues()
    return {
        { value = "standard", text = L["Standard (Blizzard's own look)"] },
        { value = "minimaldark", text = L["Shadow (darkened Blizzard border)"] },
        { value = "circle",  text = L["Circle (masked shape)"] },
        { value = "csquare", text = L["Square (masked shape)"] },
        { value = "hexagon", text = L["Hexagon (masked shape)"] },
    }
end
mod.BAR_TINT       = DARK_TINT   -- the mirror page's color fallback reads this
mod.SetBarsSkinned = setBarsSkinned
mod.RefreshAll     = refreshAll
mod.SkinAll        = skinAll
mod.ApplyAllDM     = applyAllDM

function mod:GetOptions()
    local STYLE_VALUES = mod.BarStyleValues()

    local function dmApply() applyAllDM() end
    local function dmAreaToggle(key, label, tooltip)
        return {
            type = "toggle", label = label, tooltip = tooltip,
            get = function() return mod.db[key] end,
            set = function(_, v) mod.db[key] = v; dmApply() end,
        }
    end

    return {
        -- No page header/description here: this page is a container tab, and
        -- the container already prints the tab title and the module
        -- description above -- both showed twice (user report, 31.07.2026).
        { type = "header", text = L["Action Bars"] },
        { type = "toggle", label = L["Skin the action bars"],
          tooltip = L["The dark action-bar button skin."],
          get = function() return mod.db.skinBars end,
          set = function(_, v) mod.db.skinBars = v; setBarsSkinned(v) end },
        { type = "dropdown", label = L["Bar style"],
          tooltip = L["Pick how the action buttons look: Blizzard's own untouched button, the dark Shadow skin, or a masked shape (circle, square, hexagon)."],
          width = 260,
          values = STYLE_VALUES,
          get = function() return mod.db.style or "standard" end,
          -- The DM pass follows every style switch: standard hands the rim to
          -- Dark Mode, the skin takes it back -- either way the tint must be
          -- re-decided right now, not at the next button update.
          set = function(_, v) mod.db.style = v; refreshAll(); applyAllDM() end },
        { type = "color", label = L["Border color"],
          tooltip = L["Tints the frame of the Shadow and shape styles. Reset it to get each style's built-in coloring back."],
          get = function() return mod.db.barBorderTint or { r = DARK_TINT, g = DARK_TINT, b = DARK_TINT } end,
          set = function(r, g, b) mod.db.barBorderTint = { r = r, g = g, b = b }; refreshAll() end,
          onReset = function() mod.db.barBorderTint = nil; refreshAll() end },
        { type = "toggle", label = L["Also skin pet & stance buttons"],
          get = function() return mod.db.skinPetStance end,
          set = function(_, v) mod.db.skinPetStance = v; skinAll() end },

        { type = "spacer", height = 8 },

        { type = "header", text = L["WeakAuras Icons"] },
        { type = "toggle", label = L["Skin WeakAuras icons"],
          get = function() return mod.db.skinWeakAuras end,
          set = function(_, v)
              local was = mod.db.skinWeakAuras
              mod.db.skinWeakAuras = v
              -- Through the module, like the registration in OnEnable, so the
              -- framework's teardown owns this one too. The registry refuses a
              -- duplicate, so the flip check is belt and braces.
              if mod._enabled and v and not was then
                  mod:RegisterEvent("UNIT_AURA", skinWASoon)
              elseif was and not v then
                  ns:UnregisterEvent("UNIT_AURA", skinWASoon)
              end
              if v then skinAllWAIcons() end
          end },
        { type = "dropdown", label = L["WeakAuras style"],
          tooltip = L["Style for WeakAuras icons, independent of the action bars."],
          width = 260,
          -- Its own list, not the bar styles: the five aura layer sets.
          values = {
              { value = "set1", text = L["Shadow 1"] },
              { value = "set2", text = L["Shadow 2"] },
              { value = "set3", text = L["Shadow 3"] },
              { value = "set4", text = L["Shadow 4"] },
              { value = "set5", text = L["Shadow 5"] },
          },
          get = function() return mod.db.waStyle or "set1" end,
          set = function(_, v) mod.db.waStyle = v; skinAllWAIcons() end },
        { type = "color", label = L["Border color"],
          tooltip = L["Tints the border layer of the aura sets. Reset it to get each set's built-in coloring back."],
          get = function() return mod.db.waBorderTint or { r = 1, g = 1, b = 1 } end,
          set = function(r, g, b) mod.db.waBorderTint = { r = r, g = g, b = b }; skinAllWAIcons() end,
          onReset = function() mod.db.waBorderTint = nil; skinAllWAIcons() end },
        { type = "toggle", label = L["Hide WeakAuras' own border"],
          tooltip = L["Hides the light border WeakAuras draws on icons, so only our dark rim shows. /reload to fully restore it."],
          get = function() return mod.db.hideWABorder end,
          set = function(_, v) mod.db.hideWABorder = v; skinAllWAIcons() end },

        { type = "spacer", height = 8 },

        { type = "header", text = L["Dark Mode"] },
        { type = "desc", text = L["|cffaaaaaaOptional: darkens and desaturates Blizzard's default artwork — unit frames, minimap and action bars — to a neutral dark tone. Reversible: turn it off and the gold look returns.|r"] },
        -- The master switch, tint, desaturation and the two BAR areas live on
        -- the Action Bars page (Standard branch), which mirrors them into this
        -- module's db -- they stood here TWICE and the user chose that page as
        -- the one home (31.07.2026). Only the areas no other page carries stay:
        dmAreaToggle("dmUnitframes", L["Unit frames"],
            L["Player, target, focus, pet and party frame borders."]),
        dmAreaToggle("dmMinimap", L["Minimap"],
            L["Minimap border, compass, zoom and tracking buttons."]),
        dmAreaToggle("dmBags", L["Bag slots"],
            L["Tints the backpack, bag and keyring button borders."]),

        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaNote: if the Player & Target Frame module's |cffffffffThreat glow|r is on, threat colouring takes over the target/focus border while you have aggro — that's intended.|r"] },
    }
end

ns:RegisterSlash({ key = "WEAKAURASKIN", commands = { "/vcuiwa" },
    desc = "Repaint the aura addon windows now.",
    module = "darkskin",
})
ns.Slash.WEAKAURASKIN = function()
    local shown, skinned = 0, 0
    local unskinned = {}
    local function chain(f)
        local parts, n = {}, 0
        while f and n < 7 do
            parts[#parts + 1] = (f.GetName and f:GetName())
                or ("{" .. tostring(f.regionType or (f.GetObjectType and f:GetObjectType())) .. "}")
            f = f.GetParent and f:GetParent()
            n = n + 1
        end
        return table.concat(parts, " < ")
    end
    local types = {}
    local function walk(f, d)
        if not f or d > 12 then return end
        if f.IsForbidden and f:IsForbidden() then return end
        local rt = f.regionType
        if (rt == "icon" or rt == "aurabar") and f.icon and f.IsShown and f:IsShown() then
            types[rt] = (types[rt] or 0) + 1
            shown = shown + 1
            if f._vcuiRing then
                skinned = skinned + 1
            else
                local ok, err = pcall(skinWARegion, f)
                unskinned[#unskinned + 1] = rt .. " @ " .. chain(f)
                    .. (ok and "" or (" |cffff5555ERR " .. tostring(err) .. "|r"))
            end
        end
        if not f.GetChildren then return end
        local packed = { pcall(f.GetChildren, f) }
        if packed[1] then
            for i = 2, #packed do walk(packed[i], d + 1) end
        end
    end
    walk(UIParent, 0)
    ns:Print(string.format("WeakAuras regions: shown=%d skinned=%d unskinned=%d (icon=%d aurabar=%d) enabled=%s skinWA=%s",
        shown, skinned, #unskinned, types.icon or 0, types.aurabar or 0,
        tostring(mod._enabled), tostring(mod.db and mod.db.skinWeakAuras)))
    for i = 1, math.min(#unskinned, 12) do
        ns:Print("  " .. unskinned[i])
    end
    if #unskinned == 0 and shown > 0 then ns:Print("All shown WeakAuras icon/aurabar regions are skinned.") end
end
