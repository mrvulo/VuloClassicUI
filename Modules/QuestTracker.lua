-- VuloClassicUI / Modules / QuestTracker: the game's quest watch list in the
-- house style -- its own font and size, accent titles, green finished
-- objectives, and a position of your own once you move it in edit mode.
--
-- Two client shapes, verified against the anniversary UI source:
--   TBC / Era  : QuestWatchFrame with QuestWatchLine1..MAX_QUESTWATCH_LINES,
--                repainted by QuestWatch_Update (Blizzard_UIPanels_Game/TBC).
--   Wrath      : WatchFrame with pooled lines, WatchFrame_SetLine per line and
--                WatchFrame_Update around it.
-- Both are UIParent-managed frames: `ignoreFramePositionManager` takes one out
-- of the manager, and RemoveManagedFrame drops it from the container it may
-- already sit in. Nothing here is protected.
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local mod = ns:RegisterModule("questtracker", {
    name        = "Quest Tracker",
    group       = "Character",
    description = "The quest watch list with the addon font, accent titles and green finished objectives; move it in edit mode.",
    defaults    = {
        enabled        = true,
        fontSize       = 12,
        titleAccent    = true,
        objectiveColor = { r = 0.80, g = 0.80, b = 0.80 },
        doneColor      = { r = 0.45, g = 0.90, b = 0.45 },
        moved          = false,
        x              = 0,
        y              = 0,
    },
})

local hooksecurefunc = hooksecurefunc
local anchor, mover
local hooked = false

local function watchFrame()
    return _G.QuestWatchFrame or _G.WatchFrame
end

-- Blizzard paints every line before we see it; the colour it chose tells the
-- line's role apart without re-reading the quest log: gold = title, bright
-- gold = title with everything done, white = finished objective, grey = open.
local function classify(fs, text)
    local r, g, b = fs:GetTextColor()
    if text and text:sub(1, 3) == " - " then
        return "objective", (r > 0.95 and g > 0.95 and b > 0.95)
    end
    if r > 0.9 and g > 0.9 and b > 0.9 then return "objective", true end
    if g < 0.7 then return "title", false end       -- 0.75 / 0.61 / 0
    if g > 0.8 and b < 0.2 then return "title", true end  -- NORMAL_FONT_COLOR
    return "objective", false
end

local function paint(fs, text)
    local db = mod.db
    UI.FontFor("questtracker", fs, db.fontSize)
    local kind, done = classify(fs, text)
    if kind == "title" then
        if done then
            local c = db.doneColor
            fs:SetTextColor(c.r, c.g, c.b)
        elseif db.titleAccent then
            local a = ns.COLORS.accent
            fs:SetTextColor(a.r, a.g, a.b)
        end
    elseif done then
        local c = db.doneColor
        fs:SetTextColor(c.r, c.g, c.b)
    else
        local c = db.objectiveColor
        fs:SetTextColor(c.r, c.g, c.b)
    end
end

-- TBC / Era: fixed 13 px lines in the template; a larger font needs the
-- line to grow with it or the rows overlap.
local function restyleClassic()
    if not mod.active then return end
    local n = _G.MAX_QUESTWATCH_LINES or 30
    local h = (mod.db.fontSize or 12) + 2
    for i = 1, n do
        local fs = _G["QuestWatchLine" .. i]
        if not fs then break end
        if fs:IsShown() then
            paint(fs, fs:GetText())
            fs:SetHeight(h)
        end
    end
end

-- Wrath: the lines Blizzard used this pass are listed in WATCHFRAME_SETLINES.
local function restyleWrath()
    if not mod.active then return end
    local lines = _G.WATCHFRAME_SETLINES
    if type(lines) ~= "table" then return end
    for i = 1, #lines do
        local line = lines[i]
        if line and line.text then
            paint(line.text, line.text:GetText())
            if line.dash then UI.FontFor("questtracker", line.dash, mod.db.fontSize) end
        end
    end
end

local function restyle()
    if _G.QuestWatchFrame then restyleClassic() elseif _G.WatchFrame then restyleWrath() end
end

local function installHooks()
    if hooked then return end
    if _G.QuestWatch_Update then
        hooksecurefunc("QuestWatch_Update", restyleClassic)
        hooked = true
    elseif _G.WatchFrame_Update then
        hooksecurefunc("WatchFrame_Update", restyleWrath)
        hooked = true
    end
end

------------------------------------------------------------------------
-- Position: an anchor of ours carries the mover; the watch list hangs on
-- it once the player has moved it, and stays with Blizzard's layout until.
------------------------------------------------------------------------
local function attach()
    local w = watchFrame()
    if not (w and anchor) then return end
    w.ignoreFramePositionManager = true
    local parent = w:GetParent()
    if parent and parent.RemoveManagedFrame then pcall(parent.RemoveManagedFrame, parent, w) end
    w:SetParent(UIParent)
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
end

local function detach()
    local w = watchFrame()
    if not w then return end
    w.ignoreFramePositionManager = nil
    w:ClearAllPoints()
    -- the manager re-adopts the frame on its next pass (a reload is the
    -- clean way back, and the module toggle says so)
    if _G.UIParent_ManageFramePositions then pcall(_G.UIParent_ManageFramePositions) end
end

-- Until the player moves it, the anchor follows the list so the edit-mode
-- box appears where the list actually is.
local function syncAnchorToFrame()
    local w = watchFrame()
    if not (w and anchor) or mod.db.moved then return end
    local left, top = w:GetLeft(), w:GetTop()
    if not (left and top) then return end
    local x, y = ns:GetCenterOffsets(w)
    if x and y then
        mod.db.x, mod.db.y = x, y
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

local function ensureAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "VCUI_QuestTrackerAnchor", UIParent)
    anchor:SetSize(220, 24)
    anchor:SetPoint("CENTER", UIParent, "CENTER", mod.db.x or 0, mod.db.y or 0)
    mover = ns:CreateMover(anchor, {
        key    = "questtracker",
        db     = mod.db,
        label  = L["Quest Tracker"],
        width  = 220,
        height = 24,
        -- Called on every apply, the login restore included; a drop while the
        -- editor is open is the one that means "the player moved it".
        onMove = function()
            if (ns.IsEditModeActive and ns:IsEditModeActive()) or (ns.IsMoverEditMode and ns:IsMoverEditMode()) then
                mod.db.moved = true
            end
            if mod.db.moved then attach() end
        end,
        editPreview = function(state)
            if state then syncAnchorToFrame() end
        end,
    })
end

function mod:OnEnable()
    installHooks()
    ensureAnchor()
    ns:ApplyMover(mover)
    if self.db.moved then attach() end
    restyle()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if mod.db.moved then attach() end
        restyle()
    end)
end

function mod:OnDisable()
    -- the hooks stay (hooksecurefunc cannot be undone) and gate on mod.active
    detach()
end

function mod:GetOptions()
    local db = self.db
    local function apply() restyle() end
    local items = {}
    items[#items + 1] = { type = "toggle", label = L["Enable quest tracker"],
        get = function() return ns:IsModuleEnabled("questtracker") end,
        set = function(_, v) ns:ToggleModule("questtracker", v) end }
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "slider", label = L["Font size"], min = 9, max = 18, step = 1,
        get = function() return db.fontSize end,
        set = function(_, v) db.fontSize = v; apply() end }
    items[#items + 1] = { type = "toggle", label = L["Accent colour titles"],
        tooltip = L["Quest names in the interface accent colour; finished quests turn the done colour either way."],
        get = function() return db.titleAccent end,
        set = function(_, v) db.titleAccent = v; apply() end }
    items[#items + 1] = { type = "color", label = L["Objective colour"],
        get = function() return db.objectiveColor end,
        set = function(r, g, b) db.objectiveColor = { r = r, g = g, b = b }; apply() end }
    items[#items + 1] = { type = "color", label = L["Done colour"],
        get = function() return db.doneColor end,
        set = function(r, g, b) db.doneColor = { r = r, g = g, b = b }; apply() end }
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Position"] }
    items[#items + 1] = { type = "desc",
        text = L["|cffaaaaaaThe list keeps the game's own place until you drag its box in edit mode; from then on it stays where you put it.|r"] }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180,
              label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
              onClick = function()
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
                  if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
              end },
            { type = "button", width = 200, label = L["Back to the game's place"],
              onClick = function()
                  db.moved = false
                  detach()
              end },
        },
    }
    return items
end
