// M7's auth probe: the README's tables, from the kept logs. Node, the
// standard library only. Run from the repository's root:
//   node .plans/research/m7/auth/readme-tables.mjs GROUP LOG...
// GROUP is C, A, B, D, W, S, E or H. C reads the logs itself; the rest read
// tables.mjs -x's lines (outcomes only: no times, no count of body bytes a
// server read before a close). A cell that differs by lane lists each value
// with its lanes; a lane under two values in one cell split between runs.
// Lanes: 8.20.0 (Guix), 7.85.0 (the floor), 8.5.0o and 8.5.0g (Ubuntu's,
// OpenSSL and GnuTLS), 8.23.0.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [group, ...files] = process.argv.slice(2);
const laneName = (l) => ({ 'guix-8.20.0': '8.20.0', 'floor-7.85.0': '7.85.0', 'ubuntu-openssl-8.5.0': '8.5.0o',
  'ubuntu-gnutls-8.5.0': '8.5.0g', 'current-8.23.0': '8.23.0' }[l] || l);
const esc = (s) => s.replace(/\|/g, '\\|');

if (group === 'C') {
  const cells = new Map();
  for (const f of files) {
    const per = new Map();
    for (const line of readFileSync(f, 'latin1').split('\n')) {
      const m = /^\[([^\]]+)\] case C:(\w+):(U\d+)-\S*?:(O\d+)-\S* raw (.*)$/.exec(line);
      if (!m) continue;
      const k = `${m[2]}|${m[3]}|${m[4]}|${m[1]}`;
      const e = per.get(k) || {};
      per.set(k, e);
      let r;
      if ((r = /^cred sent=basic decoded="(.*)"$/.exec(m[5]))) e.v = r[1];
      else if (/^cred sent=none$/.test(m[5])) e.v ??= 'none';
      else if (/^cred sent=other$/.test(m[5])) e.v = 'other';
      else if ((r = /^row url_rc=(\d+) not-run$/.exec(m[5]))) e.v = `url_set ${r[1]}`;
      else if ((r = /^row code=(\d+) /.exec(m[5])) && r[1] !== '0') e.code = r[1];
    }
    for (const [k, e] of per) {
      const [mode, u, o, lane] = k.split('|');
      const v = e.code && (e.v === 'none' || !e.v) ? `fails ${e.code}` : e.v;
      const ck = `${mode}|${u}|${o}`;
      if (!cells.has(ck)) cells.set(ck, new Map());
      const L = cells.get(ck);
      if (!L.has(lane)) L.set(lane, new Set());
      L.get(lane).add(v);
    }
  }
  let split = 0, modeDiff = 0, baseDiff = 0;
  for (const [ck, L] of cells) for (const [lane, s] of L) if (s.size > 1) { split++; console.error(`split ${ck} ${lane}: ${[...s]}`); }
  const one = (ck, lane) => [...cells.get(ck).get(lane)][0];
  for (const ck of cells.keys()) {
    const [mode, u, o] = ck.split('|');
    if (mode !== 'curlu') continue;
    for (const lane of cells.get(ck).keys()) if (one(ck, lane) !== one(`url|${u}|${o}`, lane)) modeDiff++;
    for (const lane of ['ubuntu-openssl-8.5.0', 'ubuntu-gnutls-8.5.0']) if (one(ck, lane) !== one(ck, 'guix-8.20.0')) baseDiff++;
  }
  const runs = new Set([...cells.values()].flatMap((L) => [...L.keys()])).size;
  console.log(`<!-- ${cells.size} cells over ${runs} lanes and ${files.length} logs; split between runs: ${split}; CURLU against CURLOPT_URL: ${modeDiff} differ; 8.5.0 (both) against 8.20.0: ${baseDiff} differ -->`);
  const U = [...new Set([...cells.keys()].map((k) => k.split('|')[1]))].sort((a, b) => a.slice(1) - b.slice(1));
  const O = [...new Set([...cells.keys()].map((k) => k.split('|')[2]))].sort((a, b) => a.slice(1) - b.slice(1));
  const fmt = (v) => (v === 'none' || v.startsWith('fails') || v.startsWith('url_set') ? v : `\`${esc(v)}\``);
  console.log(`| | ${O.join(' | ')} |`);
  console.log(`|${'---|'.repeat(O.length + 1)}`);
  for (const u of U) console.log(`| ${u} | ${O.map((o) => fmt(one(`curlu|${u}|${o}`, 'guix-8.20.0'))).join(' | ')} |`);
  console.log();
  console.log('| cell | 8.5.0, 8.20.0 | 7.85.0 | 8.23.0 |');
  console.log('|---|---|---|---|');
  for (const u of U) for (const o of O) {
    const ck = `curlu|${u}|${o}`;
    const b = one(ck, 'guix-8.20.0'), f = one(ck, 'floor-7.85.0'), c = one(ck, 'current-8.23.0');
    if (f !== b || c !== b) console.log(`| ${u} ${o} | ${fmt(b)} | ${f === b ? 'same' : fmt(f)} | ${c === b ? 'same' : fmt(c)} |`);
  }
  process.exit(0);
}

const x = execFileSync(process.execPath, [join(here, 'tables.mjs'), '-x', ...files], { encoding: 'latin1', maxBuffer: 1 << 28 });
const by = new Map();
for (const l of x.split('\n').filter((s) => s.startsWith(`${group}:`))) {
  const [k, who, v] = l.split(' :: ');
  if (!by.has(k)) by.set(k, []);
  by.get(k).push([who, v]);
}
const lanesOf = (who) => {
  if (who.startsWith('ALL(')) return '';
  return [...new Set(who.split(',').map((w) => laneName(w.replace(/^(guix-8\.20\.0-\d|\d):/, ''))))].join(',');
};
const splitNote = (vs) => {
  const seen = new Map();
  vs.forEach(([who], i) => {
    for (const w of who.split(',')) {
      const L = laneName(w.replace(/^(guix-8\.20\.0-\d|\d):/, ''));
      if (!seen.has(L)) seen.set(L, new Set());
      seen.get(L).add(i);
    }
  });
  const s = [...seen].filter(([, n]) => n.size > 1).map(([L]) => L);
  return s.length ? ` *(split on ${s.join(', ')})*` : '';
};
const auth = (v) => {
  const m = /code=(\d+) status=(\d+) outs=(\d+) auth_out=\[([^\]]*)\]/.exec(v);
  return { code: m[1], status: m[2], outs: m[3], seq: m[4].split(',').map((a) => (a === 'none' ? '–' : a)).join(' → ') };
};

if (group === 'A' || group === 'B') {
  const cols = group === 'A' ? ['basic', 'digest', 'both', 'both-rev', 'bearer', 'none', 'open'] : ['open', 'bearer', 'basic'];
  const rows = [...new Set([...by.keys()].map((k) => k.split(':')[1]))];
  console.log(`| ${group === 'A' ? 'HTTPAUTH' : 'row'} | ${cols.join(' | ')} |`);
  console.log(`|${'---|'.repeat(cols.length + 1)}`);
  for (const r of rows) {
    const cells = cols.map((c) => {
      const vs = by.get(`${group}:${r}:${c} raw`) || [];
      return vs.map(([who, v]) => {
        const a = auth(v);
        return `${lanesOf(who) ? `**${lanesOf(who)}**: ` : ''}${a.seq} ⇒ ${a.status}${a.code !== '0' ? ` (${a.code})` : ''}`;
      }).join('<br>') + splitNote(vs);
    });
    console.log(`| ${esc(r)} | ${cells.join(' | ')} |`);
  }
  process.exit(0);
}

if (group === 'D') {
  console.log('| case | result |');
  console.log('|---|---|');
  for (const [k, vs] of by) {
    const cell = vs.map(([who, v]) => {
      const a = auth(v);
      const d = [...v.matchAll(/#(\d+):(ok|bad\([^)]*\))(\[alt=[^\]]*\])?/g)].map((y) => `#${y[1]} ${y[2]}${y[3] ? ` ${y[3].slice(1, -1)}` : ''}`).join(', ');
      const nc = [...v.matchAll(/ nc=(\S+)/g)].map((y) => y[1]).filter((y) => y !== '-').join('/');
      const notes = (v.match(/nonce-from=[^, ;]+|nc-repeat/g) || []).join(' ');
      return `${lanesOf(who) ? `**${lanesOf(who)}**: ` : ''}${a.outs} req, ${d || 'no Digest sent'} ⇒ ${a.status}${a.code !== '0' ? ` (${a.code})` : ''}${nc ? `, nc ${nc}` : ''}${notes ? `, ${notes}` : ''}`;
    }).join('<br>');
    console.log(`| ${k.replace(/ raw$/, '').slice(2)} | ${cell}${splitNote(vs)} |`);
  }
  process.exit(0);
}

// W, S, E, H: each request at the server as SCHEME/STATUS{BODY}; – no
// Authorization, ✗ refused credentials; (refused at head) the answer went out
// as the head arrived (early=1, or Expect: 100-continue refused), else after
// the body, or once 64 KiB had arrived when the case says mid; {N} the body
// read whole, {part} part of it before the client closed, {0} none, {open}
// the request still open at the server 3 s on; @pooled, on a connection an
// earlier transfer of the lane used.
console.log('| case | face | result |');
console.log('|---|---|---|');
for (const [k, vs] of by) {
  const [name, face] = k.split(' ');
  const cell = vs.map(([who, v]) => {
    const a = auth(v);
    const s = /server=\[([^\]]*)\]/.exec(v);
    const hung = /GAVE-UP/.test(v);
    const rst = (v.match(/rst_code=\d+/) || [''])[0];
    const rounds = (s ? s[1] : '').split(' ').filter(Boolean).map((r) => r
      .replace(/^none:-\//, '–/').replace(/^(\w+):(ok|bad)\//, (q, b, c) => `${b[0].toUpperCase()}${b.slice(1)}${c === 'bad' ? '✗' : ''}/`)
      .replace('(early)', ' (refused at head)').replace('{part(closed)}', '{part}').replace('{0(closed)}', '{0}').replace('{-}', '{open}')
      .replace(/:pattern=ok/, ''));
    return `${lanesOf(who) ? `**${lanesOf(who)}**: ` : ''}${hung ? '**hung: gave up at 10 s**, ' : ''}${a.code}, ${a.status}; ${rounds.join(' · ')}${rst ? ` (${rst})` : ''}`;
  }).join('<br>');
  console.log(`| ${esc(name.slice(group.length + 1))} | ${face} | ${cell}${splitNote(vs)} |`);
}
