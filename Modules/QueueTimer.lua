-- =========================================================
-- VuloClassicUI / Modules / QueueTimer
-- Ehemals: BetterBlizzQueue (Classic-Variante)
-- Zeigt einen Countdown auf dem PvP/PvE Queue-Pop-Dialog.
-- =========================================================
local _, ns = ...

local mod = ns:RegisterModule("queuetimer", {
    name        = "Queue Timer",
    group       = "QoL",
    description = "Zeigt einen Countdown auf dem PvP/PvE Queue-Pop Dialog. Optional Sound-Warnung bei 5 Sekunden.",
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
local pveQueuePopTime  -- nur in memory; alte SV-Pop-Time wird nicht migriert

-- =========================================================
-- Helpers
-- =========================================================
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
    dialog.customLabel:SetText("Queue expires in")
    local f, _, fl = dialog.customLabel:GetFont(); dialog.customLabel:SetFont(f, 15, "OUTLINE")
    dialog.customLabel:SetWidth(maxWidth)

    dialog.timerLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.timerLabel:SetPoint("TOP", dialog.customLabel, "BOTTOM", 0, -44)
    f, _, fl = dialog.timerLabel:GetFont(); dialog.timerLabel:SetFont(f, 24, "OUTLINE")
    dialog.timerLabel:SetWidth(maxWidth)

    dialog.bgLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.bgLabel:SetPoint("TOP", dialog.timerLabel, "BOTTOM", 0, -4)
    f, _, fl = dialog.bgLabel:GetFont(); dialog.bgLabel:SetFont(f, 15, "OUTLINE")
    dialog.bgLabel:SetWidth(maxWidth)

    dialog.statusTextLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.statusTextLabel:SetPoint("TOP", dialog.bgLabel, "BOTTOM", 0, -3)
    f, _, fl = dialog.statusTextLabel:GetFont(); dialog.statusTextLabel:SetFont(f, 11, "OUTLINE")
    dialog.statusTextLabel:SetWidth(maxWidth)

    dialog.queueTimerLabels = true
end

local function setExpiresText(timeRemaining, dialog, pvp)
    local secs = timeRemaining > 0 and timeRemaining or 1
    local color = secs > 20 and "20ff20" or secs > 10 and "ffff00" or "ff0000"
    local timerText = format("|cff%s%s|r", color, SecondsToTime(secs))

    createCustomFontStrings(dialog)
    if dialog.instanceInfo then
        dialog.customLabel:SetPoint("TOP", dialog.label, "TOP", 0, 0)
        dialog.instanceInfo:SetAlpha(0)
        dialog.label:SetText("")
        dialog.timerLabel:SetText(timerText)
        if dialog.instanceInfo.name and (dialog.instanceInfo:IsShown() or pvp) then
            dialog.bgLabel:SetText(dialog.instanceInfo.name:GetText())
            dialog.statusTextLabel:SetText(dialog.instanceInfo.statusText:GetText())
        else
            dialog.bgLabel:SetText("")
            dialog.statusTextLabel:SetText("")
        end
    else
        dialog.customLabel:SetPoint("TOP", dialog.text, "TOP", 0, 0)
        dialog.text:SetText("")
        dialog.timerLabel:SetText(timerText)
    end
end

local function onUpdate(elapsed)
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
    elseif proposalTimeLeft then
        proposalTimeLeft = proposalTimeLeft - elapsed
        if mod.db.queueTimerWarning then
            if proposalTimeLeft <= 6 and not soundPlayed then
                PlaySoundFile(567458, "master")
                C_Timer.After(0.1, function() PlaySoundFile(567458, "master") end)
                C_Timer.After(0.2, function() PlaySoundFile(567458, "master") end)
                soundPlayed = true
            end
        end
        if proposalTimeLeft <= 0 then proposalTimeLeft = 40 end
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
    DEFAULT_CHAT_FRAME:AddMessage("|cff00c0ffQueueTimer:|r " .. message)
    if mod.db.queueTimerAudio then PlaySoundFile(567458, "master") end
end

local function captureDungeonQueuedTime()
    local hasData, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, queuedTime = GetLFGQueueStats(LE_LFG_CATEGORY_LFD)
    if hasData and queuedTime > 0 then dungeonQueuedTime = queuedTime end
end

local function handleDungeonReadyDialog()
    local proposalExists, _, _, _, _, _, _, hasResponded = GetLFGProposal()
    if proposalExists and not hasResponded then
        if not pveQueuePopTime then
            proposalTimeLeft = 40
        else
            local timeElapsed = GetTime() - pveQueuePopTime
            proposalTimeLeft = proposalTimeLeft - timeElapsed
            if proposalTimeLeft < 0 or proposalTimeLeft > 40 then proposalTimeLeft = 40 end
        end

        setExpiresText(proposalTimeLeft, LFGDungeonReadyDialog)
        isPveQueueActive = true
        startUpdateFrame()
        pveQueuePopTime = GetTime()

        if dungeonQueuedTime then
            local timeWaited = GetTime() - dungeonQueuedTime
            printMsg(timeWaited < 1 and "Dungeon queue popped instantly!" or format("Dungeon queue popped after %s", SecondsToTime(timeWaited)))
        else
            printMsg("Dungeon queue popped.")
        end
        dungeonQueuedTime = nil
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
                printMsg(secs < 1 and "Queue popped instantly!" or format("Queue popped after %s", SecondsToTime(secs)))
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

-- =========================================================
-- Hooks (einmalig)
-- =========================================================
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

-- =========================================================
-- Lifecycle
-- =========================================================
function mod:OnEnable()
    installHooks()

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

-- =========================================================
-- Options
-- =========================================================
function mod:GetOptions()
    return {
        { type = "header", text = "Sound" },
        {
            type = "checkbox", label = "Sound bei Queue-Pop",
            tooltip = "Spielt einen Sound ab, sobald die Queue gepoppt ist.",
            get = function() return mod.db.queueTimerAudio end,
            set = function(_, v) mod.db.queueTimerAudio = v end,
        },
        {
            type = "checkbox", label = "5-Sekunden-Warnung",
            tooltip = "Spielt 3 schnelle Sounds, wenn nur noch 5 Sekunden zum Annehmen bleiben.",
            get = function() return mod.db.queueTimerWarning end,
            set = function(_, v) mod.db.queueTimerWarning = v end,
        },
        { type = "spacer" },
        { type = "header", text = "Sonstiges" },
        {
            type = "checkbox", label = "Andere Timer (z.B. BigWigs) verstecken",
            tooltip = "Versteckt fremde StatusBars auf dem LFG-Ready-Popup, damit nur unser Timer sichtbar ist.",
            get = function() return mod.db.hideOtherTimers end,
            set = function(_, v) mod.db.hideOtherTimers = v end,
        },
    }
end
