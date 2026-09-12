-- VuloClassicUI / Modules / QuestTracker: the game's quest watch list in the
-- house style -- its own font and size, accent titles, green finished
-- objectives, and a position of your own once you move it in edit mode.
--
-- Two client shapes, verified against the anniversary UI source:
--   TBC / Era  : QuestWatchFrame with QuestWatchLine1..MAX_QUESTWATCH_LINES,
--                repainted by QuestWatch_Update (Blizzard_UIPanels_Game/TBC).
--                The line's role is read off the colour Blizzard just gave it.
--   Wrath      : WatchFrame with pooled lines; WatchFrame_SetLine hands us the
--                line and whether it is a header. Its link buttons repaint the
--                Blizzard colours on mouse-leave, so that hook repaints too.
-- Both are UIParent-managed frames: `ignoreFramePositionManager` takes one out
-- of the manager, RemoveManagedFrame drops it from the container it sits in,
-- and a Hide/Show pair hands it back. Nothing here is protected.
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
local restoring = false      -- true while OnEnable re-applies the saved position

local function watchFrame()
    return _G.QuestWatchFrame or _G.WatchFrame
end

------------------------------------------------------------------------
-- Painting. The role of a line is decided ONCE, at the hook where Blizzard
-- has just painted it, and cached on the FontString; every later repaint
-- (option change, world entry) reuses the cached role. Reading our own
-- colours back would misfile a green title as an objective.
------------------------------------------------------------------------
-- Blizzard's own colours: title 0.75/0.61/0, title with everything done
-- 1/0.82/0, finished objective 1/1/1, open objective 0.8/0.8/0.8.
local function classify(fs, text)
    local r, g, b = fs:GetTextColor()
    if text and text:sub(1, 3) == " - " then
        return "objective", (r > 0.95 and g > 0.95 and b > 0.95)
    end
    if r > 0.9 and g > 0.9 and b > 0.9 then return "objective", true end
    if g < 0.7 then return "title", false end
    if g > 0.8 and b < 0.2 then return "title", true end
    return "objective", false
end

local function paint(fs)
    local db = mod.db
    UI.FontFor("questtracker", fs, db.fontSize)
    local kind, done = fs._vcKind, fs._vcDone
    if done then
        local c = db.doneColor
        fs:SetTextColor(c.r, c.g, c.b)
    elseif kind == "title" then
        if db.titleAccent then
            local a = ns.COLORS.accent
            fs:SetTextColor(a.r, a.g, a.b)
        end
    else
        local c = db.objectiveColor
        fs:SetTextColor(c.r, c.g, c.b)
    end
end

------------------------------------------------------------------------
-- TBC / Era
------------------------------------------------------------------------
local lastFrameHeight = -1

-- Runs right after QuestWatch_Update: classify from Blizzard's colours,
-- paint, give each line the height its font needs (the template says 13 px
-- and Blizzard never touches it again), and tell the frame its true height
-- so the manager stacks the frames below it under the text, not into it.
local function onClassicUpdate()
    if not mod.active then return end
    local n = _G.MAX_QUESTWATCH_LINES or 30
    local h = (mod.db.fontSize or 12) + 3
    local total = 0
    for i = 1, n do
        local fs = _G["QuestWatchLine" .. i]
        if not fs then break end
        if fs:IsShown() then
            local text = fs:GetText()
            fs._vcKind, fs._vcDone = classify(fs, text)
            paint(fs)
            fs:SetHeight(h)
            total = total + h + (fs._vcKind == "title" and 4 or 0)
        end
    end
    local w = _G.QuestWatchFrame
    if w and total > 0 and total ~= lastFrameHeight then
        lastFrameHeight = total
        w:SetHeight(total)
        -- The manager also anchors protected bars (pet, stance). Called from
        -- our insecure hook in combat that would be a blocked SetPoint, so the
        -- relayout waits for the fight to end.
        if not mod.db.moved and _G.UIParent_ManageFramePositions then
            if InCombatLockdown() then
                ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                    if mod.active and not mod.db.moved then pcall(_G.UIParent_ManageFramePositions) end
                end)
            else
                pcall(_G.UIParent_ManageFramePositions)
            end
        end
    end
end

local function restyleClassic()
    if not mod.active then return end
    local n = _G.MAX_QUESTWATCH_LINES or 30
    local h = (mod.db.fontSize or 12) + 3
    for i = 1, n do
        local fs = _G["QuestWatchLine" .. i]
        if not fs then break end
        if fs:IsShown() and fs._vcKind then
            paint(fs)
            fs:SetHeight(h)
        end
    end
end

------------------------------------------------------------------------
-- Wrath: pooled lines, role handed over by WatchFrame_SetLine. Blizzard's
-- objective lines there are only the open ones (finished ones are dropped),
-- so the done colour shows on nothing but a finished quest's title.
------------------------------------------------------------------------
local wrathLines = setmetatable({}, { __mode = "k" })

local function onWrathSetLine(line, _, _, isHeader)
    if not mod.active or not (line and line.text) then return end
    line.text._vcKind = isHeader and "title" or "objective"
    line.text._vcDone = false
    wrathLines[line] = true
    paint(line.text)
    if line.dash then UI.FontFor("questtracker", line.dash, mod.db.fontSize) end
end

local function restyleWrath()
    if not mod.active then return end
    for line in pairs(wrathLines) do
        if line.text and line:IsShown() and line.text._vcKind then
            paint(line.text)
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
        hooksecurefunc("QuestWatch_Update", onClassicUpdate)
        hooked = true
    elseif _G.WatchFrame_SetLine then
        hooksecurefunc("WatchFrame_SetLine", onWrathSetLine)
        -- the link buttons restore Blizzard's colours on mouse-leave
        if _G.WatchFrameLinkButtonTemplate_Highlight then
            hooksecurefunc("WatchFrameLinkButtonTemplate_Highlight", restyleWrath)
        end
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
    local container = w.layoutParent or w:GetParent()
    if container and container.RemoveManagedFrame then pcall(container.RemoveManagedFrame, container, w) end
    w:SetParent(UIParent)
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
end

-- The container adopts a frame on its OnShow only, so handing the list back
-- means showing it again; with the flag cleared the show re-adds it.
local function detach()
    local w = watchFrame()
    if not w then return end
    w.ignoreFramePositionManager = nil
    w:ClearAllPoints()
    if w:IsShown() then
        w:Hide()
        w:Show()
    end
end

-- Until the player moves it, the anchor sits on the list's top-left corner,
-- so the edit-mode box moves exactly what it covers and the first drop
-- does not jump.
local function syncAnchorToFrame()
    local w = watchFrame()
    if not (w and anchor) or mod.db.moved then return end
    local left, top = w:GetLeft(), w:GetTop()
    if not (left and top) then return end
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    local x, y = ns:GetCenterOffsets(anchor)
    if x and y then mod.db.x, mod.db.y = x, y end
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
        -- editor is open (and not our own restore) is the player moving it.
        onMove = function()
            if not restoring and ns.IsMoverEditMode and ns:IsMoverEditMode() then
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
    restoring = true
    ns:ApplyMover(mover)
    restoring = false
    if self.db.moved then attach() end
    restyle()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if mod.db.moved then attach() end
        restyle()
    end)
end

function mod:OnDisable()
    -- the hooks stay (hooksecurefunc cannot be undone) and gate on mod.active
    if self.db.moved then detach() end
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
