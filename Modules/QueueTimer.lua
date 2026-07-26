-- QueueTimer: shows a countdown on the PvP/PvE queue pop dialog.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("queuetimer", {
    name        = "Queue Timer",
    group       = "QoL",
    description = "Shows a countdown on the PvP/PvE queue pop dialog. Optional sound warning at 5 seconds.",
    defaults = {
        queueTimerAudio   = true,
        queueTimerWarning = true,
        hideOtherTimers   = true,
    },
})

local bgId
local updateFrame
local proposalTimeLeft = 40
local queues = {}
local dungeonQueuedTime
local soundPlayed
local isPveQueueActive
local pveQueuePopTime  -- only in memory; old SV pop time is not migrated

local function stopUpdateFrame()
    if updateFrame then
        updateFrame:Hide()
        soundPlayed = false
    end
end

local function createCustomFontStrings(dialog)
    if dialog.queueTimerLabels then return end
    local maxWidth = dialog:GetWidth()

    dialog.customLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.customLabel:SetPoint("TOP", dialog.label or dialog.text, "TOP", 0, 0)
    dialog.customLabel:SetText(L["Queue expires in"])
    local f = dialog.customLabel:GetFont(); dialog.customLabel:SetFont(f, 15, "OUTLINE")
    dialog.customLabel:SetWidth(maxWidth)

    dialog.timerLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.timerLabel:SetPoint("TOP", dialog.customLabel, "BOTTOM", 0, -44)
    f = dialog.timerLabel:GetFont(); dialog.timerLabel:SetFont(f, 24, "OUTLINE")
    dialog.timerLabel:SetWidth(maxWidth)

    dialog.bgLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.bgLabel:SetPoint("TOP", dialog.timerLabel, "BOTTOM", 0, -4)
    f = dialog.bgLabel:GetFont(); dialog.bgLabel:SetFont(f, 15, "OUTLINE")
    dialog.bgLabel:SetWidth(maxWidth)

    dialog.statusTextLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.statusTextLabel:SetPoint("TOP", dialog.bgLabel, "BOTTOM", 0, -3)
    f = dialog.statusTextLabel:GetFont(); dialog.statusTextLabel:SetFont(f, 11, "OUTLINE")
    dialog.statusTextLabel:SetWidth(maxWidth)

    dialog.queueTimerLabels = true
end

local function setExpiresText(timeRemaining, dialog, pvp)
    local secs = timeRemaining > 0 and timeRemaining or 1
    local color = secs > 20 and "20ff20" or secs > 10 and "ffff00" or "ff0000"
    local timerText = format("|cff%s%s|r", color, SecondsToTime(secs))

    -- Battleground / arena name. Reliable in TBC via GetBattlefieldStatus;
    -- the dialog's own instanceInfo.name is empty on the Anniversary client.
    local bgName = ""
    if pvp and bgId and GetBattlefieldStatus then
        local _, mapName = GetBattlefieldStatus(bgId)
        bgName = mapName or ""
    end

    createCustomFontStrings(dialog)
    if dialog.instanceInfo then
        dialog.customLabel:SetPoint("TOP", dialog.label, "TOP", 0, 0)
        dialog.instanceInfo:SetAlpha(0)
        dialog.label:SetText("")
        dialog.timerLabel:SetText(timerText)
        if bgName == "" and dialog.instanceInfo.name and (dialog.instanceInfo:IsShown() or pvp) then
            bgName = dialog.instanceInfo.name:GetText() or ""
        end
        dialog.bgLabel:SetText(bgName)
        -- statusText sub-region isn't present on every dialog variant — guard it
        local st = dialog.instanceInfo.statusText
        dialog.statusTextLabel:SetText((st and st:GetText()) or "")
    else
        dialog.customLabel:SetPoint("TOP", dialog.text, "TOP", 0, 0)
        dialog.text:SetText("")
        dialog.timerLabel:SetText(timerText)
        dialog.bgLabel:SetText(bgName)
        dialog.statusTextLabel:SetText("")
    end
end

local function onUpdate(elapsed)
    if not mod._enabled then
        stopUpdateFrame()
        return
    end
    if bgId then
        updateFrame.timer = updateFrame.timer - elapsed
        if mod.db.queueTimerWarning then
            if GetBattlefieldPortExpiration(bgId) == 6 and not soundPlayed then
                PlaySoundFile(567458, "master")
                C_Timer.After(0.1, function() PlaySoundFile(567458, "master") end)
                C_Timer.After(0.2, function() PlaySoundFile(567458, "master") end)
                soundPlayed = true
            end
        end
        if updateFrame.timer <= 0 then
            if GetBattlefieldStatus(bgId) ~= "confirm" then
                stopUpdateFrame()
                return
            end
            setExpiresText(GetBattlefieldPortExpiration(bgId), PVPReadyDialog, true)
            updateFrame.timer = 1
        end
    elseif proposalTimeLeft and pveQueuePopTime then
        -- derive from the fixed start time instead of decrementing per frame
        proposalTimeLeft = 40 - (GetTime() - pveQueuePopTime)
        if mod.db.queueTimerWarning then
            if proposalTimeLeft <= 6 and not soundPlayed then
                PlaySoundFile(567458, "master")
                C_Timer.After(0.1, function() PlaySoundFile(567458, "master") end)
                C_Timer.After(0.2, function() PlaySoundFile(567458, "master") end)
                soundPlayed = true
            end
        end
        if proposalTimeLeft <= 0 then
            -- window elapsed: restart the display loop from now
            pveQueuePopTime = GetTime()
            proposalTimeLeft = 40
        end
        setExpiresText(proposalTimeLeft, LFGDungeonReadyDialog)
    end
end

local function startUpdateFrame()
    if not updateFrame then
        updateFrame = CreateFrame("Frame")
        updateFrame.timer = 1
        updateFrame:SetScript("OnUpdate", function(_, elapsed) onUpdate(elapsed) end)
    end
    updateFrame:Show()
end

local function printMsg(message)
    DEFAULT_CHAT_FRAME:AddMessage(L["|cff00c0ffQueueTimer:|r "] .. message)
    if mod.db.queueTimerAudio then PlaySoundFile(567458, "master") end
end

local function captureDungeonQueuedTime()
    local hasData, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, queuedTime = GetLFGQueueStats(LE_LFG_CATEGORY_LFD)
    if hasData and queuedTime > 0 then dungeonQueuedTime = queuedTime end
end

local function handleDungeonReadyDialog()
    local proposalExists, _, _, _, _, _, _, hasResponded = GetLFGProposal()
    if proposalExists and not hasResponded then
        -- pveQueuePopTime is the single fixed start time; remaining time is
        -- DERIVED from it (onUpdate reads the same source), so a re-fired
        -- LFG_PROPOSAL_SHOW no longer subtracts the elapsed window a 2nd time.
        local firstShow = not pveQueuePopTime
        if firstShow then pveQueuePopTime = GetTime() end

        proposalTimeLeft = 40 - (GetTime() - pveQueuePopTime)
        if proposalTimeLeft < 0 then proposalTimeLeft = 0 end
        setExpiresText(proposalTimeLeft, LFGDungeonReadyDialog)
        isPveQueueActive = true
        startUpdateFrame()

        if firstShow then
            if dungeonQueuedTime then
                local timeWaited = GetTime() - dungeonQueuedTime
                printMsg(timeWaited < 1 and L["Dungeon queue popped instantly!"] or format(L["Dungeon queue popped after %s"], SecondsToTime(timeWaited)))
            else
                printMsg(L["Dungeon queue popped."])
            end
            dungeonQueuedTime = nil
        end
    end
end

local function updateBattlefieldStatus()
    local isConfirm
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status == "queued" then
            queues[i] = queues[i] or GetTime() - (GetBattlefieldTimeWaited(i) / 1000)
        elseif status == "confirm" then
            if queues[i] then
                local secs = GetTime() - queues[i]
                printMsg(secs < 1 and L["Queue popped instantly!"] or format(L["Queue popped after %s"], SecondsToTime(secs)))
                queues[i] = nil
            end
            isConfirm = true
        else
            queues[i] = nil
        end
    end
    if not isConfirm and not isPveQueueActive then
        bgId = nil
        stopUpdateFrame()
    end
end

local function hideOtherTimers()
    if not mod.db.hideOtherTimers then return end
    if not LFGDungeonReadyPopup then return end
    local children = { LFGDungeonReadyPopup:GetChildren() }
    for _, child in ipairs(children) do
        if child:GetObjectType() == "StatusBar" then child:Hide() end
    end
end

local hooksInstalled = false
local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    if PVPReadyDialog_Display and hooksecurefunc then
        hooksecurefunc("PVPReadyDialog_Display", function(_, i)
            if not mod._enabled then return end
            bgId = i
            startUpdateFrame()
            setExpiresText(GetBattlefieldPortExpiration(bgId), PVPReadyDialog, true)
        end)
    end
end

-- Register events only once. Re-enabling the module must not add a second set
-- of handlers (that would fire queue pops / sounds twice). The handlers below
-- all gate on mod._enabled, so disabling them is handled by the flag alone.
local eventsRegistered = false

function mod:OnEnable()
    installHooks()

    if eventsRegistered then return end
    eventsRegistered = true

    ns:RegisterEvent("LFG_PROPOSAL_SHOW",      function()
        if not mod._enabled then return end
        handleDungeonReadyDialog(); hideOtherTimers()
    end)
    local function endProposal()
        if not mod._enabled then return end
        isPveQueueActive = false
        stopUpdateFrame()
        hideOtherTimers()
        pveQueuePopTime = nil
        proposalTimeLeft = 40
    end
    ns:RegisterEvent("LFG_PROPOSAL_SUCCEEDED", endProposal)
    ns:RegisterEvent("LFG_PROPOSAL_FAILED",    endProposal)
    ns:RegisterEvent("LFG_PROPOSAL_DONE",      endProposal)

    ns:RegisterEvent("LFG_QUEUE_STATUS_UPDATE", function()
        if not mod._enabled then return end
        captureDungeonQueuedTime()
    end)
    ns:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", function()
        if not mod._enabled then return end
        updateBattlefieldStatus()
    end)
end

-- The labels live on Blizzard's dialogs and would show stale text on the next
-- queue pop with the module off; instanceInfo was alpha-hidden by us.
-- Known gap: Blizzard's own label text (blanked by setExpiresText) cannot be
-- reconstructed here, so a dialog that is showing RIGHT NOW stays textless
-- until this pop expires; the next pop repaints it.
local function clearCustomLabels(dialog)
    if dialog and dialog.queueTimerLabels then
        dialog.customLabel:SetText("")
        dialog.timerLabel:SetText("")
        dialog.bgLabel:SetText("")
        dialog.statusTextLabel:SetText("")
        if dialog.instanceInfo then dialog.instanceInfo:SetAlpha(1) end
    end
end

function mod:OnDisable()
    bgId = nil
    isPveQueueActive = false
    pveQueuePopTime = nil
    proposalTimeLeft = 40
    stopUpdateFrame()
    clearCustomLabels(PVPReadyDialog)
    clearCustomLabels(LFGDungeonReadyDialog)
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Sound"] },
        {
            type = "checkbox", label = L["Sound on queue pop"],
            tooltip = L["Plays a sound as soon as the queue pops."],
            get = function() return mod.db.queueTimerAudio end,
            set = function(_, v) mod.db.queueTimerAudio = v end,
        },
        {
            type = "checkbox", label = L["5-second warning"],
            tooltip = L["Plays 3 quick sounds when only 5 seconds remain to accept."],
            get = function() return mod.db.queueTimerWarning end,
            set = function(_, v) mod.db.queueTimerWarning = v end,
        },
        { type = "spacer" },
        { type = "header", text = L["Misc"] },
        {
            type = "checkbox", label = L["Hide other timers (e.g. BigWigs)"],
            tooltip = L["Hides foreign StatusBars on the LFG ready popup so only our timer is visible."],
            get = function() return mod.db.hideOtherTimers end,
            set = function(_, v) mod.db.hideOtherTimers = v end,
        },
    }
end
