// Preview only: render Lucide candidates to PNG in the scratchpad so they can
// be looked at before anything is written into Media/.
'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const { Resvg } = require('@resvg/resvg-js');

const OUT = process.argv[2];
const NAMES = process.argv.slice(3);
const HOSTS = [
  'https://cdn.jsdelivr.net/npm/lucide-static@latest/icons/',
  'https://unpkg.com/lucide-static@latest/icons/',
];

function fetchText(url, depth) {
  depth = depth || 0;
  return new Promise((resolve, reject) => {
    if (depth > 6) return reject(new Error('too many redirects'));
    https.get(url, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        return fetchText(new URL(res.headers.location, url).toString(), depth + 1).then(resolve, reject);
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode)); }
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d));
    }).on('error', reject);
  });
}

(async () => {
  for (const name of NAMES) {
    let svg, err;
    for (const h of HOSTS) {
      try { svg = await fetchText(h + name + '.svg'); break; } catch (e) { err = e; }
    }
    if (!svg) { console.log('FAIL ' + name + ' :: ' + err.message); continue; }
    svg = svg.replace(/stroke="currentColor"/g, 'stroke="#FFFFFF"')
             .replace(/fill="currentColor"/g, 'fill="#FFFFFF"');
    // dark plate behind it, the way the sidebar shows it
    const r = new Resvg(svg, { fitTo: { mode: 'width', value: 64 }, background: '#18181c' });
    fs.writeFileSync(path.join(OUT, 'cand_' + name + '.png'), r.render().asPng());
    console.log('OK   ' + name);
  }
})();
