-- =========================================================
-- VuloClassicUI / Modules / CooldownManager
-- A retail-style cooldown bar for Classic: add your spells/trinkets
-- and watch their cooldowns as a row of icons with a sweep, a
-- countdown number and a ready flash. Add entries by typing a
-- name/ID, shift-clicking a spell into the box, or dragging a
-- spell/item onto the bar while unlocked.
-- Icons only DISPLAY cooldowns (no casting) -> no secure/taint issues.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("cooldownmanager", {
    name        = "Cooldown Manager",
    group       = "QoL",
    description = "A row of icons that shows the cooldowns of spells and trinkets you choose — like the retail cooldown manager.",
    defaults    = {
        enabled        = true,
        entries        = {},        -- ordered: { kind = "spell"|"item", id = number }
        iconSize       = 40,
        spacing        = 4,
        perRow         = 12,
        growth         = "RIGHT",   -- RIGHT | LEFT | UP | DOWN
        onlyOnCooldown = false,     -- true = hide ready icons
        showText       = true,
        desaturate     = true,
        readyFlash     = true,
        unlocked       = false,
        x              = 0,
        y              = -160,
    },
})

-- =========================================================
-- API compat (2.5.5 has no C_Spell / global GetItemCooldown reliably)
-- =========================================================
local GetSpellCooldown = _G.GetSpellCooldown
    or (C_Spell and C_Spell.GetSpellCooldown)
local GetSpellInfo = _G.GetSpellInfo
local GetItemIcon  = _G.GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local function getItemCooldown(itemID)
    if not itemID then return 0, 0, 0 end
    if _G.GetItemCooldown then return GetItemCooldown(itemID) end
    if C_Item and C_Item.GetItemCooldown then
        local s, d, e = C_Item.GetItemCooldown(itemID)
        return s, d, (e == true and 1) or (e == false and 0) or e
    end
    if C_Container and C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end
    return 0, 0, 0
end

-- Normalise GetSpellCooldown across the global (start,dur,enabled) and the
-- newer table form ({startTime, duration, isEnabled}).
local function spellCooldown(id)
    if not GetSpellCooldown then return 0, 0, 1 end
    local a, b, c = GetSpellCooldown(id)
    if type(a) == "table" then
        return a.startTime or 0, a.duration or 0, a.isEnabled ~= false and 1 or 0
    end
    return a or 0, b or 0, c or 1
end

local GCD_MAX = 1.5  -- treat anything this short as the global cooldown

-- =========================================================
-- State
-- =========================================================
local bar              -- container frame
local icons = {}       -- pooled icon frames
local throttle = 0
local FONT = "Fonts\\FRIZQT__.TTF"

local function db() return mod.db end

-- =========================================================
-- Entry resolution
-- =========================================================
-- Resolve a typed/linked/dragged input to (kind, id). Accepts: spell link,
-- item link, plain numeric ID, or a plain spell/item name.
local function resolveInput(text)
    if not text or text == "" then return nil end
    local sid = text:match("|Hspell:(%d+)")
    if sid then return "spell", tonumber(sid) end
    local iid = text:match("|Hitem:(%d+)")
    if iid then return "item", tonumber(iid) end

    local num = tonumber(text)
    if num then
        if GetSpellInfo(num) then return "spell", num end
        if GetItemInfo(num) then return "item", num end
        return nil
    end

    -- plain name: spell first, then item
    if GetSpellInfo(text) then
        local id = select(7, GetSpellInfo(text))
        if id then return "spell", id end
    end
    local _, link = GetItemInfo(text)
    if link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then return "item", id end
    end
    return nil
end

local function entryInfo(e)
    if e.kind == "spell" then
        local name, _, icon = GetSpellInfo(e.id)
        return name, icon
    else
        local name = GetItemInfo(e.id)
        local icon = GetItemIcon and GetItemIcon(e.id)
        return name, icon
    end
end

local function entryCooldown(e)
    if e.kind == "spell" then
        return spellCooldown(e.id)
    else
        return getItemCooldown(e.id)
    end
end

local function alreadyHas(kind, id)
    for _, e in ipairs(db().entries) do
        if e.kind == kind and e.id == id then return true end
    end
    return false
end

local relayout  -- forward
local function addEntry(input)
    local kind, id = resolveInput(input)
    if not kind then
        ns:Print(L["Cooldown Manager: '%s' is not a known spell or item."], tostring(input))
        return false
    end
    if alreadyHas(kind, id) then
        ns:Print(L["Cooldown Manager: already tracking that."])
        return false
    end
    db().entries[#db().entries + 1] = { kind = kind, id = id }
    relayout()
    local name = entryInfo(db().entries[#db().entries])
    ns:Print(L["Cooldown Manager: added %s."], name or ("#" .. id))
    return true
end

local function removeEntryAt(index)
    table.remove(db().entries, index)
    relayout()
end

-- =========================================================
-- Icons
-- =========================================================
local function makeIcon(i)
    local f = CreateFrame("Frame", "VCUI_CDM_Icon" .. i, bar)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints(f)
    f.border:SetColorTexture(0, 0, 0, 1)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.tex)
    f.cd:SetDrawEdge(true)
    -- Suppress the Cooldown widget's OWN countdown numbers every which way
    -- (the method is missing on some 2.5.5 builds) so they can't double up
    -- with ours and read as a blur.
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.cd.noCooldownCount = true   -- OmniCC opt-out

    -- The countdown number sits on its OWN frame ABOVE the cooldown frame.
    -- Otherwise the cooldown (a child frame) draws over our text and the
    -- translucent sweep bleeds through it -> the number looks washed out.
    f.textHost = CreateFrame("Frame", nil, f)
    f.textHost:SetAllPoints(f)
    f.textHost:SetFrameLevel(f.cd:GetFrameLevel() + 5)

    f.text = f.textHost:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(FONT, 16, "OUTLINE")
    f.text:SetPoint("CENTER", f.textHost, "CENTER", 0, 0)
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(1, -1)

    f.flash = f.textHost:CreateTexture(nil, "OVERLAY")
    f.flash:SetTexture("Interface\\Cooldown\\star4")
    f.flash:SetBlendMode("ADD")
    f.flash:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.flash:Hide()

    return f
end

-- (re)build the visible icon list and position it per the layout settings
relayout = function()
    if not bar then return end
    local d = db()
    local size, pad = d.iconSize, d.spacing
    local entries = d.entries

    for i, e in ipairs(entries) do
        local f = icons[i]
        if not f then f = makeIcon(i); icons[i] = f end
        local name, icon = entryInfo(e)
        f.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.text:SetFont(FONT, math.max(8, math.floor(size * 0.4)), "OUTLINE")
        f.entry = e
        f.prevRemain = 0
        f.flashT = nil
        f:SetSize(size, size)
        f:Show()
    end
    for i = #entries + 1, #icons do icons[i]:Hide() end

    -- Grid placement: lay everything out in a positive box anchored TOPLEFT,
    -- then flip cell order for LEFT/UP so the bar grows the chosen way while
    -- staying inside the mover bounds.
    local count  = #entries
    local perRow = math.max(1, d.perRow)
    local horiz  = (d.growth == "RIGHT" or d.growth == "LEFT")
    local posN   = math.min(math.max(count, 1), perRow)     -- icons along a line
    local lineN  = math.max(1, math.ceil(math.max(count, 1) / perRow))
    local totalCols = horiz and posN or lineN
    local totalRows = horiz and lineN or posN

    local step = size + pad
    for i = 1, count do
        local idx  = i - 1
        local line = math.floor(idx / perRow)
        local pos  = idx % perRow
        local col  = horiz and pos or line
        local rowi = horiz and line or pos
        if d.growth == "LEFT" then col  = (totalCols - 1) - col end
        if d.growth == "UP"   then rowi = (totalRows - 1) - rowi end
        local f = icons[i]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bar, "TOPLEFT", col * step, -rowi * step)
    end

    bar:SetSize(totalCols * size + (totalCols - 1) * pad,
                totalRows * size + (totalRows - 1) * pad)
end

local function updateIcon(f, now)
    local e = f.entry
    if not e then return end
    local start, duration, enabled = entryCooldown(e)
    local onCD = enabled ~= 0 and duration and duration > GCD_MAX
        and start and (start + duration - now) > 0

    if onCD then
        local remain = start + duration - now
        f.cd:SetCooldown(start, duration)
        if db().showText then
            if remain >= 60 then
                f.text:SetText(math.floor(remain / 60 + 0.5) .. "m")
            elseif remain >= 10 then
                f.text:SetText(string.format("%d", remain))
            else
                f.text:SetText(string.format("%.1f", remain))
            end
            f.text:SetTextColor(remain <= 3 and 1 or 1, remain <= 3 and 0.4 or 1, remain <= 3 and 0.4 or 1)
            f.text:Show()
        else
            f.text:Hide()
        end
        if db().desaturate then f.tex:SetDesaturated(true); f.tex:SetVertexColor(0.6, 0.6, 0.6)
        else f.tex:SetDesaturated(false); f.tex:SetVertexColor(1, 1, 1) end
        f.prevRemain = remain
        if db().onlyOnCooldown then f:Show() end
    else
        f.cd:Clear()
        f.text:Hide()
        f.tex:SetDesaturated(false)
        f.tex:SetVertexColor(1, 1, 1)
        -- ready flash: just transitioned from on-CD to ready
        if db().readyFlash and (f.prevRemain or 0) > 0 then
            f.flashT = 0
            f.flash:SetAlpha(0.9)
            f.flash:Show()
        end
        f.prevRemain = 0
        if db().onlyOnCooldown then f:Hide() end
    end

    -- advance an active ready flash (scale up + fade over ~0.45s)
    if f.flashT then
        f.flashT = f.flashT + 0.1
        local p = f.flashT / 0.45
        if p >= 1 then
            f.flash:Hide(); f.flashT = nil
        else
            local s = f:GetWidth() * (1.6 + p * 0.6)
            f.flash:SetSize(s, s)
            f.flash:SetAlpha(0.9 * (1 - p))
        end
    end
end

local function refreshAll()
    if not mod._enabled or not bar then return end
    local now = GetTime()
    local n = #db().entries
    for i = 1, n do
        local f = icons[i]
        if f and f:IsShown() or (f and db().onlyOnCooldown) then
            updateIcon(f, now)
        end
    end
end

local function onUpdate(_, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.1 then return end
    throttle = 0
    if #db().entries == 0 then return end
    refreshAll()
end

-- =========================================================
-- Frame / mover / drag-to-add
-- =========================================================
local function onReceiveDrag()
    if not mod._enabled then return end
    local ctype, a, b = GetCursorInfo()
    if ctype == "spell" then
        -- Classic: ("spell", bookIndex, bookType[, spellID]); try to get an ID
        local id = select(4, GetCursorInfo())
        if not id and b and GetSpellBookItemInfo then
            id = select(2, GetSpellBookItemInfo(a, b))
        end
        if id then addEntry(tostring(id)) end
    elseif ctype == "item" then
        if a then addEntry(tostring(a)) end
    end
    ClearCursor()
end

local function buildBar()
    if bar then return bar end
    local d = db()

    bar = CreateFrame("Frame", "VCUI_CooldownManager", UIParent)
    bar:SetSize(d.iconSize, d.iconSize)
    bar:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    bar:SetFrameStrata("MEDIUM")
    bar:SetScript("OnReceiveDrag", onReceiveDrag)

    bar.mover = ns:CreateMover(bar, {
        label  = L["|cffffffffCOOLDOWNS|r"],
        db     = d,
        width  = 160,
        height = 40,
        onMove = function(x, y)
            ns:Print(string.format(L["Cooldowns: x=%.0f, y=%.0f"], x, y))
        end,
    })

    bar:SetScript("OnUpdate", onUpdate)
    return bar
end

local function setUnlocked(state)
    db().unlocked = state
    buildBar()
    -- Mouse on only while unlocked, so drag-to-add works without the bar
    -- blocking clicks during play.
    bar:EnableMouse(state)
    if state then
        bar.mover:Show()
        ns:Print(L["Cooldown Manager unlocked. Drag spells/items onto the bar to add. |cff9b6cffDrag|r the bar to move."])
    else
        bar.mover:Hide()
        ns:Print(L["Cooldown Manager locked."])
    end
end

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    buildBar()
    relayout()
    refreshAll()
    ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", refreshAll)
    ns:RegisterEvent("BAG_UPDATE_COOLDOWN",   refreshAll)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    ns:RegisterEvent("SPELLS_CHANGED",        relayout)
end

function mod:OnDisable()
    ns:UnregisterEvent("SPELL_UPDATE_COOLDOWN", refreshAll)
    ns:UnregisterEvent("BAG_UPDATE_COOLDOWN",   refreshAll)
    ns:UnregisterEvent("PLAYER_ENTERING_WORLD", refreshAll)
    ns:UnregisterEvent("SPELLS_CHANGED",        relayout)
    if bar then
        if bar.mover then bar.mover:Hide() end
        bar:Hide()
    end
end

-- =========================================================
-- Options
-- =========================================================
local addInput = ""

local function rebuildPage()
    if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("cooldownmanager") end
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Cooldown Manager"] },
        { type = "desc",
          text = L["|cffaaaaaaA row of icons showing the cooldowns of the spells and trinkets you add. Type a spell/item name or ID below, shift-click a spell from your spellbook into the box, or unlock the bar and drag spells/items onto it.|r"] },
        { type = "spacer", height = 6 },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "editbox", label = L["Add (name / ID)"], width = 280, editWidth = 190,
              get = function() return addInput end,
              set = function(_, v) addInput = tostring(v or "") end },
            { type = "button", label = L["Add"], width = 80, primary = true,
              onClick = function()
                  local txt = addInput:gsub("^%s+", ""):gsub("%s+$", "")
                  if txt ~= "" and addEntry(txt) then addInput = ""; rebuildPage() end
              end },
        } },
        { type = "spacer", height = 4 },
    }

    -- Current entries
    items[#items + 1] = { type = "header", text = L["Tracked"] }
    if #mod.db.entries == 0 then
        items[#items + 1] = { type = "desc", text = L["|cff888888Nothing tracked yet.|r"] }
    else
        for i, e in ipairs(mod.db.entries) do
            local name = (entryInfo(e)) or ("#" .. e.id)
            local kindTag = e.kind == "item" and L["  |cff888888(item)|r"] or ""
            items[#items + 1] = { type = "group", layout = "row", gap = 6, items = {
                { type = "button", label = "X", width = 28,
                  onClick = function() removeEntryAt(i); rebuildPage() end },
                { type = "button", label = L["Up"], width = 44,
                  onClick = function()
                      if i > 1 then
                          mod.db.entries[i], mod.db.entries[i-1] = mod.db.entries[i-1], mod.db.entries[i]
                          relayout(); rebuildPage()
                      end
                  end },
                { type = "desc", text = name .. kindTag, width = 220 },
            } }
        end
    end

    items[#items + 1] = { type = "spacer", height = 8 }
    items[#items + 1] = { type = "header", text = L["Layout"] }
    items[#items + 1] = { type = "slider", label = L["Icon size"], min = 20, max = 64, step = 1,
        get = function() return mod.db.iconSize end,
        set = function(_, v) mod.db.iconSize = v; relayout() end }
    items[#items + 1] = { type = "slider", label = L["Spacing"], min = 0, max = 16, step = 1,
        get = function() return mod.db.spacing end,
        set = function(_, v) mod.db.spacing = v; relayout() end }
    items[#items + 1] = { type = "slider", label = L["Icons per row"], min = 1, max = 20, step = 1,
        get = function() return mod.db.perRow end,
        set = function(_, v) mod.db.perRow = v; relayout() end }
    items[#items + 1] = { type = "dropdown", label = L["Growth direction"], width = 220,
        values = {
            { value = "RIGHT", text = L["Right"] },
            { value = "LEFT",  text = L["Left"]  },
            { value = "DOWN",  text = L["Down"]  },
            { value = "UP",    text = L["Up"]    },
        },
        get = function() return mod.db.growth end,
        set = function(_, v) mod.db.growth = v; relayout() end }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "header", text = L["Display"] }
    items[#items + 1] = { type = "toggle", label = L["Only show while on cooldown"],
        tooltip = L["Hides ready icons; they reappear when on cooldown."],
        get = function() return mod.db.onlyOnCooldown end,
        set = function(_, v) mod.db.onlyOnCooldown = v; relayout(); refreshAll() end }
    items[#items + 1] = { type = "toggle", label = L["Show countdown text"],
        get = function() return mod.db.showText end,
        set = function(_, v) mod.db.showText = v; refreshAll() end }
    items[#items + 1] = { type = "toggle", label = L["Dim icon while on cooldown"],
        get = function() return mod.db.desaturate end,
        set = function(_, v) mod.db.desaturate = v; refreshAll() end }
    items[#items + 1] = { type = "toggle", label = L["Flash when ready"],
        get = function() return mod.db.readyFlash end,
        set = function(_, v) mod.db.readyFlash = v end }

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = { type = "button", label = L["Unlock / Position"], width = 200,
        onClick = function() setUnlocked(not mod.db.unlocked) end }

    return items
end
