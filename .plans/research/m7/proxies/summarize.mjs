// M7's proxy probe: reads run.sh's logs and prints them by case.
//   node summarize.mjs table LOG...          one row per case and lane
//   node summarize.mjs splits LOG1 LOG2      the cases whose normalized
//                                            lines differ between two runs
//   node summarize.mjs show PATTERN LOG...   a case's normalized lines
//                                            (PATTERN a regular expression)
//   node summarize.mjs lanes [--diff] [--no-rs] LOG...
//                                            per case, lanes grouped by cell
//   node summarize.mjs headers NAMES PATTERN LOG...
//                                            named headers of every request
//   node summarize.mjs cite PATTERN LOG...   FILE:LINE of each done line
// Normalized: every port is its face's name, from the lane's "server" line
// ({o-raw}); a connection id is its order in the case (#1, #2); the PKI's
// path is {pki}; a Digest nonce, cnonce and response, and a peer or local
// port, are elided; dates in the leaf's text are dropped. The table's cell:
// code/status/connectcode, proxy_error, used_proxy, request_size,
// num_connects, the requests each face logged, and who answered (the
// body's first two words).
import { readFileSync } from 'node:fs';

const [mode, ...rest] = process.argv.slice(2);

function load(file) {
  const lanes = new Map(); // lane -> { ports, cases: Map(name -> lines) }
  const text = readFileSync(file, 'latin1');
  for (const line of text.split('\n')) {
    const m = /^\[([^\]]+)\] (.*)$/.exec(line);
    if (!m) continue;
    const [, lane, body] = m;
    let l = lanes.get(lane);
    if (!l) { l = { ports: new Map(), cases: new Map(), head: [] }; lanes.set(lane, l); }
    const sm = /^server (ctl=.*)$/.exec(body);
    if (sm) { for (const kv of sm[1].split(' ')) { const [k, v] = kv.split('='); l.ports.set(v, k); } continue; }
    const cm = /^case (\S+) (.*)$/.exec(body);
    if (!cm) { l.head.push(body); continue; }
    if (!l.cases.has(cm[1])) l.cases.set(cm[1], []);
    l.cases.get(cm[1]).push(cm[2]);
  }
  return lanes;
}

function normalizer(ports) {
  return (s, ids) => {
    let o = s.replace(/127\.0\.0\.1:(\d+)/g, (all, p) => (ports.has(p) ? `127.0.0.1:{${ports.get(p)}}` : all));
    o = o.replace(/(to=|port )(\d+)/g, (all, k, p) => (ports.has(p) ? `${k}{${ports.get(p)}}` : all));
    o = o.replace(/\/[^ "]*m7proxies\.[A-Za-z0-9]+\/pki/g, '{pki}');
    o = o.replace(/(nonce|cnonce|response)(=\\?"?)([0-9A-Za-z+/=]+)/g, '$1$2{$1}');
    o = o.replace(/(peer|local)=\d+/g, '$1={port}');
    o = o.replace(/from 127\.0\.0\.1 port \d+/g, 'from 127.0.0.1 port {port}');
    o = o.replace(/([a-z-]+)#(\d+)/g, (all, f, n) => {
      if (!ids.has(`${f}#${n}`)) ids.set(`${f}#${n}`, `${f}#${ids.size + 1}`);
      return ids.get(`${f}#${n}`);
    });
    return o;
  };
}

// steady: a line less what moves between runs by design: byte counts
// (an ECDSA signature's length varies, so a TLS face's counts move by a
// byte or two), the bytes a TLS client sent a plaintext face (its
// random), a pointer libcurl prints, and how many milliseconds a timeout
// took. splits compares these; the logs keep everything.
const steady = (s) => s.replace(/\b(in|out|up|down|bytes)=\d+/g, '$1={n}').replace(/ unparsed=\d+ ".*"$/, ' unparsed={bytes}').replace(/\b0x[0-9a-f]{6,}\b/g, '{address}').replace(/after \d+ milliseconds/g, 'after {n} milliseconds');
// VOLATILE: lines left out of splits' comparison: the leaf's dates, the
// run's paths, and how Node saw a client hang up after it refused a leaf
// (ECONNRESET, EPIPE, or nothing).
const VOLATILE = /^debug text " +(start|expire) date|^debug text " +(CAfile|CApath)|^step (ca|proxy-ca|capath|proxy-capath)=|^debug text "SSL connection using|^server: tls \S+ error (ECONNRESET|EPIPE) /;

function caseLines(l, name) {
  const norm = normalizer(l.ports);
  const ids = new Map();
  return (l.cases.get(name) || []).map((x) => norm(x, ids));
}

function cell(lines) {
  const done = lines.find((x) => x.startsWith('done '));
  if (!done) return '(no done line)';
  const f = (k) => { const m = new RegExp(` ${k}=(\\S*)`).exec(done); return m ? m[1] : '?'; };
  const code = /^done code=(\d+)/.exec(done)[1];
  const body = /body="(.*)"$/.exec(done);
  const who = body && body[1] ? body[1].split(' ').slice(0, 2).join(' ') : '-';
  const req = lines.find((x) => x.startsWith('server: requests '));
  const setopt = lines.filter((x) => x.startsWith('setopt ')).map((x) => x.replace(/ \(.*$/, '')).join(';');
  return `${code}/${f('status')}/${f('connectcode')} pe=${f('proxy_error')} up=${f('used_proxy')} rs=${f('request_size')} nc=${f('num_connects')} [${req ? req.slice(17) : '?'}] ${who}${setopt ? ` {${setopt}}` : ''}`;
}

if (mode === 'table') {
  const all = rest.map((f) => [f, load(f)]);
  const names = [];
  for (const [, lanes] of all) for (const [, l] of lanes) for (const n of l.cases.keys()) if (!names.includes(n)) names.push(n);
  for (const n of names) {
    console.log(n);
    for (const [file, lanes] of all) for (const [lane, l] of lanes) if (l.cases.has(n)) console.log(`  ${lane.padEnd(22)} ${cell(caseLines(l, n))}   (${file.split('/').pop()})`);
  }
} else if (mode === 'lanes') {
  // lanes [--diff] [--no-rs] LOG...: per case, the lanes grouped by their
  // cell, less used_proxy (which libcurls before 8.7.0 lack); with --diff
  // only the cases whose lanes do not all agree; with --no-rs, less
  // request_size too.
  let args = rest;
  const flags = new Set();
  while (args.length && args[0].startsWith('--')) { flags.add(args[0]); args = args.slice(1); }
  const diff = flags.has('--diff');
  const files = args;
  const all = files.map((f) => [f, load(f)]);
  const names = [];
  for (const [, lanes] of all) for (const [, l] of lanes) for (const n of l.cases.keys()) if (!names.includes(n)) names.push(n);
  for (const n of names) {
    const groups = new Map();
    for (const [file, lanes] of all) {
      for (const [lane, l] of lanes) {
        if (!l.cases.has(n)) continue;
        let k = cell(caseLines(l, n)).replace(/ up=\S+/, '');
        if (flags.has('--no-rs')) k = k.replace(/ rs=\S+/, '');
        if (!groups.has(k)) groups.set(k, []);
        groups.get(k).push(`${lane}(${file.split('/').pop().replace(/\.log$/, '')})`);
      }
    }
    if (diff && groups.size < 2) continue;
    console.log(n);
    for (const [k, ls] of groups) console.log(`    ${k}  <- ${ls.join(' ')}`);
  }
} else if (mode === 'splits') {
  const [a, b] = rest.map(load);
  let n = 0;
  for (const [lane, la] of a) {
    const lb = b.get(lane);
    if (!lb) { console.log(`lane ${lane}: not in the second log`); continue; }
    for (const name of la.cases.keys()) {
      const x = caseLines(la, name).filter((s) => !VOLATILE.test(s)).map(steady);
      const y = caseLines(lb, name).filter((s) => !VOLATILE.test(s)).map(steady);
      if (x.join('\n') !== y.join('\n')) {
        if ([...x].sort().join('\n') === [...y].sort().join('\n')) { console.log(`== ${lane} ${name}: the same lines, in another order`); continue; }
        n++;
        console.log(`== ${lane} ${name}`);
        const sx = new Set(x), sy = new Set(y);
        for (const s of x) if (!sy.has(s)) console.log(`  - ${s}`);
        for (const s of y) if (!sx.has(s)) console.log(`  + ${s}`);
      }
    }
    for (const name of lb.cases.keys()) if (!la.cases.has(name)) console.log(`== ${lane} ${name}: in the second log alone`);
  }
  console.log(`-- ${n} case(s) differ`);
} else if (mode === 'show') {
  const re = new RegExp(rest[0]);
  for (const f of rest.slice(1)) {
    for (const [lane, l] of load(f)) {
      for (const name of l.cases.keys()) {
        if (!re.test(name)) continue;
        console.log(`== ${lane} ${name} (${f.split('/').pop()})`);
        for (const s of caseLines(l, name)) console.log(`  ${s}`);
      }
    }
  }
} else if (mode === 'cite') {
  // cite PATTERN LOG...: FILE:LINE of each matching case's done line, by lane.
  const re = new RegExp(rest[0]);
  for (const f of rest.slice(1)) {
    readFileSync(f, 'latin1').split('\n').forEach((line, i) => {
      const m = /^\[([^\]]+)\] case (\S+) done /.exec(line);
      if (m && re.test(m[2])) console.log(`${f.split('/').pop()}:${i + 1} ${m[1]} ${m[2]}`);
    });
  }
} else if (mode === 'headers') {
  // headers NAMES PATTERN LOG...: NAMES a comma list of header names; for
  // each case and lane, each request a face logged, in order, as
  // FACE#N:METHOD and the named headers' exact values ("-" for none).
  const names = rest[0].toLowerCase().split(',');
  const re = new RegExp(rest[1]);
  for (const f of rest.slice(2)) {
    for (const [lane, l] of load(f)) {
      for (const name of l.cases.keys()) {
        if (!re.test(name)) continue;
        const reqs = caseLines(l, name).filter((s) => s.startsWith('server: req '));
        const out = reqs.map((s) => {
          const m = /^server: req (\S+) #\d+ "(.*)"$/.exec(s);
          const lines = m[2].split('\\r\\n');
          const method = lines[0].split(' ')[0];
          const vals = names.map((h) => {
            const v = lines.slice(1).filter((x) => x.toLowerCase().startsWith(`${h}:`)).map((x) => x.slice(h.length + 1).trim());
            return v.length ? v.map((x) => `"${x}"`).join('+') : '-';
          });
          return `${m[1]}:${method} ${vals.join(' ')}`;
        });
        console.log(`${name.padEnd(36)} ${lane.padEnd(22)} ${out.join(' ; ') || '(no request)'}`);
      }
    }
  }
} else {
  process.stderr.write('usage: node summarize.mjs table|lanes|splits|show|headers|cite ...\n');
  process.exit(2);
}
