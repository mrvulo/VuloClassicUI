# Trackbars Broker-Plugin-Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein neuer Trackbars-Blocktyp „broker" zeigt ein beliebiges LibDataBroker-1.1-Datenobjekt als nativen Block (Symbol, Text, Klick, Tooltip), mit Farbcodes-Entfernen und Maximalbreite als Passform-Regler.

**Architecture:** LibDataBroker-1.1 wird als vierte Bibliothek in `Libs/` eingebettet (LibStub + CallbackHandler-1.0 liegen dort schon und stehen im TOC davor). Der Block ist eine eigene Fabrik im vorhandenen `addType`-Muster von `Modules/TrackbarsBlocks.lua` — Aktualisierung rein über die Attribut-Callbacks der Bibliothek, kein Herzschlag. Die Einstellungs-Widgets folgen dem `addTypeBlockItems`-Muster in `Modules/TrackbarsOptions.lua`.

**Tech Stack:** WoW-Classic-Addon-Lua (Anniversary 2.5.x-Klasse), LibStub, CallbackHandler-1.0, LibDataBroker-1.1; Prüfwerkzeuge `node tools/check.js` und `node tools/optcheck.cjs`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-31-trackbars-broker-block-design.md`.
- KEINE Fremd-Addon-Namen in Code, Kommentaren, Beschriftungen oder Commits (Prüfliste = `FORBIDDEN`-Regex in `tools/check.js`; Bibliotheksdateien unter `Libs/` sind davon ausgenommen wie die vorhandenen).
- Locale-Schlüssel SIND die englischen Texte; `L[...]` nie auf Dateiebene auswerten (alle neuen `L[]`-Stellen liegen in Funktionen).
- Beide TOC-Dateien führen dieselbe Dateiliste (check.js vergleicht sie).
- Nach jeder Aufgabe: `node tools/check.js` muss `RESULT: OK` melden.
- Commit-Botschaften: deutsch, keine Abkürzungen, kein Co-Authored-By.

---

### Task 1: LibDataBroker-1.1 einbetten

**Files:**
- Create: `Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua`
- Modify: `VuloClassicUI.toc:13` (nach der CallbackHandler-Zeile)
- Modify: `VuloClassicUI_Vanilla.toc` (dieselbe Stelle — Zeile per Suche nach `CallbackHandler` finden)

**Interfaces:**
- Consumes: `LibStub`, `CallbackHandler-1.0` (beide schon in `Libs/`, TOC-Zeilen 12–13).
- Produces: `LibStub:GetLibrary("LibDataBroker-1.1", true)` mit `:NewDataObject(name, dataobj)`, `:DataObjectIterator()`, `:GetDataObjectByName(name)`, `.RegisterCallback(self, event, fn)`, `.UnregisterAllCallbacks(self)` und den Ereignissen `LibDataBroker_DataObjectCreated` sowie `LibDataBroker_AttributeChanged_<name>`.

- [ ] **Step 1: Bibliotheksdatei schreiben** — Original-Wortlaut (gemeinfrei, Minor 4), UNVERÄNDERT übernehmen:

```lua
assert(LibStub, "LibDataBroker-1.1 requires LibStub")
assert(LibStub:GetLibrary("CallbackHandler-1.0", true), "LibDataBroker-1.1 requires CallbackHandler-1.0")

local lib, oldminor = LibStub:NewLibrary("LibDataBroker-1.1", 4)
if not lib then return end
oldminor = oldminor or 0


lib.callbacks = lib.callbacks or LibStub:GetLibrary("CallbackHandler-1.0"):New(lib)
lib.attributestorage, lib.namestorage, lib.proxystorage = lib.attributestorage or {}, lib.namestorage or {}, lib.proxystorage or {}
local attributestorage, namestorage, callbacks = lib.attributestorage, lib.namestorage, lib.callbacks

if oldminor < 2 then
	lib.domt = {
		__metatable = "access denied",
		__index = function(self, key) return attributestorage[self] and attributestorage[self][key] end,
	}
end

if oldminor < 3 then
	lib.domt.__newindex = function(self, key, value)
		if not attributestorage[self] then attributestorage[self] = {} end
		if attributestorage[self][key] == value then return end
		attributestorage[self][key] = value
		local name = namestorage[self]
		if not name then return end
		callbacks:Fire("LibDataBroker_AttributeChanged", name, key, value, self)
		callbacks:Fire("LibDataBroker_AttributeChanged_"..name, name, key, value, self)
		callbacks:Fire("LibDataBroker_AttributeChanged_"..name.."_"..key, name, key, value, self)
		callbacks:Fire("LibDataBroker_AttributeChanged__"..key, name, key, value, self)
	end
end

if oldminor < 2 then
	function lib:NewDataObject(name, dataobj)
		if self.proxystorage[name] then return end

		if dataobj then
			assert(type(dataobj) == "table", "Invalid dataobj, must be nil or a table")
			self.attributestorage[dataobj] = {}
			for i,v in pairs(dataobj) do
				self.attributestorage[dataobj][i] = v
				dataobj[i] = nil
			end
		end
		dataobj = setmetatable(dataobj or {}, self.domt)
		self.proxystorage[name], self.namestorage[dataobj] = dataobj, name
		self.callbacks:Fire("LibDataBroker_DataObjectCreated", name, dataobj)
		return dataobj
	end
end

if oldminor < 1 then
	function lib:DataObjectIterator()
		return pairs(self.proxystorage)
	end

	function lib:GetDataObjectByName(dataobjectname)
		return self.proxystorage[dataobjectname]
	end

	function lib:GetNameByDataObject(dataobject)
		return self.namestorage[dataobject]
	end
end

if oldminor < 4 then
	local next = pairs(attributestorage)
	function lib:pairs(dataobject_or_name)
		local t = type(dataobject_or_name)
		assert(t == "string" or t == "table", "Usage: ldb:pairs('dataobjectname') or ldb:pairs(dataobject)")

		local dataobj = self.proxystorage[dataobject_or_name] or dataobject_or_name
		assert(attributestorage[dataobj], "Data object not found")

		return next, attributestorage[dataobj], nil
	end

	local ipairs_iter = ipairs(attributestorage)
	function lib:ipairs(dataobject_or_name)
		local t = type(dataobject_or_name)
		assert(t == "string" or t == "table", "Usage: ldb:ipairs('dataobjectname') or ldb:ipairs(dataobject)")

		local dataobj = self.proxystorage[dataobject_or_name] or dataobject_or_name
		assert(attributestorage[dataobj], "Data object not found")

		return ipairs_iter, attributestorage[dataobj], 0
	end
end
```

- [ ] **Step 2: Beide TOCs ergänzen** — in `VuloClassicUI.toc` UND `VuloClassicUI_Vanilla.toc` direkt nach der Zeile `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua` einfügen:

```
Libs\LibDataBroker-1.1\LibDataBroker-1.1.lua
```

- [ ] **Step 3: Prüfen** — `node tools/check.js` → `RESULT: OK` (Syntaxprüfung der neuen Datei, TOC-Listen beider Flavours deckungsgleich).

### Task 2: Block-Fabrik „broker" in TrackbarsBlocks.lua

**Files:**
- Modify: `Modules/TrackbarsBlocks.lua` (ans Dateiende, NACH dem `addType("micromenu", …)`-Block ab Zeile 509)

**Interfaces:**
- Consumes: die Datei-Locals `instKey(prefix, b, bar)`, `blockColor(b)`, `textBlockFontSize(bar, def)`; `mod.RequestLayout(barId)`; `UI.FontFor("trackbars", fs, size)`; `addType(key, labelKey, defaults, factory)`; die Bibliothek aus Task 1.
- Produces: Blocktyp-Schlüssel `"broker"` mit `BLOCK_DEFAULTS.broker = { plugin = "", stripColors = false, maxWidth = 0 }`; Instanz-Vertrag `Refresh/GetAutoLength/Restyle/Enable/Disable` wie jeder Block. Task 3 liest `b.settings.plugin/stripColors/maxWidth` unter genau diesen Namen.

- [ ] **Step 1: Fabrik anhängen** (ein Block, ans Dateiende):

```lua
-- Broker-Plugin: zeigt ein Datenobjekt, das ein anderes Addon ueber die
-- eingebettete Broker-Bibliothek registriert hat. Aktualisierung rein ueber
-- deren Attribut-Callbacks -- die Bibliothek feuert bei JEDER Aenderung,
-- ein Herzschlag wuerde nur dasselbe noch einmal malen. Jeder Griff in
-- Plugin-Code laeuft durch pcall: ein kaputtes Fremd-Plugin darf die
-- Leiste nicht mitreissen.
addType("broker", "Broker plugin", { plugin = "", stripColors = false, maxWidth = 0 },
function(b, slot, content, bar)
    local inst = { _key = instKey("broker", b, bar) }
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local fs = content:CreateFontString(nil, "OVERLAY")
    UI.FontFor("trackbars", fs, textBlockFontSize(bar, {}))
    fs:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    fs:SetWordWrap(false)
    local icon = content:CreateTexture(nil, "ARTWORK")
    local isz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
    icon:SetSize(isz, isz)
    icon:SetPoint("RIGHT", fs, "LEFT", -4, 0)
    icon:Hide()
    inst.fs, inst.icon = fs, icon

    local function obj()
        local name = b.settings.plugin
        if not ldb or not name or name == "" then return nil, name end
        return ldb:GetDataObjectByName(name), name
    end

    function inst:Restyle()
        UI.FontFor("trackbars", fs, textBlockFontSize(bar, {}))
        local sz = math.floor((bar.thickness or 26) * 0.62 + 0.5)
        icon:SetSize(sz, sz)
    end

    local lastLen = -1
    function inst:Refresh()
        local o, name = obj()
        local r, g, bl = blockColor(b)
        fs:SetTextColor(r, g, bl)
        local txt
        if o then
            txt = o.text or o.label or name or ""
            if b.settings.stripColors then
                txt = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            end
            if o.icon then
                icon:SetTexture(o.icon)
                local c = o.iconCoords
                if type(c) == "table" and c[4] then
                    icon:SetTexCoord(c[1], c[2], c[3], c[4])
                else
                    icon:SetTexCoord(0, 1, 0, 1)
                end
                icon:Show()
            else
                icon:Hide()
            end
        else
            -- konfiguriert, aber (noch) nicht registriert: Name ausgegraut,
            -- der DataObjectCreated-Callback unten holt den Block dann ab
            txt = "|cff888888" .. ((name and name ~= "" and name) or L["Broker plugin"]) .. "|r"
            icon:Hide()
        end
        fs:SetWidth(0)
        fs:SetText(txt or "")
        local mw = b.settings.maxWidth or 0
        local natural = fs:GetStringWidth() or 0
        if mw > 0 and natural > mw then fs:SetWidth(mw) end
        local len = self:GetAutoLength()
        content:SetSize(math.max(len, 1), bar.thickness or 26)
        if len ~= lastLen then lastLen = len; mod.RequestLayout(bar.id) end
    end

    function inst:GetAutoLength()
        local w = fs:GetStringWidth() or 0
        local mw = b.settings.maxWidth or 0
        if mw > 0 and w > mw then w = mw end
        if w <= 0 then return 0 end
        if icon:IsShown() then w = w + (icon:GetWidth() or 0) + 4 end
        return math.ceil(w)
    end

    function inst:Enable()
        if ldb then
            local name = b.settings.plugin
            if name and name ~= "" then
                ldb.RegisterCallback(inst, "LibDataBroker_AttributeChanged_" .. name,
                    function() inst:Refresh() end)
            end
            ldb.RegisterCallback(inst, "LibDataBroker_DataObjectCreated",
                function() inst:Refresh() end)
        end
        slot:EnableMouse(true)
        slot:SetScript("OnMouseUp", function(s, btn)
            local o = obj()
            if o and type(o.OnClick) == "function" then pcall(o.OnClick, s, btn) end
        end)
        slot:SetScript("OnEnter", function(s)
            local o, name = obj()
            if o and type(o.OnTooltipShow) == "function" then
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                pcall(o.OnTooltipShow, GameTooltip)
                GameTooltip:Show()
            elseif o and type(o.OnEnter) == "function" then
                pcall(o.OnEnter, s)
            elseif name and name ~= "" then
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                GameTooltip:SetText(name)
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function(s)
            local o = obj()
            if o and type(o.OnLeave) == "function" then pcall(o.OnLeave, s) end
            GameTooltip:Hide()
        end)
    end

    function inst:Disable()
        if ldb then ldb.UnregisterAllCallbacks(inst) end
        slot:EnableMouse(false)
    end

    return inst
end)
```

Hinweise für den Umsetzer: `textBlockFontSize(bar, {})` nutzt den Standard-`fontScale` 0,5 wie die Textblöcke. `L` ist in der Datei bereits als `ns.L` gebunden. `fs:SetWidth(0)` stellt vor JEDER Messung die natürliche Breite her, sonst misst `GetStringWidth` nach einem früheren Kappen falsch weiter.

- [ ] **Step 2: Prüfen** — `node tools/check.js` → `RESULT: OK`. Erwartung außerdem: Abschnitt „locale keys nothing reaches" nennt jetzt zusätzlich die noch unübersetzten neuen Beschriftungen NICHT (sie sind ja im Code referenziert), aber „locale coverage (deDE)" MELDET die neuen `L[]`-Schlüssel als fehlend — das ist der erwartete Rot-Zustand bis Task 4. Wenn check.js deshalb nicht OK meldet, ist das hier akzeptiert und in Task 4 zu heilen (die Reihenfolge der Aufgaben nicht tauschen: erst Code, dann Schlüssel, sonst meldet 3c die Schlüssel als tot).

### Task 3: Einstellungs-Widgets in TrackbarsOptions.lua

**Files:**
- Modify: `Modules/TrackbarsOptions.lua` — in `addTypeBlockItems` (beginnt Zeile 110), neuer `elseif`-Zweig VOR dem `elseif t == "spacer"`-Zweig (Zeile 162)

**Interfaces:**
- Consumes: `s` = `b.settings` (Local der Funktion), `br.ApplyBar(cfg.id)`, `L[]`; Bibliothek aus Task 1; Feldnamen `plugin/stripColors/maxWidth` aus Task 2.
- Produces: nichts Neues für andere Aufgaben.

- [ ] **Step 1: Zweig einfügen:**

```lua
    elseif t == "broker" then
        local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
        local values = {}
        if ldb then
            for name in ldb:DataObjectIterator() do
                values[#values + 1] = { value = name, text = name }
            end
            table.sort(values, function(a, b2) return a.value < b2.value end)
        end
        local cur = s.plugin or ""
        if cur ~= "" and not (ldb and ldb:GetDataObjectByName(cur)) then
            -- konfiguriert, aber gerade nicht registriert: waehlbar lassen,
            -- damit die Auswahl ein /reload ohne das Plugin ueberlebt
            table.insert(values, 1, { value = cur,
                text = "|cff888888" .. cur .. " (" .. L["not loaded"] .. ")|r" })
        end
        if #values == 0 then
            values[1] = { value = "",
                text = "|cff888888" .. L["No broker plugins found"] .. "|r" }
        end
        items[#items + 1] = {
            type = "dropdown", label = L["Plugin"], width = 240,
            values = values,
            get = function() return s.plugin or "" end,
            set = function(_, v)
                if v ~= "" then s.plugin = v; br.ApplyBar(cfg.id) end
            end,
        }
        items[#items + 1] = {
            type = "toggle", label = L["Strip colors"],
            tooltip = L["Removes the plugin's own color codes so the text takes the block color."],
            get = function() return s.stripColors end,
            set = function(_, v) s.stripColors = v; br.ApplyBar(cfg.id) end,
        }
        items[#items + 1] = {
            type = "slider", label = L["Max width"], min = 0, max = 400, step = 10,
            tooltip = L["0 = automatic width. Above 0 the text is cut off at this width."],
            get = function() return s.maxWidth or 0 end,
            set = function(_, v) s.maxWidth = v; br.ApplyBar(cfg.id) end,
        }
```

- [ ] **Step 2: Prüfen** — `node tools/check.js` (deDE-Deckung weiter rot bis Task 4, sonst OK) und `node tools/optcheck.cjs --selftest && node tools/optcheck.cjs` → beide `RESULT: OK`.

### Task 4: Sprachschlüssel ×9

**Files:**
- Modify: `Locales/deDE.lua` … `Locales/zhTW.lua` (alle neun; `Locales/enUS.lua` ist ein Stub und bleibt unberührt)
- Create: `<scratchpad>/merge_broker_l10n.cjs` (Wegwerf-Skript, wird nicht committet)

**Interfaces:**
- Consumes: die in Task 2/3 referenzierten Schlüssel: `Broker plugin`, `Plugin`, `No broker plugins found`, `Strip colors`, `Max width`, `Removes the plugin's own color codes so the text takes the block color.`, `0 = automatic width. Above 0 the text is cut off at this width.` — `not loaded` existiert schon übersetzt und wird NICHT neu angelegt.
- Produces: vollständige deDE-Deckung, check.js wieder grün.

- [ ] **Step 1: Bestand prüfen (lebend UND tot)** — je Schlüssel über alle neun Dateien; ein bereits vorhandener (auch als „toter" gelisteter) Schlüssel wird WIEDERVERWENDET, nicht neu übersetzt (Lehre v1.58.3):

```bash
cd <repo> && for k in "Broker plugin" "Plugin" "No broker plugins found" "Strip colors" "Max width"; do echo "== $k"; grep -Fl "[\"$k\"]" Locales/*.lua | wc -l; done
```

- [ ] **Step 2: Merge-Skript schreiben und laufen lassen** — Muster ist `merge_notes_1_58_3.cjs` aus dem Scratchpad dieser Sitzung bzw. der changelog-Skill: schlüssel-verankerte Tabelle `{ [englischer Schlüssel] = { deDE = …, … } }`, Validierungen (Schlüssel darf noch nicht existieren, Zeilenbilanz = vorher + n, keine ASCII-Anführungszeichen in deDE-Werten, `luaparse`-Parse-Probe, LF-Ausgabe), Einfügepunkt `lastIndexOf('\n} end')`. Aufruf aus `tools/` mit `NODE_PATH="$(pwd)/node_modules"`. Übersetzungs-Stilanker: vorhandene Werte für „Text size", „0 = uses the general text size.", „not loaded" je Sprache nachschlagen und den Ton übernehmen (deDE du-Form, „deutsche Anführungszeichen").

- [ ] **Step 3: Prüfen** — `node tools/check.js` → `RESULT: OK` einschließlich „locale coverage (deDE)" und „locale keys nothing reaches" ohne NEUE Einträge.

### Task 5: Endprüfung und thematischer Commit

**Files:**
- Modify: keine neuen — Gesamtstand aus Task 1–4.

**Interfaces:**
- Consumes: alles oben.
- Produces: EIN Feature-Commit auf master (der Nutzer ruft danach erfahrungsgemäß nur noch „release").

- [ ] **Step 1: Alle Prüfer** — `node tools/check.js` und `node tools/optcheck.cjs --selftest && node tools/optcheck.cjs` → `RESULT: OK`; `graphify update .`.

- [ ] **Step 2: Status-Gegenprobe** — `git status --short` darf NUR zeigen: `Libs/LibDataBroker-1.1/` (neu), beide TOCs, `Modules/TrackbarsBlocks.lua`, `Modules/TrackbarsOptions.lua`, neun `Locales/*.lua`, Spec- und Plan-Datei (falls noch uncommittet).

- [ ] **Step 3: Commit** — Botschaft per Write-Werkzeug in den Scratchpad, dann `git commit -F <Pfad mit Vorwärtsschrägstrichen>`:

```
Trackbars: neuer Block "Broker-Plugin" -- zeigt Datenobjekte fremder Addons als nativen Block mit Symbol, Text, Klick und Tooltip; Farbcodes-Entfernen und Maximalbreite als Passform-Regler; Plugin-Klappmenue mit Hinweis, wenn nichts registriert ist; die Broker-Bibliothek ist eingebettet und aktualisiert den Block ueber ihre Attribut-Callbacks statt ueber einen Herzschlag
```

- [ ] **Step 4: Spielprüfliste an den Nutzer geben** (aus der Spec): Block ohne Plugin-Addon anlegen (Hinweiszeile im Klappmenü), mit Broker-Addon Plugin wählen (Text/Symbol erscheinen und aktualisieren sich ohne /reload), Klick + Tooltip, stripColors an/aus, maxWidth kappt, Leiste aus/an, /reload mit fehlendem Plugin → ausgegrauter Name ohne Fehler. `/reload` genügt (keine Texturen).
