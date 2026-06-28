-- =========================================================
-- VuloClassicUI / Modules / UnlockMode  ("Edit Mode")
-- The single Global entry for our Edit Mode HUD. It:
--   * toggles the HUD (Core/Mover.lua + UI/EditMode.lua),
--   * AND makes Blizzard's default frames movable inside the SAME HUD.
--
-- Blizzard frames use the "anchor frame" technique: one invisible addon frame
-- per Blizzard frame; the Blizzard frame FOLLOWS it. Dragging our anchor (a
-- normal addon frame) moves the Blizzard frame — no StartMoving on Edit-Mode
-- managed frames.
--   * TBC Anniversary (Blizzard Edit Mode present): the follow link is written
--     into the Edit Mode layout via LibEditModeOverride (:ReanchorFrame) —
--     taint-free and persisted by Blizzard. We only link a frame once the user
--     actually moves it, so untouched frames keep Blizzard's default placement.
--   * Classic Era (no Edit Mode): the Blizzard frame is SetPoint'd onto our
--     anchor (a live anchor), restored on login.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("unlockmode", {
    name        = "Edit Mode",
    group       = "Global",
    noToggle    = true,   -- it's an action, not an on/off feature
    description = "Move every VuloUI window and Blizzard's default frames in one editor.",
    defaults    = { enabled = true, frames = {} },
})

local hasEM  = (C_EditMode ~= nil) and (EditModeManagerFrame ~= nil)
local lib    = LibStub and LibStub("LibEditModeOverride-1.0", true)
local LAYOUT = "VuloClassicUI"

local BLIZZ = {
    { key = "player",  name = "PlayerFrame",    label = "PLAYER"  },
    { key = "target",  name = "TargetFrame",    label = "TARGET"  },
    { key = "focus",   name = "FocusFrame",     label = "FOCUS"   },
    { key = "minimap", name = "MinimapCluster", label = "MINIMAP" },
    { key = "buffs",   name = "BuffFrame",      label = "BUFFS"   },
}
local anchors = {}   -- key -> our invisible anchor frame

local function rebuild()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("unlockmode", ns.UI.currentTab)
    end
end

local function centerOffset(frame)
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and px) then return 0, 0 end
    return fx - px, fy - py
end

local function placeAnchor(anchor, x, y)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)
end

-- ---------------------------------------------------------
-- Era path: the real frame follows our anchor via a live SetPoint.
-- ---------------------------------------------------------
local function linkDirect(frame, anchor)
    if InCombatLockdown() then return end
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, true) end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
end

-- ---------------------------------------------------------
-- TBC path: LibEditModeOverride writes the follow link into the Edit Mode layout.
-- ---------------------------------------------------------
local function emEnsure()
    if not (lib and lib.IsReady and lib:IsReady()) then return false end
    return (pcall(function()
        lib:LoadLayouts()
        if not lib:CanEditActiveLayout() then
            if not lib:DoesLayoutExist(LAYOUT) then
                lib:AddLayout(Enum.EditModeLayoutType.Character, LAYOUT)  -- also activates it
            else
                lib:SetActiveLayout(LAYOUT)
            end
        end
    end))
end

-- Reanchor a single frame onto its anchor in the layout (no apply). Caller must
-- have run emEnsure() first. Returns true if a link was written.
local function emReanchor(def)
    local done = false
    pcall(function()
        if not lib:CanEditActiveLayout() then return end
        local frame, anchor = _G[def.name], anchors[def.key]
        if frame and anchor and lib:HasEditModeSettings(frame) then
            lib:ReanchorFrame(frame, "CENTER", anchor, "CENTER", 0, 0)
            done = true
        end
    end)
    return done
end

local function emApply()
    pcall(function()
        if InCombatLockdown() then lib:SaveOnly() else lib:ApplyChanges() end
    end)
end

-- Called by UI/EditMode.lua when the HUD opens: park each anchor box over its
-- frame and (re)link the frames the user has already placed.
function ns:PrepareBlizzMovers()
    if not hasEM or InCombatLockdown() then return end
    if not emEnsure() then return end
    local any = false
    for _, def in ipairs(BLIZZ) do
        local frame, anchor = _G[def.name], anchors[def.key]
        local fdb = mod.db.frames[def.key]
        if frame and anchor then
            if fdb and fdb.placed then
                placeAnchor(anchor, fdb.x, fdb.y)
                if emReanchor(def) then any = true end
            else
                -- not yet placed: park the box over the frame, don't link it
                -- (linking an unplaced frame would yank it to the anchor on login)
                local x, y = centerOffset(frame)
                placeAnchor(anchor, x, y)
                if fdb then fdb.x, fdb.y = x, y end
            end
        end
    end
    if any then emApply() end
end

function mod:OnEnable()
    mod.db.frames = mod.db.frames or {}

    for _, def in ipairs(BLIZZ) do
        local frame = _G[def.name]
        if frame and not def._wired then
            def._wired = true
            local fdb = mod.db.frames[def.key] or {}
            mod.db.frames[def.key] = fdb

            local cx, cy = centerOffset(frame)
            local ax = fdb.placed and (fdb.x or 0) or cx
            local ay = fdb.placed and (fdb.y or 0) or cy
            fdb.x, fdb.y = ax, ay

            local anchor = CreateFrame("Frame", "VCUIAnchor_" .. def.key, UIParent)
            anchor:SetSize(math.max(80, frame:GetWidth() or 120), math.max(36, frame:GetHeight() or 40))
            placeAnchor(anchor, ax, ay)
            anchors[def.key] = anchor

            ns:CreateMover(anchor, {
                key    = "blizz:" .. def.key,
                label  = "|cffffffff" .. (L[def.label] or def.label) .. "|r",
                db     = fdb,
                scope  = "blizz",
                width  = anchor:GetWidth(),
                height = anchor:GetHeight(),
                -- Dragging moves the anchor; the Blizzard frame follows. On the
                -- first move we establish the follow link.
                onMove = function()
                    if not fdb.placed then
                        fdb.placed = true
                        if hasEM then
                            if emEnsure() then emReanchor(def); emApply() end
                        else
                            linkDirect(frame, anchor)
                        end
                    end
                end,
            })
        end
    end

    -- Restore placed frames on login (out of combat).
    if not mod._evt then
        mod._evt = true
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
            if InCombatLockdown() then return end
            local ensured = hasEM and emEnsure()
            local any = false
            for _, def in ipairs(BLIZZ) do
                local frame, anchor = _G[def.name], anchors[def.key]
                local fdb = mod.db.frames[def.key]
                if frame and anchor and fdb and fdb.placed then
                    placeAnchor(anchor, fdb.x, fdb.y)
                    if hasEM then
                        if ensured and emReanchor(def) then any = true end
                    else
                        linkDirect(frame, anchor)
                    end
                end
            end
            if any then emApply() end
        end)
    end
end

-- =========================================================
-- Options page (English; one entry for the whole Edit Mode)
-- =========================================================
function mod:GetOptions()
    local on = (ns.IsEditModeActive and ns:IsEditModeActive()) or ns:IsMoverEditMode()
    local items = {
        { type = "header", text = L["Edit Mode"] },
        { type = "desc",
          text = L["|cffaaaaaaMove everything in one editor: VuloUI windows and Blizzard's frames (player, target, focus, minimap, buffs). They snap to a shared grid.|r"] },
        { type = "spacer", height = 6 },
        { type = "button", primary = true, width = 360,
          label = on and L["Done — lock everything"] or L["Open Edit Mode"],
          onClick = function()
              if ns.SetEditMode then
                  ns:SetEditMode(not ns:IsEditModeActive())
              else
                  ns:SetMoversEditMode(not ns:IsMoverEditMode())
              end
              rebuild()
          end },
        { type = "spacer", height = 8 },
        { type = "desc",
          text = L["|cff888888• Drag a purple box to move that frame.|n• Hover a box, then arrow keys fine-tune (SHIFT = 5px).|n• Right-click a box for exact X / Y.|n• |cffffffff/vedit|r toggles Edit Mode too.|r"] },
    }
    if on then
        items[#items + 1] = { type = "desc",
            text = L["|cff44ff44Edit Mode is ON.|r Close this window to reach the boxes."] }
    end
    return items
end
