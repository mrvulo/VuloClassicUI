-- =========================================================
-- VuloClassicUI / Modules / ActionBars
--
-- Builds our OWN buttons for all 5 action bars on this modern EditMode client,
-- because Blizzard's own bars are PROTECTED — an addon cannot move them
-- (frame:StartMoving errors + taints). Each of our bars lives on its own
-- SecureHandlerStateTemplate frame, movable via the addon's Edit Mode mover.
--
--   * MAIN bar (VuloActionButton1-12) — dynamic paging (druid/rogue via
--     [bonusbar:N], warrior/priest via [form:N]) driven by a state driver.
--   * MULTIBARS 2-5 (VuloAB_<key>B1-12) — a FIXED action offset (base) pushed to
--     the buttons via the frame's secure ChildUpdate. Action is only ever set
--     from SECURE code, so casting never taints.
--   * Keybinds: override bindings route the native command keys (ACTIONBUTTONn /
--     MULTIACTIONBARxBUTTONn) onto our buttons; hotkey text filled in manually.
--   * Blizzard's own action bars are hidden TAINT-FREE in place via SetAlpha(0)
--     + EnableMouse(false) (never moved/reparented). MainActionBar art + the blue
--     XP/reputation status bar are parked too. STANCE/PET are left fully native
--     (a different secure button type — arranged with Blizzard's own Edit Mode).
--
-- Every protected op (create/SetPoint/RegisterStateDriver/override bindings/
-- SetAttribute/Execute) runs OUT OF COMBAT; the secure snippets run in combat.
-- Disabling un-hides Blizzard's bars; a /reload fully re-inits them.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("actionbars", {
    name        = "Action Bars",
    group       = "HUD",
    description = "Takes over every action bar with its own movable frames: real combat/mouseover show-hide, scale and grid layout per bar, correct main-bar paging (druid/rogue/warrior/priest forms) and your keybinds. EXPERIMENTAL — test ability clicks and paging in combat; /reload after disabling.",
    defaults = {
        -- OFF by default: Blizzard's standard bars load normally; enabling this
        -- module is what switches them over to the takeover.
        enabled        = false,
        fadeSpeed      = 0.18,
        hideStatusBars = true,   -- hide Blizzard's leftover XP/reputation bar
        hidePerfBar    = true,   -- hide Blizzard's green FPS/latency performance bar
        hideMicroMenu  = false,  -- hide the micro menu (menu buttons)
        hideBags       = false,  -- hide the bag bar
        -- movable holders for Blizzard chrome (x/y = CENTER offset, Edit Mode)
        chrome = {
            micro = { x = 300,  y = -350, scale = 1 },
            bags  = { x = 560,  y = -350, scale = 1 },
            perf  = { x = 60,   y = -350, scale = 1 },
        },
        -- our own XP bar (replaces the hidden Blizzard one)
        xpbar = { on = true, width = 420, height = 14, x = 0, y = -320, scale = 1,
                  color = { r = 0.58, g = 0.0, b = 0.55 } },
        -- per bar: on/visibility/fade/perRow/spacing + mover position (x,y = CENTER
        -- offset) and scale (multiplier). Position/scale are edited in Edit Mode.
        bars = {
            main        = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 12, spacing = 4, x = 0,    y = -300 },
            bottomleft  = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 12, spacing = 4, x = 0,    y = -338 },
            bottomright = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 12, spacing = 4, x = 0,    y = -376 },
            right       = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 6,  spacing = 4, x = 520,  y = -40 },
            left        = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 6,  spacing = 4, x = 452,  y = -40 },
            stance      = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 10, spacing = 4, x = -380, y = -250 },
            pet         = { on = true, visibility = "always", fadeAlpha = 0, scale = 1, perRow = 10, spacing = 4, x = 380,  y = -250 },
        },
    },
})

local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey
local abs = math.abs

-- bar descriptors ------------------------------------------------------------
local BARS = {
    { key = "main",        kind = "own",    count = 12, cmd = "ACTIONBUTTON%d",         label = "Action Bar 1 (Main)" },
    { key = "bottomleft",  kind = "reuse",  count = 12, base = 60, prefix = "MultiBarBottomLeft",  cmd = "MULTIACTIONBAR1BUTTON%d", label = "Action Bar 2" },
    { key = "bottomright", kind = "reuse",  count = 12, base = 48, prefix = "MultiBarBottomRight", cmd = "MULTIACTIONBAR2BUTTON%d", label = "Action Bar 3" },
    { key = "right",       kind = "reuse",  count = 12, base = 24, prefix = "MultiBarRight",       cmd = "MULTIACTIONBAR3BUTTON%d", label = "Action Bar 4" },
    { key = "left",        kind = "reuse",  count = 12, base = 36, prefix = "MultiBarLeft",        cmd = "MULTIACTIONBAR4BUTTON%d", label = "Action Bar 5" },
    { key = "stance",      kind = "stance", count = 10, prefix = "StanceButton",    blizz = "StanceBarFrame",     cmd = "SHAPESHIFTBUTTON%d", label = "Stance bar" },
    { key = "pet",         kind = "pet",    count = 10, prefix = "PetActionButton", blizz = "PetActionBarFrame",  cmd = "BONUSACTIONBUTTON%d", label = "Pet bar" },
}
local BAR_BY_KEY = {}
for _, d in ipairs(BARS) do BAR_BY_KEY[d.key] = d end

local state = {}          -- key -> { frame, buttons={}, curAlpha, tgtAlpha, hovered }
local shadow              -- hidden dump parent for Blizzard's frames
local taken = false
local hidden = {}         -- Blizzard frame -> original parent (restore)
local pendingRestore = false
local updater

-- Blizzard main-bar art (hidden while taken) + legacy xp frames (nil on 20506)
local MAIN_ART = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuBarTextureExtender",
}
local LEGACY_BARS = { "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }
-- Blizzard multibar containers we hide (alpha) because we render our own buttons
local MULTIBAR_FRAMES = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }
-- Blizzard's stance bar container (hidden when our own stance bar is active)
local STANCE_HIDE = { "StanceBar", "StanceBarFrame" }
-- micro menu + bag bar frames (best-effort names across client versions)
local MICRO_FRAMES = { "MicroMenu", "MicroMenuContainer" }
local BAG_FRAMES   = {
    "BagsBar", "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
}

-- Class paging states for the MAIN bar. page = 1 + reference mainbar offset.
local CLASS_STATES = {
    DRUID = {
        { m = "[bonusbar:3]", page = 9 },   -- bear
        { m = "[bonusbar:1]", page = 7 },   -- cat (also covers prowl)
        { f = 24858,          page = 10 },  -- moonkin
        { f = 33891,          page = 8 },   -- tree
    },
    ROGUE   = { { m = "[bonusbar:1]", page = 7 } },                                    -- stealth
    WARRIOR = { { f = 2457, page = 7 }, { f = 71, page = 8 }, { f = 2458, page = 9 } },-- battle/def/berserker
    PRIEST  = { { m = "[form:1]", page = 7 } },                                        -- shadowform
}

-- =========================================================
-- Helpers
-- =========================================================
local function ensureShadow()
    if shadow then return end
    shadow = CreateFrame("Frame", "VuloABShadow", UIParent)
    shadow:SetAllPoints(UIParent)
    shadow:Hide()
end

local function barDB(key) return mod.db.bars[key] end

-- resolve a form spell id (or list) to "[form:N]" via the live form table
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

-- shorten a binding key the way the stock buttons do (SHIFT-Q -> s-Q, etc.)
local function keyAbbr(key)
    if not key then return nil end
    return (key
        :gsub("SHIFT%-", "s-"):gsub("STRG%-", "c-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-")
        :gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD")
        :gsub("NUMPAD", "N"):gsub("SPACE", "Sp"))
end

-- =========================================================
-- Bar frame + button setup (out of combat)
-- =========================================================
local function ensureBar(desc)
    local st = state[desc.key]
    if not st then st = { buttons = {}, curAlpha = 1, tgtAlpha = 1, hovered = false }; state[desc.key] = st end

    if not st.frame then
        local f = CreateFrame("Frame", "VuloAB_" .. desc.key, UIParent, "SecureHandlerStateTemplate")
        f:SetSize(desc.count * 40, 40)
        f:SetFrameStrata("MEDIUM")
        st.frame = f
        if desc.kind == "own" then   -- MAIN bar needs the dynamic paging controller
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
            -- MAIN: own button, action driven by paging (seed 0 so first page paints)
            local b = _G["VuloActionButton" .. i] or CreateFrame("CheckButton", "VuloActionButton" .. i, st.frame, "ActionBarButtonTemplate")
            b:SetParent(st.frame)
            b:SetAttributeNoHandler("action", 0)
            b:SetAttributeNoHandler("index", i)
            b:SetAttributeNoHandler("commandName", "ACTIONBUTTON" .. i)
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
            -- PET: reuse Blizzard's PetActionButton1-10 (the proven recipe on this
            -- client): reparent onto our frame, keep the container's events so
            -- Blizzard keeps painting + showing/hiding them; native BONUSACTIONBUTTON
            -- keybinds keep working (buttons stay in the container's actionButtons).
            local bf = _G.PetActionBar or _G.PetActionBarFrame
            local b = (bf and bf.actionButtons and bf.actionButtons[i]) or _G["PetActionButton" .. i]
            if b then
                b:SetParent(st.frame)
                b:SetAttribute("commandName", "BONUSACTIONBUTTON" .. i)
                st.buttons[i] = b
            end
        elseif desc.kind == "stance" then
            -- STANCE: own StanceButtonTemplate button. Passing the id to CreateFrame
            -- wires up the secure form-cast (no insecure attribute = no taint); we
            -- paint icon/cooldown/checked ourselves in updateStance().
            local name = "VuloAB_stanceB" .. i
            local b = _G[name] or CreateFrame("CheckButton", name, st.frame, "StanceButtonTemplate", i)
            b:SetParent(st.frame)
            b:SetAttribute("commandName", "SHAPESHIFTBUTTON" .. i)
            if b.cooldown and b.cooldown.SetDrawEdge then b.cooldown:SetDrawEdge(false) end
            if b.SlotBackground then b.SlotBackground:Hide() end
            b:EnableMouseWheel()
            st.buttons[i] = b
        else
            -- MULTIBAR: own button, FIXED action slot (base + i). The action MUST be
            -- set from SECURE code (the frame's ChildUpdate), never insecure
            -- SetAttribute, or casting taints and gets blocked in combat.
            local name = "VuloAB_" .. desc.key .. "B" .. i
            local b = _G[name] or CreateFrame("CheckButton", name, st.frame, "ActionBarButtonTemplate")
            b:SetParent(st.frame)
            b:SetAttributeNoHandler("action", 0)
            b:SetAttributeNoHandler("index", i)
            b:SetAttributeNoHandler("commandName", desc.cmd:format(i))
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

-- paint the own stance buttons (icon/cooldown/checked) — the template doesn't
-- self-update when created standalone, so we drive it from shapeshift events.
local function updateStance()
    local st = state.stance
    if not st then return end
    for i, b in ipairs(st.buttons) do
        local texture, isActive, isCastable = GetShapeshiftFormInfo(i)
        b:SetShown(texture ~= nil)
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

-- size the frame + grid the buttons. The FRAME's screen position + scale are
-- owned by the mover (Edit Mode); we only size it, then re-apply the mover so the
-- grab box tracks the new size and the position/scale get applied.
local function layoutBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    local db = barDB(desc.key)
    local buttons = st.buttons
    if desc.kind == "stance" then   -- only lay out the forms the class actually has
        local nf = GetNumShapeshiftForms() or 0
        buttons = {}
        for i = 1, nf do if st.buttons[i] then buttons[#buttons + 1] = st.buttons[i] end end
    end
    local n = #buttons
    local perRow = math.max(1, math.min(db.perRow or desc.count, desc.count))
    local sp = db.spacing or 4
    local iconSize = (db.iconSize and db.iconSize > 0) and db.iconSize or nil

    -- per-button styling: optional icon size + hide keybind / macro text
    for _, b in ipairs(st.buttons) do
        if iconSize then b:SetSize(iconSize, iconSize) end
        local nm = b:GetName()
        local hk = b.HotKey or (nm and _G[nm .. "HotKey"])
        if hk then hk:SetShown(not db.hideKeybind) end
        local macro = b.Name or (nm and _G[nm .. "Name"])
        if macro then macro:SetShown(not db.hideMacro) end
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
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", st.frame, "TOPLEFT", col * (w + sp), -row * (h + sp))
        end
    end
    if st.mover and st.mover.SetSize then st.mover:SetSize(st.frame:GetWidth(), st.frame:GetHeight()) end
    if ns.ApplyMover and st.mover then ns:ApplyMover(st.mover) end   -- position + scale
end

local function pageBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    if desc.kind == "own" then
        RegisterStateDriver(st.frame, "page", pageDriver())   -- fires _onstate-page → initial paging
    else
        -- multibar: push the FIXED action offset (base) to the buttons securely so
        -- each ends up with action = index + base (no insecure action set = no taint)
        st.frame:SetAttribute("actionOffset", desc.base)
        st.frame:Execute([[ self:ChildUpdate('offset', self:GetAttribute('actionOffset') or 0) ]])
    end
end

local function visBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    local m = barDB(desc.key).visibility
    if desc.kind == "pet" then
        -- the pet bar only ever shows while a pet with an action bar exists;
        -- the secure driver folds the user's visibility choice into that.
        local cond
        if m == "combat" then cond = "[@pet,exists,combat] show; hide"
        elseif m == "noncombat" then cond = "[@pet,exists,nocombat] show; hide"
        else cond = "[@pet,exists] show; hide" end
        RegisterStateDriver(st.frame, "userDisplay", cond)
        return
    end
    if m == "combat" then
        RegisterStateDriver(st.frame, "userDisplay", "[combat] show; hide")
    elseif m == "noncombat" then
        RegisterStateDriver(st.frame, "userDisplay", "[combat] hide; show")
    else
        UnregisterStateDriver(st.frame, "userDisplay")
        st.frame:Show()
    end
end

-- Our own buttons have no Blizzard binding of their own, so we route the native
-- command keys (ACTIONBUTTONn for main, MULTIACTIONBARxBUTTONn for the multibars)
-- onto them via override bindings, and fill the hotkey text ourselves.
local function bindBar(desc)
    -- pet buttons are Blizzard's own (names + container entry intact), so their
    -- native BONUSACTIONBUTTON bindings and hotkey text still work — skip them.
    if desc.kind == "pet" then return end
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
            -- respect the per-bar "hide keybind text" toggle (bindBar runs AFTER
            -- layoutBar, so it must not undo it)
            hk:SetShown(keys[1] ~= nil and not barDB(desc.key).hideKeybind)
        end
    end
end

-- =========================================================
-- Hide / restore Blizzard chrome
-- =========================================================
-- Blizzard's XP/rep bar goes away when the user hides it OR when our own XP bar
-- is on (two experience bars at once makes no sense).
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

-- Blizzard's green FPS/latency performance bar (MainMenuBarPerformanceBar).
-- Hidden taint-free via alpha + mouse, since it's chrome on the bar we replaced.
local function applyPerfBar()
    local hide = mod.active and mod.db.hidePerfBar
    local f = _G.MainMenuBarPerformanceBarFrame
    if f then f:SetAlpha(hide and 0 or 1) end
    local b = _G.MainMenuBarPerformanceBarFrameButton
    if b then b:SetAlpha(hide and 0 or 1); if b.EnableMouse then b:EnableMouse(not hide) end end
end

-- hide/show a set of frames taint-free (alpha + mouse), never moving them
local function setFramesHidden(names, hide)
    for _, n in ipairs(names) do
        local f = _G[n]
        if f then f:SetAlpha(hide and 0 or 1); if f.EnableMouse then f:EnableMouse(not hide) end end
    end
end

-- micro menu + bag bar hide toggles (alpha — works wherever the frames live)
local function applyMicroBags()
    setFramesHidden(MICRO_FRAMES, mod.active and mod.db.hideMicroMenu)
    setFramesHidden(BAG_FRAMES, mod.active and mod.db.hideBags)
end

-- =========================================================
-- Chrome holders: micro menu / bag bar / FPS-latency bar re-homed onto small
-- movable holder frames. None of these are protected action frames, so the
-- reparent + SetPoint is taint-free — unlike the action bars themselves.
-- =========================================================
local CHROME = {
    { key = "micro", label = "Micro menu" },
    { key = "bags",  label = "Bag bar" },
    { key = "perf",  label = "FPS / latency bar" },
}
local chromeState = {}   -- key -> { holder, mover, targets }
local chromeOrig = {}    -- reparented frame -> original parent

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

-- keep a reparented chrome frame glued to its holder: Blizzard's layout code
-- re-anchors these frames (that's why the bags snapped back), so we hook SetPoint
-- and immediately re-pin. Insecure frames — taint-free even in combat.
local function pinFrame(f, point, holder, relPoint, x, y)
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

-- Blizzard's keyring layout updater re-anchors the performance bar to the keyring
-- button; with both re-homed onto our holders that SetPoint is refused ("anchor
-- family connection") and spams errors. We own those positions now, so the
-- updater is neutralised while the module is active (restored on disable).
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

local function applyChrome()
    if InCombatLockdown() then return end
    muteKeyRingLayout(true)
    for _, c in ipairs(CHROME) do ensureChrome(c) end
end

local function restoreChrome()
    muteKeyRingLayout(false)
    for f, parent in pairs(chromeOrig) do
        f._vcuiPinTo = nil   -- release the pin so Blizzard may anchor freely again
        f:SetParent(parent)
        chromeOrig[f] = nil
    end
    for _, cs in pairs(chromeState) do
        if cs.holder then cs.holder:Hide() end
    end
end

-- =========================================================
-- Own XP bar (movable / resizable; Blizzard's status bar stays hidden)
-- =========================================================
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
    xpBar:Show()
    if xpBar.mover then
        xpBar.mover:SetSize(xpBar:GetWidth(), xpBar:GetHeight())
        if ns.ApplyMover then ns:ApplyMover(xpBar.mover) end
    end
    updateXPBar()
end

-- park a Blizzard container frame under the hidden shadow (records its parent)
-- park a Blizzard container out of the way. We do NOT wipe its actionButtons:
-- Blizzard's own keybind handlers (MultiActionButtonDown/Up etc.) index that
-- table and error if it's empty, and the buttons we reparented still live in it.
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
    -- main bar frame + its buttons + art
    parkFrame("MainActionBar", true)
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if b then b:UnregisterAllEvents(); b:SetAttributeNoHandler("statehidden", true); b:Hide() end
    end
    for _, n in ipairs(MAIN_ART) do local t = _G[n]; if t then t:Hide() end end
    local art = _G.MainMenuBarArtFrame
    if art then art:SetAlpha(0) end
    -- Blizzard's multibar containers: we can't move them (protected EditMode), so
    -- just make them invisible + click-through in place — TAINT-FREE (SetAlpha /
    -- EnableMouse aren't protected). Our own buttons render at the mover position.
    for _, n in ipairs(MULTIBAR_FRAMES) do
        local f = _G[n]
        if f then
            f:SetAlpha(0)
            if f.EnableMouse then f:EnableMouse(false) end
            if type(f.actionButtons) == "table" then
                for _, b in pairs(f.actionButtons) do if b.EnableMouse then b:EnableMouse(false) end end
            end
        end
    end
    -- pet container: parent it away (recorded) but KEEP its events + no Hide —
    -- Blizzard's handlers must keep updating the reparented pet buttons.
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

-- =========================================================
-- Fade (mouseover) — insecure alpha per bar frame
-- =========================================================
local function refreshFade(desc)
    local st = state[desc.key]
    if not (mod.active and st and st.frame) then return end
    if barDB(desc.key).visibility == "mouseover" then
        st.tgtAlpha = st.hovered and 1 or (barDB(desc.key).fadeAlpha or 0) / 100
    else
        st.tgtAlpha = 1
    end
    if abs(st.curAlpha - st.tgtAlpha) > 0.001 and updater then updater:Show() end
end

local function hookHover(desc)
    local st = state[desc.key]
    if not st then return end
    for _, b in ipairs(st.buttons) do
        if not b.vHovered then
            b.vHovered = true
            b:HookScript("OnEnter", function()
                if mod.active and barDB(desc.key).visibility == "mouseover" then st.hovered = true; refreshFade(desc) end
            end)
            b:HookScript("OnLeave", function()
                if not (mod.active and barDB(desc.key).visibility == "mouseover") then return end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.1, function()
                        if mod.active and st.frame and not st.frame:IsMouseOver() then st.hovered = false; refreshFade(desc) end
                    end)
                else st.hovered = false; refreshFade(desc) end
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

-- =========================================================
-- Take over / restore
-- =========================================================
local function applyBar(desc)
    local st = state[desc.key]
    if not st or not st.frame or InCombatLockdown() then return end
    local on = barDB(desc.key).on
    -- stance: hide the whole bar when the class has no forms
    if on and desc.kind == "stance" and (GetNumShapeshiftForms() or 0) == 0 then on = false end
    if desc.kind == "stance" then setFramesHidden(STANCE_HIDE, on) end   -- hide Blizzard's when ours is up
    if on then
        st.frame:Show()
        layoutBar(desc)
        if desc.kind == "stance" then updateStance()
        elseif desc.kind ~= "pet" then pageBar(desc) end   -- pet: Blizzard drives the buttons
        visBar(desc); bindBar(desc)
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
    applyChrome(); applyXPBar()
    taken = true
    -- ask the Dark Skin module to skin our freshly-created buttons
    if ns.ReskinActionButtons then ns.ReskinActionButtons() end
end

local function restore()
    if not taken then return end
    if InCombatLockdown() then pendingRestore = true; return end
    -- hide our own frames (main + multibars)
    for _, desc in ipairs(BARS) do
        local st = state[desc.key]
        if st and st.frame then
            UnregisterStateDriver(st.frame, "page")
            UnregisterStateDriver(st.frame, "userDisplay")
            ClearOverrideBindings(st.frame)
            st.frame:Hide()
        end
    end
    -- un-hide Blizzard's multibars (a /reload restores their full native state)
    for _, n in ipairs(MULTIBAR_FRAMES) do
        local f = _G[n]
        if f then
            f:SetAlpha(1)
            if f.EnableMouse then f:EnableMouse(true) end
            if type(f.actionButtons) == "table" then
                for _, b in pairs(f.actionButtons) do if b.EnableMouse then b:EnableMouse(true) end end
            end
        end
    end
    unpark("MainActionBar")
    unpark("PetActionBar"); unpark("PetActionBarFrame")
    for _, n in ipairs(MAIN_ART) do local t = _G[n]; if t then t:Show() end end
    local art = _G.MainMenuBarArtFrame
    if art then art:SetAlpha(1) end
    local pf = _G.MainMenuBarPerformanceBarFrame
    if pf then pf:SetAlpha(1) end
    local pb = _G.MainMenuBarPerformanceBarFrameButton
    if pb then pb:SetAlpha(1); if pb.EnableMouse then pb:EnableMouse(true) end end
    setFramesHidden(MICRO_FRAMES, false)
    setFramesHidden(BAG_FRAMES, false)
    setFramesHidden(STANCE_HIDE, false)
    restoreChrome()
    if xpBar then xpBar:Hide() end
    local stbm = _G.StatusTrackingBarManager
    if stbm then stbm:Show(); if stbm.RegisterAllEvents then stbm:RegisterAllEvents() end end
    for _, n in ipairs(LEGACY_BARS) do local f = _G[n]; if f then f:Show() end end
    taken = false
    ns:Print(L["|cffffcc00Action Bars disabled — type /reload to fully restore the default bars.|r"])
end

-- =========================================================
-- Apply / events
-- =========================================================
local function applyAll()
    if not mod.active then return end
    if InCombatLockdown() then return end   -- flushed on PLAYER_REGEN_ENABLED
    if not taken then
        takeOver()
    else
        for _, desc in ipairs(BARS) do applyBar(desc) end
        applyChrome(); applyXPBar()
    end
end

-- While Edit Mode is open, force-show every bar (even ones hidden by visibility
-- rules, no forms or no pet) so their boxes can be placed; restore on exit.
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
        applyAll()   -- re-applies visibility drivers, alpha and stance/pet gating
    end
end
if ns.RegisterEditModeHook then ns:RegisterEditModeHook(onEditMode) end

local function onRegen()
    if pendingRestore then pendingRestore = false; restore(); return end
    applyAll()
end
local function onWorld() applyAll() end
local function onForms()
    if mod.active and not InCombatLockdown() and taken then
        pageBar(BAR_BY_KEY.main); applyBar(BAR_BY_KEY.stance)
    end
end
local function onPet()
    if mod.active and not InCombatLockdown() and taken then applyBar(BAR_BY_KEY.pet) end
end
-- form activated / usability / cooldown → repaint our stance buttons (insecure,
-- so this is safe in combat, unlike re-layout).
local function onStance() if mod.active and taken then updateStance() end end
local function onXP() if mod.active and taken then updateXPBar() end end
local function onBindings()
    if mod.active and not InCombatLockdown() then
        for _, desc in ipairs(BARS) do bindBar(desc) end
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    pendingRestore = false
    -- migrate a previous version's per-bar scale (stored as a 50-150 percent) to
    -- the mover's multiplier, so a saved 100 doesn't become SetScale(100).
    for _, desc in ipairs(BARS) do
        local db = barDB(desc.key)
        if db then
            if db.scale and db.scale > 3 then db.scale = db.scale / 100 end
            if not db.scale or db.scale <= 0 then db.scale = 1 end
        end
    end
    ensureUpdater()
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", onRegen)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", onWorld)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", onForms)
    ns:RegisterEvent("UPDATE_BINDINGS", onBindings)
    ns:RegisterEvent("PET_BAR_UPDATE", onPet)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_FORM", onStance)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_USABLE", onStance)
    ns:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN", onStance)
    ns:RegisterEvent("PLAYER_XP_UPDATE", onXP)
    ns:RegisterEvent("PLAYER_LEVEL_UP", onXP)
    ns:RegisterEvent("UPDATE_EXHAUSTION", onXP)
    applyAll()
end

function mod:OnDisable()
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED", onRegen)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onWorld)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS", onForms)
    ns:UnregisterEvent("UPDATE_BINDINGS", onBindings)
    ns:UnregisterEvent("PET_BAR_UPDATE", onPet)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_FORM", onStance)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_USABLE", onStance)
    ns:UnregisterEvent("UPDATE_SHAPESHIFT_COOLDOWN", onStance)
    ns:UnregisterEvent("PLAYER_XP_UPDATE", onXP)
    ns:UnregisterEvent("PLAYER_LEVEL_UP", onXP)
    ns:UnregisterEvent("UPDATE_EXHAUSTION", onXP)
    if updater then updater:Hide() end
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

-- =========================================================
-- Options
-- =========================================================
local function reapply() if mod.active then applyAll() end end

local VIS_VALUES = {
    { value = "always",    text = L["Always shown"] },
    { value = "mouseover", text = L["Mouseover"] },
    { value = "combat",    text = L["In combat"] },
    { value = "noncombat", text = L["Out of combat"] },
}

local function moverApply(key)
    local st = state[key]
    if st and st.mover and ns.ApplyMover then ns:ApplyMover(st.mover) end
end

local function barSection(desc)
    local key = desc.key
    return {
        type = "section",
        title = L[desc.label],
        collapsed = (key ~= "main"),
        items = {
            { type = "group", layout = "row", gap = 8, items = {
                { type = "checkbox", label = L["Enabled"],
                  get = function() return barDB(key).on end,
                  set = function(_, v) barDB(key).on = v; reapply() end },
                { type = "dropdown", label = L["Visibility"], width = 220, values = VIS_VALUES,
                  get = function() return barDB(key).visibility end,
                  set = function(_, v) barDB(key).visibility = v; reapply() end },
            } },
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
                { type = "checkbox", label = L["Hide keybind text"],
                  get = function() return barDB(key).hideKeybind end,
                  set = function(_, v) barDB(key).hideKeybind = v; reapply() end },
                { type = "checkbox", label = L["Hide macro text"],
                  get = function() return barDB(key).hideMacro end,
                  set = function(_, v) barDB(key).hideMacro = v; reapply() end },
            } },
        },
    }
end

function mod:GetOptions()
    local items = {
        { type = "desc",
          text = L["|cffaaaaaaOwn buttons for every action bar (1-5): real combat / mouseover show-hide, scale and grid layout, correct main-bar paging (druid/rogue/warrior/priest forms) and your keybinds. Move each in Edit Mode (/vedit). After disabling, /reload to fully restore Blizzard's bars.|r"] },
        { type = "desc",
          text = L["|cff9b6cffButton border / icon style lives in the Dark Skin module (Action Bars → Bar style): square, accent edge, shadow and more.|r"] },
        { type = "checkbox", label = L["Hide Blizzard's XP / reputation bar"],
          tooltip = L["Removes the leftover blue experience / reputation bar under the action bar."],
          get = function() return mod.db.hideStatusBars end,
          set = function(_, v) mod.db.hideStatusBars = v; if mod.active then applyStatusBar() end end },
        { type = "checkbox", label = L["Hide the FPS / latency bar"],
          tooltip = L["Hides Blizzard's small green performance (FPS / latency) bar."],
          get = function() return mod.db.hidePerfBar end,
          set = function(_, v) mod.db.hidePerfBar = v; if mod.active then applyPerfBar() end end },
        { type = "checkbox", label = L["Hide the micro menu"],
          tooltip = L["Hides the row of menu buttons (character, spellbook, …)."],
          get = function() return mod.db.hideMicroMenu end,
          set = function(_, v) mod.db.hideMicroMenu = v; if mod.active then applyMicroBags() end end },
        { type = "checkbox", label = L["Hide the bag bar"],
          tooltip = L["Hides the backpack and bag slots."],
          get = function() return mod.db.hideBags end,
          set = function(_, v) mod.db.hideBags = v; if mod.active then applyMicroBags() end end },
        { type = "slider", label = L["Fade speed (sec.)"], min = 0.05, max = 0.6, step = 0.01, width = 180,
          get = function() return mod.db.fadeSpeed end,
          set = function(_, v) mod.db.fadeSpeed = v end },
        { type = "desc",
          text = L["|cff9b6cffThe micro menu, bag bar, FPS/latency bar and the XP bar below are movable in Edit Mode (/vedit) like the action bars.|r"] },
        { type = "section", title = L["XP bar"], collapsed = true, items = {
            { type = "checkbox", label = L["Show a custom XP bar"],
              tooltip = L["A movable, resizable experience bar with rested overlay. Hidden at max level. Replaces Blizzard's bar while on."],
              get = function() return mod.db.xpbar.on end,
              set = function(_, v) mod.db.xpbar.on = v; if mod.active then applyXPBar(); applyStatusBar() end end },
            { type = "group", layout = "row", gap = 8, items = {
                { type = "slider", label = L["Width"], min = 120, max = 900, step = 10, width = 160,
                  get = function() return mod.db.xpbar.width end,
                  set = function(_, v) mod.db.xpbar.width = v; if mod.active then applyXPBar() end end },
                { type = "slider", label = L["Height"], min = 6, max = 32, step = 1, width = 160,
                  get = function() return mod.db.xpbar.height end,
                  set = function(_, v) mod.db.xpbar.height = v; if mod.active then applyXPBar() end end },
                { type = "color", label = L["Colour"], width = 120,
                  get = function() return mod.db.xpbar.color end,
                  set = function(r, g, b) mod.db.xpbar.color = { r = r, g = g, b = b }; if mod.active then updateXPBar() end end },
            } },
        } },
    }
    for _, key in ipairs({ "main", "bottomleft", "bottomright", "right", "left", "stance", "pet" }) do
        items[#items + 1] = barSection(BAR_BY_KEY[key])
    end
    return items
end
