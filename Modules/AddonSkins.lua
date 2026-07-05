-- =========================================================
-- VuloClassicUI / Modules / AddonSkins
-- Restyles OTHER installed addons' windows to the house look (dark panel,
-- accent border, own font/buttons). Cosmetic runtime-only changes — nothing
-- of the target addons is modified on disk or redistributed.
--
-- Per-target notes (all frame names verified against the installed versions):
--   * BugSack        — window is created lazily on first open -> hook
--                      BugSack:OpenSack; raw-texture chrome, no re-paint.
--   * Questie        — the CLEAN path: drive Questie's own profile settings
--                      (LSM font "Expressway", backdrop keys + their current*
--                      mirrors) and let its tracker keep the look itself.
--                      Original values are backed up and restored on disable.
--   * AtlasLoot      — eager GUI; its refresh only re-colors ITS backdrop
--                      (behind our overlay textures) -> overlay wins.
--   * HealPredict    — options window is already dark; align backdrop/border.
--   * AddonProfiler  — eager ButtonFrameTemplate window; same chrome-strip
--                      recipe as the friends frame.
--
-- Toggling a skin OFF generally needs a /reload (texture strips are
-- session-permanent); the Questie toggle restores live.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("addonskins", {
    name        = "Addon Skins",
    group       = "UI Reskin",
    description = "Restyles supported third-party addon windows to match the dark look: error list, quest tracker, loot browser, profiler and more.",
    defaults = {
        enabled       = true,
        bugsack       = true,
        questie       = true,
        atlasloot     = true,
        healpredict   = true,
        addonprofiler = true,
        novaworldbuffs      = true,
        novainstancetracker = true,
        questieBackup = nil,   -- Questie settings before we touched them
    },
})

local sk = { done = {} }   -- [key] = true once a skin is applied

local function loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

-- =========================================================
-- Shared recipes (the proven house kit)
-- =========================================================
local function stripTextures(region)
    for _, r in ipairs({ region:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            r:SetTexture(nil)
            r:SetAlpha(0)
        end
    end
end

local function panelize(f, opts)
    local UI = ns.UI
    if not (UI and UI.StyleBackdrop) then return end
    UI:StyleBackdrop(f, { bg = (opts and opts.bg) or ns.COLORS.bg,
        border = ns.COLORS.accentDim or ns.COLORS.border })
    if UI.CreateShadow and not (opts and opts.noShadow) then UI:CreateShadow(f) end
    if not (opts and opts.noStrip) then
        local strip = f:CreateTexture(nil, "ARTWORK")
        strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        strip:SetHeight(2)
        if UI.SetGradient then
            local a = ns.COLORS.accent
            UI.SetGradient(strip, "HORIZONTAL", a.r, a.g, a.b, 0.1, a.r, a.g, a.b, 0.9)
        end
    end
end

local function buttonFonts()
    if sk.fontN then return end
    local UI = ns.UI
    sk.fontN = _G.VCUI_SkinFontNormal or CreateFont("VCUI_SkinFontNormal")
    sk.fontH = _G.VCUI_SkinFontHighlight or CreateFont("VCUI_SkinFontHighlight")
    sk.fontD = _G.VCUI_SkinFontDisabled or CreateFont("VCUI_SkinFontDisabled")
    if UI and UI.FONT_PATH then
        sk.fontN:SetFont(UI.FONT_PATH, 12, "")
        sk.fontH:SetFont(UI.FONT_PATH, 12, "")
        sk.fontD:SetFont(UI.FONT_PATH, 12, "")
    end
    local ac = ns.COLORS.accent
    sk.fontN:SetTextColor(0.9, 0.9, 0.95)
    sk.fontH:SetTextColor(ac.r, ac.g, ac.b)
    sk.fontD:SetTextColor(0.45, 0.45, 0.5)
end

local function skinButton(b)
    if not b or b._vcuiSkin then return end
    b._vcuiSkin = true
    buttonFonts()
    local ac = ns.COLORS.accent
    local bc = ns.COLORS.border or { r = 0.22, g = 0.22, b = 0.27 }
    stripTextures(b)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.13, 0.13, 0.16, 1)
    local edges = {}
    for i = 1, 4 do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    if b.SetNormalFontObject then b:SetNormalFontObject(sk.fontN) end
    if b.SetHighlightFontObject then b:SetHighlightFontObject(sk.fontH) end
    if b.SetDisabledFontObject then b:SetDisabledFontObject(sk.fontD) end
    b:HookScript("OnEnter", function()
        bg:SetColorTexture(0.19, 0.19, 0.23, 1)
        for _, t in ipairs(edges) do t:SetColorTexture(ac.r, ac.g, ac.b, 0.9) end
    end)
    b:HookScript("OnLeave", function()
        bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        for _, t in ipairs(edges) do t:SetColorTexture(bc.r, bc.g, bc.b, 1) end
    end)
end

-- flat tab: strip the art, keep the label (PanelTemplates keeps toggling the
-- alpha-0 pieces — harmless)
local function skinTab(tab)
    if not tab or tab._vcuiSkin then return end
    tab._vcuiSkin = true
    stripTextures(tab)
    local tabName = tab.GetName and tab:GetName()
    local fs = tab.Text or (tabName and _G[tabName .. "Text"])
        or (tab.GetFontString and tab:GetFontString())
    if fs then
        if ns.UI and ns.UI.Font then ns.UI.Font(fs, 11) end
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -8, 4)
        bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 8, -4)
        bg:SetColorTexture(0.10, 0.10, 0.13, 0.95)
    end
end

-- ButtonFrameTemplate chrome off. On the classic client the template's look
-- is built from INDIVIDUALLY NAMED corner/border textures (the NineSlice is
-- inert there — same finding as the friends frame), so hide every piece via
-- parentKey AND its "$parentPiece" global name.
local BFT_PIECES = {
    "Bg", "TitleBg", "Portrait", "PortraitFrame", "PortraitOverlay",
    "TopRightCorner", "TopLeftCorner", "TopBorder", "TopTileStreaks",
    "BotLeftCorner", "BotRightCorner", "BottomBorder",
    "LeftBorder", "RightBorder",
    "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder", "InsetBg",
}
local function stripButtonFrame(f)
    local function off(r) if r and r.SetAlpha then r:SetAlpha(0) end end
    local name = f.GetName and f:GetName()
    for _, piece in ipairs(BFT_PIECES) do
        off(f[piece])
        if name then off(_G[name .. piece]) end
    end
    off(f.NineSlice)
    if f.portrait then off(f.portrait) end
    if f.PortraitContainer then off(f.PortraitContainer) end
    if f.TitleContainer and f.TitleContainer.TitleBg then off(f.TitleContainer.TitleBg) end
    if f.Inset then
        off(f.Inset.Bg)
        off(f.Inset.NineSlice)
    end
end

-- red round close button -> flat × with accent hover
local function skinClose(cb)
    if not cb or cb._vcuiClose then return end
    cb._vcuiClose = true
    stripTextures(cb)
    local ac = ns.COLORS.accent
    local x = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if ns.UI and ns.UI.Font then ns.UI.Font(x, 16) end
    x:SetPoint("CENTER", cb, "CENTER", 0, 0)
    x:SetText("×")
    x:SetTextColor(0.8, 0.8, 0.85)
    cb:HookScript("OnEnter", function() x:SetTextColor(ac.r, ac.g, ac.b) end)
    cb:HookScript("OnLeave", function() x:SetTextColor(0.8, 0.8, 0.85) end)
end

-- =========================================================
-- BugSack (lazy window; hook OpenSack)
-- =========================================================
function sk.skinBugSack()
    if sk.done.bugsack or mod.db.bugsack == false then return end
    local f = _G.BugSackFrame
    if not f then return end
    sk.done.bugsack = true
    stripTextures(f)                    -- 8-piece border + dialog/title art
    panelize(f)
    skinButton(_G.BugSackNextButton)
    skinButton(_G.BugSackPrevButton)
    skinButton(_G.BugSackSendButton)
    skinTab(_G.BugSackTabAll)
    skinTab(_G.BugSackTabSession)
    skinTab(_G.BugSackTabLast)
end

function sk.armBugSack()
    if sk.armed_bugsack then return end
    local bs = _G.BugSack
    if not (bs and type(bs.OpenSack) == "function") then return end
    hooksecurefunc(bs, "OpenSack", function()
        if mod.active then sk.skinBugSack() end
    end)
    sk.armed_bugsack = true   -- after the hook: a hook error must not latch
    sk.skinBugSack()   -- in case it is already open
end

-- =========================================================
-- Questie tracker (drive its OWN profile settings; backup + live restore)
-- =========================================================
function sk.questieUpdate()
    local ok, QT = pcall(function()
        return QuestieLoader and QuestieLoader.ImportModule
            and QuestieLoader:ImportModule("QuestieTracker")
    end)
    if ok and QT and QT.Update then pcall(QT.Update, QT) end
end

-- accent decoration: zone/section header lines get the accent color and a
-- thin underline (the modern-tracker look). Lines are pooled globals
-- ("linePool1".."linePool250") repainted on every tracker update, so this
-- runs as a posthook on QuestieTracker:Update and always wins.
function sk.questieDecorate()
    if not mod.active or mod.db.questie == false then return end
    local ac = ns.COLORS.accent
    local hex = string.format("%02x%02x%02x",
        math.floor(ac.r * 255 + 0.5), math.floor(ac.g * 255 + 0.5),
        math.floor(ac.b * 255 + 0.5))
    for i = 1, 250 do
        local line = _G["linePool" .. i]
        if not (line and line.IsShown) then break end
        if line:IsShown() and line.mode == "zone" and line.label then
            -- zone headers carry an EMBEDDED |cFF..|r escape in the label
            -- text which overrides SetTextColor — rewrite the escape itself
            local txt = line.label:GetText()
            if txt then
                local newTxt, nrep = txt:gsub("^|c%x%x%x%x%x%x%x%x", "|cff" .. hex)
                if nrep > 0 and newTxt ~= txt then line.label:SetText(newTxt) end
            end
            line.label:SetTextColor(ac.r, ac.g, ac.b, 1)  -- escape-less builds
            if not line._vcUnderline then
                local u = line:CreateTexture(nil, "ARTWORK")
                u:SetHeight(1)
                -- both points on the label's bottom edge: a second vertical
                -- constraint anywhere else overrides SetHeight entirely
                u:SetPoint("TOPLEFT",  line.label, "BOTTOMLEFT",  0, -2)
                u:SetPoint("TOPRIGHT", line.label, "BOTTOMRIGHT", 0, -2)
                line._vcUnderline = u
            end
            line._vcUnderline:SetColorTexture(ac.r, ac.g, ac.b, 0.55)
            line._vcUnderline:Show()
        elseif line._vcUnderline then
            line._vcUnderline:Hide()
        end
    end
end

function sk.hookQuestieTracker()
    if sk.questieHooked then return end
    local ok, QT = pcall(function()
        return QuestieLoader and QuestieLoader.ImportModule
            and QuestieLoader:ImportModule("QuestieTracker")
    end)
    if ok and QT and QT.Update then
        sk.questieHooked = true
        hooksecurefunc(QT, "Update", sk.questieDecorate)
    end
end

function sk.skinQuestie()
    if mod.db.questie == false then return end
    -- once per session: without this, every loading screen re-stomps the
    -- profile keys and reverts tracker changes the user made in between
    if sk.done.questie then sk.hookQuestieTracker(); return end
    local q = _G.Questie
    local p = q and q.db and q.db.profile
    if not p then return end
    sk.hookQuestieTracker()
    if not mod.db.questieBackup
       -- if the profile ALREADY carries our exact skin values (fresh VCUI
       -- profile mid-session while the tracker is skinned), backing them up
       -- would enshrine the skin as "original" — leave the backup empty
       and not (p.trackerFontQuest == "Expressway"
                and p.trackerBackdropEnabled == true
                and p.trackerBorderEnabled == false) then
        mod.db.questieBackup = {
            fq = p.trackerFontQuest,   fo = p.trackerFontObjective,
            fz = p.trackerFontZone,    fh = p.trackerFontHeader,
            be = p.trackerBackdropEnabled, bo = p.trackerBorderEnabled,
            bc = p.trackerBackdropColor,
        }
    end
    p.trackerFontQuest      = "Expressway"
    p.trackerFontObjective  = "Expressway"
    p.trackerFontZone       = "Expressway"
    p.trackerFontHeader     = "Expressway"
    p.trackerBackdropEnabled = true
    p.trackerBorderEnabled   = false
    local bg = ns.COLORS.bg
    p.trackerBackdropColor = { r = bg.r, g = bg.g, b = bg.b, a = 0.78 }
    -- the resize handler restores from these mirrors — keep them in sync or
    -- a single tracker resize reverts the whole skin
    p.currentBackdropEnabled = true
    p.currentBorderEnabled   = false
    sk.done.questie = true
    sk.questieUpdate()
end

function sk.restoreQuestie()
    local b = mod.db.questieBackup
    local q = _G.Questie
    local p = q and q.db and q.db.profile
    if not (b and p) then return end
    p.trackerFontQuest       = b.fq
    p.trackerFontObjective   = b.fo
    p.trackerFontZone        = b.fz
    p.trackerFontHeader      = b.fh
    p.trackerBackdropEnabled = b.be
    p.trackerBorderEnabled   = b.bo
    p.trackerBackdropColor   = b.bc
    p.currentBackdropEnabled = b.be
    p.currentBorderEnabled   = b.bo
    mod.db.questieBackup = nil
    sk.done.questie = nil
    sk.questieUpdate()
end

-- =========================================================
-- AtlasLoot browser (eager GUI; overlay textures beat its color refreshes)
-- =========================================================
function sk.skinAtlasLoot()
    if sk.done.atlasloot or mod.db.atlasloot == false then return end
    local f = _G["AtlasLoot_GUI-Frame"]
    if not f then return end
    sk.done.atlasloot = true
    panelize(f)
    if f.titleFrame then
        panelize(f.titleFrame, { bg = { r = 0.07, g = 0.07, b = 0.1, a = 0.95 }, noShadow = true, noStrip = true })
        if f.titleFrame.text and ns.UI and ns.UI.Font then ns.UI.Font(f.titleFrame.text, 13) end
    end
    local cf = f.contentFrame
    if cf then
        skinButton(cf.itemsButton)
        skinButton(cf.modelButton)
        skinButton(cf.soundsButton)
    end
    skinClose(f.CloseButton or _G["AtlasLoot_GUI-Frame-CloseButton"])
end

function sk.armAtlasLoot()
    if sk.armed_atlasloot then return end
    local al = _G.AtlasLoot
    if not (al and al.GUI) then return end
    if type(al.GUI.Create) == "function" then
        hooksecurefunc(al.GUI, "Create", function()
            if mod.active then sk.skinAtlasLoot() end
        end)
    end
    if type(al.GUI.Toggle) == "function" then
        hooksecurefunc(al.GUI, "Toggle", function()
            if mod.active then sk.skinAtlasLoot() end
        end)
    end
    sk.armed_atlasloot = true   -- after the hooks: a hook error must not latch
    sk.skinAtlasLoot()
end

-- =========================================================
-- HealPredict options window (already dark — align panel + border)
-- =========================================================
-- cyan accent text -> our accent (title, active tab labels, links)
function sk.hpRecolorText(frame)
    if not frame then return end
    local ac = ns.COLORS.accent
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
            local cr, cg, cb = r:GetTextColor()
            if cr and cb and cb > 0.85 and cg > 0.55 and cr < 0.45 then
                r:SetTextColor(ac.r, ac.g, ac.b)
            end
        end
    end
end

function sk.skinHealPredict()
    if sk.done.healpredict or mod.db.healpredict == false then return end
    local f = _G.HP_OptionsFrame
    if not f then return end   -- created during the addon's init; retried later
    sk.done.healpredict = true
    if f.SetBackdropColor then
        local bg = ns.COLORS.bg
        f:SetBackdropColor(bg.r, bg.g, bg.b, 0.97)
    end
    if f.SetBackdropBorderColor then
        local bd = ns.COLORS.accentDim or ns.COLORS.border
        f:SetBackdropBorderColor(bd.r, bd.g, bd.b, 1)
    end
    if ns.UI and ns.UI.CreateShadow then ns.UI:CreateShadow(f) end
    sk.hpRecolorText(f)

    -- text buttons (profile row, Defaults / Layout / Test Mode ...) -> house
    -- style. Checkboxes, sliders and textured icon buttons stay untouched.
    local function skinButtonsIn(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            local ot = child.GetObjectType and child:GetObjectType()
            if ot == "Button" and not child._vcuiSkin and not child._vcuiClose then
                local fs = child.GetFontString and child:GetFontString()
                local txt = fs and fs:GetText()
                if txt and txt ~= "" then skinButton(child) end
            end
            if depth > 1 and ot == "Frame" then skinButtonsIn(child, depth - 1) end
        end
    end
    skinButtonsIn(f, 2)

    -- the active-tab cyan is re-applied on every tab switch -> recolor a
    -- frame later, after its own paint ran
    for i = 1, 5 do
        local tab = _G["HP_Tab" .. i]
        if tab then
            sk.hpRecolorText(tab)
            tab:HookScript("OnClick", function()
                if not (mod.active and C_Timer and C_Timer.After) then return end
                C_Timer.After(0, function()
                    for j = 1, 5 do sk.hpRecolorText(_G["HP_Tab" .. j]) end
                    sk.hpRecolorText(f)
                end)
            end)
        end
    end
end

function sk.armHealPredict()
    -- no global addon table to hook — the options window is built during the
    -- addon's own init sequence; applyLoaded's retries pick it up
    sk.skinHealPredict()
end

-- =========================================================
-- Addon Profiler (eager ButtonFrameTemplate window)
-- =========================================================
function sk.skinAddonProfiler()
    if sk.done.addonprofiler or mod.db.addonprofiler == false then return end
    local nap = _G.NumyAddonProfiler
    local f = (nap and nap.ProfilerFrame) or _G.NumyAddonProfilerFrame
    if not f then return end
    sk.done.addonprofiler = true
    stripButtonFrame(f)
    panelize(f)
    skinClose(f.CloseButton or _G.NumyAddonProfilerFrameCloseButton)
    local title = f.TitleContainer and f.TitleContainer.TitleText
    if title and ns.UI and ns.UI.Font then
        ns.UI.Font(title, 13)
    end
    skinButton(_G.NumyAddonProfilerFrameToggle)
    skinButton(_G.NumyAddonProfilerFrameReset)
    -- pin window: plain dark frame with its own bg texture — align it
    local pin = nap and nap.PinContainer
    if pin then panelize(pin, { noStrip = true }) end
end

-- =========================================================
-- Nova-family windows (world-buff timers + instance tracker, same author,
-- same architecture): every window is a ScrollFrame on an InputScrollFrame
-- template whose visible chrome is a set of input-border TEXTURES
-- (parentKeys below), plus a WHITE8x8 backdrop painted ONCE at load — so a
-- restyle applied after load is durable. All windows exist right after the
-- addon loads (nothing lazy except two tracker sub-windows, hooked below);
-- nothing in these windows is secure.
-- =========================================================
local NOVA_BORDER_KEYS = {
    "TopLeftTex", "TopRightTex", "BottomLeftTex", "BottomRightTex",
    "TopTex", "BottomTex", "LeftTex", "RightTex", "MiddleTex",
}

function sk.novaWindow(f, opts)
    if not f or f._vcuiSkin then return end
    f._vcuiSkin = true
    for _, k in ipairs(NOVA_BORDER_KEYS) do
        local t = f[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    -- some of their windows use a backdrop EDGE file (gold tooltip ring /
    -- orange chat-border) instead of the texture set — the edge draws above
    -- our overlay panel, so tint it away
    if f.SetBackdropBorderColor then
        pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 0)
    end
    panelize(f, opts)
    local n = f.GetName and f:GetName()
    if n then
        skinClose(_G[n .. "Close"] or _G[n .. "CloseButton"])
    end
end

function sk.skinNovaWorldBuffs()
    if sk.done.novaworldbuffs or mod.db.novaworldbuffs == false then return end
    if not _G.NWBlayerFrame then return end   -- all windows exist after load
    sk.done.novaworldbuffs = true
    for _, name in ipairs({
        "NWBlayerFrame", "NWBbuffListFrame", "NWBLayerMapFrame",
        "NWBVersionFrame", "NWBCopyFrame", "NWBTimerLogFrame", "NWBLFrame",
        "NWBDMFListFrame", "NWBDmfFrame",
    }) do
        sk.novaWindow(_G[name])
    end
    -- the layer window's bottom button row + the copy button
    skinButton(_G.NWBlayerFrameConfButton)
    skinButton(_G.NWBlayerFrameBuffsButton)
    skinButton(_G.NWBlayerFrameMapButton)
    skinButton(_G.NWBGuildLayersButton)
    skinButton(_G.NWBlayerFrameCopyButton)
    -- the darkmoon window's close carries a doubled-name typo upstream
    skinClose(_G.NWBDmfFrameFrameClose)

    -- the on-minimap LAYER READOUT: gold-edge template art off, thin dark
    -- panel + accent text instead (its frame has no backdrop mixin — build
    -- the panel from plain textures like the button recipe does)
    local ml = _G.MinimapLayerFrame
    if ml and not ml._vcuiSkin then
        ml._vcuiSkin = true
        stripTextures(ml)
        local bgc = ns.COLORS.bg
        local bg = ml:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(ml)
        bg:SetColorTexture(bgc.r, bgc.g, bgc.b, 0.9)
        local bc = ns.COLORS.accentDim or ns.COLORS.border
        local edges = {}
        for i = 1, 4 do
            local t = ml:CreateTexture(nil, "BORDER")
            t:SetColorTexture(bc.r, bc.g, bc.b, 0.9)
            edges[i] = t
        end
        edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
        if ml.fs then
            local ac = ns.COLORS.accent
            ml.fs:SetTextColor(ac.r, ac.g, ac.b, 1)
        end
    end
end

function sk.skinNovaInstanceTracker()
    if sk.done.novainstancetracker or mod.db.novainstancetracker == false then return end
    if not _G.NITInstanceFrame then return end
    sk.done.novainstancetracker = true
    for _, name in ipairs({
        "NITInstanceFrame", "NITTradeLogFrame", "NITTradeCopyFrame",
        "NITAltsFrame", "NITCopyFrame", "NITInstanceFrameDC",
        "NITCharsFrameDC", "NITPostInstanceStatsFrame",
    }) do
        sk.novaWindow(_G[name])
    end
    -- window buttons + off-pattern close names
    skinButton(_G.NITInstanceFrameConfButton)
    skinButton(_G.NITInstanceFrameTradesButton)
    skinButton(_G.NITInstanceFrameLockoutsButton)
    skinButton(_G.NITInstanceFrameRestedButton)
    skinButton(_G.NITTradeFrameCopyButton)
    -- both delete-confirm closes sit on off-pattern global names
    skinClose(_G.NITInstanceDCFrameClose)
    skinClose(_G.NITCharsDCFrameClose)
    -- gold-edge top bar of the copy popup
    if _G.NITCopyFrameTopBar then stripTextures(_G.NITCopyFrameTopBar) end
    -- two windows build lazily on first open — hook their loaders (the
    -- tracker's addon object IS global, unlike its sibling addon)
    local nit = _G.NIT
    if nit and not sk.nitHooked then
        sk.nitHooked = true
        if type(nit.openLockoutsFrame) == "function" then
            hooksecurefunc(nit, "openLockoutsFrame", function()
                if mod.active and mod.db.novainstancetracker ~= false then
                    sk.novaWindow(_G.NRCLockoutsFrame)   -- their (stale) global name
                end
            end)
        end
        if type(nit.loadLevelLogFrame) == "function" then
            hooksecurefunc(nit, "loadLevelLogFrame", function()
                if mod.active and mod.db.novainstancetracker ~= false then
                    local llf = _G.NITLevelLogFrame
                    sk.novaWindow(llf)
                    -- its attached header bar has its own backdrop + border
                    if llf and llf.topFrame then
                        sk.novaWindow(llf.topFrame, { noShadow = true })
                    end
                end
            end)
        end
    end
end

-- =========================================================
-- Arming: apply what's loaded now, watch ADDON_LOADED for the rest
-- =========================================================
local TARGETS = {
    { key = "bugsack",       addon = "BugSack" },
    { key = "questie",       addon = "Questie" },
    { key = "atlasloot",     addon = "AtlasLootClassic" },
    { key = "healpredict",   addon = "HealPredict" },
    { key = "addonprofiler", addon = "!!AddonProfiler" },
    { key = "novaworldbuffs",      addon = "NovaWorldBuffs" },
    { key = "novainstancetracker", addon = "NovaInstanceTracker" },
}

function sk.applyLoaded()
    if not mod.active then return end
    -- leftover skin from a session where the option was ON but this session
    -- has it OFF (restore only ever ran behind the session-local done flag)
    if mod.db.questie == false and mod.db.questieBackup then
        sk.restoreQuestie()
    end
    if loaded("BugSack") then sk.armBugSack() end
    if loaded("Questie") then sk.skinQuestie() end
    if loaded("AtlasLootClassic") then sk.armAtlasLoot() end
    if loaded("HealPredict") then sk.armHealPredict() end
    if loaded("!!AddonProfiler") then sk.skinAddonProfiler() end
    if loaded("NovaWorldBuffs") then sk.skinNovaWorldBuffs() end
    if loaded("NovaInstanceTracker") then sk.skinNovaInstanceTracker() end
end

local function onEvent(event, arg1)
    if not mod.active then return end
    if event == "ADDON_LOADED" then
        if arg1 == "BugSack" then sk.armBugSack()
        elseif arg1 == "Questie" then
            -- Questie's db exists after its load; the tracker starts later and
            -- reads the profile keys when it does
            sk.skinQuestie()
        elseif arg1 == "AtlasLootClassic" then sk.armAtlasLoot()
        elseif arg1 == "HealPredict" then sk.armHealPredict()
        elseif arg1 == "!!AddonProfiler" then sk.skinAddonProfiler()
        elseif arg1 == "NovaWorldBuffs" then sk.skinNovaWorldBuffs()
        elseif arg1 == "NovaInstanceTracker" then sk.skinNovaInstanceTracker()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        sk.applyLoaded()
        -- several targets build their windows in their own deferred init
        -- sequences (Questie tracker coroutine, lazily-built options) —
        -- re-apply a few times; every skin function is one-shot-guarded
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() if mod.active then sk.applyLoaded() end end)
            C_Timer.After(8, function()
                if mod.active then
                    sk.applyLoaded()
                    if sk.done.questie then
                        sk.hookQuestieTracker()
                        sk.questieUpdate()
                    end
                end
            end)
        end
    end
end

function mod:OnEnable()
    ns:RegisterEvent("ADDON_LOADED", onEvent)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", onEvent)
    sk.applyLoaded()
end

function mod:OnDisable()
    ns:UnregisterEvent("ADDON_LOADED", onEvent)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", onEvent)
    if sk.done.questie then sk.restoreQuestie() end
    -- texture strips on the other targets are session-permanent -> /reload
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    local items = {
        { type = "header", text = L["Addon Skins"] },
        { type = "desc", text = L["|cffaaaaaaRestyles the windows of supported addons to the dark look. Skins apply when the addon is loaded; turning one off needs a /reload (the quest tracker restores live).|r"] },
        { type = "spacer", height = 6 },
    }
    for _, t in ipairs(TARGETS) do
        local key, addonName = t.key, t.addon:gsub("^!+", "")
        local isLoaded = loaded(t.addon)
        table.insert(items, {
            type = "toggle",
            label = addonName .. (isLoaded and "" or (" |cff888888(" .. L["not loaded"] .. ")|r")),
            get = function() return mod.db[key] ~= false end,
            set = function(_, v)
                mod.db[key] = v and true or false
                if v then
                    sk.applyLoaded()
                elseif key == "questie" and sk.done.questie then
                    sk.restoreQuestie()
                end
            end,
        })
    end
    return items
end
