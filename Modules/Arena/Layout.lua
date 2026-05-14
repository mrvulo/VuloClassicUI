-- =========================================================
-- VuloClassicUI / Modules / Arena / Layout
-- Drag&Drop für die Reihenfolge der Arena-Frames.
-- Blizzard ordnet sie standardmäßig 1-5 untereinander an.
-- Wir überschreiben das mit mod.db.slotOrder und mod.db.slotSpacing.
-- =========================================================
local _, ns = ...
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- Layout anwenden
-- =========================================================
local function applyLayout()
    local owner = H.GetOwner()
    if not owner then return end

    local order   = mod.db.slotOrder   or { 1, 2, 3, 4, 5 }
    local spacing = mod.db.slotSpacing or 6
    local grow    = mod.db.growDirection or "down"

    -- Erstes Frame relative zum Container, alle anderen relativ zum vorherigen
    local previous = nil
    for visualIndex, slotIndex in ipairs(order) do
        local frame = _G["ArenaEnemyFrame" .. slotIndex]
        if frame then
            frame:ClearAllPoints()
            local offsets = mod.db.slotOffsets and mod.db.slotOffsets[slotIndex] or { x = 0, y = 0 }

            if not previous then
                -- Erstes sichtbares Frame an Container
                local anchorPoint = (grow == "down") and "TOP" or "BOTTOM"
                frame:SetPoint(anchorPoint, owner, anchorPoint, offsets.x or 0, offsets.y or 0)
            else
                local thisAnchor   = (grow == "down") and "TOP"    or "BOTTOM"
                local prevAnchor   = (grow == "down") and "BOTTOM" or "TOP"
                local yDelta       = (grow == "down") and -spacing or  spacing
                frame:SetPoint(thisAnchor, previous, prevAnchor, offsets.x or 0, (offsets.y or 0) + yDelta)
            end
            previous = frame
        end
    end
end

mod.ApplyLayout = applyLayout

-- =========================================================
-- Hook in Blizzards Update, damit unser Layout nach jedem Refresh greift
-- =========================================================
local layoutHooked = false
local function hookLayout()
    if layoutHooked or not hooksecurefunc then return end
    layoutHooked = true

    -- ArenaEnemyFrames_UpdatePlayer wird pro Slot aufgerufen
    if _G.ArenaEnemyFrames_UpdatePlayer then
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end
    -- Generelles Update
    if _G.ArenaEnemyFrames_Update then
        hooksecurefunc("ArenaEnemyFrames_Update", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end
end

-- =========================================================
-- Layout-Editor: zeigt Buttons im VCUI mit ↑ ↓ zum Verschieben einzelner Slots
-- =========================================================
local function moveSlot(slotIndex, direction)
    local order = mod.db.slotOrder
    local pos = nil
    for i, v in ipairs(order) do
        if v == slotIndex then pos = i; break end
    end
    if not pos then return end
    local newPos = pos + direction
    if newPos < 1 or newPos > #order then return end
    order[pos], order[newPos] = order[newPos], order[pos]
    applyLayout()
    -- Page neu rendern um neue Reihenfolge anzuzeigen
    ns.UI:BuildOptionsPage("arenaframes")
end

-- =========================================================
-- Lifecycle
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    -- Nichts pro Frame zu tun, wir setzen Layout für alle gleichzeitig
end)

-- Hook installieren (passiert nach Init, wenn Blizzard_ArenaUI da ist)
local layoutInitFrame = CreateFrame("Frame")
layoutInitFrame:RegisterEvent("ADDON_LOADED")
layoutInitFrame:RegisterEvent("PLAYER_LOGIN")
layoutInitFrame:SetScript("OnEvent", function(_, _, addonName)
    hookLayout()
    if mod._enabled then applyLayout() end
end)

-- =========================================================
-- Options-Section
-- =========================================================
mod:AddOptionsSection("layout", function()
    local items = {
        { type = "header", text = "Layout (Reihenfolge)" },
        { type = "desc",   text = "Reihenfolge der Arena-Frames. Nutze ↑/↓ um Slot 1-5 zu verschieben." },
        { type = "spacer", height = 4 },
    }

    -- Pro Slot eine Reihe: [Slot N] [↑] [↓]
    for visualIndex, slotIndex in ipairs(mod.db.slotOrder) do
        table.insert(items, {
            type = "group", layout = "row", gap = 4,
            items = {
                { type = "desc", text = string.format("|cff9b6cff%d.|r  Arena-Slot %d", visualIndex, slotIndex), width = 140 },
                { type = "iconbutton", icon = "up",   width = 28, height = 24,
                  tooltip = "Nach oben verschieben",
                  onClick = function() moveSlot(slotIndex, -1) end },
                { type = "iconbutton", icon = "down", width = 28, height = 24,
                  tooltip = "Nach unten verschieben",
                  onClick = function() moveSlot(slotIndex,  1) end },
            },
        })
    end

    table.insert(items, { type = "spacer", height = 4 })
    table.insert(items, {
        type = "slider", label = "Abstand zwischen Frames",
        min = 0, max = 40, step = 1,
        get = function() return mod.db.slotSpacing end,
        set = function(_, v) mod.db.slotSpacing = v; applyLayout() end,
    })
    table.insert(items, {
        type = "dropdown", label = "Wachstumsrichtung",
        values = {
            { value = "down", text = "Nach unten" },
            { value = "up",   text = "Nach oben" },
        },
        get = function() return mod.db.growDirection end,
        set = function(_, v) mod.db.growDirection = v; applyLayout() end,
    })
    table.insert(items, {
        type = "button", label = "Reihenfolge zurücksetzen", width = 180,
        onClick = function()
            mod.db.slotOrder = { 1, 2, 3, 4, 5 }
            applyLayout()
            ns.UI:BuildOptionsPage("arenaframes")
        end,
    })

    return items
end)
