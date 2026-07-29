#!/usr/bin/env node
// One command for everything a release does BEFORE the commit.
//
//   node tools/release.js               report only: versions, tag, commits, tree
//   node tools/release.js 1.40.0        bump, generate, measure, validate, report
//
// It never commits, never tags and never pushes. Those stay explicit, because
// they are the steps that reach other people.
//
// Written because a release used to be eight separate commands whose order
// mattered and whose failures were easy to miss -- a forgotten generator run
// silently ships German release notes, a forgotten translation silently shows
// English patch notes in eight languages, and an over-long changelog block is
// silently truncated by Discord.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const LOCALES = ['deDE', 'esES', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW'];
const DISCORD_SOFT = 1900;   // our budget
const DISCORD_HARD = 2000;   // Discord truncates here

let failed = false;
const fail = (m) => { console.log('  FAIL  ' + m); failed = true; };
const warn = (m) => console.log('  WARN  ' + m);
const ok = (m) => console.log('  ok    ' + m);
const head = (m) => console.log('\n== ' + m + ' ==');

function bumpGuess(v) {
  const p = String(v || '0.0.0').split('.').map(Number);
  return [p[0], p[1], (p[2] || 0) + 1].join('.');
}

function git(args, allowFail) {
  const r = spawnSync('git', args, { cwd: ROOT, encoding: 'utf8' });
  if (r.status !== 0 && !allowFail) return null;
  return (r.stdout || '').replace(/\s+$/, '');
}

const target = process.argv[2];
if (target && !/^\d+\.\d+\.\d+$/.test(target)) {
  console.error('Version must look like 1.40.0');
  process.exit(1);
}

// ---------------------------------------------------------------- state
head('current state');

const tocs = fs.readdirSync(ROOT).filter((f) => f.endsWith('.toc'));
if (!tocs.length) { fail('no .toc file found'); process.exit(1); }

const tocVersions = {};
for (const t of tocs) {
  const m = fs.readFileSync(path.join(ROOT, t), 'utf8').match(/^##\s*Version:\s*(.+?)\s*$/m);
  tocVersions[t] = m ? m[1] : null;
  if (!m) fail(t + ' has no "## Version:" line');
}
const distinct = [...new Set(Object.values(tocVersions))];
if (distinct.length > 1) fail('TOC versions disagree: ' + JSON.stringify(tocVersions));
else ok('TOC version ' + distinct[0] + ' (' + tocs.length + ' files)');

const lastTag = git(['describe', '--tags', '--abbrev=0'], true) || '(none)';
const range = lastTag === '(none)' ? [] : (git(['log', lastTag + '..HEAD', '--format=%h %s']) || '').split('\n').filter(Boolean);
ok('last tag ' + lastTag + ', ' + range.length + ' commit(s) since');
range.forEach((l) => console.log('          ' + l));

const dirty = (git(['status', '--porcelain']) || '').split('\n').filter(Boolean);
if (dirty.length) {
  console.log('  ..    working tree has ' + dirty.length + ' change(s)');
  const media = dirty.filter((l) => /\sMedia\//.test(l) || /^\?\?\s+Media\//.test(l));
  if (media.length) warn('Media/ is in the change set -- check it is not licensed art:\n' + media.map((l) => '          ' + l).join('\n'));
} else {
  ok('working tree clean');
}

const branch = git(['rev-parse', '--abbrev-ref', 'HEAD']);
if (branch !== 'master') warn('on branch ' + branch + ', releases go out from master');

// Licensed artwork must stay untracked. check-ignore exits 0 and prints when ignored.
if (fs.existsSync(path.join(ROOT, 'Media', 'LocalClasses'))) {
  const ig = git(['check-ignore', 'Media/LocalClasses'], true);
  if (ig) ok('Media/LocalClasses still ignored');
  else fail('Media/LocalClasses is NOT ignored -- licensed art must never ship');
}

if (!target) {
  console.log('\nReport only. Pass a version to bump and validate, e.g.:');
  console.log('  node tools/release.js ' + bumpGuess(distinct[0]));
  process.exit(failed ? 1 : 0);
}

// ---------------------------------------------------------------- guards
head('release ' + target);

if (distinct[0] === target) warn('TOCs already say ' + target);
if (git(['rev-parse', '-q', '--verify', 'refs/tags/v' + target], true)) fail('tag v' + target + ' already exists');

const CHANGELOG = path.join(ROOT, 'CHANGELOG.md');
const md = fs.readFileSync(CHANGELOG, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
const firstVersion = (md.match(/^##\s+(.+?)\s*$/m) || [])[1];
if (firstVersion !== target) {
  fail('CHANGELOG.md starts with "## ' + firstVersion + '", not "## ' + target + '" -- write the changelog block FIRST (see the changelog skill)');
  process.exit(1);
}
ok('CHANGELOG.md starts with ' + target);

// ---------------------------------------------------------------- bump
for (const t of tocs) {
  const file = path.join(ROOT, t);
  const src = fs.readFileSync(file, 'utf8');
  const next = src.replace(/^(##\s*Version:\s*).+?\s*$/m, '$1' + target);
  if (next !== src) { fs.writeFileSync(file, next); ok('bumped ' + t); }
  else ok(t + ' already at ' + target);
}

// ---------------------------------------------------------------- generate
const gen = path.join(ROOT, 'tools', 'gen_changelog.js');
if (fs.existsSync(gen)) {
  const r = spawnSync(process.execPath, [gen], { cwd: ROOT, encoding: 'utf8' });
  if (r.status !== 0) fail('gen_changelog.js failed:\n' + (r.stderr || r.stdout));
  else ok('regenerated ChangelogData.lua + CHANGELOG-release.md');
} else {
  warn('no tools/gen_changelog.js (VuloUI?) -- in-game notes not generated');
}

// ---------------------------------------------------------------- measure
const block = ('## ' + md.split(/^## /m).find((b) => b.startsWith(target))).trim();
const len = block.length;
if (len > DISCORD_HARD) fail('changelog block is ' + len + ' chars, Discord cuts at ' + DISCORD_HARD);
else if (len > DISCORD_SOFT) warn('changelog block is ' + len + ' chars, over our ' + DISCORD_SOFT + ' budget');
else ok('changelog block ' + len + ' chars');

// ---------------------------------------------------------------- locales
const dataFile = path.join(ROOT, 'Modules', 'ChangelogData.lua');
if (fs.existsSync(dataFile)) {
  const data = fs.readFileSync(dataFile, 'utf8');
  const start = data.indexOf('{ version = "' + target + '"');
  if (start < 0) {
    fail(target + ' missing from ChangelogData.lua');
  } else {
    const nextVer = data.indexOf('{ version = "', start + 10);
    const vBlock = data.slice(start, nextVer < 0 ? undefined : nextVer);

    const keys = [];
    for (const m of vBlock.matchAll(/category = "((?:[^"\\]|\\.)*)"/g)) {
      const c = m[1].replace(/\\"/g, '"');
      if (c !== '') keys.push(c);
    }
    for (const m of vBlock.matchAll(/^\s+"((?:[^"\\]|\\.)*)",\s*$/gm)) {
      const line = m[1].replace(/\\"/g, '"');
      const rest = line.match(/^NEW:\s*(.+)$/);
      keys.push(rest ? rest[1] : line);
    }

    const src = {};
    for (const loc of LOCALES) {
      const f = path.join(ROOT, 'Locales', loc + '.lua');
      if (fs.existsSync(f)) src[loc] = fs.readFileSync(f, 'utf8');
    }
    const gaps = [];
    keys.forEach((k, i) => {
      const needle = '["' + k.replace(/"/g, '\\"') + '"]';
      const miss = Object.keys(src).filter((loc) => !src[loc].includes(needle));
      if (miss.length) gaps.push('[' + i + '] ' + miss.join(' ') + '  ' + k.slice(0, 60));
    });
    if (gaps.length) {
      fail(gaps.length + ' of ' + keys.length + ' patch-note key(s) untranslated -- run the changelog skill pipeline:');
      gaps.forEach((g) => console.log('          ' + g));
    } else {
      ok('all ' + keys.length + ' patch-note keys present in ' + Object.keys(src).length + ' locales');
    }
  }
}

// ---------------------------------------------------------------- validate
const check = path.join(ROOT, 'tools', 'check.js');
if (fs.existsSync(check)) {
  const r = spawnSync(process.execPath, [check], { cwd: ROOT, encoding: 'utf8' });
  const out = (r.stdout || '') + (r.stderr || '');
  if (/RESULT: OK/.test(out)) ok('check.js RESULT: OK');
  else { fail('check.js did not print RESULT: OK'); console.log(out.split('\n').slice(-25).map((l) => '          ' + l).join('\n')); }
} else {
  warn('no tools/check.js -- nothing validated');
}

// Structural check of the options pages. Its own self-test runs first: these
// checks look for things that fail SILENTLY in game (a gear that is never
// drawn, two gears on one key), so a checker that has quietly stopped firing
// would be worse than none -- and it has stopped firing once already.
const optcheck = path.join(ROOT, 'tools', 'optcheck.cjs');
if (fs.existsSync(optcheck)) {
  for (const [args, what] of [[['--selftest'], 'optcheck self-test'], [[], 'optcheck RESULT: OK']]) {
    const r = spawnSync(process.execPath, [optcheck, ...args], { cwd: ROOT, encoding: 'utf8' });
    const out = (r.stdout || '') + (r.stderr || '');
    if (/RESULT: OK/.test(out)) ok(what);
    else { fail(what + ' failed'); console.log(out.split('\n').slice(-20).map((l) => '          ' + l).join('\n')); }
  }
}

// ---------------------------------------------------------------- next steps
head(failed ? 'NOT READY' : 'ready to commit');
if (failed) {
  console.log('  Fix the FAIL lines above, then run this again.');
  process.exit(1);
}
const newTga = dirty.filter((l) => /\.tga\s*$/i.test(l));
if (newTga.length) console.log('  Ships new textures -- tell the user a FULL CLIENT RESTART is needed, not /reload.\n');
console.log([
  '  git add -A',
  '  git commit        (vX.Y.Z: summary; no addon names, no abbreviations, no Co-Authored-By)',
  '  git push origin master',
  '  git tag -a v' + target + ' -m "v' + target + ': <summary>"',
  '  git push origin v' + target,
  '  curl -sS "https://api.github.com/repos/mrvulo/VuloClassicUI/actions/workflows/discord.yml/runs?per_page=3"',
].join('\n'));
