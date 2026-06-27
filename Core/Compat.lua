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
