-- =========================================================
-- VuloClassicUI / Modules / FixBindSocket
-- The Anniversary client (2.5.5) ships Blizzard_ItemSocketingUI without the
-- StaticPopup dialog "BIND_SOCKET". Socketing a gem that would bind the item
-- then calls StaticPopup_Show("BIND_SOCKET"), which errors with
--   "Dialog BIND_SOCKET does not exist."
-- and the socketing aborts. We re-add the dialog (identical to Blizzard's own
-- FrameXML definition) so the confirmation works and the gem goes in.
-- =========================================================
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("fixbindsocket", {
    name        = "Bind-on-Socket Fix",
    group       = "Bugfixes",
    description = "Re-adds the missing BIND_SOCKET confirmation dialog so socketing a gem that binds the item no longer throws a Lua error (Anniversary client).",
    defaults = { enabled = true },
})

local function installFix()
    local dialogs = _G.StaticPopupDialogs
    if not dialogs or dialogs["BIND_SOCKET"] then return end  -- already there -> leave it
    dialogs["BIND_SOCKET"] = {
        text         = _G.BIND_SOCKET or L["Socketing this gem will bind the item to you. Continue?"],
        button1      = _G.ACCEPT or "Accept",
        button2      = _G.CANCEL or "Cancel",
        OnAccept     = function() if _G.AcceptSockets then _G.AcceptSockets() end end,
        timeout      = 0,
        whileDead    = 1,
        hideOnEscape = 1,
        showAlert    = 1,
    }
end

function mod:OnEnable()
    -- StaticPopupDialogs exists at login; define right away.
    installFix()
end

function mod:GetOptions()
    local defined = _G.StaticPopupDialogs and _G.StaticPopupDialogs["BIND_SOCKET"] ~= nil
    return {
        { type = "header", text = L["Bind-on-Socket Fix"] },
        { type = "desc", text = L["The Anniversary client is missing the |cffffffffBIND_SOCKET|r confirmation dialog. Socketing a gem that would bind the item then throws \"Dialog BIND_SOCKET does not exist\" and aborts. This re-adds the dialog so socketing works."] },
        { type = "spacer", height = 6 },
        { type = "desc", text = string.format(L["|cffaaaaaaStatus: %s|r"],
            defined and L["|cff66ff66Dialog defined|r"] or L["not defined yet"]) },
    }
end
