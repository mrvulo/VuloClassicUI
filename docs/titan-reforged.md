# Titan Reforged (China) — Stand, Messungen, offene Punkte

Register für alles, was diesen Client betrifft. **Verhalten steht in
`Core/Wrath.lua`, Geschichte steht hier.** Bei jeder neuen Runde unten anhängen,
mit Datum.

## Was Titan Reforged ist

Offiziell von Blizzard und NetEase, exklusiv China, kein privater Server.
Angekündigt 17.07.2025, gestartet 18.11.2025. Vanilla, The Burning Crusade und
Wrath zu einem Pfad bis Stufe 80 verschmolzen: neu entworfene Schlachtzüge,
überarbeitete Klassensets, aufwertbare legendäre Waffen, ein kontoweiter
Machtpfad neben der Charakterstufe, elf von den Spielern gemeinsam
freigeschaltete Phasen. **Regelwerk und Talentbäume sind Wrath 3.4.3.**

Nicht mit dem gleichnamigen Addon verwechseln. Der Name ist erlaubt: Titan
Reforged ist eine Blizzard-Spielversion, kein fremdes Addon, und steht nicht auf
der Verbotsliste in `tools/check.js`.

## Die technischen Zahlen — gemessen, nicht angenommen

| | |
|---|---|
| Interface | **38002** (vorher 38001), beide in unserer TOC-Liste |
| Client-Version | 3.80.0 / 3.80.1 / 3.80.2 |
| `WOW_PROJECT_ID` | **11** = `WOW_PROJECT_WRATH_CLASSIC` |
| `select(4, GetBuildInfo())` | **38002** |

Bestätigt am 30.07.2026 durch eine `/dump`-Zeile des Melders:

```
WOW_PROJECT_ID = 11        select(4, GetBuildInfo()) = 38002
VuloClassicUI.isBCC = false   VuloClassicUI.isEra = false
```

**Eine TOC reicht.** Die Dateiendung entscheidet nur, welche Datei geladen wird;
die Interface-Liste nur, ob der Client sie veraltet nennt. Eine `_Wrath.toc` war
nie nötig — der BigWigs-Packer liest die Komma-Liste und bietet die Variante an.

**Erkennung:** `Core/Namespace.lua` entscheidet zuerst über die Kennung, danach
über die Build-Nummer (11xxx Era, 2xxxx BCC, 3xxxx Wrath **inkl. Titan**, 4xxxx
Cata). Eine Zahlenspanne ist variantenfest, eine Konstantenliste nicht: vorher
ließ eine unbekannte Kennung ALLE Flaggen falsch, was schlechter ist als gar
keine Kennung.

## Was hier nicht hingehört

Die meisten Fehler aus den Titan-Berichten waren keine Titan-Fehler. Titan war
der Bote:

- der Verzauberungs-Filter kannte nur englische und deutsche Präfixe — kaputt für
  jeden chinesischen, koreanischen und russischen Spieler;
- das Klappmenü, das nicht ans Ende scrollte — alle 114 Klappmenüs, jeder Client
  mit niedrigem Bildschirm;
- der Einstellungs-Tod an einer nicht-endlichen Zahl — jedes Profil.

Solche Fixe stehen bei ihrem Feature und gelten überall. Sie hier oder in
`Core/Wrath.lua` abzulegen würde dem nächsten Leser verbergen, dass sie
allgemein sind.

## Die Fähigkeiten in `Core/Wrath.lua`

Acht Verzweigungen im ganzen Addon fragen nach dieser Client-Generation. Sie
fragen alle über `ns.Wrath.*`, damit die Antwort an einer Stelle steht:

| Fähigkeit | Wahr auf | Wer fragt |
|---|---|---|
| `hasRatings` | BCC + Wrath | `Modules/CharacterPanel.lua` |
| `hasWideQuestLog` | Wrath + Cata | `Modules/General.lua` (2×) |
| `hasDeathKnight` | Wrath | `Modules/GlobalSettings.lua` |
| `hasRunicPower` | Wrath | `Modules/GlobalSettings.lua` |
| `hasMovableLoot` | Wrath | `Modules/UnlockMode.lua` |
| `hasTotemicRecall` | Wrath | `Modules/Classes/Shaman.lua` |
| `hasTalentTrees` | Wrath | `Modules/TalentView.lua` |
| `hasReshapedProfessionFrames` | Wrath | `Modules/General.lua` (Berufsfenster-Kapsel) |
| `hasFixedColumnSocialTabs` | Wrath | `Modules/FriendList.lua` |

Ein Feature, das es **nur** dort gibt, bekommt weiterhin eine eigene Datei mit
einem Modultor am Kopf — `Modules/TalentView.lua` ist das Muster.

## Chronik

### 30.07.2026 — Diagnose und erste Fixe (`870dd58`)

Ein Melder zeigte per Bild ein **leeres Charakterfenster**. Ursache gefunden und
belegt: `Modules/CharacterPanel.lua` hatte eine Positivliste
(`if not (ns.isBCC or ns.isEra) then return end`). Auf Wrath sind beide falsch,
das ganze Modul stieg aus.

Umgesetzt:

1. Das Modultor fragt jetzt nach `PaperDollItemSlotButton_Update`, der einzigen
   harten Abhängigkeit, statt nach einer Namensliste.
2. `Core/Namespace.lua` — Kennung zuerst, dann Build-Nummer als Rückfall.
3. Drei Wertungszeilen: `ns.isBCC` → `hasRatings`. Hier bleibt eine Namensliste
   **mit Absicht** — die Frage ist, ob das SPIEL die Wertung hat, nicht ob der
   Client die Funktion kennt.
4. `38001, 38002` in die Interface-Liste beider TOCs.

### 31.07.2026 — Bericht zu Client 3.80.2, vier Fixe

1. **Questlog-Knöpfe verschoben** bei „Größeres Questlog": unsere Vergrößerung
   ist auf die einspaltige Anatomie geeicht, Wrath hat nativ das breite
   Zweispalten-Log. Die Vergrößerung steigt aus, die Optionszeile wird gar nicht
   angeboten.
2. **Cooldown-Manager, gleichnamige Zauber fremder Klassen** (zhCN 复生 /
   自然迅捷): Klassentor vor dem Namensabgleich, Adoption per Zauber-ID.
   Restlücke bewusst: klassenlose Alteinträge mit ungelernter Rang-ID adoptiert
   niemand mehr per Name, sonst käme der Fehler zurück. Der Melder musste zwei
   falsch gestempelte Einträge einmal von Hand löschen.
3. **Klappmenü scrollte nicht ans Ende** bei 100+ Texturen: Fensterhöhe kam von
   der Bildschirmhöhe, öffnete aber immer nach unten. Jetzt wird der Platz unter
   dem Knopf gemessen und bei mehr Platz nach oben geöffnet. Betrifft alle 114
   Klappmenüs, auf jedem Client.
4. **Shift-Klick-Link zeigte den Questnamen der Gegenstandsstufe**: der
   zhCN-Client verarbeitet Linktexte gegen eigene Daten nach. Stufe steht jetzt
   außerhalb des Links, dazu eine Doppellauf-Sicherung.

### 01.08.2026 — der große Bericht ④–⑨ plus Persistenz

- **Persistenz (der kritische):** die SavedVariables-Datei starb an einer
  nicht-endlichen Zahl (nan/inf → Datei lädt nicht → Client legt `.bak` an →
  Werkszustand kontoweit). `ns:ScrubSavedVariables()` beim Abmelden entfernt
  solche Werte und Schlüssel; der Zähler landet in `global.scrubbedNonFinite`
  und wird beim nächsten Anmelden gemeldet.
  **Offen: existiert beim Melder eine `VuloClassicUI.lua.bak`?** Das bestätigt
  die Diagnose. Fehlende `.bak` plus unverändertes Dateidatum würde stattdessen
  heißen, dass der Client gar nicht schreibt.
- **④** Cooldown-Manager: Eintragsliste als Zahnrad-Zeilen, Eintrag parken,
  „Nur eigene" je Eintrag.
- **⑤** Charakterfenster: der zhCN-Kernfehler war der Grüne-Zeilen-Filter mit
  nur EN/DE-Präfixen — auf zhCN verdrängte die Sockelbonus-Zeile die echte
  Verzauberung. Jetzt lokalisierungsfest über Client-Globals, dazu UTF-8-sichere
  Kürzung (CJK zählt zwei Einheiten).
- **⑥** Totem-Rückruf: eigener sichtbarer Knopf, nur auf dieser Generation.
- **⑦** Neu `Modules/TalentView.lua`: drei Bäume nebeneinander, Ränge live,
  Klick lernt, ersetzt Blizzards Fenster. Bricht bei unplausiblen Shim-Formen ab
  und lässt Blizzards Oberfläche in Ruhe.
- **⑧** Freundesliste: Breitenregler.
- **⑨** Beutefenster verschiebbar (`direct`-Pfad in `Modules/UnlockMode.lua`).

### 01.08.2026, zweite Runde — Talentfenster-Nachbericht (`f53f89f`)

Der Melder bestätigt, dass das Talentfenster normal öffnet. Zwei Restfehler
behoben:

1. **Tooltip zeigte nur „TalentID: n"**: der 3.80.x-Shim beantwortet
   `GameTooltip:SetTalent(tab, index)` OHNE Fehler mit einem Platzhalter — der
   `pcall`-Erfolg war also kein Beweis. Jetzt wird die erste Tooltipzeile
   validiert, danach `GetTalentLink`, zuletzt ein selbst gebauter Tooltip.
2. **Taste schloss das Fenster nicht**: Blizzards Umschalter sieht nur sein
   eigenes, von uns verstecktes Fenster, also ist jeder Druck ein Öffnen. Der
   Hook behandelt „unser Fenster ist schon offen" jetzt als zweite Hälfte des
   Umschaltens.

### 02.08.2026 — dieses Register und `Core/Wrath.lua`

Die acht Variantenverzweigungen fragen jetzt über `ns.Wrath.*` statt die
Flaggen direkt. Verhalten unverändert; die Datei ist der eine Ort, an dem
Neues zu dieser Client-Generation dazukommt.

### 02.08.2026, zweite Runde — Bitte ① des Melders: Talentgruppen-Knöpfe

Der Melder wünscht sich am Talentfenster die Knöpfe, die Blizzards Fenster rechts
außen trägt: einen je **gekaufter** Talentwahl, mit Rechtsklick zum Umschalten.
Kein Fehler, sondern eine Angleichung an die gewohnte Bedienung — gebaut.

Was dafür an einer Stelle zusammengezogen wurde (`Core/TalentOverrides.lua`):

| Neu | Zweck |
|---|---|
| `ns:NumTalentGroups()` | wie viele Talentwahlen der Charakter besitzt; `Modules/Loadouts.lua` hatte dieselben zwei Quellen als eigene Kopie und fragt jetzt hier |
| `ns:ActivateTalentGroup(g)` | der Wechsel; gibt `false` plus Grund zurück (`combat`, `already`, `unsupported`, `failed`), damit ein Klick nie stumm verpufft |
| `ns:TalentGroupIcon(g)` | das Symbol des Baums mit den meisten Punkten — dasselbe, was Blizzards Knopf zeigt. `ns:DominantTalentTree` liefert es jetzt als dritten Rückgabewert |

Aus der Quelle belegt, nicht angenommen:

- `C_SpecializationInfo.SetActiveSpecGroup(groupIndex)` ist der echte Aufruf und
  steht in `SpecializationInfoDocumentation.lua`. Die Altglobale
  `SetActiveTalentGroup` steht **nur** in `Deprecated_Specialization_Cata.lua`
  und `_Mists.lua` — in der Wrath-Datei fehlt sie. Sie ist also Zugabe, nie der
  Plan.
- `GetTalentInfo` nimmt die Talentwahl als fünftes Argument, im Original wie im
  Shim (dort als `talentInfoQuery.groupIndex`). Deshalb ist die Vorschau auf die
  andere Wahl überhaupt möglich.

Drei Fallen, die dabei bewusst zugemacht wurden:

1. **`LearnTalent` kennt keine Talentwahl** — es gibt immer in die AKTIVE aus.
   Ein Klick in der Vorschau würde also im falschen Aufbau lernen. Er tut daher
   gar nichts, und der Hinweis steht vorher im Tooltip.
2. **Der zweiargumentige Aufruf bleibt unangetastet.** Genau den hat der Melder
   am 01.08. als funktionierend bestätigt; das fünfte Argument geht nur raus,
   wenn wirklich die andere Wahl auf dem Schirm ist. Wird es je abgelehnt,
   leidet nur die Vorschau.
3. **`UnitCharacterPoints` antwortet nur für die aktive Wahl.** In der Vorschau
   stünde dort also eine fremde Zahl — die Kopfzeile nennt stattdessen die
   gezeigte Talentwahl.

Der Streifen hängt außerhalb des Fensters und misst wie die Klappmenüs den Platz:
reicht er rechts nicht, klappt er nach links.

### 02.08.2026, dritte Runde — Bitte ② des Melders: Berufsfenster tritt zurück

Bild vom Melder: das Berufsfenster vergrößert, schwarze Löcher dort, wo unsere
versteckten Regionen saßen, die Titelleiste gedehnt, die Klappmenüs über der
Rezeptliste. **Kein Lua-Fehler** — es wirft nichts, es landet nur auf den
falschen Widgets.

Ursache ist die Bauart des Anstrichs: er spricht Blizzards Widgets über NAMEN
und über **Regionsnummern** an (4, 5, 8, 9, 10), hängt das Suchfeld an
`TradeSkillFrameAvailableFilterCheckButtonText` und setzt die beiden Klappmenüs
auf feste Abstände am vergrößerten Rahmen. Auf dieser Generation steht hinter
diesen Namen und Nummern eine andere Anatomie.

**Entscheidung des Besitzers: kein Nachbauen, sondern zurücktreten.** Die Kapsel
in `Modules/General.lua` steigt jetzt VOR `RegisterModule` aus, wenn
`ns.Wrath.hasReshapedProfessionFrames` wahr ist. Damit gibt es dort keine
Seitenleisten-Zeile, keine Optionsseite, keine gespeicherten Standardwerte und
vor allem keine Hooks — der Client behält sein eigenes Fenster, unvergrößert und
ungefärbt, ohne Favoritensterne, Materialzähler und Bankspalte.

Geprüft, dass ein nicht registriertes Modul nichts mitreißt: `memberBlock` und
`MakeCollectionPage` überspringen ein Mitglied, das sie nicht finden,
`ns:IsModuleEnabled` und `ns:ToggleModule` geben bei unbekanntem Schlüssel
zurück. Die Sammelseite „Windows & Professions" bleibt also mit Questlog und
Entzauber-Warteschlange stehen.

Nicht angefasst: der Reagenzien-Griff der Gegenstands-ID-Anzeige
(`Modules/General.lua`, ~7211). Der färbt nichts, er liest nur einen Link — und
er nimmt bereits den modernen Weg über `TradeSkillFrame.RecipeList`.

Wenn das Fenster dort je doch wieder unseren Anstrich bekommen soll, braucht es
zuerst Tatsachen vom Melder statt Vermutungen: die Kindfenster- und Regionsliste
des echten `TradeSkillFrame` per `/dump`. Ohne die wäre jeder Versuch das
nächste Bild.

### 02.08.2026, vierte Runde — Bitte ③: die Breite folgt der Registerkarte

Bild vom Melder: Freundes-, Wer-, Gilden- und Schlachtzugsliste, jeweils mit
leerer rechter Hälfte. Sein Satz: verbreitert, aber nicht neu ausgerichtet.

Die Ursache ist unsere eigene: `extraWidth` (Bitte ⑧ vom 01.08., von demselben
Melder gewünscht) verbreitert `FriendsFrame`. Die Zeilentexte der FREUNDESliste
sind zweipunkt-verankert und wachsen mit — die Spaltenköpfe und Zeilenfelder der
drei anderen Registerkarten stehen auf festen x-Abständen und bleiben links
stehen. Jeder gewonnene Punkt landet dort in einer leeren Hälfte.

**Gebaut: die Zusatzbreite gehört der Freundesliste allein.** Auf Wer, Gilde und
Schlachtzug wird sie wieder abgezogen, also gelten dort Blizzards eigene
Proportionen — die, für die seine Spalten ausgemessen wurden. Ein Haken an
`PanelTemplates_SetTab` und am `OnShow` lässt die Breite der Registerkarte
folgen; er hängt bewusst NICHT am Fensteranstrich, damit er auch für jemanden
greift, der nur den Regler benutzt.

Belegt, nicht angenommen: dass die Breite den Registerwechsel überhaupt
übersteht. Auf dem Bild des Melders stehen Wer und Gilde in UNSERER Breite —
Blizzard setzt das Fenster hier also nicht je Registerkarte neu, und niemand
kämpft mit uns darum.

**Nicht gebaut: die Spalten über eine breitere Fläche verteilen.** Das hieße,
Blizzards Spaltenköpfe beim Namen zu nennen, und diese Namen stehen in keiner
Quelle, die wir haben: die entpackte Clientquelle enthält nur `Interface/AddOns`
ohne das FrameXML mit Freundes- und Gildenfenster, der eigene Client des
Besitzers ist TBC-Anniversary (20505/20506) und kennt das Wrath-Gildenfenster
nicht, und kein installiertes Fremdaddon nennt sie. Geraten wäre es das nächste
Bild — dieselbe Regel wie beim Berufsfenster eine Runde davor.

**Stattdessen eine Sonde.** `/friendstate` (versteckt) druckt jetzt zusätzlich
Fensterbreite, gewählte Registerkarte und die sichtbaren benannten Kindfenster
mit x-Abstand und Breite, zwei Ebenen tief, bei 40 Zeilen gedeckelt. Der Melder
öffnet die betroffene Registerkarte, tippt `/friendstate`, schickt den Block —
dann sind die Spalten eine Messung statt einer Vermutung.

### 02.08.2026, fünfte Runde — Bitte ⑤: die Lücken an den runden Balken

Bild vom Melder: „Runde Balken" eingeschaltet, links und rechts am Lebensbalken
je ein toter Streifen — in der Vorschau und auf der Plakette im Spiel.

**Gemessen, nicht vermutet.** `Media/Masks/csquare_mask.tga` ist 128×128, die
runde Form darin liegt aber nur bei x=10..117 und y=10..117: ringsum **10 px
durchsichtiger Rand, 7,8 % je Seite**, Eckenradius 7 px. `applyBarRounding`
spannt diese Maske mit `SetAllPoints` über den Balken, also wird der Rand
mitgedehnt: auf 120×15 sind das rund **11 px toter Balken an jedem Ende** und
knapp 1 px oben und unten. Deshalb fällt es waagerecht auf und senkrecht nicht.

Behoben, indem die Maske um genau die Breite ihres eigenen Randes ÜBER den
Balken hinaushängt — dann landet die Form auf den Kanten statt innerhalb. Nur
Ankerpunkte; ein Haken an `OnSizeChanged` lässt sie den Breiten- und
Höhenreglern folgen. Die geteilte Maskendatei bleibt unangetastet, also behalten
Schieberegler, Abklingsymbole und der dunkle Anstrich ihr Aussehen. Die
Live-Vorschau läuft durch dasselbe `skinPlate` und ist damit mit erledigt.

**Das ist ausdrücklich KEINE Client-Eigenschaft** und steht deshalb nicht in
`Core/Wrath.lua`, sondern mit der Messung an der Fundstelle: der Rand steckt in
der Datei, die Lücke entsteht auf jedem Client, sobald jemand runde Balken
einschaltet. Der Besitzer hat sie am 02.08.2026 trotzdem — mit der Messung auf
dem Tisch — auf diese Client-Generation begrenzt. Die Bedingung steht an genau
einer Stelle (`anchorRoundMask`), das Ausweiten ist eine Zeile.

Nebenwirkung dieser Begrenzung, damit sie beim Prüfen niemanden überrascht: auf
dem TBC-Anniversary-Client des Besitzers zeigt die Optionsvorschau die Lücke
weiterhin. Das ist gewollt, nicht kaputt.

### 02.08.2026, sechste Runde — Bitte ⑥: die Eingabezeile

Zwei Wünsche zum Chat-Eingabefeld: es über das Chatfenster setzen können, und
ihm einen eigenen Hintergrund geben — denn mit ausgeschaltetem dunklen Panel kam
Blizzards Standardrahmen zum Vorschein, und der sieht neben unserem Chat nicht
gut aus. Beides gebaut, beides als Optionszeile.

**Was dafür auseinandergenommen wurde.** `styleEditBox` war ein Einmalgriff:
Chrom verstecken, verankern, Höhe setzen — alles in einem, alles nur beim ersten
Mal. Die Seite ist jetzt eine Option, also musste das Verankern wiederholbar
werden (`anchorEditBox`), während Höhe und Textränder ein Einmalgriff bleiben.

**Drei Dinge hängen um die Eingabezeile herum und mussten gemeinsam kippen:**
die Zeile selbst, das dunkle Panel, das Chat und Eingabe zu einem Block
zusammenfasst, und die Bewegen-Fläche des Edit-Mode, die genau diesen Block
abdecken muss. Sie gehen jetzt alle drei durch `anchorBlock`, damit sie nicht
auseinanderlaufen können. Das äußere Rechteck ist in beide Richtungen dasselbe,
nur gespiegelt.

**Die Reiterleiste brauchte keinen Handgriff — fast.** `positionDock` hängt sie
an die OBERKANTE des Panels, also landet sie von selbst über der Eingabezeile.
Ohne Panel aber lassen wir Blizzards Anordnung in Ruhe, und dort wäre die Zeile
oben genau auf den Reitern gelandet. Deshalb hängt die Leiste in genau diesem
Fall an der Eingabezeile statt am Panel. Der obere Verlauf klebt am
Nachrichtenbereich und bleibt richtig, wo er ist.

**Doppelte Schicht vermieden:** solange das dunkle Panel an ist, deckt es die
Eingabezeile schon ab. Ein zweiter Hintergrund derselben Farbe darüber würde sie
nur doppelt abdunkeln, also zeigt sich der eigene Hintergrund erst, wenn das
Panel aus ist. Der Deckkraft-Regler erfasst ihn mit, sonst hätte er als einziges
Stück in einer anderen Tönung gestanden.

**Wieder KEINE Client-Eigenschaft.** Beide Optionen funktionierten überall. Der
Besitzer hat sie am 02.08.2026 auf diese Client-Generation begrenzt; die beiden
Zeilen werden anderswo gar nicht erst angeboten, und die Standardwerte lesen
sich dort genau wie das Verhalten vor ihnen. Die Bedingung steht an drei
Stellen, alle in `Modules/Chat.lua` und alle mit `ns.Wrath.is` benannt.

### 02.08.2026, siebte Runde — Bitte ⑦: das Charakterfenster

Drei Punkte, und **zwei davon gibt es schon**. Das ist selbst der Befund:

1. **„Gegenstandsstufen-Schrift zu klein."** Der Regler existiert seit
   Langem — „Textgröße → Gegenstandsstufen-Textgröße", 8 bis 24, Standard 11.
   Er greift aber nur, wenn er die Schriftzüge FINDET, und dabei sucht er an
   zwei erhofften Stellen: am Slot-Knopf selbst und unter den Kindfenstern von
   `PaperDollItemsFrame`. Wo der Client seine Paperdoll-Knöpfe woanders
   einhängt, findet er nichts und der Regler tut still gar nichts — von außen
   nicht zu unterscheiden von „die Schrift ist zu klein".
   **Behoben mit einem Register:** jede Anzeige, die wir bauen, trägt sich in
   `mod._displays` ein; Regler und Textumstiler laufen zuerst darüber. Das kann
   nicht danebengreifen, weil es nur enthält, was wir selbst erzeugt haben. Die
   beiden Suchen bleiben stehen — wo sie funktionieren, finden sie dieselben
   Schriftzüge, und dieselbe Größe zweimal zu setzen ändert nichts.
2. **„Wertepanel lässt sich nicht nach rechts."** Gibt es: „Stil →
   Charakterfenster-Stil → Modern". Der Hilfetext sagt es wörtlich — Modern
   „verschiebt alle Werte in ein Panel rechts vom Charakterfenster"
   (`MODERN_RIGHT_EXT = 172`). Nichts zu bauen; der Melder hat die Option nicht
   gefunden.
3. **„Sockel und Verzauberungen nicht gleichzeitig."** Im Code steht kein
   Entweder-oder: `showSockets` und `shortenEnchants` sind zwei unabhängige
   Schalter, und die beiden zeichnen an verschiedene Orte — die Sockel mittig
   unter die Gegenstandsstufe AUF das Symbol
   (`AnchorSocketsBelowCentered`), der Verzauberungstext daneben in den Streifen
   neben dem Slot (`positionLeft`/`positionRight`/`positionCenter`). Warum sich
   die beiden bei ihm ausschließen, ist von hier aus nicht zu sehen. **Offen,
   Rückfrage gestellt** — raten hieße hier, an einer 1800-Zeilen-Datei nach
   Gefühl zu schrauben.

**Zum Client-Tor:** Punkt 1 ist bewusst OHNE Tor gebaut. Wo die alte Suche
funktioniert, findet das Register dieselben Schriftzüge und setzt dieselbe Größe
— auf TBC und Era ändert sich also nachweislich nichts. Ein Tor hätte dort
denselben Anblick erzeugt und nur die kaputte Suche konserviert.

### 02.08.2026, achte Runde — Bitte ⑧: die Knöpfe fremder Addons sammeln

Wunsch: die Minikarten-Knöpfe anderer Addons zusammenfassen, damit die
Oberfläche aufgeräumt bleibt.

**Die halbe Antwort lag schon da** — wie bei ⑦. `Modules/MinimapStyle.lua`
sammelt die Knöpfe längst ein (`collectAddonButtons`, Knopf-Kinder der
Minikarte zwischen 20 und 44 Punkten Breite, Blizzards eigene ausgenommen),
malt sie im Hausstil an (`skinAddonButton`) und fängt Spätregistrierungen über
den Rückruf der Symbolbibliothek, `ADDON_LOADED` und einen Nachlauf drei
Sekunden nach dem Anmelden. Es gab sogar schon „nur bei Mauskontakt". Was
fehlte, war ein ORT: bisher blieben die Knöpfe rund um die Karte liegen und
wurden nur aus- und eingeblendet.

**Gebaut: ein Kasten unter der Karte.** Ein Punkt-Punkt-Punkt-Knopf unten links
am Kartenrand klappt ihn auf und zu; die gesammelten Knöpfe werden umgehängt
und in ein Raster zu vier Spalten gelegt, der Kasten wächst mit ihrer Zahl.
Keine neue Textur: ein neues TGA braucht einen kompletten Client-Neustart, ehe
es zeichnet, und der Ring des Moduls plus drei Punkte tun es genauso.

Vier Dinge, die sonst zurückgekommen wären:

1. **Die Symbolbibliotheken hängen ihre Knöpfe nach eigenem Fahrplan wieder an
   die Karte.** Ein eingesammelter Knopf würde also wieder ausbrechen. Der
   vorhandene Zeitgeber der Datei legt das Raster deshalb alle halbe Sekunde
   neu — ein paar `SetPoint`-Aufrufe, billig genug, und es heilt sich selbst.
2. **Der eigene Knopf darf nicht in seinen eigenen Kasten.** Er trägt
   `_vcuiOwn`, und der Sammler überspringt das.
3. **Ein leerer Kasten liest sich als Fehler.** Ohne gesammelte Knöpfe
   verschwinden Kasten UND Öffner.
4. **Modul aus.** Die Knöpfe werden ZUERST zurückgegeben und dann erst der
   Kasten versteckt — andernfalls nähme ein versteckter Kasten die Symbole
   aller Addons mit vom Bildschirm.

**Optionszeile:** drei Orte sind eine Auswahl, also ein Klappmenü — aber nur
dort, wo es den dritten Ort gibt. Anderswo bleibt die Zeile der Schalter, der
sie immer war. Beide Formen schreiben dieselben zwei gespeicherten Schlüssel,
ein bestehendes Profil mit „nur bei Mauskontakt" liest sich also als dieser
Modus und schuldet keine Wanderung.

## Offene Punkte

- **Cata und der Todesritter.** `hasDeathKnight` und `hasRunicPower` sind
  bewusst nur auf Wrath wahr, weil die beiden Farblisten das vorher so hielten.
  Auf einem Cata-Client wären sie ebenfalls wahr. Verhalten zu ändern ist eine
  eigene Entscheidung; wenn wir je für Cata ausliefern, gehört das geprüft.
- **`.bak`-Frage an den Melder** (siehe Persistenz oben) — bestätigt oder
  widerlegt die Diagnose zum Werkszustand.
- **Beim nächsten Release nachsehen**, ob der Packer die Titan-Variante wirklich
  anbietet (Flavours im Lauf-Log von CurseForge und Wago). Das ist die einzige
  Stelle, die diese Änderung praktisch bestätigen kann.
- **Feature-Wunsch offen:** „Nur eigene Zauber" im Cooldown-Manager je
  Einzelzauber statt global — inzwischen gebaut (④), aber der ursprüngliche
  Anwendungsfall (fremdes Focus Magic auf mir verfolgen) ist im Spiel ungeprüft.
- **`/friendstate`-Block vom Melder** (Wer-, Gilden- und Schlachtzugsregister
  einzeln). Erst damit lassen sich die Spalten über eine breitere Fläche
  verteilen, statt die Zusatzbreite dort nur abzuziehen.
- **Die Zeilenform der Freundesliste** aus seinem „NEED"-Bild — Stufe in der
  Namenszeile, Ort und Reich rechtsbündig auf derselben Zeile — ist ein
  Gestaltungswunsch, kein Fehler, und bewusst nicht mitgebaut worden. Er gilt
  überall, nicht nur hier, und gehört erst entschieden.
- **Zeigt die Vorschau wirklich die andere Talentwahl?** `GetTalentInfo` nimmt
  die Wahl als fünftes Argument, im Original wie im Shim — aber ob der 3.80.x-
  Client sie auch beachtet, kann nur der Melder sehen: Knopf 2 anklicken und
  prüfen, ob die Ränge sich ändern. Tut er es nicht, zeigt die Vorschau still
  die aktive Wahl.
- **Alles aus den Runden 31.07. und 01.08. ist im Spiel ungeprüft.** Wir können
  diesen Client nicht selbst testen: Regionssperre, chinesisches Konto. Jede
  Bestätigung kommt vom Melder.
