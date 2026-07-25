#!/usr/bin/env node
// VuloClassicUI pre-release checker. Run from the addon root or tools/:
//   cd tools && npm install && node check.js
//
// Checks, in order:
//   1. Lua 5.1 syntax of every .lua file (luaparse)
//   2. top-level locals per chunk (Lua 5.1 hard cap: 200; warn at 185)
//   3. locale coverage: every L["..."] key used in code exists in deDE.lua
//      (missing keys fall back to English — listed so nothing slips through)
//   4. raw/escaped ASCII double quotes inside GERMAN locale values
//      (house rule: use „ " or ' — a stray " breaks or uglifies the string)
//   5. third-party addon names in code/comments/strings (house rule: never
//      name other addons; WeakAuras is the only allowed exception)
//
// Exit code 1 only on syntax errors or locals-cap violations; everything
// else is a warning report for human judgment.
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..');
const SCAN_DIRS = ['Core', 'Modules', 'UI', 'Locales', 'Trinkets'];
const SYNTAX_ONLY_DIRS = ['Libs'];   // vendor code: syntax/locals checks only
const DEDE = path.join(ROOT, 'Locales', 'deDE.lua');
const FORBIDDEN = /baganator|ellesmere|chattynator|dragonflight|dfui|elvui|leatrix|masque|sexymap|ndui|bartender|dominos|totemtimers|tacotip|gearscore/i;
// "masque" is also the ordinary French word for "hides", so the French locale
// alone produced 60 false hits — enough noise to hide a real one. That name can
// only appear meaningfully in code (an integration), so it is dropped for
// locale files while every other name is still checked there.
const FORBIDDEN_LOCALE = new RegExp(FORBIDDEN.source.replace('|masque', ''), 'i');
const patternFor = (file) => file.includes(path.sep + 'Locales' + path.sep)
    ? FORBIDDEN_LOCALE : FORBIDDEN;
// WeakAuras is the one allowed mention: STRIP it, then test the rest of the
// line — a line-level exemption would mask other names sharing the line
const stripAllowed = (line) => line.replace(/weakauras\w*/gi, '');

let hardFail = false;

function walk(dir, out) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.lua')) out.push(p);
    }
    return out;
}

const files = [];
for (const d of SCAN_DIRS) {
    const p = path.join(ROOT, d);
    if (fs.existsSync(p)) walk(p, files);
}
// vendor libs are TOC-loaded too — a corrupt file breaks the whole load
// chain in-game, so they get the syntax/locals pass (house rules skipped)
const syntaxOnly = [];
for (const d of SYNTAX_ONLY_DIRS) {
    const p = path.join(ROOT, d);
    if (fs.existsSync(p)) walk(p, syntaxOnly);
}

// ---- 1 + 2: syntax + locals -------------------------------------------------
console.log('== syntax + top-level locals ==');
for (const f of [...files, ...syntaxOnly]) {
    const src = fs.readFileSync(f, 'utf8');
    let ast;
    try {
        ast = luaparse.parse(src, { luaVersion: '5.1' });
    } catch (e) {
        console.log('SYNTAX FAIL ' + path.relative(ROOT, f) + ' -> ' + e.message);
        hardFail = true;
        continue;
    }
    let locals = 0;
    for (const s of ast.body) {
        if (s.type === 'LocalStatement') locals += s.variables.length;
        if (s.type === 'FunctionDeclaration' && s.isLocal) locals += 1;
    }
    if (locals >= 200) {
        console.log('LOCALS FAIL ' + path.relative(ROOT, f) + ' -> ' + locals + '/200');
        hardFail = true;
    } else if (locals > 185) {
        console.log('LOCALS WARN ' + path.relative(ROOT, f) + ' -> ' + locals + '/200');
    }
}
console.log('checked ' + (files.length + syntaxOnly.length) + ' files ('
    + syntaxOnly.length + ' vendor, syntax-only)');

// ---- 3: locale coverage -----------------------------------------------------
console.log('\n== locale coverage (deDE) ==');
const KEY_RE = /L\[\s*"((?:[^"\\]|\\.)*)"\s*\]/g;
const DEF_RE = /\["((?:[^"\\]|\\.)*)"\]\s*=/g;   // global: lines can hold SEVERAL defs
const deSrc = fs.existsSync(DEDE) ? fs.readFileSync(DEDE, 'utf8') : '';
const defined = new Set();
for (const line of deSrc.split('\n')) {
    if (/^\s*--/.test(line)) continue;   // commented-out entries don't count
    let m;
    while ((m = DEF_RE.exec(line)) !== null) defined.add(m[1]);
}
const missing = new Map();
for (const f of files) {
    // skip the locale files themselves (segment match, not substring —
    // a parent folder containing "Locales" in its name must not skip all)
    if (path.relative(ROOT, f).split(path.sep)[0] === 'Locales') continue;
    const src = fs.readFileSync(f, 'utf8');
    for (const line of src.split('\n')) {
        if (/^\s*--/.test(line)) continue;   // doc comments aren't real usages
        let m;
        while ((m = KEY_RE.exec(line)) !== null) {
            if (!defined.has(m[1]) && !missing.has(m[1])) {
                missing.set(m[1], path.relative(ROOT, f));
            }
        }
    }
}
if (missing.size === 0) {
    console.log('all used L[...] keys have deDE entries');
} else {
    console.log(missing.size + ' key(s) missing a deDE entry (English fallback):');
    for (const [k, f] of missing) {
        console.log('  MISSING [' + f + '] ' + (k.length > 90 ? k.slice(0, 90) + '…' : k));
    }
}

// ---- 4: quotes in German values ----------------------------------------------
console.log('\n== ASCII quotes inside German values ==');
let qhits = 0;
deSrc.split('\n').forEach((line, i) => {
    if (/^\s*--/.test(line)) return;
    // global + unanchored: lines can hold SEVERAL ["k"] = "v" pairs
    const VAL_RE = /\["(?:[^"\\]|\\.)*"\]\s*=\s*"((?:[^"\\]|\\.)*)"/g;
    let m;
    while ((m = VAL_RE.exec(line)) !== null) {
        if (m[1].includes('\\"')) {
            qhits++;
            console.log('  QUOTE deDE.lua:' + (i + 1));
            break;   // one report per line is enough
        }
    }
});
if (qhits === 0) console.log('clean');

// ---- 5: forbidden names -------------------------------------------------------
console.log('\n== third-party addon names ==');
let nhits = 0;
const tocs = fs.readdirSync(ROOT).filter(n => n.endsWith('.toc')).map(n => path.join(ROOT, n));
for (const f of [...files, ...tocs]) {
    const src = fs.readFileSync(f, 'utf8');
    src.split('\n').forEach((line, i) => {
        if (patternFor(f).test(stripAllowed(line))) {
            nhits++;
            console.log('  NAME ' + path.relative(ROOT, f) + ':' + (i + 1) + '  ' + line.trim().slice(0, 100));
        }
    });
}
if (nhits === 0) console.log('clean');
else console.log('(known pre-existing functional references may be acceptable — judge each hit)');

console.log('\n' + (hardFail ? 'RESULT: FAIL' : 'RESULT: OK (warnings above, if any)'));
process.exit(hardFail ? 1 : 0);
