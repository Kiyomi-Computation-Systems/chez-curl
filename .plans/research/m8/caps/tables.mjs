// M8's header-caps probe: the README's tables, read from the kept logs
// alone. Node 20 or later, the standard library alone. Run from the
// repository's root (the host has no node; the container's):
//   scripts/guix-env node .plans/research/m8/caps/tables.mjs < /dev/null > build/m8/caps/tables.md
// It reads results/guix-8.20.0-{1,2}.log, docker-{1,2}.log and, when there,
// mac-8.7.1-{1,2}.log, and the case 5 Valgrind and case 6 logs. A lane's
// cell shows what both runs showed, or "A / B" where they differ, and every
// such cell is listed at the end ("Cells the runs split").
import { existsSync, readFileSync } from 'node:fs';

const R = '.plans/research/m8/caps/results';
const LANES = [
  ['F', 'floor-7.85.0', 'docker'],
  ['O', 'ubuntu-openssl-8.5.0', 'docker'],
  ['G', 'ubuntu-gnutls-8.5.0', 'docker'],
  ['X', 'guix-8.20.0', 'guix'],
  ['C', 'current-8.23.0', 'docker'],
  ['M', 'mac-8.7.1', 'mac'],
];
const logOf = (lane, k) => (lane[2] === 'docker' ? `${R}/docker-${k}.log` : lane[2] === 'guix' ? `${R}/guix-8.20.0-${k}.log` : `${R}/mac-8.7.1-${k}.log`);
const prefixOf = (lane, k) => (lane[2] === 'docker' ? `[${lane[1]}] ` : `[${lane[1]}-${k}] `);

const kv = (s) => {
  const o = {};
  const re = /(\w+)=("(?:[^"\\]|\\.)*"|\[[^\]]*\]|\S+)/g;
  let m;
  while ((m = re.exec(s))) o[m[1]] = m[2].startsWith('"') ? m[2].slice(1, -1) : m[2];
  return o;
};

// data[lane][k] = { cells: Map(key -> rec), walks: [rec] }
const data = {};
const present = [];
for (const lane of LANES) {
  data[lane[0]] = {};
  for (const k of [1, 2]) {
    const f = logOf(lane, k);
    if (!existsSync(f)) continue;
    const pre = prefixOf(lane, k);
    const cells = new Map();
    const walks = [];
    for (const line of readFileSync(f, 'utf8').split('\n')) {
      if (!line.startsWith(pre)) continue;
      const body = line.slice(pre.length);
      if (body.startsWith('cell ')) {
        const [, cs, label] = body.split(' ');
        const r = kv(body);
        cells.set(`${cs} ${label} ${r.face} ${r.mode}`, r);
      } else if (body.startsWith('walk ')) walks.push(kv(body));
    }
    if (cells.size || walks.length) data[lane[0]][k] = { cells, walks, file: f };
  }
  if (data[lane[0]][1] || data[lane[0]][2]) present.push(lane);
}

const splits = [];
// both: the two runs' values of FN on cell KEY in LANE, joined.
function both(lane, key, fn) {
  const vs = [1, 2].map((k) => (data[lane[0]][k] && data[lane[0]][k].cells.get(key) ? fn(data[lane[0]][k].cells.get(key)) : null)).filter((v) => v !== null);
  if (!vs.length) return '-';
  if (vs.length === 2 && vs[0] !== vs[1]) { splits.push(`${lane[0]} ${key}: ${vs[0]} / ${vs[1]}`); return `${vs[0]} / ${vs[1]}`; }
  return vs.length === 1 ? `${vs[0]} (1 run)` : vs[0];
}
function keys(cs, mode) {
  const ks = [];
  for (const lane of present) for (const k of [1, 2]) {
    const d = data[lane[0]][k];
    if (!d) continue;
    for (const key of d.cells.keys()) if (key.startsWith(`${cs} `) && key.endsWith(` ${mode}`) && !ks.includes(key)) ks.push(key);
  }
  return ks;
}
const out = [];
const table = (title, cols, rows) => {
  out.push(`\n### ${title}\n`);
  out.push(`| ${cols.join(' | ')} |`);
  out.push(`|${cols.map(() => '---').join('|')}|`);
  for (const r of rows) out.push(`| ${r.join(' | ')} |`);
};
const cellName = (key) => { const [, label, face] = key.split(' '); return [label, face]; };
const errNum = (r) => { const m = /Too large response headers: (\d+) >/.exec(r.err || ''); return m ? ` ${m[1]}` : ''; };

// verdict: the obs mode's code, with where it stopped: the header lines
// (count) or bytes (bytes) handed, when the code is not 0.
const vCount = (r) => (r.code === '0' ? `0` : `${r.code} @${r.hdr_lines}`);
const vBytes = (r) => (r.code === '0' ? `0` : `${r.code} @${r.bytes}${errNum(r) && errNum(r).trim() !== r.bytes ? ` (libcurl:${errNum(r)})` : ''}`);
const vHeads = (r) => (r.code === '0' ? `0 ${r.heads}` : `${r.code} ${r.heads}`);
const vCap = (r) => (r.refused && r.refused !== 'none' ? `${r.code} ${r.refused}` : r.code === '0' ? '0, none' : `${r.code}, libcurl first`);

const lanesHdr = present.map((l) => `${l[0]} ${l[1].replace(/-(\d)$/, '')}`);
for (const [cs, title, fn] of [
  ['count', 'Case 1, count: the code (obs), and @ the header lines handed when it stopped', vCount],
  ['bytes', 'Case 2, bytes: the code (obs), and @ the bytes handed, status and empty lines in, when it stopped; libcurl\'s own figure where it differs', vBytes],
  ['toward', 'Case 3, what counts: the code (obs) and each head handed, as status:header-lines:bytes (T a trailer section)', vHeads],
]) {
  table(title, ['cell', 'face', ...lanesHdr], keys(cs, 'obs').map((key) => [...cellName(key), ...present.map((l) => both(l, key, fn))]));
}
// none against obs: the buffered path's code
{
  const rows = [];
  for (const cs of ['count', 'bytes', 'toward']) for (const key of keys(cs, 'none')) {
    const okey = key.replace(/ none$/, ' obs');
    const diff = present.map((l) => {
      const a = both(l, key, (r) => r.code);
      const b = both(l, okey, (r) => r.code);
      return a === b ? '' : `none ${a}, obs ${b}`;
    });
    if (diff.some((x) => x)) rows.push([cs, ...cellName(key), ...diff.map((x) => x || 'same')]);
  }
  table('No HEADERFUNCTION (none) against the counting one (obs): every cell whose code differs', ['case', 'cell', 'face', ...lanesHdr], rows.length ? rows : [['-', 'none', '-', ...present.map(() => '-')]]);
}
// case 4
for (const cs of ['count', 'bytes', 'toward']) {
  table(`Case 4, the cap (1,000 header lines, 102,400 bytes) in a HEADERFUNCTION, over case ${cs === 'count' ? 1 : cs === 'bytes' ? 2 : 3}: the code, and what refused`, ['cell', 'face', ...lanesHdr],
    keys(cs, 'cap').map((key) => [...cellName(key), ...present.map((l) => both(l, key, vCap))]));
}
// header_size against the callback's bytes, for every obs cell ended 0
{
  const rows = [];
  for (const cs of ['count', 'bytes', 'toward']) for (const key of keys(cs, 'obs')) {
    const v = present.map((l) => both(l, key, (r) => (r.code !== '0' ? '' : r.header_size === r.bytes ? '=' : `${r.header_size} vs ${r.bytes}`)));
    if (v.some((x) => x && x !== '=' && x !== '-')) rows.push([cs, ...cellName(key), ...v.map((x) => x || 'n/a')]);
  }
  table('CURLINFO_HEADER_SIZE against the callback\'s bytes, cells ended 0 where they differ (= the same)', ['case', 'cell', 'face', ...lanesHdr], rows);
}
// times: case 1, t_ms of the none mode (the buffered path), and the walk
{
  const med = (xs) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.floor((s.length - 1) / 2)] : NaN; };
  const rows = [];
  for (const key of keys('count', 'none')) {
    rows.push([...cellName(key), ...present.map((l) => {
      const rs = [1, 2].map((k) => data[l[0]][k] && data[l[0]][k].cells.get(key)).filter(Boolean);
      if (!rs.length) return '-';
      const t = rs.map((r) => Number(r.t_ms));
      const w = rs.filter((r) => r.code === '0').map((r) => Number(r.walk_cpu_ms));
      return `${t.map((x) => x.toFixed(1)).join(', ')}${w.length ? `; walk ${w.map((x) => x.toFixed(1)).join(', ')}` : ''}`;
    })]);
  }
  table('Case 1, times: the transfer (ms, add to done, no HEADERFUNCTION), each run; then the walk\'s CPU (ms) after a code of 0', ['cell', 'face', ...lanesHdr], rows);
}
// case 5
{
  const rows = [];
  const ns = new Set();
  for (const l of present) for (const k of [1, 2]) if (data[l[0]][k]) for (const w of data[l[0]][k].walks) ns.add(`${w.n} ${w.names}`);
  const sorted = [...ns].sort((a, b) => Number(a.split(' ')[0]) - Number(b.split(' ')[0]) || a.localeCompare(b));
  for (const nk of sorted) {
    const [n, names] = nk.split(' ');
    rows.push([n, names, ...present.map((l) => {
      const ws = [1, 2].flatMap((k) => (data[l[0]][k] ? data[l[0]][k].walks : [])).filter((w) => w.n === n && w.names === names);
      if (!ws.length) return '-';
      const c = ws.map((w) => Number(w.walk1_cpu_ms)).sort((a, b) => a - b);
      const st = [...new Set(ws.map((w) => `${w.code}:${w.stored}`))].join(',');
      const p = (x) => (x < 10 ? x.toFixed(2) : x.toFixed(0));
      return `${p(c[0])} / ${p(c[Math.floor((c.length - 1) / 2)])} / ${p(c[c.length - 1])} (${c.length}; ${st})`;
    })]);
  }
  table('Case 5, the walk: one whole curl_easy_nextheader walk\'s CPU, ms, min / median / max over both runs\' rounds (samples; code:stored)', ['N', 'names', ...lanesHdr], rows);
}
// case 5 under Valgrind, and case 6
for (const [f, label] of [[`${R}/valgrind-guix-8.20.0-1.log`, 'valgrind run 1'], [`${R}/valgrind-guix-8.20.0-2.log`, 'valgrind run 2']]) {
  if (!existsSync(f)) continue;
  const ws = readFileSync(f, 'utf8').split('\n').filter((l) => / walk n=/.test(l)).map((l) => kv(l.replace(/^\[[^\]]*\] /, '')));
  const rows = [];
  for (const nk of [...new Set(ws.map((w) => `${w.n} ${w.names}`))]) {
    const [n, names] = nk.split(' ');
    const c = ws.filter((w) => w.n === n && w.names === names).map((w) => Number(w.walk1_cpu_ms)).sort((a, b) => a - b);
    rows.push([n, names, c.map((x) => x.toFixed(0)).join(', '), String(c.length)]);
  }
  table(`Case 5 under Valgrind, lane X, ${label} (${f}): the walk's CPU, ms, each round`, ['N', 'names', 'walk CPU ms', 'samples'], rows);
}
for (const k of [1, 2]) {
  const f = `${R}/stream-cost-guix-8.20.0-${k}.log`;
  if (!existsSync(f)) continue;
  const cs = readFileSync(f, 'utf8').split('\n').filter((l) => / c6 way=/.test(l)).map((l) => kv(l.replace(/^\[[^\]]*\] /, '')));
  const groups = new Map();
  for (const c of cs) {
    if (c.head === 'warm') continue;
    const g = `${c.way} ${c.head} ${c.n}`;
    if (!groups.has(g)) groups.set(g, []);
    groups.get(g).push(c);
  }
  const rows = [];
  const stat = (xs) => { const s = [...xs].sort((a, b) => a - b); return `${s[0].toFixed(1)} / ${s[Math.floor((s.length - 1) / 2)].toFixed(1)} / ${s[s.length - 1].toFixed(1)}`; };
  for (const [g, xs] of groups) {
    const [way, head, n] = g.split(' ');
    rows.push([way, head, n, [...new Set(xs.map((x) => `${x.status}:${x.headers}${x.held_head && x.held_head !== '-' ? `:${x.held_head}` : ''}`))].join(','),
      stat(xs.map((x) => Number(x.cpu_ms))), stat(xs.map((x) => Number(x.wall_ms))), stat(xs.map((x) => Number(x.total_us) / 1000)), String(xs.length)]);
  }
  table(`Case 6, lane X, run ${k} (${f}): min / median / max`, ['way', 'head', 'N', 'status:headers[:head]', 'process CPU ms', 'wall ms', 'libcurl total ms', 'samples'], rows);
}
table('Cells the runs split', ['lane, cell: run 1 / run 2'], [...new Set(splits)].map((s) => [s]));
out.push(`\nLogs read: ${present.map((l) => [1, 2].filter((k) => data[l[0]][k]).map((k) => data[l[0]][k].file).join(', ')).join('; ')}`);
process.stdout.write(`${out.join('\n')}\n`);
