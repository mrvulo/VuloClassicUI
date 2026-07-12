// make_class_sheets.js — build the shippable "Vulo Fantasy 1/2" friends-list
// class sheets from game-icons.net glyphs (CC BY 3.0, credited in
// Media/ClassSheets/LICENSE.txt). Each 128px cell = class colour on a rounded
// tile + a white game-icons glyph (dark on light classes), placed on the same
// 8x8 / 128px grid the addon's SHEET_COORDS expects.
// Output: Media/ClassSheets/vulofantasy1.tga + vulofantasy2.tga (genuine 32-bit TGA)
'use strict';
const fs = require('fs');
const path = require('path');
const https = require('https');
const zlib = require('zlib');
const { Resvg } = require('@resvg/resvg-js');

const OUT_DIR = 'C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Interface\\AddOns\\VuloClassicUI\\Media\\ClassSheets';
const CELL = 128, COLS = 8, SIZE = COLS * CELL;

// class -> colour + grid cell (matches SHEET_COORDS)
const GRID = {
  WARRIOR:{c:'C69B6D',col:0,row:0}, MAGE:{c:'3FC7EB',col:1,row:0}, ROGUE:{c:'FFF468',col:2,row:0},
  DRUID:{c:'FF7C0A',col:3,row:0},   EVOKER:{c:'33937F',col:4,row:0}, HUNTER:{c:'AAD372',col:0,row:1},
  SHAMAN:{c:'0070DD',col:1,row:1},  PRIEST:{c:'FFFFFF',col:2,row:1}, WARLOCK:{c:'8788EE',col:3,row:1},
  PALADIN:{c:'F48CBA',col:0,row:2}, DEATHKNIGHT:{c:'C41E3A',col:1,row:2}, MONK:{c:'00FF98',col:2,row:2},
  DEMONHUNTER:{c:'A330C9',col:3,row:2},
};
// author/name per class for each sheet ("crossed-swords" is the only warrior pick)
const SET1 = {
  WARRIOR:'lorc/crossed-swords', MAGE:'lorc/fireball', ROGUE:'lorc/plain-dagger',
  DRUID:'lorc/paw', EVOKER:'lorc/dragon-head', HUNTER:'delapouite/bow-arrow',
  SHAMAN:'lorc/lightning-trio', PRIEST:'lorc/prayer', WARLOCK:'lorc/imp-laugh',
  PALADIN:'lorc/winged-shield', DEATHKNIGHT:'lorc/grim-reaper', MONK:'lorc/fist',
  DEMONHUNTER:'delapouite/devil-mask',
};
const SET2 = {
  WARRIOR:'lorc/crossed-swords', MAGE:'lorc/wizard-staff', ROGUE:'lorc/daggers',
  DRUID:'delapouite/oak-leaf', EVOKER:'lorc/dragon-spiral', HUNTER:'lorc/high-shot',
  SHAMAN:'lorc/lightning-arc', PRIEST:'lorc/holy-symbol', WARLOCK:'lorc/evil-minion',
  PALADIN:'delapouite/thor-hammer', DEATHKNIGHT:'lorc/skull-signet', MONK:'delapouite/high-kick',
  DEMONHUNTER:'lorc/horned-helm',
};

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode + ' ' + url)); }
      let d = ''; res.on('data', c => d += c); res.on('end', () => resolve(d));
    }).on('error', reject);
  });
}
function glyphColor(hex) {
  const r = parseInt(hex.slice(0,2),16)/255, g = parseInt(hex.slice(2,4),16)/255, b = parseInt(hex.slice(4,6),16)/255;
  return (0.2126*r + 0.7152*g + 0.0722*b) > 0.62 ? '#15151b' : '#ffffff';
}
function decodePng(pngBuf) {
  let pos = 8, w = 0, h = 0; const idat = [];
  while (pos < pngBuf.length) {
    const len = pngBuf.readUInt32BE(pos), type = pngBuf.toString('ascii', pos+4, pos+8), data = pngBuf.slice(pos+8, pos+8+len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); }
    else if (type === 'IDAT') idat.push(data); else if (type === 'IEND') break;
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat)), stride = w*4, out = Buffer.alloc(h*stride);
  const paeth = (a,b,c) => { const p=a+b-c, pa=Math.abs(p-a), pb=Math.abs(p-b), pc=Math.abs(p-c); return pa<=pb&&pa<=pc?a:(pb<=pc?b:c); };
  for (let y = 0; y < h; y++) {
    const f = raw[y*(stride+1)], rowIn = raw.slice(y*(stride+1)+1,(y+1)*(stride+1)), rowOut = out.slice(y*stride,(y+1)*stride), prev = y>0?out.slice((y-1)*stride,y*stride):null;
    for (let x = 0; x < stride; x++) {
      const a = x>=4?rowOut[x-4]:0, b = prev?prev[x]:0, c = (prev&&x>=4)?prev[x-4]:0;
      let v = rowIn[x];
      if (f===1) v+=a; else if (f===2) v+=b; else if (f===3) v+=(a+b)>>1; else if (f===4) v+=paeth(a,b,c);
      rowOut[x] = v & 0xff;
    }
  }
  return { w, h, rgba: out };
}
async function cell(hex, iconPath) {
  const raw = await fetchText('https://raw.githubusercontent.com/game-icons/icons/master/' + iconPath + '.svg');
  const gc = glyphColor(hex);
  const inner = raw.slice(raw.indexOf('>') + 1, raw.lastIndexOf('</svg>'))
    .replace('<path d="M0 0h512v512H0z"/>', '')        // drop the black backdrop
    .replace(/fill="#fff"/g, `fill="${gc}"`);
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">` +
    `<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">` +
      `<stop offset="0" stop-color="#${hex}" stop-opacity="1"/><stop offset="1" stop-color="#${hex}" stop-opacity="0.72"/>` +
    `</linearGradient></defs>` +
    `<rect x="6" y="6" width="116" height="116" rx="26" fill="url(#g)"/>` +
    `<rect x="6" y="6" width="116" height="116" rx="26" fill="none" stroke="#15151b" stroke-width="6"/>` +
    `<g transform="translate(20,20) scale(0.172)" fill="${gc}">${inner}</g></svg>`;
  const png = new Resvg(svg, { fitTo: { mode: 'width', value: CELL }, background: 'rgba(0,0,0,0)' }).render().asPng();
  return decodePng(Buffer.from(png));
}
function writeTga(sheet, file) {
  const header = Buffer.alloc(18);
  header[2] = 2; header.writeUInt16LE(SIZE, 12); header.writeUInt16LE(SIZE, 14); header[16] = 32; header[17] = 0x28;
  const body = Buffer.alloc(SIZE * SIZE * 4);
  for (let i = 0; i < SIZE * SIZE; i++) { const s = i*4; body[s]=sheet[s+2]; body[s+1]=sheet[s+1]; body[s+2]=sheet[s]; body[s+3]=sheet[s+3]; }
  fs.writeFileSync(file, Buffer.concat([header, body]));
}
async function buildSheet(setMap, outFile) {
  const sheet = Buffer.alloc(SIZE * SIZE * 4);
  for (const [cls, def] of Object.entries(GRID)) {
    const { w, h, rgba } = await cell(def.c, setMap[cls]);
    const x0 = def.col * CELL, y0 = def.row * CELL;
    for (let y = 0; y < h; y++) { const src = y*w*4, dst = ((y0+y)*SIZE + x0)*4; rgba.copy(sheet, dst, src, src + w*4); }
    console.log('  OK ' + cls + ' <- ' + setMap[cls]);
  }
  writeTga(sheet, outFile);
  console.log('  wrote ' + outFile);
}
(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  console.log('Vulo Fantasy 1:'); await buildSheet(SET1, path.join(OUT_DIR, 'vulofantasy1.tga'));
  console.log('Vulo Fantasy 2:'); await buildSheet(SET2, path.join(OUT_DIR, 'vulofantasy2.tga'));
  console.log('\ndone (' + (18 + SIZE*SIZE*4) + ' bytes each)');
})().catch(e => { console.error(e.message); process.exit(1); });
