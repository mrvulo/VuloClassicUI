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

if not ns.Wrath.hasTalentTrees then return end

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
local SPEC_BTN = 32      -- talent-group button edge, outside the right border
local SPEC_GAP = 6

local win            -- the window frame
local trees = {}     -- [tab] = { frame, buttons = { [i] = btn }, nameFS, ptsFS }
local buildBroken    -- set when the API shapes failed sanity; never retry this session
local specTabs = {}  -- [group] = button, down the outer right edge
local viewGroup      -- the talent group the trees are SHOWING (not necessarily the active one)
local lastActive     -- to notice a switch even on a build that never fires the event

-- ---------------------------------------------------------------------------
-- Guarded API reads

local function apiReady()
    return type(_G.GetNumTalentTabs) == "function"
       and type(_G.GetNumTalents) == "function"
       and type(_G.GetTalentInfo) == "function"
end

-- The active group unless the player is looking at the other one. Everything
-- that reads a rank goes through this, so a preview can never be half-applied.
local function activeGroup()
    return ns:ActiveTalentGroup()
end

local function shownGroup()
    return viewGroup or activeGroup()
end

local function previewing()
    return shownGroup() ~= activeGroup()
end

-- The fifth argument is the talent group. It is part of the original 3.3.5
-- signature AND of the deprecation shim (which forwards it as
-- talentInfoQuery.groupIndex), so asking for the other group is supported on
-- both shapes -- unlike the point count, which the two disagree about.
--
-- It is nevertheless passed ONLY when another group is actually being previewed.
-- The two-argument call is the one the reporter confirmed working on 3.80.x, and
-- a feature that nobody asked for must not put a new argument shape underneath
-- it. If the extra arguments were ever refused, only the preview would suffer.
local function readTalent(tab, i, group)
    local ok, name, icon, tier, col, rank, maxRank
    if group and group ~= activeGroup() then
        ok, name, icon, tier, col, rank, maxRank =
            pcall(_G.GetTalentInfo, tab, i, false, false, group)
    else
        ok, name, icon, tier, col, rank, maxRank = pcall(_G.GetTalentInfo, tab, i)
    end
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

-- The 3.80.x shim can answer SetTalent with a "TalentID: n" placeholder
-- instead of an error, so a clean pcall proves nothing -- the tooltip only
-- counts when its first line actually carries this talent's name.
local function tooltipNamed(name)
    if name == "" then return false end   -- find("") matches anything
    local fs = _G.GameTooltipTextLeft1
    local txt = fs and fs:GetText()
    -- anchored: a WRONG talent whose name merely contains this one must fail
    return type(txt) == "string" and txt:find(name, 1, true) == 1
end

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
        local name = self.talentName or ""
        -- Same rule as readTalent: the confirmed two-argument call stays exactly
        -- as it is, and only a preview asks for another group.
        local ok
        if previewing() then
            ok = pcall(GameTooltip.SetTalent, GameTooltip, self.tab, self.index,
                       false, false, shownGroup())
        else
            ok = pcall(GameTooltip.SetTalent, GameTooltip, self.tab, self.index)
        end
        local shown = ok and tooltipNamed(name)
        if not shown and type(_G.GetTalentLink) == "function" then
            local okL, link = pcall(_G.GetTalentLink, self.tab, self.index)
            if okL and type(link) == "string" and link:find("|H", 1, true) then
                local okH = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                shown = okH and tooltipNamed(name)
            end
        end
        if not shown then
            GameTooltip:ClearLines()
            GameTooltip:SetText(name, 1, 1, 1)
            GameTooltip:AddLine(string.format("%d/%d", self.rank or 0, self.maxRank or 1), 0.7, 0.7, 0.75)
        end
        -- Say why the click will do nothing before it is spent, not after.
        if previewing() then
            GameTooltip:AddLine(L["Talents can only be learned in the active talent group."], 1, 0.5, 0.5, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self)
        -- LearnTalent has no talent-group argument: it always spends into the
        -- ACTIVE group. Clicking while the other group is on screen would
        -- therefore learn the wrong talent in the wrong build -- so it does
        -- nothing at all, and the tooltip said so beforehand.
        if previewing() then return end
        -- Unusable clicks (tier locked, maxed, no points) are filtered before we
        -- get here, and the call itself is guarded because the shim owns it.
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
            local name, icon, tier, col, rank, maxRank = readTalent(tab, i, shownGroup())
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

-- ---------------------------------------------------------------------------
-- Talent-group buttons, down the outer right edge
--
-- The client's own talent frame puts one button per OWNED talent group there:
-- a character who never bought the second one sees a single button, and that is
-- deliberately kept -- it is the badge of the build you are playing, not a
-- switch that happens to be lonely.
--
-- Left-click looks at a group, right-click activates it. That split is the one
-- the client trained people on, so it is not ours to redesign.

-- Computed lazily and thrown away on any talent change: the walk below is a
-- couple of hundred guarded calls, which is nothing once, and wasteful on every
-- refresh.
local iconCache = {}

-- C_SpecializationInfo answers on the Anniversary client. On a real Wrath client
-- it does not, and the button wore the placeholder question mark even though the
-- character had 11/5/55 spent (user screenshot, 02.08.2026). So there is a
-- classic fallback, and it leans on the one number that cannot be misread: the
-- ranks, summed by us.
local function classicGroupIcon(group)
    local okTabs, numTabs = pcall(_G.GetNumTalentTabs)
    if not okTabs or type(numTabs) ~= "number" or numTabs < 1 or numTabs > 5 then return nil end

    local bestTab, bestPts
    for tab = 1, numTabs do
        local okN, num = pcall(_G.GetNumTalents, tab)
        if okN and type(num) == "number" and num >= 1 and num <= 60 then
            local pts = 0
            for i = 1, num do
                local _, _, _, _, rank = readTalent(tab, i, group)
                pts = pts + (rank or 0)
            end
            if pts > 0 and (not bestPts or pts > bestPts) then bestPts, bestTab = pts, tab end
        end
    end
    if not bestTab then return nil end

    -- Two shapes live behind this call (see Core/TalentOverrides.lua): the
    -- original leads with the name and carries the icon second, the deprecation
    -- shim prepends a spec id and pushes it to slot four. Rather than counting
    -- slots -- which is exactly what went wrong twice before -- take the first
    -- value that can only BE a texture. The name is a string too, but no tree is
    -- called Interface\something.
    local ok, a, b, c, d = pcall(_G.GetTalentTabInfo, bestTab)
    if not ok then return nil end
    local vals = { a, b, c, d }
    for i = 1, 4 do
        local v = vals[i]
        if type(v) == "number" and v > 1000 then return v end
        if type(v) == "string" and v:find("^Interface") then return v end
    end
    return nil
end

local function groupIcon(group)
    local cached = iconCache[group]
    if cached == nil then
        cached = ns:TalentGroupIcon(group) or classicGroupIcon(group) or false
        iconCache[group] = cached
    end
    -- Nothing spent yet, or no shape answered: a question mark is honest, a
    -- borrowed icon from the other group would be a lie.
    return cached or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function specTabClick(self, button)
    local g = self.group
    if button == "RightButton" then
        local ok, why = ns:ActivateTalentGroup(g)
        if ok then
            viewGroup = g          -- the event confirms it; this keeps the click honest meanwhile
        elseif why == "combat" then
            ns:Print(L["Talent groups cannot be switched in combat."])
        elseif why ~= "already" then
            ns:Print(L["This client refused to switch the talent group."])
        end
    else
        viewGroup = g
    end
    refreshAll()
end

local function specTabTooltip(self)
    if not ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then return end
    local ac = ns.COLORS.accent
    GameTooltip:ClearLines()
    GameTooltip:SetText(ns:TalentGroupText(self.group), ac.r, ac.g, ac.b)
    if self.group == activeGroup() then
        GameTooltip:AddLine(L["Active talent group"], 0.6, 1, 0.6)
    else
        GameTooltip:AddLine(L["Left-click: show this talent group"], 0.8, 0.8, 0.85)
        GameTooltip:AddLine(L["Right-click: activate this talent group"], 0.8, 0.8, 0.85)
    end
    GameTooltip:Show()
end

local function makeSpecTab(group)
    local b = CreateFrame("Button", nil, win)
    b:SetSize(SPEC_BTN, SPEC_BTN)
    b.group = group
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetAllPoints(b)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", specTabTooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", specTabClick)
    return b
end

-- ---------------------------------------------------------------------------
-- The glyph button, under the talent-group buttons
--
-- Blizzard keeps the glyphs on a tab of the very frame we replace, so the way in
-- is the one the Blizzard button below already uses: let that frame show, then
-- pick the tab. BY ITS LABEL, not by an index -- GLYPHS is a client global, so
-- this holds in every language, and a client that has no such tab simply lands
-- on the talent frame with nothing broken.
local glyphTab
local applyGlyphSkin   -- forward: defined with the paint further down

local function openGlyphs()
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    if not tf then return false end
    if win then win:Hide() end
    mod._suppress = true
    pcall(_G.ShowUIPanel or function(f) f:Show() end, tf)
    if not tf:IsShown() then
        -- Same trap as the Blizzard button: if the panel refused, its OnHide
        -- never fires and the flag would let the NEXT talent open slip through.
        mod._suppress = nil
        return false
    end
    local want = _G.GLYPHS
    if type(want) == "string" and want ~= "" then
        for i = 1, 6 do
            local tab = _G["PlayerTalentFrameTab" .. i]
            local txt = tab and tab.GetText and tab:GetText()
            if txt == want then pcall(tab.Click, tab); break end
        end
    end
    -- The glyph addon loads the moment that tab is first clicked, so this is the
    -- earliest point at which there is anything to paint.
    if applyGlyphSkin then applyGlyphSkin() end
    return true
end

local function ensureGlyphTab()
    if glyphTab or not win then return glyphTab end
    local b = CreateFrame("Button", nil, win)
    b:SetSize(SPEC_BTN, SPEC_BTN)

    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetAllPoints(b)
    b.ring:SetColorTexture(0.22, 0.22, 0.26, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture("Interface\\Icons\\INV_Inscription_Tradeskill01")

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        local ac = ns.COLORS.accent
        self.ring:SetColorTexture(ac.r, ac.g, ac.b, 1)
        if ns.UI:OpenTooltip(self, "ANCHOR_RIGHT") then
            GameTooltip:ClearLines()
            GameTooltip:SetText(_G.GLYPHS or L["Glyphs"], ac.r, ac.g, ac.b)
            GameTooltip:AddLine(L["Opens the glyph page of the client's own talent window."], 0.8, 0.8, 0.85, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.ring:SetColorTexture(0.22, 0.22, 0.26, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", openGlyphs)
    glyphTab = b
    return b
end

local function updateSpecTabs()
    if not win then return end
    local n = ns:NumTalentGroups()
    -- A count outside the dual-talent range means the shim answered with
    -- something we do not understand: fall back to the one group we can prove.
    if type(n) ~= "number" or n < 1 or n > 4 then n = 1 end

    local active = activeGroup()
    if viewGroup and viewGroup > n then viewGroup = nil end
    -- Some builds never fire ACTIVE_TALENT_GROUP_CHANGED (Modules/Loadouts.lua
    -- carries a poller for exactly that). Any refresh notices the switch here
    -- and follows it, so the window can never sit on a stale preview of the
    -- group the player is now actually playing.
    if lastActive and lastActive ~= active then viewGroup = active end
    lastActive = active

    -- The strip hangs OUTSIDE the window, so the clamp that keeps the window on
    -- screen knows nothing about it. Same answer as the dropdown that would not
    -- scroll: measure the room and take the other side when there is none.
    local room = SPEC_GAP + SPEC_BTN
    local right, edge = win:GetRight(), UIParent and UIParent:GetRight()
    local onLeft = (right and edge) and (right + room > edge) or false

    local ac = ns.COLORS.accent
    for g = 1, n do
        local b = specTabs[g]
        if not b then
            b = makeSpecTab(g)
            specTabs[g] = b
        end
        local y = -(HEAD_H + TREE_PAD + (g - 1) * (SPEC_BTN + SPEC_GAP))
        b:ClearAllPoints()
        if onLeft then
            b:SetPoint("TOPRIGHT", win, "TOPLEFT", -SPEC_GAP, y)
        else
            b:SetPoint("TOPLEFT", win, "TOPRIGHT", SPEC_GAP, y)
        end
        b.icon:SetTexture(groupIcon(g))
        if g == active then
            b.ring:SetColorTexture(ac.r, ac.g, ac.b, 1)
            b.icon:SetDesaturated(false)
            b.icon:SetVertexColor(1, 1, 1)
        elseif g == shownGroup() then
            b.ring:SetColorTexture(0.6, 0.6, 0.68, 1)
            b.icon:SetDesaturated(false)
            b.icon:SetVertexColor(0.85, 0.85, 0.9)
        else
            b.ring:SetColorTexture(0.22, 0.22, 0.26, 1)
            b.icon:SetDesaturated(true)
            b.icon:SetVertexColor(0.7, 0.7, 0.75)
        end
        b:Show()
    end
    for g = n + 1, #specTabs do
        if specTabs[g] then specTabs[g]:Hide() end
    end

    -- The glyphs sit one slot below the last talent group, on whichever side the
    -- strip ended up on, with a slightly wider gap: it opens a different window,
    -- and reading as a third talent group would be a lie about what it does.
    local gb = ensureGlyphTab()
    if gb then
        local y = -(HEAD_H + TREE_PAD + n * (SPEC_BTN + SPEC_GAP) + SPEC_GAP)
        gb:ClearAllPoints()
        if onLeft then
            gb:SetPoint("TOPRIGHT", win, "TOPLEFT", -SPEC_GAP, y)
        else
            gb:SetPoint("TOPLEFT", win, "TOPRIGHT", SPEC_GAP, y)
        end
        gb:Show()
    end
end

refreshAll = function()
    if not win or not win:IsShown() then return end
    local ac = ns.COLORS.accent
    updateSpecTabs()
    local group = shownGroup()
    for tab, t in pairs(trees) do
        local spent = 0
        for i, b in pairs(t.buttons) do
            local _, icon, _, _, rank, maxRank = readTalent(tab, i, group)
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
        -- UnitCharacterPoints answers for the ACTIVE group only, so while the
        -- other one is on screen a point count would be someone else's number.
        -- The header says which build is showing instead.
        if previewing() then
            win.ptsFS:SetText(string.format(L["Talent group %d (not active)"], group))
            win.ptsFS:SetTextColor(0.8, 0.8, 0.85)
        else
            win.ptsFS:SetText(string.format(L["Points left: %d"], pointsLeft()))
            win.ptsFS:SetTextColor(0.95, 0.95, 1)
        end
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
    -- The talent-group strip hangs off one side and picks that side by the room
    -- left on screen, so a move has to let it pick again.
    win:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); savePos(); updateSpecTabs() end)
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
    -- Every open starts on the build you are playing. A preview is a look, not
    -- a place the window remembers.
    viewGroup = nil
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

-- ---------------------------------------------------------------------------
-- Painting the client's glyph page
--
-- The names below are MEASURED, not guessed: they come off a frame stack the
-- owner took on a running Wrath client (02.08.2026). GlyphFrame,
-- GlyphFrameBackground, GlyphFrameSparkleFrame, GlyphFrameGlyph<n> with its
-- Background, Highlight, Ring and Setting, and on the parent side
-- PlayerTalentFrame, PlayerTalentFrameScrollFrame,
-- PlayerTalentFrameBackgroundTopLeft and PlayerTalentFrameTopRight.
--
-- The siblings of those last two are named by the same rule and are touched
-- ONLY if they answer -- a name that resolves to nothing is skipped, never
-- assumed. The whole file is already behind ns.Wrath.hasTalentTrees, so no
-- second client gate is owed here.
local PANEL_CHROME = {
    "PlayerTalentFrameBackgroundTopLeft",    "PlayerTalentFrameBackgroundTopRight",
    "PlayerTalentFrameBackgroundBottomLeft", "PlayerTalentFrameBackgroundBottomRight",
    "PlayerTalentFrameTopLeft",              "PlayerTalentFrameTopRight",
    "PlayerTalentFrameBottomLeft",           "PlayerTalentFrameBottomRight",
}

-- Two things this got wrong the first time, both proven by a frame stack the
-- owner took (02.08.2026):
--
--   * THE GLYPH PAGE IS ITS OWN ADDON. The stack names its source as
--     Blizzard_GlyphUI.xml, not Blizzard_TalentUI. Skinning on the talent
--     addon's load ran while GlyphFrame did not exist yet and quietly gave up
--     halfway.
--   * THE FRAME REPAINTS ITSELF. PlayerTalentFrame._vcBG was in the stack --
--     our backdrop WAS there -- with Blizzard's parchment still on top of it.
--     The corner art is re-set when the page changes, so a one-shot pass loses.
--
-- Hence: the paint is idempotent and runs again on every show and every update.
-- Only what must exist once is guarded.
local chromeBuilt

applyGlyphSkin = function()
    local UI = ns.UI
    local tf = _G.PlayerTalentFrame
    if not (tf and UI and UI.StyleBackdrop) then return end
    local ac = ns.COLORS.accent
    local bc = ns.COLORS.borderDark or ns.COLORS.border

    if not chromeBuilt then
        chromeBuilt = true
        UI:StyleBackdrop(tf, { bg = ns.COLORS.bg, border = bc })
        if UI.CreateShadow then UI:CreateShadow(tf) end
        local strip = tf:CreateTexture(nil, "OVERLAY")
        strip:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, 0)
        strip:SetPoint("TOPRIGHT", tf, "TOPRIGHT", 0, 0)
        strip:SetHeight(2)
        if UI.SetGradient then
            UI.SetGradient(strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
        end
        -- The repaint happens on show and on the page update; catch both rather
        -- than hoping one of them is enough.
        tf:HookScript("OnShow", applyGlyphSkin)
        if type(_G.PlayerTalentFrame_Update) == "function" then
            hooksecurefunc("PlayerTalentFrame_Update", applyGlyphSkin)
        end
    end

    -- ---- everything below runs again on every pass, because Blizzard redraws it

    for _, n in ipairs(PANEL_CHROME) do
        local t = _G[n]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    -- The portrait medallion belongs to the parchment look and has nothing to
    -- hold once the parchment is gone.
    local portrait = _G.PlayerTalentFramePortrait
    if portrait and portrait.SetAlpha then portrait:SetAlpha(0) end

    local title = _G.PlayerTalentFrameTitleText
    if title then
        if UI.Font then UI.Font(title, 13) end
        title:SetTextColor(ac.r, ac.g, ac.b)
    end

    -- The tabs along the bottom, in the same shape the friends window uses: art
    -- off, a dark plate behind the label, an accent underline on the open one.
    for i = 1, 6 do
        local tab = _G["PlayerTalentFrameTab" .. i]
        if tab then
            if not tab._vcTabSkin then
                tab._vcTabSkin = true
                -- Blizzard's own textures, collected ONCE. This pass runs on
                -- every talent-frame update, and rebuilding the region list each
                -- time meant a fresh table per tab per update for a set that
                -- never changes. Snapshotting also removes the need to exclude
                -- our own plate and underline further down: they are created
                -- below this line, so they were never in the list.
                local art = {}
                for _, r in ipairs({ tab:GetRegions() }) do
                    if r.IsObjectType and r:IsObjectType("Texture") then
                        art[#art + 1] = r
                        r:SetAlpha(0)
                    end
                end
                tab._vcArt = art
                local fs = tab.GetFontString and tab:GetFontString()
                if fs then
                    local plate = tab:CreateTexture(nil, "BACKGROUND")
                    plate:SetPoint("TOPLEFT", fs, "TOPLEFT", -8, 5)
                    plate:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 8, -5)
                    plate:SetColorTexture(0.10, 0.10, 0.13, 0.95)
                    local ul = tab:CreateTexture(nil, "ARTWORK")
                    ul:SetHeight(2)
                    ul:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 0, 0)
                    ul:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", 0, 0)
                    ul:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
                    tab._vcPlate, tab._vcUnderline, tab._vcText = plate, ul, fs
                end
            end
            -- Selection can change without a reload, and the tab art comes back
            -- with it, so it is re-asserted here rather than at build time --
            -- over the snapshot, without building a list each pass.
            -- Not `i`: that is the tab index of the loop this sits inside.
            local art = tab._vcArt
            if art then
                for a = 1, #art do art[a]:SetAlpha(0) end
            end
            local selected = (tf.selectedTab or 1) == i
            if tab._vcText then
                if UI.Font then UI.Font(tab._vcText, 11) end
                if selected then
                    tab._vcText:SetTextColor(ac.r, ac.g, ac.b)
                else
                    tab._vcText:SetTextColor(0.72, 0.72, 0.78)
                end
            end
            if tab._vcUnderline then tab._vcUnderline:SetShown(selected) end
            if tab._vcPlate then
                tab._vcPlate:SetColorTexture(selected and 0.14 or 0.10,
                                             selected and 0.14 or 0.10,
                                             selected and 0.18 or 0.13, 0.95)
            end
        end
    end

    local gf = _G.GlyphFrame
    if not gf then return end
    if not gf._vcGlyphHook then
        gf._vcGlyphHook = true
        gf:HookScript("OnShow", applyGlyphSkin)
    end

    -- The big rune circle is DIMMED, not deleted. It is what makes the page
    -- recognisable as the glyph page, and an empty dark box would be a worse
    -- answer than a loud one; desaturated and dark it reads as material.
    local bg = _G.GlyphFrameBackground
    if bg then
        if bg.SetDesaturated then bg:SetDesaturated(true) end
        bg:SetVertexColor(0.30, 0.30, 0.38, 1)
        bg:SetAlpha(0.45)
    end

    for i = 1, 6 do
        local sbg = _G["GlyphFrameGlyph" .. i .. "Background"]
        if sbg then
            if sbg.SetDesaturated then sbg:SetDesaturated(true) end
            sbg:SetVertexColor(0.45, 0.45, 0.53, 1)
        end
        local ring = _G["GlyphFrameGlyph" .. i .. "Ring"]
        if ring then
            if ring.SetDesaturated then ring:SetDesaturated(true) end
            ring:SetVertexColor(ac.r, ac.g, ac.b, 1)
        end
        -- Setting and Highlight stay untouched on purpose: the first is the
        -- glyph's own artwork, the second is the feedback while one hangs on the
        -- cursor, and both have to stay readable.
    end
end

-- Kept under the old name: three call sites already ask for it.
local function skinGlyphFrame()
    applyGlyphSkin()
end

local function wireBlizzard()
    local tf = _G.PlayerTalentFrame or _G.TalentFrame
    if not tf or tf._vcuiTalentHook then return end
    tf._vcuiTalentHook = true
    tf:HookScript("OnShow", function(f)
        if not mod.active or mod.db.replace == false or mod._suppress or buildBroken then return end
        if win and win:IsShown() then
            -- The toggle keybind only sees Blizzard's frame, which we keep
            -- hidden -- every press lands here as an "open". With our window
            -- already up, this press MEANT "close": honor the toggle.
            win:Hide()
        elseif not openView() then
            return   -- broken build: leave Blizzard's UI alone
        end
        if _G.HideUIPanel then pcall(_G.HideUIPanel, f) else f:Hide() end
    end)
    tf:HookScript("OnHide", function()
        mod._suppress = nil
    end)
end

local function onAddonLoaded(_, name)
    if name == "Blizzard_TalentUI" then wireBlizzard() end
    -- Blizzard_GlyphUI is a SEPARATE load-on-demand addon (proven by the frame
    -- stack: its source is Blizzard_GlyphUI.xml). Listening only for the talent
    -- addon meant painting a window that did not exist yet.
    if name == "Blizzard_TalentUI" or name == "Blizzard_GlyphUI" then
        skinGlyphFrame()
    end
end

-- The group icon follows the tree with the most points, so anything that can
-- move a point invalidates it.
local function onTalentChanged()
    wipe(iconCache)
    refreshAll()
end

function mod:OnEnable()
    wireBlizzard()
    -- Blizzard_TalentUI is load-on-demand, but it may already be up when the
    -- module is switched on mid-session.
    skinGlyphFrame()
    mod:RegisterEvent("ADDON_LOADED",             onAddonLoaded)
    mod:RegisterEvent("PLAYER_TALENT_UPDATE",     onTalentChanged)
    mod:RegisterEvent("CHARACTER_POINTS_CHANGED", onTalentChanged)
    mod:RegisterEvent("SPELLS_CHANGED",           refreshAll)
    -- Snap back to the newly active group rather than leaving a preview open on
    -- the build the player just left. updateSpecTabs does the same on any other
    -- refresh, for the builds where this event never arrives.
    mod:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function()
        viewGroup = nil
        onTalentChanged()
    end)
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
