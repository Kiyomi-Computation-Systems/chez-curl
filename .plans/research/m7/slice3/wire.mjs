// M7 slice 3's wire check (2026-11-02): for each case of the wire part in
// LOG (its tags wireN), the request heads libcurl's own trace shows (VERBOSE:
// a "> " line and the lines after it, to the blank line, between the
// program's verbose-begin and verbose-end lines) beside the heads the
// stand-in logged for that tag (its "req FACE#ID #N via=V "HEAD"" lines over
// HTTP/1.1), whole, byte for byte. A head an origin got by a proxy's forward
// is the proxy's rewrite, not libcurl's bytes, and is left out; every other
// logged head, a proxy's and an origin's through a tunnel, is libcurl's. Each
// traced head must match one logged head, and each logged head one traced
// head. Node's standard library only:
//   node .plans/research/m7/slice3/wire.mjs LOG...
// Prints "wire LANE TAG #K same" or "... DIFFERS", "wire LANE TAG count
// libcurl=N standin=M" when the counts differ, and a summary line per log;
// exits 1 when any head differs or any count does, or when no case was read.
import { readFileSync } from 'node:fs';

const unescape = (s) => s.replace(/\\x([0-9a-f]{2})|\\r|\\n|\\(.)/g, (m, h, c) => {
  if (h) return String.fromCharCode(parseInt(h, 16));
  if (m === '\\r') return '\r';
  if (m === '\\n') return '\n';
  return c;
});
let failed = false;
for (const file of process.argv.slice(2)) {
  const lines = readFileSync(file, 'latin1').split('\n');
  const traced = new Map();
  const logged = new Map();
  const open = new Map(); // lane -> { tag, block }
  for (const raw of lines) {
    const m = /^\[([^\]]+)\] (.*)$/s.exec(raw);
    if (!m) continue;
    const lane = m[1];
    const line = m[2];
    let x;
    if ((x = /^verbose-begin (wire\d+)\r?$/.exec(line))) { open.set(lane, { tag: x[1], block: null }); traced.set(`${lane} ${x[1]}`, []); continue; }
    if ((x = /^verbose-end (\S+)\r?$/.exec(line))) { open.delete(lane); continue; }
    const o = open.get(lane);
    if (o) {
      if (o.block === null && line.startsWith('> ')) { o.block = [line.slice(2)]; }
      else if (o.block !== null) {
        const body = line.startsWith('> ') ? line.slice(2) : line;
        o.block.push(body);
        if (body === '\r' || body === '') {
          traced.get(`${lane} ${o.tag}`).push(o.block.map((l) => (l.endsWith('\r') ? `${l}\n` : `${l}\r\n`)).join(''));
          o.block = null;
        }
      }
      continue;
    }
    if ((x = /^s (wire\d+) req (\S+) #\d+ via=(\S+) "(.*)"\r?$/.exec(line))) {
      if (x[3].endsWith('/forward')) continue;
      const k = `${lane} ${x[1]}`;
      if (!logged.has(k)) logged.set(k, []);
      logged.get(k).push(unescape(x[4]));
    }
  }
  let same = 0; let differ = 0; let counts = 0;
  for (const [k, heads] of traced) {
    const got = [...(logged.get(k) || [])];
    if (got.length !== heads.length) { console.log(`wire ${k} count libcurl=${heads.length} standin=${got.length}`); counts++; }
    heads.forEach((h, i) => {
      const j = got.indexOf(h);
      if (j >= 0) { same++; got.splice(j, 1); console.log(`wire ${k} #${i + 1} same ${JSON.stringify(h.split('\r\n')[0])}`); }
      else { differ++; console.log(`wire ${k} #${i + 1} DIFFERS ${JSON.stringify(h)}`); }
    });
    for (const g of got) { differ++; console.log(`wire ${k} logged-only DIFFERS ${JSON.stringify(g)}`); }
  }
  console.log(`wire ${file}: ${traced.size} cases, ${same} heads the same, ${differ} differ, ${counts} counts differ`);
  if (!traced.size || differ || counts) failed = true;
}
process.exit(failed ? 1 : 0);
