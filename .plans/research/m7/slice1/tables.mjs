// M7 slice 1's tables (2026-11-02), built from the kept logs alone, Node's
// standard library only:
//   node .plans/research/m7/slice1/tables.mjs
// It reads results/guix-8.20.0.log and results/docker.log as run 1, and
// their -2 twins as run 2, and prints, in Markdown, one table per item: a
// row per case, a column per lane (F 7.85.0, O 8.5.0 OpenSSL, G 8.5.0
// GnuTLS, X 8.20.0, C 8.23.0). A cell the two runs disagree on reads
// "**run 1 / run 2**". Ports, timings and connection numbers are left out;
// what a cell keeps is said above each table. It fails, exit 1, on a lane
// or a line it cannot read, and on a case missing from a lane or a run.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const lanes = [['floor-7.85.0', 'F'], ['ubuntu-openssl-8.5.0', 'O'], ['ubuntu-gnutls-8.5.0', 'G'],
  ['guix-8.20.0', 'X'], ['current-8.23.0', 'C']];
// node tables.mjs [RUN1 RUN2 [TABLE,...]]: each RUN a comma list of log
// files, relative to results/, and the tables to print; by default the kept
// runs and every table.
const argv = process.argv.slice(2);
const runs = argv.length >= 2
  ? [argv[0].split(','), argv[1].split(',')]
  : [['guix-8.20.0.log', 'docker.log'], ['guix-8.20.0-2.log', 'docker-2.log']];
const only = argv.length >= 3 ? new Set(argv[2].split(',')) : null;

const die = (why) => { process.stderr.write(`tables.mjs: ${why}\n`); process.exit(1); };

// field: NAME=VALUE's value in LINE, VALUE a "quoted" string or a word.
function field(line, name) {
  const re = new RegExp(`(?:^| )${name}=("(?:[^"\\\\]|\\\\.)*"|[^ ]*)`);
  const m = re.exec(line);
  if (!m) return null;
  return m[1].startsWith('"') ? m[1].slice(1, -1) : m[1];
}

const ver = (v) => ({ 'http/1.1': '1.1', 'http/2': '2', 'http/1.0': '1.0', '#f': 'none' }[v] || v);

// outcome: what a described outcome keeps: status and version, or code
// and class; the body's face when it names one.
function outcome(text) {
  if (text.startsWith('ok ')) {
    const body = field(text, 'body') || '';
    let where = '';
    const f = /face=([a-z0-9]+)/.exec(body);
    if (f) where = `${f[1]} `;
    else if (body.startsWith(':method:')) where = 'h2-face ';
    else if (body.startsWith('GET /')) where = 'h1-face ';
    return `${where}${field(text, 'status')} ${ver(field(text, 'version'))}`;
  }
  if (text.startsWith('fail ')) return `${field(text, 'code')} ${field(text, 'class')}`;
  if (text.startsWith('refused ')) return `refused ${field(text, 'reason')}`;
  return text.split(' ')[0];
}

const tables = new Map();
function cell(table, key, laneName, run, value) {
  if (!tables.has(table)) tables.set(table, new Map());
  const rows = tables.get(table);
  if (!rows.has(key)) rows.set(key, new Map());
  const row = rows.get(key);
  const k = `${laneName}#${run}`;
  if (row.has(k)) die(`${table} ${key} ${laneName} run ${run + 1} twice`);
  row.set(k, value);
}

const after = (line, marker) => line.slice(line.indexOf(marker) + marker.length);

// shares: item 4's cases, by row, lane and run, each rep's connections and
// versions, in the reps' order; made into cells once every log is read.
const shares = new Map();

for (const [run, files] of runs.entries()) {
  for (const file of files) {
    const text = readFileSync(join(here, 'results', file), 'utf8');
    for (const raw of text.split('\n')) {
      const m = /^\[([^\]]+)\] (.*)$/.exec(raw);
      if (!m) continue;
      const [, laneName, line] = m;
      if (!lanes.some(([n]) => n === laneName)) die(`no lane ${laneName}`);
      const kind = line.split(' ')[0];
      if (kind === 'v1') {
        const rest = after(line, ` face=${field(line, 'face')} `);
        const body = field(rest, 'body') || '';
        const upgrade = body.includes('Upgrade: h2c') ? ', Upgrade: h2c sent' : '';
        const sent = rest.startsWith('fail ') ? (field(rest, 'sent') === '0' ? ', none sent' : ', sent') : '';
        cell('v1', `${field(line, 'version')} | ${field(line, 'face')}`, laneName, run, `${outcome(rest)}${upgrade}${sent}`);
      } else if ((kind === 'p2a' || kind === 'p2b') && field(line, 'case')) {
        const rest = after(line, ` connects=${field(line, 'connects')} `);
        const [before, afterN] = field(line, 'connects').split('->').map(Number);
        const body = field(rest, 'body') || '';
        const notes = [];
        if (body.startsWith('GET http://')) notes.push('absolute form');
        if (afterN > before) notes.push('CONNECT');
        cell(kind, `${field(line, 'case')} | ${field(line, 'face')} | ${field(line, 'version')}`, laneName, run,
          `${outcome(rest)}${notes.length ? `, ${notes.join(', ')}` : ''}`);
      } else if (kind === 'p2a' && line.startsWith('p2a hatch-proxy-on-this-src')) {
        cell('p2a', 'the hatch\'s PROXY, on main\'s src/ | - | -', laneName, run, outcome(after(line, 'hatch-proxy-on-this-src ')));
      } else if (kind === 'alpn') {
        const rest = after(line, ` alpn=${field(line, 'alpn')} `);
        const body = field(rest, 'body') || '';
        const a = /alpn=([^ ]+)/.exec(body);
        cell('alpn', `${field(line, 'face')} | ${field(line, 'version')} | ${field(line, 'alpn')}`, laneName, run,
          `${outcome(rest)}${a ? `, ALPN ${a[1]}` : ''}`);
      } else if (kind === 'altsvc-i' && field(line, 'step')) {
        const c = field(line, 'case');
        const step = field(line, 'step');
        if (step === 'A') {
          const rest = after(line, ' events=');
          const res = rest.slice(rest.search(/ (ok|fail) /) + 1);
          const state = (s) => (s === 'absent' ? 'absent' : s === 'no-entries' ? 'no entries' : 'entry');
          cell('altsvc-i', `${c} | A`, laneName, run, outcome(res));
          cell('altsvc-i', `${c} | file at A's head, end`, laneName, run,
            `${state(field(line, 'file-at-head'))}, ${state(field(line, 'file-at-end'))}`);
        } else {
          const rest = after(line, ' events=');
          const res = rest.slice(rest.search(/ (ok|fail) /) + 1);
          cell('altsvc-i', `${c} | ${step}`, laneName, run, outcome(res));
        }
      } else if (kind === 'altsvc-ii') {
        const rest = after(line, ' file-after=');
        const res = rest.slice(rest.search(/ (ok|fail) /) + 1);
        const fileAfter = rest.slice(0, rest.search(/ (ok|fail) /));
        const entry = field(line, 'entry').replace(/\\"/g, '"');
        const kept = fileAfter === entry ? '' : ', file rewritten';
        cell('altsvc-ii', `${field(line, 'case')} | ${field(line, 'version')}`, laneName, run, `${outcome(res)}${kept}`);
      } else if (kind === 'h09' || kind === 'alias') {
        const rest = after(line, ` face=${field(line, 'face')} `).replace(/^version=[^ ]+ /, '');
        cell('misc', `${kind} ${field(line, 'case')}${field(line, 'version') ? ` (${field(line, 'version')})` : ''}`, laneName, run, outcome(rest));
      } else if (kind === 'connect-to') {
        const rest = after(line, ` events=${field(line, 'events')}`);
        const res = rest.slice(rest.search(/ (ok|fail) /) + 1);
        cell('misc', `CONNECT_TO alt2 (${field(line, 'version')})`, laneName, run, outcome(res));
      } else if (kind === 'share') {
        const key = `${field(line, 'setup')} | ${field(line, 'case')}`;
        const same = field(line, 'same');
        const conns = same === '#t' ? '1' : same === '#f' ? '2' : '?';
        const versions = [...line.matchAll(/version=([^ ]+)/g)].map((x) => ver(x[1]));
        let note = '';
        if (field(line, 'case') === 'b-after-head' && field(line, 'first-done-at-second-end') !== '#f') note = '!first-ended';
        const rep = field(line, 'rep');
        const k = `${rep === 'verbose' ? `${key} | verbose rep` : `${key} | reps 1, 2, 3`}#${laneName}#${run}`;
        if (!shares.has(k)) shares.set(k, []);
        shares.get(k).push({ conns: `${conns}${note}`, versions });
      }
    }
  }
}

for (const [k, reps] of shares) {
  const [key, laneName, run] = k.split('#');
  const versions = [...new Set(reps.flatMap((r) => r.versions))].join('/');
  cell('share', key, laneName, Number(run), `${reps.map((r) => r.conns).join(', ')} (${versions})`);
}

function print(table, title, note, columns) {
  if (only && !only.has(table)) return;
  const rows = tables.get(table);
  if (!rows) die(`no table ${table}`);
  process.stdout.write(`\n### ${title}\n\n${note}\n\n| ${columns.join(' | ')} | ${lanes.map(([, s]) => s).join(' | ')} |\n|${columns.map(() => '---|').join('')}${lanes.map(() => '---|').join('')}\n`);
  for (const [key, row] of rows) {
    if (key.split(' | ').length !== columns.length) die(`${table} ${key}: not ${columns.length} key columns`);
    const cells = lanes.map(([n]) => {
      const a = row.get(`${n}#0`);
      const b = row.get(`${n}#1`);
      if (a === undefined || b === undefined) die(`${table} ${key}: ${n} lacks run ${a === undefined ? 1 : 2}`);
      return a === b ? a : `**${a} / ${b}**`;
    });
    process.stdout.write(`| ${key} | ${cells.join(' | ')} |\n`);
  }
}

print('v1', 'Item 1: each HTTP_VERSION over each face (`v1` lines)',
  'A cell: who answered (`h1-face`, `h2-face`: the origin\'s /echo over HTTP/1.1, over HTTP/2), status and version read; or the code and its class, and whether a request was sent (`CURLINFO_REQUEST_SIZE` above 0); `Upgrade: h2c sent` when the echo shows it.', ['version', 'face']);
print('p2a', 'Item 2 (a): the environment\'s proxy (`p2a` lines)',
  '`http_proxy` and `https_proxy` name the origin\'s http face. A cell: the outcome; `absolute form` when the http face\'s /echo shows `GET http://...`; `CONNECT` when its tunnel count rose. `h2-face` is the origin\'s HTTP/2 /echo, reached through the tunnel.', ['case', 'face', 'version']);
print('p2b', 'Item 2 (b): a named proxy, on the prototype (`p2b` lines)',
  'The hatch\'s `PROXY` at the http face and `NOPROXY ""`; no proxy variable set. Cells as in (a).', ['case', 'face', 'version']);
print('alpn', 'Item 3: `SSL_ENABLE_ALPN` (`alpn` lines)', 'A cell: the outcome; for the stand-in\'s `both` face, the ALPN it chose (`none`: no ALPN).', ['face', 'version', 'SSL_ENABLE_ALPN']);
print('altsvc-i', 'Item 3 (i) and (iii): `ALTSVC` and `ALTSVC_CTRL`, two transfers on one engine, then one on a fresh engine (`altsvc-i` lines)',
  'A cell: the face that answered, and the version. A is streamed from alt1\'s `/slow` (head, then the body 500 ms on); the file row reads the alt-svc file at A\'s head and at its end.', ['case', 'step']);
print('altsvc-ii', 'Item 3 (ii): a pre-written alt-svc file, one transfer on a fresh engine (`altsvc-ii` lines)',
  'A cell: the face that answered (`h2-face`, `h1-face`: the origin\'s h2 face, its https face) and the version, or the code; `file rewritten` when the file no longer holds the entry alone.', ['entry', 'version']);
print('misc', 'Item 3: `HTTP09_ALLOWED`, `HTTP200ALIASES`, `CONNECT_TO` (`h09`, `alias`, `connect-to` lines)', 'A cell: the face that answered, status and version, or the code.', ['case']);
print('share', 'Item 4: connection sharing (`share` lines)',
  'A cell: for each rep, the connections the two requests used, by the origin\'s `/connection` K, then the versions read. `!first-ended`: the first had ended before the second did (none should). Each rep and each case ran on a fresh engine.', ['setup', 'case', 'reps']);
