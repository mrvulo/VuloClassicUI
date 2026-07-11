#!/usr/bin/env node
// Generates Modules/ChangelogData.lua from CHANGELOG.md, so the in-game
// "Patch Notes" module shows the same notes as the changelog / Discord post
// without maintaining the text twice.
//
// Run from the repo root or tools/:  node tools/gen_changelog.js
// (Re-run it after editing CHANGELOG.md — e.g. as part of a release.)
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SRC  = path.join(ROOT, 'CHANGELOG.md');
const OUT  = path.join(ROOT, 'Modules', 'ChangelogData.lua');
const MAX_VERSIONS = 25;   // keep the embedded list bounded

const md = fs.readFileSync(SRC, 'utf8');

// Strip the leading HTML comment block (the "how this works" note).
const body = md.replace(/<!--[\s\S]*?-->/g, '');

const versions = [];
let cur = null, sec = null;
for (const raw of body.split(/\r?\n/)) {
    const line = raw.replace(/\s+$/, '');
    let m;
    if ((m = line.match(/^##\s+(.+?)\s*$/))) {                 // ## 1.31.0
        cur = { version: m[1], sections: [] };
        sec = null;
        versions.push(cur);
    } else if (!cur) {
        // ignore anything before the first version (e.g. the "# ... Changelog" title)
    } else if ((m = line.match(/^\*\*(.+?):\*\*\s*$/))) {      // **Category:**
        sec = { category: m[1], lines: [] };
        cur.sections.push(sec);
    } else if ((m = line.match(/^[-*]\s+(.+?)\s*$/))) {        // - a bullet
        if (!sec) { sec = { category: '', lines: [] }; cur.sections.push(sec); }
        sec.lines.push(cleanText(m[1]));
    }
}

// Drop markdown bold markers; keep WoW color escapes and em dashes as-is.
function cleanText(s) {
    return s.replace(/\*\*/g, '');
}

// Lua-escape a double-quoted string.
function lua(s) {
    return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

const parts = [];
parts.push('-- =========================================================');
parts.push('-- VuloClassicUI / Modules / ChangelogData');
parts.push('-- AUTO-GENERATED from CHANGELOG.md by tools/gen_changelog.js.');
parts.push('-- Do NOT edit by hand — edit CHANGELOG.md and re-run the generator.');
parts.push('-- =========================================================');
parts.push('local _, ns = ...');
parts.push('');
parts.push('ns.CHANGELOG = {');
for (const v of versions.slice(0, MAX_VERSIONS)) {
    parts.push('    { version = ' + lua(v.version) + ', sections = {');
    for (const s of v.sections) {
        parts.push('        { category = ' + lua(s.category) + ', lines = {');
        for (const ln of s.lines) {
            parts.push('            ' + lua(ln) + ',');
        }
        parts.push('        } },');
    }
    parts.push('    } },');
}
parts.push('}');
parts.push('');

fs.writeFileSync(OUT, parts.join('\n'));
console.log('wrote ' + OUT + ' (' + versions.length + ' versions, capped at ' + MAX_VERSIONS + ')');
