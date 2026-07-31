-- Addon skins: runtime-only restyling of other addons' windows; texture strips are session-permanent (/reload to undo).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("addonskins", {
    -- Strict grid: with an odd target count the last toggle stretched across
    -- the page with its switch far from the label (user report, 31.07.2026).
    -- On the grid a lone row keeps its half.
    optionsGrid = true,
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
        gargul        = true,
        attune        = true,
        wowsims       = true,
        leamaps       = true,
        questieBackup = nil,
    },
})

local sk = { done = {} }

local function loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

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
    sk.fontN, sk.fontH, sk.fontD = ns.UI:PanelButtonFonts("VCUI_SkinFont")
end

local function skinButton(b)
    if not b or b._vcuiSkin then return end
    buttonFonts()
    ns.UI:SkinPanelButton(b, { fonts = { sk.fontN, sk.fontH, sk.fontD } })
end

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

-- on this client the template chrome is built from individually named textures (the NineSlice is inert), so hide both the parentKey and the $parent global
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

function sk.skinBugSack()
    if sk.done.bugsack or mod.db.bugsack == false then return end
    local f = _G.BugSackFrame
    if not f then return end
    sk.done.bugsack = true
    stripTextures(f)
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
    sk.skinBugSack()
end

function sk.questieUpdate()
    local ok, QT = pcall(function()
        return QuestieLoader and QuestieLoader.ImportModule
            and QuestieLoader:ImportModule("QuestieTracker")
    end)
    if ok and QT and QT.Update then pcall(QT.Update, QT) end
end

-- the lines are pooled globals "linePool1".."linePool250" repainted on every tracker update, so decorate as a posthook
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
            -- the label carries an embedded |cFF..|r escape that overrides SetTextColor; rewrite the escape itself
            local txt = line.label:GetText()
            if txt then
                local newTxt, nrep = txt:gsub("^|c%x%x%x%x%x%x%x%x", "|cff" .. hex)
                if nrep > 0 and newTxt ~= txt then line.label:SetText(newTxt) end
            end
            line.label:SetTextColor(ac.r, ac.g, ac.b, 1)
            if not line._vcUnderline then
                local u = line:CreateTexture(nil, "ARTWORK")
                u:SetHeight(1)
                -- both points on the label's bottom edge: any second vertical constraint overrides SetHeight
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
    -- once per session: otherwise every loading screen re-stomps the profile keys
    if sk.done.questie then sk.hookQuestieTracker(); return end
    local q = _G.Questie
    local p = q and q.db and q.db.profile
    if not p then return end
    sk.hookQuestieTracker()
    if not mod.db.questieBackup
       -- the profile already holds our skin values: backing them up would enshrine the skin as the original
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
    -- the resize handler restores from these mirrors; keep them in sync
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

function sk.skinAtlasLootPVP()
    if sk.done.atlaslootpvp or mod.db.atlasloot == false then return end
    local p = _G.AtlasLootPVPSidePanel
    if not p then return end
    sk.done.atlaslootpvp = true
    if p.SetBackdrop then p:SetBackdrop(nil) end
    panelize(p)
    if ns.UI and ns.UI.Font then
        for _, r in ipairs({ p:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("FontString") then
                local _, size = r:GetFont()
                ns.UI.Font(r, math.max(10, math.floor((size or 12) + 0.5)))
            end
        end
    end
    for _, child in ipairs({ p:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Button")
            and child.GetText and child:GetText() then
            skinButton(child)
        end
    end
    skinButton(_G.AtlasLootPVPCalcToggleButton)
    -- Flush with whatever it sits beside: same top edge, same bottom edge.
    -- Anchoring straight to CharacterFrame does NOT do that -- the Modern style
    -- paints its dark ground as a texture inset 6 from the top and 72 from the
    -- bottom, so the frame reaches well below anything you can see (the tabs sit
    -- in that gap). CharacterPanelModernExt reports those insets; the Loadouts
    -- sidebar docks through the same helper for the same reason.
    local function dock()
        local sb = _G.VCUI_LoadoutsSidebar
        p._vcuiDocking = true
        p:ClearAllPoints()
        if sb and sb:IsShown() then
            p:SetPoint("TOPLEFT",     sb, "TOPRIGHT",    2, 0)
            p:SetPoint("BOTTOMLEFT",  sb, "BOTTOMRIGHT", 2, 0)
        elseif _G.CharacterFrame then
            -- classic art has its own frame/edge margins, hence the fallback pair
            local x, top, bottom = 6, -8, 45
            if ns.CharacterPanelModernExt then
                local ext, extTop, extBot, modernOn = ns.CharacterPanelModernExt()
                if modernOn then x, top, bottom = 6 + ext, extTop, extBot end
            end
            p:SetPoint("TOPLEFT",     _G.CharacterFrame, "TOPRIGHT",    x, top)
            p:SetPoint("BOTTOMLEFT",  _G.CharacterFrame, "BOTTOMRIGHT", x, bottom)
        end
        p._vcuiDocking = nil
    end
    dock()
    p:HookScript("OnShow", dock)

    -- Re-assert from a SetPoint hook so nothing else can move it back; same
    -- idiom as pinFrame in Modules/ActionBars.lua. The flag keeps our own two
    -- calls above from re-entering it.
    if not p._vcuiDockHook then
        p._vcuiDockHook = true
        hooksecurefunc(p, "SetPoint", function(self)
            if self._vcuiDocking or not mod.active then return end
            dock()
        end)
    end
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
    if _G.PVPFrame and not sk.armed_atlaslootpvp then
        sk.armed_atlaslootpvp = true
        _G.PVPFrame:HookScript("OnShow", function()
            if mod.active then sk.skinAtlasLootPVP() end
        end)
    end
    sk.armed_atlasloot = true
    sk.skinAtlasLoot()
    sk.skinAtlasLootPVP()
end

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
    if not f then return end
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

    -- the active-tab color is re-applied on every tab switch, so recolor after its own paint
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
    -- no global table to hook; the retries in applyLoaded pick the window up
    sk.skinHealPredict()
end

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
    local pin = nap and nap.PinContainer
    if pin then panelize(pin, { noStrip = true }) end
end

-- the visible chrome is a set of named border textures plus a backdrop painted once at load, so a late restyle is durable
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
    -- some windows use a backdrop edge file that draws above our panel; tint it away
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
    skinButton(_G.NWBlayerFrameConfButton)
    skinButton(_G.NWBlayerFrameBuffsButton)
    skinButton(_G.NWBlayerFrameMapButton)
    skinButton(_G.NWBGuildLayersButton)
    skinButton(_G.NWBlayerFrameCopyButton)
    -- the darkmoon window's close carries a doubled-name typo upstream
    skinClose(_G.NWBDmfFrameFrameClose)

    -- this frame has no backdrop mixin, so build the panel from plain textures
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
    skinButton(_G.NITInstanceFrameConfButton)
    skinButton(_G.NITInstanceFrameTradesButton)
    skinButton(_G.NITInstanceFrameLockoutsButton)
    skinButton(_G.NITInstanceFrameRestedButton)
    skinButton(_G.NITTradeFrameCopyButton)
    skinClose(_G.NITInstanceDCFrameClose)
    skinClose(_G.NITCharsDCFrameClose)
    if _G.NITCopyFrameTopBar then stripTextures(_G.NITCopyFrameTopBar) end
    -- two windows build lazily on first open; hook their loaders
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
                    if llf and llf.topFrame then
                        sk.novaWindow(llf.topFrame, { noShadow = true })
                    end
                end
            end)
        end
    end
end

-- AceGUI-3.0 frame: the widget back-reference is frame.obj (titletext/titlebg live on the widget, not the frame)
function sk.skinAceGUIFrame(f)
    if not f or f._vcuiSkin then return end
    f._vcuiSkin = true
    local w = f.obj
    if f.SetBackdropColor then pcall(f.SetBackdropColor, f, 0, 0, 0, 0) end
    if f.SetBackdropBorderColor then pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 0) end
    panelize(f)
    -- header art: the widget's titlebg plus two unnamed sibling textures (file id 131080)
    if w and w.titlebg and w.titlebg.SetAlpha then w.titlebg:SetAlpha(0) end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            local tex = r.GetTexture and r:GetTexture()
            if tex == 131080 or (type(tex) == "string" and tex:find("Header")) then
                r:SetAlpha(0)
            end
        end
    end
    if w then
        if w.titletext then
            if ns.UI and ns.UI.Font then ns.UI.Font(w.titletext, 13) end
            local ac = ns.COLORS.accent
            w.titletext:SetTextColor(ac.r, ac.g, ac.b, 1)
        end
        if w.statustext then w.statustext:SetTextColor(0.7, 0.7, 0.75, 1) end
    end
    -- close text button (child 1) + status backdrop (child 2)
    local closebutton, statusbg = f:GetChildren()
    if closebutton and closebutton.GetObjectType and closebutton:GetObjectType() == "Button" then
        skinButton(closebutton)
    end
    if statusbg then
        if statusbg.SetBackdropColor then pcall(statusbg.SetBackdropColor, statusbg, 0.10, 0.10, 0.13, 0.9) end
        if statusbg.SetBackdropBorderColor then pcall(statusbg.SetBackdropBorderColor, statusbg, 0, 0, 0, 0) end
    end
end

-- two render paths: named builder windows via Interface:createWindow, AceGUI widgets via Interface:set, plus two bars hooked on :draw
function sk.skinGargulBuilder(f)
    if not f or f._vcuiSkin then return end
    f._vcuiSkin = true
    if f.SetBackdropColor then pcall(f.SetBackdropColor, f, 0, 0, 0, 0) end
    if f.SetBackdropBorderColor then pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 0) end
    panelize(f)
    if f.CloseButton then skinClose(f.CloseButton) end
    if f.Watermark and f.Watermark.SetAlpha then f.Watermark:SetAlpha(0) end
end

function sk.skinGargulBar(f)
    if not f or f._vcuiSkin then return end
    f._vcuiSkin = true
    panelize(f, { noShadow = true })
end

function sk.skinGargulExisting()
    if not (mod.active and mod.db.gargul ~= false) then return end
    sk.skinGargulBar(_G.GargulUI_RollerUI_Window)
    sk.skinGargulBar(_G.GARGUL_GDKP_BIDDER_WINDOW)
    for _, n in ipairs({
        "GARGUL_AWARD_WINDOW", "GARGUL_SETTING_WINDOW", "GARGUL_TMB_OVERVIEW_WINDOW",
        "GARGUL_SOFTRES_OVERVIEW_WINDOW", "GARGUL_PLUSONES_OVERVIEW_WINDOW",
        "GARGUL_BOOSTEDROLLS_OVERVIEW_WINDOW", "GARGUL_PLAYER_SELECTOR_WINDOW",
        "GARGUL_RAID_GROUP_WINDOW", "GARGUL_EXPORTER_WINDOW",
        "GARGUL_MASTER_LOOTER_DIALOG_WINDOW",
    }) do
        if _G[n] then sk.skinAceGUIFrame(_G[n]) end
    end
end

function sk.armGargul()
    if sk.armed_gargul then return end
    local G = _G.Gargul
    if not (G and G.Interface and type(G.Interface.createWindow) == "function") then return end
    sk.armed_gargul = true
    hooksecurefunc(G.Interface, "createWindow", function(_, opts)
        if not (mod.active and mod.db.gargul ~= false) then return end
        if type(opts) == "table" and opts.name then
            sk.skinGargulBuilder(_G[opts.name])
        end
    end)
    if type(G.Interface.set) == "function" then
        hooksecurefunc(G.Interface, "set", function(_, _, _, Item)
            if not (mod.active and mod.db.gargul ~= false) then return end
            if type(Item) == "table" and Item.frame and Item.type == "Frame" then
                sk.skinAceGUIFrame(Item.frame)
            end
        end)
    end
    if G.RollerUI and type(G.RollerUI.draw) == "function" then
        hooksecurefunc(G.RollerUI, "draw", function()
            if mod.active and mod.db.gargul ~= false then sk.skinGargulBar(_G.GargulUI_RollerUI_Window) end
        end)
    end
    local Bidder = G.Interface.GDKP and G.Interface.GDKP.Bidder
    if Bidder and type(Bidder.draw) == "function" then
        hooksecurefunc(Bidder, "draw", function()
            if mod.active and mod.db.gargul ~= false then sk.skinGargulBar(_G.GARGUL_GDKP_BIDDER_WINDOW) end
        end)
    end
    sk.skinGargulExisting()
end

-- built lazily on first open; the per-row node colors carry state and stay untouched
function sk.skinAttune()
    if sk.done.attune or mod.db.attune == false then return end
    local f = _G.Attune_MainFrame
    if not f then return end   -- only exists after its lazy builder ran
    sk.done.attune = true
    sk.skinAceGUIFrame(f)
    for _, child in ipairs({ f:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
            local fs = child.GetFontString and child:GetFontString()
            local txt = fs and fs:GetText()
            if txt and txt ~= "" then skinButton(child) end
        end
    end
end

function sk.armAttune()
    if sk.armed_attune then return end
    if type(_G.Attune_Frame) ~= "function" then return end
    sk.armed_attune = true
    hooksecurefunc("Attune_Frame", function()
        if mod.active and mod.db.attune ~= false then sk.skinAttune() end
    end)
    if _G.Attune_MainFrame then sk.skinAttune() end
end

-- the addon's own tables are local, so every control is reached by walking the frame's regions/children
function sk.skinMapAddonPanel(f)
    if not f or f._vcuiSkin then return end
    f._vcuiSkin = true
    for _, r in ipairs({ f:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            local tex = r.GetTexture and r:GetTexture()
            if type(tex) == "string" and tex:lower():find("parchment") then
                r:SetAlpha(0)
            end
        end
    end
    panelize(f)
    local ac = ns.COLORS.accent
    for _, r in ipairs({ f:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
            if r == f.v then
                r:SetTextColor(0.6, 0.6, 0.66)
            else
                local cr, cg, cb = r:GetTextColor()
                if cr and cr > 0.8 and cg > 0.7 and (cb or 0) < 0.35 then
                    r:SetTextColor(ac.r, ac.g, ac.b)
                end
            end
        end
    end
    for _, c in ipairs({ f:GetChildren() }) do
        local ot = c.GetObjectType and c:GetObjectType()
        -- a dropdown is a direct child too; never skin it as a plain button
        local isDropdown = c.SetupMenu ~= nil or c.OpenMenu ~= nil or c.Arrow ~= nil
        if ot == "Button" and not isDropdown then
            local fs = c.GetFontString and c:GetFontString()
            local txt = fs and fs:GetText()
            if txt and txt ~= "" then
                skinButton(c)
                if c.f and c.f.SetTextColor then c.f:SetTextColor(0.9, 0.9, 0.95) end
            else
                local w = (c.GetWidth and c:GetWidth()) or 0
                local h = (c.GetHeight and c:GetHeight()) or 0
                if w >= 28 and h >= 28 and math.abs(w - h) < 6 then
                    skinClose(c)   -- the 30x30 UIPanelCloseButton
                end
            end
        elseif ot == "CheckButton" then
            if c.f and c.f.SetTextColor then c.f:SetTextColor(0.9, 0.9, 0.95) end
        end
    end
end

function sk.skinMapAddon()
    if not (mod.active and mod.db.leamaps ~= false) then return end
    if _G.LeaMapsGlobalPanel then sk.skinMapAddonPanel(_G.LeaMapsGlobalPanel) end
    -- the sub-panels share the same global-name prefix; one-time scan for the ones built at load
    if not sk.leamapsSubsScanned then
        sk.leamapsSubsScanned = true
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("^LeaMapsGlobalPanel_") and type(v) == "table" then
                local ok, isFrame = pcall(function() return v.IsObjectType and v:IsObjectType("Frame") end)
                if ok and isFrame then sk.skinMapAddonPanel(v) end
            end
        end
    end
end

function sk.armMapAddon()
    if sk.armed_leamaps then return end
    local f = _G.LeaMapsGlobalPanel
    if not f then return end
    sk.armed_leamaps = true
    sk.skinMapAddon()
    f:HookScript("OnShow", function()
        if mod.active and mod.db.leamaps ~= false then sk.skinMapAddon() end
    end)
end

local TARGETS = {
    { key = "bugsack",       addon = "BugSack" },
    { key = "questie",       addon = "Questie" },
    { key = "atlasloot",     addon = "AtlasLootClassic" },
    { key = "healpredict",   addon = "HealPredict" },
    { key = "addonprofiler", addon = "!!AddonProfiler" },
    { key = "novaworldbuffs",      addon = "NovaWorldBuffs" },
    { key = "novainstancetracker", addon = "NovaInstanceTracker" },
    { key = "gargul",              addon = "Gargul" },
    { key = "attune",              addon = "Attune" },
    { key = "wowsims",             addon = "WowSimsExporter" },
}

-- the button is created without a name, so it is found by its text among CharacterFrame's children
function sk.skinWowSims()
    if sk.done.wowsims or mod.db.wowsims == false then return end
    if not _G.CharacterFrame then return end
    local btn
    for _, child in ipairs({ _G.CharacterFrame:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Button")
            and not child:GetName()
            and child.GetText and child:GetText() == "WowSims" then
            btn = child
            break
        end
    end
    if not btn then return end   -- not created yet; retried by applyLoaded
    sk.done.wowsims = true
    skinButton(btn)
    local lastTab
    for i = 1, 6 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab and tab:IsShown() then lastTab = tab end
    end
    if lastTab then
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", lastTab, "RIGHT", 8, 0)
        btn:SetHeight(22)
    end
    skinButton(_G.WSEInspectButton)
end

function sk.applyLoaded()
    if not mod.active then return end
    -- leftover skin from a session where the option was on
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
    if loaded("Gargul") then sk.armGargul() end
    if loaded("Attune") then sk.armAttune() end
    if loaded("WowSimsExporter") then sk.skinWowSims() end
    if _G.LeaMapsGlobalPanel then sk.armMapAddon() end
end

local function onEvent(event, arg1)
    if not mod.active then return end
    if event == "ADDON_LOADED" then
        if arg1 == "BugSack" then sk.armBugSack()
        elseif arg1 == "Questie" then
            -- the db exists after its load; the tracker reads the profile keys when it starts
            sk.skinQuestie()
        elseif arg1 == "AtlasLootClassic" then sk.armAtlasLoot()
        elseif arg1 == "HealPredict" then sk.armHealPredict()
        elseif arg1 == "!!AddonProfiler" then sk.skinAddonProfiler()
        elseif arg1 == "NovaWorldBuffs" then sk.skinNovaWorldBuffs()
        elseif arg1 == "NovaInstanceTracker" then sk.skinNovaInstanceTracker()
        elseif arg1 == "Gargul" then sk.armGargul()
        elseif arg1 == "Attune" then sk.armAttune()
        elseif arg1 == "WowSimsExporter" then sk.skinWowSims()
        end
        if _G.LeaMapsGlobalPanel then sk.armMapAddon() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        sk.applyLoaded()
        -- targets build their windows in deferred init; re-apply, every skin is one-shot-guarded
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
    mod:RegisterEvent("ADDON_LOADED", onEvent)
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", onEvent)
    sk.applyLoaded()
end

function mod:OnDisable()
    if sk.done.questie then sk.restoreQuestie() end
    -- texture strips on the other targets are session-permanent -> /reload
end

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
    do
        local isLoaded = _G.LeaMapsGlobalPanel ~= nil
        table.insert(items, {
            type = "toggle",
            -- The target's REAL name, like every other row here -- explicitly
            -- granted by the user (31.07.2026). Skin targets may be named in
            -- code; never in commit messages or the changelog.
            label = "Leatrix Maps" .. (isLoaded and "" or (" |cff888888(" .. L["not loaded"] .. ")|r")),
            get = function() return mod.db.leamaps ~= false end,
            set = function(_, v)
                mod.db.leamaps = v and true or false
                if v then sk.applyLoaded() end
            end,
        })
    end
    return items
end
