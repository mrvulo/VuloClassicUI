// make_module_icons.js — fetch Lucide (ISC-licensed) SVG icons, rasterize
// them WHITE at 64px on transparent, and write GENUINE 32-bit TGA files for
// the addon sidebar. Output: <outDir>/<moduleKey>.tga
'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const { Resvg } = require('@resvg/resvg-js');

const OUT = 'C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Interface\\AddOns\\VuloClassicUI\\Media\\Icons\\modules';

// moduleKey -> lucide icon name (https://lucide.dev)
const MAP = {
  globalsettings:     'sliders-horizontal',
  unlockmode:         'move',
  qol:                'sparkles',
  bugfixes:           'bug',
  profiles:           'files',
  minimap:            'map',
  minimapstyle:       'compass',
  fontbars:           'type',
  playercastbar:      'activity',
  unitframes:         'square-user-round',
  nameplates:         'id-card',
  uireskin:           'layout-grid',
  cooldownpulse:      'timer',
  cooldownmanager:    'clock',
  powerbar:           'zap',
  actionbars:         'gallery-horizontal',
  arenaframes:        'swords',
  characterpanel:     'user',
  darkskin:           'palette',
  // addonskins makes OTHER addons match, so it must not read as another paint
  // pot next to darkskin's palette
  addonskins:         'puzzle',
  popupskin:          'picture-in-picture',
  // the plain bell reads as a blob once the sidebar desaturates it and drops it
  // to 40% for a disabled module; the swing arcs keep the silhouette readable
  reminders:          'bell-ring',
  friendlist:         'users',
  miscqol:            'wrench',
  queuetimer:         'hourglass',
  tooltipids:         'info',
  autoitembuy:        'shopping-cart',
  goldtracker:        'coins',
  goldvendors:        'piggy-bank',
  spamfilter:         'filter',
  chat:               'message-circle',
  bags:               'backpack',
  questlog:           'book-open',
  professionwindow:   'hammer',
  disenchantqueue:    'flask-conical',
  vtmanadisplay:      'droplet',
  lazyvulo:           'flame',
  vulslot:            'scroll',
  combattext:         'hash',
  loadouts:           'layers',
  slotpicker:         'mouse-pointer-click',
  trinkets:           'gem',
  swingtimer:         'gauge',
  vulmail:            'mail',
  vulfishing:         'fish',
  vullfg:             'megaphone',
  vultraining:        'graduation-cap',
  fixinspect:         'search',
  fixlfgbrowsenil:    'list',
  fixguildnews:       'newspaper',
  fixauctiondropdown: 'gavel',
  fixbindsocket:      'diamond',
  fixcombatglow:      'sun',
  changelog:          'file-text',

  // Aggregate pages from Modules/Pages.lua. Each one deliberately differs from
  // the glyphs of the modules it collects, so a page and its members never look
  // like the same entry: questlog owns book-open, chat owns message-circle,
  // goldtracker owns coins.
  pg_windows:         'app-window',
  pg_gold:            'store',
  pg_chat:            'messages-square',

  _fallback:          'settings',
  _dashboard:         'home',
};

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        const next = new URL(res.headers.location, url).toString();  // relative redirects!
        return fetchText(next).then(resolve, reject);
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode)); }
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

// PNG (RGBA8, non-interlaced) -> genuine 32-bit uncompressed TGA
const zlib = require('zlib');
function pngToTga(pngBuf, outFile) {
  let pos = 8, w = 0, h = 0; const idat = [];
  while (pos < pngBuf.length) {
    const len = pngBuf.readUInt32BE(pos);
    const type = pngBuf.toString('ascii', pos + 4, pos + 8);
    const data = pngBuf.slice(pos + 8, pos + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * 4;
  const out = Buffer.alloc(h * stride);
  const paeth = (a, b, c) => {
    const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
    return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
  };
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    const rowIn = raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const rowOut = out.slice(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.slice((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= 4 ? rowOut[x - 4] : 0;
      const b = prev ? prev[x] : 0;
      const c = (prev && x >= 4) ? prev[x - 4] : 0;
      let v = rowIn[x];
      if (f === 1) v += a; else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1; else if (f === 4) v += paeth(a, b, c);
      rowOut[x] = v & 0xff;
    }
  }
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(w, 12); header.writeUInt16LE(h, 14);
  header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const s = i * 4;
    body[s] = out[s + 2]; body[s + 1] = out[s + 1]; body[s + 2] = out[s]; body[s + 3] = out[s + 3];
  }
  fs.writeFileSync(outFile, Buffer.concat([header, body]));
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const failed = [];
  for (const [key, icon] of Object.entries(MAP)) {
    try {
      // unpkg answers HTTP 500 for perfectly valid icon names often enough that
      // a single source makes this script unreliable; jsdelivr serves the same
      // package and is tried first.
      let svg;
      for (const host of ['https://cdn.jsdelivr.net/npm/lucide-static@latest/icons/',
                          'https://unpkg.com/lucide-static@latest/icons/']) {
        try { svg = await fetchText(host + icon + '.svg'); break; } catch (e) { /* next host */ }
      }
      if (!svg) throw new Error('no host served ' + icon + '.svg');
      // white strokes on transparent (lucide uses currentColor)
      svg = svg.replace(/stroke="currentColor"/g, 'stroke="#FFFFFF"')
               .replace(/fill="currentColor"/g, 'fill="#FFFFFF"');
      const r = new Resvg(svg, { fitTo: { mode: 'width', value: 64 }, background: 'rgba(0,0,0,0)' });
      const png = r.render().asPng();
      pngToTga(Buffer.from(png), path.join(OUT, key + '.tga'));
      console.log('OK   ' + key + ' <- ' + icon);
    } catch (e) {
      failed.push(key + ' (' + icon + '): ' + e.message);
      console.log('FAIL ' + key + ' <- ' + icon + ' :: ' + e.message);
    }
  }
  if (failed.length) { console.log('\nFAILED: ' + failed.length); process.exitCode = 1; }
  else console.log('\nall icons written to ' + OUT);
})();
