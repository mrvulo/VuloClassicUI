-- Edit Mode HUD; Blizzard frames are never left anchored to an addon frame (taints secure unit-frame paths).
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("unlockmode", {
    name        = "Edit Mode",
    group       = "Global",
    noToggle    = true,
    description = "Move every VuloUI window and Blizzard's default frames in one editor.",
    defaults    = { enabled = true, frames = {} },
})

-- Checked at call time, not load time: Blizzard_EditMode may load on demand after this addon.
local function emClient()
    return (C_EditMode ~= nil) and (EditModeManagerFrame ~= nil)
end
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
local anchors = {}

local function rebuild()
    if ns.UI and ns.UI.BuildOptionsPage then
        ns.UI:BuildOptionsPage("unlockmode", ns.UI.currentTab)
    end
end

local function centerOffset(frame)
    -- scale-aware: Edit-Mode-scaled frames would otherwise park their anchors off
    local x, y = ns:GetCenterOffsets(frame)
    if not x then return 0, 0 end
    return x, y
end

local function placeAnchor(anchor, x, y)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)
end

-- Classic Era path only (never on an Edit Mode client, never in combat).
-- SetMovable(true) must precede SetUserPlaced(true) or the flag fails to stick.
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
        -- left movable on purpose; an immovable user-placed frame may not persist in the layout cache
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
end

-- Transient link during a drag only; linkDirect() detaches back onto UIParent on drop.
local function dragLink(def)
    if InCombatLockdown() or C_EditMode then return end
    local frame, anchor = _G[def.name], anchors[def.key]
    if frame and anchor then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
end

local function emEnsure()
    if not (lib and lib.IsReady and lib:IsReady()) then return false end
    return (pcall(function()
        lib:LoadLayouts()
        if not lib:CanEditActiveLayout() then
            if not lib:DoesLayoutExist(LAYOUT) then
                lib:AddLayout(Enum.EditModeLayoutType.Character, LAYOUT)
            else
                lib:SetActiveLayout(LAYOUT)
            end
        end
    end))
end

-- Never pass an addon frame as relativeTo: the layout stores its name and taints
-- the protected frame's anchor chain. Caller must have run emEnsure() first.
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
            -- Edit Mode manages Target/Focus only with the "Target and Focus" account setting on
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
                -- unplaced: park the box over the frame, don't link (would yank it on login)
                local x, y = centerOffset(frame)
                placeAnchor(anchor, x, y)
                if fdb then fdb.x, fdb.y = x, y end
            end
        end
    end
    if any then emApply() end

    -- Blizzard's Edit Mode owns far more frames than the five above, and
    -- emEnsure has to SELECT a layout before the library will let us write
    -- anything. Selecting a layout re-applies that layout's anchor to every
    -- system in it -- including the chat window, which we place ourselves and
    -- for which that layout holds nothing but a default.
    --
    -- Measured, not deduced. A hook on ChatFrame1:SetPoint while entering edit
    -- mode answered with
    --   Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:375 ApplySystemAnchor
    -- which is why the chat jumped left on every entry and stood correctly again
    -- the moment edit mode closed and our own code repositioned it.
    --
    -- Deferred by a frame: ApplyChanges does its anchoring first, and anything
    -- we place before that would simply be overwritten.
    if C_Timer and C_Timer.After and ns.ReapplyAllMovers then
        C_Timer.After(0, function() ns:ReapplyAllMovers() end)
    end
end

function mod:OnEnable()
    mod.db.frames = mod.db.frames or {}

    for _, def in ipairs(BLIZZ) do
        local frame = _G[def.name]
        -- the minimap module owns its own mover; wiring the cluster here would duplicate the box
        if def.key == "minimap" and ns.IsModuleEnabled and ns:IsModuleEnabled("minimapstyle") then
            frame = nil
        end
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
                onMove = function()
                    fdb.placed = true
                    if emClient() then
                        if emEnsure() and emReanchor(def) then emApplyDebounced() end
                        if mod._needsTargetFocusSetting and not mod._warnedTF then
                            mod._warnedTF = true
                            ns:Print(L["Enable 'Target and Focus' in Blizzard's Edit Mode settings, then /reload, so VuloUI can move the target/focus frame."])
                        end
                    elseif InCombatLockdown() then
                        mod._restorePending = true
                    else
                        linkDirect(def)
                    end
                end,
            })
            if def.secure and mover and mover.HookScript then
                mover:HookScript("OnDragStart", function() dragLink(def) end)
            end
        end
    end

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
        -- one-time migration: older versions wrote anchor frames as relativeTo into the EM layout
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
                    -- client already restored it natively
                else
                    linkDirect(def)
                end
            end
        end
        if em and ensured then mod.db.emMigrated = true end
        if any then emApply() end
    end
    -- restoreAll is a closure built inside this function, so it has a fresh
    -- identity on every call -- the registry's duplicate check cannot see that.
    -- The latch stays. (The module is noToggle, so these never need removing.)
    if not mod._evt then
        mod._evt = true
        ns:RegisterEvent("PLAYER_ENTERING_WORLD", restoreAll)
        ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            if mod._restorePending then restoreAll() end
        end)
    end
end

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
