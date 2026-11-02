// M7 slice 2's tables (2026-11-02), built from the kept logs alone, Node's
// standard library only:
//   node .plans/research/m7/slice2/tables.mjs [TABLE,...]
// It reads results/guix-8.20.0-1.log and results/docker-1.log as run 1, and
// their -2 twins as run 2, and prints, in Markdown, every table, or those
// named: a row per case, a column per lane (F 7.85.0, O 8.5.0 OpenSSL, G
// 8.5.0 GnuTLS, X 8.20.0, C 8.23.0). A cell the two runs disagree on reads
// "**run 1 / run 2**". A table with a face column shows one row for the
// faces whose cells agree on every lane in both runs. Timings, ports, nonces
// and connection numbers are left out of compared cells; what a cell keeps
// is said above each table. With --valgrind it prints instead the
// Valgrind pass (results/valgrind-ubuntu-openssl-8.5.0.log) against lane O's
// two native runs, by code, status and request count alone. It fails, exit
// 1, on a lane or a line it cannot read, and on a case missing from a lane
// or a run.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
// --lanes=NAME,... keeps those lanes alone (for a partial log; the kept
// tables use all five).
const lanesArg = argv.find((a) => a.startsWith('--lanes='));
const lanes = [['floor-7.85.0', 'F'], ['ubuntu-openssl-8.5.0', 'O'], ['ubuntu-gnutls-8.5.0', 'G'],
  ['guix-8.20.0', 'X'], ['current-8.23.0', 'C']].filter(([n]) => !lanesArg || lanesArg.slice(8).split(',').includes(n));
const valgrind = argv.includes('--valgrind');
const only = argv.filter((a) => !a.startsWith('--')).length ? new Set(argv.filter((a) => !a.startsWith('--'))[0].split(',')) : null;
const die = (why) => { process.stderr.write(`tables.mjs: ${why}\n`); process.exit(1); };

// --- reading a log -------------------------------------------------------------

function unescape(s) {
  return s.replace(/\\x([0-9a-f]{2})|\\(.)/g, (m, h, c) => (h ? String.fromCharCode(parseInt(h, 16)) : c));
}
function kv(text) {
  const out = {};
  for (const m of text.matchAll(/(?:^| )([A-Za-z0-9_-]+)=("(?:[^"\\]|\\.)*"|[^ ]*)/g)) out[m[1]] = m[2].startsWith('"') ? m[2].slice(1, -1) : m[2];
  return out;
}

// readRun: FILES' lines, by lane: { cases: [t-line records], tags: Map, refusals: [], origin: [], parts: [] }
function readRun(files) {
  const byLane = new Map();
  const laneOf = (name) => {
    if (!lanes.some(([n]) => n === name)) die(`no lane ${name}`);
    if (!byLane.has(name)) byLane.set(name, { cases: [], tags: new Map(), refusals: [], origin: [], parts: [], lines: [], trace: new Map(), open: null });
    return byLane.get(name);
  };
  for (const file of files) {
    const text = readFileSync(join(here, 'results', file), 'latin1');
    let tree = '?';
    for (const raw of text.split('\n')) {
      const m = /^\[([^\]]+)\] (.*)$/.exec(raw.replace(/\r$/, ""));
      if (!m) continue;
      const L = laneOf(m[1].replace(/ .*/, ''));
      const line = m[2];
      L.lines.push(line);
      let x;
      if ((x = /^verbose-begin (\S+)$/.exec(line))) { L.open = x[1]; L.trace.set(x[1], []); continue; }
      if (/^verbose-end /.test(line)) { L.open = null; continue; }
      if (L.open) { L.trace.get(L.open).push(line); continue; }
      if ((x = /^part (\S+) libdirs (\S+)$/.exec(line))) { tree = x[2] === 'src' ? 'main' : 'prototype'; L.parts.push({ name: x[1], tree }); }
      else if ((x = /^part (\S+) exited (\d+)/.exec(line))) L.parts.push({ name: x[1], exited: Number(x[2]) });
      else if ((x = /^t (\S+) (.*?) ?tag=(\S+)(.*?) => (.*)$/.exec(line))) {
        L.cases.push({ item: x[1], fields: kv(x[2]), tag: x[3], extra: kv(x[4].trim()), outcome: x[5], tree });
      } else if ((x = /^s (\S+) (.*)$/.exec(line))) {
        const tag = x[1];
        if (!L.tags.has(tag)) L.tags.set(tag, { reqs: new Map(), rounds: null, open: false, lines: [] });
        const T = L.tags.get(tag);
        const s = x[2];
        T.lines.push(s);
        let y;
        const req = (n) => { if (!T.reqs.has(n)) T.reqs.set(n, { n }); return T.reqs.get(n); };
        if ((y = /^req #(\d+) (.*)$/.exec(s))) Object.assign(req(Number(y[1])), kv(y[2]));
        else if ((y = /^names #(\d+) (.*)$/.exec(s))) req(Number(y[1])).names = y[2];
        else if ((y = /^head #(\d+) "(.*)"$/.exec(s))) req(Number(y[1])).head = unescape(y[2]);
        else if ((y = /^auth #(\d+) value=(.*)$/.exec(s))) { const r = req(Number(y[1])); (r.auths ||= []).push(y[2].startsWith('"') ? unescape(y[2].slice(1, -1)) : y[2]); }
        else if ((y = /^(basic|bearer|digest|other) #(\d+) (.*)$/.exec(s))) {
          const r = req(Number(y[2]));
          r.verdict = y[1] === 'digest' ? y[3].split(' ')[0] : y[3];
          r.vk = kv(y[3]);
          r.vline = y[3];
        } else if ((y = /^answer #(\d+) status=(\d+) (.*)$/.exec(s))) { const r = req(Number(y[1])); r.status = y[2]; r.answer = y[3]; }
        else if (s.startsWith('rounds ')) {
          const brackets = (text) => [...text.matchAll(/\[#(\d+) (\S+) (\S+) conn=(\d+) auth=([^ ]+) status=(\S+) (\S+) body=([^\]]*)\]/g)]
            .map((r) => ({ n: Number(r[1]), face: r[2], method: r[3], conn: r[4], auth: r[5], status: r[6], when: r[7], body: r[8] }));
          const more = / more=(\d+) last (.*)$/.exec(s);
          T.total = Number(/^rounds n=(\d+)/.exec(s)[1]);
          T.rounds = brackets(more ? s.slice(0, more.index) : s);
          if (more) { T.more = Number(more[1]); T.last = brackets(more[2])[0]; }
        }
        else if (s.startsWith('log: ')) T.open = true;
      } else if ((x = /^r case=(\S+) => (.*)$/.exec(line))) L.refusals.push({ tree, kase: x[1], outcome: x[2] });
      else if (line.startsWith('o ')) {
        const o = {};
        for (const m of line.slice(2).matchAll(/([a-z-]+)=(\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)|\S+)/g)) o[m[1]] = m[2];
        L.origin.push(o);
      }
    }
  }
  return byLane;
}

// --runs=A,B;C,D reads other logs as runs 1 and 2, relative to results/.
const runsArg = argv.find((a) => a.startsWith('--runs='));
const runFiles = runsArg ? runsArg.slice(7).split(';').map((r) => r.split(',')) : [['guix-8.20.0-1.log', 'docker-1.log'], ['guix-8.20.0-2.log', 'docker-2.log']];
const kept = valgrind ? [] : runFiles.map(readRun);

// --- rendering ---------------------------------------------------------------

// sequence's ·E marks a request that carried an Expect header.
const schemeLabel = (a) => ({ none: '–', basic: 'Basic', digest: 'Digest', bearer: 'Bearer', 'aws4-hmac-sha256': 'AWS4' }[a] ?? a);
function bodyNote(b) {
  if (b === '0' || b === '-') return '';
  if (b === 'none-sent') return '{none sent}';
  const m = /^(\d+)(?::pattern=(\w+@?\d*))?(?::sha=\w+)?(\(closed\))?$/.exec(b);
  if (!m) return `{${b}}`;
  return `{${m[1]}${m[2] && m[2] !== 'ok' ? ` ${m[2]}` : ''}${m[3] ? ', closed' : ''}}`;
}
// roundLabel: one request at the stand-in: scheme, verdict, status, when, body.
function roundLabel(r) {
  const [scheme, verdict, many] = r.auth.split(':');
  const mark = verdict === 'ok' ? '✓' : verdict === 'bad' ? '✗' : '';
  const when = r.when === 'early' ? ' at head' : r.when === 'mid' ? ' mid-body' : '';
  return `${schemeLabel(scheme)}${mark}${many ? ` ${many}` : ''}/${r.status}${when}${bodyNote(r.body)}`;
}
// sequence: a tag's requests, runs of one label folded as "N × label".
function sequence(T, conns) {
  if (!T || !T.rounds) return 'no log';
  const expect = (r) => ((T.reqs.get(r.n)?.names || '').split(',').includes('expect') ? '·E' : '');
  const labels = T.rounds.map((r) => `${conns ? `${conns(r)}:` : ''}${roundLabel(r)}${expect(r)}`);
  const out = [];
  for (let i = 0; i < labels.length;) {
    let j = i;
    while (j < labels.length && labels[j] === labels[i]) j++;
    out.push(j - i > 2 ? `${j - i} × ${labels[i]}` : labels.slice(i, j).join(' → '));
    i = j;
  }
  const many = (n) => (n >= 1000 ? 'over 1,000' : String(n));
  const tail = T.more ? ` → ${many(T.more)} more, the last ${conns ? `${conns(T.last)}:` : ''}${roundLabel(T.last)} (${T.total >= 1000 ? 'over 1,000' : T.total} requests)` : '';
  return `${out.join(' → ')}${tail}${T.open ? ' (open 3 s on)' : ''}`;
}
function outcome(o) {
  if (o.startsWith('ok ')) return `${kv(o).status}`;
  if (o.startsWith('fail ')) {
    const k = kv(o);
    const none = k.sent === '0' ? ', nothing sent' : '';
    return k.reason === 'perform-failed' ? `fails ${k.code}${none}` : `${k.reason} ${k.code ?? ''}${none}`.trim();
  }
  if (o.startsWith('refused ')) return `refused ${kv(o).reason}`;
  if (o.startsWith('condition ')) return 'condition';
  return o.split(' ')[0];
}
// conns: a labeller giving each (face, conn) of a group A, B, C... in order.
function connLabeller() {
  const seen = new Map();
  return (r) => {
    const k = `${r.face}#${r.conn}`;
    if (!seen.has(k)) seen.set(k, String.fromCharCode(65 + seen.size));
    return seen.get(k);
  };
}

// --- tables ------------------------------------------------------------------

const tables = [];
function table(id, title, note, columns, rowsOf, fold = ['face'], data = kept) {
  if (only && !only.has(id)) return;
  // rowsOf(laneData, laneName) -> [[keyArray, cell]...]
  const rows = new Map();
  for (const [run, runData] of data.entries()) {
    for (const [laneName] of lanes) {
      const L = runData.get(laneName);
      if (!L) die(`${id}: no lane ${laneName} in run ${run + 1}`);
      for (const [key, cell] of rowsOf(L, laneName)) {
        const k = key.join(' | ');
        if (!rows.has(k)) rows.set(k, { key, cells: new Map() });
        const c = `${laneName}#${run}`;
        if (rows.get(k).cells.has(c)) die(`${id} ${k} ${laneName} run ${run + 1} twice`);
        rows.get(k).cells.set(c, cell);
      }
    }
  }
  const render = (row) => lanes.map(([n]) => {
    const a = row.cells.get(`${n}#0`);
    const b = row.cells.get(`${n}#1`);
    if (a === undefined || b === undefined) die(`${id} ${row.key.join(' | ')}: ${n} lacks run ${a === undefined ? 1 : 2}`);
    return a === b ? a : `**${a} / ${b}**`;
  });
  let list = [...rows.values()];
  // Rows that differ only in a fold column, and agree on every lane in both
  // runs, become one row naming each value, in order: each fold column in turn.
  for (const col of fold) {
    const fi = columns.indexOf(col);
    if (fi < 0) continue;
    const groups = new Map();
    for (const row of list) {
      const g = `${row.key.filter((_, i) => i !== fi).join(' | ')}#${render(row).join(' | ')}`;
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g).push(row);
    }
    const merged = [];
    for (const g of groups.values()) {
      if (g.length > 1) {
        const key = [...g[0].key];
        key[fi] = g.map((r) => r.key[fi]).join(', ');
        merged.push({ key, cells: g[0].cells, order: Math.min(...g.map((r) => list.indexOf(r))) });
      } else merged.push({ ...g[0], order: list.indexOf(g[0]) });
    }
    list = merged.sort((a, b) => a.order - b.order);
  }
  tables.push(`\n### ${title}\n\n${note}\n\n| ${columns.join(' | ')} | ${lanes.map(([, s]) => s).join(' | ')} |\n|${columns.map(() => '---|').join('')}${lanes.map(() => '---|').join('')}\n${list.map((r) => `| ${r.key.join(' | ')} | ${render(r).join(' | ')} |`).join('\n')}\n`);
}
const tagOf = (L, c) => L.tags.get(c.tag);
const casesOf = (L, item) => L.cases.filter((c) => c.item === item);

// refusals
table('refusals', 'The hatch, on main\'s `src/` and on the prototype (`r` lines)',
  'A cell: `attached`, or the refusal\'s reason, or `condition` for an assertion violation (the option takes a string).',
  ['case', 'tree'], (L) => L.refusals.map((r) => [[r.kase, r.tree], r.outcome.startsWith('refused') ? `refused ${kv(r.outcome).reason}` : r.outcome.startsWith('condition') ? 'condition: takes a string' : r.outcome]));

// item 1
table('i1', 'Item 1: each scheme, each case (`i1` lines)',
  'A cell: each request at the stand-in, in order: its `Authorization` scheme (– none), the stand-in\'s verdict (✓ valid, ✗ refused), its status, `{N}` the body bytes it read; then ⇒ the final status, or the code. Every case ran on a fresh engine.',
  ['scheme', 'case', 'method', 'face'],
  (L) => casesOf(L, 'i1').map((c) => [[c.fields.scheme, c.fields.case, c.fields.method, c.fields.face], `${sequence(tagOf(L, c))} ⇒ ${outcome(c.outcome)}`]),
  ['face', 'scheme']);

// item 1's headers whole
function maskDigest(v) {
  return v.replace(/nonce="[0-9a-f]+"/, 'nonce=N').replace(/cnonce="[^"]*"/, 'cnonce=CN').replace(/response="[0-9a-f]+"/, 'response=R')
    .replace(/uri="[^"]*"/, 'uri=U');
}
table('i1auth', 'Item 1: the `Authorization` sent, whole (`i1`, right credentials, get)',
  'A cell: the value of the last request\'s `Authorization`, as the stand-in received it; for Digest, the nonce, cnonce, response and uri replaced by N, CN, R and U (each verified by the stand-in, `ok` in item 1\'s table).',
  ['scheme', 'face'],
  (L) => casesOf(L, 'i1').filter((c) => c.fields.case === 'right' && c.fields.method === 'get').map((c) => {
    const T = tagOf(L, c);
    const last = T ? [...T.reqs.values()].pop() : null;
    const v = last && last.auths ? last.auths.join(' + ') : 'none';
    return [[c.fields.scheme, c.fields.face], `\`${maskDigest(v)}\``];
  }));

// item 5 (a): Digest's round and its connection, from item 1
table('i5round', 'Item 5 (a): Digest\'s second request and the first\'s connection (from `i1`, right credentials)',
  'A cell: for each Digest variant with a second request, `same` when it rode the first\'s connection, else `other`, counted: 8 of the 10 variants per face and method send one (`-sess` without `qop` does not).',
  ['method', 'face'],
  (L) => {
    const acc = new Map();
    for (const c of casesOf(L, 'i1')) {
      if (!c.fields.scheme.startsWith('digest') || c.fields.case !== 'right') continue;
      const T = tagOf(L, c);
      if (!T || !T.rounds || T.rounds.length < 2) continue;
      const k = `${c.fields.method}|${c.fields.face}`;
      if (!acc.has(k)) acc.set(k, { same: 0, other: 0 });
      acc.get(k)[T.rounds[1].conn === T.rounds[0].conn && T.rounds[1].face === T.rounds[0].face ? 'same' : 'other']++;
    }
    return [...acc].map(([k, v]) => [k.split('|'), `${v.same ? `same ×${v.same}` : ''}${v.same && v.other ? ', ' : ''}${v.other ? `other ×${v.other}` : ''}`]);
  });

// wholeOrPart: CELL with each body count {N...} as {whole...} when N is
// TOTAL, else {part...}: how much of a body cut short the stand-in read
// races, so the compared cells keep whether it was whole alone.
const wholeOrPart = (cell, total) => cell.replace(/\{(\d+)(, closed)?\}/g, (m, n, c) => `{${Number(n) === total ? 'whole' : 'part'}${c || ''}}`);

// item 2
const streamCell = (L, c) => {
  const e = c.extra;
  const prod = e['last-put'] ? `last put ${e['last-put']}` : `head ${e.head}, read ${e.read}${e.end === 'timeout' ? ', timeout' : ''}`;
  return `${outcome(c.outcome)}; ${sequence(tagOf(L, c))}; ${prod}`;
};
table('i2', 'Item 2: streams (`i2` lines)',
  'A cell: the outcome; the requests at the stand-in, `{whole}` or `{part}` of the 256 KiB body it read (`closed` when the client closed first); for a streamed body the producer\'s last put (`end`: every piece taken, then the end; `done`: the transfer had ended; `#f`: its 3 s bound passed), for a streamed response the head the token published and the body bytes read. How much of a body cut short the stand-in read races; the counts are in the next table.',
  ['scheme', 'case', 'kind', 'when', 'face'],
  (L) => casesOf(L, 'i2').map((c) => [[c.fields.scheme, c.fields.case, c.fields.kind, c.fields.when, c.fields.face],
    wholeOrPart(streamCell(L, c), 262144)]));

if (!only || only.has('i2times')) {
  // not a compared table: each run's numbers side by side
  const rows = new Map();
  for (const [run, data] of kept.entries()) {
    for (const [laneName, s] of lanes) {
      for (const c of casesOf(data.get(laneName), 'i2')) {
        const k = [c.fields.scheme, c.fields.case, c.fields.kind, c.fields.when, c.fields.face].join(' | ');
        if (!rows.has(k)) rows.set(k, new Map());
        const T = tagOf(data.get(laneName), c);
        const got = T && T.rounds ? T.rounds.map((r) => r.body.replace(/:pattern=\w+:sha=\w+/, '')).join('+') : '-';
        rows.get(k).set(`${s}#${run}`, `${c.extra.ms ?? '-'} ms${c.extra.count ? `, put ${c.extra.count}` : ''}, got ${got}`);
      }
    }
  }
  tables.push(`\n### Item 2: times and bytes, run 1; run 2 (not compared)\n\nA cell: ms from the submit to the end; for a streamed body the bytes the puts committed (\`curl-token-body-count\`); the bytes the stand-in read per request.\n\n| case | ${lanes.map(([, s]) => s).join(' | ')} |\n|---|${lanes.map(() => '---|').join('')}\n${[...rows].map(([k, m]) => `| ${k} | ${lanes.map(([, s]) => `${m.get(`${s}#0`)}; ${m.get(`${s}#1`)}`).join(' | ')} |`).join('\n')}\n`);
}

// item 3
const sentOf = (T) => {
  if (!T) return 'no log';
  const each = [...T.reqs.values()].map((r) => {
    if (!r.auths) return '–';
    const s = r.vk || {};
    if (r.vk === undefined) return r.auths[0].length > 60 ? `${r.auths[0].slice(0, 60)}...` : r.auths[0];
    if (r.auths[0].startsWith('Basic')) return `Basic "${s.decoded !== undefined ? unescape(s.decoded) : '?'}"`;
    if (r.auths[0].startsWith('Bearer')) return `Bearer "${s.token !== undefined ? unescape(s.token) : r.auths[0].slice(7)}"`;
    if (r.auths[0].startsWith('Digest')) return `Digest username="${s.username !== undefined ? unescape(s.username) : '?'}"`;
    return r.auths[0].split(' ')[0];
  });
  const out = [];
  for (let i = 0; i < each.length;) {
    let j = i;
    while (j < each.length && each[j] === each[i]) j++;
    out.push(j - i > 2 ? `${j - i} × ${esc(each[i])}` : each.slice(i, j).map(esc).join(' → '));
    i = j;
  }
  return out.join(' → ') + (T.more ? ' → ...' : '');
};
const esc = (s) => s.replace(/[\x00-\x1f\x7f-\xff\\|`]/g, (ch) => (ch === '\\' ? '\\\\' : ch === '|' ? '\\|' : ch === '`' ? '\\`' : `\\x${ch.charCodeAt(0).toString(16).padStart(2, '0')}`));
table('i3', 'Item 3: empty values (`i3` lines)',
  'A cell: each request\'s credentials as the stand-in decoded them; then the requests in order, as in item 1; ⇒ the final status or code.',
  ['scheme', 'user', 'pass', 'token', 'face'],
  (L) => casesOf(L, 'i3').map((c) => [[c.fields.scheme, c.fields.user, c.fields.pass, c.fields.token, c.fields.face],
    `${sentOf(tagOf(L, c))}; ${sequence(tagOf(L, c))} ⇒ ${outcome(c.outcome)}`]));

// item 4
const known = new Set(['host', 'authorization', 'accept', 'user-agent', 'content-length', 'content-type', 'expect', 'transfer-encoding']);
// extraNames: the header names T's requests carried beyond known, each
// once, with the requests that carried it: "+header referer (#2)".
function extraNames(T) {
  if (!T) return '';
  const seen = new Map();
  for (const r of T.reqs.values()) {
    for (const n of (r.names || '').split(',')) {
      if (!n || known.has(n)) continue;
      if (!seen.has(n)) seen.set(n, []);
      seen.get(n).push(`#${r.n}`);
    }
  }
  return [...seen].map(([n, rs]) => ` +header ${n} (${rs.join(',')})`).join('');
}
function bytesCell(L, c) {
  const T = tagOf(L, c);
  const o = outcome(c.outcome);
  if (!T || !T.reqs.size) return `${o}, no request reached the stand-in`;
  const last = [...T.reqs.values()].pop();
  const extra = (last.names || '').split(',').filter((n) => n && !known.has(n));
  const head = last.head || '';
  const bare = /[^\r]\n|\r(?!\n)/.test(head) ? ' bare CR or LF in head' : '';
  const own = extra.length ? ` +header ${extra.join(',')}` : '';
  let what = sentOf(T);
  if (last.vk && last.vk.decoded && (unescape(last.vk.decoded).match(/:/g) || []).length > 1) what += ` (user "${esc(unescape(last.vk.user))}" by the first colon)`;
  if (last.vline && /username\*=/.test(last.vline)) what += ` username*=${esc(unescape(/username\*="([^"]*)"/.exec(last.vline)[1]))}`;
  const verdict = last.verdict ? (last.verdict.includes('match=yes') || last.verdict === 'ok' ? 'valid' : last.verdict.startsWith('bad') ? last.verdict : 'refused') : '';
  return `${what}; ${verdict || (last.auths ? 'no verdict' : 'no Authorization arrived')}${own}${bare} ⇒ ${o}`;
}
table('i4', 'Item 4: hostile and edge bytes, `a` BYTE `b` (`i4` lines)',
  'A cell: what the stand-in received, escaped as `\\xNN` (for Digest the `username` parameter, unquoted, and any `username*`); the verdict, the stand-in\'s own arithmetic on the bytes set (`valid`, `refused`, or Digest\'s `bad(...)` list); `+header N` for a header name no request otherwise carries, a header of its own; `bare CR or LF in head`; ⇒ the final status or code; `no request reached the stand-in` when none did, and `nothing sent` when the failure\'s request size is 0.',
  ['field', 'scheme', 'byte', 'face'],
  (L) => casesOf(L, 'i4').map((c) => [[c.fields.field, c.fields.scheme, c.fields.byte, c.fields.face], bytesCell(L, c)]));

table('i4len', 'Item 4: lengths (`i4len` lines)',
  'A cell: the outcome (a setopt refusal names its code); the stand-in\'s verdict on the bytes it received, and their length.',
  ['field', 'scheme', 'length', 'face'],
  (L) => casesOf(L, 'i4len').map((c) => {
    const T = tagOf(L, c);
    const o = c.outcome.startsWith('fail ') && kv(c.outcome).reason === 'setopt-failed' ? `setopt ${kv(c.outcome).code} ${kv(c.outcome).option}` : outcome(c.outcome);
    const reqs = T ? [...T.reqs.values()] : [];
    const last = reqs.pop();
    let got = 'nothing sent';
    if (last) {
      const v = last.vk || {};
      const len = (s) => { if (!s) return '?'; const m = /^len=(\d+)/.exec(s); return m ? m[1] : String(unescape(s).length); };
      if (!last.auths) got = 'no Authorization';
      else if (last.auths[0].startsWith('Basic') || /^len=/.test(last.auths[0])) got = `${last.verdict && last.verdict.includes('match=yes') ? 'valid' : last.verdict && last.verdict.startsWith('bad') ? last.verdict : 'refused'}, header ${len(last.auths[0].startsWith('len=') ? last.auths[0] : null) || last.auths[0].length} bytes`;
      else got = `${last.verdict && (last.verdict.includes('match=yes') || last.verdict === 'ok') ? 'valid' : last.verdict}`;
      if (T.rounds) got += `; ${sequence(T)}`;
    }
    return [[c.fields.field, c.fields.scheme, c.fields.length, c.fields.face], `${o}; ${got}`];
  }));

table('i4trace', 'Item 4: control bytes over h2, in libcurl\'s own trace (`i4trace` lines)',
  'The h2 face\'s HTTP/2 stack drops a field holding a control byte before the stand-in sees it, so these cases ran again with `VERBOSE`. A cell: each `authorization` field libcurl\'s trace shows it handing HTTP/2 (`[HTTP/2] [N] [...]` from 8.5.0, `h2h3 [...]` on 7.85.0), escaped, the nonce and response cut; then the outcome, and the stand-in\'s view as in item 4.',
  ['field', 'scheme', 'byte', 'face'],
  (L) => casesOf(L, 'i4trace').map((c) => {
    const lines = L.trace.get(c.tag) || [];
    const got = [];
    for (let i = 0; i < lines.length; i++) {
      if (!/(\[HTTP\/2\] \[\d+\] |h2h3 )\[authorization: /i.test(lines[i])) continue;
      let v = lines[i].replace(/^.*?\[authorization: /i, '');
      if (!v.endsWith(']') && i + 1 < lines.length) v += `\n${lines[i + 1]}`;
      v = v.replace(/\]$/, '').replace(/, realm=.*$/s, ', ...');
      got.push(esc(v));
    }
    return [[c.fields.field, c.fields.scheme, c.fields.byte, c.fields.face],
      `${got.length ? got.map((g) => `\`${g}\``).join(' → ') : 'no authorization field traced'}; ${bytesCell(L, c)}`];
  }));

// item 5
table('i5expect', 'Item 5 (b): a caller\'s `Expect: 100-continue`, a 64 KiB `post` (`i5expect` lines)',
  'Modes: `417`, the stand-in answers 417 to every request carrying it; `417once`, to the first alone; `401`, a head that would fail is answered 401 before any 100. A cell: the requests, as in item 1 (`{none sent}`: the next bytes began a request), ⇒ the final status or code. Every transfer\'s timeout-ms is 5,000.',
  ['scheme', 'case', 'mode', 'face'],
  (L) => casesOf(L, 'i5expect').map((c) => [[c.fields.scheme, c.fields.case, c.fields.mode, c.fields.face], `${sequence(tagOf(L, c))} ⇒ ${outcome(c.outcome)}`]));

table('i5stale', 'Item 5 (c): the first valid request (or two) answered 401 again (`i5stale` lines)',
  'Digest\'s second 401 carries `stale=true` and a new nonce; Basic\'s and Bearer\'s carry the route\'s challenge. A cell as in item 1.',
  ['scheme', 'stale', 'face'],
  (L) => casesOf(L, 'i5stale').map((c) => [[c.fields.scheme, c.fields.stale, c.fields.face], `${sequence(tagOf(L, c))} ⇒ ${outcome(c.outcome)}`]));

table('i5follow', 'Item 5 (d): the private follow, a 302 from the first hop (`i5follow` lines)',
  'A cell: each request, with its connection as a letter (A, B ... in order of first use; another letter is another connection), as in item 1, ⇒ the final status. The first hop is `http://127.0.0.1` (`localhost` in `localhost-to-ip`), the h2 face in `h2-same-origin`; `http-to-https-same-port` changes the scheme alone, on one port.',
  ['scheme', 'target', 'UNRESTRICTED_AUTH'],
  (L) => casesOf(L, 'i5follow').map((c) => [[c.fields.scheme, c.fields.target, c.fields.unrestricted], `${sequence(tagOf(L, c), connLabeller())} ⇒ ${outcome(c.outcome)}`]));

table('peers', 'Items 5 and 8: the address each request to `localhost` reached (`i5follow`, `i8` lines)',
  'A cell: each request\'s peer address at the stand-in, in order; every face listens on 127.0.0.1 and on ::1 at one port.',
  ['item', 'scheme', 'target', 'UNRESTRICTED_AUTH'],
  (L) => [...casesOf(L, 'i5follow'), ...casesOf(L, 'i8').filter((c) => c.fields.step === '1')]
    .filter((c) => /localhost|other-host/.test(c.fields.target))
    .map((c) => [[c.item, c.fields.scheme, c.fields.target, c.fields.unrestricted || '-'],
      [...(tagOf(L, c)?.reqs.values() || [])].map((r) => r.peer).join(', ')]));

// item 6
table('i6', 'Item 6: transfers on one engine (`i6` lines)',
  'A cell: each request of the step, its connection a letter shared by the case\'s two steps (A, B ... in order of first use), as in item 1, ⇒ its final status. `together`: both submitted in one batch; `after-head`: the second submitted once the first\'s head was in.',
  ['case', 'scheme', 'face', 'step'],
  (L) => {
    const out = [];
    const groups = new Map();
    for (const c of casesOf(L, 'i6')) {
      const g = [c.fields.case, c.fields.scheme, c.fields.face].join('|');
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g).push(c);
    }
    for (const cs of groups.values()) {
      const lab = connLabeller();
      cs.sort((a, b) => Number(a.fields.step) - Number(b.fields.step));
      // label in arrival order across the two steps
      const all = cs.flatMap((c) => (tagOf(L, c)?.rounds || []).map((r) => ({ r, c })));
      for (const { r } of all.sort((a, b) => 0)) lab(r);
      for (const c of cs) {
        const extra = c.extra.head ? `; head ${c.extra.head}` : c.extra['first-done-at-second-end'] ? `; first done at second's end ${c.extra['first-done-at-second-end']}` : '';
        out.push([[c.fields.case, c.fields.scheme, c.fields.face, c.fields.step], `${sentOf(tagOf(L, c))}; ${sequence(tagOf(L, c), lab)} ⇒ ${outcome(c.outcome)}${extra}`]);
      }
    }
    return out;
  });

// item 7
table('i7', 'Item 7: the twins (`i7` lines)',
  'A cell: the requests\' credentials as the stand-in decoded them (an `AWS4-HMAC-SHA256` header named by its scheme), and `+header N (#K)` for a header no request otherwise carries, with the requests that carried it; the requests, as in item 1 (a verdict ✗ on `AWS4` is the stand-in knowing no such scheme); ⇒ the final status or code. Every case is a `get` to the `http` face with the route\'s challenge for the scheme, but where named: `AWS_SIGV4-*` to an open route, `*-post` a 64 KiB `post`, `early-401-*` a 1 MiB `post` answered 401 at its head, `stream-*` a streamed 256 KiB body answered 401 at its head.',
  ['twin', 'scheme', 'face'],
  (L) => casesOf(L, 'i7').map((c) => [[c.fields.twin, c.fields.scheme, c.fields.face || 'http'],
    ((cell) => (/^early-401/.test(c.fields.twin) ? wholeOrPart(cell, 1048576) : /^stream-/.test(c.fields.twin) ? wholeOrPart(cell, 262144) : cell))(
      `${sentOf(tagOf(L, c))}${extraNames(tagOf(L, c))}; ${sequence(tagOf(L, c))} ⇒ ${outcome(c.outcome)}${c.extra['last-put'] ? `; last put ${c.extra['last-put']}` : ''}`)]));

// item 8
table('i8', 'Item 8: a redirect\'s hops built by hand on one engine (`i8` lines)',
  'Step 1 is a `get` to `http://127.0.0.1` answered 302 once the credentials pass; step 2 a fresh transfer on the same engine to the `Location`, with the same credentials by the hatch. A cell: each request of the two steps, its connection a letter (the same letter in step 2 is step 1\'s pooled connection), as in item 1; ⇒ each step\'s final status.',
  ['scheme', 'target'],
  (L) => {
    const by = new Map();
    for (const c of casesOf(L, 'i8')) {
      const k = `${c.fields.scheme}|${c.fields.target}`;
      if (!by.has(k)) by.set(k, []);
      by.get(k).push(c);
    }
    return [...by].map(([k, cs]) => {
      const T = tagOf(L, cs[0]);
      return [k.split('|'), `${sequence(T, connLabeller())} ⇒ ${cs.map((c) => outcome(c.outcome)).join(', ')}`];
    });
  });

table('i8creds', 'Item 8: what each hop\'s credentials decoded to (`i8` lines)',
  'A cell: each request\'s credentials as the stand-in decoded them, in order, across the two steps.',
  ['scheme', 'target'],
  (L) => {
    const seen = new Set();
    return casesOf(L, 'i8').filter((c) => { const k = `${c.fields.scheme}|${c.fields.target}`; if (seen.has(k)) return false; seen.add(k); return true; })
      .map((c) => [[c.fields.scheme, c.fields.target], sentOf(tagOf(L, c))]);
  });

table('origin', 'Item 8: today\'s origin rule, by `exchange-step` (`o` lines)',
  'A 302 from A to the Location B, the request carrying `Authorization`, `Cookie` and `X-Other`. A cell: the headers the next request keeps (dropped ones are another origin\'s), and the parts `curl-url-part` gave B (scheme, host, port).',
  ['A', 'Location B'],
  (L) => L.origin.map((o) => [[o.a, o.b], `${o.answer} ${o['next-headers']}; B ${o['b-parts']}`]));

// --- the MAXREDIRS addition (maxredirs.sps, its own logs) ------------------------
if (!valgrind && (!only || only.has('maxredirs') || only.has('maxredirs-times'))) {
  const mrRuns = runsArg ? null : [readRun(['maxredirs-guix-8.20.0-1.log', 'maxredirs-docker-1.log']),
    readRun(['maxredirs-guix-8.20.0-2.log', 'maxredirs-docker-2.log'])];
  if (!mrRuns) die('maxredirs: give no --runs');
  const reqs = (T) => (T && T.rounds ? (T.total ?? T.rounds.length) : 0);
  const lastStatus = (T) => (T && T.rounds && T.rounds.length ? (T.last || T.rounds[T.rounds.length - 1]).status : '-');
  table('maxredirs', 'MAXREDIRS beside a loop, a stale Digest and a round (`mr` lines, `maxredirs.sps`)',
    'Each case on an engine of its own, `timeout-ms` 5,000, MAXREDIRS unset (libcurl\'s default: -1 on 7.85.0, 30 from 8.7.1) or set to 30 by the hatch. `expect417`: rounds1\'s case, a 64 KiB `post` with a caller\'s `Expect: 100-continue`, the stand-in answering 417 to every request carrying it; `stale-forever`: Digest against a route that answers every valid response 401 `stale=true`, a new nonce each time; `round`: Digest against a route that challenges once. A cell: the requests the stand-in counted (`over 1,000` past it, the exact counts in the next table), the last one\'s status, ⇒ the final status or code.',
    ['case', 'scheme', 'MAXREDIRS'],
    (L) => L.cases.filter((c) => c.item === 'mr').map((c) => {
      const T = tagOf(L, c);
      const n = reqs(T);
      return [[c.fields.case, c.fields.scheme, c.fields.maxredirs], `${n >= 1000 ? 'over 1,000 requests' : n === 1 ? '1 request' : `${n} requests`}, the last ${lastStatus(T)} ⇒ ${outcome(c.outcome)}`];
    }), [], mrRuns);
  if (!only || only.has('maxredirs-times')) {
    const rows = new Map();
    const checks = [];
    for (const [run, data] of mrRuns.entries()) {
      for (const [laneName, s] of lanes) {
        const L = data.get(laneName);
        if (!L) die(`maxredirs: no lane ${laneName} in run ${run + 1}`);
        for (const c of L.cases.filter((x) => x.item === 'mr')) {
          const k = [c.fields.case, c.fields.scheme, c.fields.maxredirs].join(' | ');
          if (!rows.has(k)) rows.set(k, new Map());
          rows.get(k).set(`${s}#${run}`, `${reqs(tagOf(L, c))} req, ${c.extra.ms} ms`);
        }
        const exits = L.parts.filter((p) => p.exited !== undefined);
        checks.push(`| ${s} | ${run + 1} | ${exits.map((p) => `${p.name} exited ${p.exited}`).join(', ')} | ${L.lines.filter((l) => l.startsWith('standin selftest')).join('; ')} | ${L.lines.filter((l) => l.startsWith('native ')).filter((l) => /\. [1-9]/.test(l)).length} nonzero | ${L.cases.filter((x) => x.outcome === 'hung').length} | ${L.lines.filter((l) => /standin-stderr|^Exception|log-fetch-failed/.test(l)).length} |`);
      }
    }
    tables.push(`\n### MAXREDIRS: the requests counted and the time to the end, run 1; run 2 (not compared)\n\nA cell: the stand-in's count of the transfer's requests, and ms from the submit to the end.\n\n| case | scheme | MAXREDIRS | ${lanes.map(([, s]) => s).join(' | ')} |\n|---|---|---|${lanes.map(() => '---|').join('')}\n${[...rows].map(([k, m]) => `| ${k} | ${lanes.map(([, s]) => `${m.get(`${s}#0`)}; ${m.get(`${s}#1`)}`).join(' | ')} |`).join('\n')}\n\n| lane | run | exits | self-test | native counts | hung | error lines |\n|---|---|---|---|---|---|---|\n${checks.join('\n')}\n`);
  }
}

// --- checks ---------------------------------------------------------------------
if (!valgrind && (!only || only.has('checks'))) {
  const lines = [];
  for (const [run, data] of kept.entries()) {
    for (const [laneName, s] of lanes) {
      const L = data.get(laneName);
      const exits = L.parts.filter((p) => p.exited !== undefined);
      const bad = exits.filter((p) => p.exited !== 0).map((p) => `${p.name}=${p.exited}`);
      const self = L.lines.filter((l) => l.startsWith('standin selftest'));
      const native = L.lines.filter((l) => l.startsWith('native '));
      const nonzero = native.filter((l) => /\. [1-9]/.test(l));
      const hung = L.cases.filter((c) => c.outcome === 'hung').length;
      const errs = L.lines.filter((l) => /standin-stderr|exited [1-9]|^Exception|log-fetch-failed/.test(l)).length;
      const open = [...L.tags.values()].filter((t) => t.open).length;
      lines.push(`| ${s} | ${run + 1} | ${exits.length} parts, ${bad.length ? `not 0: ${bad.join(' ')}` : 'all 0'} | ${self.join('; ')} | ${native.length} native, ${nonzero.length} nonzero | ${L.cases.length} | ${hung} | ${open} | ${errs} |`);
    }
  }
  tables.push(`\n### Checks, each lane-run\n\n| lane | run | exits | self-test | counts | transfers | hung | tags still open 3 s on | error lines |\n|---|---|---|---|---|---|---|---|---|\n${lines.join('\n')}\n`);
}

// --- Valgrind -------------------------------------------------------------------
if (valgrind) {
  // --against=LANE compares with another lane's native runs instead: the
  // control, which must differ where that lane's libcurl does.
  const againstArg = argv.find((a) => a.startsWith('--against='));
  const against = againstArg ? againstArg.slice(10) : 'ubuntu-openssl-8.5.0';
  const native = [readRun(['docker-1.log']), readRun(['docker-2.log'])].map((d) => d.get(against));
  const vg = readRun(['valgrind-ubuntu-openssl-8.5.0.log']).get('ubuntu-openssl-8.5.0');
  if (!vg) die('no Valgrind lane');
  const brief = (L, c) => {
    const T = tagOf(L, c);
    const n = T && T.rounds ? (T.total ?? T.rounds.length) : 0;
    return `${outcome(c.outcome)}, ${n} req, ${T && T.rounds ? T.rounds.map((r) => r.status).join('/') : '-'}`;
  };
  const key = (c) => `${c.item} ${Object.entries(c.fields).map(([k, v]) => `${k}=${v}`).join(' ')}`;
  const nmaps = native.map((L) => new Map(L.cases.filter((c) => ['i1', 'i2', 'i6'].includes(c.item)).map((c) => [key(c), brief(L, c)])));
  let same = 0; const differ = [];
  const vcases = vg.cases.filter((c) => ['i1', 'i2', 'i6'].includes(c.item));
  for (const c of vcases) {
    const v = brief(vg, c);
    const a = nmaps[0].get(key(c)); const b = nmaps[1].get(key(c));
    if (a === undefined || b === undefined) die(`valgrind: ${key(c)} not in a native run`);
    if (v === a && v === b) same++; else differ.push(`| ${key(c)} | ${v} | ${a} | ${b} |`);
  }
  const exits = vg.parts.filter((p) => p.exited !== undefined).map((p) => `${p.name} exited ${p.exited}`).join(', ');
  const summary = vg.lines.filter((l) => /valgrind \S+: .*(ERROR SUMMARY|definitely lost)/.test(l)).map((l) => l.replace(/==\d+==/, '').trim());
  console.log(`\n### The Valgrind pass, lane O, against ${against}'s two native runs\n\n${vcases.length} transfers (items 1, 2 and 6); ${same} give the same code, status and statuses of each request as both native runs. ${exits}.\n\n${summary.map((s) => `- \`${s}\``).join('\n')}\n\n${differ.length ? `| case | Valgrind | native run 1 | native run 2 |\n|---|---|---|---|\n${differ.join('\n')}\n` : 'No transfer differs.\n'}`);
  process.exit(0);
}

process.stdout.write(tables.join(''));
