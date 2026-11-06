// refuse-loop.mjs: the /refuse race, outside the suite. Starts ORIGIN (an
// origin.mjs) with --pki PKI, then N rounds of the three /refuse shapes
// test-origin-tls sends (at=0 HEADERS alone; at=3 HEADERS and 3 bytes of
// DATA, the stream left open; at=5 HEADERS and 3 bytes, then 4 more 300 ms
// on, ending the stream), each through PROBE (a wire-probe.mjs) with
// --half-close, on h2c and h2, each a fresh key. Prints one line per probe:
//   ROW face at round ok|MISS hex end
// and a tally. The origin's stderr goes to STDERR-FILE. Env: ORIGIN, PROBE,
// PKI, N, ORIGIN_ENV (extra env for the origin only, NAME=VALUE;...),
// PAR (probes run at once, default 1).
//
//   node refuse-loop.mjs
import { spawn, execFile } from 'node:child_process';
import { openSync } from 'node:fs';
import process from 'node:process';

const origin = process.env.ORIGIN || 'tests/origin.mjs';
const probe = process.env.PROBE || 'tests/wire-probe.mjs';
const pki = process.env.PKI;
const n = Number(process.env.N || '20');
const par = Number(process.env.PAR || '1');
const stderrFile = process.env.STDERR_FILE || '/dev/null';
const faces = (process.env.FACES || 'h2c,h2').split(',');
const ats = (process.env.ATS || '0,3,5').split(',').map((a) => (a === 'get' || a === 'stop0' ? a : Number(a)));

const oenv = { ...process.env };
for (const pair of (process.env.ORIGIN_ENV || '').split(';').filter(Boolean)) {
  const i = pair.indexOf('=');
  oenv[pair.slice(0, i)] = pair.slice(i + 1);
}

const frame = (type, flags, stream, payload) => {
  const h = Buffer.alloc(9);
  h.writeUIntBE(payload.length, 0, 3);
  h[3] = type; h[4] = flags; h.writeUInt32BE(stream, 5);
  return Buffer.concat([h, payload]);
};
const text = (s) => Buffer.concat([Buffer.from([s.length]), Buffer.from(s, 'latin1')]);
const preface = Buffer.from('PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n', 'latin1');
function start(scheme, path, cl) {
  const block = Buffer.concat([Buffer.from([0x83, scheme === 'http' ? 0x86 : 0x87, 0x04]), text(path),
    Buffer.from([0x01]), text('localhost'), Buffer.from([0x00]), text('content-length'), text(String(cl))]);
  return Buffer.concat([preface, frame(4, 0, 0, Buffer.alloc(0)), frame(1, 4, 1, block)]);
}
const want = '000000040000000000' + '000000040100000000' + '00000403000000000100000007';

const o = spawn(process.execPath, [origin, '--pki', pki], { env: oenv, stdio: ['pipe', 'pipe', openSync(stderrFile, 'a')] });
let announced = '';
const ann = await new Promise((resolve, reject) => {
  o.stdout.on('data', (c) => {
    announced += c;
    if (announced.includes('\n')) resolve(JSON.parse(announced.split('\n')[0]));
  });
  o.on('exit', (code) => reject(new Error(`origin exited ${code}`)));
});

function runProbe(args) {
  return new Promise((resolve) => {
    execFile(process.execPath, [probe, ...args], { env: process.env }, (err, stdout, stderr) => {
      resolve({ err, stdout, stderr });
    });
  });
}

// stoppedProbe: the probe with ARGS, the origin stopped (SIGSTOP) from 300
// ms after the probe says it connected to 2000 ms after, then continued.
function stoppedProbe(args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [probe, ...args], { env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stopped = false;
    child.stdout.on('data', (c) => {
      stdout += c;
      if (!stopped && stdout.includes('(connected ')) {
        stopped = true;
        setTimeout(() => process.kill(ann.pid, 'SIGSTOP'), 300);
        setTimeout(() => process.kill(ann.pid, 'SIGCONT'), 2000);
      }
    });
    child.on('close', () => resolve({ stdout }));
  });
}

function parse(out) {
  let hex = '';
  let end = null;
  for (const line of out.split('\n')) {
    const d = /^\(data \d+ \d+ "([0-9a-f]*)"\)$/.exec(line);
    if (d) hex += d[1];
    const e = /^\(end (\S+)/.exec(line);
    if (e) end = e[1];
  }
  return { hex, end };
}

const tally = {};
let seq = 0;
async function one(face, at, round) {
  const [host, port] = ann[face].split(':');
  const scheme = face === 'h2c' ? 'http' : 'https';
  seq += 1;
  const key = `loop-${face}-${at}-${round}-${seq}`;
  const tls = face === 'h2' ? ['--tls', 'localhost', '--alpn', 'h2'] : [];
  let bytes;
  let extra = [];
  let expect = want;
  if (at === 'get') {
    const block = Buffer.concat([Buffer.from([0x82, scheme === 'http' ? 0x86 : 0x87, 0x04]), text('/status/200'),
      Buffer.from([0x01]), text('localhost')]);
    bytes = Buffer.concat([preface, frame(4, 0, 0, Buffer.alloc(0)), frame(1, 5, 1, block)]);
    expect = '000000040000000000' + '000000040100000000' + '000006010400000001880f0d023131' + '00000b00010000000173746174757320323030' + '0a';
  } else if (at === 'stop0') {
    bytes = start(scheme, `/refuse?key=${key}&at=0`, 4);
    extra = ['--split', '24:1000'];
  } else if (at === 0) bytes = start(scheme, `/refuse?key=${key}&at=0`, 4);
  else if (at === 3) bytes = Buffer.concat([start(scheme, `/refuse?key=${key}&at=3`, 7), frame(0, 0, 1, Buffer.from('abc'))]);
  else {
    const first = Buffer.concat([start(scheme, `/refuse?key=${key}&at=5`, 7), frame(0, 0, 1, Buffer.from('abc'))]);
    bytes = Buffer.concat([first, frame(0, 1, 1, Buffer.from('defg'))]);
    extra = ['--split', `${first.length}:300`];
  }
  const probeArgs = ['--half-close', ...extra, ...tls, '--deadline', '30000', host, port, bytes.toString('hex'), '3000'];
  const r = at === 'stop0' ? await stoppedProbe(probeArgs) : await runProbe(probeArgs);
  const p = parse(r.stdout);
  const ok = p.hex === expect && p.end === 'eof';
  const k = `${face} at=${at}`;
  tally[k] = tally[k] || { ok: 0, miss: 0 };
  tally[k][ok ? 'ok' : 'miss'] += 1;
  console.log(`ROW ${face} ${at} ${round} ${ok ? 'ok' : 'MISS'} ${p.hex} ${p.end} key=${key}`);
}

const jobs = [];
for (let round = 1; round <= n; round += 1) {
  for (const face of faces) for (const at of ats) jobs.push([face, at, round]);
}
let next = 0;
async function worker() {
  while (next < jobs.length) {
    const j = jobs[next];
    next += 1;
    await one(...j);
  }
}
await Promise.all(Array.from({ length: par }, worker));
for (const [k, v] of Object.entries(tally)) console.log(`TALLY ${k} ok ${v.ok} miss ${v.miss}`);
o.stdin.end();
