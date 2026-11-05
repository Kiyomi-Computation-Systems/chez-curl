// M7 slice 4's tables (2026-11-03), built from the kept logs alone, Node's
// standard library only:
//   node .plans/research/m7/slice4/tables.mjs [--dir=DIR] [--lanes=L,...] [TABLE,...]
//   node .plans/research/m7/slice4/tables.mjs --splits
//   node .plans/research/m7/slice4/tables.mjs --valgrind
// It reads results/guix-8.20.0-1.log and results/docker-1.log as run 1, and
// their -2 twins as run 2, and the Mac's results/mac-8.7.1-*-N.log when
// they are there, and prints, in Markdown, every table, or those named
// (lanes, 1, 2, 3, 4, 4x, 5, 5x, 6, 7, 8, 9, 10, 11, 12): a row per case, a
// column per lane (F 7.85.0, O 8.5.0 OpenSSL, G 8.5.0 GnuTLS, X 8.20.0, C
// 8.23.0; M and S the Mac's 8.7.1, LibreSSL and SecureTransport). Each row
// cites run 1's line for its case, FILE:LINE, on the lane named. A cell the
// two runs disagree on reads "**run 1 / run 2**". Cells leave out ports,
// tags, connection numbers, timings and expiry times read from the clock.
// --splits lists every case line whose two runs differ, so normalised;
// --valgrind summarises the Valgrind pass. It fails, exit 1, on a log it
// cannot read, and on a lane-run with no case.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const opt = (name) => { const a = argv.find((x) => x.startsWith(`--${name}=`)); return a ? a.slice(name.length + 3) : null; };
const dir = opt('dir') || join(here, 'results');
const ALL = [['floor-7.85.0', 'F'], ['ubuntu-openssl-8.5.0', 'O'], ['ubuntu-gnutls-8.5.0', 'G'], ['guix-8.20.0', 'X'], ['current-8.23.0', 'C'],
  ['mac-8.7.1-default', 'M'], ['mac-8.7.1-secure-transport', 'S']];
const die = (why) => { process.stderr.write(`tables.mjs: ${why}\n`); process.exit(1); };
const named = argv.filter((a) => !a.startsWith('--'));
const only = named.length ? new Set(named[0].split(',')) : (argv.includes('--splits') || argv.includes('--valgrind') || opt('cite') ? new Set() : null);

// ------------------------------------------------------------------ reading
// runs: run -> lane -> { lines: [[text, file, lineNo]], cases: Map(item/name -> Case) }
const runs = new Map();
function addFile(file, run) {
  const path = join(dir, file);
  if (!existsSync(path)) return false;
  const text = readFileSync(path, 'latin1');
  let n = 0;
  for (const raw of text.split('\n')) {
    n += 1;
    const m = /^\[([^\]]+)\] (.*)$/.exec(raw);
    if (!m) continue;
    const lane = m[1];
    if (!runs.has(run)) runs.set(run, new Map());
    const byLane = runs.get(run);
    if (!byLane.has(lane)) byLane.set(lane, { lines: [], cases: new Map(), current: null });
    const L = byLane.get(lane);
    L.lines.push([m[2], file, n]);
    const t = m[2];
    let c;
    if ((c = /^case (\S+) (\S+)$/.exec(t))) {
      const key = `${c[1]}/${c[2]}`;
      const cs = { item: c[1], name: c[2], file, line: n, lines: [] };
      L.cases.set(key, cs);
      L.current = cs;
    } else if ((c = /^end (\S+) (\S+)$/.exec(t))) {
      L.current = null;
    } else if (L.current && /^[tsrxn] /.test(t)) {
      L.current.lines.push([t, file, n]);
    }
  }
  return true;
}
for (const r of [1, 2]) {
  if (!addFile(`guix-8.20.0-${r}.log`, r)) die(`no log guix-8.20.0-${r}.log in ${dir}`);
  if (!addFile(`docker-${r}.log`, r)) die(`no log docker-${r}.log in ${dir}`);
  for (const pass of ['default', 'secure-transport']) addFile(`mac-8.7.1-${pass}-${r}.log`, r);
}
const LANES = ALL.filter(([n]) => runs.get(1).has(n) && (!opt('lanes') || opt('lanes').split(',').includes(n)));
for (const [lane] of LANES) for (const r of [1, 2]) {
  const L = runs.get(r) && runs.get(r).get(lane);
  if (!L || L.cases.size === 0) die(`lane ${lane} has no case in run ${r}`);
}
const short = (lane) => (ALL.find(([n]) => n === lane) || [lane, lane])[1];
const cite = (cs) => (cs ? `${cs.file}:${cs.line}` : '-');

function caseOf(r, lane, item, name) {
  const L = runs.get(r) && runs.get(r).get(lane);
  return L ? L.cases.get(`${item}/${name}`) : undefined;
}
function caseNames(item) {
  const seen = [];
  for (const [lane] of LANES) {
    const L = runs.get(1).get(lane);
    for (const cs of L.cases.values()) if (cs.item === item && !seen.includes(cs.name)) seen.push(cs.name);
  }
  return seen;
}
// strip "ITEM NAME " after the kind letter
const body = (cs, kind) => cs.lines.filter(([t]) => t.startsWith(`${kind} `)).map(([t, f, n]) => [t.slice(kind.length + 1 + cs.item.length + 1 + cs.name.length + 1), f, n]);
const facts = (cs) => body(cs, 'x').map(([t]) => t);
const readouts = (cs) => {
  // each read-out: { header, lines: [render], rules: [verdict] }
  const out = [];
  for (const [t] of body(cs, 'r')) {
    if (t.startsWith('readout ')) out.push({ header: t.slice(8), lines: [], rules: [] });
    else if (t.startsWith('line ') && out.length) {
      const m = /^line "(.*)" rule=(\S+)$/.exec(t);
      out[out.length - 1].lines.push(m ? m[1] : t);
      out[out.length - 1].rules.push(m ? m[2] : '?');
    }
  }
  return out;
};
const transfers = (cs) => {
  // each t line with the s lines after it
  const out = [];
  for (const [t] of cs.lines.map(([x, f, n]) => [x.slice(0, 2) === 't ' || x.slice(0, 2) === 's ' ? x : null, f, n]).filter(([x]) => x)) {
    const rest = t.slice(2 + cs.item.length + 1 + cs.name.length + 1);
    if (t.startsWith('t ')) out.push({ head: rest, report: [] });
    else if (out.length) out[out.length - 1].report.push(rest);
  }
  return out;
};

// ------------------------------------------------------------------ normalising
function norm(s) {
  return String(s)
    .replace(/(localhost|127\.0\.0\.1|\]):\d{2,5}/g, '$1:#')
    .replace(/tag=[a-z0-9-]+-\d+/g, 'tag=T')
    .replace(/req #\d+/g, 'req #N')
    .replace(/conn=\d+/g, 'conn=C').replace(/conn=h2c\d+/g, 'conn=H')
    .replace(/(connect-us|total-us|caller-ms|caller-ns|engine-ns|setopt-ns|getinfo-ns|walk-ns|free-ns|offset-us|submit-minus-close-us)=[-0-9.]+/g, '$1=~')
    .replace(/(\\x09|\b)1[789]\d{8}(?=\\x09|\b)/g, '$1EPOCH')
    .replace(/\b(nonce|cnonce)="[^"]*"/g, '$1=~')
    .replace(/\/tmp\/m7s4\.[A-Za-z0-9]+/g, '/tmp/m7s4.X')
    .replace(/port \d+/g, 'port #').replace(/::1:\d+/g, '::1:#').replace(/stand-in v6=\d+/g, 'stand-in v6=#')
    .replace(/after \d+ milliseconds/g, 'after # milliseconds');
}
// cell: the value per run, bolded when the runs differ
function cell(fn, lane, item, name) {
  const a = caseOf(1, lane, item, name);
  const b = caseOf(2, lane, item, name);
  const va = a ? norm(fn(a)) : 'no case';
  const vb = b ? norm(fn(b)) : 'no case';
  return va === vb ? va : `**${va} / ${vb}**`;
}
const md = (s) => String(s).replace(/\|/g, '\\|');
// table: a Markdown table; in a row whose lane cells all agree, the first
// holds the value and the rest "same".
function table(title, header, rows) {
  const lanes = LANES.map(([n]) => short(n));
  const first = header.findIndex((h) => lanes.includes(h));
  if (first >= 0) {
    rows = rows.map((r) => {
      const cells = r.slice(first, first + lanes.length);
      return cells.length > 1 && cells.every((c) => c === cells[0]) ? [...r.slice(0, first), cells[0], ...cells.slice(1).map(() => 'same'), ...r.slice(first + lanes.length)] : r;
    });
  }
  console.log(`\n### ${title}\n`);
  console.log(`| ${header.map(md).join(' | ')} |`);
  console.log(`|${header.map(() => '---').join('|')}|`);
  for (const r of rows) console.log(`| ${r.map(md).join(' | ')} |`);
}
const laneHeader = (first) => [...first, ...LANES.map(([n]) => short(n))];
const citeLane = (item, name) => {
  for (const [lane] of LANES) { const cs = caseOf(1, lane, item, name); if (cs) return `${short(lane)} ${cite(cs)}`; }
  return '-';
};
const want = (t) => !only || only.has(t);

// helpers over a case
const cookieLines = (tr) => tr.report.filter((l) => l.startsWith('cookie "')).map((l) => l.slice(7));
const sentOf = (cs, step) => {
  const tr = transfers(cs).find((x) => x.head.startsWith(`step=${step} `));
  if (!tr) return 'no transfer';
  const o = /=> (\S+)/.exec(tr.head);
  if (!o || o[1] !== 'ok') {
    const failed = tr.head.replace(/^step=\S+ => /, '').replace(/ errbuf=.*$/, '');
    const head = tr.report.find((l) => l.startsWith('unterminated head '));
    return head ? `${failed}; the stand-in saw ${head}, sent ${cookieLines(tr).join(' + ') || 'none'}` : failed;
  }
  const c = cookieLines(tr);
  return c.length ? c.join(' + ') : 'none';
};
const outcomeOf = (cs, step) => {
  const tr = transfers(cs).find((x) => x.head.startsWith(`step=${step} `));
  if (!tr) return 'no transfer';
  const m = /=> (ok status=\d+ version=\S+|fail reason=\S+ code=\S+|refused field=\S+ reason=\S+|hung|\S+)/.exec(tr.head);
  return m ? m[1] : tr.head;
};
const lastReadout = (cs) => { const r = readouts(cs); return r.length ? r[r.length - 1] : null; };
const readoutText = (ro) => (!ro ? 'none' : ro.header.startsWith('code=') ? (ro.lines.length ? ro.lines.join(' ; ') : 'empty') : ro.header);
const factMatch = (cs, re) => { for (const f of facts(cs)) { const m = re.exec(f); if (m) return m; } return null; };
const countsOf = (cs) => { const n = body(cs, 'n').map(([t]) => t); return n.length ? n[0].replace(/^counts /, '') : 'none'; };

// ------------------------------------------------------------------ tables
if (want('lanes')) {
  const rows = [];
  for (const [lane] of LANES) {
    for (const r of [1, 2]) {
      const L = runs.get(r).get(lane);
      const lines = L.lines.map(([t]) => t);
      const lib = lines.find((t) => t.startsWith('libcurl version=')) || '';
      const sel = lines.find((t) => t.startsWith('standin selftest ')) || '';
      const exits = lines.filter((t) => / exited \d+ after/.test(t)).map((t) => /part (\S+) exited (\d+)/.exec(t)).map((m) => `${m[1]}=${m[2]}`);
      const bad = exits.filter((e) => !e.endsWith('=0'));
      const proto = (lines.find((t) => t.startsWith('prototype ')) || '').split(' ')[2] || '';
      const src = (lines.find((t) => t.startsWith('src ')) || '').split(' ')[1] || '';
      const cases = L.cases.size;
      const nonzero = [...L.cases.values()].filter((cs) => !cs.name.startsWith('g-') && /=[1-9]/.test(countsOf(cs))).map((cs) => `${cs.item}/${cs.name}`);
      rows.push([short(lane), r, lib.replace(/ path=.*$/, '').replace('libcurl ', ''), sel.replace('standin ', ''), `${exits.length} parts, ${bad.length ? `not 0: ${bad.join(',')}` : 'all 0'}`,
        cases, nonzero.length ? nonzero.join(', ') : 'none', `src ${src.slice(0, 12)} proto ${proto.slice(0, 12)}`, `${L.lines[0][1]}:${L.lines[0][2]}`]);
    }
  }
  table('Lanes', ['lane', 'run', 'libcurl', 'stand-in self-test', 'parts', 'cases', 'cases with a count not 0 (but g)', 'hashes', 'first line'], rows);
}

if (want('1')) {
  const rows = [];
  const add = (label, item, name, fn) => rows.push([label, citeLane(item, name), ...LANES.map(([l]) => cell(fn, l, item, name))]);
  add('1a outcomes, most holders', '1', 'a-200-transfers-20-live', (cs) => { const m = factMatch(cs, /most-holders=(\d+) outcomes=(.*)$/); return m ? `${m[2]} most=${m[1]}` : '?'; });
  add('1a read-out lines', '1', 'a-200-transfers-20-live', (cs) => { const ro = lastReadout(cs); return ro ? ro.header : '?'; });
  add('1a common in the read-out', '1', 'a-200-transfers-20-live', (cs) => { const ro = lastReadout(cs); const l = ro && ro.lines.find((x) => x.includes('\\x09common\\x09')); return l ? `common=${l.split('\\x09').pop()}` : 'none'; });
  add('1a jar log', '1', 'a-200-transfers-20-live', (cs) => { const m = factMatch(cs, /^jar j (.*)$/); return m ? m[1] : '?'; });
  add('1b sent', '1', 'b-load-submit-read-in-one-batch', (cs) => sentOf(cs, 1));
  add('1b read-out queued after the submit', '1', 'b-load-submit-read-in-one-batch', (cs) => facts(cs).filter((f) => f.startsWith('read-out-after-submit line ')).map((f) => f.slice(27)).join(' ; ') || 'empty');
  add('1b read-out once done', '1', 'b-load-submit-read-in-one-batch', (cs) => readoutText(lastReadout(cs)));
  add('1c probes and close', '1', 'c-close-while-held', (cs) => facts(cs).filter((f) => /^(probe|close =>|after t)/.test(f)).map((f) => f.replace(/ state=\S+$/, '')).join(' ; '));
  add('1c peeks while closing', '1', 'c-close-while-held', (cs) => readouts(cs).map(readoutText).join(' || '));
  add('1c a submit after', '1', 'c-close-while-held', (cs) => outcomeOf(cs, 3));
  add('1c jar log', '1', 'c-close-while-held', (cs) => { const m = factMatch(cs, /^jar j (.*)$/); return m ? m[1] : '?'; });
  add('1d outcomes of 500', '1', 'd-close-crossing-submit', (cs) => { const m = factMatch(cs, /outcomes=(.*) anomalies=(\d+)$/); return m ? `${m[1]} anomalies=${m[2]}` : '?'; });
  add('1d controls', '1', 'd-control', (cs) => facts(cs).filter((f) => f.startsWith('control ')).map((f) => f.replace(/ ok status=200 version=\S+ url=\S+ connect-us=\S+ total-us=\S+/, '')).join(' ; '));
  add('1e', '1', 'e-stop-with-live-and-closing', (cs) => [outcomeOf(cs, 1), ...facts(cs).filter((f) => /^(jar|after stop)/.test(f))].join(' ; '));
  add('1f connections, cookies', '1', 'f-freed-share-then-pooled-connections', (cs) => transfers(cs).map((tr) => `${(/step=(\d+)/.exec(tr.head) || [])[1]}:${((tr.report.find((l) => l.startsWith('req ')) || '').match(/conn=\S+/) || ['?'])[0]}:${cookieLines(tr).join('+') || 'none'}`).join(' '));
  for (const name of ['g-abandoned-left', 'g-abandoned-then-freed']) {
    add(`1${name}`, '1', name, (cs) => facts(cs).filter((f) => f.includes('=>') || f.startsWith('counts')).join(' ; '));
    add(`1${name} counts at the end`, '1', name, countsOf);
  }
  table('Item 1: the lifetime', laneHeader(['case', 'cite']), rows);
}

if (want('2')) {
  const rows = [];
  for (const v of ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '99', '-1']) {
    const f = (re) => (cs) => { const m = factMatch(cs, re); return m ? m[1] : '?'; };
    rows.push([`SHARE ${v} on a fresh share`, citeLane('2', 'answers'), ...LANES.map(([l]) => cell(f(new RegExp(`^fresh SHARE ${v} => (\\S+)$`)), l, '2', 'answers'))]);
    rows.push([`UNSHARE ${v} on a fresh share`, citeLane('2', 'answers'), ...LANES.map(([l]) => cell(f(new RegExp(`^fresh UNSHARE ${v} => (\\S+)$`)), l, '2', 'answers'))]);
    rows.push([`UNSHARE ${v} after SHARE 2`, citeLane('2', 'answers'), ...LANES.map(([l]) => cell(f(new RegExp(`^after SHARE 2 \\(=> \\S+\\), UNSHARE ${v} => (\\S+)$`)), l, '2', 'answers'))]);
  }
  for (const [label, re] of [['option 0 (NONE), value 2', /^option 0 \(NONE\) value 2 => (\S+)$/], ['option 6 (LAST), value 2', /^option 6 \(LAST\) value 2 => (\S+)$/],
    ['option 99, value 2', /^option 99 value 2 => (\S+)$/], ['a share a handle holds: SHARE 3, UNSHARE 2', /^in use: SHARE 3 => (\S+), UNSHARE 2 => \S+$/],
    ['a share a handle holds: UNSHARE 2', /^in use: SHARE 3 => \S+, UNSHARE 2 => (\S+)$/], ['a share a handle holds: cleanup', /^in use: cleanup => (\S+)$/],
    ['cleanup once the handle is cleaned up', /^after the handle's cleanup: cleanup => (\S+)$/]]) {
    rows.push([label, citeLane('2', 'answers'), ...LANES.map(([l]) => cell((cs) => { const m = factMatch(cs, re); return m ? m[1] : '?'; }, l, '2', 'answers'))]);
  }
  table('Item 2: curl_share_setopt\'s answers (CURLSHcode: 0 OK, 1 BAD_OPTION, 2 IN_USE, 5 NOT_BUILT_IN)', laneHeader(['call', 'cite']), rows);
  const carry = [];
  for (const name of caseNames('2').filter((n) => n.startsWith('carry-'))) {
    carry.push([name, citeLane('2', name), ...LANES.map(([l]) => cell((cs) => {
      const m = factMatch(cs, /^make ops=(.*) => (.*)$/);
      return `${m ? m[2].replace(/^ok /, '') : '?'}; second sent ${sentOf(cs, 2)}`;
    }, l, '2', name))]);
  }
  table('Item 2: what a share set so carries between two transfers (make\'s codes; what the second sent)', laneHeader(['share', 'cite']), carry);
}

if (want('3')) {
  const rows = [];
  for (const name of ['detector', 'share-first', 'file-first']) {
    rows.push([`${name}: empty-path or detector opens`, citeLane('3', name), ...LANES.map(([l]) => cell((cs) => { const m = factMatch(cs, /(?:empty-path opens during the case|detector opens): (\d+)/); return m ? m[1] : '?'; }, l, '3', name))]);
    if (name === 'detector') continue;
    for (const step of [1, 2, 3]) rows.push([`${name}: transfer ${step} sent`, citeLane('3', name), ...LANES.map(([l]) => cell((cs) => sentOf(cs, step), l, '3', name))]);
    rows.push([`${name}: read-out at the end`, citeLane('3', name), ...LANES.map(([l]) => cell((cs) => readoutText(lastReadout(cs)), l, '3', name))]);
  }
  table('Item 3: SHARE then COOKIEFILE "", against COOKIEFILE "" then SHARE', laneHeader(['row', 'cite']), rows);
}

// item 4: what the rule lets through
function loadRow(cs) {
  const line = factMatch(cs, /^line "(.*)" rule=(\S+)$/);
  const load = factMatch(cs, /^load => (.*)$/);
  const ro = readouts(cs)[0];
  const rt = factMatch(cs, /^round-trip (same|DIFFERS)/);
  return { line: line ? line[1] : '?', rule: line ? line[2] : '?', load: load ? load[1] : '?', readout: readoutText(ro), sent: sentOf(cs, 1), roundtrip: rt ? rt[1] : (ro && ro.lines.length ? 'not run' : '-') };
}
if (want('4') || want('4x')) {
  const names = caseNames('4').filter((n) => n !== 'nul');
  if (want('4')) {
    const rows = [];
    for (const name of names) {
      const first = (() => { for (const [l] of LANES) { const cs = caseOf(1, l, '4', name); if (cs) return loadRow(cs); } return null; })();
      rows.push([name, first ? `"${first.line}"` : '?', first ? first.rule : '?', citeLane('4', name),
        ...LANES.map(([l]) => cell((cs) => { const r = loadRow(cs); return `load ${r.load}; read out ${r.readout}; sent ${r.sent}; round trip ${r.roundtrip}`; }, l, '4', name))]);
    }
    table('Item 4: each line loaded alone into a fresh jar (rule: as written / with #HttpOnly_ stripped)', laneHeader(['case', 'line', 'rule', 'cite']), rows);
    const nul = [];
    for (const [l] of LANES) { const cs = caseOf(1, l, '4', 'nul'); if (cs) for (const f of facts(cs)) nul.push([short(l), cite(cs), f]); }
    table('Item 4: a line holding NUL', ['lane', 'cite', 'answer'], nul);
  }
  if (want('4x')) {
    // the rule's gaps: a line accepted on either reading that some lane drops,
    // keeps changed, or keeps unlike another lane; and every round trip that
    // failed.
    const rows = [];
    for (const name of names) {
      const per = LANES.map(([l]) => { const cs = caseOf(1, l, '4', name); return cs ? loadRow(cs) : null; });
      const first = per.find((x) => x);
      if (!first) continue;
      const accepted = first.rule.split('/').includes('accept');
      const outs = per.map((x) => (x ? norm(x.readout) : 'no case'));
      const dropped = outs.some((o) => o === 'empty');
      const changed = outs.some((o) => o !== 'empty' && o !== norm(first.line));
      const split = new Set(outs).size > 1;
      const rtFail = per.some((x) => x && x.roundtrip === 'DIFFERS');
      const failed = per.some((x) => x && x.sent.startsWith('fail'));
      if ((accepted && (dropped || changed || split || failed)) || rtFail) {
        rows.push([name, `"${first.line}"`, first.rule,
          [accepted && dropped ? 'dropped' : '', accepted && changed ? 'changed' : '', accepted && split ? 'lanes differ' : '',
            accepted && failed ? 'the transfer failed' : '', rtFail ? 'round trip differs' : ''].filter(Boolean).join(', '),
          ...LANES.map(([l], i) => (per[i] ? `${norm(per[i].readout)}${per[i].sent.startsWith('fail') ? ` [${norm(per[i].sent)}]` : ''}` : 'no case'))]);
      }
    }
    table('Item 4: lines the rule accepts that libcurl drops, changes, or keeps unlike on every lane, and the round trip\'s failures (run 1)', laneHeader(['case', 'line', 'rule', 'why']), rows);
  }
}

if (want('5') || want('5x')) {
  const names = caseNames('5');
  if (want('5')) {
    const rows = [];
    for (const name of names) {
      const sc = (() => { for (const [l] of LANES) { const cs = caseOf(1, l, '5', name); if (cs) return facts(cs).filter((f) => f.startsWith('set-cookie ')).map((f) => f.slice(11)).join(' + '); } return '?'; })();
      rows.push([name, sc, citeLane('5', name), ...LANES.map(([l]) => cell((cs) => {
        const ro = lastReadout(cs);
        const o = outcomeOf(cs, 1);
        const lines = ro && ro.lines.length ? ro.lines.map((x, i) => `${x} [${ro.rules[i]}]`).join(' ; ') : (ro ? readoutText(ro) : 'none');
        return o.startsWith('ok') ? lines : `${o}; ${lines}`;
      }, l, '5', name))]);
    }
    table('Item 5: Set-Cookie lines, then the read-out, each line with the rule\'s verdict', laneHeader(['case', 'Set-Cookie', 'cite']), rows);
  }
  if (want('5x')) {
    const rows = [];
    for (const [l] of LANES) for (const name of names) for (const r of [1, 2]) {
      const cs = caseOf(r, l, '5', name);
      if (!cs) continue;
      for (const ro of readouts(cs)) ro.lines.forEach((x, i) => { if (ro.rules[i] !== 'accept/accept') rows.push([short(l), r, name, `"${x}"`, ro.rules[i], cite(cs)]); });
    }
    table('Item 5: every read-out line the rule refuses, by lane and run', ['lane', 'run', 'case', 'line', 'rule', 'case cite'], rows);
  }
}

if (want('6')) {
  const rows = [];
  const ms = (ns) => (ns === undefined ? '?' : (Number(ns) / 1e6).toFixed(1));
  for (const name of caseNames('6')) {
    rows.push([name, citeLane('6', name), ...LANES.map(([l]) => {
      const vals = [1, 2].map((r) => {
        const cs = caseOf(r, l, '6', name);
        if (!cs) return 'no case';
        const ld = factMatch(cs, /^load n=(\d+) codes-nonzero=(\d+) engine-ns=(\d+) setopt-ns=(\d+)/);
        const ro = factMatch(cs, /^read-out 1 n=(\d+) getinfo-ns=(\d+) walk-ns=(\d+) free-ns=(\d+)/);
        const ro2 = factMatch(cs, /^read-out 2 n=(\d+) getinfo-ns=(\d+) walk-ns=(\d+) free-ns=(\d+)/);
        return ld && ro ? `load ${ms(ld[3])} (setopt ${ms(ld[4])}); read ${ms(Number(ro[2]) + Number(ro[3]) + Number(ro[4]))} (walk ${ms(ro[3])}), again ${ro2 ? ms(Number(ro2[2]) + Number(ro2[3]) + Number(ro2[4])) : '?'}; n=${ro[1]}` : '?';
      });
      return `${vals[0]} / ${vals[1]}`;
    })]);
  }
  table('Item 6: the time on the engine\'s thread, ms, run 1 / run 2 (a read is getinfo + walk + free)', laneHeader(['case', 'cite']), rows);
}

if (want('7')) {
  const rows = [];
  for (const name of caseNames('7')) {
    rows.push([name, citeLane('7', name), ...LANES.map(([l]) => cell((cs) => {
      const tr = transfers(cs)[0];
      if (!tr) return 'no transfer';
      const o = outcomeOf(cs, 1);
      const host = tr.report.filter((x) => /^(host|authority) /.test(x)).join(' ');
      const ro = lastReadout(cs);
      const set = ro ? ro.lines.find((x) => /\\x09set[A-Za-z-]+\\x09/.test(x)) : null;
      return `${o.startsWith('ok') ? '' : `${o}; `}${host}; sent ${cookieLines(tr).join(' + ') || 'none'}${set ? `; stored ${set.split('\\x09')[0]}` : ''}`;
    }, l, '7', name))]);
  }
  table('Item 7: a caller\'s Host and Cookie beside the jar (what the server received; where the answer\'s cookie was stored)', laneHeader(['case', 'cite']), rows);
}

if (want('8')) {
  const rows = [];
  for (const name of caseNames('8')) {
    rows.push([name, citeLane('8', name), ...LANES.map(([l]) => cell((cs) => transfers(cs).map((tr) => {
      const req = tr.report.find((x) => x.startsWith('req ')) || '';
      const face = (/face=(\S+)/.exec(req) || [])[1];
      const conn = (/conn=(\S+)/.exec(req) || [])[1];
      const stream = (/stream=(\S+)/.exec(req) || [])[1];
      const fields = tr.report.find((x) => /^cookie-(fields|headers) /.test(x)) || '';
      return `${(/step=(\d+)/.exec(tr.head) || [])[1]}:${face}:${conn}:s${stream}:${fields}:${cookieLines(tr).join('+') || 'none'}`;
    }).join(' ') + (factMatch(cs, /^t1 done when t2 was: (\S+)/) ? ` t1-done-at-t2=${factMatch(cs, /^t1 done when t2 was: (\S+)/)[1]}` : ''), l, '8', name))]);
  }
  table('Item 8: the Cookie header over HTTP/2 (step:face:connection:stream:fields:values)', laneHeader(['case', 'cite']), rows);
}

if (want('9')) {
  const rows = [];
  for (const name of caseNames('9')) {
    rows.push([name, citeLane('9', name), ...LANES.map(([l]) => cell((cs) => {
      const tr = transfers(cs)[0];
      if (!tr) return 'no transfer';
      const blocks = [];
      for (const x of tr.report) {
        if (x.startsWith('req ')) blocks.push({ answer: '?', cookies: [], expect: false, auth: '' });
        else if (blocks.length && x.startsWith('cookie "')) blocks[blocks.length - 1].cookies.push(x.slice(7));
        else if (blocks.length && x.startsWith('answer ')) blocks[blocks.length - 1].answer = x.slice(7);
        else if (blocks.length && x.startsWith('expect ')) blocks[blocks.length - 1].expect = true;
        else if (blocks.length && x.startsWith('auth ')) blocks[blocks.length - 1].auth = x.slice(5);
      }
      return `${outcomeOf(cs, 1)}; ${blocks.map((bk, i) => `#${i + 1} ${bk.answer}${bk.expect ? ' expect' : ''}${bk.auth ? ` auth ${bk.auth}` : ''} sent ${bk.cookies.join('+') || 'none'}`).join('; ')}; read out ${readoutText(lastReadout(cs))}`;
    }, l, '9', name))]);
  }
  table('Item 9: the requests libcurl makes inside one transfer', laneHeader(['case', 'cite']), rows);
}

if (want('10')) {
  const main = [];
  for (const [l] of LANES) {
    const L = runs.get(1).get(l);
    const hs = L.lines.filter(([t]) => /^h \S+ => /.test(t));
    if (hs.length) main.push([short(l), `${hs[0][1]}:${hs[0][2]}`, hs.map(([t]) => t.slice(2)).join(' ; ')]);
  }
  table('Item 10: the hatch on main (main.sps)', ['lane', 'cite', 'answers'], main);
  const rows = [];
  for (const name of caseNames('10')) {
    rows.push([name, citeLane('10', name), ...LANES.map(([l]) => cell((cs) => {
      const req = factMatch(cs, /^twin's request => (.*)$/);
      const ros = readouts(cs).map(readoutText);
      return `request ${req ? req[1] : '?'}; twin sent ${sentOf(cs, 1)}; jar after it: ${ros[1] || '?'}; the other (sent before) ${sentOf(cs, 2)}; jar after it: ${ros[2] || '?'}; next sent ${sentOf(cs, 3)}`;
    }, l, '10', name))]);
  }
  table('Item 10: each twin, set by the hatch on one transfer that holds the jar, beside another live one', laneHeader(['twin', 'cite']), rows);
}

if (want('11')) {
  const rows = [];
  for (const name of caseNames('11')) {
    rows.push([name, citeLane('11', name), ...LANES.map(([l]) => cell((cs) => {
      const make = factMatch(cs, /^make ops=(.*) => (.*)$/);
      const trs = transfers(cs);
      const scheme = (tr) => { const req = tr && tr.report.find((x) => x.startsWith('req ')); return req ? (/scheme=(\S+)/.exec(req) || [])[1] : outcomeOf(cs, 2); };
      return `make ${make ? make[2] : '?'}; first ${scheme(trs[0])}; second, an http:// URL, arrived as ${scheme(trs[1])}`;
    }, l, '11', name))]);
  }
  table('Item 11: Strict-Transport-Security on an https:// transfer, then an http:// transfer to that host', laneHeader(['case', 'cite']), rows);
}

if (want('12')) {
  const facts12 = [];
  for (const [l] of LANES) {
    const L = runs.get(1).get(l);
    const ip = L.lines.find(([t]) => t.startsWith('ipv6 lo '));
    const ports = L.lines.find(([t]) => t.startsWith('standin ports '));
    const origin = L.lines.find(([t]) => t.startsWith('origin.mjs announces: '));
    facts12.push([short(l), ip ? `${ip[0]} (${ip[1]}:${ip[2]})` : '?', ports ? `${ports[0].replace(/=\d+/g, '=#')} (${ports[1]}:${ports[2]})` : '?', origin ? `${origin[0].replace(/:\d+"/g, ':#"').replace(/"pid":\d+/, '"pid":#')} (${origin[1]}:${origin[2]})` : '?']);
  }
  const net = join(dir, 'netcheck-docker-default.log');
  if (existsSync(net)) readFileSync(net, 'latin1').split('\n').forEach((t, i) => { if (t.startsWith('network default:')) facts12.push(['Docker default network', `netcheck-docker-default.log:${i + 1}`, t, '']); });
  table('Item 12: the loopback, the stand-in\'s faces, and tests/origin.mjs', ['lane', 'IPv6', 'stand-in', 'origin.mjs'], facts12);
  const rows = [];
  for (const name of caseNames('12').filter((n) => n !== 'facts')) {
    rows.push([name, citeLane('12', name), ...LANES.map(([l]) => {
      const vals = [1, 2].map((r) => {
        const cs = caseOf(r, l, '12', name);
        if (!cs) return 'no case';
        const no = factMatch(cs, /^no v6 face: (.*)$/);
        if (no) return `no v6 face ${no[1]}`;
        return transfers(cs).map((tr) => {
          const o = /=> (ok status=\d+|fail reason=\S+ code=\S+|\S+)/.exec(tr.head);
          const c = /connect-us=(\S+) total-us=(\S+)/.exec(tr.head);
          const addr = ((tr.report.find((x) => x.startsWith('req ')) || '').match(/addr=\S+/) || ['-'])[0];
          return `${o ? o[1].replace('ok status=', '') : '?'} ${addr} ${c ? `${c[1]}/${c[2]}us` : ''}`;
        }).join(', ');
      });
      return norm(vals[0].replace(/\d+\/\d+us/g, '')) === norm(vals[1].replace(/\d+\/\d+us/g, '')) ? vals[0] : `**${vals[0]} / ${vals[1]}**`;
    })]);
  }
  table('Item 12: three transfers to each server and host (outcome, address reached, connect/total µs; run 1, bold when run 2 differs beyond times)', laneHeader(['face-host', 'cite']), rows);
}

// --cite=ITEM/NAME[,...]: every lane-run's line for each case named.
if (opt('cite')) {
  for (const key of opt('cite').split(',')) {
    const [item, name] = key.split('/');
    const cells = [];
    for (const [l] of LANES) for (const r of [1, 2]) { const cs = caseOf(r, l, item, name); cells.push(`${short(l)}${r} ${cs ? cite(cs) : 'none'}`); }
    console.log(`${key}: ${cells.join(', ')}`);
  }
}

if (argv.includes('--splits')) {
  console.log('\n### Splits: case lines whose two runs differ, normalised\n');
  let count = 0;
  for (const [l] of LANES) {
    const a = runs.get(1).get(l);
    const b = runs.get(2).get(l);
    for (const [key, ca] of a.cases) {
      const cb = b.cases.get(key);
      if (!cb) { console.log(`- ${short(l)} ${key}: no case in run 2`); count++; continue; }
      const la = ca.lines.map(([t]) => norm(t));
      const lb = cb.lines.map(([t]) => norm(t));
      const n = Math.max(la.length, lb.length);
      const diffs = [];
      for (let i = 0; i < n; i++) if (la[i] !== lb[i]) diffs.push(i);
      if (diffs.length) {
        count++;
        const i = diffs[0];
        console.log(`- ${short(l)} ${key}: ${diffs.length} of ${n} lines differ; first at ${ca.lines[i] ? `${ca.lines[i][1]}:${ca.lines[i][2]}` : '-'} / ${cb.lines[i] ? `${cb.lines[i][1]}:${cb.lines[i][2]}` : '-'}: "${(la[i] || '').slice(0, 160)}" / "${(lb[i] || '').slice(0, 160)}"`);
      }
    }
  }
  console.log(`\n${count} cases differ between runs`);
}

if (argv.includes('--valgrind')) {
  const path = join(dir, 'valgrind-ubuntu-openssl-8.5.0.log');
  if (!existsSync(path)) die(`no ${path}`);
  const lines = readFileSync(path, 'latin1').split('\n');
  console.log('\n### The Valgrind pass\n');
  lines.forEach((t, i) => {
    if (/ exited \d+ after|valgrind \S+: ==\d+== (ERROR SUMMARY|   definitely|   indirectly|     possibly|Command)|\] x 1 d-close-crossing-submit crossings|\] n 1 /.test(t)) console.log(`- valgrind-ubuntu-openssl-8.5.0.log:${i + 1} ${t.replace(/^\[[^\]]+\] /, '').replace(/ lane=.*$/, ' ...')}`);
  });
}
