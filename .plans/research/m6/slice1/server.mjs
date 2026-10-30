// M6 slice 1's probe server (2026-10-30; the M6 plan, section 4.1). Node 20
// or later, ESM, the standard library only. Not tests/origin.mjs: that file
// is the suites' and stays as it is.
//
//   node server.mjs PKI
//
// PKI is a directory tests/make-test-pki.sh made. Once every face listens it
// writes one line on stdout, a flat JSON object, then serves until stdin
// ends, and exits 0:
//   {"node":"v24.18.0","pid":N,"http":"127.0.0.1:P","raw":...,"https":...,"h2":...,"proxy":...}
//
// The faces, each on 127.0.0.1:
//   http   node:http, keep-alive as Node keeps it;
//   raw    node:net, every head written byte for byte, Connection: close and
//          a FIN after each answer;
//   https  node:https, the good leaf, ALPN http/1.1 alone;
//   h2     node:http2's secure server, compat API, the good leaf, ALPN h2
//          alone: a client that does not choose h2 has its socket destroyed;
//   proxy  node:http, a plain HTTP proxy for CONNECT alone: it answers
//          "HTTP/1.1 200 Connection Established" and pipes both ways; any
//          other request gets a 400.
//
// The routes, on http, raw, https and h2 alike but where said:
//   /body?n=N[&chunk=K][&gap=MS][&delay=MS][&pattern=mod251|zero][&gzip=1]
//     200, Content-Type: application/octet-stream, X-Probe: body, X-Twice: a,
//     X-Twice: b, and Content-Length: the body is N bytes, byte i being i
//     mod 251, or zero; with gzip=1 the body is those bytes gzip-encoded,
//     Content-Encoding: gzip, and Content-Length its own. DELAY ms after the
//     head, K bytes a write (default 16384), GAP ms apart, each write that
//     returns false awaiting its drain; the head is flushed at once, before
//     the delay. A HEAD gets the head alone.
//   /early
//     a 100 Continue, then a 103 Early Hints with a Link header, then 50 ms
//     on a 200 with X-Probe: early and the body "early\n". On raw, exact
//     bytes; on http, https and h2 by writeContinue and writeEarlyHints.
//   /empty   a 204, no body.
//   /small   a 200, X-Probe: small, the body "ok\n".
//   /hold?ms=N
//     holds the request N ms, or until the connection closes, then a 200,
//     "held\n".
//   /pieces?n=N&size=S&gap=MS
//     raw alone: a 200, Content-Length N*S, then N writes of S bytes each,
//     GAP ms apart, the bytes of write i (from 1) all i.
//   /connects
//     http alone: "connects N\n", N the CONNECTs the proxy face has taken.
//   anything else: 404.
import { readFileSync } from 'node:fs';
import http from 'node:http';
import http2 from 'node:http2';
import https from 'node:https';
import net from 'node:net';
import process from 'node:process';
import zlib from 'node:zlib';

const HOST = '127.0.0.1';
const fatal = (what, err) => { process.stderr.write(`server: ${what}: ${(err && err.stack) || err}\n`); process.exit(1); };
process.on('uncaughtException', (err) => fatal('uncaught exception', err));
process.on('unhandledRejection', (err) => fatal('unhandled rejection', err));

const pki = process.argv[2];
if (!pki) { process.stderr.write('usage: node server.mjs PKI\n'); process.exit(2); }
const cert = readFileSync(`${pki}/good.pem`);
const key = readFileSync(`${pki}/good.key`);
const sleep = (n) => new Promise((r) => setTimeout(r, n));

const sockets = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };
const sessions = new Set();

function parseTarget(target) {
  const q = target.indexOf('?');
  const path = q < 0 ? target : target.slice(0, q);
  const params = new URLSearchParams(q < 0 ? '' : target.slice(q + 1));
  return { path, params };
}

// The bodies, each made once.
const block = Buffer.from(Array.from({ length: 251 }, (_, i) => i));
const bodies = new Map();
function bodyOf(n, pattern, gz) {
  const k = `${n}:${pattern}:${gz}`;
  let b = bodies.get(k);
  if (!b) {
    const plain = pattern === 'zero' ? Buffer.alloc(n) : Buffer.alloc(n).fill(block);
    b = gz ? zlib.gzipSync(plain, { level: 9 }) : plain;
    bodies.set(k, b);
  }
  return b;
}
function bodyParams(params) {
  const n = Number(params.get('n') || '0');
  const pattern = params.get('pattern') === 'zero' ? 'zero' : 'mod251';
  const gz = params.get('gzip') === '1';
  return {
    data: bodyOf(n, pattern, gz),
    gz,
    k: Math.max(1, Number(params.get('chunk') || '16384')),
    gap: Number(params.get('gap') || '0'),
    delay: Number(params.get('delay') || '0'),
  };
}

// pump: DATA through W, K bytes a write, GAP ms apart, after DELAY ms; a
// write that returns false awaits W's drain or close.
async function pump(w, data, k, gap, delay) {
  if (delay > 0) await sleep(delay);
  for (let off = 0; off < data.length; off += k) {
    if (w.gone()) return false;
    const ok = w.write(data.subarray(off, Math.min(off + k, data.length)));
    if (!ok) await w.drain();
    if (gap > 0 && off + k < data.length) await sleep(gap);
  }
  return true;
}
function drainOf(emitter) {
  return () => new Promise((res) => {
    const done = () => { emitter.off('drain', done); emitter.off('close', done); res(); };
    emitter.on('drain', done);
    emitter.on('close', done);
  });
}

let connects = 0;

// --- http, https and h2: one handler, node:http's API and http2's compat --
async function handle(req, res) {
  req.on('error', () => {});
  res.on('error', () => {});
  const { path, params } = parseTarget(req.url);
  const head = req.method === 'HEAD';
  switch (path) {
    case '/body': {
      const p = bodyParams(params);
      const h = { 'content-type': 'application/octet-stream', 'x-probe': 'body', 'x-twice': ['a', 'b'] };
      if (p.gz) h['content-encoding'] = 'gzip';
      h['content-length'] = String(p.data.length);
      res.writeHead(200, h);
      if (head) { res.end(); return; }
      // node:http holds a head back until the first write: send it now.
      if (typeof res.flushHeaders === 'function') res.flushHeaders();
      const w = { write: (b) => res.write(b), drain: drainOf(res), gone: () => res.destroyed || res.writableEnded || (res.stream && res.stream.destroyed) };
      if (await pump(w, p.data, p.k, p.gap, p.delay)) res.end();
      return;
    }
    case '/early':
      res.writeContinue();
      res.writeEarlyHints({ link: '</style.css>; rel=preload; as=style' });
      await sleep(50);
      res.writeHead(200, { 'x-probe': 'early', 'content-length': '6' });
      res.end(head ? undefined : 'early\n');
      return;
    case '/empty':
      res.writeHead(204);
      res.end();
      return;
    case '/small':
      res.writeHead(200, { 'x-probe': 'small', 'content-length': '3' });
      res.end(head ? undefined : 'ok\n');
      return;
    case '/hold': {
      const ms = Number(params.get('ms') || '1000');
      await new Promise((r) => { const t = setTimeout(r, ms); res.on('close', () => { clearTimeout(t); r(); }); });
      if (res.destroyed) return;
      res.writeHead(200, { 'content-length': '5' });
      res.end('held\n');
      return;
    }
    case '/connects': {
      const body = `connects ${connects}\n`;
      res.writeHead(200, { 'content-length': String(body.length) });
      res.end(body);
      return;
    }
    default:
      res.writeHead(404, { 'content-length': '10' });
      res.end('not found\n');
  }
}
const handler = (req, res) => { handle(req, res).catch(() => { try { res.destroy(); } catch (e) { /* gone */ } }); };

const httpFace = http.createServer(handler);
httpFace.on('connection', track);
const httpsFace = https.createServer({ cert, key, ALPNProtocols: ['http/1.1'] }, handler);
httpsFace.on('connection', track);
httpsFace.on('tlsClientError', () => {});
const h2Face = http2.createSecureServer({ cert, key, ALPNProtocols: ['h2'], allowHTTP1: false }, handler);
h2Face.on('connection', track);
h2Face.on('tlsClientError', () => {});
h2Face.on('unknownProtocol', (socket) => socket.destroy());
h2Face.on('session', (session) => {
  sessions.add(session);
  session.on('close', () => sessions.delete(session));
  session.on('error', () => session.destroy());
});

// --- raw: exact bytes ------------------------------------------------------
const rawFace = net.createServer({ allowHalfOpen: true }, (sock) => {
  track(sock);
  let buf = Buffer.alloc(0);
  let started = false;
  sock.on('data', (chunk) => {
    if (started) return;
    buf = Buffer.concat([buf, chunk]);
    const end = buf.indexOf('\r\n\r\n');
    if (end < 0) { if (buf.length > 65536) sock.destroy(); return; }
    started = true;
    const [method, target] = buf.toString('latin1', 0, end).split('\r\n')[0].split(' ');
    raw(sock, method, target).catch(() => sock.destroy());
  });
  sock.on('end', () => { if (!started) sock.end(); });
});
async function raw(sock, method, target) {
  const { path, params } = parseTarget(target);
  const head = method === 'HEAD';
  const w = { write: (b) => sock.write(b), drain: drainOf(sock), gone: () => sock.destroyed };
  switch (path) {
    case '/body': {
      const p = bodyParams(params);
      sock.write(`HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nX-Probe: body\r\nX-Twice: a\r\nX-Twice: b\r\n${p.gz ? 'Content-Encoding: gzip\r\n' : ''}Content-Length: ${p.data.length}\r\nConnection: close\r\n\r\n`);
      if (!head) await pump(w, p.data, p.k, p.gap, p.delay);
      sock.end();
      return;
    }
    case '/early':
      sock.write('HTTP/1.1 100 Continue\r\n\r\n');
      sock.write('HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload; as=style\r\n\r\n');
      await sleep(50);
      sock.end(`HTTP/1.1 200 OK\r\nX-Probe: early\r\nContent-Length: 6\r\nConnection: close\r\n\r\n${head ? '' : 'early\n'}`);
      return;
    case '/empty':
      sock.end('HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n');
      return;
    case '/small':
      sock.end(`HTTP/1.1 200 OK\r\nX-Probe: small\r\nContent-Length: 3\r\nConnection: close\r\n\r\n${head ? '' : 'ok\n'}`);
      return;
    case '/pieces': {
      const n = Number(params.get('n') || '3');
      const size = Number(params.get('size') || '5');
      const gap = Number(params.get('gap') || '50');
      sock.write(`HTTP/1.1 200 OK\r\nContent-Length: ${n * size}\r\nConnection: close\r\n\r\n`);
      for (let i = 1; i <= n; i++) {
        await sleep(gap);
        if (sock.destroyed) return;
        sock.write(Buffer.alloc(size, i));
      }
      sock.end();
      return;
    }
    default:
      sock.end('HTTP/1.1 404 Not Found\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n');
  }
}

// --- proxy: CONNECT alone ----------------------------------------------------
const proxyFace = http.createServer((req, res) => { res.writeHead(400, { 'content-length': '0' }); res.end(); });
proxyFace.on('connection', track);
proxyFace.on('connect', (req, client, early) => {
  track(client);
  const [host, port] = req.url.split(':');
  const up = net.connect(Number(port), host, () => {
    connects++;
    client.write('HTTP/1.1 200 Connection Established\r\nX-Proxy: probe\r\n\r\n');
    if (early && early.length) up.write(early);
    up.pipe(client);
    client.pipe(up);
  });
  track(up);
  up.on('error', () => client.destroy());
  client.on('error', () => up.destroy());
  client.on('close', () => up.destroy());
  up.on('close', () => client.destroy());
});

const listen = (server) => new Promise((resolve) => server.listen(0, HOST, () => resolve(`${HOST}:${server.address().port}`)));
const faces = { http: httpFace, raw: rawFace, https: httpsFace, h2: h2Face, proxy: proxyFace };
const line = { node: process.version, pid: process.pid };
for (const [name, server] of Object.entries(faces)) line[name] = await listen(server);
process.stdout.write(`${JSON.stringify(line)}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const s of Object.values(faces)) s.close();
  process.exit(0);
});
