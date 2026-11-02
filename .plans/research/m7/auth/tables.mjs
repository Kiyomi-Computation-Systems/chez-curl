// M7's auth probe: one line per transfer from run.sh's logs, for reading
// and for the README's tables. Node, the standard library only.
//   node tables.mjs LOG...           every transfer of every log
//   node tables.mjs -g D LOG...      group D's alone
//   node tables.mjs -x LOG...        across logs: each transfer's line
//                                    once per distinct value, with the
//                                    lanes and runs that gave it
// A transfer's line: its lane, case, face, then the row's code, status and
// Authorization schemes per request (auth_out); the server's rounds, each
// as AUTH:VERDICT/STATUS, and its body summary when not 0; the server's
// digest and basic verdicts, in short; and the transfer's own
// noteworthy lines (done's t, gave-up, seeks, prereqs, url_set, cred).
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

const args = process.argv.slice(2);
let group = null;
let across = false;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '-g') group = args[++i];
  else if (args[i] === '-x') across = true;
  else files.push(args[i]);
}

// pooled: a round whose connection (the client's port, at the server) an
// earlier transfer of the same lane and log used, marked "@pooled".
function parse(file) {
  const out = new Map();
  const run = basename(file).replace(/\.log$/, '');
  const seen = new Map();
  for (const line of readFileSync(file, 'latin1').split('\n')) {
    const m = /^\[([^\]]+)\] case (\S+) (raw|h2) (.*)$/.exec(line);
    if (!m) continue;
    const [, lane, name, face, rest] = m;
    if (group && !name.startsWith(`${group}:`)) continue;
    const k = `${lane}|${name}|${face}`;
    let e = out.get(k);
    if (!e) { e = { lane, run, name, face, parts: {} }; out.set(k, e); }
    const p = e.parts;
    let r;
    if ((r = /^row (.*)$/.exec(rest))) p.row = r[1].replace(/ server=\d+/, '');
    else if ((r = /^server: rounds n=\d+ (.*)$/.exec(rest))) {
      if (!seen.has(lane)) seen.set(lane, new Set());
      const before = seen.get(lane);
      const rs = [...r[1].matchAll(/\[#\d+ \S+ (\S+) conn=(\d+) auth=(\S+) status=(\S+) (\S+) body=(\S+)\]/g)];
      p.rounds = rs.map(([, meth, conn, a, st, when, body]) => `${a}/${st}${when === 'early' ? '(early)' : ''}${body !== '0' ? `{${body.replace(/:sha=[0-9a-f]+/, '')}}` : ''}${before.has(`${face}:${conn}`) ? '@pooled' : ''}`).join(' ');
      p.conns = new Set(rs.map((x) => x[2])).size;
      for (const x of rs) before.add(`${face}:${x[2]}`);
    } else if ((r = /^server: digest #(\d+) (\S+) .*?alg=(\S+) qop=(\S+) nc=(\S+) .*?userhash=(\S+) username="([^"]*)" .*?alt=(\S+)( .*)?$/.exec(rest))) {
      (p.digest ??= []).push(`#${r[1]}:${r[2]}${r[8] !== '-' ? `[alt=${r[8]}]` : ''} alg=${r[3]} qop=${r[4]} nc=${r[5]}${r[6] !== '-' ? ` uh=${r[6]}` : ''}`);
      const notes = (r[9] || '').match(/nonce-from=\S+|nc-repeat/g);
      if (notes) p.digest.push(notes.join(','));
    } else if ((r = /^server: basic #(\d+) decoded="([^"]*(?:\\"[^"]*)*)" .*match=(\S+)/.exec(rest))) (p.basic ??= []).push(`#${r[1]}:"${r[2]}"=${r[3]}`);
    else if ((r = /^server: (after-refusal #\d+: .*|closed #\d+ .*|body #\d+ after the early answer: .*)$/.exec(rest))) (p.notes ??= []).push(r[1].replace(/:sha=[0-9a-f]+/, ''));
    else if ((r = /^server: (stale: .*|scheme: .*)$/.exec(rest))) (p.notes ??= []).push(r[1]);
    else if ((r = /^done code=(\d+) err="([^"]*)" t=(\S+) .*?conns=(\S+) outs=(\d+) reads=(\d+) seeks=(\d+) prereqs=(\d+) handed=(\d+)/.exec(rest))) {
      p.done = `t=${r[3]} reads=${r[6]} seeks=${r[7]} prereqs=${r[8]} handed=${r[9]}`;
      p.t = Number(r[3]);
    } else if ((r = /^gave-up (.*)$/.exec(rest))) p.gaveup = r[1];
    else if ((r = /^seek n=(\d+) .*answer=(\S+)$/.exec(rest))) (p.seeks ??= []).push(`seek${r[1]}=${r[2]}`);
    else if ((r = /^cred (.*)$/.exec(rest))) p.cred = r[1];
    else if ((r = /^url_set rc=(\d+)/.exec(rest))) p.url = `url_set=${r[1]}`;
    else if ((r = /^setopt (\S+) rc=(\d+)/.exec(rest))) (p.setopt ??= []).push(`${r[1]}=${r[2]}`);
    else if ((r = /^wire #(\d+) DIFFERS/.exec(rest))) (p.wire ??= []).push(`wire#${r[1]}-DIFFERS`);
    else if ((r = /^wire requests (.*)$/.exec(rest))) (p.wire ??= []).push(`requests ${r[1]}`);
    else if ((r = /^text t=(\S+) "(.*)"$/.exec(rest))) {
      if (!/^Issue another request/.test(r[2]) && /rewind|Mid-auth|stop sending|keep sending|problem|Ignoring this|not supported|Unsupported|refused|Connection died|necessary data|Expect:|100-continue|417|seek/i.test(r[2]))
        (p.text ??= []).push(`${r[1]}:${r[2]}`);
    }
  }
  return [...out.values()];
}

function brief(e, full) {
  const p = e.parts;
  const bits = [p.row ?? '(no row)'];
  if (p.rounds) bits.push(`server=[${p.rounds}] conns=${p.conns}`);
  if (p.cred) bits.push(p.cred);
  if (p.url) bits.push(p.url);
  if (p.setopt) bits.push(`setopt:${p.setopt.join(',')}`);
  if (p.digest) bits.push(`digest:${p.digest.join(' ')}`);
  if (p.basic && full) bits.push(`basic:${p.basic.join(' ')}`);
  if (p.seeks) bits.push(p.seeks.join(','));
  if (p.notes) bits.push(`notes:${p.notes.join(' | ')}`);
  if (p.gaveup) bits.push(`GAVE-UP ${p.gaveup}`);
  if (p.wire) bits.push(p.wire.join(','));
  if (full && p.done) bits.push(p.done);
  if (full && p.text) bits.push(`text:${p.text.join(' | ')}`);
  return bits.join(' ; ');
}

if (!across) {
  for (const f of files) for (const e of parse(f)) console.log(`${e.lane} ${e.name} ${e.face} :: ${brief(e, true)}`);
} else {
  // Timing (t=, handed=, reads=) is left out, so a line differs only on
  // what the transfer did; a row whose done t= splits is shown by -g alone.
  const byCase = new Map();
  for (const f of files) {
    for (const e of parse(f)) {
      const k = `${e.name} ${e.face}`;
      if (!byCase.has(k)) byCase.set(k, new Map());
      // Outcomes only: times, and how many body bytes a server read before a
      // close (more than 0), are left out; a body read whole, or none, stays.
      // @pooled is kept for the body groups alone (W, S, E, H): elsewhere
      // connection reuse is not what is measured.
      let v = brief(e, false).replace(/\{(\d+):pattern=ok\}/g, '{$1}')
        .replace(/\{[1-9]\d*:pattern=ok\(closed\)\}/g, '{part(closed)}')
        .replace(/with [1-9]\d* body bytes read/g, 'with some body bytes read')
        .replace(/, (whole )?at [\d.]+ms/g, '').replace(/ at [\d.]+ms/g, '')
        .replace(/after 10000 ms, the probe's own bound: status=(\d+) outs=(\d+) handed=\d+ rpaused=\d+/, 'after 10000 ms: status=$1 outs=$2');
      if (/^[CABD]:/.test(e.name)) v = v.replace(/@pooled/g, '');
      const m = byCase.get(k);
      if (!m.has(v)) m.set(v, []);
      m.get(v).push(e.run.replace(/^docker-/, '').replace(/^guix-/, 'guix-') + ':' + e.lane);
    }
  }
  for (const [k, m] of byCase) {
    if (m.size === 1) {
      const [[v, who]] = [...m];
      console.log(`${k} :: ALL(${who.length}) :: ${v}`);
    } else {
      for (const [v, who] of m) console.log(`${k} :: ${who.join(',')} :: ${v}`);
    }
  }
}
