# Sets sortieren + Helm/Umhang je Set — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set-Zeilen der Charakterfenster-Seitenleiste per Drag-and-drop umsortierbar machen (Reihenfolge persistent) und je Set Helm/Umhang dreistufig (Zeigen/Verstecken/Nicht ändern) beim Anlegen steuern.

**Architecture:** Alles in `Modules/Loadouts.lua`. Reihenfolge = Feld `order` je Set, `sortedLoadoutNames()` wird die einzige Sortierstelle; Drag über `RegisterForDrag` auf den bestehenden Zeilen-Buttons mit schwebendem Geist und Einfügelinie. Helm/Umhang = Felder `helm`/`cloak` (`"show"`/`"hide"`/`nil`), gesetzt über `submenu`-Einträge des geteilten Aufklappmenüs, angewendet am Ende von `equipLoadout()` über `ShowHelm`/`ShowCloak`.

**Tech Stack:** WoW-Classic-Anniversary-Addon (Lua 5.1, kein Test-Framework); statische Prüfung `node tools/check.js`; Spielprüfung manuell durch den Nutzer.

## Global Constraints

- Keine fremden Addon-Namen in Code, Kommentaren oder Commits.
- Commits auf Deutsch, beschreibend, ohne Abkürzungen, ohne Co-Authored-By.
- Sprachschlüssel: englische Basis als Schlüssel, 9 Übersetzungen über die locale-translate-Pipeline.
- `ShowHelm`/`ShowCloak`/`ShowingHelm`/`ShowingCloak` nur nach Existenzprüfung rufen (1.15-Client-Vorbehalt); gegen `wow-ui-source-2.5.x` verifiziert vorhanden.
- Bestehende Sets dürfen ihr Verhalten nicht ändern (Migration ohne sichtbaren Sprung; `nil` = Nicht ändern).
- Nach Code-Änderungen `graphify update .` laufen lassen.

---

### Task 1: Persistente Reihenfolge (Datenmodell)

**Files:**
- Modify: `Modules/Loadouts.lua:380-389` (`sortedLoadoutNames`), `:397-416` (`saveAs`)

**Interfaces:**
- Produces: `sortedLoadoutNames()` liefert Namen nach `order` (Zahl je Set), bei Gleichstand alphabetisch; `moveLoadout(name, targetIndex)` (neue lokale Funktion direkt nach `sortedLoadoutNames`) fügt `name` an Position `targetIndex` der sortierten Liste ein und nummeriert alle `order` neu 1..n. Task 2 ruft `moveLoadout`.

- [ ] **Step 1: `sortedLoadoutNames` ersetzen**

```lua
local function sortedLoadoutNames()
    local names = {}
    if mod.db and LO() then
        local lo = LO()
        for name in pairs(lo) do table.insert(names, name) end
        -- Ohne order ans Ende und dort alphabetisch: bestehende Bestaende
        -- (alle ohne order) landen so in ihrer bisherigen Reihenfolge und
        -- der erste Aufbau sieht exakt aus wie vor dem Feature.
        table.sort(names, function(a, b)
            local oa = lo[a].order or math.huge
            local ob = lo[b].order or math.huge
            if oa ~= ob then return oa < ob end
            return a < b
        end)
        -- Fehlende order-Felder einmalig vergeben; danach ist die Nummer
        -- lueckenlos 1..n und jede spaetere Verschiebung hat festen Boden.
        for i, name in ipairs(names) do
            if lo[name].order ~= i then lo[name].order = i end
        end
    end
    return names
end

-- Fuegt das Set an targetIndex der angezeigten Liste ein (1..n+1) und
-- nummeriert alles neu; targetIndex zaehlt auf der Liste OHNE das gezogene Set.
local function moveLoadout(name, targetIndex)
    local lo = LO()
    if not lo or not lo[name] then return end
    local names = sortedLoadoutNames()
    for i, n in ipairs(names) do
        if n == name then table.remove(names, i) break end
    end
    if targetIndex < 1 then targetIndex = 1 end
    if targetIndex > #names + 1 then targetIndex = #names + 1 end
    table.insert(names, targetIndex, name)
    for i, n in ipairs(names) do lo[n].order = i end
end
```

Achtung: `sortedLoadoutNames` schreibt jetzt (`order`-Vergabe). Sie wird auch aus Tooltips/Listen gerufen — das bleibt korrekt, weil die Vergabe idempotent ist (zweiter Aufruf ändert nichts).

- [ ] **Step 2: Neue Sets hinten anfügen** — in `saveAs`, im `if not set then`-Zweig:

```lua
    if not set then
        set = { createdAt = time() }
        -- ans Ende der angezeigten Liste, nicht alphabetisch einsortiert
        local maxOrder = 0
        for _, other in pairs(LO()) do
            if other.order and other.order > maxOrder then maxOrder = other.order end
        end
        set.order = maxOrder + 1
        LO()[name] = set
    end
```

- [ ] **Step 3: Statisch prüfen** — Run: `node tools/check.js` — Expected: keine neuen Befunde.
- [ ] **Step 4: Commit** — `git add Modules/Loadouts.lua && git commit` — „Die Sets der Seitenleiste haben eine gespeicherte Reihenfolge: jedes Set trägt eine Ordnungsnummer, bestehende Bestände übernehmen ihre bisherige alphabetische Abfolge, neue Sets hängen sich hinten an"

---

### Task 2: Drag-and-drop in der Seitenleiste

**Files:**
- Modify: `Modules/Loadouts.lua` — neuer Block vor `createSetRow` (~1384); `createSetRow` (~1388-1573); Tooltip-`OnEnter` (~1462)

**Interfaces:**
- Consumes: `moveLoadout(name, targetIndex)` aus Task 1; lokale Upvalues `sidebar`, `sidebarSetButtons`, `refreshSidebar` (existieren).
- Produces: nichts für spätere Tasks.

- [ ] **Step 1: Zieh-Zustand und Geist/Linie** — vor `createSetRow` einfügen:

```lua
-- Ziehen zum Umsortieren: _dragName ist gesetzt, solange eine Zeile am
-- Mauszeiger haengt. Geist und Linie werden faul gebaut und wiederverwendet.
local _dragName, _dragGhost, _dragLine

local function visibleSetRows()
    local rows = {}
    for _, b in ipairs(sidebarSetButtons) do
        if b:IsShown() then table.insert(rows, b) end
    end
    return rows
end

-- Einfuegeposition aus den Y-Mitten der SET-Zeilen; ausgeklappte Item-Zeilen
-- sind bewusst keine Ziele, die Luecke unter ihnen gehoert zur Zeile darueber.
local function dragInsertIndex()
    local scale = sidebar:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    cy = cy / scale
    local rows = visibleSetRows()
    for i, b in ipairs(rows) do
        local top, bottom = b:GetTop(), b:GetBottom()
        if top and bottom and cy > (top + bottom) / 2 then return i end
    end
    return #rows + 1
end

local function ensureDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetSize(150, 28)
    g:SetFrameStrata("TOOLTIP")
    g:SetAlpha(0.6)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetSize(22, 22)
    g.icon:SetPoint("LEFT", g, "LEFT", 2, 0)
    g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if ns.UI and ns.UI.Font then ns.UI.Font(g.text, 12) end
    g.text:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
    g:Hide()
    _dragGhost = g
    return g
end

local function ensureDragLine()
    if _dragLine then return _dragLine end
    local l = sidebar:CreateTexture(nil, "OVERLAY")
    l:SetHeight(2)
    local c = ns.COLORS.accent
    l:SetColorTexture(c.r, c.g, c.b, 0.9)
    l:Hide()
    _dragLine = l
    return l
end

local function updateDragVisual()
    local ghost = ensureDragGhost()
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        cx / scale + 12, cy / scale - 8)

    local line = ensureDragLine()
    if not sidebar:IsMouseOver() then line:Hide() return end
    local rows = visibleSetRows()
    local idx  = dragInsertIndex()
    line:ClearAllPoints()
    if idx <= #rows then
        -- OBERKANTE der Zielzeile: dort wird eingefuegt
        line:SetPoint("TOPLEFT",  rows[idx], "TOPLEFT",  0, 2)
        line:SetPoint("TOPRIGHT", rows[idx], "TOPRIGHT", 0, 2)
    elseif rows[#rows] then
        -- hinter die letzte Zeile; haengt dort eine Item-Zeile, unter diese
        local anchor = rows[#rows]
        if sidebarExpanded == anchor.setName then
            for _, r in pairs(sidebarItemRows) do
                if r:IsShown() then anchor = r break end
            end
        end
        line:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, -2)
        line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    end
    line:Show()
end

local function stopDrag(apply)
    local name = _dragName
    _dragName = nil
    if _dragGhost then _dragGhost:Hide(); _dragGhost:SetScript("OnUpdate", nil) end
    if _dragLine  then _dragLine:Hide() end
    if not name then return end
    if apply and sidebar and sidebar:IsMouseOver() then
        local idx  = dragInsertIndex()
        local rows = visibleSetRows()
        -- idx zaehlt MIT der gezogenen Zeile; fuer moveLoadout zaehlt die
        -- Liste ohne sie, also rutscht alles hinter ihr um eins auf
        for i, b in ipairs(rows) do
            if b.setName == name and i < idx then idx = idx - 1 break end
        end
        moveLoadout(name, idx)
    end
    refreshSidebar()
end
```

Hinweis: `sidebarExpanded` und `sidebarItemRows` sind an dieser Stelle bereits deklarierte Upvalues (Deklaration bei ~974-976 bzw. weiter oben); der Block muss NACH diesen Deklarationen und VOR `createSetRow` liegen.

- [ ] **Step 2: Zeilen-Handler in `createSetRow`** — nach dem `btn:SetScript("OnClick", ...)`-Block (~1570) einfügen:

```lua
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if not self.setName then return end
        _dragName = self.setName
        ns.UI:HideTooltip()
        local g = ensureDragGhost()
        g.icon:SetTexture(getSetIcon(self.setName))
        g.text:SetText(self.setName)
        g:Show()
        g:SetScript("OnUpdate", updateDragVisual)
        updateDragVisual()
    end)
    btn:SetScript("OnDragStop", function() stopDrag(true) end)
```

- [ ] **Step 3: Tooltip beim Ziehen unterdrücken** — erste Zeile im `OnEnter`-Handler (~1462):

```lua
        if _dragName then return end
```

(Der Handler steht VOR dem neuen Block aus Step 1 — deshalb muss `local _dragName, _dragGhost, _dragLine` stattdessen VOR `createSetRow` UND vor dem OnEnter nutzbar sein: die Deklarationszeile aus Step 1 gehört daher vor `createSetRow`, und da `createSetRow` selbst nach dem Step-1-Block steht, ist die Reihenfolge erfüllt.)

- [ ] **Step 4: Statisch prüfen** — Run: `node tools/check.js` — Expected: sauber. Zusätzlich Sichtprüfung: kein Zugriff auf `_dragGhost`/`_dragLine` vor Deklaration.
- [ ] **Step 5: Commit** — „Die Set-Zeilen lassen sich mit gedrückter linker Maustaste umsortieren: ein halbtransparenter Geist folgt dem Mauszeiger, eine Linie in der Akzentfarbe zeigt die Einfügeposition, Loslassen außerhalb der Leiste bricht ab"

---

### Task 3: Helm und Umhang je Set

**Files:**
- Modify: `Modules/Loadouts.lua` — `equipLoadout` (Ende der Slot-Schleife, ~522); Rechtsklickmenü in `createSetRow` (~1519, nach „Rename…"); Tooltip-`OnEnter` (~1490, vor den Hinweiszeilen)

**Interfaces:**
- Consumes: Menü-Mechanik `ns:ShowPopupMenu` mit `submenu`/`checked`-Einträgen (vorhanden, `Core/PopupMenu.lua`).
- Produces: Set-Felder `helm`, `cloak` ∈ `"show" | "hide" | nil`. Task 4 übersetzt die hier eingeführten Schlüssel.

- [ ] **Step 1: Anwenden in `equipLoadout`** — direkt nach der `for _, slot in ipairs(sortedSlots) do … end`-Schleife (~Zeile 522), vor den Meldungen:

```lua
    -- Anzeige von Helm und Umhang gehoert zum Set: nur angefasst, wenn das
    -- Set einen Wunsch hat, und nur geschrieben, wenn er noch nicht gilt.
    if ShowHelm and loadout.helm then
        local want = (loadout.helm == "show")
        if not ShowingHelm or ShowingHelm() ~= want then ShowHelm(want) end
    end
    if ShowCloak and loadout.cloak then
        local want = (loadout.cloak == "show")
        if not ShowingCloak or ShowingCloak() ~= want then ShowCloak(want) end
    end
```

- [ ] **Step 2: Untermenüs im Rechtsklickmenü** — Hilfsfunktion VOR `createSetRow` (zum Block aus Task 2 dazu):

```lua
-- Dreistufiger Anzeige-Schalter als Untermenue: Zeigen / Verstecken /
-- Nicht aendern. nil heisst "nicht anfassen" und ist der Standard, damit
-- bestehende Sets sich exakt wie bisher verhalten.
local function displayToggleEntry(setName, field, label)
    local function option(value, text)
        return {
            text    = text,
            checked = function()
                local lo = LO()[setName]
                return lo and lo[field] == value
            end,
            func = function()
                local lo = LO()[setName]
                if lo then lo[field] = value end
            end,
        }
    end
    return {
        text = label,
        submenu = {
            option("show", L["Show"]),
            option("hide", L["Hide"]),
            option(nil,    L["Don't change"]),
        },
    }
end
```

Im Menü in `createSetRow`, nach dem „Rename…"-Eintrag (~1519):

```lua
            if ShowHelm and ShowCloak then
                table.insert(menu, displayToggleEntry(setName, "helm",  L["Helm"]))
                table.insert(menu, displayToggleEntry(setName, "cloak", L["Cloak"]))
            end
```

- [ ] **Step 3: Tooltip-Zeilen** — im `OnEnter` nach der Slot-Schleife, VOR `GameTooltip:AddLine(" ")` + Hinweiszeilen (~1491):

```lua
            if loadout.helm or loadout.cloak then
                GameTooltip:AddLine(" ")
                if loadout.helm then
                    GameTooltip:AddDoubleLine(L["Helm"],
                        loadout.helm == "show" and L["shown"] or L["hidden"],
                        0.6, 0.6, 0.6, 0.95, 0.95, 1)
                end
                if loadout.cloak then
                    GameTooltip:AddDoubleLine(L["Cloak"],
                        loadout.cloak == "show" and L["shown"] or L["hidden"],
                        0.6, 0.6, 0.6, 0.95, 0.95, 1)
                end
            end
```

- [ ] **Step 4: Statisch prüfen** — Run: `node tools/check.js` — Expected: sauber (die neuen L-Schlüssel meldet ggf. der Locale-Abgleich; Task 4 liefert sie).
- [ ] **Step 5: Commit** — „Jedes Set kann Helm und Umhang beim Anlegen zeigen, verstecken oder unangetastet lassen: zwei Untermenüs im Rechtsklickmenü der Zeile, der Zeilen-Tooltip nennt den gewählten Zustand"

---

### Task 4: Sprachschlüssel

**Files:**
- Modify: `Locales/enUS.lua` + die 9 Übersetzungsdateien über die locale-translate-Pipeline

**Interfaces:**
- Consumes: Schlüssel aus Task 3: `Helm`, `Cloak`, `Show`, `Hide`, `Don't change`, `shown`, `hidden`.
- Produces: vollständige Einträge in allen 10 Sprachdateien.

- [ ] **Step 1:** locale-translate-Skill mit genau diesen 7 Schlüsseln laufen lassen (Skill kennt die Pipeline samt Validierungs-Merge). Vorher gegen `Locales/enUS.lua` abgleichen, ob einer schon existiert — dann NICHT doppeln.
- [ ] **Step 2: Prüfen** — Run: `node tools/check.js` — Expected: kein fehlender/toter Schlüssel aus dieser Liste.
- [ ] **Step 3: Commit** — „Sieben neue Sprachzeilen für den Helm-Umhang-Schalter und den Tooltip, übersetzt in alle neun Sprachen"

---

### Abschluss

- [ ] `graphify update .`
- [ ] adversarial-review-Skill über die Änderungen laufen lassen (Zieh-Logik + Menü sind die heiklen Stellen: Index-Rechnung beim Entfernen der gezogenen Zeile, Ziehen bei ausgeklappter Item-Zeile, `checked`-Semantik bei `nil`).
- [ ] Spielprüfung durch den Nutzer: Umsortieren (auch mit ausgeklappter Zeile, Abbruch außerhalb), Reload-Beständigkeit, Set mit Helm=Verstecken anlegen, unverändertes Verhalten alter Sets.
