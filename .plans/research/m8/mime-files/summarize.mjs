// M8's mime-files probe: the README's tables, from the kept logs. Node 20 or
// later, the standard library only:
//   node .plans/research/m8/mime-files/summarize.mjs LOG...
// Reads every "[LANE] ..." line of each LOG (gzip'd when its name ends .gz) (run.sh's output, as docker.sh,
// nomime.sh, mac.sh and the Guix lane keep it), groups the lines by lane and
// case, and prints one Markdown table per question, a column per lane. A
// lane seen in several logs is several runs: a cell whose runs agree prints
// once; one whose runs differ prints each run's value, "run1 ‖ run2", and
// the cell is listed under the table. Nothing here is typed by hand: each
// cell is computed from the lines named in its table's notes.
// With --count first, a cell counts its runs' values instead: "VALUE ×N"
// for each value, most first, and only the rows some run holds are printed:
// the racing cells' extra runs (results/races-*.log).
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { basename } from 'node:path';

const LANES = [
  ['floor-7.85.0', 'F 7.85.0'], ['ubuntu-openssl-8.5.0', 'O 8.5.0'], ['ubuntu-gnutls-8.5.0', 'G 8.5.0'],
  ['guix-8.20.0', 'X 8.20.0'], ['current-8.23.0', 'C 8.23.0'], ['mac-8.7.1', 'Mac 8.7.1'],
  ['nomime-7.85.0', 'no-mime 7.85.0'], ['nomime-8.23.0', 'no-mime 8.23.0'],
];
const laneOf = (raw) => raw.replace(/-run\d+$/, '');
// field: KEY's value in S: a quoted one (its escapes kept, as \\" and \\\\), or a word.
const field = (s, key) => { const m = new RegExp(`(?:^| )${key}=("((?:[^"\\\\]|\\\\.)*)"|\\S+)`).exec(s); return m ? (m[2] !== undefined ? m[2] : m[1]) : null; };

// runs: lane -> [{ file, cases: Map(case -> rec) }]
const runs = new Map();
const rec0 = () => ({ exit: null, xfers: new Map(), fs: [], server: [], expects: new Map(), lines: [], vg: { exit: null, errors: null, definite: null, invalid: [], out: [], codes: [] } });
const COUNT = process.argv[2] === '--count';
for (const file of process.argv.slice(COUNT ? 3 : 2)) {
  const raw0 = readFileSync(file);
  const text = (file.endsWith('.gz') ? gunzipSync(raw0) : raw0).toString('latin1');
  const perLane = new Map();
  for (const line of text.split('\n')) {
    const m = /^\[([^\]]+)\] (.*)$/.exec(line);
    if (!m) continue;
    const raw = m[1];
    let body = m[2];
    if (!perLane.has(raw)) perLane.set(raw, { file: basename(file), raw, cases: new Map() });
    const run = perLane.get(raw);
    const get = (c) => { if (!run.cases.has(c)) run.cases.set(c, rec0()); return run.cases.get(c); };
    let mm;
    if ((mm = /^probe (\S+) exit=(\d+)$/.exec(body))) { get(mm[1]).exit = Number(mm[2]); continue; }
    if ((mm = /^vg (\S+) exit=(\d+)/.exec(body))) { get(mm[1]).vg.exit = Number(mm[2]); continue; }
    if ((mm = /^vg (\S+) valgrind: ==\d+== (.*)$/.exec(body))) {
      const r = get(mm[1]);
      const v = mm[2];
      let k;
      if ((k = /^ERROR SUMMARY: (\d+) errors/.exec(v))) r.vg.errors = Number(k[1]);
      if ((k = /definitely lost: ([\d,]+) bytes in ([\d,]+) blocks/.exec(v))) r.vg.definite = `${k[1]} B in ${k[2]} blocks`;
      if (/All heap blocks were freed/.test(v)) r.vg.definite = '0 (all heap blocks freed)';
      if (/^(Invalid|Conditional|Syscall param|Use of uninit|Mismatched|Source and destination)/.test(v)) r.vg.invalid.push(v);
      continue;
    }
    if ((mm = /^vg (\S+) out: (.*)$/.exec(body))) {
      const r = get(mm[1]);
      r.vg.out.push(mm[2]);
      const k = /^case \S+ (\S+) done code=(\d+) .* status=(\d+) /.exec(mm[2]);
      if (k) r.vg.codes.push(`${k[1]}:${k[2]}${k[3] !== '0' ? `/${k[3]}` : ''}`);
      continue;
    }
    if (!(mm = /^case (\S+) (.*)$/.exec(body))) continue;
    const r = get(mm[1]);
    body = mm[2];
    r.lines.push(body);
    let k;
    if ((k = /^fs (\S+) step=(\S+) pf=(\d+) tid=(\S+) path="([^"]*)" ?(.*)$/.exec(body))) {
      r.fs.push({ fn: k[1], step: k[2], pf: Number(k[3]), tid: k[4], path: k[5], rest: k[6] });
      continue;
    }
    if ((k = /^expect part=(\S+) len=(\d+) fnv=([0-9a-f]+)/.exec(body))) { r.expects.set(k[3], { part: k[1], len: Number(k[2]) }); continue; }
    if ((k = /^(\S+) done code=(\d+) \(([^)]*)\) errbuf="([^"]*)" status=(\d+) num_connects=(\d+) attempts=(\d+) data_out=(\S+) t_end=([\d.]+)/.exec(body))) {
      const x = r.xfers.get(k[1]) || {};
      Object.assign(x, { code: Number(k[2]), err: k[4], status: Number(k[5]), conns: Number(k[6]), attempts: Number(k[7]), dataOut: k[8], tEnd: Number(k[9]) });
      r.xfers.set(k[1], x);
      continue;
    }
    if ((k = /^(\S+) perform_max=([\d.]+) ms/.exec(body))) { const x = r.xfers.get(k[1]) || {}; x.pmax = Number(k[2]); r.xfers.set(k[1], x); continue; }
    if ((k = /^\S+ server: ev \d+ t=[\d.]+ (\S+) face=(\S+) conn=(\S+) ?(.*)$/.exec(body))) {
      const f = { kind: k[1], face: k[2], conn: k[3], rest: k[4] };
      const t = /tag=(\S+)/.exec(k[4]);
      f.tag = t ? t[1] : '-';
      // a part line follows its body line: it belongs to that request
      if (f.kind === 'body') { r.lastBody = r.lastBody || new Map(); r.lastBody.set(`${f.tag} ${f.conn}`, field(f.rest, 'idx')); }
      if (f.kind === 'part') f.idx = r.lastBody ? r.lastBody.get(`${f.tag} ${f.conn}`) : null;
      r.server.push(f);
    }
  }
  for (const [raw, run] of perLane) {
    const lane = laneOf(raw);
    if (!runs.has(lane)) runs.set(lane, []);
    runs.get(lane).push(run);
  }
}
const allLanes = LANES.filter(([l]) => runs.has(l));

// ---------------------------------------------------------------- cell helpers
function bodiesFor(r, tags) {
  // the requests and bodies the server logged for TAGS, in order
  const reqs = r.server.filter((e) => (e.kind === 'req' || e.kind === 'stream') && tags.includes(e.tag));
  const out = [];
  for (const q of reqs) {
    const idx = field(q.rest, q.kind === 'req' ? 'idx' : 'stream');
    const b = r.server.find((e) => (e.kind === 'body' || e.kind === 'partial') && e.tag === q.tag && e.conn === q.conn && (e.kind === 'partial' || field(e.rest, 'idx') === idx));
    const dropped = r.server.find((e) => e.kind === 'drop' && e.tag === q.tag && e.conn === q.conn && field(e.rest, 'idx') === idx);
    const rst = r.server.find((e) => e.kind === 'rst' && e.tag === q.tag && field(e.rest, 'stream') === idx && e.conn === q.conn);
    const ans = r.server.find((e) => e.kind === 'answer' && e.tag === q.tag && e.conn === q.conn && (field(e.rest, 'idx') === idx || field(e.rest, 'stream') === idx));
    const refused = r.server.find((e) => e.kind === 'refused-body' && e.tag === q.tag && field(e.rest, 'idx') === idx);
    out.push({
      tag: q.tag, conn: q.conn, idx, cl: field(q.rest, 'cl'), te: field(q.rest, 'te'), expect: field(q.rest, 'expect'), auth: field(q.rest, 'auth'),
      method: (/ (GET|POST|PUT) /.exec(` ${q.rest} `) || [])[1] || '?',
      got: b ? (b.kind === 'partial' ? `${field(b.rest, 'got')}(partial)` : field(b.rest, 'got')) : (dropped && field(dropped.rest, 'at') === 'head' ? '0(dropped at head)' : '-'),
      fnv: b && b.kind === 'body' ? field(b.rest, 'fnv') : null,
      framing: b ? field(b.rest, 'framing') : null,
      end: dropped ? `drop@${field(dropped.rest, 'at')}` : rst ? `RST@${field(rst.rest, 'at')}` : ans ? field(ans.rest, 'status') : refused ? 'refused-body' : 'none',
    });
  }
  return out;
}
function partsFor(r, tag) {
  return r.server.filter((e) => e.kind === 'part' && e.tag === tag);
}
// fileParts: the server's part 1 (the second part) of each body of TAG, by its expect name
function partName(r, p) {
  const un = /(^| )unterminated /.test(p.rest);
  const fnv = field(p.rest, 'fnv');
  const len = un ? field(p.rest, 'len_to_end') : field(p.rest, 'len');
  const seed = field(p.rest, 'seed');
  const e = r.expects.get(fnv);
  const what = e ? `${e.part}(${len})` : seed === 'empty' ? 'empty(0)' : seed && seed !== 'no' ? `seed${seed}(${len})` : `other(${len},${fnv})`;
  return un ? `unterminated ${what}` : what;
}
function partFilename(p) {
  const h = field(p.rest, 'headers') || '';
  const m = /filename=\\"([^\\]*)\\"/.exec(h);
  const t = /Content-Type: ([^\\]+)/.exec(h);
  return `${m ? `filename ${m[1]}` : 'no filename'}${t ? `, ${t[1]}` : ''}`;
}
function partSummary(r, tag, i = 1, withName = false) {
  const ps = partsFor(r, tag);
  const rows = ps.filter((p) => field(p.rest, 'i') === String(i));
  const sums = ps.filter((p) => / summary /.test(` ${p.rest} `));
  const bad = ps.filter((p) => /malformed|no-delimiter|no boundary/.test(p.rest));
  const parts = rows.map((p) => (withName ? `${partName(r, p)} [${partFilename(p)}]` : partName(r, p)));
  const s = parts.length ? parts.join(',') : 'none';
  return `${s}${bad.length ? `; ${bad.length} malformed` : ''}`;
}
const fopens = (r, re) => r.fs.filter((f) => /^fopen/.test(f.fn) && re.test(f.path));
const xf = (r, name) => r.xfers.get(name) || {};
const codeStr = (x) => (x.code === undefined ? 'no done line' : `${x.code}${x.status ? `/${x.status}` : ''}`);
const rcOf = (r, part) => { const l = r.lines.find((s) => s.startsWith(`mime fn=curl_mime_filedata part=${part} `)); return l ? field(l, 'rc') : '-'; };

function table(title, notes, rows, cell) {
  const diffs = [];
  // a lane none of whose runs holds any of the rows gets no column
  const lanes = allLanes.filter(([l]) => runs.get(l).some((run) => rows.some((row) => run.cases.has(row))));
  if (COUNT && !lanes.length) return '';
  let o = `\n### ${title}\n\n${notes}\n\n| Case | ${lanes.map(([, n]) => n).join(' | ')} |\n|---|${lanes.map(() => '---').join('|')}|\n`;
  for (const row of rows) {
    if (COUNT && !lanes.some(([l]) => runs.get(l).some((run) => run.cases.has(row)))) continue;
    const cells = lanes.map(([l, n]) => {
      const vals = runs.get(l).filter((run) => !COUNT || run.cases.has(row)).map((run) => {
        const r = run.cases.get(row);
        if (!r) return '—';
        try { return cell(r, row, l); } catch (e) { return `?(${e.message})`; }
      });
      const uniq = [...new Set(vals)];
      if (COUNT) {
        const n = new Map();
        for (const v of vals) n.set(v, (n.get(v) || 0) + 1);
        return [...n].sort((a, b) => b[1] - a[1]).map(([v, k]) => `${v} ×${k}`).join(' ‖ ').replace(/\|/g, '\\|');
      }
      if (uniq.length > 1) diffs.push(`${row} on ${n}: ${runs.get(l).map((run, i) => `${run.file}[${run.raw}]: ${vals[i]}`).join('; ')}`);
      return (uniq.length === 1 ? uniq[0] : vals.join(' ‖ ')).replace(/\|/g, '\\|');
    });
    o += `| ${row} | ${cells.join(' | ')} |\n`;
  }
  o += COUNT ? `\nRuns: ${lanes.map(([l, n]) => `${n} ${runs.get(l).length} runs (${[...new Set(runs.get(l).map((run) => run.file))].join(', ')})`).join('; ')}.\n`
    : `\nRuns: ${lanes.map(([l, n]) => `${n} ${runs.get(l).map((run) => `${run.file}[${run.raw}]`).join(', ')}`).join('; ')}.\n`;
  if (diffs.length && !COUNT) o += `\nCells whose runs differ:\n${diffs.map((d) => `- ${d}`).join('\n')}\n`;
  return o;
}

// N-relative's three transfers are rows of their own, read from its one case.
for (const [l] of allLanes) for (const run of runs.get(l)) { const r = run.cases.get('N-relative'); if (r) for (const s of ['stay', 'to-b', 'to-none']) run.cases.set(`N-relative-${s}`, r); }
const build = () => {
  let o = '';
  o += table('1. When and where libcurl reads a file part', 'Each cell: the step of each file call on the part\'s file, from the probe\'s `fs` lines (Linux alone): `stat` at `curl_mime_filedata`, the first `fopen` and the `curl_multi_perform` it ran in (#pf), each `fclose`; `tid` main is the thread that called libcurl. R-when: two file parts (when1, when2), then the same easy handle and mime sent again (the second fopen pair). R-big: a 4 MiB part, its `fread` count and the performs they spread over. X-drop-file: the opens of one transfer that libcurl resent. C-grown: where the grown file\'s `fclose` ran.',
    ['R-when', 'R-big', 'X-drop-file', 'C-grown'], (r, row) => {
      const fsOf = (re) => r.fs.filter((f) => re.test(f.path));
      if (row === 'R-when') {
        const a = fsOf(/when1\.txt$/);
        const st = a.filter((f) => /^stat/.test(f.fn) || f.fn === 'access').map((f) => `${f.fn}@${f.step}`);
        const op = a.filter((f) => /^fopen/.test(f.fn)).map((f) => `${f.fn}@${f.step}#${f.pf}`);
        const cl = a.filter((f) => f.fn === 'fclose').map((f) => `fclose@${f.step}#${f.pf}`);
        const tids = [...new Set(r.fs.map((f) => f.tid))].join(',');
        const b = fsOf(/when2\.txt$/).filter((f) => /^(fopen|fclose)/.test(f.fn)).map((f) => `${f.fn}#${f.pf}`);
        return `when1: ${[...new Set(st)].join(' ') || 'no stat'}; ${op.join(' ') || 'no fopen'}; ${cl.join(' ') || 'no fclose'}; when2: ${b.join(' ') || 'no fopen'}; tid=${tids || '-'}`;
      }
      if (row === 'R-big') {
        const a = fsOf(/big\.bin$/);
        const fr = a.filter((f) => f.fn === 'fread');
        const pfs = new Set(fr.map((f) => f.pf));
        const cl = a.filter((f) => f.fn === 'fclose').map((f) => `fclose@${f.step}`);
        const op = a.filter((f) => /^fopen/.test(f.fn)).map((f) => `${f.fn}@${f.step}`);
        return `${op.join(' ') || 'no fopen'}; ${fr.length} freads over ${pfs.size} performs; ${cl.join(' ') || 'no fclose'}; ${codeStr(xf(r, 'R-big'))}`;
      }
      if (row === 'X-drop-file') {
        const a = fopens(r, /up\.txt$/).map((f) => `#${f.pf}`);
        const s = r.fs.filter((f) => /^fseek/.test(f.fn) && /up\.txt$/.test(f.path)).map((f) => `${f.fn}(${field(f.rest, 'offset')})#${f.pf}`);
        return `fopen ${a.length}x (${a.join(' ')})${s.length ? `; ${s.join(' ')}` : '; no fseek'}; ${xf(r, 'X-drop-file').attempts} attempts`;
      }
      const cl = r.fs.filter((f) => f.fn === 'fclose' && /change\.txt$/.test(f.path)).map((f) => `fclose@${f.step}`);
      return cl.join(' ') || 'no fclose';
    });
  o += table('2. A file that changes between `curl_mime_filedata` and the transfer', 'Each cell: `curl_mime_filedata`\'s answer; the transfer\'s code/status; what the server read (Content-Length or chunked, and the bytes it got: "(partial)" when the connection ended first); the file part as received, named by the probe\'s `expect` line its FNV-1a matches (`other` when none does; "unterminated" when the body ended without the part\'s closing delimiter). C-missing: no file. C-missing-made: none at `filedata`, 1000 bytes made after. C-removed: unlinked after. C-unreadable-first: mode 000 before; -later: after. C-grown: 1000 bytes at `filedata`, 3000 at the transfer; C-shrunk: 3000, then 1000; C-replaced: another 1000-byte file renamed over it. The probe runs as the host\'s uid, never root (run.sh prints it).',
    ['C-missing', 'C-missing-made', 'C-removed', 'C-unreadable-first', 'C-unreadable-later', 'C-grown', 'C-shrunk', 'C-replaced'], (r, row) => {
      const x = xf(r, row);
      const b = bodiesFor(r, [row]);
      const srv = b.map((q) => `${q.te === 'chunked' ? 'chunked' : `CL ${q.cl}`} got ${q.got}`).join('; ') || 'no request';
      return `rc ${rcOf(r, 'upload')}; ${codeStr(x)}; ${srv}; part: ${partSummary(r, row)}`;
    });
  o += table('3. Paths that are not regular files', 'Each cell: `curl_mime_filedata`\'s answer; code/status; the framing the server read and the bytes it got; the file part as received (by `expect` name; `other` when no `expect` matches; `none` when the body held no second part). N-fifo-late: the longest `curl_multi_perform` and the transfer\'s end, in ms (the writer opens the FIFO 1500 ms in; TIMEOUT_MS 500). N-stdin: `stdin-left`, the bytes of the pipe left after the transfer. N-relative-*: `rel.txt`, relative, given in directory a (1000 bytes, `upload-a`); the transfer then runs there (stay), after a chdir to b (1500 bytes, `upload-b`), or after one to a directory with none.',
    ['N-fifo', 'N-fifo-late', 'N-dir', 'N-devnull', 'N-stdin', 'N-proc', 'N-relative-stay', 'N-relative-to-b', 'N-relative-to-none'], (r, row) => {
      const x = xf(r, row);
      const b = bodiesFor(r, [row]);
      const srv = b.map((q) => `${q.te === 'chunked' ? 'chunked' : `CL ${q.cl}`} got ${q.got}`).join('; ') || 'no request';
      let extra = '';
      if (row === 'N-fifo-late') extra = `; longest perform ${Math.round(x.pmax / 100) / 10} s, end at ${Math.round(x.tEnd / 100) / 10} s`;
      if (row === 'N-stdin') { const l = r.lines.find((s) => s.startsWith('stdin-left=')); extra = `; ${l || 'no stdin-left line'}`; }
      let rc = rcOf(r, 'upload');
      if (row.startsWith('N-relative')) {
        const i = r.lines.findIndex((s) => s.startsWith(`${row} setopt MIMEPOST`));
        const ls = r.lines.slice(0, i).filter((s) => s.startsWith('mime fn=curl_mime_filedata'));
        rc = ls.length ? field(ls[ls.length - 1], 'rc') : '-';
      }
      if (row === 'N-proc' && r.lines.some((s) => s.startsWith('skip:'))) return 'skipped: no /proc';
      return `rc ${rc}; ${codeStr(x)}; ${srv}; part: ${partSummary(r, row, 1, true)}${extra}`;
    });
  const resendRows = [];
  for (const base of ['X-417', 'X-late417', 'X-idle', 'X-drop', 'X-drophead', 'X-digest', 'X-stale', 'X-refuse-end', 'X-refuse-head', 'F-307', 'F-308']) {
    for (const k of ['data', 'file', 'pipe']) resendRows.push(`${base}-${k}`);
    if (base === 'X-idle') resendRows.push('X-idle1500-file');
    if (base === 'X-drophead' || base === 'X-refuse-head') resendRows.push(`${base}-big`);
  }
  const resendCell = (r, row) => {
    const x = xf(r, row);
    const tags = [row, `${row}.hop`];
    const b = bodiesFor(r, tags);
    const att = b.map((q) => `${q.got}${q.end !== '200' ? `→${q.end}` : ''}`).join(', ');
    const fnvs = b.filter((q) => q.fnv && Number(q.got) > 0).map((q) => q.fnv);
    const same = fnvs.length > 1 ? (new Set(fnvs).size === 1 ? 'bodies identical' : `bodies differ (${[...new Set(fnvs)].length} kinds)`) : '';
    const fo = fopens(r, /(up\.txt|fifo)$/).length;
    const fseeks = r.fs.filter((f) => /^fseek/.test(f.fn) && /(up\.txt|fifo)$/.test(f.path)).map((f) => `${f.fn}(${field(f.rest, 'offset')})`);
    const conns = new Set(b.map((q) => q.conn)).size;
    const seeds = b.map((q) => partsFor(r, q.tag).filter((p) => field(p.rest, 'i') === '1' && p.conn === q.conn && p.idx === q.idx)).flat().map((p) => partName(r, p));
    const pipe2 = /pipe/.test(row) ? `; file parts received ${seeds.join(',') || 'none'}` : '';
    // a big part's first attempt sends as much as the kernel took before the reset: timing, not a row
    const dout = /big/.test(row) ? (x.attempts > 1 ? `${x.dataOut.split(',').pop()} on the last` : 'part of the body') : x.dataOut;
    return `${codeStr(x)}${x.code ? ` "${x.err}"` : ''}; server: ${b.length} req on ${conns} conn: ${att || '-'}${same ? `; ${same}` : ''}; client: ${x.attempts} heads, data_out ${dout}${/file|pipe|big/.test(row) ? `; fopen ${fo}x${fseeks.length ? `, ${fseeks.join(' ')}` : ''}` : ''}${pipe2}`;
  };
  o += table('4 and 5. Resends inside one transfer, and libcurl\'s own follow', 'Each cell: code/status (with libcurl\'s error buffer when the code is not 0); the requests the server logged for the transfer\'s tag (and, for F-, its hop\'s), on how many connections, each as the body bytes it read and how it ended when not 200 (417, 401, 307, 308, drop@body or drop@head: closed unanswered, RST@head or RST@end: RST_STREAM REFUSED_STREAM, none: no answer before the connection went); whether the bodies of more than one non-empty request were byte-identical (FNV-1a of the whole body: one mime keeps its boundary); then the client\'s own count: the request heads libcurl sent (CURLINFO_HEADER_OUT) and the body bytes it sent after each (CURLINFO_DATA_OUT); for file, big and pipe parts, how many times libcurl opened the file and each `fseek` it made on it; for pipe, each file part the server received, by name (`upload` is the FIFO\'s first content, seed 3; a second open\'s content is seed 25, 103 mod 26). X-417: Expect: 100-continue named, 417 at the head, once. X-late417: the same, but 417 after the whole body (EXPECT_100_TIMEOUT_MS 200). X-idle: a GET, the server closes that connection 100 ms after it, the POST 400 ms later (X-idle1500: 1500 ms). X-drop: a GET, then the POST on that connection, read whole and closed unanswered; X-drophead: closed as its head arrived. X-digest: Digest; X-stale: the first valid response answered 401 stale=true. X-refuse-*: h2c, the first stream refused at its headers or at its end. F-307, F-308: FOLLOWLOCATION 1, the code after the whole body. The big kind is a 4 MiB file part, so that the resend comes while libcurl is inside it. The pipe kind is a FIFO whose writer writes once, then answers any second open with another content.',
    resendRows, resendCell);
  o += table('6. Lifetime: native outcome, and Valgrind', 'Each cell: the transfer\'s code/status and the bytes the server got; libcurl\'s live bytes after the last cleanup, by the counting allocator (natively; 0 is none leaked); then under Valgrind with the gate\'s options (ADR-0014): the probe\'s exit, ERROR SUMMARY\'s count, definitely lost (Valgrind prints no leak summary when every block was freed), and each transfer\'s code there, NAME:code/status. L-cleanup-then-free: `curl_easy_cleanup`, then `curl_mime_free`; L-free-then-cleanup: the reverse; L-free-in-multi: `curl_mime_free` while the done easy handle is still in its multi, then remove, then clean up; L-free-before-transfer: freed after MIMEPOST, before the transfer; L-null-then-free: MIMEPOST NULL, then free, then clean up; L-never-attached: a mime never attached, freed before and (second) after its easy handle\'s cleanup; L-free-midflight: freed 300 ms into an 8 MiB file part\'s send. M- rows are case 7\'s, under Valgrind too.',
    ['L-cleanup-then-free', 'L-free-then-cleanup', 'L-free-in-multi', 'L-free-before-transfer', 'L-null-then-free', 'L-never-attached', 'L-free-midflight', 'R-when', 'M-other-easy', 'M-other-gone', 'M-null-easy', 'M-twice', 'M-after-cleanup'], (r, row) => {
      const x = xf(r, row);
      const b = bodiesFor(r, [row]);
      const live = (() => { const ls = r.lines.filter((s) => /^live after_(multi_cleanup|all)=/.test(s) || /^all done live_before_global_cleanup=/.test(s)); return ls.length ? ls.map((s) => s.split('=').pop()).pop() : '-'; })();
      const vg = r.vg.exit === null ? 'no Valgrind run' : `vg exit ${r.vg.exit}, errors ${r.vg.errors}, definitely lost ${r.vg.definite}${r.vg.invalid.length ? `, ${[...new Set(r.vg.invalid)].join('; ')}` : ''}; codes under vg ${r.vg.codes.join(' ') || '-'}`;
      const got = (q) => (row === 'L-free-midflight' && /partial/.test(q.got) ? 'part of the body, then the connection ended' : q.got);
      const srv = row === 'L-never-attached' ? 'no transfer' : `${codeStr(x)}, server got ${b.map((q) => `${q.method} ${got(q)}`).join(',') || '-'}`;
      return `${srv}; live ${live}; ${vg}`;
    });
  o += table('7. A mime made with one easy handle, attached to another', 'Each cell: the MIMEPOST answers (on A, then on B, as the case makes them), the transfer on B\'s code, and the method and body bytes the server got for B. M-other-easy: made with A, attached to B, A alive. M-other-gone: A cleaned up before the attach. M-null-easy: `curl_mime_init(NULL)`. M-twice: attached to A, then to B while still on A. M-after-cleanup: attached to A, sent, A cleaned up, then attached to B.',
    ['M-other-easy', 'M-other-gone', 'M-null-easy', 'M-twice', 'M-after-cleanup'], (r, row) => {
      const ms = r.lines.filter((s) => /^setopt MIMEPOST on [AB] rc=/.test(s)).map((s) => s.replace(/^setopt MIMEPOST on ([AB]) rc=(\d+).*/, '$1:$2'));
      const x = xf(r, row);
      const b = bodiesFor(r, [row]);
      return `MIMEPOST ${ms.join(' ')}; ${codeStr(x)}; server: ${b.map((q) => `${q.method} ${q.got}`).join(',') || '-'}`;
    });
  o += table('8. A libcurl configured without mime, and the same calls on each lane', 'Each cell: the answers of D-calls\' lines, in order: `curl_mime_init(easy)`, `curl_mime_addpart`, `curl_mime_name`, `curl_mime_data`, `curl_mime_filedata`, MIMEPOST with NULL and with init\'s answer, `curl_formadd`, HTTPPOST, then two transfers: the mime init gave, with a data and a file part (D-send-init), and MIMEPOST NULL alone (D-send-mimepost-null): code, the server\'s method, Content-Type and body bytes.',
    ['D-calls'], (r) => {
      const pick = (re) => { const l = r.lines.find((s) => re.test(s)); return l || '-'; };
      const v = (re, f) => { const l = pick(re); return l === '-' ? '-' : f(l); };
      const init = v(/^curl_mime_init\(easy\)/, (l) => l.split('-> ')[1]);
      const ap = v(/^curl_mime_addpart/, (l) => l.split('-> ')[1]);
      const rc = (name) => v(new RegExp(`^${name} rc=`), (l) => field(l, 'rc'));
      const fd = v(/^curl_mime_filedata\(/, (l) => field(l, 'rc'));
      const mpn = v(/^setopt MIMEPOST NULL rc=/, (l) => field(l, 'rc'));
      const mpi = v(/^setopt MIMEPOST init's answer/, (l) => field(l, 'rc'));
      const fa = v(/^curl_formadd rc=/, (l) => field(l, 'rc'));
      const hp = v(/^setopt HTTPPOST rc=/, (l) => field(l, 'rc'));
      const sends = ['D-send-init', 'D-send-mimepost-null'].map((t) => {
        const x = xf(r, t);
        const q = r.server.find((e) => e.kind === 'req' && e.tag === t);
        const b = bodiesFor(r, [t])[0];
        const ct = q ? field(q.rest, 'ct') : '-';
        return `${t.replace('D-send-', '')}: ${codeStr(x)} ${b ? `${b.method} CL ${b.cl} ${b.te === 'chunked' ? 'chunked ' : ''}got ${b.got}` : '-'} ct ${ct === '-' ? 'none' : ct.replace(/boundary=-+[A-Za-z0-9]+/, 'boundary=…')}`;
      });
      const feat = v(/^version runtime=/, (l) => `features ${field(l, 'features')}`);
      return `init ${init}; addpart ${ap}; name ${rc('curl_mime_name')}; data ${rc('curl_mime_data')}; filedata ${fd}; MIMEPOST NULL ${mpn}, init's ${mpi}; formadd ${fa}; HTTPPOST ${hp}; ${sends.join('; ')}; ${feat}`;
    });
  return o;
};
let out = build();
const exits = [];
for (const [l, n] of allLanes) for (const run of runs.get(l)) for (const [c, r] of run.cases) if (r.exit !== null && r.exit !== 0) exits.push(`${n} ${run.file}[${run.raw}] ${c}: exit ${r.exit}`);
if (COUNT) out = out.replace(/\n### (\d)/g, '\n### Races: $1');
out += `\n### Probe processes that did not exit 0\n\n${exits.length ? exits.map((e) => `- ${e}`).join('\n') : 'None.'}\n`;
process.stdout.write(out);
