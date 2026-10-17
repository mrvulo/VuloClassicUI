-- VuloClassicUI / UI / StringDialog: the modal for profile strings.
--
-- Export shows the string pre-selected, so Ctrl+C is the only step left.
-- Import is a two-step flow: a paste box that ABSORBS the string instead of
-- displaying it (a 40 KB string in a live EditBox stalls the whole client for
-- seconds -- the box is capped and the characters are collected off-screen),
-- then a preview of what the string carries: the name is editable and every
-- module can be unticked before anything is written.
local _, ns = ...
local L = ns.L

local DIALOG_W   = 560
local DIALOG_H   = 400
local PAD        = 14

local host, dlg
local exportPanel, pastePanel, previewPanel, reviewPanel
local w = {}          -- widget refs shared across the builders
local session         -- current import session: payload, summary, sel, name

-- ---------------------------------------------------------------------------
-- Shell

local function hideAll()
    if exportPanel then exportPanel:Hide() end
    if pastePanel then pastePanel:Hide() end
    if previewPanel then previewPanel:Hide() end
    if reviewPanel then reviewPanel:Hide() end
end

local function applyAccent()
    -- the theme color is live-mutated; re-tint on every open, never bake it
    local ac = ns.COLORS.accent
    ns.UI.SetGradient(w.strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    w.title:SetTextColor(ac.r, ac.g, ac.b)
end

local function ensureShell()
    if host then return end
    local UI = ns.UI

    host = CreateFrame("Frame", "VCUI_StringDialogHost", UIParent)
    host:SetFrameStrata("FULLSCREEN_DIALOG")
    host:SetAllPoints(UIParent)
    host:EnableMouse(true)
    host:Hide()
    local dim = host:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(host)
    dim:SetColorTexture(0, 0, 0, 0.35)
    -- click beside the window closes it, like ESC
    host:SetScript("OnMouseDown", function() host:Hide() end)
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, "VCUI_StringDialogHost")

    dlg = CreateFrame("Frame", nil, host)
    dlg:SetSize(DIALOG_W, DIALOG_H)
    dlg:SetPoint("CENTER", host, "CENTER", 0, 40)
    dlg:EnableMouse(true)   -- swallows clicks so they never reach the dimmer
    UI:StyleBackdrop(dlg, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    if UI.CreateShadow then UI:CreateShadow(dlg) end

    w.strip = dlg:CreateTexture(nil, "ARTWORK")
    w.strip:SetPoint("TOPLEFT", dlg, "TOPLEFT", 0, 0)
    w.strip:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", 0, 0)
    w.strip:SetHeight(2)

    w.title = dlg:CreateFontString(nil, "OVERLAY")
    UI.Font(w.title, 13)
    w.title:SetPoint("TOPLEFT", dlg, "TOPLEFT", PAD, -12)

    UI:CreateCloseX(dlg, function() host:Hide() end)

    host:SetScript("OnHide", function() session = nil end)
end

local function openShell(titleText)
    ensureShell()
    hideAll()
    w.title:SetText(titleText)
    applyAccent()
    host:Show()
end

-- One scrollframe + multiline EditBox pair, the shared recipe of all panels.
local function makeScrollBox(parent)
    local UI = ns.UI
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local bg = sf:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.8)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    UI.Font(eb, 11)
    eb:SetTextColor(0.85, 0.85, 0.9)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    UI.StyleScrollbar(sf)
    return sf, eb
end

-- ---------------------------------------------------------------------------
-- Export

local function ensureExportPanel()
    if exportPanel then return end
    local UI = ns.UI
    exportPanel = CreateFrame("Frame", nil, dlg)
    exportPanel:SetAllPoints(dlg)
    -- born hidden: the ensure*() calls run AFTER openShell's hideAll, so a
    -- panel created on this very open would otherwise stay visible forever
    exportPanel:Hide()

    local hint = exportPanel:CreateFontString(nil, "OVERLAY")
    UI.Font(hint, 12)
    hint:SetPoint("TOPLEFT", exportPanel, "TOPLEFT", PAD, -40)
    hint:SetTextColor(0.75, 0.75, 0.8)
    hint:SetText(L["The string is selected - press Ctrl+C to copy it."])

    local sf, eb = makeScrollBox(exportPanel)
    sf:SetPoint("TOPLEFT", exportPanel, "TOPLEFT", PAD + 2, -64)
    sf:SetPoint("BOTTOMRIGHT", exportPanel, "BOTTOMRIGHT", -(PAD + 16), 56)
    w.exportEB = eb

    -- read-only that survives keystrokes: any user change snaps the text
    -- back and re-selects it, so a stray key never breaks the Ctrl+C flow
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self._locked and self:GetText() ~= self._locked then
            self:SetText(self._locked)
            self:HighlightText()
        end
    end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)

    w.exportCount = exportPanel:CreateFontString(nil, "OVERLAY")
    UI.Font(w.exportCount, 11)
    w.exportCount:SetPoint("BOTTOMLEFT", exportPanel, "BOTTOMLEFT", PAD, 22)
    w.exportCount:SetTextColor(0.55, 0.55, 0.6)

    local close = UI:CreateButton(exportPanel, {
        label = CLOSE, width = 120, primary = true,
        onClick = function() host:Hide() end,
    })
    close:SetPoint("BOTTOMRIGHT", exportPanel, "BOTTOMRIGHT", -PAD, 14)
end

function ns.UI:ShowProfileExportDialog(str)
    openShell(L["Export as string"])
    ensureExportPanel()
    exportPanel:Show()
    local eb = w.exportEB
    eb._locked = nil
    eb:SetWidth(DIALOG_W - 2 * PAD - 26)
    eb:SetText(str)
    eb._locked = str
    w.exportCount:SetText(string.format(L["%d characters"], #str))
    eb:SetFocus()
    eb:HighlightText()
end

-- ---------------------------------------------------------------------------
-- Import, step 1: the paste absorber

local function ensurePastePanel()
    if pastePanel then return end
    local UI = ns.UI
    pastePanel = CreateFrame("Frame", nil, dlg)
    pastePanel:SetAllPoints(dlg)
    pastePanel:Hide()

    local hint = pastePanel:CreateFontString(nil, "OVERLAY")
    UI.Font(hint, 12)
    hint:SetPoint("TOPLEFT", pastePanel, "TOPLEFT", PAD, -40)
    hint:SetTextColor(0.75, 0.75, 0.8)
    hint:SetText(L["Paste the string here with Ctrl+V."])

    local sf, eb = makeScrollBox(pastePanel)
    sf:SetPoint("TOPLEFT", pastePanel, "TOPLEFT", PAD + 2, -64)
    sf:SetPoint("BOTTOMRIGHT", pastePanel, "BOTTOMRIGHT", -(PAD + 16), 56)
    w.pasteEB = eb

    -- The box never holds the real string: the cap keeps the layout cost
    -- flat while OnChar still sees every pasted character. They are collected
    -- here and the paste counts as finished on the first frame that brings
    -- no new ones.
    eb:SetMaxBytes(2048)
    local buf, lastCount = {}, -1
    -- characters past the cap are counted, not kept: the paste still has to
    -- be seen to end before it can be refused
    local overflow = 0
    local maxChars = ns.SHARE_MAX_TEXT or 250000
    local watcher = CreateFrame("Frame", nil, pastePanel)
    watcher:Hide()

    local function resetPaste()
        for i = #buf, 1, -1 do buf[i] = nil end
        lastCount = -1
        overflow = 0
        watcher:Hide()
    end
    w.resetPaste = function()
        resetPaste()
        w.pasteEB:SetText("")
        w.pasteError:SetText("")
    end

    eb:SetScript("OnChar", function(_, c)
        if #buf < maxChars then buf[#buf + 1] = c else overflow = overflow + 1 end
        watcher:Show()
    end)
    watcher:SetScript("OnUpdate", function()
        local n = #buf + overflow
        if n > 0 and n == lastCount then
            local tooLong = overflow > 0
            local text = (not tooLong) and table.concat(buf) or nil
            resetPaste()
            if tooLong then
                w.pasteEB:SetText("")
                w.pasteError:SetText("|cffff5555" .. L["The string is too large to import."] .. "|r")
                return
            end
            -- A session may bring its OWN reader; the bar setups do. It answers
            -- with an error line or with nothing, and owns whatever happens
            -- afterwards -- there is no profile preview to show it.
            if session and session.onText then
                local err = session.onText(text)
                if err then
                    w.pasteEB:SetText("")
                    w.pasteError:SetText("|cffff5555" .. tostring(err) .. "|r")
                    return
                end
                w.pasteEB:SetText(string.format(L["String captured - %d characters."], #text))
                w.pasteEB:ClearFocus()
                w.pasteError:SetText("")
                host:Hide()
                return
            end
            local payload, summaryOrErr = ns:DecodeProfileString(text)
            if not payload then
                w.pasteEB:SetText("")
                w.pasteError:SetText("|cffff5555" .. tostring(summaryOrErr) .. "|r")
                return
            end
            w.pasteEB:SetText(string.format(L["String captured - %d characters."], #text))
            w.pasteEB:ClearFocus()
            w.pasteError:SetText("")
            ns.UI:ShowImportPreview(payload, summaryOrErr)
        else
            lastCount = n
        end
    end)

    w.pasteError = pastePanel:CreateFontString(nil, "OVERLAY")
    UI.Font(w.pasteError, 12)
    w.pasteError:SetPoint("BOTTOMLEFT", pastePanel, "BOTTOMLEFT", PAD, 22)
    w.pasteError:SetJustifyH("LEFT")

    local cancel = UI:CreateButton(pastePanel, {
        label = CANCEL, width = 120,
        onClick = function() host:Hide() end,
    })
    cancel:SetPoint("BOTTOMRIGHT", pastePanel, "BOTTOMRIGHT", -PAD, 14)
    -- a long locale error must wrap short of the button, not run under it
    w.pasteError:SetPoint("RIGHT", cancel, "LEFT", -10, 0)
    w.pasteError:SetWordWrap(false)
end

-- ---------------------------------------------------------------------------
-- Import, step 2: the preview

local togglePool = {}

local function ensurePreviewPanel()
    if previewPanel then return end
    local UI = ns.UI
    previewPanel = CreateFrame("Frame", nil, dlg)
    previewPanel:SetAllPoints(dlg)
    previewPanel:Hide()

    w.nameBox = UI:CreateEditBox(previewPanel, {
        label = L["Name"], editWidth = 240, commitOnFocusLost = true,
        get = function() return session and session.name or "" end,
        set = function(_, v) if session then session.name = v end end,
    })
    w.nameBox:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", PAD, -42)

    w.previewNote = previewPanel:CreateFontString(nil, "OVERLAY")
    UI.Font(w.previewNote, 11)
    w.previewNote:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", PAD, -74)
    w.previewNote:SetPoint("RIGHT", previewPanel, "RIGHT", -PAD, 0)
    w.previewNote:SetJustifyH("LEFT")
    w.previewNote:SetTextColor(0.6, 0.6, 0.65)

    local sf = CreateFrame("ScrollFrame", nil, previewPanel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", PAD + 2, -96)
    sf:SetPoint("BOTTOMRIGHT", previewPanel, "BOTTOMRIGHT", -(PAD + 16), 56)
    local bg = sf:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.8)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(DIALOG_W - 2 * PAD - 30, 10)
    sf:SetScrollChild(content)
    UI.StyleScrollbar(sf)
    w.previewContent = content

    local import = UI:CreateButton(previewPanel, {
        label = L["Import"], width = 140, primary = true,
        onClick = function()
            if not session then return end
            local s = session
            local mods, anyOff = {}, false
            for _, k in ipairs(s.summary.moduleKeys) do
                if s.sel[k] == false then anyOff = true else mods[k] = true end
            end
            local name, err = ns:ImportProfilePayload(s.payload, {
                name      = s.name,
                modules   = anyOff and mods or nil,
                layout    = s.sel.__layout ~= false,
                overrides = s.sel.__overrides ~= false,
                look      = s.sel.__look ~= false,
                -- opt-in: ShowImportPreview starts this one at false
                macroTexts = s.sel.__macros ~= false,
            })
            if not name then
                ns:Print("|cffff5555%s|r", err or L["Error."])
                return
            end
            local cb = s.onSuccess
            host:Hide()
            if cb then cb(name) end
        end,
    })
    import:SetPoint("BOTTOMRIGHT", previewPanel, "BOTTOMRIGHT", -PAD, 14)

    local back = UI:CreateButton(previewPanel, {
        label = L["Go back"], width = 110,
        onClick = function()
            previewPanel:Hide()
            pastePanel:Show()
            if w.resetPaste then w.resetPaste() end
        end,
    })
    back:SetPoint("RIGHT", import, "LEFT", -8, 0)
end

local ROW_H, COL_W = 24, 244
local rowsTop = 6   -- where the toggle grid starts; the macro block sits above it

-- Ample for every module this build has plus the unknown ones the decoder
-- lets through; a cap all the same, because each row is a pooled frame.
local MAX_PREVIEW_ROWS = 100
-- the macro block shows this much of each text
local MACRO_SHOW_CHARS = 300
-- and lists this many; no real profile has a tenth of that
local MACRO_SHOW_COUNT = 200

-- Text from the string, shown as text: | doubled so no colour, link or
-- texture code can draw anything, other control characters gone.
local function plainText(s, maxLen)
    s = tostring(s or ""):gsub("|", "||"):gsub("[%z\001-\009\011-\031]", "")
    if maxLen and #s > maxLen then
        -- never cut a doubled bar in half, it would open an escape again
        s = s:sub(1, maxLen)
        local bars = #(s:match("|*$"))
        if bars % 2 == 1 then s = s:sub(1, -2) end
        s = s .. "..."
    end
    return s
end

-- Long text as a stack of FontStrings of a couple of thousand bytes each, cut
-- at line ends: one string holding a whole review would be a single huge
-- layout. Each piece's wrapped height places the next. Returns the height.
local CHUNK_BYTES = 2000

local function setStackText(stack, parent, text, width, x, y)
    local pieces, cur, n = {}, {}, 0
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        if n + #line > CHUNK_BYTES and #cur > 0 then
            pieces[#pieces + 1] = table.concat(cur, "\n")
            cur, n = {}, 0
        end
        cur[#cur + 1] = line
        n = n + #line + 1
    end
    if #cur > 0 then pieces[#pieces + 1] = table.concat(cur, "\n") end
    local h = 0
    for i, piece in ipairs(pieces) do
        local fs = stack[i]
        if not fs then
            fs = parent:CreateFontString(nil, "OVERLAY")
            ns.UI.Font(fs, stack.size or 11)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(stack.r or 0.85, stack.g or 0.85, stack.b or 0.9)
            stack[i] = fs
        end
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + h))
        fs:SetText(piece)
        fs:Show()
        h = h + math.ceil(fs:GetStringHeight())
    end
    for i = #pieces + 1, #stack do stack[i]:Hide() end
    return h
end

local function previewRow(idx, label, selKey)
    local content = w.previewContent
    local t = togglePool[idx]
    if not t then
        t = ns.UI:CreateToggle(content, {
            label = label, width = COL_W,
            get = function() return true end,
            set = function() end,
        })
        togglePool[idx] = t
    end
    -- pooled: rebind label + selection key on every open
    t._vcConfig.label = label
    t._vcConfig.get = function()
        return not (session and session.sel[selKey] == false)
    end
    t._vcConfig.set = function(_, v)
        if session then
            if v then session.sel[selKey] = nil else session.sel[selKey] = false end
        end
    end
    t._vcSetup(t, t._vcConfig)
    t:ClearAllPoints()
    local col = (idx - 1) % 2
    local row = math.floor((idx - 1) / 2)
    t:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + col * (COL_W + 12), -(rowsTop + row * ROW_H))
    t:Show()
    return idx + 1
end

function ns.UI:ShowImportPreview(payload, summary)
    ensurePreviewPanel()
    hideAll()
    w.title:SetText(L["Import from string"])
    session = session or {}
    session.payload  = payload
    session.summary  = summary
    session.sel      = {}
    session.name     = summary.name
    previewPanel:Show()

    w.nameBox._vcSetup(w.nameBox, w.nameBox._vcConfig)

    -- one line of room: the partial hint outranks the untick hint, because a
    -- partial string merges no matter what is ticked
    w.previewNote:SetText(summary.partial
        and L["Partial string: anything missing is taken from your active profile."]
        or  L["Unticked parts keep your current settings."])

    -- Texts that run on a key press go on top, in full view, and stay out
    -- unless ticked: a /run in a ring entry acts the first time the key is
    -- pressed, and a list of module names says nothing about that.
    local content = w.previewContent
    local fullW = content:GetWidth() - 16
    local texts = summary.macroTexts or {}
    rowsTop = 6
    if #texts > 0 then
        session.sel.__macros = false
        if not w.macroHead then
            w.macroHead = content:CreateFontString(nil, "OVERLAY")
            ns.UI.Font(w.macroHead, 12)
            w.macroHead:SetJustifyH("LEFT")
            w.macroHead:SetTextColor(1, 0.35, 0.35)
            w.macroBody = { size = 11, r = 0.9, g = 0.85, b = 0.6 }
            w.macroToggle = ns.UI:CreateToggle(content, {
                label = L["Import these macro texts"], width = 2 * COL_W + 12,
                get = function() return session and session.sel.__macros ~= false end,
                set = function(_, v)
                    if session then
                        if v then session.sel.__macros = nil else session.sel.__macros = false end
                    end
                end,
            })
        end
        w.macroHead:SetWidth(fullW)
        w.macroHead:ClearAllPoints()
        w.macroHead:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -6)
        w.macroHead:SetText(string.format(
            L["This string contains %d texts that run as macros when a key is pressed. Unless you tick the box below, they are left out:"], #texts))
        w.macroHead:Show()
        local top = 6 + math.ceil(w.macroHead:GetStringHeight()) + 6
        -- listed, not counted: the tick takes all of them at once; each one
        -- is cut to a readable length
        local lines = {}
        for i = 1, math.min(#texts, MACRO_SHOW_COUNT) do
            lines[#lines + 1] = i .. ". " .. plainText(texts[i], MACRO_SHOW_CHARS)
        end
        if #texts > MACRO_SHOW_COUNT then
            lines[#lines + 1] = string.format(L["... and %d more."], #texts - MACRO_SHOW_COUNT)
        end
        top = top + setStackText(w.macroBody, content, table.concat(lines, "\n"), fullW, 8, top) + 8
        w.macroToggle._vcSetup(w.macroToggle, w.macroToggle._vcConfig)
        w.macroToggle:ClearAllPoints()
        w.macroToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -top)
        w.macroToggle:Show()
        rowsTop = top + ROW_H + 10
    elseif w.macroHead then
        w.macroHead:Hide(); w.macroToggle:Hide()
        for _, fs in ipairs(w.macroBody) do fs:Hide() end
    end

    local idx = 1
    for i, k in ipairs(summary.moduleKeys) do
        if i > MAX_PREVIEW_ROWS then
            session.sel[k] = false   -- no row, so no way to tick it: left out
        else
            local m = ns.modules and ns.modules[k]
            -- a key this build does not know is the string's own text: shown
            -- escaped, never as markup
            local label = m and tostring(L[m.name])
                or string.format(L["%s (unknown module)"], (plainText(k, 40):gsub("\n", " ")))
            idx = previewRow(idx, label, k)
        end
    end
    if summary.hasLayout then
        idx = previewRow(idx, L["Interface layout (window positions and links)"], "__layout")
    end
    if summary.hasOverrides then
        idx = previewRow(idx, L["Talent Overrides"], "__overrides")
    end
    if summary.hasLook then
        idx = previewRow(idx, L["Fonts & colors (account-wide)"], "__look")
    end
    for i = idx, #togglePool do togglePool[i]:Hide() end
    local rows = math.ceil((idx - 1) / 2)
    local height = rowsTop + rows * ROW_H + 6

    -- rows that did not fit, and unknown modules past the decoder's cut, are
    -- not imported -- said here rather than left to be discovered
    local hidden = (summary.droppedUnknown or 0)
        + math.max(0, #summary.moduleKeys - MAX_PREVIEW_ROWS)
    if hidden > 0 then
        if not w.previewFoot then
            w.previewFoot = content:CreateFontString(nil, "OVERLAY")
            ns.UI.Font(w.previewFoot, 11)
            w.previewFoot:SetJustifyH("LEFT")
            w.previewFoot:SetTextColor(0.6, 0.6, 0.65)
        end
        w.previewFoot:SetWidth(fullW)
        w.previewFoot:ClearAllPoints()
        w.previewFoot:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -(height + 4))
        w.previewFoot:SetText(string.format(L["%d further unknown modules are left out."], hidden))
        w.previewFoot:Show()
        height = height + 4 + math.ceil(w.previewFoot:GetStringHeight()) + 6
    elseif w.previewFoot then
        w.previewFoot:Hide()
    end
    content:SetHeight(math.max(10, height))
end

-- onSuccess(name) runs after the profile has been created.
-- The paste step WITHOUT the profile preview behind it, for features that read
-- their own strings. onText gets the pasted text and returns an error line to
-- show, or nothing to close the dialog.
function ns.UI:ShowStringImportDialog(title, onText)
    openShell(title or L["Import from string"])
    ensurePastePanel()
    session = { onText = onText }
    -- The preview belongs to the profile path; a leftover from a previous
    -- session must not sit under this one.
    if previewPanel then previewPanel:Hide() end
    pastePanel:Show()
    if w.resetPaste then w.resetPaste() end
    w.pasteEB:SetWidth(DIALOG_W - 2 * PAD - 26)
    w.pasteEB:SetFocus()
end

function ns.UI:ShowProfileImportDialog(onSuccess)
    openShell(L["Import from string"])
    ensurePastePanel()
    ensurePreviewPanel()
    session = { onSuccess = onSuccess }
    pastePanel:Show()
    if w.resetPaste then w.resetPaste() end
    w.pasteEB:SetWidth(DIALOG_W - 2 * PAD - 26)
    w.pasteEB:SetFocus()
end

-- ---------------------------------------------------------------------------
-- Review: a read-only text, up to two ticks, and an accept button. For a
-- feature that must show what a foreign string will DO before it does it --
-- the bar setups list the macros and key bindings an import creates here.
-- The text is the caller's: it escapes whatever came from the string.
--
-- opts = { title, text, accept = label, toggles = { {label, get, set}, ... },
--          onAccept = fn }

local reviewToggles = {}

local function ensureReviewPanel()
    if reviewPanel then return end
    local UI = ns.UI
    reviewPanel = CreateFrame("Frame", nil, dlg)
    reviewPanel:SetAllPoints(dlg)
    reviewPanel:Hide()

    local sf = CreateFrame("ScrollFrame", nil, reviewPanel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", reviewPanel, "TOPLEFT", PAD + 2, -40)
    sf:SetPoint("BOTTOMRIGHT", reviewPanel, "BOTTOMRIGHT", -(PAD + 16), 56 + 2 * ROW_H + 8)
    local bg = sf:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.8)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(DIALOG_W - 2 * PAD - 30, 10)
    sf:SetScrollChild(content)
    UI.StyleScrollbar(sf)
    w.reviewText = { size = 11 }
    w.reviewContent = content

    for i = 1, 2 do
        local t = UI:CreateToggle(reviewPanel, {
            label = "", width = DIALOG_W - 2 * PAD,
            get = function() return false end,
            set = function() end,
        })
        t:SetPoint("BOTTOMLEFT", reviewPanel, "BOTTOMLEFT", PAD, 56 + (2 - i) * ROW_H)
        reviewToggles[i] = t
    end

    w.reviewAccept = UI:CreateButton(reviewPanel, {
        label = L["Load profile"], width = 160, primary = true,
        onClick = function()
            local s = session
            host:Hide()
            if s and s.onAccept then s.onAccept() end
        end,
    })
    w.reviewAccept:SetPoint("BOTTOMRIGHT", reviewPanel, "BOTTOMRIGHT", -PAD, 14)
    local cancel = UI:CreateButton(reviewPanel, {
        label = CANCEL, width = 110,
        onClick = function() host:Hide() end,
    })
    cancel:SetPoint("RIGHT", w.reviewAccept, "LEFT", -8, 0)
end

function ns.UI:ShowReviewDialog(opts)
    openShell(opts.title or "")
    ensureReviewPanel()
    -- a fresh session: closing the window any other way drops onAccept
    session = { onAccept = opts.onAccept }
    reviewPanel:Show()
    local h = setStackText(w.reviewText, w.reviewContent, opts.text, DIALOG_W - 2 * PAD - 42, 6, 6)
    w.reviewContent:SetHeight(math.max(10, h + 12))
    for i, t in ipairs(reviewToggles) do
        local spec = opts.toggles and opts.toggles[i]
        if spec then
            t._vcConfig.label = spec.label
            t._vcConfig.get = spec.get
            t._vcConfig.set = spec.set
            t._vcSetup(t, t._vcConfig)
            t:Show()
        else
            t:Hide()
        end
    end
    w.reviewAccept._textFS:SetText(opts.accept or L["Load profile"])
end
