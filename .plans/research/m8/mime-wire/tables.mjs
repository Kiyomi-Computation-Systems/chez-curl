// M8's mime wire probe: the README's tables, from the kept logs. Node 20 or
// later, the standard library only. Run from the repository's root:
//   node .plans/research/m8/mime-wire/tables.mjs [LOG ...]
// With no LOG, every .log in results/. It prints, per question, one row per
// variant: a cell per lane, or "all" where every lane gave one cell. A lane's
// runs are its logs (guix-8.20.0.log, -2.log and -E3.log; docker.log, -2 and
// -E3; the Mac's [mac-8.7.1] and [mac-8.7.1-2]), and a run that did not run a
// case (the E3 logs ran E alone) is left out of that case's cells; a cell
// where the runs differ is printed "SPLIT run1 || run2 ...", and one read
// from one run alone "(ONE RUN)". Before it compares, it normalizes what varies
// by design: libcurl's random boundary becomes B (its length and form are
// cells of their own), a port becomes PORT, and a wait becomes a bucket
// (none under 50 ms, else ~N00 ms); the waits' ranges are a table of their
// own. Then the checks: every probe's exit, every transfer's code, gave-ups,
// failed fetches, open requests, incomplete bodies, setopt and mime refusals,
// and the server's stderr.
import { readFileSync, readdirSync } from 'node:fs';
import { join, basename, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const files = process.argv.slice(2).length ? process.argv.slice(2)
  : readdirSync(join(here, 'results')).filter((f) => f.endsWith('.log')).sort().map((f) => join(here, 'results', f));

const SHORT = { 'floor-7.85.0': 'F', 'ubuntu-openssl-8.5.0': 'O', 'ubuntu-gnutls-8.5.0': 'G', 'guix-8.20.0': 'X', 'current-8.23.0': 'C', 'mac-8.7.1': 'M' };
const ORDER = ['F', 'O', 'G', 'M', 'X', 'C'];

// ---------------------------------------------------------------- parse
const recs = new Map();   // `${lane}|${run}|${name}|${face}` -> record
const runsOf = new Map(); // lane -> Set of run ids
const checks = [];
const misc = [];          // lines outside a transfer, by lane and run
function rec(lane, run, name, face) {
  const k = `${lane}|${run}|${name}|${face}`;
  let r = recs.get(k);
  if (!r) {
    r = { lane, run, name, face, setup: '', done: null, hout: [], text: [], hin: [], srv: [], other: [], at: null };
    recs.set(k, r);
  }
  return r;
}
function kv(s) {
  const o = {};
  const re = /([a-z_0-9]+)=("(?:[^"\\]|\\.)*"|\S+)/g;
  let m;
  while ((m = re.exec(s))) o[m[1]] = m[2];
  return o;
}
for (const f of files) {
  const lines = readFileSync(f, 'latin1').split('\n');
  lines.forEach((line, i) => {
    const m = /^\[([^\]]+)\] (.*)$/.exec(line);
    if (!m) { if (line.trim()) misc.push({ file: basename(f), n: i + 1, line }); return; }
    let label = m[1];
    const body = m[2];
    let run = basename(f);
    if (/-2$/.test(label)) { label = label.slice(0, -2); run += '#2'; }
    const lane = SHORT[label] || label;
    if (!runsOf.has(lane)) runsOf.set(lane, new Set());
    runsOf.get(lane).add(run);
    const c = /^case (\S+) (\S+) (.*)$/.exec(body);
    if (!c) { misc.push({ file: basename(f), n: i + 1, lane, run, line: body }); return; }
    const [, name, face, rest] = c;
    if (face === 'all' || face === 'live') return;
    const r = rec(lane, run, name, face);
    const sp = rest.indexOf(' ');
    const kind = sp < 0 ? rest : rest.slice(0, sp);
    const tail = sp < 0 ? '' : rest.slice(sp + 1);
    if (kind === 'setup') r.setup = tail;
    else if (kind === 'done') { r.done = kv(tail); r.at = `${basename(f)}:${i + 1}`; }
    else if (kind === 'header_out') r.hout.push(tail.replace(/^t=\S+ /, ''));
    else if (kind === 'header_in') r.hin.push(tail.replace(/^t=\S+ /, ''));
    else if (kind === 'text') r.text.push(tail.replace(/^t=\S+ /, ''));
    else if (kind === 'server:') r.srv.push(tail);
    else r.other.push(rest);
  });
}

// ---------------------------------------------------------------- helpers
const unq = (s) => (s && s[0] === '"' ? s.slice(1, -1) : s);
const normB = (s) => String(s).replace(/-{24}[0-9A-Za-z]{16,22}/g, 'B').replace(/127\.0\.0\.1:\d+/g, '127.0.0.1:PORT').replace(/tag=[^&\s"]+/g, 'tag=T');
const srvLine = (r, kind) => r.srv.find((l) => l.startsWith(`${kind} `) || l === kind);
const srvLines = (r, kind) => r.srv.filter((l) => l.startsWith(`${kind} `));
const srvKv = (r, kind) => { const l = srvLine(r, kind); return l ? kv(l) : {}; };
const bucket = (w) => (w === undefined || w === null || Number.isNaN(w) || w < 0 ? 'no-body-sent' : w < 50 ? 'none' : `~${Math.round(w / 100) * 100}ms`);
function hdr(r) {
  const l = srvLine(r, 'hdr');
  if (!l) return {};
  const o = {};
  for (const k of ['content-type', 'content-length', 'transfer-encoding', 'expect']) {
    const m = new RegExp(`${k}=("(?:[^"\\\\]|\\\\.)*"\\(x\\d+\\)|none)`).exec(l);
    o[k] = m ? m[1] : '?';
  }
  return o;
}
function lanes() { return ORDER.filter((l) => runsOf.has(l)).concat([...runsOf.keys()].filter((l) => !ORDER.includes(l))); }
function cellFor(lane, name, face, fn) {
  const runs = [...(runsOf.get(lane) || [])].sort();
  // a run that did not run this case (CASES=E alone) has no record: it is
  // left out, not a split
  const vals = runs.map((run) => recs.get(`${lane}|${run}|${name}|${face}`)).filter(Boolean).map(fn);
  const uniq = [...new Set(vals)];
  if (!vals.length) return 'absent';
  if (uniq.length === 1) return vals.length >= 2 ? uniq[0] : `${uniq[0]} (ONE RUN)`;
  return `SPLIT ${vals.join(' || ')}`;
}
function table(title, rows, fn, faces) {
  const ls = lanes();
  console.log(`\n### ${title}\n`);
  for (const row of rows) {
    for (const face of faces || ['h1']) {
      const cells = ls.map((l) => [l, cellFor(l, row, face, fn)]);
      const u = [...new Set(cells.map(([, c]) => c))];
      if (u.length === 1 && u[0] === 'absent') continue;
      const label = faces && faces.length > 1 ? `${row} ${face}` : row;
      if (u.length === 1) console.log(`- \`${label}\` all: ${u[0]}`);
      else {
        // group lanes by cell
        const g = new Map();
        for (const [l, c] of cells) { if (!g.has(c)) g.set(c, []); g.get(c).push(l); }
        console.log(`- \`${label}\` ${[...g].map(([c, l]) => `${l.join('')}: ${c}`).join(' ;; ')}`);
      }
    }
  }
}
const names = (prefix) => [...new Set([...recs.values()].filter((r) => r.name.startsWith(prefix)).map((r) => r.name))];
const FACES = ['h1', 'tlsh1', 'tlsh2', 'h2c'];

// ---------------------------------------------------------------- cells
// frame: the protocol, and the framing relative to the body: CL=body when
// Content-Length is the body's length as read, else both numbers; for h1 a
// wire length other than the body's (chunk framing) is named. ABS: the
// numbers, always.
function frame(r, abs) {
  const h = hdr(r);
  const b = srvKv(r, 'body');
  const proto = (srvKv(r, 'req').proto) || '?';
  const clv = h['content-length'] === 'none' ? null : unq(h['content-length'].replace(/\(x\d+\)$/, ''));
  const cl = clv === null ? 'no-CL' : !abs && clv === b.bytes ? 'CL=body' : `CL ${clv}`;
  const te = h['transfer-encoding'] === 'none' ? '' : ` TE ${unq(h['transfer-encoding'].replace(/\(x\d+\)$/, ''))}`;
  const wire = proto !== 'h2' && b.wire !== b.bytes ? ` wire=${b.wire}` : '';
  return `${proto} ${cl}${te}${abs || clv !== b.bytes ? ` body=${b.bytes || '?'}` : ''}${wire}`;
}
function sameB(r) { const mp = srvLine(r, 'mp'); return mp ? (kv(mp).same === '1' ? 'CT-boundary=body\'s' : 'CT-boundary!=body\'s') : 'no-mp'; }
function ctOf(r) { const h = hdr(r); return h['content-type'] === 'none' ? 'no-CT' : `CT ${normB(h['content-type'].replace(/\(x\d+\)$/, ''))}`; }
function ctForm(r) { const c = srvKv(r, 'ctype'); return c.first_len ? `${c.first_form}(${c.first_len})` : 'no-boundary'; }
function expectOf(r) { const h = hdr(r); return h.expect === 'none' ? 'no-Expect' : `Expect ${unq(h.expect.replace(/\(x\d+\)$/, ''))}`; }
function parseOf(r) {
  const mp = srvLine(r, 'mp') || 'mp none';
  const ok = /parse=ok/.test(mp) ? `parse ok parts=${kv(mp).parts}` : /empty-body/.test(mp) ? 'empty-body' : `parse FAIL ${kv(mp).why || ''}`;
  const mpl = srvLine(r, 'mpl');
  if (!mpl) return ok;
  if (/delimiters=0/.test(mpl)) return `${ok}; lenient none (no delimiter of that boundary)`;
  return `${ok}; lenient ${kv(mpl).parts} [${(/names=\[(.*)\]/.exec(mpl) || [])[1] || ''}]`;
}
// dispOf: each part's Content-Disposition type, from the strict parse's
// header lines, or, where that parse failed, from the body's bytes (logged
// whole up to 8 KiB), marked "by-bytes".
function dispOf(r) {
  let ds = srvLines(r, 'pline').map((l) => l.replace(/^pline \S+ /, '')).filter((l) => /^"Content-Disposition:/i.test(l))
    .map((l) => (/^"Content-Disposition: ([^;"]*)/i.exec(l) || [])[1]);
  if (ds.length) return `disp [${ds.join(',')}]`;
  const bb = srvLine(r, 'bodybytes') || '';
  ds = [...bb.matchAll(/\\r\\nContent-Disposition: ([^;\\]*)/g)].map((m) => m[1]);
  return `disp by-bytes [${ds.join(',')}]`;
}
function codeOf(r) { return r.done ? `code ${r.done.code}${r.done.status !== '200' ? ` status ${r.done.status}` : ''}` : 'NO-DONE'; }
function methodOf(r) { return `${unq(srvKv(r, 'req').method) || '?'}`; }
function wait(r) { return r.done ? Number(r.done.wait_ms) : NaN; }

// Q1, Q2, Q8: H
const H = names('H:');
table('Q1/Q2/Q8 the head (H): method; Content-Type, B its random boundary; framing; Expect; parse', H,
  (r) => `${codeOf(r)}; ${methodOf(r)}; ${ctOf(r)}; ${sameB(r)}; ${frame(r)}; ${expectOf(r)}; ${parseOf(r)}; ${dispOf(r)}`, FACES);
table('Q1 the boundary: its form and length in the Content-Type (24 dashes, then N characters)', H, (r) => ctForm(r), ['h1']);
table('Q1/Q2 the body sizes: Content-Length, and the bytes read', H, (r) => frame(r, true), ['h1', 'tlsh2']);
table('Q1 the file part (H:file): its part headers and its data against f.txt (512 bytes, sha a6c62a340c7a1a1e)', H.filter((n) => n.includes('file')),
  (r) => `${srvLines(r, 'pline').map((l) => l.replace(/^pline \S+ /, '')).join(' | ')}; ${(() => { const p = kv(srvLine(r, 'part') || ''); return `data ${p.data_len} sha ${p.data_sha}`; })()}`, FACES);
// Q3: T
table('Q3 a caller\'s Content-Type (T), "Expect:" beside it', names('T:'),
  (r) => `${codeOf(r)}; ${ctOf(r)}; boundaries=${srvKv(r, 'ctype').boundaries || 0}; ${parseOf(r)}; ${dispOf(r)}`, FACES);
// Q4, Q8: E
const E = names('E:').filter((n) => n !== 'E:calibrate' && n !== 'E:setopt-only');
table('Q4/Q8 Expect (E): Expect sent; the wait before the body (bucket); a 100 seen by libcurl', E,
  (r) => `${codeOf(r)}; ${expectOf(r)}; wait ${bucket(wait(r))}; ${r.done && r.done.t_100 !== '-1.0' ? 'got-100' : 'no-100'}; ${frame(r)}`, FACES);
// waits' ranges
{
  console.log('\n### Q4 the waits, in ms: min-max over every run, for every E row whose bucket is not none\n');
  const ls = lanes();
  for (const n of E) for (const face of FACES) {
    const row = [];
    for (const l of ls) {
      const ws = [...(runsOf.get(l) || [])].map((run) => recs.get(`${l}|${run}|${n}|${face}`)).filter(Boolean).map(wait).filter((w) => w >= 50);
      if (ws.length) row.push(`${l} ${Math.min(...ws).toFixed(1)}-${Math.max(...ws).toFixed(1)}`);
    }
    if (row.length) console.log(`- \`${n} ${face}\` ${row.join(', ')}`);
  }
  // every E transfer whose Expect went out (the server's hdr line), but the
  // planted tmo-65836: per cont, timeout and HTTP version, over every lane
  // and run, the count, how many waited 50 ms or more, the wait's range, and
  // where a 100 came, whether libcurl saw it before its first body byte, after,
  // or in the same 0.1 ms tick; then that order per lane at timeout 0
  console.log('\n### Q4 every transfer an Expect went out on: count, waits, and the 100 against the first body byte\n');
  const groups = new Map();
  for (const r of recs.values()) {
    if (!r.name.startsWith('E:') || /tmo-65836$/.test(r.name) || !r.done) continue;
    const h = hdr(r);
    if (!h.expect || h.expect === 'none') continue;
    const [, , , cont, tmo] = r.name.split(':');
    const proto = r.face === 'h1' || r.face === 'tlsh1' ? 'HTTP/1.1' : 'HTTP/2';
    for (const key of [`${cont} ${tmo} ${proto}`, `${cont} ${tmo} ${proto} lane ${r.lane}`]) {
      if (!groups.has(key)) groups.set(key, { n: 0, waited: 0, min: Infinity, max: -Infinity, first100: 0, firstBody: 0, tie: 0, no100: 0 });
      const g = groups.get(key);
      const w = wait(r);
      g.n++;
      if (w >= 50) g.waited++;
      g.min = Math.min(g.min, w);
      g.max = Math.max(g.max, w);
      const t100 = Number(r.done.t_100);
      const tb = Number(r.done.t_first_data_out);
      if (t100 < 0) g.no100++;
      else if (t100 < tb) g.first100++;
      else if (t100 > tb) g.firstBody++;
      else g.tie++;
    }
  }
  for (const [k, g] of [...groups].sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (/ lane /.test(k) && !/tmo-0 /.test(k)) continue;
    console.log(`- \`${k}\` n=${g.n} waited=${g.waited} wait=${g.min.toFixed(1)}-${g.max.toFixed(1)}ms 100-before-body=${g.first100} body-before-100=${g.firstBody} same-tick=${g.tie} no-100=${g.no100}`);
  }
  console.log('\n### Q4 calibration and setopt answers\n');
  for (const l of ls) for (const run of [...(runsOf.get(l) || [])].sort()) {
    const r = recs.get(`${l}|${run}|E:calibrate|h1`);
    const cal = r ? r.other.find((o) => o.startsWith('calibration')) : null;
    const sr = recs.get(`${l}|${run}|E:setopt-only|-`);
    const so = sr ? sr.other : [];
    console.log(`- ${l} ${run}: ${cal || 'no calibration'}; ${so.join('; ')}`);
  }
}
// Q5: M
const M = names('M:');
table('Q5 part metadata (M): part 1\'s header lines as they arrived, then part count; any mime call refusal', M,
  (r) => {
    const p1 = kv(srvLines(r, 'part')[0] || '');
    const data = p1.data_len === undefined ? '' : p1.data_len === '1' && p1.data_head === '"v"' ? '' : ` || part1 data ${p1.data_len}b ${p1.data_head}`;
    return `${codeOf(r)}; ${r.other.filter((o) => o.startsWith('mime ')).join(' ')}${srvLines(r, 'pline').filter((l) => /^pline 1\./.test(l)).map((l) => l.replace(/^pline \S+ /, '')).join(' | ')}${data} || ${parseOf(r)}`;
  });
// Q6: D
table('Q6 defaults (D): every part\'s header lines, then each part\'s data length', names('D:'),
  (r) => `${codeOf(r)}; ${r.other.filter((o) => o.startsWith('mime ')).join(' ')}${ctOf(r)}; ${srvLines(r, 'pline').map((l) => l.replace(/^pline /, '')).join(' | ')} || ${srvLines(r, 'part').map((l) => `p${l.split(' ')[1]} ${kv(l).data_len}b`).join(' ')} || ${parseOf(r)}`);
// Q7: W
function bodyKind(r) {
  const b = srvKv(r, 'body');
  const bb = srvLine(r, 'bodybytes') || '';
  if (b.stdin === '1') return 'STDIN';
  if (b.readfn === '1') return 'READFUNCTION';
  if (b.bytes === '0') return 'empty';
  if (/POSTFIELDS-BODY|COPYPOSTFIELDS-BODY|ENGINE-WHOLE-BODY/.test(bb)) return `postfields(${(/(COPYPOSTFIELDS-BODY|POSTFIELDS-BODY|ENGINE-WHOLE-BODY!)/.exec(bb) || [])[1]})`;
  const mpl = srvLine(r, 'mpl');
  if (mpl) return `mime[${(/names=\[(.*)\]/.exec(mpl) || [])[1] || ''}]${/HTTPPOST-BODY/.test(bb) ? '(HTTPPOST\'s)' : ''}`;
  return `other(${b.bytes}b)`;
}
table('Q7 methods and twins (W): method; Content-Type; framing; Expect; which body', names('W:'),
  (r) => `${codeOf(r)}; ${methodOf(r)}; ${ctOf(r)}; ${frame(r)}; ${expectOf(r)}; body ${bodyKind(r)}`);
// Q9: S
table('Q9 size (S): REQUEST_SIZE against the server\'s head bytes (h1) and body bytes; SIZE_UPLOAD_T; CONTENT_LENGTH_UPLOAD_T', names('S:'),
  (r) => {
    const d = r.done || {};
    const head = srvKv(r, 'head');
    const b = srvKv(r, 'body');
    const hb = head.bytes ? Number(head.bytes) : null;
    const rs = Number(d.request_size);
    const rel = hb === null ? 'h2' : rs === hb ? 'req=head' : rs === hb + Number(b.bytes) ? 'req=head+body' : `req-head=${rs - hb}`;
    return `request_size ${d.request_size} (${rel}); size_upload ${d.size_upload}; content_length_upload ${d.content_length_upload}; server body ${b.bytes}${hb === null ? '' : ` head ${hb}`}`;
  }, FACES);
// Q9 across E: the same relation on the big bodies
table('Q9 size on E\'s bodies (none, cont1, timeout unset)', E.filter((n) => /:none:cont1:tmo-unset$/.test(n)),
  (r) => {
    const d = r.done || {};
    const head = srvKv(r, 'head');
    const b = srvKv(r, 'body');
    const hb = head.bytes ? Number(head.bytes) : null;
    const rs = Number(d.request_size);
    const rel = hb === null ? 'h2' : rs === hb ? 'req=head' : rs === hb + Number(b.bytes) ? 'req=head+body' : `req-head=${rs - hb}`;
    return `request_size ${d.request_size} (${rel}); size_upload ${d.size_upload}; server body ${b.bytes}`;
  }, FACES);

// ---------------------------------------------------------------- checks
console.log('\n### Checks\n');
for (const l of lanes()) for (const run of [...(runsOf.get(l) || [])].sort()) {
  const rs = [...recs.values()].filter((r) => r.lane === l && r.run === run && r.face !== '-');
  const done = rs.filter((r) => r.done);
  const nonzero = done.filter((r) => r.done.code !== '0').map((r) => `${r.name} ${r.face} code=${r.done.code}`);
  const gave = done.filter((r) => r.done.gave_up !== '0').map((r) => `${r.name} ${r.face}`);
  const nodone = rs.filter((r) => !r.done).map((r) => `${r.name} ${r.face}`);
  const fetch = rs.filter((r) => r.srv.some((s) => /log fetch failed/.test(s))).length;
  const openq = rs.filter((r) => r.srv.some((s) => /^count .*open=[1-9]/.test(s))).length;
  const nreq = rs.map((r) => r.srv.filter((s) => s.startsWith('req ')).length);
  const zero = rs.filter((r, i) => nreq[i] === 0).map((r) => `${r.name} ${r.face}`);
  const multi = rs.filter((r, i) => nreq[i] > 1).map((r) => `${r.name} ${r.face} x${nreq[rs.indexOf(r)]}`);
  const inc = rs.filter((r) => r.srv.some((s) => /incomplete=1/.test(s))).map((r) => `${r.name} ${r.face}`);
  const refusals = rs.flatMap((r) => r.other.filter((o) => /^(setopt|mime|curl_formadd|curl_url_set|multi_add)/.test(o)).map((o) => `${r.name}: ${o}`));
  // over HTTP/1.1, the head the server read against the one libcurl's
  // debug callback says it sent, byte for byte (both escaped by one rule)
  const h1 = rs.filter((r) => (r.face === 'h1' || r.face === 'tlsh1') && srvLines(r, 'head').length);
  const heads = h1.filter((r) => r.hout.join('|') === srvLines(r, 'head').map((x) => x.replace(/^head bytes=\d+ /, '')).join('|')).length;
  // every E body, but the planted tmo-65836, at the size its name gives
  const eb = rs.filter((r) => /^E:\d+:/.test(r.name) && !/tmo-65836$/.test(r.name));
  const ebOk = eb.filter((r) => srvKv(r, 'body').bytes === r.name.split(':')[1]).length;
  // every HTTP/2 request's content-length against the DATA bytes read
  const h2 = rs.filter((r) => srvKv(r, 'req').proto === 'h2');
  const h2ok = h2.filter((r) => { const c = hdr(r)['content-length']; return c && c !== 'none' && unq(c.replace(/\(x\d+\)$/, '')) === srvKv(r, 'body').bytes; }).length;
  const m = misc.filter((x) => x.lane === l && x.run === run);
  const exits = m.filter((x) => / exit=/.test(x.line)).map((x) => x.line.replace(/^probe /, ''));
  const stderr = m.filter((x) => /server-stderr|the server exited|compile exited/.test(x.line));
  console.log(`- ${l} ${run}: transfers ${rs.length}, done ${done.length}; h1 heads read = sent ${heads} of ${h1.length}; E bodies at their size ${ebOk} of ${eb.length}; h2 content-length = DATA bytes ${h2ok} of ${h2.length}; exits [${exits.join(', ')}]; code!=0 ${nonzero.length ? nonzero.join(', ') : 'none'}; gave-up ${gave.length ? gave.join(', ') : 'none'}; no-done ${nodone.length ? nodone.join(', ') : 'none'}; fetch-failed ${fetch}; open-at-fetch ${openq}; no-request-seen ${zero.length ? zero.join(', ') : 'none'}; more-than-one-request ${multi.length ? multi.join(', ') : 'none'}; incomplete ${inc.length ? inc.join(', ') : 'none'}; refusals ${refusals.length ? refusals.join(' | ') : 'none'}; server-stderr ${stderr.length ? stderr.map((x) => x.line).join(' | ') : 'none'}`);
}
