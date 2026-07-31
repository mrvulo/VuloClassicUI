-- VuloClassicUI / Modules / TalentView: all three talent trees in ONE window.
--
-- Wrath-family clients only (Titan report ⑦): that is where the class plays
-- with three live trees and where Blizzard's window shows one tree at a time.
-- The shipped TBC/Era variants never see this file do anything.
--
-- DEFENSIVE BY DESIGN. The talent globals on the 3.80.x hybrid are the
-- deprecation shim, and this codebase has already been burned twice by its
-- reshaped returns (see Core/TalentOverrides.lua). So nothing here trusts a
-- slot blindly: every value is type- and range-checked, and if the very first
-- tree fails those checks the build ABORTS and Blizzard's window stays --
-- a missing feature, never a broken talent frame.
local _, ns = ...
local L = ns.L

if not ns.isWrath then return end

local mod = ns:RegisterModule("talentview", {
    name        = "Talent Window",
    group       = "UI Reskin",
    description = "Shows all three talent trees side by side in one window.",
    defaults    = {
        enabled = true,
        replace = true,
        x = 0, y = 0,
    },
})

local BTN      = 34      -- talent button edge
local GAP      = 8
local TREE_PAD = 10
local COLS     = 4
local HEAD_H   = 44      -- window header
local TREE_HEAD = 40     -- per-tree header (name + points)
local FOOT_H   = 40

local win            -- the window frame
local trees = {}     -- [tab] = { frame, buttons = { [i] = btn }, nameFS, ptsFS }
local buildBroken    -- set when the API shapes failed sanity; never retry this session

-- ---------------------------------------------------------------------------
-- Guarded API reads

local function apiReady()
    return type(_G.GetNumTalentTabs) == "function"
       and type(_G.GetNumTalents) == "function"
       and type(_G.GetTalentInfo) == "function"
end

local function readTalent(tab, i)
    local ok, name, icon, tier, col, rank, maxRank = pcall(_G.GetTalentInfo, tab, i)
    if not ok or type(name) ~= "string" or name == "" then return nil end
    if type(tier) ~= "number" or type(col) ~= "number"
        or tier < 1 or tier > 15 or col < 1 or col > 6 then
        return nil
    end
    if type(rank)    ~= "number" then rank = 0 end
    if type(maxRank) ~= "number" or maxRank < 1 then maxRank = 1 end
    return name, icon, tier, col, rank, maxRank
end

-- The shim prepends a spec id; the original leads with the name. The first
-- non-empty STRING is the name either way. Point counts are never taken from
-- here -- they are summed from the ranks, which cannot be misread.
local function treeName(tab)
    local ok, a, b, c = pcall(_G.GetTalentTabInfo, tab)
    if ok then
        for _, v in ipairs({ a, b, c }) do
            if type(v) == "string" and v ~= "" then return v end
        end
    end
    return tostring(tab)
end

local function pointsLeft()
    local ok, n = pcall(_G.UnitCharacterPoints, "player")
    if ok and type(n) == "number" and n >= 0 then return n end
    return 0
end

-- ---------------------------------------------------------------------------
-- Window

local function savePos()
    local x, y = ns:GetCenterOffsets(win)
    if x then mod.db.x, mod.db.y = x, y end
end

local function applyPos()
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
end

local refreshAll   -- forward

local function makeTalentButton(parent, tab, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BTN, BTN)
    b.tab, b.index = tab, index

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetAllPoints(b)
    b.ring:SetColorTexture(0.22, 0.22, 0.26, 1)

    b.rankFS = b:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(b.rankFS, 10, "OUTLINE")
    b.rankFS:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b:SetScript("OnEnter", function(self)
        if not ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then return end
        local shown = pcall(GameTooltip.SetTalent, GameTooltip, self.tab, self.index)
        if not shown then GameTooltip:SetText(self.talentName or "") end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self)
        -- LearnTalent is the classic spend call; unusable clicks (tier locked,
        -- maxed, no points) are filtered before we get here, and the call
        -- itself is guarded because the shim owns it.
        if self.locked or (self.rank or 0) >= (self.maxRank or 1) then return end
        if pointsLeft() < 1 then return end
        pcall(_G.LearnTalent, self.tab, self.index)
    end)
    return b
end

-- Returns false when the client's answers fail sanity -- the caller tears the
-- window down and never replaces Blizzard's UI.
local function buildTrees()
    local okTabs, numTabs = pcall(_G.GetNumTalentTabs)
    if not okTabs or type(numTabs) ~= "number" or numTabs < 1 or numTabs > 5 then return false end

    local treeW = COLS * BTN + (COLS - 1) * GAP + 2 * TREE_PAD
    local maxTier = 0
    local layout = {}

    for tab = 1, numTabs do
        local okN, num = pcall(_G.GetNumTalents, tab)
        if not okN or type(num) ~= "number" or num < 1 or num > 60 then return false end
        local list = {}
        for i = 1, num do
            local name, icon, tier, col, rank, maxRank = readTalent(tab, i)
            if not name then return false end
            list[#list + 1] = { i = i, name = name, icon = icon, tier = tier,
                                col = col, rank = rank, maxRank = maxRank }
            if tier > maxTier then maxTier = tier end
        end
        layout[tab] = list
    end
    if maxTier == 0 then return false end

    local treeH = TREE_HEAD + maxTier * BTN + (maxTier - 1) * GAP + TREE_PAD
    local totalW = numTabs * treeW + (numTabs - 1) * GAP + 2 * TREE_PAD
    local totalH = HEAD_H + treeH + FOOT_H + 2 * TREE_PAD

    win:SetSize(totalW, totalH)

    local ac = ns.COLORS.accent
    for tab = 1, numTabs do
        local t = trees[tab]
        if not t then
            local f = CreateFrame("Frame", nil, win)
            ns.UI:StyleBackdrop(f, { bg = { r = 0.05, g = 0.05, b = 0.07, a = 0.85 },
                                     border = ns.COLORS.borderDark or ns.COLORS.border })
            local nameFS = f:CreateFontString(nil, "OVERLAY")
            ns.UI.Font(nameFS, 12)
            nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
            nameFS:SetTextColor(0.95, 0.95, 1)
            local ptsFS = f:CreateFontString(nil, "OVERLAY")
            ns.UI.Font(ptsFS, 12)
            ptsFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
            ptsFS:SetTextColor(ac.r, ac.g, ac.b)
            t = { frame = f, buttons = {}, nameFS = nameFS, ptsFS = ptsFS }
            trees[tab] = t
        end
        t.frame:SetSize(treeW, treeH)
        t.frame:ClearAllPoints()
        t.frame:SetPoint("TOPLEFT", win, "TOPLEFT",
            TREE_PAD + (tab - 1) * (treeW + GAP), -(HEAD_H + TREE_PAD))
        t.nameFS:SetText(treeName(tab))

        for _, d in ipairs(layout[tab]) do
            local b = t.buttons[d.i]
            if not b then
                b = makeTalentButton(t.frame, tab, d.i)
                t.buttons[d.i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", t.frame, "TOPLEFT",
                TREE_PAD + (d.col - 1) * (BTN + GAP),
                -(TREE_HEAD + (d.tier - 1) * (BTN + GAP)))
            b.talentName = d.name
            b.tier = d.tier
            if d.icon then b.icon:SetTexture(d.icon) end
            b:Show()
        end
    end
    return true
end

refreshAll = function()
    if not win or not win:IsShown() then return end
    local ac = ns.COLORS.accent
    for tab, t in pairs(trees) do
        local spent = 0
        for i, b in pairs(t.buttons) do
            local _, icon, _, _, rank, maxRank = readTalent(tab, i)
            b.rank, b.maxRank = rank or 0, maxRank or 1
            spent = spent + (rank or 0)
            if icon then b.icon:SetTexture(icon) end
        end
        -- classic rule, computed locally: a tier opens at 5 points per tier
        -- above it in the same tree -- no reliance on an unverified return slot
        for _, b in pairs(t.buttons) do
            b.locked = spent < (b.tier - 1) * 5
            local maxed = b.rank >= b.maxRank
            if b.locked and b.rank == 0 then
                b.icon:SetDesaturated(true)
                b.icon:SetVertexColor(0.5, 0.5, 0.5)
                b.ring:SetColorTexture(0.18, 0.18, 0.2, 1)
            else
                b.icon:SetDesaturated(b.rank == 0)
                b.icon:SetVertexColor(1, 1, 1)
                if maxed then b.ring:SetColorTexture(0.95, 0.82, 0.3, 1)
                elseif b.rank > 0 then b.ring:SetColorTexture(ac.r, ac.g, ac.b, 1)
                else b.ring:SetColorTexture(0.28, 0.28, 0.33, 1) end
            end
            b.rankFS:SetText(string.format("%d/%d", b.rank, b.maxRank))
            if maxed then b.rankFS:SetTextColor(0.95, 0.82, 0.3)
            elseif b.rank > 0 then b.rankFS:SetTextColor(0.6, 1, 0.6)
            else b.rankFS:SetTextColor(0.7, 0.7, 0.75) end
        end
        t.ptsFS:SetText(tostring(spent))
    end
    if win.ptsFS then
        win.ptsFS:SetText(string.format(L["Points left: %d"], pointsLeft()))
    end
end

local function ensureWindow()
    if win or buildBroken then return win end
    local UI = ns.UI
    win = CreateFrame("Frame", "VCUI_TalentView", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); savePos() end)
    UI:StyleBackdrop(win, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    if UI.CreateShadow then UI:CreateShadow(win) end

    local ac = ns.COLORS.accent
    local strip = win:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)

    local title = win:CreateFontString(nil, "OVERLAY")
    UI.Font(title, 13)
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -12)
    title:SetText(L["TALENTS"])
    title:SetTextColor(ac.r, ac.g, ac.b)

    win.ptsFS = win:CreateFontString(nil, "OVERLAY")
    UI.Font(win.ptsFS, 12)
    win.ptsFS:SetPoint("TOP", win, "TOP", 0, -13)
    win.ptsFS:SetTextColor(0.95, 0.95, 1)

    local close = CreateFrame("Button", nil, win)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
    local x = close:CreateFontString(nil, "OVERLAY")
    UI.Font(x, 20)
    x:SetPoint("CENTER")
    x:SetText("×")
    x:SetTextColor(0.8, 0.8, 0.85)
    close:SetScript("OnEnter", function() x:SetTextColor(ac.r, ac.g, ac.b) end)
    close:SetScript("OnLeave", function() x:SetTextColor(0.8, 0.8, 0.85) end)
    close:SetScript("OnClick", function() win:Hide() end)

    local blizz = UI:CreateButton(win, {
        label = L["Open Blizzard's talent window"], width = 230,
        tooltip = L["For glyphs and everything this window does not cover."],
        onClick = function()
            local tf = _G.PlayerTalentFrame or _G.TalentFrame
            win:Hide()
            if tf then
                mod._suppress = true
                pcall(_G.ShowUIPanel or function(f) f:Show() end, tf)
                -- If the panel refused to show, its OnHide (which clears the
                -- flag) will never fire -- clear it here or the NEXT talent
                -- open would pass through un-replaced (review find).
                if not tf:IsShown() then mod._suppress = nil end
            end
        end,
    })
    blizz:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)

    if not buildTrees() then
        buildBroken = true
        win:Hide()
        win = nil
        return nil
    end

    -- ESC closes it like any panel
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, "VCUI_TalentView")

    win:SetScript("OnShow", refreshAll)
    applyPos()
    win:Hide()
    return win
end

local function openView()
    if not apiReady() then return false end
    if not ensureWindow() then return false end
    applyPos()
    win:Show()
    refreshAll()
    return true
end
ns.ToggleTalentView = function()
    if win and win:IsShown() then win:Hide() else openView() end
end

-- ---------------------------------------------------------------------------
-- Taking over from Blizzard's window

local function wireBlizzard()
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    if not tf or tf._vcuiTalentHook then return end
    tf._vcuiTalentHook = true
    tf:HookScript("OnShow", function(f)
        if not mod.active or mod.db.replace == false or mod._suppress or buildBroken then return end
        if not openView() then return end   -- broken build: leave Blizzard's UI alone
        if _G.HideUIPanel then pcall(_G.HideUIPanel, f) else f:Hide() end
    end)
    tf:HookScript("OnHide", function()
        mod._suppress = nil
    end)
end

local function onAddonLoaded(_, name)
    if name == "Blizzard_TalentUI" then wireBlizzard() end
end

function mod:OnEnable()
    wireBlizzard()
    mod:RegisterEvent("ADDON_LOADED",             onAddonLoaded)
    mod:RegisterEvent("PLAYER_TALENT_UPDATE",     refreshAll)
    mod:RegisterEvent("CHARACTER_POINTS_CHANGED", refreshAll)
    mod:RegisterEvent("SPELLS_CHANGED",           refreshAll)
end

function mod:OnDisable()
    if win then win:Hide() end
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Talent Window"] },
        { type = "desc",
          text = L["|cffaaaaaaAll three talent trees side by side, with live ranks and click-to-learn. Glyphs stay in Blizzard's window, one button away.|r"] },
        { type = "toggle", label = L["Replace Blizzard's talent window"],
          tooltip = L["Opening talents shows this window instead. Turn it off to get Blizzard's one-tree window back."],
          get = function() return mod.db.replace ~= false end,
          set = function(_, v) mod.db.replace = v end },
        { type = "spacer", height = 6 },
        { type = "button", label = L["Open talent window"], width = 220,
          onClick = function() openView() end },
    }
end
