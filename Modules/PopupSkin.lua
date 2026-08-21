-- Dialog popups: restyles Blizzard's StaticPopup dialogs to the dark look.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("popupskin", {
    name        = "Dialog Popups",
    group       = "UI Reskin",
    description = "Restyles Blizzard's confirmation dialogs (logout countdown, delete item, resurrect, group invite) to match the dark look.",
    defaults = {
        enabled = true,
        accentStrip = true,
    },
})

-- Every popup we have touched, so the toggle can restore Blizzard's look
-- without a /reload. Each entry keeps the regions we faded plus our own.
local skinned = {}

local function stripBackdrop(f)
    if not f.SetBackdrop then return end
    -- GetBackdrop() reports the live backdrop whether it came from XML or from
    -- backdropInfo; backdropInfo alone is nil on XML-defined chrome and the
    -- SetBackdrop(nil) below would then be unrecoverable. SetBackdrop also
    -- resets both colors to white, so they have to be saved separately.
    if f._vcOrigBackdrop == nil then
        f._vcOrigBackdrop = (f.GetBackdrop and f:GetBackdrop()) or f.backdropInfo or false
        if f.GetBackdropColor then f._vcOrigBdColor = { f:GetBackdropColor() } end
        if f.GetBackdropBorderColor then f._vcOrigBdBorder = { f:GetBackdropBorderColor() } end
    end
    f:SetBackdrop(nil)
end

local function restoreBackdrop(f)
    if not (f.SetBackdrop and f._vcOrigBackdrop) then return end
    f:SetBackdrop(f._vcOrigBackdrop)
    local c = f._vcOrigBdColor
    if c and c[1] and f.SetBackdropColor then f:SetBackdropColor(c[1], c[2], c[3], c[4]) end
    local b = f._vcOrigBdBorder
    if b and b[1] and f.SetBackdropBorderColor then f:SetBackdropBorderColor(b[1], b[2], b[3], b[4]) end
end

-- Fade instead of SetTexture(nil) so enabling/disabling stays reversible.
-- IsShown() is the load-bearing filter: regions Blizzard uses situationally
-- (item icon, alert icon) sit hidden on the frame but still report alpha 1, and
-- Blizzard brings them back with Show(), not SetAlpha — fading those would hide
-- them forever. Only what is actually drawn right now is chrome.
local function fadeRegions(frame, store)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture")
            and r.IsShown and r:IsShown()
            and r.GetAlpha and r:GetAlpha() > 0 then
            store[#store + 1] = { r, r:GetAlpha() }
            r:SetAlpha(0)
        end
    end
end

-- Font + color have to be captured too, otherwise disabling leaves our typeface
-- on Blizzard's chrome.
-- Records the original font/color alongside the one we want, so setShown can
-- flip between them without re-measuring (a second capture would record OUR
-- values as the original and make the revert a no-op).
local function restyleFont(fs, size, r, g, b, entry)
    if not (fs and fs.GetFont and fs.SetFont) then return end
    local path, oldSize, flags = fs:GetFont()
    local cr, cg, cb, ca = 1, 1, 1, 1
    if fs.GetTextColor then cr, cg, cb, ca = fs:GetTextColor() end
    entry.fonts[#entry.fonts + 1] = {
        fs = fs,
        path = path, size = oldSize, flags = flags,
        r = cr, g = cg, b = cb, a = ca,
        ourSize = size, ourR = r, ourG = g, ourB = b,
    }
end

local function applyFonts(entry, on)
    for _, e in ipairs(entry.fonts) do
        local fs = e.fs
        if on then
            if ns.UI and ns.UI.Font then ns.UI.Font(fs, e.ourSize) end
            if e.ourR and fs.SetTextColor then fs:SetTextColor(e.ourR, e.ourG, e.ourB) end
        else
            if e.path then fs:SetFont(e.path, e.size, e.flags) end
            if fs.SetTextColor then fs:SetTextColor(e.r, e.g, e.b, e.a) end
        end
    end
end

local function fadeButtonTextures(b, store)
    local getters = { b.GetNormalTexture, b.GetPushedTexture, b.GetDisabledTexture }
    for _, get in ipairs(getters) do
        local t = get and get(b)
        if t and t.GetAlpha and t:GetAlpha() > 0 then
            store[#store + 1] = { t, t:GetAlpha() }
            t:SetAlpha(0)
        end
    end
    fadeRegions(b, store)
end

local function skinPopupButton(b, entry)
    if not b or b._vcPopupSkin or not b.HookScript then return end
    b._vcPopupSkin = true

    local ac = ns.COLORS.accent
    local bc = ns.COLORS.border or { r = 0.22, g = 0.22, b = 0.27 }
    fadeButtonTextures(b, entry.faded)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.13, 0.13, 0.16, 1)
    entry.ours[#entry.ours + 1] = bg

    local edges = {}
    for i = 1, 4 do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        edges[i] = t
        entry.ours[#entry.ours + 1] = t
    end
    edges[1]:SetPoint("TOPLEFT");     edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT");  edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");     edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");    edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)

    restyleFont(b.GetFontString and b:GetFontString(), 12, nil, nil, nil, entry)

    -- resting look, also used to clear a hover that was left behind when the
    -- module was switched off mid-hover (OnLeave bails while inactive)
    local function rest()
        bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        for _, t in ipairs(edges) do t:SetColorTexture(bc.r, bc.g, bc.b, 1) end
    end
    entry.rests[#entry.rests + 1] = rest

    -- gate on mod.active: HookScript cannot be removed once the toggle is off
    b:HookScript("OnEnter", function()
        if not mod.active then return end
        bg:SetColorTexture(0.19, 0.19, 0.23, 1)
        for _, t in ipairs(edges) do t:SetColorTexture(ac.r, ac.g, ac.b, 0.9) end
    end)
    b:HookScript("OnLeave", function()
        if not mod.active then return end
        rest()
    end)
end

local function skinEditBox(eb, entry)
    if not eb or eb._vcPopupSkin or not eb.CreateTexture then return end
    eb._vcPopupSkin = true
    fadeRegions(eb, entry.faded)

    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, -1)
    bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 1)
    bg:SetColorTexture(0.07, 0.07, 0.09, 1)
    entry.ours[#entry.ours + 1] = bg

    local bc = ns.COLORS.border or { r = 0.22, g = 0.22, b = 0.27 }
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 1, true }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1, true } }) do
        local t = eb:CreateTexture(nil, "BORDER")
        t:SetPoint(p[1], bg, p[1]); t:SetPoint(p[2], bg, p[2]); t:SetHeight(p[3])
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        entry.ours[#entry.ours + 1] = t
    end
end

-- built on demand so toggling the option back on works without a /reload
local function ensureStrip(entry)
    if not mod.db.accentStrip or entry.strip then return end
    local f = entry.frame
    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    local a = ns.COLORS.accent
    local UI = ns.UI
    if UI and UI.SetGradient then
        UI.SetGradient(strip, "HORIZONTAL", a.r, a.g, a.b, 0.1, a.r, a.g, a.b, 0.9)
    else
        strip:SetColorTexture(a.r, a.g, a.b, 0.7)
    end
    -- siehe skinPopup: eigene Texturen duerfen nicht in die Layout-Messung
    strip.ignoreInLayout = true
    entry.ours[#entry.ours + 1] = strip
    entry.strip = strip
end

-- Der moderne Dialog ist ein ResizeLayoutFrame: StaticPopup_Show misst seine
-- Hoehe aus den Kindern, und zwar VOR unserem Schrifttausch im Show-Hook.
-- Faellt der Text mit unserer Schrift hoeher aus, fliesst der Inhalt ueber
-- die gemessene Kante und die Knoepfe haengen unter dem Rahmen -- sichtbar
-- geworden am Loeschen-Bestaetigungsdialog, wo langer Text plus Eingabefeld
-- den Fehler aufsummieren (Nutzerbild 19.08.2026). Nach jedem Schriftwechsel
-- deshalb die dialogeigene Rechnung erneut anstossen; die misst dann mit der
-- Schrift, die wirklich gezeichnet wird. Der Rueckfall auf das alte globale
-- StaticPopup_Resize deckt Clients ohne den Mixin-Umbau.
local function resizeShownPopups()
    for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
        local f = _G["StaticPopup" .. i]
        if f and f.IsShown and f:IsShown() then
            if f.Resize and f.dialogInfo then
                pcall(f.Resize, f)
            elseif _G.StaticPopup_Resize and f.which then
                pcall(_G.StaticPopup_Resize, f, f.which)
            end
        end
    end
end

-- popups that were visible when we wanted to skin them; skinned on OnHide
local pending = {}

local function skinPopup(f)
    if not f then return end
    local entry = skinned[f]
    if entry then return entry end

    -- A dialog that is on screen right now carries its situational art (item
    -- icon, alert icon) as VISIBLE regions — capturing here would fade them
    -- forever. The IsShown filter in fadeRegions only protects while the frame
    -- is hidden, so defer this popup until it closes.
    if f.IsShown and f:IsShown() then
        pending[f] = true
        -- the hook must go in exactly once — HookScript stacks, and `pending`
        -- gets cleared, so it cannot double as the installed-marker
        if not f._vcHideHooked then
            f._vcHideHooked = true
            f:HookScript("OnHide", function()
                -- fonts arrive via the Show-hook's setShown on the next show
                if pending[f] and not skinned[f] and mod.active then
                    skinPopup(f)
                end
                pending[f] = nil
            end)
        end
        return
    end
    pending[f] = nil

    entry = { frame = f, ours = {}, faded = {}, fonts = {}, rests = {} }
    -- registered before the work below so a mid-way error still leaves us the
    -- record needed to undo what was already changed
    skinned[f] = entry

    stripBackdrop(f)
    fadeRegions(f, entry.faded)

    local UI = ns.UI
    if UI and UI.StyleBackdrop then
        UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim or ns.COLORS.border })
        -- StyleBackdrop parks its pieces on the frame itself; collect them so the
        -- revert can hide them again
        if f._vcBG then entry.ours[#entry.ours + 1] = f._vcBG end
        if f._vcBorders then
            for _, b in ipairs(f._vcBorders) do entry.ours[#entry.ours + 1] = b end
        end
    end
    if UI and UI.CreateShadow then
        UI:CreateShadow(f)
        if f._vcShadow then
            for _, t in ipairs(f._vcShadow) do entry.ours[#entry.ours + 1] = t end
        end
    end

    ensureStrip(entry)

    -- parentKey first, $parent global second: the classic template exposes the
    -- globals, the rewritten one only the keys — take whichever this client has
    local name = f.GetName and f:GetName()
    -- `probe` decides whether the parentKey is the object we want; without it a
    -- key holding a container (not the widget) would shadow the global and the
    -- fallback would never run
    local function part(key, suffix, probe)
        local v = f[key]
        if not (v and v[probe]) then v = name and _G[name .. suffix] or nil end
        if v and v[probe] then return v end
        return nil
    end

    for i = 1, 4 do
        skinPopupButton(part("button" .. i, "Button" .. i, "HookScript"), entry)
    end
    skinEditBox(part("editBox", "EditBox", "CreateTexture"), entry)

    restyleFont(part("text", "Text", "SetTextColor"), 13, 0.92, 0.90, 0.96, entry)

    -- Der Dialog misst als ResizeLayoutFrame JEDE sichtbare Region ohne
    -- ignoreInLayout mit -- auch unsere. Der Schatten ragt bis 7px ueber jede
    -- Kante und wuerde den Rahmen bei jeder Messung aufblasen; die uebrigen
    -- Stuecke haengen an den Rahmenkanten oder an Kind-Fenstern (Knoepfe,
    -- Eingabefeld -- dort misst niemand) und sind harmlos, bekommen die
    -- Markierung aber mit, damit die Frage nie wieder offen ist.
    for _, t in ipairs(entry.ours) do t.ignoreInLayout = true end

    return entry
end

local function skinAll()
    -- read at call time: the global is not guaranteed to exist while files load
    for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
        -- one odd dialog must not stop the others from being skinned
        local ok, err = pcall(skinPopup, _G["StaticPopup" .. i])
        if not ok and ns.Debug then ns:Debug("PopupSkin: StaticPopup%d: %s", i, tostring(err)) end
    end
end

local function setShown(on)
    for f, entry in pairs(skinned) do
        for _, t in ipairs(entry.ours) do
            if on then t:Show() else t:Hide() end
        end
        for _, pair in ipairs(entry.faded) do
            pair[1]:SetAlpha(on and 0 or pair[2])
        end
        applyFonts(entry, on)
        if on then stripBackdrop(f) else restoreBackdrop(f) end
        if on then ensureStrip(entry) end
        if entry.strip then
            if on and mod.db.accentStrip then entry.strip:Show() else entry.strip:Hide() end
        end
    end
end

local hooked = false
local function installHooks()
    if hooked then return end
    -- StaticPopup_Show may not exist yet: modules are enabled on ADDON_LOADED,
    -- and the dialogs live in a Blizzard addon that can load later. Only latch
    -- `hooked` once the hook really went in, so the retry below can catch up.
    if not _G.StaticPopup_Show then return end
    hooked = true
    -- Blizzard re-applies backdropInfo when a dialog is shown, so re-assert on Show
    hooksecurefunc("StaticPopup_Show", function()
        if not mod.active then return end
        skinAll()
        -- not just stripBackdrop: a dialog first seen here still needs its
        -- recorded fonts applied
        setShown(true)
        resizeShownPopups()
    end)
end

local function setup()
    installHooks()
    skinAll()
    setShown(true)
    resizeShownPopups()
    -- clear any hover left frozen by a toggle-off mid-hover (OnLeave bails
    -- while inactive). Deliberately NOT in the Show-hook: there it would reset
    -- a button the mouse is legitimately resting on.
    for _, entry in pairs(skinned) do
        for _, rest in ipairs(entry.rests) do rest() end
    end
end

local retry = CreateFrame("Frame")
retry:RegisterEvent("PLAYER_LOGIN")
retry:SetScript("OnEvent", function()
    if mod.active then setup() end
end)

function mod:OnEnable()
    setup()
end

function mod:OnDisable()
    setShown(false)
    -- zurueck zu Blizzards Schrift heisst auch: zurueck zu Blizzards Mass
    resizeShownPopups()
end

function mod:GetOptions()
    return {
        { type = "header", text = L["Dialog Popups"] },
        { type = "desc", text = L["|cffaaaaaaRestyles Blizzard's confirmation dialogs — logout countdown, delete item, resurrect, group invite — to match the dark look.|r"] },

        { type = "spacer", height = 6 },
        { type = "toggle", label = L["Accent strip"],
          tooltip = L["Draws a thin accent gradient along the top edge of each dialog."],
          get = function() return mod.db.accentStrip end,
          set = function(_, v)
              mod.db.accentStrip = v
              -- while the module is off nothing of ours may become visible;
              -- setShown(true) applies the new setting on the next enable
              if not mod.active then return end
              for _, entry in pairs(skinned) do
                  ensureStrip(entry)
                  if entry.strip then
                      if v then entry.strip:Show() else entry.strip:Hide() end
                  end
              end
          end },
    }
end
