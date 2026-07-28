-- Wraps the embedded engine under Trinkets/*: hides its own options window and minimap icon.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("trinkets", {
    name        = "Trinkets",
    group       = "Bags & Items",
    description = "Two trinket slots on screen with cooldown display, dropdown selection and auto-queue.",
    defaults    = {
        enabled   = true,
        showFrame = true,
    },
})

local function getMainFrame()    return _G.Trinkets_MainFrame end
local function getIconFrame()    return _G.Trinkets_IconFrame end
local function getOptFrame()     return _G.Trinkets_OptFrame  end

local function setShown(state)
    local f = getMainFrame()
    if not f then return end
    -- Secure frame: Show/Hide from insecure code is blocked, so bail in combat and pcall otherwise.
    if InCombatLockdown and InCombatLockdown() then return end
    if state and f:IsShown() then return end
    if not state and not f:IsShown() then return end
    pcall(function()
        if state then f:Show() else f:Hide() end
    end)
end

local function rescaleMain()
    local f = getMainFrame()
    if f and TrinketsPerOptions and TrinketsPerOptions.MainScale then
        f:SetScale(TrinketsPerOptions.MainScale)
    end
end

-- HookScript keeps them hidden if the engine tries to show them again later.
local function suppressEngineUI()
    if _G.TrinketsOptions then
        _G.TrinketsOptions.ShowIcon = "OFF"
    end

    local mm = getIconFrame()
    if mm then
        mm:Hide()
        mm:EnableMouse(false)
        if not mm._vcui_suppressHooked then
            mm._vcui_suppressHooked = true
            mm:HookScript("OnShow", function(self) self:Hide() end)
        end
    end

    local opt = getOptFrame()
    if opt then
        opt:Hide()
        if not opt._vcui_suppressHooked then
            opt._vcui_suppressHooked = true
            opt:HookScript("OnShow", function(self) self:Hide() end)
        end
    end
end

function mod:OnEnable()
    -- Engine initializes on load, so this is deferred; setShown must never run
    -- inline here (secure frame), which is why it sits inside the timers.
    local function apply()
        suppressEngineUI()
        -- The engine persists its own visibility flag whenever the frame is
        -- hidden, so OnDisable below told it to stay hidden for good. Nothing
        -- ever put that back: re-enabling the module left the slots gone while
        -- "Show frame" still read as on, and only toggling that option twice
        -- brought them back. The player's own setting decides here.
        setShown(mod.db.showFrame ~= false)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, apply)
        C_Timer.After(2,   apply)
    else
        suppressEngineUI()
    end
end

function mod:OnDisable()
    setShown(false)
end

-- =========================================================================
-- Auto queue
--
-- The engine has a whole window for this -- order, delay, per-item flags,
-- profiles -- and it sits behind Trinkets_OptFrame, which suppressEngineUI
-- above hides on purpose. So the queue RAN (alt-click arms a slot, it swaps in
-- combat) while the order it swapped by could not be looked at, let alone
-- changed. That has been true since the window was vendored.
--
-- Rebuilt here out of our own controls rather than by un-hiding a 2006 window.
-- The data and every operation on it come from the engine unchanged:
--
--   TrinketsQueue.Enabled[which]  0 = top slot (13), 1 = bottom slot (14)
--   TrinketsQueue.Sort[which]     ordered item ids
--   TrinketsQueue.Stats[id]       { delay, priority, keep }
--
-- Nothing here writes a queue rule by hand; it moves entries in that list and
-- lets Trinkets.UpdateCombatQueue react, exactly as the old window did.
-- =========================================================================

local selected = { [0] = 1, [1] = 1 }   -- which row of each slot's list is picked

local function queueList(which)
    local q = _G.TrinketsQueue
    return (q and q.Sort and q.Sort[which]) or {}
end

-- Item id 0 is not an item. Trinkets.PopulateSort inserts it as a marker and
-- Trinkets.SortValidate treats it apart -- everything below it is off the queue.
-- Without this the row read "#0", and the per-entry settings underneath would
-- have been offered for something that cannot carry them.
local function isStopMarker(id)
    return id == 0 or id == "0"
end

local function queueName(id)
    if isStopMarker(id) then return L["— queue stops here —"] end
    if Trinkets and Trinkets.GetNameByID then
        local n = Trinkets.GetNameByID(id)
        if n and n ~= "" then return n end
    end
    local n = GetItemInfo(id or "")
    return n or ("#" .. tostring(id))
end

local function selectedId(which)
    return queueList(which)[selected[which]]
end

local function stats(which, create)
    local q, id = _G.TrinketsQueue, selectedId(which)
    if not (q and id) then return nil end
    q.Stats = q.Stats or {}
    if create then q.Stats[id] = q.Stats[id] or {} end
    return q.Stats[id]
end

local function rebuild()
    if ns.UI and ns.UI.RebuildCurrentPage then ns.UI:RebuildCurrentPage() end
end

-- Move the picked entry, keeping the selection ON it rather than on the
-- position -- otherwise pressing "up" twice moves two different trinkets.
local function move(which, delta)
    local list = queueList(which)
    local i = selected[which]
    local j = i + delta
    if not (list[i] and list[j]) then return end
    list[i], list[j] = list[j], list[i]
    selected[which] = j
    if Trinkets and Trinkets.UpdateCombatQueue then Trinkets.UpdateCombatQueue() end
    rebuild()
end

local function removeEntry(which)
    local list = queueList(which)
    if not list[selected[which]] then return end
    table.remove(list, selected[which])
    if selected[which] > #list then selected[which] = #list end
    if selected[which] < 1 then selected[which] = 1 end
    if Trinkets and Trinkets.UpdateCombatQueue then Trinkets.UpdateCombatQueue() end
    rebuild()
end

-- Trinkets in the bags that are not in this slot's list yet.
--
-- Two traps in Trinkets.BaggedTrinkets, both read out of the scan in
-- Trinkets.BuildMenu: it is filled by that scan and would otherwise be stale or
-- empty when this page is opened first, and it is never SHORTENED -- entries
-- past NumberOfTrinkets are leftovers from a fuller bag. So: rescan, then count
-- to that number rather than walking the table with ipairs.
local function addableValues(which)
    if Trinkets and Trinkets.BuildMenu and not InCombatLockdown() then
        pcall(Trinkets.BuildMenu)
    end
    local bagged = (Trinkets and Trinkets.BaggedTrinkets) or {}
    local n      = (Trinkets and Trinkets.NumberOfTrinkets) or 0

    local out, seen = {}, {}
    for _, id in ipairs(queueList(which)) do seen[tostring(id)] = true end
    for i = 1, n do
        local id = bagged[i] and bagged[i].id
        if id and not seen[tostring(id)] then
            seen[tostring(id)] = true
            out[#out + 1] = { value = tostring(id), text = bagged[i].name or queueName(id) }
        end
    end
    return out
end

-- What the picked entry can carry. nil when nothing is picked or when the pick
-- is the stop marker, and then no gear appears at all -- an empty expander is
-- worse than none.
local function entrySettings(which)
    local id = selectedId(which)
    if not id or isStopMarker(id) then return nil end
    return {
        { type = "slider", label = L["Swap delay"],
          min = 0, max = 60, step = 1,
          tooltip = L["Seconds this trinket stays equipped before the queue swaps it out again. 0 = no wait."],
          get = function() local s = stats(which); return (s and s.delay) or 0 end,
          set = function(_, v)
              local s = stats(which, true)
              if s then s.delay = (v ~= 0) and v or nil end
          end },
        { type = "checkbox", label = L["Priority"],
          tooltip = L["This trinket is swapped in ahead of the ones above it once it is ready."],
          get = function() local s = stats(which); return (s and s.priority) and true or false end,
          set = function(_, v) local s = stats(which, true); if s then s.priority = v or nil end end },
        { type = "checkbox", label = L["Pause while equipped"],
          tooltip = L["While this trinket is worn the queue holds still - for a trinket whose effect you do not want cut short."],
          get = function() local s = stats(which); return (s and s.keep) and true or false end,
          set = function(_, v) local s = stats(which, true); if s then s.keep = v or nil end end },
    }
end

local function queueSection(which, title)
    local list = queueList(which)

    local rows = {}
    for i, id in ipairs(list) do
        rows[i] = { value = i, text = string.format("%d. %s", i, queueName(id)) }
    end
    if #rows == 0 then
        rows[1] = { value = 1, text = L["- empty -"] }
    end
    if selected[which] > #list then selected[which] = math.max(1, #list) end

    local items = {
        { type = "toggle", label = L["Auto queue for this slot"],
          tooltip = L["Same switch as alt-clicking the slot. While on, the queue swaps this trinket in combat, following the order below."],
          get = function() return (_G.TrinketsQueue and _G.TrinketsQueue.Enabled[which]) and true or false end,
          set = function(_, v)
              local q = _G.TrinketsQueue
              if not q then return end
              q.Enabled[which] = v and 1 or nil
              if not v and Trinkets and Trinkets.CombatQueue then
                  Trinkets.CombatQueue[which] = nil
              end
              if Trinkets and Trinkets.UpdateCombatQueue then Trinkets.UpdateCombatQueue() end
          end },

        -- The picked entry's own settings hang off this row's gear rather than
        -- lying loose underneath it: they belong to whatever is selected here,
        -- and the gear says so. subKey because both slots have an "Order" row
        -- and the expansion state is keyed by label.
        { type = "dropdown", label = L["Order"], width = 260,
          subKey = "trinketOrder" .. which,
          tooltip = L["The queue works through this list from the top. Pick an entry to move it or to change its settings."],
          values = rows,
          subOptions = entrySettings(which),
          get = function() return selected[which] end,
          set = function(_, v) selected[which] = tonumber(v) or 1; rebuild() end },

        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Up"],     width = 90,
              onClick = function() move(which, -1) end },
            { type = "button", label = L["Down"],   width = 90,
              onClick = function() move(which,  1) end },
            { type = "button", label = L["Remove"], width = 90,
              onClick = function() removeEntry(which) end },
        } },
    }

    local addable = addableValues(which)
    if #addable > 0 then
        items[#items + 1] = { type = "dropdown", label = L["Add from bags"], width = 260,
            tooltip = L["Adds a trinket you are carrying to the end of this list."],
            values = addable,
            get = function() return "" end,
            set = function(_, v)
                if Trinkets and Trinkets.AddToSort then Trinkets.AddToSort(which, v) end
                rebuild()
            end }
    end

    return { type = "section", title = title, items = items }
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Trinkets"] },
        { type = "desc",
          text = L["|cffaaaaaaTwo trinket slots with cooldown, dropdown selection and auto-queue.|nLeft click = use, right click = dropdown.|r"] },

        { type = "toggle", label = L["Show frame"],
          tooltip = L["Hides or shows the two trinket slots. Auto-queue continues to run while hidden."],
          get = function() return mod.db.showFrame end,
          set = function(_, v)
              mod.db.showFrame = v
              setShown(v)
          end },

        { type = "toggle", label = L["Position locked"],
          tooltip = L["If on, the frame cannot be accidentally moved."],
          get = function()
              return _G.TrinketsOptions and _G.TrinketsOptions.Locked == "ON"
          end,
          set = function(_, v)
              if _G.TrinketsOptions then
                  _G.TrinketsOptions.Locked = v and "ON" or "OFF"
              end
          end },

        { type = "slider", label = L["Size"],
          min = 0.5, max = 2.0, step = 0.05,
          tooltip = L["Scales the trinket slots."],
          get = function()
              return (_G.TrinketsPerOptions and _G.TrinketsPerOptions.MainScale) or 1.0
          end,
          set = function(_, v)
              if _G.TrinketsPerOptions then
                  _G.TrinketsPerOptions.MainScale = v
              end
              rescaleMain()
          end },

        { type = "spacer", height = 4 },
        { type = "desc",
          text = L["|cffaaaaaaTip: left click a slot to use the trinket, right click for the list. Alt-click arms the auto queue for that slot.|r"] },

        -- Sections start closed, so the two queues cost two lines until opened.
        queueSection(0, L["Auto queue: top slot"]),
        queueSection(1, L["Auto queue: bottom slot"]),
    }
end
