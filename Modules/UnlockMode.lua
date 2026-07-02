-- =========================================================
-- VuloClassicUI / Modules / UnlockMode  ("Edit Mode")
-- The single Global entry for our Edit Mode HUD. It:
--   * toggles the HUD (Core/Mover.lua + UI/EditMode.lua),
--   * AND makes Blizzard's default frames movable inside the SAME HUD.
--
-- Blizzard frames use the "anchor frame" technique: one invisible addon frame
-- per Blizzard frame as the drag handle. The REAL unit frame is never left
-- anchored to an addon frame (that propagates combat protection onto the
-- anchor and taints Blizzard's secure unit-frame paths -> blocked
-- "TargetFrameToT:Show()" in combat).
--   * Edit Mode client (TBC Anniversary 20505): positions are written into the
--     Edit Mode layout via LibEditModeOverride as UIPARENT-relative offsets —
--     taint-free, applied and persisted by Blizzard's own manager. No raw
--     SetPoint ever touches an Edit-Mode-managed frame here.
--   * No Edit Mode (Classic Era): the field-proven recipe — SetMovable(true),
--     ClearAllPoints, SetPoint onto UIParent, SetUserPlaced(true) — applied on
--     drop and (only if drifted) once per login, never in combat. Unit frames
--     follow the box live only DURING a drag (transient link, detached on drop).
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

-- Edit Mode availability is checked at CALL time, not file-load time: on 20505
-- Blizzard_EditMode can load on demand AFTER this addon, which used to freeze
-- the check to false and route unit frames through raw SetPoint on an Edit-Mode
-- client — the exact taint behind blocked TargetFrameToT:Show()/Hide()
-- (Blizzard TargetFrame.lua:954, Update).
local function emClient()
    return (C_EditMode ~= nil) and (EditModeManagerFrame ~= nil)
end
-- On an EM-capable client make sure Blizzard_EditMode is actually loaded before
-- the first layout write (mirrors the Blizzard_ArenaUI force-load pattern).
local function ensureEMLoaded()
    if C_EditMode and not EditModeManagerFrame and not InCombatLockdown() then
        pcall(C_AddOns and C_AddOns.LoadAddOn or UIParentLoadAddOn or LoadAddOn, "Blizzard_EditMode")
    end
end
local lib    = LibStub and LibStub("LibEditModeOverride-1.0", true)
local LAYOUT = "VuloClassicUI"

local BLIZZ = {
    { key = "player",  name = "PlayerFrame",    label = "PLAYER",  secure = true },
    { key = "target",  name = "TargetFrame",    label = "TARGET",  secure = true },
    { key = "focus",   name = "FocusFrame",     label = "FOCUS",   secure = true },
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
-- Non-Edit-Mode path (Classic Era). Protected unit frames get the field-proven
-- recipe: anchored to UIPARENT (never to an addon frame) with the user-placed
-- flag set, so the client itself treats and restores the position as
-- player-chosen (C-side, secure). SetMovable(true) must precede
-- SetUserPlaced(true) or the flag silently fails to stick.
-- Non-protected frames (minimap, buffs) keep the old live anchor link.
-- HARD RULE: never runs on an Edit Mode client (C_EditMode present), never in
-- combat.
-- ---------------------------------------------------------
local function linkDirect(def)
    if InCombatLockdown() or C_EditMode then return end
    local frame, anchor = _G[def.name], anchors[def.key]
    local fdb = mod.db.frames[def.key]
    if not (frame and anchor and fdb) then return end
    if def.secure then
        pcall(frame.SetMovable, frame, true)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", fdb.x or 0, fdb.y or 0)
        pcall(frame.SetUserPlaced, frame, true)
        -- deliberately left movable; an immovable user-placed frame may not
        -- persist in the client's layout cache
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
end

-- Live-follow ONLY while a unit-frame box is actually being dragged (HUD open,
-- out of combat, non-EM client); linkDirect() detaches it back onto UIParent on
-- drop. Box and frame are coincident before the drag, so linking causes no jump.
local function dragLink(def)
    if InCombatLockdown() or C_EditMode then return end
    local frame, anchor = _G[def.name], anchors[def.key]
    if frame and anchor then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
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

-- Write the frame's position into the Edit Mode layout as a UIPARENT-relative
-- offset (no apply). NEVER reference an addon frame as relativeTo in the
-- layout: the layout stores the addon frame's NAME as relativeTo (the lib
-- resolves it via GetName()), leaving the protected frame's rect permanently
-- dependent on an insecurely-positioned addon frame — every anchor write then
-- taints the unit frame's anchor chain (-> blocked protected Show/Hide in
-- combat). The follow link was static anyway, so UX is unchanged.
-- Caller must have run emEnsure() first. Returns true if a link was written.
local function emReanchor(def)
    local done = false
    pcall(function()
        if not lib:CanEditActiveLayout() then return end
        local frame = _G[def.name]
        local fdb   = mod.db.frames[def.key]
        if frame and fdb and lib:HasEditModeSettings(frame) then
            lib:ReanchorFrame(frame, "CENTER", UIParent, "CENTER", fdb.x or 0, fdb.y or 0)
            done = true
        elseif frame and (def.key == "target" or def.key == "focus") then
            -- Edit Mode manages Target/Focus only while the account setting
            -- "Target and Focus" is enabled; without it our write is void.
            mod._needsTargetFocusSetting = true
        end
    end)
    return done
end

local function emApply()
    pcall(function()
        if InCombatLockdown() then lib:SaveOnly() else lib:ApplyChanges() end
    end)
end

-- Coalesce layout applies: held arrow keys / panel edits fire onMove per step,
-- and every ApplyChanges flushes the Edit Mode manager panel. One flush per
-- burst is enough (the emReanchor WRITES still happen immediately).
local function emApplyDebounced()
    if mod._emApplyPending then return end
    mod._emApplyPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            mod._emApplyPending = false
            emApply()
        end)
    else
        mod._emApplyPending = false
        emApply()
    end
end

-- Called by UI/EditMode.lua when the HUD opens: park each anchor box over its
-- frame and (re)link the frames the user has already placed.
function ns:PrepareBlizzMovers()
    ensureEMLoaded()
    if not emClient() or InCombatLockdown() then return end
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

            local mover = ns:CreateMover(anchor, {
                key    = "blizz:" .. def.key,
                label  = "|cffffffff" .. (L[def.label] or def.label) .. "|r",
                db     = fdb,
                scope  = "blizz",
                width  = anchor:GetWidth(),
                height = anchor:GetHeight(),
                -- Fires on every drag stop / arrow nudge / panel edit (fdb.x/y
                -- already updated by Core/Mover.lua). Both paths re-link every
                -- time: EM because the layout offset is static, Era because the
                -- frame must be detached from the anchor back onto UIParent.
                onMove = function()
                    fdb.placed = true
                    if emClient() then
                        if emEnsure() and emReanchor(def) then emApplyDebounced() end
                        if mod._needsTargetFocusSetting and not mod._warnedTF then
                            mod._warnedTF = true
                            ns:Print(L["Enable 'Target and Focus' in Blizzard's Edit Mode settings, then /reload, so VuloUI can move the target/focus frame."])
                        end
                    elseif InCombatLockdown() then
                        mod._restorePending = true   -- re-link once combat drops
                    else
                        linkDirect(def)
                    end
                end,
            })
            -- Era unit frames: glide with the box during the drag gesture only.
            if def.secure and mover and mover.HookScript then
                mover:HookScript("OnDragStart", function() dragLink(def) end)
            end
        end
    end

    -- Restore placed frames on login/zone-in — never in combat; retried once
    -- combat drops. Writes are skipped when the frame already sits where our
    -- SavedVariables say (steady state after the first session is zero-write:
    -- on EM clients Blizzard's layout persists itself, on Era the client
    -- restores user-placed frames C-side from its layout cache).
    local function drifted(frame, fdb)
        local cx, cy = centerOffset(frame)
        return math.abs(cx - (fdb.x or 0)) > 1.5 or math.abs(cy - (fdb.y or 0)) > 1.5
    end
    local function restoreAll()
        if InCombatLockdown() then mod._restorePending = true; return end
        mod._restorePending = false
        ensureEMLoaded()
        local em      = emClient()
        local ensured = em and emEnsure()
        -- one-time migration: older versions wrote VCUIAnchor_* frames as
        -- relativeTo into the EM layout; force one rewrite to UIParent anchors.
        local force   = em and not mod.db.emMigrated
        local any = false
        for _, def in ipairs(BLIZZ) do
            local frame, anchor = _G[def.name], anchors[def.key]
            local fdb = mod.db.frames[def.key]
            if frame and anchor and fdb and fdb.placed then
                placeAnchor(anchor, fdb.x, fdb.y)
                if em then
                    if (force or drifted(frame, fdb)) and ensured and emReanchor(def) then
                        any = true
                    end
                elseif def.secure and frame.IsUserPlaced and frame:IsUserPlaced()
                       and not drifted(frame, fdb) then
                    -- client already restored it natively — write nothing
                else
                    linkDirect(def)
                end
            end
        end
        if em and ensured then mod.db.emMigrated = true end
        if any then emApply() end
    end
    if not mod._evt then
        mod._evt = true
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", restoreAll)
        ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            if mod._restorePending then restoreAll() end
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
