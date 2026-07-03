-- =========================================================
-- VuloClassicUI / Core / Compat
-- Cross-client API shims so the same module code runs on every flavor we ship
-- for (Classic Era 1.15.x and BCC/Anniversary 2.5.x).
--
-- Classic Era removed the global bag functions (GetContainerItemInfo, ...) and
-- exposes only C_Container.*; BCC still has the globals. Our modules call the
-- bare global names, so on Era we recreate them from C_Container when missing.
-- Each shim is installed ONLY when the global is absent, so on clients that
-- still have the real function nothing changes.
-- =========================================================
local _, ns = ...

local c = _G.C_Container
if c then
    -- These keep the legacy single-value / same-argument contract -> safe to alias 1:1.
    GetContainerNumSlots     = GetContainerNumSlots     or c.GetContainerNumSlots
    GetContainerItemID       = GetContainerItemID       or c.GetContainerItemID
    GetContainerItemLink     = GetContainerItemLink     or c.GetContainerItemLink
    GetContainerNumFreeSlots = GetContainerNumFreeSlots or c.GetContainerNumFreeSlots
    GetContainerItemCooldown = GetContainerItemCooldown or c.GetContainerItemCooldown
    PickupContainerItem      = PickupContainerItem      or c.PickupContainerItem
    UseContainerItem         = UseContainerItem         or c.UseContainerItem
    SplitContainerItem       = SplitContainerItem       or c.SplitContainerItem

    -- GetContainerItemInfo CHANGED contract: C_Container returns a single table,
    -- the old global returned a tuple. Re-wrap to the legacy tuple our call sites expect.
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

-- =========================================================
-- FUTURE-PROOFING SHIMS. The classic clients trail retail's API removals by a
-- few builds: everything below is either already gone on one of our flavors
-- (addon management + GetMouseFocus on 2.5.5) or only survives as a Blizzard
-- "Deprecated_*" Lua wrapper gated by the loadDeprecationFallbacks CVar, with
-- a TOC note that it dies at the next client jump. Each shim installs ONLY
-- when the legacy global is nil and its modern source exists — a no-op today
-- where the native remains, an invisible safety net the day it disappears.
-- Legacy tuple shapes mirror Blizzard's own wrappers exactly.
-- Test harness on a live client: /console loadDeprecationFallbacks 0 + /reload.
-- =========================================================

-- ---- addon management (already REMOVED on 2.5.5; wrapper-only on 1.15.x) ----
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

-- ---- mouse focus (already removed on BOTH flavors) ---------------------------
if not GetMouseFocus and _G.GetMouseFoci then
    local foci = _G.GetMouseFoci
    GetMouseFocus = function()
        local f = foci()
        return f and f[1]
    end
end

-- ---- auras (wrapper-only on BOTH flavors — the natives are already gone) -----
local cua = _G.C_UnitAuras
if cua and cua.GetAuraDataByIndex then
    -- legacy tuple = AuraUtil.UnpackAuraData: name, icon, count, dispelType,
    -- duration, expirationTime, source, isStealable, nameplateShowPersonal,
    -- spellId, canApplyAura, isBossAura, castByPlayer, nameplateShowAll,
    -- timeMod, ...points
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
    -- UnitBuff/UnitDebuff must COMBINE the implied flag with any caller
    -- filter (UnitDebuff(unit, i, "RAID") means HARMFUL|RAID) — exactly what
    -- the dedicated getters do; a plain `filter or "HELPFUL"` default would
    -- silently return buffs for a filtered debuff query.
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

-- ---- items (wrapper-only on both; C_Item keeps the legacy tuples 1:1) --------
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

-- ---- spells (still native on both; C_Spell exists on both = next in line) ----
local cs = _G.C_Spell
if cs then
    if not GetSpellInfo and cs.GetSpellInfo then
        GetSpellInfo = function(spell)
            local si = cs.GetSpellInfo(spell)
            if not si then return nil end
            -- legacy: name, rank(nil), icon, castTime, minRange, maxRange,
            -- spellID, originalIcon (rank text lives in GetSpellSubtext)
            return si.name, nil, si.iconID, si.castTime, si.minRange,
                   si.maxRange, si.spellID, si.originalIconID
        end
    end
    if not GetSpellTexture and cs.GetSpellTexture then
        GetSpellTexture = cs.GetSpellTexture   -- plain values, same order
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

-- ---- chat plumbing (wrapper-only; ChatFrameUtil is the modern home) ----------
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
