// M7 slice 2's wire check (2026-11-02): for each case of the wire part in
// LOG (its tags wireN), the
// Authorization values libcurl's own trace shows (VERBOSE, its "> " header
// blocks between the program's verbose-begin and verbose-end lines) beside
// the values the stand-in logged for that tag, in order, whole. Node's
// standard library only:
//   node .plans/research/m7/slice2/wire.mjs LOG...
// Prints "wire LANE TAG #K same" or "... DIFFERS", "wire LANE TAG count
// libcurl=N standin=M" when the counts differ, and a summary line per log;
// exits 1 when any value differs or any count does, or when no case was
// read.
import { readFileSync } from 'node:fs';

const unescape = (s) => s.replace(/\\x([0-9a-f]{2})|\\(.)/g, (m, h, c) => (h ? String.fromCharCode(parseInt(h, 16)) : c));
let failed = false;
for (const file of process.argv.slice(2)) {
  const lines = readFileSync(file, 'latin1').split('\n');
  const traced = new Map();
  const logged = new Map();
  const open = new Map();
  for (const raw of lines) {
    const m = /^\[([^\]]+)\] (.*)$/.exec(raw.replace(/\r$/, ""));
    if (!m) continue;
    const lane = m[1];
    const line = m[2];
    let x;
    // The wire part's cases alone (tags wireN): the trace part's are over
    // h2, of bytes no header line carries whole.
    if ((x = /^verbose-begin (wire\d+)$/.exec(line))) { open.set(lane, x[1]); traced.set(`${lane} ${x[1]}`, []); continue; }
    if ((x = /^verbose-end (\S+)$/.exec(line))) { open.delete(lane); continue; }
    if (open.has(lane) && (x = /^(?:> )?Authorization: (.*?)\r?$/.exec(line))) traced.get(`${lane} ${open.get(lane)}`).push(x[1]);
    if ((x = /^s (\S+) auth #\d+ value="(.*)"$/.exec(line))) {
      const k = `${lane} ${x[1]}`;
      if (!logged.has(k)) logged.set(k, []);
      logged.get(k).push(unescape(x[2]));
    } else if ((x = /^s (\S+) auth #\d+ none$/.exec(line))) {
      const k = `${lane} ${x[1]}`;
      if (!logged.has(k)) logged.set(k, []);
    }
  }
  let same = 0; let differ = 0; let counts = 0;
  for (const [k, vs] of traced) {
    const got = logged.get(k) || [];
    if (got.length !== vs.length) { console.log(`wire ${k} count libcurl=${vs.length} standin=${got.length}`); counts++; }
    for (let i = 0; i < Math.min(vs.length, got.length); i++) {
      if (vs[i] === got[i]) { same++; console.log(`wire ${k} #${i + 1} same`); } else { differ++; console.log(`wire ${k} #${i + 1} DIFFERS`); }
    }
  }
  console.log(`wire ${file}: ${traced.size} cases, ${same} values the same, ${differ} differ, ${counts} counts differ`);
  if (!traced.size || differ || counts) failed = true;
}
process.exit(failed ? 1 : 0);
