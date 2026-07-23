-- VuloClassicUI / Core / Mover: generic mover helper + global edit mode.
local _, ns = ...

ns._movers          = ns._movers or {}
ns._moverEditGlobal = ns._moverEditGlobal or false
ns._moverEditScopes = ns._moverEditScopes or {}

local function moverShouldEdit(mover)
    if ns._moverEditGlobal then return true end
    local sc = mover.opts and mover.opts.scope
    return (sc and ns._moverEditScopes[sc]) and true or false
end

-- Factor between a frame's LOCAL units (SetPoint offsets, db.x) and UIParent units.
function ns:GetScaleRatio(frame)
    if not (frame and frame.GetEffectiveScale) then return 1 end
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    if s == 0 then return 1 end
    return s
end

-- THE formula for anything writing db.x/db.y; plain `fx - px` breaks on scaled frames.
-- Returns nil while the frame has no rect yet (early login).
function ns:GetCenterOffsets(frame)
    if not (frame and frame.GetCenter) then return nil end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and fy and px and py) then return nil end
    local s = ns:GetScaleRatio(frame)
    return fx - px / s, fy - py / s
end

-- db.x/db.y are ALWAYS a CENTER offset, whatever db.anchor is; anchor only re-pins.
-- Named point on a frame, in that frame's own coordinate space.
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

    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)

    -- Re-pin to another point WITHOUT moving the frame, so it survives resolution
    -- and UI-scale changes. nil anchorEnabled means "follow db.anchor" (legacy).
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

-- Movers with their OWN applyPos keep the plain-CENTER drop; they re-apply their
-- custom anchor model from db themselves.
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

-- ---------------------------------------------------------------------------
-- Persistent window links: a mover can be pinned to another mover and follows
-- whenever that one moves. Stored PER PROFILE (class isolation intact) as
-- moverLinks[childKey] = { to = parentKey, dx, dy } with dx/dy in UIParent units.

local function linkStore()
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.moverLinks = p.moverLinks or {}
    return p.moverLinks
end

function ns:GetMoverByKey(key)
    if not key then return nil end
    for _, m in ipairs(ns._movers) do
        if m.key == key then return m end
    end
    return nil
end

-- frame centre as an offset from UIParent's centre, in UIParent units —
-- comparable across frames with different effective scales
local function screenCenter(frame)
    if not (frame and frame.GetCenter) then return nil end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and px) then return nil end
    local fs = frame:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then return nil end
    return (fx * fs - px * us) / us, (fy * fs - py * us) / us
end

function ns:GetMoverLink(key)
    local store = linkStore()
    return (store and key) and store[key] or nil
end

function ns:MoverLinkWouldCycle(childKey, parentKey)
    local store = linkStore()
    if not store then return false end
    local seen, cur = {}, parentKey
    while cur do
        if cur == childKey then return true end
        if seen[cur] then return false end
        seen[cur] = true
        local l = store[cur]
        cur = (type(l) == "table" and type(l.to) == "string") and l.to or nil
    end
    return false
end

function ns:SetMoverLink(child, parentKey)
    local store = linkStore()
    if not (store and child and child.key) then return false end
    if not parentKey or parentKey == "" then
        store[child.key] = nil
        return true
    end
    if parentKey == child.key or ns:MoverLinkWouldCycle(child.key, parentKey) then
        return false
    end
    local parent = ns:GetMoverByKey(parentKey)
    if not (parent and parent.target) then return false end
    local cx, cy = screenCenter(child.target)
    local px, py = screenCenter(parent.target)
    if not (cx and px) then return false end
    store[child.key] = { to = parentKey, dx = cx - px, dy = cy - py }
    return true
end

local function applyLink(child, link)
    -- link may come from an imported profile: tolerate any garbage in it
    if type(link) ~= "table" or type(link.to) ~= "string" then return end
    local dx = type(link.dx) == "number" and link.dx or 0
    local dy = type(link.dy) == "number" and link.dy or 0
    local parent = ns:GetMoverByKey(link.to)
    if not (parent and parent.target and child.opts and child.opts.db) then return end
    local px, py = screenCenter(parent.target)
    if not px then return end
    local r = ns:GetScaleRatio(child.target)
    child.opts.db.x = (px + dx) / r
    child.opts.db.y = (py + dy) / r
    commitPos(child)
end

-- After ANY reposition of `mover`: a moved child keeps its link at the new
-- distance, and every child linked to `mover` is dragged along (chains included;
-- `visited` guards against runtime cycles).
function ns:OnMoverRepositioned(mover, visited)
    local store = linkStore()
    if not (store and mover and mover.key) then return end
    visited = visited or {}
    if visited[mover.key] then return end
    visited[mover.key] = true

    local own = store[mover.key]
    if own then
        local parent = ns:GetMoverByKey(own.to)
        local cx, cy = screenCenter(mover.target)
        local px, py = parent and parent.target and screenCenter(parent.target)
        if cx and px then own.dx, own.dy = cx - px, cy - py end
    end

    for key, link in pairs(store) do
        if link.to == mover.key and not visited[key] then
            local child = ns:GetMoverByKey(key)
            if child then
                applyLink(child, link)
                ns:OnMoverRepositioned(child, visited)
            end
        end
    end
end

-- login / layout import / reset: apply every link parent-first
function ns:ApplyAllMoverLinks()
    local store = linkStore()
    if not store then return end
    local resolved = {}
    local function resolve(key)
        if resolved[key] then return end
        resolved[key] = true
        local link = store[key]
        if not link then return end
        if store[link.to] then resolve(link.to) end
        local child = ns:GetMoverByKey(key)
        if child then applyLink(child, link) end
    end
    for key in pairs(store) do resolve(key) end
end

function ns:ResetAllMovers()
    -- lets onMove callbacks tell an explicit reset apart from a drag snapped to 0,0
    ns._inMoverReset = true
    for _, mover in ipairs(ns._movers) do
        local opts = mover.opts
        local db   = opts and opts.db
        if db then
            db.x, db.y = 0, 0
            pcall(applyPos, mover)
        end
    end
    ns._inMoverReset = false
    ns:ApplyAllMoverLinks()
end

function ns:ApplyMover(mover)
    if mover then pcall(applyPos, mover) end
end

function ns:MoverSetCenter(mover, x, y)
    if not (mover and mover.target and mover.opts and mover.opts.db) then return end
    mover.opts.db.x, mover.opts.db.y = x, y
    commitPos(mover)
    ns:OnMoverRepositioned(mover)
end

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

function ns:MoverSetAnchorEnabled(mover, on)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.anchorEnabled = on and true or false
    applyPos(mover)
end

function ns:IsMoverAnchorEnabled(mover)
    local db = mover and mover.opts and mover.opts.db
    return db ~= nil and db.anchorEnabled ~= false
end

-- Per-frame "free move": db.freeMove is deliberately separate from db.unlocked so
-- it never collides with per-module unlock buttons, and it never drives
-- opts.editPreview (a persistent state must not leave fake content on screen).
function ns:IsMoverFreeMove(mover)
    local db = mover and mover.opts and mover.opts.db
    return db ~= nil and db.freeMove and true or false
end

function ns:SetMoverFreeMove(mover, on)
    if not (mover and mover.opts and mover.opts.db) then return end
    on = on and true or false
    mover.opts.db.freeMove = on
    if on or moverShouldEdit(mover) then
        mover:Show()
    else
        mover:Hide()
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

function ns:RestoreFreeMovers()
    for _, mover in ipairs(ns._movers) do
        local db = mover.opts and mover.opts.db
        if db and db.freeMove then mover:Show() end
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

-- Layout snapshot: key -> {x,y,scale,anchor}. Movers with a custom opts.applyPos
-- opt out — a flat x/y snapshot cannot represent their richer position model.
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

-- Returns how many movers were moved; movers absent from the snapshot are untouched.
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
    ns:ApplyAllMoverLinks()
    -- On the Edit-Mode client (TBC) the Blizzard follow link is a static snapshot,
    -- so moving the anchor alone doesn't move the frame; re-establish the links.
    if ns.PrepareBlizzMovers then ns:PrepareBlizzMovers() end
    return n
end

-- Export format: VCUI1!<name>!key=x,y[,s<scale>][,a<anchor>];...!<checksum>
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
    table.sort(parts)
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
    -- Stable identity for layouts; unkeyed movers are simply not captured.
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

    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        ns._draggingMover = mover
        if ns.BeginGroupDrag then ns:BeginGroupDrag(mover) end
        target:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        ns._draggingMover = nil
        local x, y = ns:GetCenterOffsets(target)
        if x and y then
            local rawx, rawy = x, y
            -- Magnetism / grid snap from UI/EditMode.lua; no-op until it is loaded.
            if ns.EditResolveDrop and ns:IsEditModeActive() then
                x, y = ns:EditResolveDrop(mover, x, y)
            elseif ns.EditSnapXY then
                x, y = ns:EditSnapXY(x, y, ns:GetScaleRatio(target))
            end
            db.x, db.y = x, y
            commitPos(mover)
            -- shift followers by the leader's snap delta so the group stays rigid
            if ns.EndGroupDrag then ns:EndGroupDrag(x - rawx, y - rawy) end
            ns:OnMoverRepositioned(mover)
            if ns.OnMoverMoved then ns:OnMoverMoved(mover) end
        elseif ns.EndGroupDrag then
            ns:EndGroupDrag(0, 0)
        end
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and ns.SelectMover then ns:SelectMover(self, IsShiftKeyDown()) end
    end)

    -- Hover picks the single mover the arrow keys nudge (many are visible at once).
    mover:SetScript("OnEnter", function(self) ns._activeMover = self end)

    mover:EnableKeyboard(true)
    mover:SetPropagateKeyboardInput(true)
    mover:SetScript("OnKeyDown", function(self, key)
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
        if ns.NudgeGroupFollowers then ns:NudgeGroupFollowers(self, dx, dy) end
        ns:OnMoverRepositioned(self)
        if ns.OnMoverMoved then ns:OnMoverMoved(self) end
    end)

    mover:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and ns.SelectMover then ns:SelectMover(self, IsShiftKeyDown()) end
    end)

    ns._movers[#ns._movers + 1] = mover

    -- Restore free-move here too: lazily built movers miss the one-shot login pass.
    if db.freeMove then
        mover:Show()
        if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    end

    -- A mover built after the login link pass must still honour its saved link,
    -- and pull in any child already waiting on it. Deferred so the frame has a
    -- rect (screenCenter needs one) before the offsets are computed.
    if mover.key and ns._movers and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local store = linkStore()
            if not store then return end
            local own = store[mover.key]
            if own then applyLink(mover, own) end
            for k, link in pairs(store) do
                if type(link) == "table" and link.to == mover.key then
                    local child = ns:GetMoverByKey(k)
                    if child then applyLink(child, link) end
                end
            end
        end)
    end

    return mover
end

-- scope nil -> global edit (every window); scope given -> just that module's.
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
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

function ns:IsMoverEditMode(scope)
    if ns._moverEditGlobal then return true end
    if scope then return ns._moverEditScopes[scope] == true end
    return false
end

function ns:HookBlizzardEditMode()
    -- Intentional no-op: on TBC, applying a change briefly opens/closes
    -- EditModeManagerFrame, so hooking its OnShow would create a feedback loop.
    return _G.EditModeManagerFrame ~= nil
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, evt, name)
    if evt == "PLAYER_ENTERING_WORLD" then
        -- after every module applied its own saved position; links win last
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function() ns:ApplyAllMoverLinks() end)
        else
            ns:ApplyAllMoverLinks()
        end
        return
    end
    if evt == "ADDON_LOADED" and name ~= "Blizzard_EditMode" then return end
    ns:HookBlizzardEditMode()
end)
