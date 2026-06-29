-- =========================================================
-- VuloClassicUI / Core / Mover
-- Generic mover helper + a global EDIT MODE that shows every registered mover
-- at once (and mirrors Blizzard's Edit Mode where the client has one, e.g.
-- the Anniversary client).
--
--   - drag a purple box to move its frame
--   - arrow keys fine-tune (1px / SHIFT = 5px) while editing
--   - click a box (either button) -> selects it and opens the Edit Mode panel
--     (UI/EditMode.lua) with X / Y / reset
--
-- Usage:
--   local mover = ns:CreateMover(target, {
--       label  = "|cffffffffMY FRAME|r",
--       db     = mod.db,                 -- needs x, y (and optionally unlocked)
--       width  = 200, height = 40,
--       onMove   = function(x, y) end,   -- after a drag/key (optional)
--       applyPos = function() end,       -- custom reposition (optional; else CENTER)
--       editPreview = function(show) end,-- show/hide a preview while editing (optional)
--   })
-- =========================================================
local _, ns = ...

ns._movers          = ns._movers or {}      -- every mover created via ns:CreateMover
ns._moverEditGlobal = ns._moverEditGlobal or false
ns._moverEditScopes = ns._moverEditScopes or {}  -- per-module edit, e.g. ["cooldownmanager"]

-- Should THIS mover be draggable right now? Global edit, or its own scope.
local function moverShouldEdit(mover)
    if ns._moverEditGlobal then return true end
    local sc = mover.opts and mover.opts.scope
    return (sc and ns._moverEditScopes[sc]) and true or false
end

-- ---------------------------------------------------------
-- Positioning. Modules with their own anchoring pass opts.applyPos; everything
-- else stores a CENTER offset from the screen centre. Movers that opt in via
-- opts.scalable / opts.anchorable additionally honour db.scale (SetScale) and
-- db.anchor (which screen point the frame is pinned to). db.x/db.y ALWAYS stay
-- the CENTER offset, so magnetism works in one coordinate space and the anchor
-- point is only "what the frame is glued to", set without moving the frame.
-- ---------------------------------------------------------

-- Coordinates of a named point ("CENTER","TOPLEFT",...) on a frame, in that
-- frame's own coordinate space (raw GetLeft/GetBottom based).
local function pointXY(frame, point)
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (l and b and w and h) then return nil end
    local x = point:find("LEFT") and l or (point:find("RIGHT") and (l + w)) or (l + w / 2)
    local y = point:find("BOTTOM") and b or (point:find("TOP") and (b + h)) or (b + h / 2)
    return x, y
end

local function applyPos(mover)
    local opts = mover.opts
    if opts.applyPos then opts.applyPos(); return end
    local target, db = mover.target, opts.db

    if opts.scalable and db.scale then target:SetScale(db.scale) end

    -- canonical placement: the frame's CENTER at db.x/db.y from the screen centre
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)

    -- optionally RE-PIN to another point WITHOUT moving the frame, so it stays
    -- glued to that edge/corner across resolution / UI-scale changes. The user
    -- can switch this off per frame (db.anchorEnabled == false) to keep it on a
    -- plain CENTER offset; nil means "follow whatever anchor is set" (legacy).
    local anchorOn = (db.anchorEnabled ~= false)
    local p = opts.anchorable and anchorOn and db.anchor
    if p and p ~= "CENTER" then
        local fx, fy = pointXY(target, p)
        local ux, uy = pointXY(UIParent, p)
        if fx and ux then
            local r = UIParent:GetEffectiveScale() / (target:GetEffectiveScale() or 1)
            target:ClearAllPoints()
            target:SetPoint(p, UIParent, p, fx - ux * r, fy - uy * r)
        end
    end

    if opts.onMove then opts.onMove(db.x or 0, db.y or 0) end
end

-- Place a mover from its stored db.x/db.y after a drag / panel edit. Default
-- movers go through applyPos (so scale + anchor apply); movers with their OWN
-- applyPos keep the original plain-CENTER drop so their custom anchoring is not
-- regressed (they re-apply their own model from db elsewhere).
local function commitPos(mover)
    local opts = mover.opts
    if opts.applyPos then
        local db = opts.db
        mover.target:ClearAllPoints()
        mover.target:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)
        if opts.onMove then opts.onMove(db.x or 0, db.y or 0) end
    else
        applyPos(mover)
    end
end

-- Reset EVERY central mover back to the screen centre (db.x/db.y = 0) and
-- re-apply. Used by the Edit Mode HUD's "Reset positions" button. Movers with a
-- custom applyPos still get db.x/db.y zeroed and their applyPos re-run.
function ns:ResetAllMovers()
    for _, mover in ipairs(ns._movers) do
        local opts = mover.opts
        local db   = opts and opts.db
        if db then
            db.x, db.y = 0, 0
            pcall(applyPos, mover)
        end
    end
end

-- Re-apply a single mover's stored position (used by the Edit Mode panel).
function ns:ApplyMover(mover)
    if mover then pcall(applyPos, mover) end
end

-- Move one mover to a CENTER offset and persist it, honouring scale/anchor.
function ns:MoverSetCenter(mover, x, y)
    if not (mover and mover.target and mover.opts and mover.opts.db) then return end
    mover.opts.db.x, mover.opts.db.y = x, y
    commitPos(mover)
end

-- Scale / anchor-point setters used by the Edit Mode panel (opt-in movers only).
function ns:MoverSetScale(mover, s)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.scale = s
    applyPos(mover)
end

function ns:MoverSetAnchor(mover, point)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.anchor = point
    applyPos(mover)
end

-- Turn the per-frame anchor (edge/corner re-pin) on or off without moving the
-- frame. Off keeps it on a plain CENTER offset; on re-pins to db.anchor.
function ns:MoverSetAnchorEnabled(mover, on)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.anchorEnabled = on and true or false
    applyPos(mover)
end

function ns:IsMoverAnchorEnabled(mover)
    local db = mover and mover.opts and mover.opts.db
    return db ~= nil and db.anchorEnabled ~= false
end

-- ---------------------------------------------------------
-- Per-frame "free move": unlock a SINGLE window so its purple box stays grabbable
-- after Edit Mode is closed (and survives /reload). Independent of the global
-- Edit Mode AND of a module's own db.unlocked test/preview flag — this uses its
-- own db.freeMove so it never collides with per-module unlock buttons. Persists
-- in the module's own db next to x/y.
--
-- It deliberately does NOT drive opts.editPreview: free-move is a persistent
-- state, and forcing a preview/test bar on would leave fake content (a sample
-- castbar / scrolling text) on screen indefinitely. The box itself marks where
-- the frame sits and is the drag handle; aiming is done against the box.
-- ---------------------------------------------------------
function ns:IsMoverFreeMove(mover)
    local db = mover and mover.opts and mover.opts.db
    return db ~= nil and db.freeMove and true or false
end

function ns:SetMoverFreeMove(mover, on)
    if not (mover and mover.opts and mover.opts.db) then return end
    on = on and true or false
    mover.opts.db.freeMove = on
    -- The purple box is itself a HIGH-strata, mouse-enabled frame: showing it is
    -- all that's needed to drag the (anchored) target — no preview/test content
    -- is forced, so a preview-only frame doesn't get a permanent fake bar. Keep
    -- the box shown while free (or while global edit is on); hide it once locked
    -- again and edit is off.
    if on or moverShouldEdit(mover) then
        mover:Show()
    else
        mover:Hide()
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

-- After login, re-show the box of any window the user left "free move" on, so it
-- stays draggable across sessions without re-opening Edit Mode.
function ns:RestoreFreeMovers()
    for _, mover in ipairs(ns._movers) do
        local db = mover.opts and mover.opts.db
        if db and db.freeMove then mover:Show() end
    end
end

-- The old right-click "X / Y / reset" popup was removed. The Edit Mode HUD's
-- per-frame panel (UI/EditMode.lua) is now the single settings surface — both
-- left- and right-click on a mover box select it and open that one panel.

-- ---------------------------------------------------------
-- Named layouts: snapshot / restore every keyed mover's position (+ scale /
-- anchor where it opts in). A snapshot is a plain map key -> {x,y,scale,anchor},
-- decoupled from the live db so it survives profile switches and can be exported.
-- ---------------------------------------------------------
-- Custom positioners (CooldownManager bars chain to anchors; the Loadouts
-- sidebar pins to the CharacterFrame) carry a richer position model than a flat
-- x/y/scale/anchor snapshot can represent faithfully, so they OPT OUT of layouts
-- (captured/applied via opts.applyPos == nil).
function ns:CaptureLayout()
    local snap = {}
    for _, mover in ipairs(ns._movers) do
        local k  = mover.key
        local o  = mover.opts
        local db = o and o.db
        if k and db and not o.applyPos then
            local e = { x = db.x or 0, y = db.y or 0 }
            if o.scalable  and db.scale  then e.scale  = db.scale  end
            if o.anchorable and db.anchor then e.anchor = db.anchor end
            snap[k] = e
        end
    end
    return snap
end

-- Apply a snapshot to every keyed, non-custom mover whose key it contains.
-- Movers not in the snapshot are left untouched. Returns how many were moved.
function ns:ApplyLayout(snap)
    if type(snap) ~= "table" then return 0 end
    local n = 0
    for _, mover in ipairs(ns._movers) do
        local o  = mover.opts
        local k  = mover.key
        local e  = k and snap[k]
        local db = o and o.db
        if e and db and not o.applyPos then
            db.x, db.y = tonumber(e.x) or 0, tonumber(e.y) or 0
            if o.scalable   then db.scale  = tonumber(e.scale) or db.scale end
            if o.anchorable then db.anchor = e.anchor or db.anchor end
            pcall(applyPos, mover)
            n = n + 1
        end
    end
    -- Blizzard frames follow an invisible anchor; on the Edit-Mode client (TBC)
    -- the follow link is a STATIC layout snapshot, so moving the anchor alone
    -- doesn't move the real frame — re-establish the links after applying.
    if ns.PrepareBlizzMovers then ns:PrepareBlizzMovers() end
    return n
end

-- ---------------------------------------------------------
-- Export / import string (self-contained, no external libs). Format:
--   VCUI1!<name>!<entries>!<checksum>
-- entries: key=x,y[,s<scale>][,a<anchor>] joined by ';'. String fields are
-- percent-escaped for the delimiters so user-typed names are safe. The checksum
-- guards against truncated / corrupted paste.
-- ---------------------------------------------------------
local function esc(s)
    return (tostring(s):gsub("[%%;=,!\n\r]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
local function unesc(s)
    return (tostring(s):gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end
local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum * 31 + string.byte(s, i)) % 1000000007 end
    return string.format("%X", sum)
end

function ns:SerializeLayout(name, snap)
    local parts = {}
    for k, e in pairs(snap or {}) do
        local s = esc(k) .. "=" .. tostring(math.floor((tonumber(e.x) or 0) + 0.5))
                          .. "," .. tostring(math.floor((tonumber(e.y) or 0) + 0.5))
        if e.scale  then s = s .. ",s" .. string.format("%.4g", e.scale) end
        if e.anchor then s = s .. ",a" .. esc(e.anchor) end
        parts[#parts + 1] = s
    end
    table.sort(parts)   -- deterministic output
    local payload = esc(name or "") .. "!" .. table.concat(parts, ";")
    return "VCUI1!" .. payload .. "!" .. checksum(payload)
end

-- Returns name, snap on success; nil, errorKey on failure.
function ns:DeserializeLayout(str)
    if type(str) ~= "string" then return nil, "empty" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str == "" then return nil, "empty" end
    local payload, sum = str:match("^VCUI1!(.*)!(%x+)$")
    if not payload then return nil, "format" end
    if checksum(payload) ~= sum then return nil, "checksum" end
    local namePart, body = payload:match("^(.-)!(.*)$")
    if not namePart then return nil, "format" end
    local snap = {}
    if body ~= "" then
        for entry in body:gmatch("[^;]+") do
            local k, vals = entry:match("^(.-)=(.+)$")
            if k then
                local e = {}
                for tok in vals:gmatch("[^,]+") do
                    local p = tok:sub(1, 1)
                    if     p == "s" then e.scale  = tonumber(tok:sub(2))
                    elseif p == "a" then e.anchor = unesc(tok:sub(2))
                    elseif not e.x  then e.x = tonumber(tok)
                    elseif not e.y  then e.y = tonumber(tok) end
                end
                if e.x and e.y then snap[unesc(k)] = e end
            end
        end
    end
    return unesc(namePart), snap
end

-- ---------------------------------------------------------
-- Mover factory
-- ---------------------------------------------------------
function ns:CreateMover(target, opts)
    opts = opts or {}
    local db = opts.db
    assert(db, "ns:CreateMover needs opts.db")
    assert(target, "ns:CreateMover needs target")

    target:SetMovable(true)
    target:SetClampedToScreen(false)

    local mover = CreateFrame("Frame", nil, target)
    mover.target = target
    mover.opts   = opts
    -- Stable identity for named layouts / export-import (locale- and rename-proof).
    -- Prefer an explicit opts.key; else the frame's global name. Unkeyed movers
    -- simply aren't captured by layouts.
    mover.key    = opts.key or (target.GetName and target:GetName()) or nil
    mover:SetPoint("CENTER", target, "CENTER", 0, 0)
    mover:SetSize(opts.width or 200, opts.height or 40)
    mover:SetFrameStrata("HIGH")
    mover:EnableMouse(true)
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(0.6, 0.4, 1.0, 0.4)

    mover.border = CreateFrame("Frame", nil, mover,
        BackdropTemplateMixin and "BackdropTemplate")
    mover.border:SetAllPoints(mover)
    if mover.border.SetBackdrop then
        mover.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        mover.border:SetBackdropBorderColor(0.75, 0.35, 1, 1)
    end

    if opts.label then
        mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        mover.label:SetPoint("CENTER", mover, "CENTER", 0, 6)
        mover.label:SetJustifyH("CENTER")
        mover.label:SetText(opts.label)
        mover.hint = mover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        mover.hint:SetPoint("CENTER", mover, "CENTER", 0, -9)
        mover.hint:SetText((ns.L and ns.L["click to edit"]) or "click to edit")
    end

    -- Drag — moves target, writes x/y (a CENTER offset) into db
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        ns._draggingMover = mover
        -- if this box is part of a multi-selection, grab the whole group
        if ns.BeginGroupDrag then ns:BeginGroupDrag(mover) end
        target:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        ns._draggingMover = nil
        local fx, fy = target:GetCenter()
        local px, py = UIParent:GetCenter()
        if fx and fy and px and py then
            local x, y = fx - px, fy - py
            local rawx, rawy = x, y
            -- Edit Mode (UI/EditMode.lua): magnetism (snap to other frames' edges
            -- / centres + screen centre, with alignment guides) and a grid-snap
            -- fallback. No-op until EditMode.lua is loaded. CENTER-offset model.
            if ns.EditResolveDrop and ns:IsEditModeActive() then
                x, y = ns:EditResolveDrop(mover, x, y)
            elseif ns.EditSnapXY then
                x, y = ns:EditSnapXY(x, y)
            end
            db.x, db.y = x, y
            commitPos(mover)   -- default movers: position + scale + anchor; custom: plain CENTER
            -- group drag: shift the OTHER selected frames by the same delta the
            -- leader ended up taking (incl. any magnet snap) so the group stays rigid
            if ns.EndGroupDrag then ns:EndGroupDrag(x - rawx, y - rawy) end
            if ns.OnMoverMoved then ns:OnMoverMoved(mover) end
        elseif ns.EndGroupDrag then
            -- leader position unreadable (rare): still commit followers + clear group state
            ns:EndGroupDrag(0, 0)
        end
    end)

    -- Right-click also selects this frame (opens the Edit Mode panel) — there is
    -- one settings surface now, so both buttons lead to the same place.
    mover:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and ns.SelectMover then ns:SelectMover(self, IsShiftKeyDown()) end
    end)

    -- Hovering a box makes it the ACTIVE one — arrow keys then nudge only it
    -- (several movers are visible at once in edit mode, so we must single one out).
    mover:SetScript("OnEnter", function(self) ns._activeMover = self end)

    -- Keyboard — arrow keys 1px, SHIFT 5px (while editing OR individually unlocked)
    mover:EnableKeyboard(true)
    mover:SetPropagateKeyboardInput(true)
    mover:SetScript("OnKeyDown", function(self, key)
        -- only the last-hovered ("active") box reacts, so arrow keys nudge one
        if not (moverShouldEdit(self) or db.unlocked or db.freeMove) or ns._activeMover ~= self then
            self:SetPropagateKeyboardInput(true)
            return
        end
        local step = IsShiftKeyDown() and 5 or 1
        local dx, dy = 0, 0
        if     key == "UP"    then dy =  step
        elseif key == "DOWN"  then dy = -step
        elseif key == "LEFT"  then dx = -step
        elseif key == "RIGHT" then dx =  step
        else
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        db.x = (db.x or 0) + dx
        db.y = (db.y or 0) + dy
        applyPos(self)
        -- nudge the rest of a multi-selection by the same step
        if ns.NudgeGroupFollowers then ns:NudgeGroupFollowers(self, dx, dy) end
        -- keep the Edit Mode panel's X / Y in step while nudging this box
        if ns.OnMoverMoved then ns:OnMoverMoved(self) end
    end)

    -- left-click selects this frame in the Edit Mode HUD (opens its panel).
    -- Shift+click toggles it in/out of the selection set (multi-select).
    mover:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and ns.SelectMover then ns:SelectMover(self, IsShiftKeyDown()) end
    end)

    ns._movers[#ns._movers + 1] = mover

    -- Restore per-frame "free move" the moment the box exists. This covers movers
    -- built lazily (on first open) AFTER login, which a one-shot login pass would
    -- miss — the box reappears grabbable as soon as its window is created.
    if db.freeMove then mover:Show() end

    return mover
end

-- ---------------------------------------------------------
-- Global edit mode: show / hide EVERY registered mover at once
-- ---------------------------------------------------------
-- scope nil -> GLOBAL edit (every window). scope given -> just that module's.
function ns:SetMoversEditMode(state, scope)
    state = state and true or false
    if scope then
        if (ns._moverEditScopes[scope] or false) == state then return end
        ns._moverEditScopes[scope] = state or nil
    else
        if ns._moverEditGlobal == state then return end
        ns._moverEditGlobal = state
        if not state then wipe(ns._moverEditScopes) end
    end
    for _, mover in ipairs(ns._movers) do
        local opts = mover.opts
        local edit = moverShouldEdit(mover)
        if opts.editPreview then pcall(opts.editPreview, edit) end
        if edit then
            mover:Show()
        elseif not (opts.db and (opts.db.unlocked or opts.db.freeMove)) then
            mover:Hide()
        end
    end
end

-- scope nil -> is GLOBAL edit on?  scope given -> global OR that scope on.
function ns:IsMoverEditMode(scope)
    if ns._moverEditGlobal then return true end
    if scope then return ns._moverEditScopes[scope] == true end
    return false
end

-- Hook Blizzard's Edit Mode (Anniversary) so it toggles ours too.
function ns:HookBlizzardEditMode()
    -- No-op on purpose. Our Edit Mode HUD is self-driven (/vedit, Unlock Mode
    -- button) and moves Blizzard frames itself (Modules/UnlockMode.lua). On TBC,
    -- LibEditModeOverride briefly opens/closes EditModeManagerFrame every time it
    -- applies a change, so auto-opening our HUD from that frame's OnShow would
    -- create a feedback loop.
    return _G.EditModeManagerFrame ~= nil
end

-- Try the hook now and again when Blizzard_EditMode loads on demand.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, evt, name)
    if evt == "ADDON_LOADED" and name ~= "Blizzard_EditMode" then return end
    ns:HookBlizzardEditMode()
end)
