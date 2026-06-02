-- =========================================================
-- VuloClassicUI / Modules / QuestLog
-- Enhances the (Classic) quest log:
--   * quest levels (and optional quest IDs) in the titles
--   * an enlarged frame (more quests, detail pane beside the list)
--   * a theme choice: Parchment or Dark
--
-- TBC 2.5.5 has no C_QuestLog.GetInfo (Shadowlands+), so this uses the classic
-- QuestLogFrame / GetQuestLogTitle / QuestLog_Update API. The frame's own
-- parchment regions are retextured with a neutral Blizzard parchment (no foreign
-- assets), which the theme then tints. Everything is guarded.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("questlog", {
    name        = "Quest Log",
    group       = "QoL",
    description = "Enhances the quest log: quest levels (and optional quest IDs) in the titles, a larger frame, and a Parchment or Dark theme.",
    defaults = {
        enabled  = true,
        levels   = true,        -- show quest level in the titles
        questIDs = false,       -- show the quest ID after the title
        larger   = true,        -- enlarge the quest log frame
        theme    = "parchment", -- "parchment" | "dark"
    },
})

local GetQuestLogTitle      = GetQuestLogTitle
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogSelection  = GetQuestLogSelection
local format                = string.format

-- A Blizzard parchment that is present in TBC 2.5.5 (the -Desaturated variant is
-- not). We retexture the quest log's own parchment regions with it and remove
-- the gold cast at runtime via SetDesaturated, so the theme tint defines the
-- tone with no orange. No foreign assets.
local PARCHMENT = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal"

local hooked   = false
local enlarged = false
local bgDone   = false

-- =========================================================
-- Titles: "[67] Title (1234)"  — Blizzard already shows the (Dungeon) tag.
-- =========================================================
local function formatTitle(title, level, questID)
    local prefix = (mod.db.levels and level and level > 0) and format("[%d] ", level) or ""
    local idTag  = (mod.db.questIDs and questID and questID > 0) and format(" |cff808080(%d)|r", questID) or ""
    return prefix .. title .. idTag
end

-- Levels on the quest list (hooked onto QuestLog_Update)
local function updateListLevels()
    if not (mod.db.levels or mod.db.questIDs) then return end
    local numEntries = GetNumQuestLogEntries()
    if not numEntries or numEntries == 0 then return end
    local offset = (_G.FauxScrollFrame_GetOffset and _G.QuestLogListScrollFrame
        and _G.FauxScrollFrame_GetOffset(_G.QuestLogListScrollFrame)) or 0
    for i = 1, (_G.QUESTS_DISPLAYED or 0) do
        local idx = i + offset
        if idx <= numEntries then
            local btn = _G["QuestLogTitle" .. i]
            local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(idx)
            if btn and title and not isHeader and level and level > 0 then
                local txt = "  " .. formatTitle(title, level, questID)
                btn:SetText(txt)
                if _G.QuestLogDummyText then _G.QuestLogDummyText:SetText(txt) end
            end
        end
    end
end

-- Dark theme: lighten the (parchment-coloured) detail text so it stays readable
local function lightenDetailText()
    local sc = _G.QuestLogDetailScrollChildFrame
    if not sc then return end
    local function walk(frame)
        if frame.GetRegions then
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetTextColor then
                    local cr, cg, cb = r:GetTextColor()
                    if cr and (cr + cg + cb) < 1.2 then          -- dark text -> lighten
                        r:SetTextColor(0.92, 0.90, 0.84)
                    end
                end
            end
        end
        if frame.GetChildren then
            for _, c in ipairs({ frame:GetChildren() }) do walk(c) end
        end
    end
    pcall(walk, sc)
end

-- Levels on the detail pane title (hooked onto QuestLog_UpdateQuestDetails)
local function updateDetail()
    if mod.db.levels or mod.db.questIDs then
        local q = GetQuestLogSelection and GetQuestLogSelection()
        if q and _G.QuestLogQuestTitle then
            local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(q)
            if title and not isHeader and level and level > 0 then
                _G.QuestLogQuestTitle:SetText(formatTitle(title, level, questID))
            end
        end
    end
    if mod.db.theme == "dark" then lightenDetailText() end
end

local function installHooks()
    if hooked then return end
    hooked = true
    if _G.QuestLog_Update then hooksecurefunc("QuestLog_Update", updateListLevels) end
    if _G.QuestLog_UpdateQuestDetails then hooksecurefunc("QuestLog_UpdateQuestDetails", updateDetail) end
end

-- =========================================================
-- Background: retexture the quest log's OWN parchment regions (3-6).
-- This is the approach the reference addons use for the enlarged frame: keep
-- Blizzard's regions (so the list area on the left keeps its parchment) and
-- just swap the image + tint, instead of hiding them and overlaying our own.
-- =========================================================
local function setupBg()
    if bgDone then return end
    local QLF = _G.QuestLogFrame
    if not QLF then return end
    bgDone = true
    pcall(function()
        local regs = { QLF:GetRegions() }
        local q = {}
        for i = 3, 6 do
            local r = regs[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then q[i] = r end
        end

        if enlarged and q[3] and q[4] then
            -- Two big quadrants fill the whole enlarged frame (list + detail);
            -- the bottom pair isn't needed once the top pair is tall enough.
            q[3]:SetSize(512, 512)
            q[3]:SetTexture(PARCHMENT)
            q[3]:SetTexCoord(0, 1, 0, 1)

            q[4]:ClearAllPoints()
            q[4]:SetPoint("TOPLEFT", q[3], "TOPRIGHT", 0, 0)
            q[4]:SetSize(256, 512)
            q[4]:SetTexture(PARCHMENT)
            q[4]:SetTexCoord(0, 1, 0, 1)

            if q[5] then q[5]:Hide() end
            if q[6] then q[6]:Hide() end
            QLF._vcuiRegs = { q[3], q[4] }
        else
            -- Normal size: retexture every quadrant in place.
            local list = {}
            for i = 3, 6 do
                if q[i] then
                    q[i]:SetTexture(PARCHMENT)
                    q[i]:SetTexCoord(0, 1, 0, 1)
                    list[#list + 1] = q[i]
                end
            end
            QLF._vcuiRegs = list
        end
    end)
end

local function applyTheme()
    local QLF = _G.QuestLogFrame
    if not QLF then return end
    local dark = (mod.db.theme == "dark")
    if QLF._vcuiRegs then
        for _, r in ipairs(QLF._vcuiRegs) do
            -- Parchment keeps the natural warm grain (like Leatrix); only the
            -- dark theme desaturates and tints the surface dark.
            if r.SetDesaturated then r:SetDesaturated(dark) end
            if dark then r:SetVertexColor(0.16, 0.15, 0.14, 1)
            else        r:SetVertexColor(0.92, 0.84, 0.64, 1) end  -- warm parchment
        end
    end
    if dark then lightenDetailText() end
    if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end
end

-- =========================================================
-- Enlarge the quest log (geometry only — the background is the tiled parchment)
-- =========================================================
local function enlarge()
    if enlarged or not mod.db.larger then return end
    local QLF = _G.QuestLogFrame
    if not QLF then return end
    enlarged = true
    pcall(function()
        local tall, extra = 73, 21

        if _G.UIPanelWindows and _G.UIPanelWindows["QuestLogFrame"] then
            _G.UIPanelWindows["QuestLogFrame"] = { area = "override", pushable = 0,
                xoffset = -16, yoffset = 12, bottomClampOverride = 152, width = 685, height = 487, whileDead = 1 }
        end

        QLF:SetWidth(714)
        QLF:SetHeight(487 + tall)

        if _G.QuestLogTitleText then
            _G.QuestLogTitleText:ClearAllPoints()
            _G.QuestLogTitleText:SetPoint("TOP", QLF, "TOP", 0, -18)
        end

        if _G.QuestLogDetailScrollFrame and _G.QuestLogListScrollFrame then
            _G.QuestLogDetailScrollFrame:ClearAllPoints()
            _G.QuestLogDetailScrollFrame:SetPoint("TOPLEFT", _G.QuestLogListScrollFrame, "TOPRIGHT", 31, 1)
            _G.QuestLogDetailScrollFrame:SetHeight(336 + tall)
            _G.QuestLogListScrollFrame:SetHeight(336 + tall)
        end

        -- extra quest rows
        local old = _G.QUESTS_DISPLAYED or 0
        _G.QUESTS_DISPLAYED = old + extra
        for i = old + 1, _G.QUESTS_DISPLAYED do
            if not _G["QuestLogTitle" .. i] and _G["QuestLogTitle" .. (i - 1)] then
                local b = CreateFrame("Button", "QuestLogTitle" .. i, QLF, "QuestLogTitleButtonTemplate")
                b:SetID(i)
                b:Hide()
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", _G["QuestLogTitle" .. (i - 1)], "BOTTOMLEFT", 0, 1)
            end
        end

        -- reposition the bottom buttons
        local function placeBtn(name, w, h, point, rel, relPoint, x, y)
            local b = _G[name]
            if not b then return end
            if w then b:SetSize(w, h) end
            b:ClearAllPoints()
            b:SetPoint(point, rel, relPoint, x, y)
        end
        placeBtn("QuestLogFrameAbandonButton", 110, 21, "BOTTOMLEFT", QLF, "BOTTOMLEFT", 17, 54)
        placeBtn("QuestFramePushQuestButton", 100, 21, "LEFT", _G.QuestLogFrameAbandonButton, "RIGHT", -3, 0)
        placeBtn("QuestFrameExitButton", 80, 22, "BOTTOMRIGHT", QLF, "BOTTOMRIGHT", -42, 54)
    end)
end

-- =========================================================
-- Lifecycle
-- =========================================================
local function setup()
    enlarge()
    setupBg()
    applyTheme()
    if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end
end

function mod:OnEnable()
    installHooks()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, setup)
    else
        setup()
    end
end

function mod:OnDisable()
    -- Hooks stay (gated by mod.db checks); a /reload fully restores the frame.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["Quest Log"] },
        { type = "desc", text = L["|cffaaaaaaShows quest levels (and optionally IDs) in the quest log, can enlarge it, and lets you pick a Parchment or Dark look.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Titles"] },
        { type = "toggle", label = L["Show quest levels"],
          get = function() return mod.db.levels end,
          set = function(_, v) mod.db.levels = v; if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end end },
        { type = "toggle", label = L["Show quest IDs"],
          get = function() return mod.db.questIDs end,
          set = function(_, v) mod.db.questIDs = v; if _G.QuestLog_Update then pcall(_G.QuestLog_Update) end end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Frame"] },
        { type = "toggle", label = L["Larger quest log"],
          tooltip = L["Enlarges the quest log so more quests are visible with the detail pane beside the list. /reload to fully apply or revert."],
          get = function() return mod.db.larger end,
          set = function(_, v)
              mod.db.larger = v
              if v then enlarge(); setupBg(); applyTheme() end
              ns:Print(L["Quest log size changed. /reload recommended."])
          end },
        { type = "dropdown", label = L["Theme"], width = 240,
          values = {
              { value = "parchment", text = L["Parchment (default)"] },
              { value = "dark",      text = L["Dark"] },
          },
          get = function() return mod.db.theme end,
          set = function(_, v) mod.db.theme = v; applyTheme() end },
    }
end
