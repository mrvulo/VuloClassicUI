// Well-formedness check for every XML file of the addon: a stack of open tags,
// so a mismatched or orphaned element is reported with its line instead of
// showing up in the game as a window that never appears.
//   node tools/xmlcheck.cjs [file ...]   (paths relative to the addon root)
const fs = require('fs');
const path = require('path');

// The directory used to be an absolute path on the old Windows machine, so the
// check failed everywhere else. Resolve from this file instead.
const ROOT = path.resolve(__dirname, '..');
const SKIP = new Set(['.git', 'node_modules', 'tools', 'docs']);

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (e.name.endsWith('.xml')) out.push(path.relative(ROOT, full));
  }
  return out;
}

const FILES = process.argv.slice(2);
const list = FILES.length ? FILES : walk(ROOT, []);

let bad = 0;
for (const f of list) {
  const src = fs.readFileSync(path.join(ROOT, f), 'utf8');

  // A double hyphen inside a comment is illegal XML and the parser rejects the
  // WHOLE file -- which reads in game as "Couldn't find inherited node", because
  // everything the file declared silently does not exist. Cost a round to find.
  for (const c of src.matchAll(/<!--([\s\S]*?)-->/g)) {
    if (c[1].includes('--')) {
      const line = src.slice(0, c.index).split('\n').length;
      console.log(`  ${f}:${line}  '--' im Kommentar: der Parser verwirft die ganze Datei`);
      bad++;
    }
  }

  // strip comments and the declaration
  const clean = src.replace(/<!--[\s\S]*?-->/g, '').replace(/<\?[\s\S]*?\?>/g, '');
  const stack = [];
  let line = 1;
  let problems = 0;

  const re = /<(\/?)([A-Za-z_][\w.:-]*)([^>]*?)(\/?)>|\n/g;
  let m;
  while ((m = re.exec(clean))) {
    if (m[0] === '\n') { line++; continue; }
    const [, closing, name, attrs, selfClose] = m;
    line += (m[0].match(/\n/g) || []).length;
    if (selfClose) continue;
    if (closing) {
      const top = stack.pop();
      if (top !== name) {
        console.log(`  ${f}:${line}  </${name}> schliesst <${top || 'nichts'}>`);
        problems++; bad++;
        if (top) stack.push(top);      // keep going, report the rest
      }
    } else {
      stack.push(name);
    }
  }
  if (stack.length) {
    console.log(`  ${f}: am Ende noch offen -> ${stack.join(' > ')}`);
    problems++; bad++;
  }
  console.log(`${problems ? 'FEHLER' : 'ok    '} ${f}`);
}
console.log(bad ? `\n${bad} Problem(e)` : '\nalle Dateien wohlgeformt');
process.exitCode = bad ? 1 : 0;
