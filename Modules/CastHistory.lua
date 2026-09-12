-- VuloClassicUI / Modules / CastHistory: a strip of the spells you just cast,
-- newest first, failed and interrupted ones in red. Player only, read from
-- the unit spellcast events (no combat log), no events at all while off.
local _, ns = ...
local L  = ns.L

local mod = ns:RegisterModule("casthistory", {
    name        = "Cast History",
    group       = "HUD",
    description = "A strip of icons for the spells you just cast, newest first; a failed or interrupted cast turns red. Ships disabled: switch it on here.",
    defaults    = {
        enabled    = false,
        iconSize   = 32,
        iconCount  = 6,
        spacing    = 2,
        grow       = "LEFT",
        fadeAfter  = 0,        -- seconds until an icon fades out; 0 = never
        showFailed = true,
        x = 0, y = -200,
    },
})

local CreateFrame  = CreateFrame
local GetSpellInfo = GetSpellInfo
local GetTime      = GetTime
local wipe         = wipe

-- Auto attacks and shots are not casts anyone wants a strip of.
local SKIP = { [6603] = true, [75] = true, [5019] = true }
local MAX_ENTRIES = 40
local FADE_LEN    = 1.5
local RED         = { r = 0.86, g = 0.25, b = 0.25 }

local history = {}      -- newest first: { spell, icon, t, status }, status = "ok" | "failed" | "interrupted"
local frame, icons
local layoutDirty = false
local previewOn   = false   -- set by the mover's edit preview, never derived
local fading      = false   -- paint saw an icon still on its way out

------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------
local function push(spellId, status)
    if not spellId or SKIP[spellId] then return end
    local name, _, icon = GetSpellInfo(spellId)
    if not name or not icon then return end
    table.insert(history, 1, { spell = spellId, icon = icon, t = GetTime(), status = status })
    if #history > MAX_ENTRIES then history[#history] = nil end
    layoutDirty = true
end

-- A hard cast that gets kicked never fired SUCCEEDED, so it has no icon yet
-- and gets a red one. A channel did (SUCCEEDED fires when the channel opens),
-- so its own icon turns red instead of a second one joining.
local function markInterrupted(spellId)
    local e = history[1]
    if e and e.channel and e.spell == spellId and e.status == "ok" then
        e.status = "interrupted"
        layoutDirty = true
        return
    end
    push(spellId, "interrupted")
end

local function onSpellcast(_, event, unit, _, spellId)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        push(spellId, "ok")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local e = history[1]
        if e and e.spell == spellId then e.channel = true end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if mod.db.showFailed then push(spellId, "failed") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if mod.db.showFailed then markInterrupted(spellId) end
    end
end

local UNIT_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
                      "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

------------------------------------------------------------------------
-- Strip
------------------------------------------------------------------------
local function ensureIcon(i)
    local b = icons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.edges = ns.MakeEdges and ns.MakeEdges(b, "OVERLAY") or nil
    b:SetScript("OnEnter", function(self)
        if not self.spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetSpellByID(self.spell)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icons[i] = b
    return b
end

local function border(b, status)
    if not b.edges or not ns.LayoutEdges then return end
    if status == "ok" then
        local c = ns.COLORS.border
        ns.LayoutEdges(b.edges, b, 1, c.r, c.g, c.b, 1, 0)
    else
        ns.LayoutEdges(b.edges, b, 1, RED.r, RED.g, RED.b, 1, 0)
    end
end

-- The newest icon sits at the strip's anchor end; the strip grows away from
-- it, so a longer or shorter row never moves the icon the eye is on.
local function place(b, i)
    local db   = mod.db
    local step = (db.iconSize + db.spacing) * (i - 1)
    b:ClearAllPoints()
    if db.grow == "RIGHT" then
        b:SetPoint("LEFT", frame, "LEFT", step, 0)
    elseif db.grow == "UP" then
        b:SetPoint("BOTTOM", frame, "BOTTOM", 0, step)
    elseif db.grow == "DOWN" then
        b:SetPoint("TOP", frame, "TOP", 0, -step)
    else
        b:SetPoint("RIGHT", frame, "RIGHT", -step, 0)
    end
end

local function sizeFrame()
    local db = mod.db
    local n  = db.iconCount
    local len = n * db.iconSize + (n - 1) * db.spacing
    if db.grow == "UP" or db.grow == "DOWN" then
        frame:SetSize(db.iconSize, len)
    else
        frame:SetSize(len, db.iconSize)
    end
end

local function paint()
    if not frame then return end
    local db  = mod.db
    local n   = db.iconCount
    local now = GetTime()
    fading = false
    for i = 1, n do
        local b = ensureIcon(i)
        local e = history[i]
        b:SetSize(db.iconSize, db.iconSize)
        place(b, i)
        local alpha = e and 1 or 0
        if e and db.fadeAfter > 0 then
            local over = now - e.t - db.fadeAfter
            if over >= FADE_LEN then alpha = 0 elseif over > 0 then alpha = 1 - over / FADE_LEN end
            if alpha > 0 then fading = true end
        end
        if alpha > 0 then
            b.icon:SetTexture(e.icon)
            b.spell = e.spell
            border(b, e.status)
            b:SetAlpha(alpha)
            b:Show()
        elseif previewOn then
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            b.spell = nil
            border(b, "ok")
            b:SetAlpha(0.6)
            b:Show()
        else
            b:Hide()
        end
    end
    for i = n + 1, #icons do icons[i]:Hide() end
    layoutDirty = false
end

-- A tenth of a second: fades move, new casts appear. Nothing on its way out
-- and nothing new means one cheap flag check per tick.
local function tick()
    if layoutDirty or fading then paint() end
end

local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "VCUI_CastHistory", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetScript("OnEvent", onSpellcast)
    icons = {}
    frame.mover = ns:CreateMover(frame, {
        key   = "casthistory",
        db    = mod.db,
        label = L["Cast History"],
        editPreview = function(edit) previewOn = edit and true or false; paint() end,
    })
end

function mod:Apply()
    if not (self.active and frame) then return end
    sizeFrame()
    ns:RefreshMoverGeometry(frame.mover)
    paint()
end

function mod:OnEnable()
    ensureFrame()
    -- the mover holds the table it was created with; a profile switch hands
    -- the module a new one, and drags must land there, not in the old profile
    frame.mover.opts.db = self.db
    sizeFrame()
    ns:ApplyMover(frame.mover)
    frame:Show()
    -- player only at the source: every other unit's casts never reach Lua
    for _, ev in ipairs(UNIT_EVENTS) do frame:RegisterUnitEvent(ev, "player") end
    if not self.ticker then self.ticker = ns:AddTicker(0.1, tick, nil, "casthistory") end
    paint()
end

function mod:OnDisable()
    if self.ticker then ns:CancelTicker(self.ticker); self.ticker = nil end
    wipe(history)
    if frame then
        for _, ev in ipairs(UNIT_EVENTS) do frame:UnregisterEvent(ev) end
        frame:Hide()
    end
end

function mod:GetOptions()
    local db = self.db
    local function apply() mod:Apply() end
    local items = {}
    items[#items + 1] = { type = "toggle", label = L["Enable cast history"],
        get = function() return ns:IsModuleEnabled("casthistory") end,
        set = function(_, v) ns:ToggleModule("casthistory", v) end }
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
        get = function() return db.iconSize end, set = function(_, v) db.iconSize = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Icon count"], min = 1, max = 12, step = 1,
        get = function() return db.iconCount end, set = function(_, v) db.iconCount = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Spacing"], min = 0, max = 12, step = 1,
        get = function() return db.spacing end, set = function(_, v) db.spacing = v; apply() end }
    items[#items + 1] = { type = "dropdown", label = L["Growth direction"], width = 200,
        values = { { value = "LEFT", text = L["Left"] }, { value = "RIGHT", text = L["Right"] },
                   { value = "UP", text = L["Up"] }, { value = "DOWN", text = L["Down"] } },
        get = function() return db.grow end, set = function(_, v) db.grow = v; apply() end }
    items[#items + 1] = { type = "slider", label = L["Fade after (seconds)"], min = 0, max = 30, step = 1,
        tooltip = L["0 keeps every icon until a newer cast pushes it out."],
        get = function() return db.fadeAfter end, set = function(_, v) db.fadeAfter = v; apply() end }
    items[#items + 1] = { type = "toggle", label = L["Show failed casts"],
        tooltip = L["A cast that failed or was interrupted appears with a red border."],
        get = function() return db.showFailed end, set = function(_, v) db.showFailed = v end }
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Position"] }
    items[#items + 1] = {
        type = "group", layout = "row", gap = 8,
        items = {
            { type = "button", width = 180,
              label = ns:IsMoverEditMode() and L["Stop moving"] or L["Unlock / Move"],
              onClick = function()
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
                  if ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
              end },
        },
    }
    return items
end
