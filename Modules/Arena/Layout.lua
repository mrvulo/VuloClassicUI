-- =========================================================
-- VuloClassicUI / Modules / Arena / Layout
-- Drag & drop for the order of the arena frames.
-- Blizzard arranges them 1-5 stacked by default.
-- We override that with mod.db.slotOrder and mod.db.slotSpacing.
-- =========================================================
local _, ns = ...
local L = ns.L
local mod = ns.ArenaModule
local H = mod.helpers

-- =========================================================
-- Apply layout
-- =========================================================
local function applyLayout()
    local owner = H.GetOwner()
    if not owner then return end
    -- ArenaEnemyFrames are secure frames; moving them in combat is blocked
    -- and taints them. Skip now and re-apply on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then return end

    local order   = mod.db.slotOrder   or { 1, 2, 3, 4, 5 }
    local spacing = mod.db.slotSpacing or 6
    local grow    = mod.db.growDirection or "down"

    -- First frame relative to the container, all others relative to the previous
    local previous = nil
    for visualIndex, slotIndex in ipairs(order) do
        local frame = _G["ArenaEnemyFrame" .. slotIndex]
        if frame then
            frame:ClearAllPoints()
            local offsets = mod.db.slotOffsets and mod.db.slotOffsets[slotIndex] or { x = 0, y = 0 }

            if not previous then
                -- First visible frame on container
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
-- Hook into Blizzard's update so our layout takes effect after each refresh
-- =========================================================
local layoutHooked = false
local function hookLayout()
    if layoutHooked or not hooksecurefunc then return end
    layoutHooked = true

    -- ArenaEnemyFrames_UpdatePlayer is called per slot
    if _G.ArenaEnemyFrames_UpdatePlayer then
        hooksecurefunc("ArenaEnemyFrames_UpdatePlayer", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end
    -- General update
    if _G.ArenaEnemyFrames_Update then
        hooksecurefunc("ArenaEnemyFrames_Update", function()
            if not mod._enabled then return end
            applyLayout()
        end)
    end

    -- Re-apply once combat ends: frames that updated mid-combat were skipped
    -- by the InCombatLockdown guard in applyLayout.
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if mod._enabled then applyLayout() end
    end)
end

-- =========================================================
-- Layout editor: shows buttons in VCUI with up/down arrows to move single slots
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
    -- Re-render page to show new order
    ns.UI:BuildOptionsPage("arenaframes")
end

-- =========================================================
-- Lifecycle
-- =========================================================
mod:OnArenaFramesReady(function(frame, i)
    -- Nothing to do per frame, we set layout for all at once
end)

-- Install hook (happens after init, when Blizzard_ArenaUI is loaded)
local layoutInitFrame = CreateFrame("Frame")
layoutInitFrame:RegisterEvent("ADDON_LOADED")
layoutInitFrame:RegisterEvent("PLAYER_LOGIN")
layoutInitFrame:SetScript("OnEvent", function(_, _, addonName)
    hookLayout()
    if mod._enabled then applyLayout() end
end)

-- =========================================================
-- Options section
-- =========================================================
mod:AddOptionsSection("layout", function()
    local items = {
        { type = "header", text = L["Layout (Order)"] },
        { type = "desc",   text = L["Order of the arena frames. Use up/down to move slots 1-5."] },
        { type = "spacer", height = 4 },
    }

    -- One row per slot: [Slot N] [up] [down]
    for visualIndex, slotIndex in ipairs(mod.db.slotOrder) do
        table.insert(items, {
            type = "group", layout = "row", gap = 4,
            items = {
                { type = "desc", text = string.format(L["|cff9b6cff%d.|r  Arena Slot %d"], visualIndex, slotIndex), width = 140 },
                { type = "iconbutton", icon = "up",   width = 28, height = 24,
                  tooltip = L["Move up"],
                  onClick = function() moveSlot(slotIndex, -1) end },
                { type = "iconbutton", icon = "down", width = 28, height = 24,
                  tooltip = L["Move down"],
                  onClick = function() moveSlot(slotIndex,  1) end },
            },
        })
    end

    table.insert(items, { type = "spacer", height = 4 })
    table.insert(items, {
        type = "slider", label = L["Spacing between frames"],
        min = 0, max = 40, step = 1,
        get = function() return mod.db.slotSpacing end,
        set = function(_, v) mod.db.slotSpacing = v; applyLayout() end,
    })
    table.insert(items, {
        type = "dropdown", label = L["Grow direction"],
        values = {
            { value = "down", text = L["Downward"] },
            { value = "up",   text = L["Upward"] },
        },
        get = function() return mod.db.growDirection end,
        set = function(_, v) mod.db.growDirection = v; applyLayout() end,
    })
    table.insert(items, {
        type = "button", label = L["Reset order"], width = 180,
        onClick = function()
            mod.db.slotOrder = { 1, 2, 3, 4, 5 }
            applyLayout()
            ns.UI:BuildOptionsPage("arenaframes")
        end,
    })

    return items
end)
