-- Cross-client API shims (Classic Era 1.15.x + Anniversary 2.5.x); each installs ONLY when the legacy global is absent.
local _, ns = ...

-- Era removed the global bag functions and exposes only C_Container; BCC still has them.
local c = _G.C_Container
if c then
    -- same argument/return contract -> safe to alias 1:1
    GetContainerNumSlots     = GetContainerNumSlots     or c.GetContainerNumSlots
    GetContainerItemID       = GetContainerItemID       or c.GetContainerItemID
    GetContainerItemLink     = GetContainerItemLink     or c.GetContainerItemLink
    GetContainerNumFreeSlots = GetContainerNumFreeSlots or c.GetContainerNumFreeSlots
    GetContainerItemCooldown = GetContainerItemCooldown or c.GetContainerItemCooldown
    PickupContainerItem      = PickupContainerItem      or c.PickupContainerItem
    UseContainerItem         = UseContainerItem         or c.UseContainerItem
    SplitContainerItem       = SplitContainerItem       or c.SplitContainerItem

    -- contract CHANGED: C_Container returns one table, the old global a tuple.
    if not GetContainerItemInfo and c.GetContainerItemInfo then
        local getInfo = c.GetContainerItemInfo
        GetContainerItemInfo = function(bag, slot)
            local i = getInfo(bag, slot)
            if not i then return nil end
            return i.iconFileID, i.stackCount, i.isLocked, i.quality, i.isReadable,
                   i.hasLoot, i.hyperlink, i.isFiltered, i.hasNoValue, i.itemID, i.isBound
        end
    end
end

-- Everything below is either already removed on one of our flavors or survives only as a
-- Blizzard Deprecated_* wrapper gated by the loadDeprecationFallbacks CVar; legacy tuple
-- shapes mirror those wrappers. Test with: /console loadDeprecationFallbacks 0 + /reload.

-- combat log: the classic globals are ONLY Deprecated_* aliases of C_CombatLog now,
-- so a player who turns the CVar off loses the swing timer, cooldown pulse, combat
-- text, arena tracker, nameplate and mana modules at once with "attempt to call a
-- nil value" -- every one of them calls this on the combat-log event. Blizzard's own
-- combat log already calls C_CombatLog.GetCurrentEventInfo directly.
local ccl = _G.C_CombatLog
if ccl then
    CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo or ccl.GetCurrentEventInfo
end
-- The unit flags travel with the same wrapper. These fail SOFTLY (the callers mask
-- with `or 0`, so a nil constant silently matches nothing) -- which is worse than a
-- crash, because pet ability tracking would just quietly stop working.
local ecl = _G.Enum and _G.Enum.CombatLogObject
if ecl then
    COMBATLOG_OBJECT_AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or ecl.AffiliationMine
    COMBATLOG_OBJECT_TYPE_PLAYER      = COMBATLOG_OBJECT_TYPE_PLAYER      or ecl.TypePlayer
    COMBATLOG_OBJECT_TYPE_PET         = COMBATLOG_OBJECT_TYPE_PET         or ecl.TypePet
    COMBATLOG_OBJECT_CONTROL_PLAYER   = COMBATLOG_OBJECT_CONTROL_PLAYER   or ecl.ControlPlayer
end

-- addon management: removed on 2.5.5, wrapper-only on 1.15.x
local ca = _G.C_AddOns
if ca then
    IsAddOnLoaded     = IsAddOnLoaded     or ca.IsAddOnLoaded
    LoadAddOn         = LoadAddOn         or ca.LoadAddOn
    GetAddOnMetadata  = GetAddOnMetadata  or ca.GetAddOnMetadata
    GetNumAddOns      = GetNumAddOns      or ca.GetNumAddOns
    GetAddOnInfo      = GetAddOnInfo      or ca.GetAddOnInfo
    EnableAddOn       = EnableAddOn       or ca.EnableAddOn
    DisableAddOn      = DisableAddOn      or ca.DisableAddOn
    -- legacy signature is (character, name); the namespaced one is (name, character)
    if not GetAddOnEnableState and ca.GetAddOnEnableState then
        GetAddOnEnableState = function(character, name)
            return ca.GetAddOnEnableState(name, character)
        end
    end
end

-- mouse focus: removed on both flavors
if not GetMouseFocus and _G.GetMouseFoci then
    local foci = _G.GetMouseFoci
    GetMouseFocus = function()
        local f = foci()
        return f and f[1]
    end
end

-- auras: wrapper-only on both flavors, natives already gone
local cua = _G.C_UnitAuras
if cua and cua.GetAuraDataByIndex then
    -- legacy tuple order = AuraUtil.UnpackAuraData
    local function unpackAura(data)
        if not data then return nil end
        if _G.AuraUtil and _G.AuraUtil.UnpackAuraData then
            return _G.AuraUtil.UnpackAuraData(data)
        end
        return data.name, data.icon, data.applications, data.dispelName,
               data.duration, data.expirationTime, data.sourceUnit,
               data.isStealable, data.nameplateShowPersonal, data.spellId,
               data.canApplyAura, data.isBossAura, data.isFromPlayerOrPlayerPet,
               data.nameplateShowAll, data.timeMod,
               unpack(data.points or {})
    end
    if not UnitAura then
        UnitAura = function(unit, index, filter)
            return unpackAura(cua.GetAuraDataByIndex(unit, index, filter))
        end
    end
    -- dedicated getters COMBINE the implied flag with the caller filter (UnitDebuff(u,i,"RAID") = HARMFUL|RAID); a `filter or "HELPFUL"` default would return the wrong auras.
    if not UnitBuff and cua.GetBuffDataByIndex then
        UnitBuff = function(unit, index, filter)
            return unpackAura(cua.GetBuffDataByIndex(unit, index, filter))
        end
    end
    if not UnitDebuff and cua.GetDebuffDataByIndex then
        UnitDebuff = function(unit, index, filter)
            return unpackAura(cua.GetDebuffDataByIndex(unit, index, filter))
        end
    end
end

-- items: wrapper-only on both; C_Item keeps the legacy tuples 1:1
local ci = _G.C_Item
if ci then
    GetItemInfo              = GetItemInfo              or ci.GetItemInfo
    GetItemInfoInstant       = GetItemInfoInstant       or ci.GetItemInfoInstant
    GetItemQualityColor      = GetItemQualityColor      or ci.GetItemQualityColor
    GetDetailedItemLevelInfo = GetDetailedItemLevelInfo or ci.GetDetailedItemLevelInfo
    GetItemCount             = GetItemCount             or ci.GetItemCount
    GetItemFamily            = GetItemFamily            or ci.GetItemFamily
    GetItemSpell             = GetItemSpell             or ci.GetItemSpell
    IsUsableItem             = IsUsableItem             or ci.IsUsableItem
    IsEquippableItem         = IsEquippableItem         or ci.IsEquippableItem
    GetItemIcon              = GetItemIcon              or ci.GetItemIconByID   -- renamed upstream
end

-- spells: still native on both, but C_Spell exists = next in line for removal
local cs = _G.C_Spell
if cs then
    if not GetSpellInfo and cs.GetSpellInfo then
        GetSpellInfo = function(spell)
            local si = cs.GetSpellInfo(spell)
            if not si then return nil end
            -- legacy slot 2 was rank text, which now lives in GetSpellSubtext
            return si.name, nil, si.iconID, si.castTime, si.minRange,
                   si.maxRange, si.spellID, si.originalIconID
        end
    end
    if not GetSpellTexture and cs.GetSpellTexture then
        GetSpellTexture = cs.GetSpellTexture
    end
    if not GetSpellLink and cs.GetSpellLink then
        GetSpellLink = cs.GetSpellLink
    end
    if not GetSpellCooldown and cs.GetSpellCooldown then
        GetSpellCooldown = function(spell)
            local sc = cs.GetSpellCooldown(spell)
            if not sc then return nil end
            -- legacy returned enabled as 1|0, the struct carries a boolean
            return sc.startTime, sc.duration, sc.isEnabled and 1 or 0, sc.modRate
        end
    end
end

-- chat: wrapper-only; ChatFrameUtil is the modern home
if not SendChatMessage and _G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage then
    SendChatMessage = _G.C_ChatInfo.SendChatMessage
end
local cfu = _G.ChatFrameUtil
if cfu then
    ChatFrame_AddMessageEventFilter    = ChatFrame_AddMessageEventFilter
        or cfu.AddMessageEventFilter
    ChatFrame_RemoveMessageEventFilter = ChatFrame_RemoveMessageEventFilter
        or cfu.RemoveMessageEventFilter
end

-- reputation: unlike deprecated globals gated by the fallback CVar, this one
-- is absent on Anniversary; C_Reputation is the only data source.
local cr = _G.C_Reputation
if not GetWatchedFactionInfo and cr and cr.GetWatchedFactionData then
    GetWatchedFactionInfo = function()
        local d = cr.GetWatchedFactionData()
        if not d then return nil end
        return d.name, d.reaction, d.currentReactionThreshold,
               d.nextReactionThreshold, d.currentStanding
    end
end

-- currency: the namespaced helper retains the legacy signature 1:1.
if not GetCoinTextureString and C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
    GetCoinTextureString = GetCoinTextureString or C_CurrencyInfo.GetCoinTextureString
end
