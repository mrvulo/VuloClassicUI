-- VuloClassicUI / Modules / ActionBars
-- Protected ops (frame creation, SetPoint, state drivers, override bindings,
-- SetAttribute) must run out of combat; only the secure snippets run in combat.
local _, ns = ...
local L = ns.L

local function barDefaults(over)
    local d = {
        on = true, visibility = "always", fadeAlpha = 0, scale = 1,
        perRow = 12, spacing = 4, x = 0, y = -300,
        alpha = 100, showEmpty = true, clickThrough = false,
        textKeybindSize = 0, textMacroSize = 0, textCountSize = 0, textCooldownSize = 0,
        growH = "right",
        growV = "down",
        onlyInstances = false, hideMounted = false,
        hideNoTarget = false, hideNoEnemyTarget = false,
        groupVis = "any",
        bgOn = false, bgColor = { r = 0, g = 0, b = 0 }, bgAlpha = 60, bgPad = 4,
    }
    for k, v in pairs(over) do d[k] = v end
    return d
end

local mod = ns:RegisterModule("actionbars", {
    -- The strict grid: a lone last row keeps its half instead of stretching,
    -- and every run shares the page's label column (user report, 31.07.2026 --
    -- the fifth Dark Mode row spanned the page with its switch far right).
    optionsGrid = true,
    name        = "Action Bars",
    group       = "HUD",
    description = "Takes over every action bar with its own movable frames: real combat/mouseover show-hide, scale and grid layout per bar, correct main-bar paging (druid/rogue/warrior/priest forms) and your keybinds. EXPERIMENTAL — test ability clicks and paging in combat; /reload after disabling.",
    defaults = {
        enabled        = false,
        fadeSpeed      = 0.18,
        pushedTint = false, pushedColor = { r = 1, g = 0.82, b = 0 }, pushedClassColor = false,
        highlightTint = false, highlightColor = { r = 1, g = 1, b = 1 }, highlightClassColor = false,
        hideStatusBars = true,
        hidePerfBar    = true,
        hideMicroMenu  = false,
        microStyle     = "classic",
        hideBags       = false,
        bagStyle       = "classic",
        textKeybindColor = { r = 1, g = 1, b = 1 },
        textMacroColor   = { r = 1, g = 1, b = 1 },
        textCountColor   = { r = 1, g = 1, b = 1 },
        textKeybindX = 0, textKeybindY = 0,
        textMacroX   = 0, textMacroY   = 0,
        textCountX   = 0, textCountY   = 0,
        hoverShowsAll = false,
        cdSwipe       = 80,
        cdSwipeColor  = { r = 0, g = 0, b = 0 },
        cdAlpha       = 100,
        desatOnCd     = false,
        rangeColoring = false,
        rangeColor    = { r = 0.8, g = 0.15, b = 0.15 },
        tooltipMode   = "show",
        chrome = {
            micro = { x = 300,  y = -350, scale = 1 },
            bags  = { x = 560,  y = -350, scale = 1 },
            perf  = { x = 60,   y = -350, scale = 1 },
        },
        xpbar = { on = true, width = 420, height = 14, x = 0, y = -320, scale = 1,
                  color = { r = 0.58, g = 0.0, b = 0.55 } },
        bars = {
            main        = barDefaults({ y = -300, pageShift = 0, pageCtrl = 0, pageAlt = 0, pageHelp = 0, pageHarm = 0 }),
            bottomleft  = barDefaults({ y = -338 }),
            bottomright = barDefaults({ y = -376 }),
            right       = barDefaults({ perRow = 6,  x = 520,  y = -40 }),
            left        = barDefaults({ perRow = 6,  x = 452,  y = -40 }),
            extra       = barDefaults({ on = false, y = -262 }),
            stance      = barDefaults({ perRow = 10, x = -380, y = -250 }),
            pet         = barDefaults({ perRow = 10, x = 380,  y = -250 }),
        },
    },
})

local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey
local abs = math.abs

-- Three tabs like the reference: the bars themselves, the chrome around them
-- (micro menu, bag bar, XP bar), and the interaction tinting.
mod.tabs = {
    { id = "display", label = "Bar Display" },
    { id = "chrome",  label = "Menu, Bags & XP Bar" },
    { id = "anim",    label = "Bar Animations" },
}

local BARS = {
    { key = "main",        kind = "own",    count = 12, cmd = "ACTIONBUTTON%d",         label = "Action Bar 1 (Main)" },
    { key = "bottomleft",  kind = "reuse",  count = 12, base = 60, prefix = "MultiBarBottomLeft",  cmd = "MULTIACTIONBAR1BUTTON%d", label = "Action Bar 2" },
    { key = "bottomright", kind = "reuse",  count = 12, base = 48, prefix = "MultiBarBottomRight", cmd = "MULTIACTIONBAR2BUTTON%d", label = "Action Bar 3" },
    { key = "right",       kind = "reuse",  count = 12, base = 24, prefix = "MultiBarRight",       cmd = "MULTIACTIONBAR3BUTTON%d", label = "Action Bar 4" },
    { key = "left",        kind = "reuse",  count = 12, base = 36, prefix = "MultiBarLeft",        cmd = "MULTIACTIONBAR4BUTTON%d", label = "Action Bar 5" },
    -- no Blizzard command exists for actions 13-24; bound via click bindings
    { key = "extra",       kind = "reuse",  count = 12, base = 12, cmd = "CLICK VuloAB_extraB%d:LeftButton", label = "Action Bar 6 (Extra)" },
    { key = "stance",      kind = "stance", count = 10, prefix = "StanceButton",    blizz = "StanceBarFrame",     cmd = "SHAPESHIFTBUTTON%d", label = "Stance bar" },
    { key = "pet",         kind = "pet",    count = 10, prefix = "PetActionButton", blizz = "PetActionBarFrame",  cmd = "BONUSACTIONBUTTON%d", label = "Pet bar" },
}
local BAR_BY_KEY = {}
for _, d in ipairs(BARS) do BAR_BY_KEY[d.key] = d end

local state = {}
local shadow
local taken = false
local hidden = {}         -- Blizzard frame -> original parent (restore)
local pendingRestore = false
local updater

local MAIN_ART = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuBarTextureExtender",
}
local LEGACY_BARS = { "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }
local MULTIBAR_FRAMES = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }
local STANCE_HIDE = { "StanceBar", "StanceBarFrame" }
local MICRO_FRAMES = { "MicroMenu" }
local BAG_FRAMES   = {
    "BagsBar", "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
}

local CLASS_STATES = {
    DRUID = {
        { m = "[bonusbar:3]", page = 9 },
        { m = "[bonusbar:1]", page = 7 },
        { f = 24858,          page = 10 },
        { f = 33891,          page = 8 },
    },
    ROGUE   = { { m = "[bonusbar:1]", page = 7 } },
    WARRIOR = { { f = 2457, page = 7 }, { f = 71, page = 8 }, { f = 2458, page = 9 } },
    PRIEST  = { { m = "[form:1]", page = 7 } },
}

local function ensureShadow()
    if shadow then return end
    shadow = CreateFrame("Frame", "VuloABShadow", UIParent)
    shadow:SetAllPoints(UIParent)
    shadow:Hide()
end

local function barDB(key) return mod.db.bars[key] end

local function formCond(spells)
    if type(spells) ~= "table" then spells = { spells } end
    for i = 1, (GetNumShapeshiftForms() or 0) do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        for _, s in ipairs(spells) do
            if s == spellID then return ("[form:%d]"):format(i) end
        end
    end
end

local function pageDriver()
    local conds = {}
    -- order matters: first matching condition wins in a state driver
    local db = barDB("main")
    local function modpage(cond, page)
        page = tonumber(page) or 0
        if page >= 2 and page <= 6 then conds[#conds + 1] = cond .. page end
    end
    modpage("[mod:shift]", db.pageShift)
    modpage("[mod:ctrl]",  db.pageCtrl)
    modpage("[mod:alt]",   db.pageAlt)
    modpage("[@target,help]", db.pageHelp)
    modpage("[@target,harm]", db.pageHarm)
    for p = 2, 6 do conds[#conds + 1] = ("[bar:%d]%d"):format(p, p) end
    local _, class = UnitClass("player")
    local states = CLASS_STATES[class]
    if states then
        for _, st in ipairs(states) do
            local cond = st.m or (st.f and formCond(st.f))
            if cond then conds[#conds + 1] = cond .. st.page end
        end
    end
    conds[#conds + 1] = "1"
    return table.concat(conds, ";")
end

local function keyAbbr(key)
    if not key then return nil end
    return (key
        :gsub("SHIFT%-", "s-"):gsub("STRG%-", "c-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-")
        :gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
        :gsub("NUMPAD", "N"):gsub("SPACE", "Sp"))
end

-- never call the mixin's OnShow eagerly: it registers callbacks that poke secure scripts
local function wireQuickKeybind(b, command)
    b.commandName = command
    if not _G.QuickKeybindButtonTemplateMixin or b._vcuiQKB then return end
    b._vcuiQKB = true
    Mixin(b, _G.QuickKeybindButtonTemplateMixin)
    b:HookScript("OnShow", b.QuickKeybindButtonOnShow)
    b:HookScript("OnHide", b.QuickKeybindButtonOnHide)
    b:HookScript("OnClick", b.QuickKeybindButtonOnClick)
    b:HookScript("OnEnter", b.QuickKeybindButtonOnEnter)
    b:HookScript("OnLeave", b.QuickKeybindButtonOnLeave)
end

-- The bar background: an insecure texture on the secure container -- textures
-- are unprotected, and anchoring to the frame corners means it follows every
-- resize on its own. Re-applied only from its setters and ensureBar.
local function applyBarBg(key)
    local st = state[key]
    if not (st and st.bg) then return end
    local db = barDB(key)
    if db.bgOn then
        local c = db.bgColor or { r = 0, g = 0, b = 0 }
        local pad = db.bgPad or 4
        st.bg:ClearAllPoints()
        st.bg:SetPoint("TOPLEFT",     st.frame, "TOPLEFT",     -pad,  pad)
        st.bg:SetPoint("BOTTOMRIGHT", st.frame, "BOTTOMRIGHT",  pad, -pad)
        st.bg:SetVertexColor(c.r or 0, c.g or 0, c.b or 0, (db.bgAlpha or 60) / 100)
        st.bg:Show()
    else
        st.bg:Hide()
    end
end

local function ensureBar(desc)
    local st = state[desc.key]
    if not st then st = { buttons = {}, curAlpha = 1, tgtAlpha = 1, hovered = false }; state[desc.key] = st end

    if not st.frame then
        local f = CreateFrame("Frame", "VuloAB_" .. desc.key, UIParent, "SecureHandlerStateTemplate")
        f:SetSize(desc.count * 40, 40)
        f:SetFrameStrata("MEDIUM")
        st.frame = f
        local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:Hide()
        st.bg = bg
        applyBarBg(desc.key)
        if desc.kind == "own" then
            f:SetAttribute("checkselfcast", true)
            f:SetAttribute("checkfocuscast", true)
            f:SetAttribute("checkmouseovercast", true)
            f:SetAttribute("barLength", desc.count)
            f:SetAttribute("_onstate-page", "self:RunAttribute('UpdateOffset')")
            f:SetAttribute("UpdateOffset", [[
                local page = self:GetAttribute('state-page') or 1
                local offset = (page - 1) * self:GetAttribute('barLength')
                self:SetAttribute('actionOffset', offset)
                control:ChildUpdate('offset', offset)
            ]])
        end
        f:SetAttribute("UpdateShown", [[
            if self:GetAttribute('state-userDisplay') == 'hide' then self:Hide() else self:Show() end
        ]])
        f:SetAttribute("_onstate-userDisplay", "self:RunAttribute('UpdateShown')")
        if ns.CreateMover and not st.mover then
            st.mover = ns:CreateMover(f, { db = barDB(desc.key), key = "actionbar_" .. desc.key, label = L[desc.label], scalable = true })
        end
    end

    for i = 1, desc.count do
        if desc.kind == "own" then
            local b = _G["VuloActionButton" .. i] or CreateFrame("CheckButton", "VuloActionButton" .. i, st.frame, "ActionBarButtonTemplate")
            b:SetParent(st.frame)
            -- no insecure 'action' seed: the page state driver writes it from the
            -- restricted environment, and a Lua-set value taints every later read
            b:SetAttributeNoHandler("index", i)
            b:SetAttributeNoHandler("commandName", "ACTIONBUTTON" .. i)
            wireQuickKeybind(b, "ACTIONBUTTON" .. i)
            b:SetAttributeNoHandler("useparent-checkselfcast", true)
            b:SetAttributeNoHandler("useparent-checkfocuscast", true)
            b:SetAttributeNoHandler("useparent-checkmouseovercast", true)
            b:SetAttributeNoHandler("_childupdate-offset", [[
                local offset = message or 0
                local id = self:GetAttribute('index') + offset
                if self:GetAttribute('action') ~= id then self:SetAttribute('action', id) end
            ]])
            b:EnableMouseWheel()
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:Show()
            st.buttons[i] = b
        elseif desc.kind == "pet" then
            -- pet buttons must stay in the container's actionButtons or Blizzard's events and keybinds break
            local bf = _G.PetActionBar or _G.PetActionBarFrame
            local b = (bf and bf.actionButtons and bf.actionButtons[i]) or _G["PetActionButton" .. i]
            if b then
                b:SetParent(st.frame)
                b:SetAttribute("commandName", "BONUSACTIONBUTTON" .. i)
                st.buttons[i] = b
            end
        elseif desc.kind == "stance" then
            -- the id passed to CreateFrame wires the secure form-cast without an insecure attribute set
            local name = "VuloAB_stanceB" .. i
            local b = _G[name] or CreateFrame("CheckButton", name, st.frame, "StanceButtonTemplate", i)
            b:SetParent(st.frame)
            b:SetAttribute("commandName", "SHAPESHIFTBUTTON" .. i)
            if b.cooldown and b.cooldown.SetDrawEdge then b.cooldown:SetDrawEdge(false) end
            if b.SlotBackground then b.SlotBackground:Hide() end
            b:EnableMouseWheel()
            st.buttons[i] = b
        else
            -- `action` may only be set from the secure ChildUpdate snippet; an
            -- insecure set taints it, and Blizzard's UpdatePressAndHoldAction
            -- reads that field and then calls SetAttribute -> blocked in combat
            local name = "VuloAB_" .. desc.key .. "B" .. i
            local b = _G[name] or CreateFrame("CheckButton", name, st.frame, "ActionBarButtonTemplate")
            b:SetParent(st.frame)
            b:SetAttributeNoHandler("index", i)
            b:SetAttributeNoHandler("commandName", desc.cmd:format(i))
            wireQuickKeybind(b, desc.cmd:format(i))
            b:SetAttributeNoHandler("_childupdate-offset", [[
                local offset = message or 0
                local id = self:GetAttribute('index') + offset
                if self:GetAttribute('action') ~= id then self:SetAttribute('action', id) end
            ]])
            b:EnableMouseWheel()
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:Show()
            st.buttons[i] = b
        end
    end
end

-- the template does not self-update when created standalone
local function updateStance()
    local st = state.stance
    if not st then return end
    local canShow = not InCombatLockdown()   -- Show/Hide on a secure button is protected in combat
    for i, b in ipairs(st.buttons) do
        local texture, isActive, isCastable = GetShapeshiftFormInfo(i)
        if canShow then b:SetShown(texture ~= nil) end
        local icon = b.icon or (b:GetName() and _G[b:GetName() .. "Icon"])
        if icon then
            icon:SetTexture(texture)
            local c = isCastable and 1 or 0.4
            icon:SetVertexColor(c, c, c)
        end
        if b.cooldown then
            local start, dur, en = GetShapeshiftFormCooldown(i)
            if en and en ~= 0 and (start or 0) > 0 and (dur or 0) > 0 then
                b.cooldown:SetCooldown(start, dur)
            elseif b.cooldown.Clear then
                b.cooldown:Clear()
            end
        end
        b:SetChecked(isActive and true or false)
    end
end

-- position + scale belong to the mover; only size here, then re-apply the mover
local function layoutBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    local db = barDB(desc.key)
    local buttons = st.buttons
    if desc.kind == "stance" then
        local nf = GetNumShapeshiftForms() or 0
        buttons = {}
        for i = 1, nf do if st.buttons[i] then buttons[#buttons + 1] = st.buttons[i] end end
    end
    local n = #buttons
    local perRow = math.max(1, math.min(db.perRow or desc.count, desc.count))
    local sp = db.spacing or 4
    local iconSize = (db.iconSize and db.iconSize > 0) and db.iconSize or nil

    local function fontSize(fs, size)
        if fs and size and size > 0 and ns.ApplyFontSize then ns:ApplyFontSize(fs, size) end
    end
    local function styleText(fs, color, ox2, oy2)
        if not fs then return end
        if color then fs:SetTextColor(color.r or 1, color.g or 1, color.b or 1) end
        ox2, oy2 = ox2 or 0, oy2 or 0
        if ox2 ~= 0 or oy2 ~= 0 or fs._vcuiMoved then
            if not fs._vcuiDef then
                local p, rel, rp, x, y = fs:GetPoint(1)
                if p then fs._vcuiDef = { p, rel, rp, x or 0, y or 0 } end
            end
            local d0 = fs._vcuiDef
            if d0 then
                fs:ClearAllPoints()
                fs:SetPoint(d0[1], d0[2], d0[3], d0[4] + ox2, d0[5] + oy2)
                fs._vcuiMoved = (ox2 ~= 0 or oy2 ~= 0) or nil
            end
        end
    end
    local g = mod.db
    for _, b in ipairs(st.buttons) do
        if iconSize then b:SetSize(iconSize, iconSize) end
        local nm = b:GetName()
        local hk = b.HotKey or (nm and _G[nm .. "HotKey"])
        if hk then
            hk:SetShown(not db.hideKeybind); fontSize(hk, db.textKeybindSize)
            styleText(hk, g.textKeybindColor, g.textKeybindX, g.textKeybindY)
        end
        local macro = b.Name or (nm and _G[nm .. "Name"])
        if macro then
            macro:SetShown(not db.hideMacro); fontSize(macro, db.textMacroSize)
            styleText(macro, g.textMacroColor, g.textMacroX, g.textMacroY)
        end
        local count = b.Count or (nm and _G[nm .. "Count"])
        if count then
            fontSize(count, db.textCountSize)
            styleText(count, g.textCountColor, g.textCountX, g.textCountY)
        end
        if (db.textCooldownSize or 0) > 0 and b.cooldown and b.cooldown.GetRegions then
            for _, r in ipairs({ b.cooldown:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" then
                    fontSize(r, db.textCooldownSize)
                end
            end
        end
        b:EnableMouse(not db.clickThrough)
    end

    local w = iconSize or (buttons[1] and buttons[1]:GetWidth()) or 36
    local h = iconSize or (buttons[1] and buttons[1]:GetHeight()) or 36
    if w == 0 then w = 36 end; if h == 0 then h = 36 end

    if n == 0 then
        st.frame:SetSize(40, 40)
    else
        local cols = db.vertical and math.ceil(n / perRow) or math.min(perRow, n)
        local rows = db.vertical and math.min(perRow, n) or math.ceil(n / perRow)
        st.frame:SetSize(cols * (w + sp) - sp, rows * (h + sp) - sp)
        for idx, b in ipairs(buttons) do
            local slot = (db.reverse and (n - idx + 1) or idx) - 1
            local col, row
            if db.vertical then row = slot % perRow; col = math.floor(slot / perRow)
            else               col = slot % perRow; row = math.floor(slot / perRow) end
            if db.growH == "left" then col = cols - 1 - col end
            if db.growV == "up" then row = rows - 1 - row end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", st.frame, "TOPLEFT", col * (w + sp), -row * (h + sp))
        end
    end
    if st.mover and st.mover.SetSize then st.mover:SetSize(st.frame:GetWidth(), st.frame:GetHeight()) end
    if ns.ApplyMover and st.mover then ns:ApplyMover(st.mover) end
end

local function pageBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    if desc.kind == "own" then
        RegisterStateDriver(st.frame, "page", pageDriver())
    else
        -- Seed the offset inside the restricted environment as well. Setting it
        -- from plain Lua first taints the value, and the snippet then writes a
        -- tainted 'action' onto every child -- which is exactly what the taint
        -- log pins the blocked SetShown on.
        st.frame:Execute((
            "self:SetAttribute('actionOffset', %d) " ..
            "self:ChildUpdate('offset', %d)"
        ):format(desc.base, desc.base))
    end
end

-- all conditions must fold into ONE bracket (they AND) to stay secure in combat
local function visBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    local db = barDB(desc.key)
    if db.onlyInstances and not IsInInstance() then
        RegisterStateDriver(st.frame, "userDisplay", "hide")
        return
    end
    local gates = {}
    if desc.kind == "pet" then gates[#gates + 1] = "@pet,exists" end
    if db.hideMounted then gates[#gates + 1] = "nomounted" end
    if db.hideNoEnemyTarget then gates[#gates + 1] = "@target,harm"
    elseif db.hideNoTarget then gates[#gates + 1] = "@target,exists" end
    local grp = db.groupVis
    if grp == "group" then gates[#gates + 1] = "group"
    elseif grp == "raid" then gates[#gates + 1] = "group:raid"
    elseif grp == "party" then gates[#gates + 1] = "group:party"
    elseif grp == "solo" then gates[#gates + 1] = "nogroup" end
    local m = db.visibility
    if m == "combat" then gates[#gates + 1] = "combat"
    elseif m == "noncombat" then gates[#gates + 1] = "nocombat" end
    if #gates > 0 then
        RegisterStateDriver(st.frame, "userDisplay",
            "[" .. table.concat(gates, ",") .. "] show; hide")
    else
        UnregisterStateDriver(st.frame, "userDisplay")
        st.frame:Show()
    end
end

-- our buttons have no native binding, so route the command keys via overrides
local function bindBar(desc)
    if desc.kind == "pet" then return end   -- Blizzard's own buttons, already bound
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() or not desc.cmd then return end
    ClearOverrideBindings(st.frame)
    for i, b in ipairs(st.buttons) do
        local keys = { GetBindingKey(desc.cmd:format(i)) }
        for _, key in ipairs(keys) do
            SetOverrideBindingClick(st.frame, false, key, b:GetName(), "LeftButton")
        end
        local hk = b.HotKey or _G[b:GetName() .. "HotKey"]
        if hk then
            hk:SetText(keyAbbr(keys[1]) or "")
            -- bindBar runs after layoutBar, so it must not undo the hide toggle
            hk:SetShown(keys[1] ~= nil and not barDB(desc.key).hideKeybind)
        end
    end
end

local function wantStatusHidden()
    return mod.active and (mod.db.hideStatusBars or (mod.db.xpbar and mod.db.xpbar.on)) and true or false
end

local function applyStatusBar()
    if InCombatLockdown() then return end
    local stbm = _G.StatusTrackingBarManager
    local hide = wantStatusHidden()
    if stbm then
        if hide then
            stbm:UnregisterAllEvents(); stbm:Hide()
            if not stbm.vHooked then
                stbm.vHooked = true
                stbm:HookScript("OnShow", function(self)
                    if wantStatusHidden() and not InCombatLockdown() then self:Hide() end
                end)
            end
        else
            stbm:Show()
            if stbm.RegisterAllEvents then stbm:RegisterAllEvents() end
        end
    end
    for _, n in ipairs(LEGACY_BARS) do
        local f = _G[n]
        if f then if hide then f:Hide() else f:Show() end end
    end
end

local function applyPerfBar()
    local hide = mod.active and mod.db.hidePerfBar
    local f = _G.MainMenuBarPerformanceBarFrame
    if f then f:SetAlpha(hide and 0 or 1) end
    local b = _G.MainMenuBarPerformanceBarFrameButton
    if b then b:SetAlpha(hide and 0 or 1); if b.EnableMouse then b:EnableMouse(not hide) end end
end

-- alpha + mouse only (never move) is taint-free; the original mouse state is kept
-- because enabling mouse on a frame that never had it makes it eat clicks
local function setFramesHidden(names, hide)
    for _, n in ipairs(names) do
        local f = _G[n]
        if f then
            if f._vcuiMouse == nil and f.IsMouseEnabled then
                f._vcuiMouse = f:IsMouseEnabled() and true or false
            end
            f:SetAlpha(hide and 0 or 1)
            if f.EnableMouse then f:EnableMouse((not hide) and f._vcuiMouse or false) end
        end
    end
end

local function applyMicroBags()
    setFramesHidden(MICRO_FRAMES, mod.active and (mod.db.hideMicroMenu or (taken and mod.db.microStyle == "modern")))
    setFramesHidden(BAG_FRAMES, mod.active and mod.db.hideBags)
end

-- these are not protected action frames, so reparent + SetPoint is taint-free
local CHROME = {
    { key = "micro", label = "Micro menu" },
    { key = "bags",  label = "Bag bar" },
    { key = "perf",  label = "FPS / latency bar" },
}
local chromeState = {}
local chromeOrig = {}    -- reparented frame -> original parent
-- moved frame -> the points it carried before we moved it, as
-- { n = <count>, <GetPoint results> } so a nil relativeTo survives unpack.
--
-- chromeOrig gives a frame its PARENT back; without this it keeps our ANCHOR and
-- so stays wherever the holder was. Measured on a live client: BagsBar and the
-- performance bar are stranded that way, while MicroMenu re-anchors itself during
-- the session and needs nothing. See restoreChrome.
local origAnchor = {}

local BAG_SLOT_BUTTONS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
}

local function chromeTargets(key)
    if key == "micro" then
        local c = _G.MicroMenu or _G.MicroMenuContainer
        return c and { c }
    elseif key == "bags" then
        local c = _G.BagsBar
        if c then return { c } end
        local t = {}
        for _, n in ipairs(BAG_SLOT_BUTTONS) do local f = _G[n]; if f then t[#t + 1] = f end end
        if #t > 0 then return t end
    else
        local c = _G.MainMenuBarPerformanceBarFrame
        return c and { c }
    end
end

-- Blizzard's layout code re-anchors these frames, so hook SetPoint and re-pin
local function pinFrame(f, point, holder, relPoint, x, y)
    -- FIRST WRITE WINS. ensureChrome has already re-parented the frame by the time
    -- we get here, but it has NOT touched the points yet -- verified on a live
    -- client, where the values read at this moment are still Blizzard's own.
    if origAnchor[f] == nil and f.GetNumPoints then
        local pts = {}
        for i = 1, (f:GetNumPoints() or 0) do
            pts[i] = { n = select("#", f:GetPoint(i)), f:GetPoint(i) }
        end
        if #pts > 0 then origAnchor[f] = pts end
    end
    f._vcuiPinTo = { point, holder, relPoint, x, y }
    f._vcuiPinning = true
    f:ClearAllPoints()
    f:SetPoint(point, holder, relPoint, x, y)
    f._vcuiPinning = false
    if not f._vcuiPinHook then
        f._vcuiPinHook = true
        hooksecurefunc(f, "SetPoint", function(self)
            if self._vcuiPinning or not self._vcuiPinTo then return end
            if not (mod.active and taken) then return end
            self._vcuiPinning = true
            self:ClearAllPoints()
            self:SetPoint(unpack(self._vcuiPinTo))
            self._vcuiPinning = false
        end)
    end
end

local function ensureChrome(c)
    local cs = chromeState[c.key]
    if not cs then cs = {}; chromeState[c.key] = cs end
    if not cs.holder then
        local h = CreateFrame("Frame", "VuloABChrome_" .. c.key, UIParent)
        h:SetSize(220, 40)
        h:SetFrameStrata("MEDIUM")
        cs.holder = h
        if ns.CreateMover then
            cs.mover = ns:CreateMover(h, { db = mod.db.chrome[c.key], key = "abchrome_" .. c.key, label = L[c.label], scalable = true })
        end
    end
    cs.targets = chromeTargets(c.key)
    if not cs.targets then cs.holder:Hide(); return end
    cs.holder:Show()
    for _, f in ipairs(cs.targets) do
        if chromeOrig[f] == nil then chromeOrig[f] = f:GetParent() or UIParent end
        f:SetParent(cs.holder)
    end
    if #cs.targets == 1 then
        local f = cs.targets[1]
        local w, hgt = f:GetSize()
        if not w or w < 1 then w, hgt = 220, 40 end
        cs.holder:SetSize(w, hgt)
        pinFrame(f, "CENTER", cs.holder, "CENTER", 0, 0)
    else
        local x, maxH = 0, 0
        for _, f in ipairs(cs.targets) do
            local w, hgt = f:GetSize()
            if not w or w < 1 then w, hgt = 32, 32 end
            pinFrame(f, "BOTTOMLEFT", cs.holder, "BOTTOMLEFT", x, 0)
            x = x + w + 2
            if hgt > maxH then maxH = hgt end
        end
        cs.holder:SetSize(math.max(40, x - 2), math.max(20, maxH))
    end
    if cs.mover then
        cs.mover:SetSize(cs.holder:GetWidth(), cs.holder:GetHeight())
        if ns.ApplyMover then ns:ApplyMover(cs.mover) end
    end
end

-- with both frames re-homed, Blizzard's keyring updater errors on every SetPoint
local origUpdateKeyRing
local function muteKeyRingLayout(mute)
    if mute then
        if not origUpdateKeyRing and type(_G.MainMenuBar_UpdateKeyRing) == "function" then
            origUpdateKeyRing = _G.MainMenuBar_UpdateKeyRing
            _G.MainMenuBar_UpdateKeyRing = function() end
        end
    elseif origUpdateKeyRing then
        _G.MainMenuBar_UpdateKeyRing = origUpdateKeyRing
        origUpdateKeyRing = nil
    end
end

-- Blizzard anchors micro buttons in a chain, so force-shown ones stack unless the row is laid out here
local MICRO_ORDER = {
    CharacterMicroButton = 1, SpellbookMicroButton = 2, TalentMicroButton = 3,
    QuestLogMicroButton = 4, SocialsMicroButton = 5, GuildMicroButton = 5,
    LFGMicroButton = 6, StoreMicroButton = 7,
    MainMenuMicroButton = 8, HelpMicroButton = 9,
}
local microHooked = false
local microSeen = {}
local function showAllMicro()
    local cs = chromeState.micro
    local container = cs and cs.targets and cs.targets[1]
    if not (container and container.GetChildren) then return end
    local btns = {}
    for _, b in ipairs({ container:GetChildren() }) do
        if b.IsObjectType and b:IsObjectType("Button") then
            -- never resurrect buttons Blizzard never shows (deprecated twins)
            if b:IsShown() then
                microSeen[b] = true
            elseif microSeen[b] then
                b:Show()
            end
            if b:IsShown() then btns[#btns + 1] = b end
        end
    end
    if #btns == 0 then return end
    table.sort(btns, function(a, b)
        local oa = MICRO_ORDER[a:GetName() or ""] or 50
        local ob = MICRO_ORDER[b:GetName() or ""] or 50
        if oa ~= ob then return oa < ob end
        return (a:GetName() or "") < (b:GetName() or "")
    end)
    local prev
    for _, b in ipairs(btns) do
        b:ClearAllPoints()
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 1, 0)
        else
            b:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
        end
        prev = b
    end
end

local applyMicroStyle, applyBagStyle   -- forward decls; defined below restoreChrome

local function applyChrome()
    if InCombatLockdown() then return end
    muteKeyRingLayout(true)
    for _, c in ipairs(CHROME) do ensureChrome(c) end
    if not microHooked and type(_G.UpdateMicroButtons) == "function" then
        microHooked = true
        hooksecurefunc("UpdateMicroButtons", function()
            if mod.active and taken then
                showAllMicro()
                if applyMicroStyle then applyMicroStyle() end
            end
        end)
    end
    showAllMicro()
    -- the emptied container shell stays mouse-enabled and swallows clicks
    local shell = _G.MicroMenuContainer
    local microTarget = chromeState.micro and chromeState.micro.targets and chromeState.micro.targets[1]
    if shell and shell ~= microTarget then
        if shell._vcuiMouse == nil and shell.IsMouseEnabled then
            shell._vcuiMouse = shell:IsMouseEnabled() and true or false
        end
        shell:EnableMouse(false)
    end
end

-- True while the frame is still anchored to one of OUR holders.
--
-- This is the whole guard. MicroMenu re-anchors itself to MicroMenuContainer
-- during the session, so by teardown it is already home; replaying a stored
-- snapshot over it would be us overruling Blizzard's own layout for no reason.
-- BagsBar and the performance bar are the two that really are still pinned to a
-- holder we are about to hide, and they are the only ones this touches.
local function pinnedToOurHolder(f)
    if not (f and f.GetNumPoints) then return false end
    for i = 1, (f:GetNumPoints() or 0) do
        local _, rel = f:GetPoint(i)
        local n = rel and rel.GetName and rel:GetName()
        if n and n:find("^VuloABChrome_") then return true end
    end
    return false
end

local function restoreChrome()
    muteKeyRingLayout(false)
    for f, parent in pairs(chromeOrig) do
        local pts = origAnchor[f]
        local stranded = pinnedToOurHolder(f)
        f._vcuiPinTo = nil   -- release the pin so Blizzard may anchor freely again
        f:SetParent(parent)
        if pts and stranded then
            -- pcall on purpose, and not to hide anything: restore() shows
            -- Blizzard's bars and clears `taken` AFTER this call, so an error
            -- thrown in here would strand the action bars -- a far worse outcome
            -- than a frame that stayed where our holder was. A failure is
            -- reported rather than swallowed.
            local ok, err = pcall(function()
                f:ClearAllPoints()
                for _, p in ipairs(pts) do f:SetPoint(unpack(p, 1, p.n)) end
            end)
            -- Reported, not swallowed: a pcall that hides its own failure is a
            -- silent bug, and this one would show up as a frame that stayed put.
            if not ok then
                ns:Debug("restoreChrome anchor: %s", tostring(err))
            end
        end
        origAnchor[f] = nil
        chromeOrig[f] = nil
    end
    local shell = _G.MicroMenuContainer
    if shell and shell._vcuiMouse ~= nil then shell:EnableMouse(shell._vcuiMouse) end
    for _, cs in pairs(chromeState) do
        if cs.holder then cs.holder:Hide() end
    end
end

local MICRO_ICON_DIR = "Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\"
-- `action`: the twin acts in OnMouseUp behind an IsMouseOver check, so a forwarded Click() is a no-op
local MODERN_MICRO = {
    { names = { "CharacterMicroButton" }, icon = "micro\\character",
      action = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end },
    { names = { "SpellbookMicroButton" },                   icon = "micro\\spellbook" },
    { names = { "TalentMicroButton" },                      icon = "micro\\talents" },
    { names = { "QuestLogMicroButton" },                    icon = "micro\\questlog" },
    { custom = true, icon = "micro\\map",
      tip = function() return _G.WORLD_MAP or L["World map"] end,
      action = function() if ToggleWorldMap then ToggleWorldMap() end end },
    { names = { "SocialsMicroButton", "GuildMicroButton" }, icon = "micro\\socials" },
    { custom = true, icon = "friends",
      tip = function() return _G.FRIENDS_LIST or L["Friends list"] end,
      action = function() if ToggleFriendsFrame then ToggleFriendsFrame(1) end end },
    { names = { "LFGMicroButton" }, custom = true, icon = "micro\\lfg",
      tip = function()
          local t = _G.LFGMicroButton
          return (t and t.tooltipText) or _G.LFG_TITLE or L["Group finder"]
      end,
      action = function(self)
          local t = self._target
          if t and t.Click and (t:IsShown() or microSeen[t]) then t:Click("LeftButton"); return end
          if _G.ToggleLFGParentFrame then
              _G.ToggleLFGParentFrame()
          elseif _G.LFGParentFrame then
              if _G.LFGParentFrame:IsShown() then HideUIPanel(_G.LFGParentFrame) else ShowUIPanel(_G.LFGParentFrame) end
          end
      end },
    -- the shop is protected (a forwarded click is refused), so the real button is adopted
    { adopt = "StoreMicroButton", icon = "micro\\store" },
    { names = { "MainMenuMicroButton" }, icon = "gear",
      action = function()
          local gm = _G.GameMenuFrame
          if not gm then return end
          if gm:IsShown() then
              HideUIPanel(gm)
          else
              if CloseMenus then CloseMenus() end
              if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
              ShowUIPanel(gm)
          end
      end },
    { names = { "HelpMicroButton" },                        icon = "micro\\help" },
}
local MICRO_BTN, MICRO_GAP, MICRO_PAD, MICRO_H, MICRO_ICON = 26, 3, 6, 34, 20
local modernMicro
local adoptSkin = {}   -- adopted Blizzard button -> original state

local function adoptMicroButton(b, icon)
    if not adoptSkin[b] then
        local st = { parent = b:GetParent() or UIParent, scale = b:GetScale() or 1, alphas = {} }
        for i = 1, select("#", b:GetRegions()) do
            local r = select(i, b:GetRegions())
            if r and r.SetAlpha then st.alphas[r] = r:GetAlpha(); r:SetAlpha(0) end
        end
        adoptSkin[b] = st
    end
    if not b._vcuiGlyph then
        local g = b:CreateTexture(nil, "OVERLAY")
        g:SetPoint("CENTER")
        g:SetVertexColor(1, 1, 1, 0.45)
        b._vcuiGlyph = g
        b:HookScript("OnEnter", function(self)
            local a = ns.COLORS.accent
            if self._vcuiGlyph then self._vcuiGlyph:SetVertexColor(a.r, a.g, a.b, 0.95) end
        end)
        b:HookScript("OnLeave", function(self)
            if self._vcuiGlyph then self._vcuiGlyph:SetVertexColor(1, 1, 1, 0.45) end
        end)
    end
    b._vcuiGlyph:SetTexture(MICRO_ICON_DIR .. icon .. ".tga")
    b._vcuiGlyph:SetAlpha(1)
    b._vcuiGlyph:Show()
    if b.EnableMouse then b:EnableMouse(true) end
end

local function restoreAdoptedMicro()
    for b, st in pairs(adoptSkin) do
        for r, a in pairs(st.alphas) do if r.SetAlpha then r:SetAlpha(a) end end
        if b._vcuiGlyph then b._vcuiGlyph:Hide() end
        b._vcuiPinTo = nil
        b:SetScale(st.scale)
        b:SetParent(st.parent)
        adoptSkin[b] = nil
    end
end

local function ensureModernMicro()
    if modernMicro then return end
    local f = CreateFrame("Frame", "VuloABMicroModern", UIParent)
    f:SetSize(220, MICRO_H)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)
    f.buttons = {}
    for _, def in ipairs(MODERN_MICRO) do
        if def.adopt then
            local t = _G[def.adopt]
            if t then
                t._vcuiAdopt = def.icon
                adoptMicroButton(t, def.icon)
                t:SetParent(f)
                f.buttons[#f.buttons + 1] = t
            end
        else
        local target
        if def.names then
            for _, n in ipairs(def.names) do if _G[n] then target = _G[n]; break end end
        end
        if target or def.custom then
            local b = CreateFrame("Button", nil, f)
            b:SetSize(MICRO_BTN, MICRO_BTN)
            local ic = b:CreateTexture(nil, "ARTWORK")
            ic:SetPoint("CENTER"); ic:SetSize(MICRO_ICON, MICRO_ICON)
            ic:SetTexture(MICRO_ICON_DIR .. def.icon .. ".tga")
            ic:SetVertexColor(1, 1, 1, 0.45)
            b._icon, b._target, b._custom = ic, target, def.custom
            b._action, b._tip = def.action, def.tip
            b:SetScript("OnEnter", function(self)
                local a = ns.COLORS.accent
                ic:SetVertexColor(a.r, a.g, a.b, 0.95)
                local tip = (self._tip and self._tip()) or (self._target and self._target.tooltipText)
                if tip then
                    ns.UI:ShowTooltip(self, { anchor = "ANCHOR_TOP", title = tip })
                end
            end)
            b:SetScript("OnLeave", function()
                ic:SetVertexColor(1, 1, 1, 0.45)
                ns.UI:HideTooltip()
            end)
            b:SetScript("OnClick", function(self)
                if self._action then
                    self._action(self)
                elseif self._target and self._target.Click then
                    self._target:Click("LeftButton")
                end
            end)
            f.buttons[#f.buttons + 1] = b
        end
        end
    end
    modernMicro = f
end

local function layoutModernMicro()
    if not modernMicro then return end
    local x = MICRO_PAD
    for _, b in ipairs(modernMicro.buttons) do
        if b._vcuiAdopt then
            if not adoptSkin[b] then adoptMicroButton(b, b._vcuiAdopt) end
            local vis = (b:IsShown() or microSeen[b]) and true or false
            b:SetShown(vis)
            if vis then
                b:SetParent(modernMicro)
                local h = b:GetHeight()
                local sc = (h and h > 0) and (MICRO_BTN / h) or 1
                b:SetScale(sc)
                b._vcuiGlyph:SetSize(MICRO_ICON / sc, MICRO_ICON / sc)
                pinFrame(b, "LEFT", modernMicro, "LEFT", x / sc, 0)
                x = x + (b:GetWidth() or MICRO_BTN) * sc + MICRO_GAP
            end
        else
            local t = b._target
            local vis = (b._custom or (t and (t:IsShown() or microSeen[t]))) and true or false
            b:SetShown(vis)
            if vis then
                b:ClearAllPoints()
                b:SetPoint("LEFT", modernMicro, "LEFT", x, 0)
                x = x + MICRO_BTN + MICRO_GAP
            end
        end
    end
    modernMicro:SetSize(math.max(MICRO_BTN, x - MICRO_GAP + MICRO_PAD), MICRO_H)
end

-- alpha-blanked buttons still take clicks, so their mouse must be cut too
local function setMicroChildrenMouse(on)
    local cs = chromeState.micro
    local container = cs and cs.targets and cs.targets[1]
    if not (container and container.GetChildren) then return end
    for _, b in ipairs({ container:GetChildren() }) do
        if b.IsObjectType and b:IsObjectType("Button") and b.EnableMouse then b:EnableMouse(on) end
    end
end

function applyMicroStyle()
    local modern = mod.active and taken and mod.db.microStyle == "modern" and not mod.db.hideMicroMenu
    if modern then
        ensureModernMicro()
        local cs = chromeState.micro
        if cs and cs.holder then
            modernMicro:SetParent(cs.holder)
            modernMicro:SetFrameLevel(cs.holder:GetFrameLevel() + 5)
            modernMicro:ClearAllPoints()
            modernMicro:SetPoint("CENTER", cs.holder, "CENTER", 0, 0)
            layoutModernMicro()
            cs.holder:SetSize(modernMicro:GetSize())
            if cs.mover then
                cs.mover:SetSize(cs.holder:GetWidth(), cs.holder:GetHeight())
                if ns.ApplyMover then ns:ApplyMover(cs.mover) end
            end
        end
        setMicroChildrenMouse(false)
        modernMicro:Show()
    else
        if modernMicro then modernMicro:Hide() end
        restoreAdoptedMicro()
        setMicroChildrenMouse(true)
    end
end

local BAG_BTN_H = 26
local BAG_GLYPHS = {
    MainMenuBarBackpackButton = "micro\\backpack",
    CharacterBag0Slot = "micro\\bag", CharacterBag1Slot = "micro\\bag",
    CharacterBag2Slot = "micro\\bag", CharacterBag3Slot = "micro\\bag",
    KeyRingButton = "micro\\key",
}
local modernBags
local bagSkin = {}

local function ensureModernBags()
    if modernBags then return end
    local f = CreateFrame("Frame", "VuloABBagsModern", UIParent)
    f:SetSize(220, MICRO_H)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)
    modernBags = f
end

local function skinBagButton(b, glyph)
    if not bagSkin[b] then
        bagSkin[b] = { parent = b:GetParent() or UIParent, scale = b:GetScale() or 1,
                       width = b:GetWidth(), wasShown = b:IsShown() }
    end
    local ic = b.icon or _G[(b:GetName() or "") .. "IconTexture"]
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    if ic then ic:SetAlpha(0) end
    if not b._vcuiGlyph then
        local g = b:CreateTexture(nil, "ARTWORK")
        g:SetPoint("CENTER")
        g:SetVertexColor(1, 1, 1, 0.45)
        b._vcuiGlyph = g
        b:HookScript("OnEnter", function(self)
            if self._vcuiGlyph and self._vcuiGlyph:IsShown() then
                local a = ns.COLORS.accent
                self._vcuiGlyph:SetVertexColor(a.r, a.g, a.b, 0.95)
            end
        end)
        b:HookScript("OnLeave", function(self)
            if self._vcuiGlyph then self._vcuiGlyph:SetVertexColor(1, 1, 1, 0.45) end
        end)
    end
    b._vcuiGlyph:SetTexture(MICRO_ICON_DIR .. glyph .. ".tga")
    b._vcuiGlyph:Show()
    local cnt = _G[(b:GetName() or "") .. "Count"]
    if cnt then
        if not bagSkin[b].countPoint then
            local p, rel, rp, px, py = cnt:GetPoint(1)
            bagSkin[b].countPoint = { p or "CENTER", rel or b, rp or "CENTER", px or 0, py or 0 }
        end
        cnt:ClearAllPoints()
        cnt:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    end
end

local function unskinBagButton(b)
    local o = bagSkin[b]
    if not o then return end
    local ic = b.icon or _G[(b:GetName() or "") .. "IconTexture"]
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(1) end
    if ic then ic:SetAlpha(1) end
    if b._vcuiGlyph then b._vcuiGlyph:Hide() end
    local cnt = _G[(b:GetName() or "") .. "Count"]
    if cnt and o.countPoint then
        cnt:ClearAllPoints()
        cnt:SetPoint(unpack(o.countPoint))
    end
    b._vcuiPinTo = nil
    b:SetScale(o.scale)
    if o.width and o.width > 0 then b:SetWidth(o.width) end
    b:SetParent(o.parent)
    -- never re-show the key ring button: its OnShow errors on this client
    if o.wasShown ~= nil and b ~= _G.KeyRingButton then
        b:SetShown(o.wasShown)
    elseif b == _G.KeyRingButton then
        b:Hide()
    end
    bagSkin[b] = nil
end

function applyBagStyle()
    local modern = mod.active and taken and mod.db.bagStyle == "modern" and not mod.db.hideBags
    local shell = _G.BagsBar
    if modern then
        local cs = chromeState.bags
        if not (cs and cs.holder) then return end
        ensureModernBags()
        modernBags:SetParent(cs.holder)
        modernBags:SetFrameLevel(cs.holder:GetFrameLevel() + 5)
        modernBags:ClearAllPoints()
        modernBags:SetPoint("CENTER", cs.holder, "CENTER", 0, 0)
        local x = MICRO_PAD
        local krb = _G.KeyRingButton
        if krb and bagSkin[krb] then unskinBagButton(krb); krb:Hide() end
        for _, n in ipairs(BAG_SLOT_BUTTONS) do
            local b = _G[n]
            if b and n ~= "KeyRingButton" then
                skinBagButton(b, BAG_GLYPHS[n] or "micro\\bag")
                b:SetParent(modernBags)
                local h = b:GetHeight()
                local sc = (h and h > 0) and (BAG_BTN_H / h) or 1
                b:SetScale(sc)
                if b:GetWidth() < (h or 0) then b:SetWidth(h) end
                b._vcuiGlyph:SetSize(MICRO_ICON / sc, MICRO_ICON / sc)
                pinFrame(b, "LEFT", modernBags, "LEFT", x / sc, 0)
                x = x + (b:GetWidth() or BAG_BTN_H) * sc + MICRO_GAP
            end
        end
        local kb = modernBags._keyBtn
        if not kb then
            kb = CreateFrame("Button", nil, modernBags)
            kb:SetSize(BAG_BTN_H, BAG_BTN_H)
            local g = kb:CreateTexture(nil, "ARTWORK")
            g:SetPoint("CENTER"); g:SetSize(MICRO_ICON, MICRO_ICON)
            g:SetTexture(MICRO_ICON_DIR .. "micro\\key.tga")
            g:SetVertexColor(1, 1, 1, 0.45)
            kb:SetScript("OnEnter", function(self)
                local a = ns.COLORS.accent
                g:SetVertexColor(a.r, a.g, a.b, 0.95)
                ns.UI:ShowTooltip(self, { anchor = "ANCHOR_TOP", title = _G.KEYRING or L["Key ring"] })
            end)
            kb:SetScript("OnLeave", function()
                g:SetVertexColor(1, 1, 1, 0.45)
                ns.UI:HideTooltip()
            end)
            kb:SetScript("OnClick", function()
                -- direct toggles only: the Blizzard button's handlers error here
                if _G.ToggleKeyRing then _G.ToggleKeyRing()
                elseif ToggleBag and KEYRING_CONTAINER then ToggleBag(KEYRING_CONTAINER) end
            end)
            modernBags._keyBtn = kb
        end
        kb:ClearAllPoints()
        kb:SetPoint("LEFT", modernBags, "LEFT", x, 0)
        kb:Show()
        x = x + BAG_BTN_H + MICRO_GAP
        modernBags:SetSize(math.max(BAG_BTN_H, x - MICRO_GAP + MICRO_PAD), MICRO_H)
        cs.holder:SetSize(modernBags:GetSize())
        if cs.mover then
            cs.mover:SetSize(cs.holder:GetWidth(), cs.holder:GetHeight())
            if ns.ApplyMover then ns:ApplyMover(cs.mover) end
        end
        if shell then
            if shell._vcuiMouse == nil and shell.IsMouseEnabled then
                shell._vcuiMouse = shell:IsMouseEnabled() and true or false
            end
            shell:EnableMouse(false)
        end
        modernBags:Show()
    else
        if modernBags then modernBags:Hide() end
        if shell and shell._vcuiMouse ~= nil then shell:EnableMouse(shell._vcuiMouse) end
        local restored = false
        for b in pairs(bagSkin) do unskinBagButton(b); restored = true end
        if restored and mod.active and taken and not InCombatLockdown() then
            for _, c in ipairs(CHROME) do if c.key == "bags" then ensureChrome(c) end end
        end
    end
end

local xpBar

local function ensureXPBar()
    if xpBar then return end
    local f = CreateFrame("Frame", "VuloXPBar", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(420, 14)
    f:SetFrameStrata("LOW")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0.55)
        f:SetBackdropBorderColor(0, 0, 0, 0.9)
    end
    local rested = CreateFrame("StatusBar", nil, f)
    rested:SetPoint("TOPLEFT", 1, -1); rested:SetPoint("BOTTOMRIGHT", -1, 1)
    rested:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rested:SetStatusBarColor(0, 0.39, 0.88, 0.45)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetFrameLevel(rested:GetFrameLevel() + 1)
    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER")
    if ns.UI and ns.UI.Font then ns.UI.Font(txt, 10) end
    f.rested, f.bar, f.text = rested, bar, txt
    xpBar = f
    if ns.CreateMover then
        f.mover = ns:CreateMover(f, { db = mod.db.xpbar, key = "ab_xpbar", label = L["XP bar"], scalable = true })
    end
end

local function updateXPBar()
    if not xpBar then return end
    local maxLv = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 70
    if UnitLevel("player") >= maxLv then xpBar:Hide(); return end
    local cur, cap = UnitXP("player"), UnitXPMax("player")
    if not cur or not cap or cap == 0 then return end
    xpBar.bar:SetMinMaxValues(0, cap); xpBar.bar:SetValue(cur)
    local c = mod.db.xpbar.color or { r = 0.58, g = 0, b = 0.55 }
    xpBar.bar:SetStatusBarColor(c.r, c.g, c.b, 1)
    local rest = GetXPExhaustion()
    xpBar.rested:SetMinMaxValues(0, cap)
    xpBar.rested:SetValue(rest and math.min(cap, cur + rest) or 0)
    xpBar.text:SetFormattedText("%d / %d (%d%%)", cur, cap, math.floor(cur / cap * 100 + 0.5))
end

local function applyXPBar()
    local db = mod.db.xpbar
    if not (mod.active and db.on) then
        if xpBar then xpBar:Hide() end
        return
    end
    ensureXPBar()
    xpBar:SetSize(math.max(80, db.width or 420), math.max(6, db.height or 14))
    -- Shared-media texture; absent, empty or UNKNOWN (an uninstalled pack
    -- from another machine) = the flat fill it always had -- MediaStatusbar
    -- would otherwise silently answer with its own different fallback.
    local tex = (db.texture and db.texture ~= "" and ns.MediaStatusbar
        and ns.MediaStatusbar(db.texture, "Interface\\Buttons\\WHITE8X8"))
        or "Interface\\Buttons\\WHITE8X8"
    xpBar.bar:SetStatusBarTexture(tex)
    xpBar.rested:SetStatusBarTexture(tex)
    xpBar.rested:SetStatusBarColor(0, 0.39, 0.88, 0.45)
    xpBar:Show()
    if xpBar.mover then
        xpBar.mover:SetSize(xpBar:GetWidth(), xpBar:GetHeight())
        if ns.ApplyMover then ns:ApplyMover(xpBar.mover) end
    end
    updateXPBar()
end

-- Blizzard's own "extra action bars" setting. Remembered once so turning the
-- module off hands the user back exactly what they had, rather than leaving
-- their bars switched off with no clue why.
local function stashBarToggles()
    if mod.db.blizzBarToggles ~= nil or not GetActionBarToggles then return end
    local ok, b1, b2, b3, b4 = pcall(GetActionBarToggles)
    if not ok then return end
    mod.db.blizzBarToggles = {
        b1 and true or false, b2 and true or false,
        b3 and true or false, b4 and true or false,
    }
end

local function restoreBarToggles()
    local t = mod.db.blizzBarToggles
    if not t or not SetActionBarToggles or InCombatLockdown() then return end
    pcall(SetActionBarToggles, t[1], t[2], t[3], t[4])
    mod.db.blizzBarToggles = nil
end

-- never wipe the container's actionButtons: Blizzard's keybind handlers index it
local function parkFrame(name, keepEvents)
    local f = _G[name]
    if f and hidden[f] == nil then
        hidden[f] = f:GetParent() or UIParent
        if not keepEvents then f:UnregisterAllEvents() end
        ;(f.HideBase or f.Hide)(f)
        f:SetParent(shadow)
    end
end

local function hideBlizzard()
    ensureShadow()
    parkFrame("MainActionBar", true)
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if b then b:UnregisterAllEvents(); b:SetAttributeNoHandler("statehidden", true); b:Hide() end
    end
    for _, n in ipairs(MAIN_ART) do local t = _G[n]; if t then t:Hide() end end
    local art = _G.MainMenuBarArtFrame
    if art then art:SetAlpha(0) end
    -- Turn Blizzard's extra bars off the way Blizzard does it. Touching their
    -- buttons directly (the old EnableMouse loop) taints them, and the taint
    -- surfaces later as a blocked SetShown from the button's own OnEvent while
    -- in combat. Switched off at the source there is nothing left to taint, no
    -- invisible click target and no update logic running.
    stashBarToggles()
    if SetActionBarToggles and not InCombatLockdown() then
        pcall(SetActionBarToggles, false, false, false, false)
    end
    for _, n in ipairs(MULTIBAR_FRAMES) do
        local f = _G[n]
        -- belt and braces for a bar the toggle call could not reach; the
        -- container itself is ours to fade, its buttons are not
        if f then
            f:SetAlpha(0)
            if f.EnableMouse then f:EnableMouse(false) end
        end
    end
    -- pet container: reparent only, keep events and do not Hide, or its buttons stop updating
    local pab = _G.PetActionBar or _G.PetActionBarFrame
    if pab and hidden[pab] == nil then
        hidden[pab] = pab:GetParent() or UIParent
        pab:SetParent(shadow)
    end
    applyStatusBar()
    applyPerfBar()
    applyMicroBags()
end

local function unpark(name)
    local f = _G[name]
    if f and hidden[f] ~= nil then
        f:SetParent(hidden[f])
        if f.ShowBase then f:ShowBase() else f:Show() end
        hidden[f] = nil
    end
end

local function refreshFade(desc)
    local st = state[desc.key]
    if not (mod.active and st and st.frame) then return end
    local db = barDB(desc.key)
    local base = (db.alpha or 100) / 100
    if db.visibility == "mouseover" then
        st.tgtAlpha = st.hovered and base or (db.fadeAlpha or 0) / 100
    else
        st.tgtAlpha = base
    end
    if abs(st.curAlpha - st.tgtAlpha) > 0.001 and updater then updater:Show() end
end

local function setHovered(on)
    for _, d2 in ipairs(BARS) do
        local st2 = state[d2.key]
        if st2 and barDB(d2.key).visibility == "mouseover" then
            st2.hovered = on
            refreshFade(d2)
        end
    end
end

local function hookHover(desc)
    local st = state[desc.key]
    if not st then return end
    for _, b in ipairs(st.buttons) do
        if not b.vHovered then
            b.vHovered = true
            b:HookScript("OnEnter", function()
                if not (mod.active and barDB(desc.key).visibility == "mouseover") then return end
                if mod.db.hoverShowsAll then setHovered(true)
                else st.hovered = true; refreshFade(desc) end
            end)
            b:HookScript("OnLeave", function()
                if not (mod.active and barDB(desc.key).visibility == "mouseover") then return end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.1, function()
                        if not (mod.active and st.frame) or st.frame:IsMouseOver() then return end
                        if mod.db.hoverShowsAll then setHovered(false)
                        else st.hovered = false; refreshFade(desc) end
                    end)
                else
                    if mod.db.hoverShowsAll then setHovered(false)
                    else st.hovered = false; refreshFade(desc) end
                end
            end)
        end
    end
end

local function ensureUpdater()
    if updater then return end
    updater = CreateFrame("Frame"); updater:Hide()
    updater:SetScript("OnUpdate", function(self, elapsed)
        if not mod.active then self:Hide(); return end
        local step = (mod.db.fadeSpeed and mod.db.fadeSpeed > 0) and (elapsed / mod.db.fadeSpeed) or 1
        local busy = false
        for _, desc in ipairs(BARS) do
            local st = state[desc.key]
            if st and st.frame then
                if abs(st.curAlpha - st.tgtAlpha) > 0.004 then
                    st.curAlpha = (st.curAlpha < st.tgtAlpha) and math.min(st.tgtAlpha, st.curAlpha + step)
                        or math.max(st.tgtAlpha, st.curAlpha - step)
                    st.frame:SetAlpha(st.curAlpha); busy = true
                elseif st.curAlpha ~= st.tgtAlpha then
                    st.curAlpha = st.tgtAlpha; st.frame:SetAlpha(st.curAlpha)
                end
            end
        end
        if not busy then self:Hide() end
    end)
end

-- insecure Show/Hide, so out of combat only
local gridForced = false
local function refreshEmpty(desc)
    if InCombatLockdown() then return end
    if desc.kind ~= "own" and desc.kind ~= "reuse" then return end
    local st = state[desc.key]
    if not st then return end
    local show = gridForced or barDB(desc.key).showEmpty ~= false
    for _, b in ipairs(st.buttons) do
        if show then
            b:Show()
        else
            b:SetShown(HasAction(b:GetAttribute("action") or 0))
        end
    end
end
local function refreshEmptyAll()
    for _, desc in ipairs(BARS) do refreshEmpty(desc) end
end

local lookTicker

local function forAllButtons(fn)
    for _, desc in ipairs(BARS) do
        local st = state[desc.key]
        if st then
            for _, b in ipairs(st.buttons) do fn(b, desc) end
        end
    end
end

local function buttonIcon(b)
    local nm = b.GetName and b:GetName()
    return b.icon or b.Icon or (nm and _G[nm .. "Icon"])
end

local function ttHook()
    local m = mod.db.tooltipMode
    if mod.active and (m == "never" or (m == "combat" and InCombatLockdown())) then
        ns.UI:HideTooltip()
    end
end

local function lookTick()
    local desat = mod.db.desatOnCd
    local range = mod.db.rangeColoring
    local dim = (mod.db.cdAlpha or 100) / 100
    local c = mod.db.rangeColor or { r = 0.8, g = 0.15, b = 0.15 }
    for _, desc in ipairs(BARS) do
        if desc.kind == "own" or desc.kind == "reuse" then
            local st = state[desc.key]
            if st then
                for _, b in ipairs(st.buttons) do
                    local action = b:GetAttribute("action")
                    local icon = buttonIcon(b)
                    if icon and action and action > 0 and HasAction(action) then
                        if desat or dim < 1 then
                            local start, dur = GetActionCooldown(action)
                            local onCd = (start or 0) > 0 and (dur or 0) > 1.5
                            if desat and icon.SetDesaturated then icon:SetDesaturated(onCd) end
                            if dim < 1 then icon:SetAlpha(onCd and dim or 1) end
                        end
                        if range then
                            if IsActionInRange(action) == false then
                                icon:SetVertexColor(c.r, c.g, c.b)
                            else
                                local usable, noMana = IsUsableAction(action)
                                if usable then icon:SetVertexColor(1, 1, 1)
                                elseif noMana then icon:SetVertexColor(0.5, 0.5, 1)
                                else icon:SetVertexColor(0.4, 0.4, 0.4) end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Pressed / hover tinting (the animations tab). Vertex color on the buttons'
-- own pushed and highlight textures -- textures are unprotected on secure
-- buttons, and clearing back to white undoes it without a reload.
local function applyInteractions()
    local myClass = select(2, UnitClass("player"))
    local cc = myClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[myClass]
    forAllButtons(function(b)
        local pt = b.GetPushedTexture and b:GetPushedTexture()
        if pt then
            if mod.active and mod.db.pushedTint then
                local c = (mod.db.pushedClassColor and cc) or mod.db.pushedColor
                    or { r = 1, g = 0.82, b = 0 }
                pt:SetVertexColor(c.r, c.g, c.b, 1)
            else
                pt:SetVertexColor(1, 1, 1, 1)
            end
        end
        local ht = b.GetHighlightTexture and b:GetHighlightTexture()
        if ht then
            if mod.active and mod.db.highlightTint then
                local c = (mod.db.highlightClassColor and cc) or mod.db.highlightColor
                    or { r = 1, g = 1, b = 1 }
                ht:SetVertexColor(c.r, c.g, c.b, 1)
            else
                ht:SetVertexColor(1, 1, 1, 1)
            end
        end
    end)
end

local function applyLook()
    local swipe = (mod.db.cdSwipe or 80) / 100
    local sc = mod.db.cdSwipeColor or { r = 0, g = 0, b = 0 }
    forAllButtons(function(b)
        if b.cooldown and b.cooldown.SetSwipeColor then
            b.cooldown:SetSwipeColor(sc.r or 0, sc.g or 0, sc.b or 0, swipe)
        end
        if not b._vcuiTT and b.HookScript then
            b._vcuiTT = true
            b:HookScript("OnEnter", ttHook)
        end
        local icon = buttonIcon(b)
        if icon then
            if not mod.db.desatOnCd and icon.SetDesaturated then icon:SetDesaturated(false) end
            if not mod.db.rangeColoring then icon:SetVertexColor(1, 1, 1) end
            if (mod.db.cdAlpha or 100) >= 100 then icon:SetAlpha(1) end
        end
    end)
    local need = mod.db.desatOnCd or mod.db.rangeColoring or (mod.db.cdAlpha or 100) < 100
    if need then
        if not lookTicker then
            lookTicker = CreateFrame("Frame")
            lookTicker._acc = 0
            lookTicker:SetScript("OnUpdate", function(self, elapsed)
                self._acc = self._acc + elapsed
                if self._acc < 0.2 then return end
                self._acc = 0
                if mod.active and taken then lookTick() end
            end)
        end
        lookTicker:Show()
    elseif lookTicker then
        lookTicker:Hide()
    end
    applyInteractions()
end

local function applyBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    local on = barDB(desc.key).on
    if on and desc.kind == "stance" and (GetNumShapeshiftForms() or 0) == 0 then on = false end
    if desc.kind == "stance" then setFramesHidden(STANCE_HIDE, on) end
    if on then
        st.frame:Show()
        layoutBar(desc)
        if desc.kind == "stance" then updateStance()
        elseif desc.kind ~= "pet" then pageBar(desc) end
        visBar(desc); bindBar(desc); refreshEmpty(desc)
        hookHover(desc); refreshFade(desc)
    else
        if desc.kind == "own" then UnregisterStateDriver(st.frame, "page") end
        UnregisterStateDriver(st.frame, "userDisplay")
        ClearOverrideBindings(st.frame)
        st.frame:Hide()
    end
end

local function takeOver()
    if taken or InCombatLockdown() then return end
    ensureShadow()
    ensureBar(BAR_BY_KEY.main)
    for _, desc in ipairs(BARS) do ensureBar(desc) end
    hideBlizzard()
    for _, desc in ipairs(BARS) do applyBar(desc) end
    applyChrome(); applyXPBar(); applyLook()
    taken = true
    -- these gate on `taken`, so they must run again now that it is set
    applyMicroBags(); applyMicroStyle(); applyBagStyle()
    if ns.ReskinActionButtons then ns.ReskinActionButtons() end
end

-- Undo hideBlizzard's stop on the main bar's twelve buttons.
--
-- hideBlizzard does three things to each: UnregisterAllEvents, statehidden and
-- Hide. Measured on a live client, only TWO of them have any effect -- a HEALTHY
-- ActionButton1 has none of the ACTIONBAR_* events registered on itself, because
-- they live on the shared ActionBarActionEventsFrame. So UnregisterAllEvents
-- removed nothing, and re-registering would mean inventing a list nobody can
-- read back. statehidden and Hide are what stop the button, and they are what
-- comes back here -- statehidden to nil, which is what a fresh button reports.
--
-- Then Blizzard's own re-assert, so the bar lands in the state a /reload would
-- leave it in rather than one arranged by hand.
local function restoreMainButtons()
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if b then
            if b.SetAttributeNoHandler then b:SetAttributeNoHandler("statehidden", nil) end
            b:Show()
        end
    end
    -- pcall for the same reason the anchor replay has one: this runs inside
    -- restore(), and nothing in here is worth stranding the teardown over.
    if type(_G.ActionBarController_UpdateAll) == "function" then
        pcall(_G.ActionBarController_UpdateAll)
    end
end

local function restore()
    if not taken then return end
    if InCombatLockdown() then pendingRestore = true; return end
    for _, desc in ipairs(BARS) do
        local st = state[desc.key]
        if st and st.frame then
            UnregisterStateDriver(st.frame, "page")
            UnregisterStateDriver(st.frame, "userDisplay")
            ClearOverrideBindings(st.frame)
            st.frame:Hide()
        end
    end
    for _, n in ipairs(MULTIBAR_FRAMES) do
        local f = _G[n]
        if f then
            f:SetAlpha(1)
            if f.EnableMouse then f:EnableMouse(true) end
        end
    end
    restoreBarToggles()
    unpark("MainActionBar")
    unpark("PetActionBar"); unpark("PetActionBarFrame")
    for _, n in ipairs(MAIN_ART) do local t = _G[n]; if t then t:Show() end end
    local art = _G.MainMenuBarArtFrame
    if art then art:SetAlpha(1) end
    local pf = _G.MainMenuBarPerformanceBarFrame
    if pf then pf:SetAlpha(1) end
    local pb = _G.MainMenuBarPerformanceBarFrameButton
    if pb then pb:SetAlpha(1); if pb.EnableMouse then pb:EnableMouse(true) end end
    if modernMicro then modernMicro:Hide() end
    restoreAdoptedMicro()
    setMicroChildrenMouse(true)
    if modernBags then modernBags:Hide() end
    for b in pairs(bagSkin) do unskinBagButton(b) end
    local bagShell = _G.BagsBar
    if bagShell and bagShell._vcuiMouse ~= nil then bagShell:EnableMouse(bagShell._vcuiMouse) end
    setFramesHidden(MICRO_FRAMES, false)
    setFramesHidden(BAG_FRAMES, false)
    setFramesHidden(STANCE_HIDE, false)
    restoreChrome()
    if xpBar then xpBar:Hide() end
    local stbm = _G.StatusTrackingBarManager
    if stbm then stbm:Show(); if stbm.RegisterAllEvents then stbm:RegisterAllEvents() end end
    for _, n in ipairs(LEGACY_BARS) do local f = _G[n]; if f then f:Show() end end
    taken = false
    -- LAST, deliberately. Everything above -- showing Blizzard's bars, clearing
    -- `taken` -- has already happened, so however this call behaves it cannot
    -- strand the teardown. That is the lesson from the anchor attempt.
    restoreMainButtons()
    -- Clears the pushed/highlight tints (mod.active is already false here) --
    -- insurance for the reparented pet buttons, which would carry the tint
    -- back to Blizzard's bar if a later change hands them back on disable.
    applyInteractions()
    ns:Print(L["|cffffcc00Action Bars disabled — type /reload to fully restore the default bars.|r"])
end

local function applyAll()
    if not mod.active then return end
    if InCombatLockdown() then return end   -- flushed on PLAYER_REGEN_ENABLED
    if not taken then
        takeOver()
    else
        for _, desc in ipairs(BARS) do applyBar(desc) end
        applyChrome(); applyXPBar(); applyLook(); applyMicroStyle(); applyBagStyle()
    end
end

local editForced = false
local function onEditMode(active)
    if not (mod.active and taken) or InCombatLockdown() then return end
    if active then
        editForced = true
        for _, desc in ipairs(BARS) do
            local st = state[desc.key]
            if st and st.frame then
                UnregisterStateDriver(st.frame, "userDisplay")
                st.frame:SetAlpha(1)
                st.frame:Show()
            end
        end
        if xpBar then xpBar:Show() end
    elseif editForced then
        editForced = false
        applyAll()
    end
end
if ns.RegisterEditModeHook then ns:RegisterEditModeHook(onEditMode) end

local function openQuickKeybind()
    if InCombatLockdown() then ns:Print(L["Not possible in combat."]); return end
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_QuickKeybind")
    elseif _G.LoadAddOn then pcall(_G.LoadAddOn, "Blizzard_QuickKeybind") end
    local qkb = _G.QuickKeybindFrame
    if not qkb then
        ns:Print(L["|cffff5555Quick keybind mode is not available on this client.|r"])
        return
    end
    if not qkb._vcuiHooked then
        qkb._vcuiHooked = true
        qkb:HookScript("OnShow", function() if mod.active then onEditMode(true) end end)
        qkb:HookScript("OnHide", function() if mod.active then onEditMode(false) end end)
    end
    qkb:Show()
end
ns.OpenQuickKeybind = openQuickKeybind

ns:RegisterSlash({ key = "KEYBIND", commands = { "/vkb" },
    desc = "Assign keys by hovering a button.",
    module = "actionbars",
})
ns.Slash.KEYBIND = openQuickKeybind

local function onRegen()
    if pendingRestore then pendingRestore = false; restore(); return end
    applyAll()
end
local function onWorld() applyAll() end
local function onZone() if mod.active and taken and not InCombatLockdown() then
    for _, desc in ipairs(BARS) do visBar(desc) end
end end
local function onForms()
    if mod.active and not InCombatLockdown() and taken then
        pageBar(BAR_BY_KEY.main); applyBar(BAR_BY_KEY.stance)
    end
end
local function onPet()
    if mod.active and not InCombatLockdown() and taken then applyBar(BAR_BY_KEY.pet) end
end
local function onStance() if mod.active and taken then updateStance() end end
local function onXP() if mod.active and taken then updateXPBar() end end
local function onGridShow() if mod.active and taken then gridForced = true;  refreshEmptyAll() end end
local function onGridHide() if mod.active and taken then gridForced = false; refreshEmptyAll() end end
local function onSlot()     if mod.active and taken then refreshEmptyAll() end end
local function onBindings()
    if mod.active and not InCombatLockdown() then
        for _, desc in ipairs(BARS) do bindBar(desc) end
    end
end

function mod:OnEnable()
    pendingRestore = false
    -- migrate old per-bar scale stored as percent to the mover's multiplier
    for _, desc in ipairs(BARS) do
        local db = barDB(desc.key)
        if db then
            if db.scale and db.scale > 3 then db.scale = db.scale / 100 end
            if not db.scale or db.scale <= 0 then db.scale = 1 end
        end
    end
    ensureUpdater()
    mod:RegisterEvent("PLAYER_REGEN_ENABLED", onRegen)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", onWorld)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", onForms)
    mod:RegisterEvent("UPDATE_BINDINGS", onBindings)
    mod:RegisterEvent("PET_BAR_UPDATE", onPet)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_FORM", onStance)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_USABLE", onStance)
    mod:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN", onStance)
    mod:RegisterEvent("PLAYER_XP_UPDATE", onXP)
    mod:RegisterEvent("PLAYER_LEVEL_UP", onXP)
    mod:RegisterEvent("UPDATE_EXHAUSTION", onXP)
    mod:RegisterEvent("ACTIONBAR_SHOWGRID", onGridShow)
    mod:RegisterEvent("ACTIONBAR_HIDEGRID", onGridHide)
    mod:RegisterEvent("ACTIONBAR_SLOT_CHANGED", onSlot)
    mod:RegisterEvent("ZONE_CHANGED_NEW_AREA", onZone)
    applyAll()
end

function mod:OnDisable()
    if updater then updater:Hide() end
    if lookTicker then lookTicker:Hide() end
    if InCombatLockdown() then
        pendingRestore = true
        ns:Print(L["|cffff5555Action Bars: leaving combat to restore Blizzard's bars…|r"])
        local f = CreateFrame("Frame"); f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents(); self:SetScript("OnEvent", nil)
            if not mod.active and pendingRestore then pendingRestore = false; restore() end
        end)
    else
        restore()
    end
end

local function reapply() if mod.active then applyAll() end end


local function moverApply(key)
    local st = state[key]
    if st and st.mover and ns.ApplyMover then ns:ApplyMover(st.mover) end
end

local PAGE_VALUES
ns.OnLocaleReady(function()
PAGE_VALUES = {
    { value = 0, text = "—" },
    { value = 6, text = L["Action Bar 2"] },
    { value = 5, text = L["Action Bar 3"] },
    { value = 3, text = L["Action Bar 4"] },
    { value = 4, text = L["Action Bar 5"] },
}
end)

local function pagingRows()
    local function pageDrop(label, dbKey)
        return { type = "dropdown", label = label, width = 220, values = PAGE_VALUES,
            get = function() return barDB("main")[dbKey] or 0 end,
            set = function(_, v) barDB("main")[dbKey] = v; reapply() end }
    end
    return { type = "section", title = L["Modifier paging"], items = {
        { type = "desc",
          text = L["|cffaaaaaaWhile the key is held (or your target matches), the main bar shows the chosen bar's abilities instead. Fully secure — works in combat.|r"] },
        pageDrop(L["Shift held"], "pageShift"),
        pageDrop(L["Ctrl held"],  "pageCtrl"),
        pageDrop(L["Alt held"],   "pageAlt"),
        pageDrop(L["Friendly target"], "pageHelp"),
        pageDrop(L["Hostile target"],  "pageHarm"),
    } }
end

-- The layout fields the "apply to all bars" button carries over; perRow is
-- clamped to each destination's button count on the way, and table values
-- (the background colour) are copied by value -- a shared reference would
-- alias every bar's colour to one table.
local LAYOUT_COPY_KEYS = { "scale", "iconSize", "perRow", "spacing",
                           "vertical", "reverse", "growH", "growV",
                           "bgOn", "bgColor", "bgAlpha", "bgPad" }

-- The rows of ONE bar, as OPEN sections. The page shows a single bar at a
-- time, chosen in the pinned header above the scroll area (reference layout,
-- user request 31.07.2026) -- the old shape was eight collapsed sections,
-- each with everything behind a gear.
local function barModeSections(desc)
    local key = desc.key
    return {
        { type = "section", title = L["Visibility"], items = {
            { type = "checkbox", label = L["Enabled"],
              get = function() return barDB(key).on end,
              set = function(_, v) barDB(key).on = v; reapply() end },
            { type = "dropdown", label = L["Visibility"], width = 220, values = ns.VisibilityValues(),
              get = function() return barDB(key).visibility end,
              set = function(_, v) barDB(key).visibility = v; reapply() end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "dropdown", label = L["Group visibility"], width = 220,
                  values = ns.GroupVisValues(),
                  get = function() return barDB(key).groupVis or "any" end,
                  set = function(_, v) barDB(key).groupVis = v; reapply() end },
                { type = "checkbox", label = L["Only in instances"],
                  get = function() return barDB(key).onlyInstances end,
                  set = function(_, v) barDB(key).onlyInstances = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Hide when mounted"],
                  get = function() return barDB(key).hideMounted end,
                  set = function(_, v) barDB(key).hideMounted = v; reapply() end },
                { type = "checkbox", label = L["Hide without target"],
                  get = function() return barDB(key).hideNoTarget end,
                  set = function(_, v) barDB(key).hideNoTarget = v; reapply() end },
                { type = "checkbox", label = L["Hide without enemy target"],
                  get = function() return barDB(key).hideNoEnemyTarget end,
                  set = function(_, v) barDB(key).hideNoEnemyTarget = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Bar opacity"], min = 10, max = 100, step = 5, width = 150,
                  get = function() return barDB(key).alpha or 100 end,
                  set = function(_, v) barDB(key).alpha = v; reapply() end },
                { type = "checkbox", label = L["Show empty buttons"],
                  tooltip = L["Off hides empty slots; they reappear automatically while you drag an ability."],
                  get = function() return barDB(key).showEmpty ~= false end,
                  set = function(_, v) barDB(key).showEmpty = v; reapply() end },
                { type = "checkbox", label = L["Click through"],
                  tooltip = L["The bar ignores the mouse entirely — clicks go through it. Keybinds still work."],
                  get = function() return barDB(key).clickThrough end,
                  set = function(_, v) barDB(key).clickThrough = v; reapply() end },
            } },
        } },

        { type = "section", title = L["Layout"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Scale"], min = 50, max = 150, step = 1, width = 150,
                  get = function() return math.floor((barDB(key).scale or 1) * 100 + 0.5) end,
                  set = function(_, v) barDB(key).scale = v / 100; moverApply(key) end },
                { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1, width = 150,
                  tooltip = L["0 = use the game's default size."],
                  get = function() return barDB(key).iconSize or 0 end,
                  set = function(_, v) barDB(key).iconSize = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Buttons per row"], min = 1, max = desc.count, step = 1, width = 150,
                  get = function() return barDB(key).perRow end,
                  set = function(_, v) barDB(key).perRow = v; reapply() end },
                { type = "slider", label = L["Button spacing"], min = 0, max = 20, step = 1, width = 150,
                  get = function() return barDB(key).spacing end,
                  set = function(_, v) barDB(key).spacing = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Vertical layout"],
                  get = function() return barDB(key).vertical end,
                  set = function(_, v) barDB(key).vertical = v; reapply() end },
                { type = "checkbox", label = L["Reverse order"],
                  get = function() return barDB(key).reverse end,
                  set = function(_, v) barDB(key).reverse = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "segmented", label = L["Grow from"], width = 200,
                  values = {
                      { value = "right", text = L["Left edge (rightwards)"] },
                      { value = "left",  text = L["Right edge (leftwards)"] },
                  },
                  get = function() return barDB(key).growH or "right" end,
                  set = function(_, v) barDB(key).growH = v; reapply() end },
                { type = "segmented", label = L["Rows grow"], width = 200,
                  values = {
                      { value = "down", text = L["Downwards"] },
                      { value = "up",   text = L["Upwards"] },
                  },
                  get = function() return barDB(key).growV or "down" end,
                  set = function(_, v) barDB(key).growV = v; reapply() end },
            } },
            { type = "checkbox", label = L["Enable bar background"],
              tooltip = L["A flat colour panel behind the bar, sized with it."],
              get = function() return barDB(key).bgOn end,
              set = function(_, v) barDB(key).bgOn = v; applyBarBg(key) end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "color", label = L["Colour"], width = 120,
                        get = function() return barDB(key).bgColor end,
                        set = function(r, g, b)
                            barDB(key).bgColor = { r = r, g = g, b = b }
                            applyBarBg(key)
                        end },
                      { type = "slider", label = L["Background opacity"], min = 5, max = 100, step = 5, width = 150,
                        get = function() return barDB(key).bgAlpha or 60 end,
                        set = function(_, v) barDB(key).bgAlpha = v; applyBarBg(key) end },
                      { type = "slider", label = L["Padding"], min = 0, max = 16, step = 1, width = 150,
                        get = function() return barDB(key).bgPad or 4 end,
                        set = function(_, v) barDB(key).bgPad = v; applyBarBg(key) end },
                  } },
              } },
            { type = "button", label = L["Apply layout to all bars"], width = 260,
              tooltip = L["Copies this bar's layout - scale, icon size, buttons per row, spacing, direction - to every other bar."],
              onClick = function()
                  local src = barDB(key)
                  for _, d in ipairs(BARS) do
                      if d.key ~= key then
                          local dst = barDB(d.key)
                          for _, k in ipairs(LAYOUT_COPY_KEYS) do
                              local v = src[k]
                              if type(v) == "table" then
                                  dst[k] = { r = v.r, g = v.g, b = v.b }
                              else
                                  dst[k] = v
                              end
                          end
                          if dst.perRow then dst.perRow = math.min(dst.perRow, d.count or 12) end
                          moverApply(d.key)
                          applyBarBg(d.key)
                      end
                  end
                  reapply()
                  ns:Print(L["Layout applied to all bars."])
              end },
        } },

        { type = "section", title = L["Text sizes"], items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Hide keybind text"],
                  get = function() return barDB(key).hideKeybind end,
                  set = function(_, v) barDB(key).hideKeybind = v; reapply() end },
                { type = "checkbox", label = L["Hide macro text"],
                  get = function() return barDB(key).hideMacro end,
                  set = function(_, v) barDB(key).hideMacro = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Keybind text size"], min = 0, max = 24, step = 1, width = 150,
                  tooltip = L["0 = default size."],
                  get = function() return barDB(key).textKeybindSize or 0 end,
                  set = function(_, v) barDB(key).textKeybindSize = v; reapply() end },
                { type = "slider", label = L["Macro text size"], min = 0, max = 24, step = 1, width = 150,
                  tooltip = L["0 = default size."],
                  get = function() return barDB(key).textMacroSize or 0 end,
                  set = function(_, v) barDB(key).textMacroSize = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Count text size"], min = 0, max = 24, step = 1, width = 150,
                  tooltip = L["0 = default size."],
                  get = function() return barDB(key).textCountSize or 0 end,
                  set = function(_, v) barDB(key).textCountSize = v; reapply() end },
                { type = "slider", label = L["Cooldown text size"], min = 0, max = 24, step = 1, width = 150,
                  tooltip = L["0 = default size. Requires cooldown numbers to be enabled in the game options."],
                  get = function() return barDB(key).textCooldownSize or 0 end,
                  set = function(_, v) barDB(key).textCooldownSize = v; reapply() end },
            } },
        } },
    }
end

-- ---------------------------------------------------------------------------
-- Pinned page header (Modern mode only): the bar picker plus a live preview
-- of the chosen bar, in sight at every scroll position -- the reference
-- layout the user pointed at. The preview frames are MOCKS fed by the real
-- buttons' icon textures; reparenting secure buttons into a header would be
-- a taint trap for nothing.
local selectedBar = "main"   -- UI state, not a setting
local headerFrame
local PV_ICON, PV_GAP, PV_MAXROWS = 26, 3, 3
local HEADER_TOP = 38        -- the picker row above the preview

local function previewSource(key, i)
    if key == "main"   then return _G["VuloActionButton" .. i] end
    if key == "pet"    then return _G["PetActionButton" .. i] end
    if key == "stance" then return _G["VuloAB_stanceB" .. i] end
    return _G["VuloAB_" .. key .. "B" .. i]
end

-- The keybind shown on a preview tile: the real button's hotkey text where it
-- exists (already abbreviated by the game), else the raw binding.
local function previewBinding(d, i, real)
    local hk = real and (real.HotKey or _G[(real:GetName() or "") .. "HotKey"])
    local t = hk and hk.GetText and hk:GetText()
    if t and t ~= "" and t ~= (_G.RANGE_INDICATOR or "\226\128\162") then
        return t
    end
    if d.cmd then
        local b = GetBindingKey(d.cmd:format(i))
        if b then
            local ok, txt = pcall(GetBindingText, b, "KEY_", 1)
            return (ok and txt) or b
        end
    end
end

local function updatePreview()
    local f = headerFrame
    if not f then return 0 end
    local d = BAR_BY_KEY[selectedBar] or BAR_BY_KEY.main
    local db = barDB(d.key)
    local n = math.min(d.count or 12, 12)
    local perRow = math.max(1, math.min(db.perRow or n, n))
    local cols, rows = math.min(n, perRow), math.ceil(n / perRow)
    -- visual grid after the vertical swap
    local vCols = db.vertical and rows or cols
    local vRows = db.vertical and cols or rows
    local shown = math.min(vRows, PV_MAXROWS)
    local cell  = PV_ICON + PV_GAP
    local w, h  = vCols * cell - PV_GAP, shown * cell - PV_GAP
    f.anchor:SetSize(math.max(w, 1), math.max(h, 1))
    for i = 1, 12 do
        local pb = f.icons[i]
        if i <= n then
            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            if db.vertical then col, row = row, col end
            if row >= shown then
                pb:Hide()
            else
                pb:Show()
                pb:ClearAllPoints()
                pb:SetPoint("TOPLEFT", f.anchor, "TOPLEFT", col * cell, -row * cell)
                local real = previewSource(d.key, i)
                local tex = real and real.icon and real.icon.GetTexture
                    and real.icon:GetTexture()
                if not tex and real then
                    local byName = _G[(real:GetName() or "") .. "Icon"]
                    tex = byName and byName.GetTexture and byName:GetTexture()
                end
                if tex then
                    pb.icon:SetTexture(tex)
                    pb.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
                    pb.icon:SetVertexColor(1, 1, 1, 1)
                else
                    pb.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
                    pb.icon:SetTexCoord(0, 1, 0, 1)
                    pb.icon:SetVertexColor(0.10, 0.10, 0.13, 1)
                end
                pb.keyFS:SetText(previewBinding(d, i, real) or "")
            end
        else
            pb:Hide()
        end
    end
    return HEADER_TOP + h + 12
end

local function buildHeader(host)
    if headerFrame then return headerFrame end
    local f = CreateFrame("Frame", nil, host)

    local vals = {}
    for _, d in ipairs(BARS) do
        vals[#vals + 1] = { value = d.key, text = L[d.label] }
    end
    local dd = ns.UI:CreateDropdown(f, {
        width = 280,
        values = vals,
        get = function() return selectedBar end,
        set = function(_, v)
            selectedBar = v
            ns.UI:BuildOptionsPage("actionbars", ns.UI.currentTab)
        end,
    })
    dd:SetPoint("TOP", f, "TOP", 0, -4)

    f.anchor = CreateFrame("Frame", nil, f)
    f.anchor:SetPoint("TOP", f, "TOP", 0, -HEADER_TOP)
    f.icons = {}
    for i = 1, 12 do
        -- A Button, not a Frame: the tiles navigate (reference behavior) --
        -- click scrolls to the layout section, right-click to the text sizes.
        local pb = CreateFrame("Button", nil, f.anchor)
        pb:SetSize(PV_ICON, PV_ICON)
        pb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pb:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                ns.UI:ScrollToSection(L["Text sizes"])
            else
                ns.UI:ScrollToSection(L["Layout"])
            end
        end)
        pb:SetScript("OnEnter", function(self)
            ns.UI:ShowTooltip(self, L["Click: layout settings. Right-click: text sizes."])
        end)
        pb:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
        local bg = pb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        local ic = pb:CreateTexture(nil, "ARTWORK")
        ic:SetPoint("TOPLEFT", 1, -1)
        ic:SetPoint("BOTTOMRIGHT", -1, 1)
        pb.icon = ic
        local ks = pb:CreateFontString(nil, "OVERLAY")
        ns.UI.Font(ks, 9, "OUTLINE")
        ks:SetPoint("TOPRIGHT", pb, "TOPRIGHT", -1, -1)
        pb.keyFS = ks
        f.icons[i] = pb
    end

    -- Abilities and pages change under the preview; a slow tick is cheaper
    -- and safer than hooking every applier.
    local acc = 0
    f:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc > 0.3 then acc = 0; updatePreview() end
    end)

    headerFrame = f
    return f
end

function mod.BuildPageHeader(host, tabId)
    -- The picker and preview belong to the bars themselves, not the chrome tab.
    if (tabId ~= nil and tabId ~= "display" and tabId ~= "default")
       or not ns:IsModuleEnabled("actionbars") then
        if headerFrame then headerFrame:Hide() end
        return 0
    end
    local f = buildHeader(host)
    f:SetParent(host)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT",  host, "TOPLEFT",  14, 0)
    f:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, 0)
    f:Show()
    -- Two top anchors define the width but NO height, and a frame without a
    -- resolvable rect draws none of its children -- the header reserved its
    -- space and stayed invisible until this line.
    local h = updatePreview()
    f:SetHeight(h)
    return h
end

function mod:GetOptions(tabId)
    local modernOn = ns:IsModuleEnabled("actionbars")

    -- The chrome around the bars: micro menu, bag bar, XP bar. Its appliers
    -- run only while the module is on, and the page says so instead of
    -- offering rows that silently do nothing.
    if tabId == "chrome" then
        local items = {}
        if not modernOn then
            items[#items + 1] = { type = "desc",
                text = L["|cffaaaaaaOnly active in Modern mode (Bar Display tab).|r"] }
        end
        items[#items + 1] = { type = "checkbox", label = L["Hide Blizzard's XP / reputation bar"],
            tooltip = L["Removes the leftover blue experience / reputation bar under the action bar."],
            get = function() return mod.db.hideStatusBars end,
            set = function(_, v) mod.db.hideStatusBars = v; if mod.active then applyStatusBar() end end }
        items[#items + 1] = { type = "checkbox", label = L["Hide the FPS / latency bar"],
            tooltip = L["Hides Blizzard's small green performance (FPS / latency) bar."],
            get = function() return mod.db.hidePerfBar end,
            set = function(_, v) mod.db.hidePerfBar = v; if mod.active then applyPerfBar() end end }
        items[#items + 1] = { type = "checkbox", label = L["Hide the micro menu"],
            tooltip = L["Hides the row of menu buttons (character, spellbook, …)."],
            get = function() return mod.db.hideMicroMenu end,
            set = function(_, v) mod.db.hideMicroMenu = v; if mod.active then applyMicroBags(); applyMicroStyle() end end }
        items[#items + 1] = { type = "dropdown", label = L["Micro menu style"], width = 280,
            tooltip = L["Modern replaces Blizzard's buttons with a flat dark icon strip in the VuloUI look. Clicks and tooltips stay identical."],
            values = {
                { value = "classic", text = L["Classic (Blizzard buttons)"] },
                { value = "modern",  text = L["Modern (flat icon strip)"] },
            },
            get = function() return mod.db.microStyle or "classic" end,
            set = function(_, v) mod.db.microStyle = v; if mod.active then applyMicroBags(); applyMicroStyle() end end }
        items[#items + 1] = { type = "checkbox", label = L["Hide the bag bar"],
            tooltip = L["Hides the backpack and bag slots."],
            get = function() return mod.db.hideBags end,
            set = function(_, v) mod.db.hideBags = v; if mod.active then applyMicroBags(); applyBagStyle() end end }
        items[#items + 1] = { type = "dropdown", label = L["Bag bar style"], width = 280,
            tooltip = L["Modern puts the real bag buttons on a flat dark strip in the VuloUI look — opening, swapping and tooltips stay identical."],
            values = {
                { value = "classic", text = L["Classic (Blizzard buttons)"] },
                { value = "modern",  text = L["Modern (flat icon strip)"] },
            },
            get = function() return mod.db.bagStyle or "classic" end,
            set = function(_, v) mod.db.bagStyle = v; if mod.active then applyBagStyle() end end }
        items[#items + 1] = { type = "desc",
            text = L["|cff9b6cffThe micro menu, bag bar, FPS/latency bar and the XP bar below are movable in Edit Mode (/vedit) like the action bars.|r"] }
        items[#items + 1] = { type = "section", title = L["XP bar"], items = {
            { type = "checkbox", label = L["Show a custom XP bar"],
              tooltip = L["A movable, resizable experience bar with rested overlay. Hidden at max level. Replaces Blizzard's bar while on."],
              get = function() return mod.db.xpbar.on end,
              set = function(_, v) mod.db.xpbar.on = v; if mod.active then applyXPBar(); applyStatusBar() end end,
              subOptions = {
                  { type = "group", layout = "row", gap = 8, items = {
                      { type = "slider", label = L["Width"], min = 120, max = 900, step = 1, width = 160,
                        get = function() return mod.db.xpbar.width end,
                        set = function(_, v) mod.db.xpbar.width = v; if mod.active then applyXPBar() end end },
                      { type = "slider", label = L["Height"], min = 6, max = 32, step = 1, width = 160,
                        get = function() return mod.db.xpbar.height end,
                        set = function(_, v) mod.db.xpbar.height = v; if mod.active then applyXPBar() end end },
                      { type = "color", label = L["Colour"], width = 120,
                        get = function() return mod.db.xpbar.color end,
                        set = function(r, g, b) mod.db.xpbar.color = { r = r, g = g, b = b }; if mod.active then updateXPBar() end end },
                  } },
                  { type = "dropdown", label = L["Bar texture"], width = 240,
                    values = (function()
                        local v = { { value = "", text = L["Flat (default)"] } }
                        for _, e in ipairs((ns.MediaStatusbarValues and ns.MediaStatusbarValues()) or {}) do
                            v[#v + 1] = e
                        end
                        return v
                    end)(),
                    get = function() return mod.db.xpbar.texture or "" end,
                    set = function(_, v) mod.db.xpbar.texture = v; if mod.active then applyXPBar() end end },
              } },
        } }
        return items
    end

    -- Interaction tinting: pressed and hover colors for every bar button.
    if tabId == "anim" then
        local items = {}
        if not modernOn then
            items[#items + 1] = { type = "desc",
                text = L["|cffaaaaaaOnly active in Modern mode (Bar Display tab).|r"] }
        end
        items[#items + 1] = { type = "toggle", label = L["Tint the pressed state"],
            tooltip = L["Colours the flash a button shows while it is pressed down."],
            get = function() return mod.db.pushedTint end,
            set = function(_, v) mod.db.pushedTint = v; applyInteractions() end,
            subOptions = {
                { type = "group", layout = "row", gap = 8, items = {
                    { type = "checkbox", label = L["Use class colour"],
                      get = function() return mod.db.pushedClassColor end,
                      set = function(_, v) mod.db.pushedClassColor = v; applyInteractions() end },
                    { type = "color", label = L["Colour"], width = 120,
                      get = function() return mod.db.pushedColor end,
                      set = function(r, g, b) mod.db.pushedColor = { r = r, g = g, b = b }; applyInteractions() end },
                } },
            } }
        items[#items + 1] = { type = "toggle", label = L["Tint the hover highlight"], subKey = "hl",
            tooltip = L["Colours the glow a button shows under the mouse."],
            get = function() return mod.db.highlightTint end,
            set = function(_, v) mod.db.highlightTint = v; applyInteractions() end,
            subOptions = {
                { type = "group", layout = "row", gap = 8, items = {
                    { type = "checkbox", label = L["Use class colour"],
                      get = function() return mod.db.highlightClassColor end,
                      set = function(_, v) mod.db.highlightClassColor = v; applyInteractions() end },
                    { type = "color", label = L["Colour"], width = 120,
                      get = function() return mod.db.highlightColor end,
                      set = function(r, g, b) mod.db.highlightColor = { r = r, g = g, b = b }; applyInteractions() end },
                } },
            } }
        return items
    end

    -- Two modes, one page (user request 31.07.2026): Standard keeps
    -- Blizzard's bars, styled by the Dark Skin rows mirrored below; Modern is
    -- this module's own bar system. The active mode wears the accent.
    local items = {
        { type = "group", layout = "row", gap = 10, align = "center", items = {
            { type = "button", label = L["Standard Action Bars"], width = 220,
              primary = not modernOn,
              onClick = function()
                  if ns:IsModuleEnabled("actionbars") and ns.ToggleModule then
                      ns:ToggleModule("actionbars", false)
                      ns.UI:BuildOptionsPage("actionbars", ns.UI.currentTab)
                  end
              end },
            { type = "button", label = L["Modern"], width = 160,
              primary = modernOn,
              onClick = function()
                  if not ns:IsModuleEnabled("actionbars") and ns.ToggleModule then
                      ns:ToggleModule("actionbars", true)
                      ns.UI:BuildOptionsPage("actionbars", ns.UI.currentTab)
                  end
              end },
        } },
    }

    if not modernOn then
        items[#items + 1] = { type = "desc",
            text = L["|cffaaaaaaThe game's own action bars stay in place. Frame style and Dark Mode below come from the Dark Skin module and style Blizzard's buttons directly.|r"] }
        local ds = ns.modules and ns.modules.darkskin
        if ds and ds.db then
            items[#items + 1] = { type = "section", title = L["Bar style"], items = {
                { type = "toggle", label = L["Skin the action bars"],
                  tooltip = L["The dark action-bar button skin."],
                  get = function() return ds.db.skinBars end,
                  set = function(_, v) ds.db.skinBars = v; if ds.SetBarsSkinned then ds.SetBarsSkinned(v) end end },
                { type = "dropdown", label = L["Bar style"], width = 260,
                  tooltip = L["Pick how the action buttons look. Rounded/Circle use an icon mask; Minimal is just the cropped icon."],
                  values = ds.BarStyleValues and ds.BarStyleValues() or {},
                  get = function() return ds.db.style or "shadow" end,
                  set = function(_, v) ds.db.style = v; if ds.RefreshAll then ds.RefreshAll() end end },
                { type = "slider", label = L["Bar icon size"], min = 76, max = 100, step = 2,
                  tooltip = L["How much of the button the icon fills in Shadow style. Higher = bigger icons with a thinner rim."],
                  get = function() return ds.db.barIconSize or 90 end,
                  set = function(_, v) ds.db.barIconSize = v; if ds.RefreshAll then ds.RefreshAll() end end },
                { type = "toggle", label = L["Also skin pet & stance buttons"],
                  get = function() return ds.db.skinPetStance end,
                  set = function(_, v) ds.db.skinPetStance = v; if ds.SkinAll then ds.SkinAll() end end },
                -- Standard mode only, and that is the point: in Modern mode our
                -- own bars replace Blizzard's and the gryphons are gone anyway.
                -- The setting lives in the Dark Skin module because that is what
                -- is still running here -- this module's own appliers stand down
                -- while Blizzard keeps its bars.
                { type = "toggle", label = L["Hide the gryphons"],
                  tooltip = L["Removes the two beasts at the ends of Blizzard's main action bar. The bar itself stays."],
                  get = function() return ds.db.hideGryphons end,
                  set = function(_, v) ds.db.hideGryphons = v; if ds.ApplyAllDM then ds.ApplyAllDM() end end },
            } }
            items[#items + 1] = { type = "section", title = L["Dark Mode"], items = {
                { type = "toggle", label = L["Enable Dark Mode"],
                  tooltip = L["Re-tints Blizzard's default frames, minimap and action-bar artwork to a dark tone. Off by default."],
                  get = function() return ds.db.darkMode end,
                  set = function(_, v) ds.db.darkMode = v; if ds.ApplyAllDM then ds.ApplyAllDM() end end },
                { type = "toggle", label = L["Desaturate (greyscale)"],
                  tooltip = L["Strips the colour out of the artwork before tinting, for a true greyscale look. Off keeps a hint of the original hue."],
                  get = function() return ds.db.dmDesaturate end,
                  set = function(_, v) ds.db.dmDesaturate = v; if ds.ApplyAllDM then ds.ApplyAllDM() end end },
                { type = "color", label = L["Tint colour"], width = 160,
                  get = function() return ds.db.dmColor end,
                  set = function(r, g, b) ds.db.dmColor = { r = r, g = g, b = b }; if ds.ApplyAllDM then ds.ApplyAllDM() end end },
                { type = "toggle", label = L["Action bar artwork"],
                  tooltip = L["The gryphons and the metal action-bar background."],
                  get = function() return ds.db.dmActionbars end,
                  set = function(_, v) ds.db.dmActionbars = v; if ds.ApplyAllDM then ds.ApplyAllDM() end end },
                { type = "toggle", label = L["Action button borders"],
                  tooltip = L["Also tints the border ring around every action button. Optional — leave off if it looks too flat."],
                  get = function() return ds.db.dmActionButtons end,
                  set = function(_, v) ds.db.dmActionButtons = v; if ds.ApplyAllDM then ds.ApplyAllDM() end end },
            } }
        end
        return items
    end

    items[#items + 1] = { type = "desc",
        text = L["|cffaaaaaaOwn buttons for every action bar (1-5): real combat / mouseover show-hide, scale and grid layout, correct main-bar paging (druid/rogue/warrior/priest forms) and your keybinds. Move each in Edit Mode (/vedit). After disabling, /reload to fully restore Blizzard's bars.|r"] }
    items[#items + 1] = { type = "desc",
        text = L["|cff9b6cffButton border / icon style lives in the Dark Skin module (Action Bars > Bar style): square, accent edge, shadow and more.|r"] }

    -- The selected bar's sections, straight under the pinned picker; the
    -- picker in the header decides which bar `selectedBar` names.
    local d = BAR_BY_KEY[selectedBar] or BAR_BY_KEY.main
    for _, sec in ipairs(barModeSections(d)) do items[#items + 1] = sec end
    if d.key == "main" then items[#items + 1] = pagingRows() end

    -- Everything below applies to the modern bars as a whole; the chrome rows
    -- (micro menu, bags, XP bar) live on their own tab now.
    local rest = {
        { type = "button", label = L["Quick keybind mode (/vkb)"], width = 240,
          tooltip = L["Hover an action button and press a key to bind it. Hidden bars are shown while binding."],
          onClick = function() if ns.OpenQuickKeybind then ns.OpenQuickKeybind() end end },
        { type = "slider", label = L["Fade speed (sec.)"], min = 0.05, max = 0.6, step = 0.01, width = 180,
          get = function() return mod.db.fadeSpeed end,
          set = function(_, v) mod.db.fadeSpeed = v end },
        { type = "checkbox", label = L["Mouseover reveals all mouseover bars"],
          tooltip = L["Hovering ANY mouseover bar shows every bar set to mouseover at once."],
          get = function() return mod.db.hoverShowsAll end,
          set = function(_, v) mod.db.hoverShowsAll = v end },
        { type = "section", title = L["Button text styling"], items = {
            { type = "desc", text = L["|cffaaaaaaColours and fine offsets for the button texts, on every bar.|r"] },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "color", label = L["Keybind text colour"], width = 150,
                  get = function() return mod.db.textKeybindColor end,
                  set = function(r, g, b) mod.db.textKeybindColor = { r = r, g = g, b = b }; reapply() end },
                { type = "color", label = L["Macro text colour"], width = 150,
                  get = function() return mod.db.textMacroColor end,
                  set = function(r, g, b) mod.db.textMacroColor = { r = r, g = g, b = b }; reapply() end },
                { type = "color", label = L["Count text colour"], width = 150,
                  get = function() return mod.db.textCountColor end,
                  set = function(r, g, b) mod.db.textCountColor = { r = r, g = g, b = b }; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Keybind offset X"], min = -20, max = 20, step = 1, width = 150,
                  get = function() return mod.db.textKeybindX or 0 end,
                  set = function(_, v) mod.db.textKeybindX = v; reapply() end },
                { type = "slider", label = L["Keybind offset Y"], min = -20, max = 20, step = 1, width = 150,
                  get = function() return mod.db.textKeybindY or 0 end,
                  set = function(_, v) mod.db.textKeybindY = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Macro offset X"], min = -20, max = 20, step = 1, width = 150,
                  get = function() return mod.db.textMacroX or 0 end,
                  set = function(_, v) mod.db.textMacroX = v; reapply() end },
                { type = "slider", label = L["Macro offset Y"], min = -20, max = 20, step = 1, width = 150,
                  get = function() return mod.db.textMacroY or 0 end,
                  set = function(_, v) mod.db.textMacroY = v; reapply() end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Count offset X"], min = -20, max = 20, step = 1, width = 150,
                  get = function() return mod.db.textCountX or 0 end,
                  set = function(_, v) mod.db.textCountX = v; reapply() end },
                { type = "slider", label = L["Count offset Y"], min = -20, max = 20, step = 1, width = 150,
                  get = function() return mod.db.textCountY or 0 end,
                  set = function(_, v) mod.db.textCountY = v; reapply() end },
            } },
        } },
        { type = "section", title = L["Cooldown & look"], items = {
            { type = "desc", text = L["|cffaaaaaaApplies to every action bar.|r"] },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Cooldown swipe opacity"], min = 0, max = 100, step = 5, width = 170,
                  tooltip = L["How dark the cooldown sweep overlay is (0 = invisible)."],
                  get = function() return mod.db.cdSwipe or 80 end,
                  set = function(_, v) mod.db.cdSwipe = v; if mod.active then applyLook() end end },
                { type = "color", label = L["Swipe colour"], width = 130,
                  get = function() return mod.db.cdSwipeColor end,
                  set = function(r, g, b) mod.db.cdSwipeColor = { r = r, g = g, b = b }; if mod.active then applyLook() end end },
                { type = "checkbox", label = L["Desaturate icons on cooldown"],
                  get = function() return mod.db.desatOnCd end,
                  set = function(_, v) mod.db.desatOnCd = v; if mod.active then applyLook() end end },
            } },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Icon opacity on cooldown"], min = 20, max = 100, step = 5, width = 170,
                  tooltip = L["Dims the whole icon while the ability is on cooldown (100 = off)."],
                  get = function() return mod.db.cdAlpha or 100 end,
                  set = function(_, v) mod.db.cdAlpha = v; if mod.active then applyLook() end end },
                { type = "checkbox", label = L["Show cooldown numbers"],
                  tooltip = L["The game's own countdown numbers on cooldowns (a game setting, changed live)."],
                  get = function() return GetCVar and GetCVar("countdownForCooldowns") == "1" end,
                  set = function(_, v) if not InCombatLockdown() then pcall(SetCVar, "countdownForCooldowns", v and "1" or "0") end end },
            } },
            { type = "checkbox", label = L["Out-of-range colouring"],
              tooltip = L["Tints the whole icon while your target is out of range."],
              get = function() return mod.db.rangeColoring end,
              set = function(_, v) mod.db.rangeColoring = v; if mod.active then applyLook() end end,
              subOptions = {
                  { type = "color", label = L["Colour"], width = 120,
                    get = function() return mod.db.rangeColor end,
                    set = function(r, g, b) mod.db.rangeColor = { r = r, g = g, b = b } end },
              } },
            -- Left where it was, only unpaired: tooltips have nothing to do with
            -- range colouring, they just happened to share a row.
            { type = "dropdown", label = L["Tooltips"], width = 200,
              values = {
                  { value = "show",   text = L["Show"] },
                  { value = "combat", text = L["Hide in combat"] },
                  { value = "never",  text = L["Hide always"] },
              },
              get = function() return mod.db.tooltipMode or "show" end,
              set = function(_, v) mod.db.tooltipMode = v end },
        } },
    }
    for _, it in ipairs(rest) do items[#items + 1] = it end
    return items
end
