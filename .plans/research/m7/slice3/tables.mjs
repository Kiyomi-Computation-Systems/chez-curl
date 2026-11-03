// M7 slice 3's tables (2026-11-02), built from the kept logs alone, Node's
// standard library only:
//   node .plans/research/m7/slice3/tables.mjs [--dir=DIR] [--runs=A,B;C,D] [TABLE,...]
//   node .plans/research/m7/slice3/tables.mjs --valgrind [--against=LANE]
//   node .plans/research/m7/slice3/tables.mjs --checks
// It reads results/guix-8.20.0-1.log and results/docker-1.log as run 1, and
// their -2 twins as run 2 (--dir and --runs read others), and prints, in
// Markdown, every table, or those named: a row per case, a column per lane
// (F 7.85.0, O 8.5.0 OpenSSL, G 8.5.0 GnuTLS, X 8.20.0, C 8.23.0). A cell
// the two runs disagree on reads "**run 1 / run 2**", and is listed at the
// end. Ports read as their face's name, ephemeral ports as #, and
// connection numbers, timings, nonces and dates are left out of every cell.
// --valgrind compares results/valgrind-ubuntu-openssl-8.5.0.log's rows with
// lane O's two native runs (or LANE's, the control), by outcome alone.
// --checks prints the lane-runs' checks. It fails, exit 1, on a lane or a
// line it cannot read, and on a case missing from a lane or a run.
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const opt = (name) => { const a = argv.find((x) => x.startsWith(`--${name}=`)); return a ? a.slice(name.length + 3) : null; };
const dir = opt('dir') || join(here, 'results');
// --lanes=NAME,... keeps those lanes alone (for a partial log; the kept
// tables use all five).
const ALL_LANES = [['floor-7.85.0', 'F'], ['ubuntu-openssl-8.5.0', 'O'], ['ubuntu-gnutls-8.5.0', 'G'], ['guix-8.20.0', 'X'], ['current-8.23.0', 'C']];
const LANES = ALL_LANES.filter(([n]) => !opt('lanes') || opt('lanes').split(',').includes(n));
const valgrindMode = argv.includes('--valgrind');
const checksMode = argv.includes('--checks');
const named = argv.filter((a) => !a.startsWith('--'));
const only = named.length ? new Set(named[0].split(',')) : null;
const die = (why) => { process.stderr.write(`tables.mjs: ${why}\n`); process.exit(1); };

// ------------------------------------------------------------------ reading
const unesc = (s) => s.replace(/\\x([0-9a-f]{2})|\\r|\\n|\\(.)/g, (m, h, c) => {
  if (h) return String.fromCharCode(parseInt(h, 16));
  if (m === '\\r') return '\r';
  if (m === '\\n') return '\n';
  return c;
});
const hexText = (h) => {
  if (h === undefined) return '?';
  const b = Buffer.from(h, 'hex');
  let o = '';
  for (const c of b) o += c >= 0x21 && c <= 0x7e && c !== 0x5c ? String.fromCharCode(c) : `\\x${c.toString(16).padStart(2, '0')}`;
  return o;
};

function parseOutcome(d) {
  const o = { raw: d };
  let m;
  if ((m = /^ok status=(\d+) version=(\S+) headers="((?:[^"\\]|\\.)*)" body="((?:[^"\\]|\\.)*)"/.exec(d))) Object.assign(o, { kind: 'ok', status: m[1], version: m[2], headers: unesc(m[3]), body: unesc(m[4]) });
  else if ((m = /^hok status=(\d+) version=(\S+) url=(\S+) history=\(([^)]*)\) headers="((?:[^"\\]|\\.)*)" body="((?:[^"\\]|\\.)*)"/.exec(d))) Object.assign(o, { kind: 'hok', status: m[1], version: m[2], url: m[3], history: m[4], headers: unesc(m[5]), body: unesc(m[6]) });
  else if ((m = /^head status=(\d+) version=(\S+) headers="((?:[^"\\]|\\.)*)"/.exec(d))) Object.assign(o, { kind: 'head', status: m[1], version: m[2], headers: unesc(m[3]) });
  else if ((m = /^fail reason=(\S+) code=(\S+) classes=\(([^)]*)\) sent=(\S+) option=\S+ strerror=(?:"(?:[^"\\]|\\.)*"|#f) errbuf=(?:"((?:[^"\\]|\\.)*)"|#f)(.*)$/.exec(d))) {
    Object.assign(o, { kind: 'fail', reason: m[1], code: m[2], classes: m[3], sent: m[4], errbuf: m[5] === undefined ? '' : m[5] });
    const t = / transfers=(\d+) history=\(([^)]*)\) timeout=(\S+)/.exec(m[6]);
    if (t) Object.assign(o, { transfers: t[1], history: t[2], timeout: t[3] });
  } else if ((m = /^refused field=(\S+) reason=(\S+)/.exec(d))) Object.assign(o, { kind: 'refused', field: m[1], reason: m[2] });
  else if ((m = /^url-error reason=(\S+) code=(\S+)/.exec(d))) Object.assign(o, { kind: 'url-error', reason: m[1], code: m[2] });
  else if (d === 'hung') o.kind = 'hung';
  else if (d.startsWith('condition ')) o.kind = 'condition';
  else o.kind = 'other';
  return o;
}

// readRun: FILES' lines, by lane.
function readRun(files) {
  const byLane = new Map();
  for (const file of files) {
    const path = join(dir, file);
    if (!existsSync(path)) die(`no log ${path}`);
    const text = readFileSync(path, 'latin1');
    const cur = new Map();
    let lineNo = 0;
    for (const raw0 of text.split('\n')) {
      lineNo += 1;
      const raw = raw0.replace(/\r$/, '');
      const m = /^\[([^\]]+)\] (.*)$/.exec(raw);
      if (!m) continue;
      const lane = m[1];
      if (!ALL_LANES.some(([n]) => n === lane) && !lane.startsWith('mac-')) die(`no lane ${lane}`);
      if (!byLane.has(lane)) byLane.set(lane, { rows: [], tags: new Map(), refusals: [], setopts: [], urls: [], parts: [], envs: [], natives: [], ports: {}, meta: [], selftest: [], valgrind: [] });
      const L = byLane.get(lane);
      const line = m[2];
      let x;
      if ((x = /^part (\S+) env (\S+) libdirs (\S+)$/.exec(line))) { cur.set(lane, { part: x[1], env: x[2], tree: x[3] === 'src' ? 'main' : 'prototype' }); L.parts.push({ part: x[1], env: x[2], tree: x[3] }); continue; }
      if ((x = /^part (\S+) env (\S+) exited (\d+)/.exec(line))) { L.parts.push({ part: x[1], env: x[2], exited: Number(x[3]) }); continue; }
      if ((x = /^standin ports (.*)$/.exec(line))) { for (const p of x[1].split(' ')) { const [k, v] = p.split('='); L.ports[v] = k; } continue; }
      if (/^standin selftest/.test(line)) { L.selftest.push(line); continue; }
      if (/^(src|prototype|program|uname) /.test(line)) { L.meta.push(line); continue; }
      if (/^valgrind /.test(line)) { L.valgrind.push(line); continue; }
      const c = cur.get(lane) || { part: '?', env: '?', tree: '?' };
      if (line.startsWith('env ')) { L.envs.push({ ...c, line }); continue; }
      if (line.startsWith('native ')) { L.natives.push({ ...c, line }); continue; }
      if ((x = /^t (\S+) (.*?) ?tag=(\S+) (.*?) => (.*)$/.exec(line))) {
        const fields = Object.fromEntries([...x[2].matchAll(/(\S+?)=(\S*)/g)].map((y) => [y[1], y[2]]));
        const stepf = Object.fromEntries([...x[4].matchAll(/(\S+?)=(\S*)/g)].map((y) => [y[1], y[2]]));
        L.rows.push({ item: x[1], fields, tag: x[3], step: stepf.step, ms: stepf.ms, outcome: parseOutcome(x[5]), part: c.part, env: c.env, tree: c.tree, at: `${file}:${lineNo}` });
        continue;
      }
      if ((x = /^s (\S+) (.*)$/.exec(line))) {
        if (!L.tags.has(x[1])) L.tags.set(x[1], []);
        L.tags.get(x[1]).push(x[2]);
        continue;
      }
      if ((x = /^r case=(\S+)(?: value=(\S+))? => (.*)$/.exec(line))) { L.refusals.push({ tree: c.tree, kase: x[1] + (x[2] ? ` ${x[2]}` : ''), outcome: x[3] }); continue; }
      if ((x = /^o name=(\S+) value=(\S+) => (.*)$/.exec(line))) { L.setopts.push({ name: x[1], value: x[2], answer: x[3] }); continue; }
      if ((x = /^u case=(\S+) url="(.*)" part=(\S+) => (.*)$/.exec(line))) { L.urls.push({ kase: x[1], url: x[2], prt: x[3], answer: x[4] }); continue; }
    }
  }
  for (const [, L] of byLane) L.byTag = new Map(L.rows.map((r) => [`${r.tag} ${r.step}`, r]));
  return byLane;
}

// norm: TEXT with the lane-run's ports as their faces' names, and other
// ephemeral ports as #.
function norm(L, text) {
  // The low ports (80, 443, 1080) read as themselves.
  return String(text).replace(/\b\d{2,5}\b/g, (n) => (L.ports[n] ? (/^(p80|p1080|tp443)$/.test(L.ports[n]) ? n : `<${L.ports[n]}>`) : Number(n) >= 1024 && n.length >= 4 && n !== '1080' ? '#' : n));
}

// ------------------------------------------------------------------ the stand-in's log
// requests: TAG's requests, in log order: { face, conn, n, via, method,
// target, h2, headers [[name, value]], pa: [{user, pass, hex}], au: [...] }
function stand(L, tag) {
  const lines = L.tags.get(tag) || [];
  const reqs = [];
  const byKey = new Map();
  const ev = { reqs, tunnels: [], forwards: [], haproxy: [], tls: [], firstUp: [], conns: [], answers: [], open: lines.some((l) => l.startsWith('log: ')), lines };
  for (const s of lines) {
    let x;
    if ((x = /^req (\S+) #(\d+) via=(\S+) "(.*)"$/.exec(s))) {
      const head = unesc(x[4]);
      const hl = head.split('\r\n');
      const [method, target] = hl[0].split(' ');
      const headers = hl.slice(1).filter((l) => l).map((l) => { const i = l.indexOf(':'); return [l.slice(0, i), l.slice(i + 1).trim()]; });
      const r = { face: x[1].replace(/#.*/, ''), conn: x[1], n: x[2], via: x[3], method, target, h2: false, headers, head, pa: [], au: [] };
      reqs.push(r); byKey.set(`${x[1]} ${x[2]}`, r);
    } else if ((x = /^req (\S+) stream=(\d+) #(\d+) via=(\S+) "(.*)"$/.exec(s))) {
      const hl = unesc(x[5]).split('\r\n').filter((l) => l);
      const headers = hl.map((l) => { const i = l.indexOf(':', 1); return [l.slice(0, i), l.slice(i + 1).trim()]; });
      const get = (k) => (headers.find(([n]) => n === k) || [])[1];
      const r = { face: x[1].replace(/#.*/, ''), conn: x[1], n: x[3], stream: x[2], via: x[4], method: get(':method'), target: get(':path'), h2: true, headers: headers.filter(([n]) => !n.startsWith(':')), pa: [], au: [] };
      reqs.push(r); byKey.set(`${x[1]} ${x[3]}`, r);
    } else if ((x = /^hdr (\S+) #(\d+) (proxy-authorization|authorization) value="((?:[^"\\]|\\.)*)" scheme=(\S+)(?: hex=(\S*) user-hex=(\S*) pass-hex=(\S*) colon=(\S+) canonical=(\S+))?$/.exec(s))) {
      const r = byKey.get(`${x[1]} ${x[2]}`);
      const v = { value: unesc(x[4]), scheme: x[5], hex: x[6], user: x[7] !== undefined ? hexText(x[7]) : undefined, pass: x[8] !== undefined ? hexText(x[8]) : undefined, colon: x[9] };
      if (r) (x[3] === 'proxy-authorization' ? r.pa : r.au).push(v);
    } else if ((x = /^auth (\S+) #(\d+) (\S+) (.*)$/.exec(s))) {
      const r = byKey.get(`${x[1]} ${x[2]}`);
      if (r) r.verdict = `${x[3]} ${x[4]}`;
    } else if ((x = /^tunnel (\S+) open to=(\S+) local=(\d+)$/.exec(s))) ev.tunnels.push({ conn: x[1], to: x[2] });
    else if ((x = /^tunnel (\S+) first-up "(.*)"$/.exec(s))) ev.firstUp.push({ conn: x[1], bytes: unesc(x[2]) });
    else if ((x = /^forward (\S+) #(\d+) to=(\S+) local=(\d+) dropped=(\S+)$/.exec(s))) ev.forwards.push({ conn: x[1], n: x[2], to: x[3], dropped: x[5] });
    else if ((x = /^haproxy (\S+) "(.*)"$/.exec(s))) ev.haproxy.push({ conn: x[1], face: x[1].replace(/#.*/, ''), line: unesc(x[2]) });
    else if ((x = /^tls (\S+) (handshake alpn=(\S+).*|error (\S+).*|unknown-protocol.*)$/.exec(s))) ev.tls.push({ conn: x[1], face: x[1].replace(/#.*/, ''), alpn: x[3], error: x[4], text: x[2] });
    else if ((x = /^conn (\S+) open/.exec(s))) ev.conns.push(x[1]);
    else if ((x = /^answer (\S+) #(\d+) (\S+)/.exec(s))) {
      ev.answers.push({ conn: x[1], n: x[2], status: x[3] });
      const r = byKey.get(`${x[1]} ${x[2]}`);
      if (r) r.answer = x[3];
    }
  }
  return ev;
}

// valueLabel: a setopt's value as a row names it: a path by its file.
const valueLabel = (v) => (v.startsWith('"/') ? (v.includes('cadir') ? 'the cadir' : `the ${v.replace(/.*\/([^/]+)"$/, '$1')}`) : v);
const isProxy = (face) => /^(p-|tp-|p80|p1080|tp443)/.test(face);
const userOf = (pa) => (pa.length ? pa.map((v) => (v.scheme === 'basic' ? `${v.user}:${v.pass}` : v.scheme)).join('+') : '–');

// reqText: one request as a table reads it.
function reqText(L, r) {
  const form = r.method === 'CONNECT' ? 'CONNECT' : r.h2 ? `h2 ${r.method}` : /^https?:\/\//.test(r.target) ? `${r.method} abs` : r.method;
  const via = r.via === 'direct' ? '' : r.via.endsWith('/tunnel') ? ' (tunnel)' : ' (forwarded)';
  const pa = isProxy(r.face) || r.pa.length ? ` PA=${userOf(r.pa)}` : '';
  const au = r.au.length ? ` A=${r.au.map((v) => (v.scheme === 'basic' ? `Basic ${v.user}:${v.pass}` : v.scheme === 'digest' ? `Digest` : v.scheme)).join('+')}` : '';
  return `${r.face}: ${form}${via}${pa}${au}${r.answer ? ` → ${r.answer}` : ''}`;
}

// outcomeText: what the transfer ended with, as a cell reads it.
function outcomeText(L, o) {
  switch (o.kind) {
    case 'ok': return `${o.status}${o.version === 'http/2' ? ' h2' : ''}`;
    case 'hok': return `${o.status}${o.version === 'http/2' ? ' h2' : ''}${o.history ? ` after ${o.history}` : ''}`;
    case 'head': return `head ${o.status}`;
    case 'fail': return `${o.code} ${o.classes || '–'} sent=${o.sent}${o.transfers ? ` transfers=${o.transfers}` : ''}`;
    case 'refused': return `refused ${o.reason}`;
    case 'url-error': return `url-error ${o.reason}`;
    case 'hung': return 'hung';
    default: return norm(L, o.raw).slice(0, 80);
  }
}

// ------------------------------------------------------------------ tables
const runFiles = (opt('runs') || 'guix-8.20.0-1.log,docker-1.log;guix-8.20.0-2.log,docker-2.log').split(';').map((r) => r.split(','));
const splits = [];
let current = '';

// table: HEAD, then for each row key, a cell per lane, F(L, row, run) by
// run; a cell the runs disagree on is marked and listed.
function table(name, title, note, keys, cellOf, runs, lanes = LANES) {
  if (only && !only.has(name)) return;
  current = name;
  console.log(`\n### ${title} (\`${name}\`)\n`);
  if (note) console.log(`${note}\n`);
  console.log(`| case | ${lanes.map(([, k]) => k).join(' | ')} |`);
  console.log(`|---|${lanes.map(() => '---').join('|')}|`);
  for (const key of keys) {
    const cells = lanes.map(([lane]) => {
      const vals = runs.map((run) => {
        const L = run.get(lane);
        if (!L) return 'no lane';
        const v = cellOf(L, key);
        return v === undefined ? 'missing' : v;
      });
      if (vals.every((v) => v === vals[0])) return vals[0];
      splits.push(`${name} ${key.label || key} ${lane}: ${vals.join(' / ')}`);
      return `**${vals.join(' / ')}**`;
    });
    // A row whose lanes agree shows its cell once, then = for each other lane.
    const shown = cells.length > 1 && cells.every((c) => c === cells[0]) ? cells.map((c, i) => (i === 0 ? c : '=')) : cells;
    console.log(`| ${key.label || key} | ${shown.map((c) => String(c).replace(/\|/g, '\\|').replace(/\n/g, ' ')).join(' | ')} |`);
  }
}

// rowsOf: the keys of every row of ITEM on the lanes, in first-seen order,
// by FIELDS.
function keysOf(runs, pred, keyFields) {
  const seen = new Map();
  for (const run of runs) for (const [, L] of run) for (const r of L.rows) if (pred(r)) {
    const k = keyFields.map((f) => `${f}=${r.fields[f] ?? '-'}`).join(' ');
    if (!seen.has(k)) seen.set(k, { label: k, fields: Object.fromEntries(keyFields.map((f) => [f, r.fields[f]])) });
  }
  return [...seen.values()];
}
const match = (r, key) => Object.entries(key.fields).every(([k, v]) => r.fields[k] === v);
const rowsFor = (L, pred, key) => L.rows.filter((r) => pred(r) && match(r, key));

function main() {
  const runs = runFiles.map(readRun);
  console.log('A cell `=` is the same as the row\'s first; one in bold is two runs that disagree, run 1 / run 2.');
  for (const [lane] of LANES) for (const [i, run] of runs.entries()) if (!run.get(lane)) die(`run ${i + 1} has no lane ${lane}`);

  // --- refusals
  {
    const keys = [];
    for (const r of runs[0].get(LANES[0][0]).refusals) if (!keys.some((k) => k.label === `${r.tree} ${r.kase}`)) keys.push({ label: `${r.tree} ${r.kase}`, tree: r.tree, kase: r.kase });
    table('refusals', 'The hatch and the proxy field, on main and on the prototype',
      'A cell: `attached` (the hatch took it), `made` (the field took it), the refusal\'s reason, or `condition` for an assertion violation.',
      keys, (L, k) => { const r = L.refusals.find((x) => x.tree === (k.tree === 'main' ? 'main' : 'prototype') && x.kase === k.kase); if (!r) return undefined; return r.outcome.replace(/^refused field=\S+ reason=(\S+).*/, 'refused $1').replace(/^condition .*takes a string.*/, 'condition: takes a string').replace(/^condition .*a proxy is.*/, 'condition: not a proxy value'); }, runs);
  }
  // --- setopts
  {
    const keys = [];
    for (const r of runs[0].get(LANES[0][0]).setopts) {
      const label = `${r.name} ${valueLabel(r.value)}`;
      if (!keys.some((k) => k.label === label)) keys.push({ label, name: r.name, value: r.value });
    }
    table('setopts', 'Item 5: curl_easy_setopt\'s answer to each proxy TLS setting, on a scratch handle', 'A cell: the CURLcode, 0 OK, 4 CURLE_NOT_BUILT_IN, 48 CURLE_UNKNOWN_OPTION; `unknown` when the libcurl knows no option by the name.',
      keys, (L, k) => { const r = L.setopts.find((x) => x.name === k.name && valueLabel(x.value) === valueLabel(k.value)); return r ? r.answer.replace('code ', '') : undefined; }, runs);
  }
  // --- item 2 (a)
  {
    const keys = [];
    for (const r of runs[0].get(LANES[0][0]).urls) if (!keys.some((k) => k.label === r.kase)) keys.push({ label: r.kase });
    table('i2a', 'Item 2 (a): curl-url-part of each proxy URL, on main\'s src/',
      'A cell: scheme, user, password, host, port, path, query and fragment as curl-url-part answers them (`–` absent; zoneid after the host when present), or the refusal. `<p-open>` is that face\'s port.',
      keys, (L, k) => {
        const parts = L.urls.filter((u) => u.kase === k.label);
        if (!parts.length) return undefined;
        const get = (p) => { const u = parts.find((x) => x.prt === p); return u ? u.answer : '?'; };
        const err = parts.find((u) => u.answer.startsWith('url-error'));
        if (err) return `${norm(L, err.answer)}`;
        const v = (p) => { const a = get(p); return a === 'absent' ? '–' : a.replace(/^"(.*)"$/, '$1'); };
        return norm(L, `\`${v('scheme')}\` u=${v('user')} pw=${v('password')} h=${v('host')}${v('zoneid') !== '–' ? `%${v('zoneid')}` : ''} port=${v('port')} path=${v('path')} q=${v('query')} f=${v('fragment')}`);
      }, runs);
    // the URL each case parsed
    if (!only || only.has('i2a')) {
      const L0 = runs[0].get(LANES[0][0]);
      console.log('\nThe URLs, in order: ' + keys.map((k) => { const u = L0.urls.find((x) => x.kase === k.label); return `\`${k.label}\` ${norm(L0, u.url)}`; }).join('; ') + '.');
    }
  }
  // --- item 1
  {
    const pred = (r) => r.item === 'i1';
    const keys = [];
    for (const run of runs) for (const [, L] of run) for (const r of L.rows) if (pred(r)) {
      const label = `${r.env} ${r.fields.transport} noproxy=${r.fields.noproxy}`;
      if (!keys.some((k) => k.label === label)) keys.push({ label, env: r.env, transport: r.fields.transport, noproxy: r.fields.noproxy });
    }
    table('i1', 'Item 1: a named proxy beside the environment',
      'The named proxy is `p-open`; the variables name `p-other`. A cell: where the request went (`p-open`, `p-other`, or `direct`: only the origin logged it), the form (`abs`, `CONNECT`), the response, and for h2 the ALPN the origin chose.',
      keys, (L, k) => {
        const r = L.rows.find((x) => pred(x) && x.env === k.env && x.fields.transport === k.transport && x.fields.noproxy === k.noproxy);
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        const proxies = ev.reqs.filter((q) => isProxy(q.face));
        const went = proxies.length ? [...new Set(proxies.map((q) => `${q.face} ${q.method === 'CONNECT' ? 'CONNECT' : 'abs'}`))].join(', ') : ev.reqs.length ? 'direct' : 'nothing logged';
        const alpn = ev.tls.filter((t) => t.face === 'o-h2').map((t) => t.alpn).join(',');
        return `${went}; ${outcomeText(L, r.outcome)}${alpn ? ` alpn=${alpn}` : ''}${ev.open ? ' OPEN' : ''}`;
      }, runs);
    if (!only || only.has('i1')) {
      console.log('\nEach child\'s environment, its first line, on every lane-run (the libcurl path and the run\'s temporary directory left out), and how many lane-runs printed it:\n');
      const seen = new Map();
      for (const run of runs) for (const [lane] of LANES) { const L = run.get(lane); for (const e of L.envs.filter((x) => x.part === 'named' || x.part === 'tlsenv')) { const t = `${e.part} \`${e.env}\`: \`${norm(L, e.line).replace(/CHEZ_CURL_LIBCURL=\S+/, 'CHEZ_CURL_LIBCURL=…').replace(/\/tmp\/m7s3\.\w+/g, 'TMP')}\``; seen.set(t, (seen.get(t) || 0) + 1); } }
      for (const [t, n] of seen) console.log(`- ${t} (${n})`);
    }
  }
  // --- item 2 (b)
  {
    const pred = (r) => r.item === 'i2b';
    const keys = keysOf(runs, pred, ['form', 'transport']);
    table('i2b', 'Item 2 (b): what goes on the wire for each userinfo form, through `p-open`',
      'A cell: the outcome, then the `Proxy-Authorization` p-open decoded, user:password with each byte outside `!`..`~` as `\\xHH`, or `–` for none sent; `no request` when no face got one; `DIRECT` when the origin got the request straight, and the proxy nothing.',
      keys, (L, k) => {
        const r = rowsFor(L, pred, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        const p = ev.reqs.filter((q) => q.face === 'p-open');
        const direct = ev.reqs.some((q) => !isProxy(q.face) && q.via === 'direct');
        return `${outcomeText(L, r.outcome)}; ${p.length ? p.map((q) => userOf(q.pa)).join(' ') : direct ? 'DIRECT: the origin got it, the proxy nothing' : 'no request'}`;
      }, runs);
  }
  // --- item 2 (c)
  {
    const pred = (r) => r.item === 'i2c';
    const keys = keysOf(runs, pred, ['proxy', 'transport']);
    const docker = LANES.filter(([n]) => n !== 'guix-8.20.0');
    table('i2c', 'Item 2 (c): the port a proxy URL names, and none (Docker, root)',
      'Listeners: `p80` on 80 and `p1080` on 1080, plaintext open proxies; `tp443` on 443, an open proxy over TLS. A cell: the face that got the connection, and the outcome. Lane X did not run it: its stand-in has no low ports.',
      keys, (L, k) => {
        const r = rowsFor(L, pred, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        const faces = [...new Set(ev.conns.map((c) => c.replace(/#.*/, '')).filter(isProxy))];
        return `${faces.join(',') || 'no proxy face'}; ${outcomeText(L, r.outcome)}`;
      }, runs, docker);
  }
  // --- item 3
  {
    const pred = (r) => r.item === 'i3';
    const keys = keysOf(runs, pred, ['mode', 'order', 'flags', 'second']);
    table('i3', 'Item 3: the pooled tunnel',
      'Two transfers on one engine through one proxy that takes Basic for alice and bob, the first as alice. `sequential`: the second submitted once the first is done; `batch`: both submitted in one hold of the engine. A cell: `reused` when the second request rode the first\'s origin connection (for a tunnel: inside the first\'s tunnel; for absolute form: on the first\'s proxy connection, whose upstream it is), else `new`; then the second\'s outcome; then each request the proxy got for the second, with the credentials it carried (`no request`: the proxy got none for it).',
      keys, (L, k) => {
        const rs = rowsFor(L, pred, k);
        const r1 = rs.find((r) => r.step === '1');
        const r2 = rs.find((r) => r.step === '2');
        if (!r1 || !r2) return undefined;
        const ev = stand(L, r1.tag);
        const stepOf = (q) => { const m = /[?&]step=(\d)/.exec(q.target || ''); return m ? m[1] : null; };
        const origin = (s) => ev.reqs.find((q) => !isProxy(q.face) && stepOf(q) === s);
        const o1 = origin('1'); const o2 = origin('2');
        const reused = o1 && o2 && o1.conn === o2.conn;
        // the proxy's requests for the second: absolute form by its target;
        // a CONNECT by order (sequential), or every CONNECT but the first's
        // tunnel (batch)
        const proxies = ev.reqs.filter((q) => isProxy(q.face));
        let second;
        if (proxies.some((q) => q.method !== 'CONNECT')) second = proxies.filter((q) => q.method !== 'CONNECT' && stepOf(q) === '2');
        else {
          const t1 = o1 && o1.via.replace(/\/.*/, '');
          second = proxies.filter((q) => q.conn !== t1 || proxies.filter((p) => p.conn === q.conn).indexOf(q) > 0);
          if (!o1) second = proxies.slice(1);
        }
        const h2 = o2 && o2.h2 ? ` stream=${o2.stream}` : '';
        return `${reused ? 'reused' : 'new'}${h2}; ${outcomeText(L, r2.outcome)}; ${second.length ? second.map((q) => `${q.method === 'CONNECT' ? 'CONNECT' : 'abs'} PA=${userOf(q.pa)}${q.answer ? `→${q.answer}` : ''}`).join(', ') : 'no request'}${r1.outcome.kind !== 'ok' ? ` [first: ${outcomeText(L, r1.outcome)}]` : ''}${ev.open ? ' OPEN' : ''}`;
      }, runs);
  }
  // --- item 4
  {
    const predL = (r) => r.item === 'i4' && r.fields.level === 'low';
    table('i4', 'Item 4: a refused CONNECT, and the same proxies by absolute form',
      'A cell: the status chez-curl\'s response carries, or the failure: code, class, request size; then the error buffer.',
      keysOf(runs, predL, ['proxy', 'transport']), (L, k) => {
        const r = rowsFor(L, predL, k)[0];
        if (!r) return undefined;
        return `${outcomeText(L, r.outcome)}${r.outcome.kind === 'fail' ? `; "${norm(L, r.outcome.errbuf).replace(/after \d+ ms/, 'after N ms')}"` : ''}`;
      }, runs);
    const predH = (r) => r.item === 'i4' && r.fields.level === 'high';
    table('i4high', 'Item 4: the high level\'s retry through each',
      '`http-get` and `http-post`, with the policy (attempts 3, the default statuses and methods, backoff 20 ms, jitter off) and with none. A cell: what the call answered or raised (`transfers=` its `&http-exchange`\'s count), then the requests the proxy logged.',
      keysOf(runs, predH, ['proxy', 'transport', 'method', 'retry']), (L, k) => {
        const r = rowsFor(L, predH, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        return `${outcomeText(L, r.outcome)}; proxy got ${ev.reqs.filter((q) => isProxy(q.face)).length}`;
      }, runs);
  }
  // --- item 5
  {
    const pred = (r) => r.item === 'i5' && r.fields.leaf;
    table('i5leaves', 'Item 5: the proxy\'s leaves, verification on and off',
      'An `https://` proxy with `PROXY_CAINFO` the run CA and `PROXY_CAPATH` cleared; `off` adds `PROXY_SSL_VERIFYPEER` 0 and `PROXY_SSL_VERIFYHOST` 0. A cell: the outcome; for a failure, whether the proxy logged a request.',
      keysOf(runs, pred, ['leaf', 'verify', 'transport']), (L, k) => {
        const r = rowsFor(L, pred, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        return `${outcomeText(L, r.outcome)}${r.outcome.kind === 'fail' ? `; proxy requests ${ev.reqs.filter((q) => isProxy(q.face)).length}` : ''}`;
      }, runs);
    const predS = (r) => r.item === 'i5' && r.fields.sep;
    table('i5sep', 'Item 5: the origin\'s TLS settings against the proxy\'s',
      'Through `tp-good` to the `o-tls` origin by CONNECT. `proxy-bad`: `PROXY_CAINFO` the other CA; `origin-bad`: the origin\'s `ca-file` the other CA; `noverify`: that side\'s verification off. A cell: the outcome; which side refused it (`at proxy`: no CONNECT logged; `at origin`: the CONNECT passed).',
      keysOf(runs, predS, ['sep']), (L, k) => {
        const r = rowsFor(L, predS, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        const connect = ev.reqs.some((q) => q.method === 'CONNECT');
        return `${outcomeText(L, r.outcome)}${r.outcome.kind === 'fail' ? (connect ? '; at origin' : '; at proxy') : ''}`;
      }, runs);
    const predE = (r) => r.item === 'i5env';
    const keysE = [];
    for (const run of runs) for (const [, L] of run) for (const r of L.rows) if (predE(r)) { const label = `${r.env} proxyca=${r.fields.proxyca}`; if (!keysE.some((x) => x.label === label)) keysE.push({ label, env: r.env, proxyca: r.fields.proxyca }); }
    table('i5env', 'Item 5: SSL_CERT_FILE and SSL_CERT_DIR beside a PROXY_CAINFO, in a child\'s environment',
      'An `http://` origin through `tp-good`. `certfile-ca`: `SSL_CERT_FILE` the run CA; `certfile-other`: the other CA; `certdir-cadir`: `SSL_CERT_DIR` the run CA\'s hashed directory. `run-ca` and `other-ca`: `PROXY_CAINFO`, with `PROXY_CAPATH` cleared; `other-ca-capath-default`: not cleared.',
      keysE, (L, k) => { const r = L.rows.find((x) => predE(x) && x.env === k.env && x.fields.proxyca === k.proxyca); return r ? outcomeText(L, r.outcome) : undefined; }, runs);
    const predT = (r) => r.item === 'i5stall';
    table('i5stall', 'Item 5: TLS inside TLS, ten times each per run',
      '`timeout-ms` 10,000, through `tp-good` (`https-via-http`: through plaintext `p-open`). A cell: each outcome and how many of the ten gave it.',
      keysOf(runs, predT, ['case']), (L, k) => {
        const rs = rowsFor(L, predT, k);
        if (rs.length !== 10) return rs.length ? `${rs.length} of 10 reps` : undefined;
        const c = new Map();
        for (const r of rs) { const t = outcomeText(L, r.outcome); c.set(t, (c.get(t) || 0) + 1); }
        return [...c].map(([t, n]) => `${n}× ${t}`).join(', ');
      }, runs);
  }
  // --- item 6
  {
    const pred = (r) => r.item === 'i6';
    table('i6', 'Item 6: the twins, beside a named proxy',
      'Through `p-open`, the caller\'s headers `X-Caller: m7s3` and `Proxy-Authorization: Basic YWxpY2U6czNjcmV0`. A cell: each request in the order the stand-in logged it, `FACE: FORM` with the header names it carried (not Host, Accept), `PA=` its Proxy-Authorization; a PROXY protocol line and where it arrived; then the response chez-curl read: status, its header names, and for a streamed one the head\'s.',
      keysOf(runs, pred, ['twin', 'transport']), (L, k) => {
        const rs = rowsFor(L, pred, k);
        const r = rs.find((x) => x.step === '1');
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        const names = (q) => q.headers.map(([n]) => n).filter((n) => !/^(host|accept)$/i.test(n)).join(',');
        const reqs = ev.reqs.map((q) => `${reqText(L, q).replace(/ → .*/, '')} [${names(q)}]`).join(' ; ');
        const hap = ev.haproxy.map((h) => `PROXY line at ${h.face}: ${norm(L, h.line).replace(/127\.0\.0\.1 127\.0\.0\.1 # /, '127.0.0.1 127.0.0.1 # ')}`).concat(ev.firstUp.filter((f) => f.bytes.startsWith('PROXY ')).map((f) => 'PROXY line inside the tunnel')).join('; ');
        const resp = r.outcome.kind === 'ok' ? `→ ${r.outcome.status} [${r.outcome.headers.split(' | ').map((h) => h.replace(/:.*/, '')).join(',')}]` : `→ ${outcomeText(L, r.outcome)}${r.outcome.errbuf ? ` "${norm(L, r.outcome.errbuf)}"` : ''}`;
        const head = rs.find((x) => x.step === 'head');
        const hd = head ? ` head ${head.outcome.status} [${(head.outcome.headers || '').split(' | ').map((h) => h.replace(/:.*/, '')).join(',')}]` : '';
        return `${reqs}${hap ? `; ${hap}` : ''} ${resp}${hd}`;
      }, runs);
  }
  // --- item 7
  {
    const pred = (r) => r.item === 'i7';
    table('i7', 'Item 7: prior knowledge to the h2c origin through a named proxy',
      'A cell: each request the stand-in logged (`h2 GET`: an HTTP/2 stream), then the response\'s status and version.',
      keysOf(runs, pred, ['case']), (L, k) => {
        const r = rowsFor(L, pred, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        return `${ev.reqs.map((q) => reqText(L, q)).join(' ; ')} ⇒ ${outcomeText(L, r.outcome)}`;
      }, runs);
  }
  // --- item 8
  {
    const pred = (r) => r.item === 'i8';
    const keys = keysOf(runs, pred, ['case', 'origin', 'to', 'scheme']);
    table('i8', 'Item 8: the high level\'s proxy, hop by hop',
      'The session\'s proxy is `p-basic` as alice; `call-proxy-other` names it as bob; credentials are `ouser`/`opass` at the origin. A cell: each request in the order the stand-in logged it, `FACE: FORM`, `(tunnel)` or `(forwarded)` for an origin reached through the proxy, `PA=` the Proxy-Authorization the proxy decoded, `A=` the Authorization the origin got, `→` its answer; then what the call answered.',
      keys, (L, k) => {
        const r = rowsFor(L, pred, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        return `${ev.reqs.map((q) => reqText(L, q)).join(' ; ')} ⇒ ${outcomeText(L, r.outcome)}`;
      }, runs);
  }
  // --- item 9
  {
    const pred = (r) => r.item === 'i9';
    table('i9', 'Item 9: REQUEST_SIZE of proxied transfers',
      '`limit=none`: the transfer as it is, its outcome; `limit=1`: the same request with `body-limit` 1, which fails 63 once the response head says its length, after the whole request went: its `sent=` is `REQUEST_SIZE`. Then the bytes the stand-in got from libcurl: each head\'s length, and the body\'s, at the proxy and at the origin (through a tunnel; a forwarded request is the proxy\'s).',
      keysOf(runs, pred, ['route', 'method', 'limit']), (L, k) => {
        const r = rowsFor(L, pred, k)[0];
        if (!r) return undefined;
        const ev = stand(L, r.tag);
        const bodyLen = (q) => { const cl = q.headers.find(([n]) => /^content-length$/i.test(n)); return cl ? Number(cl[1]) : 0; };
        const libcurls = ev.reqs.filter((q) => !q.via.endsWith('/forward') && !q.h2);
        const sizes = libcurls.map((q) => `${q.face.replace(/^o-.*/, 'origin').replace(/^p-.*/, 'proxy')} ${Buffer.byteLength(q.head, 'latin1')}${bodyLen(q) ? `+${bodyLen(q)}` : ''}`).join(', ');
        return `${outcomeText(L, r.outcome)}; ${sizes}`;
      }, runs);
  }
  // --- the wire check's cases
  {
    const pred = (r) => r.item === 'wire';
    table('wire', 'The wire check\'s cases', 'A cell: the outcome. `wire.mjs` compares each head libcurl\'s trace shows with the stand-in\'s.',
      keysOf(runs, pred, ['case']), (L, k) => { const r = rowsFor(L, pred, k)[0]; return r ? outcomeText(L, r.outcome) : undefined; }, runs);
  }
  if (!only) {
    console.log(`\n### What split\n`);
    console.log(splits.length ? splits.map((s) => `- ${s}`).join('\n') : 'Nothing: every cell agrees between the runs.');
  }
}

// ------------------------------------------------------------------ checks
function checks() {
  const runs = runFiles.map(readRun);
  console.log('| lane | run | parts, exits | self-test | transfers | hung | sockets open at /end | log fetch failed | native counts not zero |');
  console.log('|---|---|---|---|---|---|---|---|---|');
  runs.forEach((run, i) => {
    for (const [lane, k] of LANES) {
      const L = run.get(lane);
      if (!L) die(`run ${i + 1} has no lane ${lane}`);
      const exits = L.parts.filter((p) => p.exited !== undefined);
      const bad = exits.filter((p) => p.exited !== 0);
      const open = [...L.tags.values()].filter((ls) => ls.some((l) => l.startsWith('log: '))).length;
      const fetch = [...L.tags.values()].filter((ls) => ls.some((l) => l.startsWith('log-fetch-failed'))).length;
      const nz = L.natives.filter((n) => /\. [1-9]/.test(n.line)).length;
      console.log(`| ${k} | ${i + 1} | ${exits.length} processes, ${bad.length ? bad.map((p) => `${p.part} ${p.env} ${p.exited}`).join(', ') : 'all 0'} | ${L.selftest.join('; ')} | ${L.rows.length} | ${L.rows.filter((r) => r.outcome.kind === 'hung').length} | ${open} | ${fetch} | ${nz} of ${L.natives.length} |`);
    }
  });
  console.log('\nHashes, every lane-run:\n');
  const hs = new Set();
  runs.forEach((run) => { for (const [, L] of run) for (const m of L.meta) if (!m.startsWith('uname')) hs.add(m.replace(/ \(.*$/, '')); });
  for (const h of hs) console.log(`- \`${h}\``);
}

// ------------------------------------------------------------------ valgrind
function valgrind() {
  const against = opt('against') || 'ubuntu-openssl-8.5.0';
  const vg = readRun(['valgrind-ubuntu-openssl-8.5.0.log']).get('ubuntu-openssl-8.5.0');
  if (!vg) die('the Valgrind log has no lane ubuntu-openssl-8.5.0');
  const natives = runFiles.map(readRun).map((run) => run.get(against));
  const key = (r) => `${r.item} ${Object.entries(r.fields).map(([a, b]) => `${a}=${b}`).join(' ')} step=${r.step}`;
  const cell = (L, r) => (r.outcome.kind === 'fail' ? `${r.outcome.code} sent=${r.outcome.sent}${r.outcome.transfers ? ` transfers=${r.outcome.transfers}` : ''}` : outcomeText(L, r.outcome));
  let same = 0; const differ = [];
  for (const r of vg.rows) {
    const k = key(r);
    const v = cell(vg, r);
    const ns = natives.map((L) => { const n = L.rows.find((x) => key(x) === k); return n ? cell(L, n) : 'missing'; });
    if (ns.every((n) => n === v)) same++; else differ.push(`${k}: valgrind ${v}; native ${ns.join(' / ')}`);
  }
  console.log(`valgrind against ${against}: ${vg.rows.length} rows, ${same} the same as both native runs, ${differ.length} differ`);
  for (const d of differ) console.log(`- ${d}`);
  console.log('\nValgrind\'s own lines:\n');
  for (const l of vg.valgrind) if (/ERROR SUMMARY|definitely lost/.test(l)) console.log(`- \`${l}\``);
  const parts = vg.parts.filter((p) => p.exited !== undefined);
  console.log(`\nparts: ${parts.map((p) => `${p.part} ${p.exited}`).join(', ')}; hung ${vg.rows.filter((r) => r.outcome.kind === 'hung').length}`);
}

// cite: each row whose item and fields match ARG, ITEM[,FIELD=VALUE...],
// with its place in the logs, run by run.
function cite(arg) {
  const [item, ...fs] = arg.split(',');
  const want = fs.map((f) => f.split('='));
  runFiles.map(readRun).forEach((run, i) => {
    for (const [lane, k] of LANES) {
      const L = run.get(lane);
      if (!L) continue;
      for (const r of L.rows) if (r.item === item && want.every(([a, b]) => r.fields[a] === b || (a === 'env' && r.env === b) || (a === 'step' && r.step === b)))
        console.log(`${k} run${i + 1} ${r.at} ${r.tag} step=${r.step} ${Object.entries(r.fields).map(([a, b]) => `${a}=${b}`).join(' ')} => ${outcomeText(L, r.outcome)}`);
    }
  });
}

if (opt('cite')) cite(opt('cite'));
else if (valgrindMode) valgrind();
else if (checksMode) checks();
else main();
