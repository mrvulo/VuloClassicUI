// Splits one CHANGELOG section into Discord-sized messages.
//
// Discord caps a message at 2000 characters. The old answer was to truncate at
// 1990 and link to the full notes, which quietly cost the release its notes: a
// version touching five modules does not fit, so whichever module came last went
// unmentioned. Posting several messages costs nothing and the budget disappears.
//
// Splits on CATEGORY boundaries, never mid-category, so a reader never sees half
// of "Nameplates:". A single category longer than one message is split again on
// its bullets, with the header repeated so the orphaned half still says what it
// belongs to. Whole categories are then packed into as few messages as fit.
//
// One implementation, two callers: .github/workflows/discord.yml posts the parts,
// tools/release.js reports how many there will be. A second copy would drift.
'use strict';

const CATEGORY = /^\*\*.+:\*\*$/;

function splitChangelog(body, limit) {
  limit = limit || 1850;
  const text = String(body).replace(/\r\n/g, '\n').trim();
  if (!text) return [];

  // 1. one block per category
  const blocks = [];
  let cur = [];
  for (const line of text.split('\n')) {
    if (CATEGORY.test(line) && cur.length) {
      blocks.push(cur.join('\n').trim());
      cur = [];
    }
    cur.push(line);
  }
  if (cur.length) blocks.push(cur.join('\n').trim());

  // 2. a category that does not fit on its own is split on its bullets, and the
  //    header is repeated so the continuation is still labelled
  const parts = [];
  for (const b of blocks.filter(Boolean)) {
    if (b.length <= limit) { parts.push(b); continue; }
    const lines = b.split('\n');
    const head = CATEGORY.test(lines[0]) ? lines.shift() : '';
    let acc = head ? [head] : [];
    let len = head.length;
    for (const l of lines) {
      // > 1 guard: a single bullet longer than the limit still has to go out
      // somewhere, and cutting mid-sentence is worse than one long message.
      if (len + 1 + l.length > limit && acc.length > (head ? 1 : 0)) {
        parts.push(acc.join('\n'));
        acc = head ? [head] : [];
        len = head.length;
      }
      acc.push(l);
      len += 1 + l.length;
    }
    if (acc.length) parts.push(acc.join('\n'));
  }

  // 3. pack neighbours together while they fit
  const msgs = [];
  for (const p of parts) {
    const last = msgs[msgs.length - 1];
    if (last !== undefined && last.length + 2 + p.length <= limit) {
      msgs[msgs.length - 1] = last + '\n\n' + p;
    } else {
      msgs.push(p);
    }
  }
  return msgs;
}

module.exports = { splitChangelog };

// CLI: body on stdin, JSON array of messages on stdout.
if (require.main === module) {
  const fs = require('fs');
  const body = fs.readFileSync(0, 'utf8');
  const limit = Number(process.env.LIMIT || 1850);
  process.stdout.write(JSON.stringify(splitChangelog(body, limit)));
}
