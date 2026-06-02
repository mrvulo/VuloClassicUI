-- =========================================================
-- VuloClassicUI / Modules / ProfessionWindow
-- Enlarges and themes the profession windows to match the quest log:
--   * TradeSkillFrame  (most professions + secondary skills)
--   * CraftFrame       (Enchanting / Beast Training)
-- Each gets a wider frame with the detail pane beside the recipe list and a
-- Parchment or Dark theme, using the same bundled parchment image as the quest
-- log. Both Blizzard UIs are load-on-demand, so we wait for ADDON_LOADED.
-- Everything is guarded; a /reload fully restores the frames.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("professionwindow", {
    name        = "Profession Window",
    group       = "QoL",
    description = "Enlarges and themes the profession windows (Tradeskill & Craft) to match the quest log: the detail pane sits beside the recipe list, with a Parchment or Dark theme.",
    defaults = {
        enabled = true,
        larger  = true,        -- enlarge the frames (detail beside the list)
        theme   = "parchment", -- "parchment" | "dark"
    },
})

-- Same bundled parchment the quest log uses (atlas: top half is the parchment).
local PARCHMENT = "Interface\\AddOns\\VuloClassicUI\\Media\\textures\\questlog-parchment"

local TALL, EXTRA = 73, 19

-- Per-frame configuration. The two profession frames share one structure but
-- use different element names; this table captures the differences.
local FRAMES = {
    {
        addon       = "Blizzard_TradeSkillUI",
        frame       = "TradeSkillFrame",
        title       = "TradeSkillFrameTitleText",
        list        = "TradeSkillListScrollFrame",
        detail      = "TradeSkillDetailScrollFrame",
        rowFmt      = "TradeSkillSkill%d",
        rowTemplate = "TradeSkillSkillButtonTemplate",
        displayed   = "TRADE_SKILLS_DISPLAYED",
        highlight   = "TradeSkillHighlightFrame",
        cancel      = "TradeSkillCancelButton",
        create      = "TradeSkillCreateButton",
        close       = "TradeSkillFrameCloseButton",
        expand      = "TradeSkillExpandTabLeft",
        extraHide   = { "TradeSkillHorizontalBarLeft" },
        detailTex   = { "TradeSkillDetailScrollFrameTop", "TradeSkillDetailScrollFrameBottom" },
        hideRegions = { 4, 5, 8 },
        repos = function(f)
            local inv    = _G.TradeSkillInvSlotDropdown
            local sub    = _G.TradeSkillSubClassDropdown
            local search = _G.TradeSearchInputBox
            local anchor = _G.TradeSkillFrameAvailableFilterCheckButtonText
            if inv then inv:ClearAllPoints(); inv:SetPoint("TOPLEFT", f, "TOPLEFT", 550, -42) end
            if inv and sub then sub:ClearAllPoints(); sub:SetPoint("RIGHT", inv, "LEFT", -10, 0) end
            if search and anchor then search:ClearAllPoints(); search:SetPoint("LEFT", anchor, "RIGHT", 30, 0) end
        end,
    },
    {
        addon       = "Blizzard_CraftUI",
        frame       = "CraftFrame",
        title       = "CraftFrameTitleText",
        list        = "CraftListScrollFrame",
        detail      = "CraftDetailScrollFrame",
        rowFmt      = "Craft%d",
        rowTemplate = "CraftButtonTemplate",
        displayed   = "CRAFTS_DISPLAYED",
        highlight   = "CraftHighlightFrame",
        cancel      = "CraftCancelButton",
        create      = "CraftCreateButton",
        close       = "CraftFrameCloseButton",
        expand      = "CraftExpandTabLeft",
        costFmt     = "Craft%dCost",   -- craft rows carry a cost sub-element
        detailTex   = { "CraftDetailScrollFrameTop", "CraftDetailScrollFrameBottom" },
        hideRegions = { 4, 5, 9, 10 },
        repos = function(f)
            local dd = f.Dropdown
            if dd then dd:ClearAllPoints(); dd:SetPoint("TOPLEFT", f, "TOPLEFT", 550, -42) end
        end,
    },
}

local states = {}  -- [frameName] = { done = bool, regs = { tex, tex } }

local function isLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

-- =========================================================
-- Theme (tint the bundled parchment, or desaturate + darken it)
-- =========================================================
local function applyTheme(cfg)
    local st = states[cfg.frame]
    if not (st and st.regs) then return end
    local dark = (mod.db.theme == "dark")
    for _, r in ipairs(st.regs) do
        -- Parchment shows the image as-is; dark desaturates + tints it dark.
        if r.SetDesaturated then r:SetDesaturated(dark) end
        if dark then r:SetVertexColor(0.16, 0.15, 0.14, 1)
        else        r:SetVertexColor(1, 1, 1, 1) end
    end
end

-- =========================================================
-- Enlarge + parchment background (runs once per frame)
-- =========================================================
local function setupFrame(cfg)
    local st = states[cfg.frame]
    if not st then st = {}; states[cfg.frame] = st end
    if st.done then return end
    local f = _G[cfg.frame]
    if not f then return end
    st.done = true

    if mod.db.larger then
        pcall(function()
            -- Double-wide override + size
            if _G.UIPanelWindows and _G.UIPanelWindows[cfg.frame] then
                _G.UIPanelWindows[cfg.frame] = { area = "override", pushable = 1,
                    xoffset = -16, yoffset = 12, bottomClampOverride = 152, width = 685, height = 487, whileDead = 1 }
            end
            f:SetWidth(714)
            f:SetHeight(487 + TALL)

            local title = _G[cfg.title]
            if title then title:ClearAllPoints(); title:SetPoint("TOP", f, "TOP", 0, -18) end

            -- Recipe list to full height
            local list = _G[cfg.list]
            if list then
                list:ClearAllPoints()
                list:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -75)
                list:SetSize(295, 336 + TALL)
            end

            -- Reposition existing rows (+ their cost column, if any)
            local displayed = _G[cfg.displayed] or 0
            if cfg.costFmt then
                local c1, b1 = _G[cfg.costFmt:format(1)], _G[cfg.rowFmt:format(1)]
                if c1 and b1 then c1:ClearAllPoints(); c1:SetPoint("RIGHT", b1, "RIGHT", -30, 0) end
            end
            for i = 2, displayed do
                local b, prev = _G[cfg.rowFmt:format(i)], _G[cfg.rowFmt:format(i - 1)]
                if b and prev then b:ClearAllPoints(); b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1) end
                if cfg.costFmt then
                    local cost = _G[cfg.costFmt:format(i)]
                    if cost and b then cost:ClearAllPoints(); cost:SetPoint("RIGHT", b, "RIGHT", -30, 0) end
                end
            end

            -- Create extra rows so the taller list is filled
            local old = displayed
            _G[cfg.displayed] = old + EXTRA
            for i = old + 1, _G[cfg.displayed] do
                local prev = _G[cfg.rowFmt:format(i - 1)]
                if not _G[cfg.rowFmt:format(i)] and prev then
                    local b = CreateFrame("Button", cfg.rowFmt:format(i), f, cfg.rowTemplate)
                    b:SetID(i); b:Hide(); b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
                    if cfg.costFmt then
                        local cost = _G[cfg.costFmt:format(i)]
                        if cost then cost:ClearAllPoints(); cost:SetPoint("RIGHT", b, "RIGHT", -30, 0) end
                    end
                end
            end

            -- Highlight bar spans the wider list
            if cfg.highlight and _G[cfg.highlight] then
                hooksecurefunc(_G[cfg.highlight], "Show", function()
                    _G[cfg.highlight]:SetWidth(290)
                end)
            end

            -- Detail pane to the right, full height; hide its own edge textures
            local detail = _G[cfg.detail]
            if detail then
                detail:ClearAllPoints()
                detail:SetPoint("TOPLEFT", f, "TOPLEFT", 352, -74)
                detail:SetSize(298, 336 + TALL)
            end
            for _, tn in ipairs(cfg.detailTex) do
                local t = _G[tn]; if t and t.SetAlpha then t:SetAlpha(0) end
            end

            -- Bottom buttons
            local create, cancel, close = _G[cfg.create], _G[cfg.cancel], _G[cfg.close]
            if create and cancel then create:ClearAllPoints(); create:SetPoint("RIGHT", cancel, "LEFT", -1, 0) end
            if cancel then
                cancel:SetSize(80, 22)
                cancel:ClearAllPoints()
                cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -42, 54)
            end
            if close then close:ClearAllPoints(); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -8) end

            if cfg.expand and _G[cfg.expand] then _G[cfg.expand]:Hide() end
            for _, n in ipairs(cfg.extraHide or {}) do
                local e = _G[n]
                if e then if e.SetSize then e:SetSize(1, 1) end; if e.Hide then e:Hide() end end
            end

            -- Reposition the filter dropdowns / search box for the wider frame
            if cfg.repos then cfg.repos(f) end

            -- Parchment background: two slices of the bundled image fill the
            -- whole frame at ~1:1 (left = list, right = detail).
            local regs = { f:GetRegions() }
            local r2, r3 = regs[2], regs[3]
            if r2 and r3 and r2.SetTexture and r3.SetTexture then
                r2:SetTexture(PARCHMENT); r2:SetTexCoord(0.25, 0.75, 0, 0.5); r2:SetSize(512, 512)
                r3:ClearAllPoints(); r3:SetPoint("TOPLEFT", r2, "TOPRIGHT", 0, 0)
                r3:SetTexture(PARCHMENT); r3:SetTexCoord(0.75, 1, 0, 0.5); r3:SetSize(256, 512)
                for _, idx in ipairs(cfg.hideRegions) do
                    local rr = regs[idx]; if rr and rr.Hide then rr:Hide() end
                end
                st.regs = { r2, r3 }
            end
        end)
    end

    applyTheme(cfg)
end

-- =========================================================
-- Lifecycle
-- =========================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if not mod._enabled then return end
    for _, cfg in ipairs(FRAMES) do
        if name == cfg.addon then C_Timer.After(0, function() setupFrame(cfg) end) end
    end
end)

function mod:OnEnable()
    -- Frames already loaded this session (professions opened before login reload)
    for _, cfg in ipairs(FRAMES) do
        if isLoaded(cfg.addon) then setupFrame(cfg) end
    end
end

function mod:OnDisable()
    -- The enlarge isn't cleanly reversible at runtime; a /reload restores it.
end

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = L["Profession Window"] },
        { type = "desc", text = L["|cffaaaaaaEnlarges the Tradeskill and Craft windows so the detail sits beside the recipe list, with a Parchment or Dark look.|r"] },

        { type = "spacer", height = 6 },
        { type = "toggle", label = L["Larger profession window"],
          tooltip = L["Enlarges the profession windows so more recipes are visible with the detail pane beside the list. /reload to fully apply or revert."],
          get = function() return mod.db.larger end,
          set = function(_, v)
              mod.db.larger = v
              ns:Print(L["Profession window size changed. /reload recommended."])
          end },
        { type = "dropdown", label = L["Theme"], width = 240,
          values = {
              { value = "parchment", text = L["Parchment (default)"] },
              { value = "dark",      text = L["Dark"] },
          },
          get = function() return mod.db.theme end,
          set = function(_, v) mod.db.theme = v; for _, cfg in ipairs(FRAMES) do applyTheme(cfg) end end },
    }
end
