// Structural check of the declarative options pages.
//
//   node tools/optcheck.cjs             -- check Modules/ and UI/
//   node tools/optcheck.cjs --selftest  -- prove the checks still fire
//   node tools/optcheck.cjs <file.lua>  -- check one file
//
// WHY THIS IS PARSED AND NOT GREPPED
// All the findings below are about WHERE a table sits, not what a line says.
// A text search cannot see nesting, and the first three of these shipped as
// real bugs before this file existed.
//
// WHAT IT LOOKS FOR
//   1. subOptions on an item inside a group. UI:PlaceGroup calls createWidget
//      directly -- both its row and its columns branch -- and never draws a
//      gear. The setting is then on no page and behind no gear: gone, silently.
//   2. subOptions on a type that gets no card (button, desc, custom, ...).
//      Same silent loss, different cause.
//   3. two gears on one page sharing an expansion key. The key is item.subKey,
//      or the label when there is none, so two rows with the same label open
//      together. This is what item.subKey exists for.
//   4. a segmented row whose values are not a literal list of 2 to 4 entries.
//      Values from a function (VisibilityValues()) would draw a dozen buttons
//      three pixels wide.
//   5. two override-capturable rows (get + set + label, no noOverride) with the
//      same label in the same place on one page -- same section, same gear
//      parent, same subKey or none. ns:AssignOverrideIds (Core/TalentOverrides)
//      can only tell them apart by an ordinal in page order, so moving one row
//      would silently swap their recorded overrides. Give one a subKey.
//      "One page" is approximated by the innermost function the rows are
//      written in (a GetOptions body or a page helper); rows split across two
//      helpers are missed, if/elseif branches are kept apart, and of
//      `c and {A} or {B}` only A is counted. A WARNING, not a failure: it
//      fired on shipped pages when it was added, and fixing those is a
//      module change (a subKey plus a migration of recorded ids).
//
// RUN THE SELF-TEST WHEN YOU TOUCH THIS FILE. Check 1 was silently dead on the
// first write -- the flag was handed to the items TABLE instead of to each item
// -- and a check that cannot fail is worse than no check, because it is trusted.
'use strict';
const fs = require('fs');
const path = require('path');
const luaparse = require(path.join(__dirname, 'node_modules', 'luaparse'));

const ROOT = path.resolve(__dirname, '..');
const CARD_TYPES = new Set(['toggle', 'checkbox', 'dropdown', 'editbox', 'slider', 'color', 'segmented']);

const SELFTEST = `
local function branches(items, wide)
    if wide then
        items[#items + 1] = { type = "slider", label = L["Either"], get = function() end, set = function() end }
    else
        items[#items + 1] = { type = "slider", label = L["Either"], get = function() end, set = function() end }
    end
    items[#items + 1] = wide and { type = "slider", label = L["Or"], get = function() end, set = function() end }
                              or { type = "slider", label = L["Or"], get = function() end, set = function() end }
    items[#items + 1] = { type = "checkbox", label = L["Swatch"], get = function() end, set = function() end,
        inline = { { kind = "gear", popup = { items = {
            { type = "color", label = L["Swatch"], get = function() end, set = function() end } } } } } }
end
return {
    { type = "group", layout = "row", items = {
        { type = "checkbox", label = L["Trap one"],
          subOptions = { { type = "slider", label = L["Hidden for ever"] } } },
    } },
    { type = "checkbox", label = L["Same label"],
      subOptions = { { type = "slider", label = L["A"] } } },
    { type = "checkbox", label = L["Same label"],
      subOptions = { { type = "slider", label = L["B"] } } },
    { type = "segmented", label = L["Too many"], values = {
        { value = "a", text = L["A"] }, { value = "b", text = L["B"] },
        { value = "c", text = L["C"] }, { value = "d", text = L["D"] },
        { value = "e", text = L["E"] },
    } },
    { type = "segmented", label = L["From a function"], values = SomeValues() },
    { type = "button", label = L["Press me"],
      subOptions = { { type = "slider", label = L["Also lost"] } } },
    { type = "checkbox", label = L["Perfectly fine"], subKey = "ok/1",
      subOptions = { { type = "slider", label = L["Visible"] } } },
    { type = "section", title = L["Twins"], items = {
        { type = "group", layout = "row", items = {
            { type = "slider", label = L["Twin"], get = function() end, set = function() end },
        } },
        { type = "slider", label = L["Twin"], get = function() end, set = function() end },
    } },
    { type = "section", title = L["Not twins"], items = {
        { type = "slider", label = L["Twin"], get = function() end, set = function() end },
        { type = "slider", label = L["Twin"], subKey = "b", get = function() end, set = function() end },
        { type = "slider", label = L["Twin"], noOverride = true, get = function() end, set = function() end },
    } },
}
`;

function walkFiles(dir, out) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walkFiles(p, out);
        else if (e.name.endsWith('.lua')) out.push(p);
    }
    return out;
}

const str = n => {
    if (!n) return null;
    if (n.type === 'StringLiteral') {
        return (n.value !== undefined && n.value !== null) ? n.value : String(n.raw).slice(1, -1);
    }
    if (n.type === 'IndexExpression') return str(n.index);   // L["Label"]
    return null;
};

function fields(node) {
    const out = {};
    if (!node || node.type !== 'TableConstructorExpression') return out;
    for (const f of node.fields) {
        if (f.type === 'TableKeyString') out[f.key.name] = f.value;
        else if (f.type === 'TableKey' && f.key.type === 'StringLiteral') out[str(f.key)] = f.value;
    }
    return out;
}
const arrayParts = node =>
    (node && node.type === 'TableConstructorExpression')
        ? node.fields.filter(f => f.type === 'TableValue').map(f => f.value) : [];

const problems = [];
const gearKeys = {};
let gearCount = 0;

function visit(node, file, insideGroup) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const n of node) visit(n, file, insideGroup); return; }

    if (node.type === 'TableConstructorExpression') {
        const f = fields(node);
        const t = str(f.type);
        const line = node.loc ? node.loc.start.line : 0;

        if (f.subOptions) {
            gearCount++;
            if (insideGroup) {
                problems.push(`${file}:${line}  subOptions in einer Gruppe -- PlaceGroup zeichnet nie ein Zahnrad`);
            }
            if (t && !CARD_TYPES.has(t)) {
                problems.push(`${file}:${line}  subOptions auf type="${t}" -- kein Kartentyp, also kein Zahnrad`);
            }
            const key = str(f.subKey) || str(f.label) || ('?' + line);
            gearKeys[file] = gearKeys[file] || {};
            (gearKeys[file][key] = gearKeys[file][key] || []).push(line);
        }

        if (t === 'segmented') {
            const vals = f.values;
            if (!vals || vals.type !== 'TableConstructorExpression') {
                problems.push(`${file}:${line}  segmented ohne woertliche Werteliste`);
            } else {
                const n = arrayParts(vals).length;
                if (n < 2 || n > 4) {
                    problems.push(`${file}:${line}  segmented mit ${n} Werten (erlaubt 2-4)`);
                }
            }
        }

        // The flag has to reach each ITEM table, so a group's items are visited
        // one by one. Handing it to the items TABLE loses it one level early.
        const isGroup = (t === 'group');
        for (const f2 of node.fields) {
            const isItems = f2.type === 'TableKeyString' && f2.key.name === 'items';
            const child = f2.value !== undefined ? f2.value : f2;
            if (isGroup && isItems) {
                for (const el of arrayParts(child)) visit(el, file, true);
            } else {
                visit(child, file, false);
            }
        }
        return;
    }

    for (const k of Object.keys(node)) {
        if (k === 'loc' || k === 'range') continue;
        visit(node[k], file, insideGroup);
    }
}

// Check 5. ctx mirrors ns:AssignOverrideIds: a section adds its key or title, a
// gear row adds its subKey or label for its subOptions, a group adds nothing.
// scope is the outermost function, one bucket per page body.
const idKeys = {};
const warnings = [];
function visitIds(node, file, ctx, scope) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const n of node) visitIds(n, file, ctx, scope); return; }

    if (node.type === 'FunctionDeclaration' || node.type === 'FunctionExpression') {
        scope = `${file}:${node.loc ? node.loc.start.line : 0}`;
    }

    // `cond and { A } or { B }`: only one of the two rows ever exists, so
    // they cannot collide with each other. Only the first branch is counted.
    if (node.type === 'LogicalExpression' && node.operator === 'or'
        && node.left && node.left.type === 'LogicalExpression' && node.left.operator === 'and'
        && node.left.right && node.left.right.type === 'TableConstructorExpression'
        && node.right && node.right.type === 'TableConstructorExpression') {
        visitIds(node.left.left, file, ctx, scope);
        visitIds(node.left.right, file, ctx, scope);
        return;
    }

    // if/elseif/else: the branches are alternatives, each its own bucket. Rows
    // before or after the if are then not compared with the branch rows --
    // a miss, never a false alarm.
    if (node.type === 'IfStatement' && node.clauses.length > 1) {
        const line = node.loc ? node.loc.start.line : 0;
        node.clauses.forEach((c, i) => {
            visitIds(c.condition, file, ctx, scope);
            visitIds(c.body, file, ctx, `${scope || file}|if${line}#${i}`);
        });
        return;
    }

    if (node.type === 'TableConstructorExpression') {
        const f = fields(node);
        const t = str(f.type);
        if (!t) {
            // a plain list (the page itself, a group's items): look inside
            for (const f2 of node.fields) visitIds(f2.value !== undefined ? f2.value : f2, file, ctx, scope);
            return;
        }
        const line = node.loc ? node.loc.start.line : 0;
        if (t !== 'section') {
            const label = str(f.label);
            const noOv = f.noOverride && f.noOverride.type === 'BooleanLiteral' && f.noOverride.value;
            if (label !== null && f.get && f.set && !noOv) {
                const sk = str(f.subKey) || (f.subKey ? '?' + line : null);
                const key = [label].concat(ctx, sk !== null ? [sk] : []).join(' > ');
                const b = (idKeys[scope || file] = idKeys[scope || file] || {});
                (b[key] = b[key] || []).push(line);
            }
        }
        // Only where AssignOverrideIds walks: items and subOptions. Inline
        // swatches and gear popups are not override rows.
        if (f.items) {
            const inner = (t === 'section') ? ctx.concat([str(f.key) || str(f.title) || '?']) : ctx;
            visitIds(f.items, file, inner, scope);
        }
        if (f.subOptions && t !== 'section') {
            visitIds(f.subOptions, file, ctx.concat([str(f.subKey) || str(f.label) || '?']), scope);
        }
        return;
    }

    for (const k of Object.keys(node)) {
        if (k === 'loc' || k === 'range') continue;
        visitIds(node[k], file, ctx, scope);
    }
}

function reportDuplicateIds(sink) {
    for (const scope of Object.keys(idKeys)) {
        for (const key of Object.keys(idKeys[scope])) {
            const lines = idKeys[scope][key];
            if (lines.length > 1) {
                const file = scope.split(':')[0].split('|')[0];
                sink.push(`${file}  Override-Zeile "${key}" ${lines.length}x (Zeilen ${lines.join(', ')}) -- nur die Reihenfolge trennt sie, subKey setzen`);
            }
        }
    }
}

function scan(label, src) {
    let ast;
    try {
        ast = luaparse.parse(src, { luaVersion: '5.1', locations: true });
    } catch (e) {
        problems.push(`${label}  NICHT PARSEBAR: ${e.message}`);
        return;
    }
    visit(ast.body, label, false);
    visitIds(ast.body, label, [], null);
}

// Runs after everything is scanned, in BOTH modes. It lived only in the file
// path at first, so the self-test reported four of five and blamed a check that
// was fine.
function reportDuplicateGears() {
    for (const file of Object.keys(gearKeys)) {
        for (const key of Object.keys(gearKeys[file])) {
            const lines = gearKeys[file][key];
            if (lines.length > 1) {
                problems.push(`${file}  Zahnrad-Schluessel "${key}" ${lines.length}x (Zeilen ${lines.join(', ')}) -- ein Klick oeffnet alle`);
            }
        }
    }
}

const arg = process.argv[2];
let scanned = 0;

if (arg === '--selftest') {
    scan('selftest', SELFTEST);
    reportDuplicateGears();
    reportDuplicateIds(problems);
    const want = 6;
    console.log(`selftest: ${problems.length} von ${want} erwarteten Befunden`);
    problems.forEach(p => console.log('  ' + p));
    if (problems.length !== want) {
        console.log('\nRESULT: SELBSTTEST FEHLGESCHLAGEN -- eine Pruefung feuert nicht mehr');
        process.exit(1);
    }
    console.log('\nRESULT: OK (alle Pruefungen feuern)');
    process.exit(0);
}

const files = arg ? [path.resolve(arg)]
                  : walkFiles(path.join(ROOT, 'Modules'), []).concat(walkFiles(path.join(ROOT, 'UI'), []));
for (const file of files) {
    scanned++;
    scan(path.relative(ROOT, file).replace(/\\/g, '/'), fs.readFileSync(file, 'utf8'));
}

reportDuplicateGears();
// A hard fail since the one shipped case (two "Border color" rows in DarkSkin)
// got its subKeys on 2026-10-17.
reportDuplicateIds(problems);

console.log(`${scanned} Datei(en), ${gearCount} Zahnraeder`);
warnings.forEach(w => console.log("  WARNUNG " + w));
if (!problems.length) {
    console.log('RESULT: OK');
} else {
    console.log(`\n${problems.length} BEFUND(E):`);
    problems.forEach(p => console.log('  ' + p));
    console.log('\nRESULT: FEHLER');
    process.exit(1);
}
