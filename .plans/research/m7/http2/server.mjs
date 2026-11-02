// M7's HTTP/2 probe server (2026-11-02; the M7 plan's measurements, area
// HTTP/2 and the HTTP version). Node 20 or later, ESM, the standard library
// only. Run with the PKI directory tests/make-test-pki.sh made:
//   node server.mjs PKI
// Writes one line on stdout, the ports, then serves until stdin ends:
//   ctl=PORT h1=PORT tlsh2=PORT tlsh1=PORT h2c=PORT
//
// Faces:
//   h1     plaintext HTTP/1.1 on node:net, parsed by hand, keep-alive. It
//          ignores Upgrade (answers over HTTP/1.1, as a server without h2c
//          does), and logs every request header. A connection whose first
//          bytes are the HTTP/2 preface is logged, answered 400 and closed.
//   tlsh2  TLS, the good leaf; its ALPNCallback logs the list the client
//          offered, in the client's order, and chooses h2 when offered, else
//          http/1.1 when offered, else refuses (Node's fatal alert). h2 goes
//          to node:http2, http/1.1 or no ALPN to the h1 handler.
//   tlsh1  as tlsh2, but chooses http/1.1 when offered, else refuses: an
//          origin that offers http/1.1 alone.
//   h2c    plaintext; the first bytes of each connection are logged, then
//          put back (unshift) and the socket handed to node:http2's
//          plaintext server: HTTP/2 by prior knowledge. An HTTP/1.1 request
//          there fails as node:http2 fails it, and its error is logged.
//   ctl    plaintext control, never logged:
//            GET /seq            the last event's number
//            GET /events?after=N every event after N, one a line, once no
//                                request is open (bounded at 3 s)
//            GET /summary?after=N&face=F
//                                one line: accepts=K ports=P,.. req_conns=P,..
//                                streams=S, from the events after N on F
//
// Routes on h1, tlsh2, tlsh1 and h2c, over HTTP/1.1 and HTTP/2 alike:
//   /hello            200, "hello\n", Content-Length 6
//   /body?n=BYTES&chunk=K&gap=MS&delay=MS
//                     200, Content-Length n; byte i is i mod 251; K bytes a
//                     write, GAP ms apart, after DELAY ms. Logs, as M6's
//                     pause server did: the bytes written when a write first
//                     returned false; each drain wait of 5 ms or more as
//                     WRITTEN:MS, the shorter counted and summed; the total
//                     time from the head's arrival to the last write's flush.
//   anything else     404.
// Every request may carry tag=TAG in its query, which its event lines name.
//
// Sockets that serve HTTP/1.1 set TCP_NODELAY: with Nagle on, the first
// body byte after a head written alone came ~40 ms late (measured). The
// HTTP/2 path keeps Node's default, as M6's pause server did.
//
// Event lines: "ev SEQ t=MS KIND face=F conn=PORT ...", MS from the server's
// start, PORT the client's port as the server's socket saw it. KIND is one
// of accept, alpn, tls, tls-error, first, preface, req, body, session,
// session-error, goaway, close.
import { readFileSync } from 'node:fs';
import http2 from 'node:http2';
import net from 'node:net';
import tls from 'node:tls';

const pki = process.argv[2];
const cert = readFileSync(`${pki}/good.pem`);
const key = readFileSync(`${pki}/good.key`);
const T0 = performance.now();
const now = () => performance.now();
const ms = (x) => x.toFixed(1);
const sleep = (n) => new Promise((r) => setTimeout(r, n));

const sockets = new Set();
const sessions = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };

const events = [];
let seq = 0;
let inflight = 0;
const ev = (kind, face, port, rest) => {
  seq++;
  events.push({ seq, kind, face, port, rest, line: `ev ${seq} t=${ms(now() - T0)} ${kind} face=${face} conn=${port}${rest ? ` ${rest}` : ''}` });
};
const escStr = (s, max = 512) => {
  let o = '';
  for (let i = 0; i < s.length && i < max; i++) {
    const c = s.charCodeAt(i);
    if (c === 13) o += '\\r';
    else if (c === 10) o += '\\n';
    else if (c === 92 || c === 34 || c < 0x20 || c > 0x7e) o += `\\x${(c & 0xff).toString(16).padStart(2, '0')}`;
    else o += s[i];
  }
  if (s.length > max) o += `...(${s.length} bytes)`;
  return `"${o}"`;
};

function parseTarget(target) {
  const q = target.indexOf('?');
  const path = q < 0 ? target : target.slice(0, q);
  const params = new URLSearchParams(q < 0 ? '' : target.slice(q + 1));
  return { path, params };
}

const patternCache = new Map();
function pattern(n) {
  let b = patternCache.get(n);
  if (!b) {
    b = Buffer.alloc(n);
    for (let i = 0; i < n; i++) b[i] = i % 251;
    patternCache.set(n, b);
  }
  return b;
}

// pump: M6's pause server's, unchanged in what it logs. W: { write(buf, cb)
// -> bool, drain() -> Promise, gone() -> bool }.
async function pump(w, data, k, gap, delay) {
  const rec = { written: 0, firstFalse: null, long: [], shortN: 0, shortMs: 0, aborted: 0, flushed: null };
  let flushed;
  rec.lastP = new Promise((res) => { flushed = res; });
  if (delay > 0) await sleep(delay);
  if (data.length === 0) flushed();
  for (let off = 0; off < data.length; off += k) {
    if (w.gone()) { rec.aborted = 1; flushed(); break; }
    const piece = data.subarray(off, Math.min(off + k, data.length));
    const last = off + k >= data.length;
    const ok = w.write(piece, last ? () => { rec.flushed = now(); flushed(); } : undefined);
    rec.written = off + piece.length;
    if (!ok) {
      if (rec.firstFalse === null) rec.firstFalse = rec.written;
      const t = now();
      const why = await w.drain();
      const d = now() - t;
      if (d >= 5) rec.long.push(`${rec.written}:${ms(d)}`); else { rec.shortN++; rec.shortMs += d; }
      if (why === 'close') { rec.aborted = rec.written < data.length ? 1 : 0; flushed(); if (rec.aborted) break; }
    }
    if (gap > 0 && !last) await sleep(gap);
  }
  return rec;
}

function bodyParams(params) {
  const n = Number(params.get('n') || '0');
  const k = Math.max(1, Number(params.get('chunk') || '16384'));
  const gap = Number(params.get('gap') || '0');
  const delay = Number(params.get('delay') || '0');
  return { n, k, gap, delay, data: pattern(n) };
}

function bodyRest(tag, p, rec, t0) {
  const total = rec.flushed == null ? '-' : ms(rec.flushed - t0);
  return `tag=${tag} n=${p.n} chunk=${p.k} gap=${p.gap} delay=${p.delay} written=${rec.written} first_false=${rec.firstFalse === null ? 'none' : rec.firstFalse} drains_long=${rec.long.length} [${rec.long.join(',')}] drains_short=${rec.shortN} sum=${ms(rec.shortMs)}ms total=${total}ms aborted=${rec.aborted}`;
}

// ---------------------------------------------------------------- HTTP/1.1
function serveH1(stream, face, port) {
  const conn = { face, stream, port, buf: Buffer.alloc(0), busy: false, dead: false, first: true };
  stream.on('data', (chunk) => {
    conn.buf = conn.buf.length ? Buffer.concat([conn.buf, chunk]) : chunk;
    parseH1(conn);
  });
  stream.on('close', () => ev('close', face, port, 'h1'));
}

function parseH1(conn) {
  for (;;) {
    if (conn.busy || conn.dead) return;
    if (conn.first && conn.buf.length >= 3) {
      conn.first = false;
      if (conn.buf.toString('latin1', 0, Math.min(conn.buf.length, 14)) === 'PRI * HTTP/2.0'.slice(0, Math.min(conn.buf.length, 14))) {
        ev('preface', conn.face, conn.port, `the HTTP/2 connection preface ${escStr(conn.buf.toString('latin1'), 64)}: answered 400 and closed`);
        conn.dead = true;
        conn.stream.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
        return;
      }
    }
    const end = conn.buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const head = conn.buf.toString('latin1', 0, end);
    conn.buf = conn.buf.subarray(end + 4);
    const lines = head.split('\r\n');
    const [method, target, version] = lines[0].split(' ');
    const hs = [];
    let cl = 0;
    for (const l of lines.slice(1)) {
      const i = l.indexOf(':');
      if (i < 0) continue;
      const name = l.slice(0, i).trim();
      const v = l.slice(i + 1).trim();
      hs.push(`${name}: ${v}`);
      if (name.toLowerCase() === 'content-length') cl = Number(v);
    }
    const { path, params } = parseTarget(target || '');
    const tag = params.get('tag') || '-';
    const upgrade = hs.filter((h) => /^upgrade:/i.test(h)).map((h) => h.slice(8).trim()).join(',') || 'none';
    ev('req', conn.face, conn.port, `proto=h1 tag=${tag} ${method} ${path} ${version} upgrade=${upgrade} headers=${escStr(hs.join(' | '), 1024)}`);
    if (cl > 0) conn.buf = conn.buf.subarray(Math.min(cl, conn.buf.length));
    conn.busy = true;
    inflight++;
    dispatchH1(conn, path, params, tag).catch((err) => { ev('error', conn.face, conn.port, String(err)); conn.stream.destroy(); })
      .finally(() => { inflight--; conn.busy = false; setImmediate(() => parseH1(conn)); });
  }
}

async function dispatchH1(conn, path, params, tag) {
  const s = conn.stream;
  if (path === '/hello') { s.write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n'); return; }
  if (path === '/body') {
    const p = bodyParams(params);
    const t0 = now();
    s.write(`HTTP/1.1 200 OK\r\nContent-Length: ${p.n}\r\n\r\n`);
    const w = {
      write: (buf, cb) => s.write(buf, cb),
      drain: () => new Promise((res) => {
        const d = () => { s.off('close', c); res('drain'); };
        const c = () => { s.off('drain', d); res('close'); };
        s.once('drain', d);
        s.once('close', c);
      }),
      gone: () => s.destroyed,
    };
    const rec = await pump(w, p.data, p.k, p.gap, p.delay);
    if (!rec.aborted && !s.destroyed) await new Promise((res) => { s.once('close', res); rec.lastP.then(res); });
    ev('body', conn.face, conn.port, `proto=h1 ${bodyRest(tag, p, rec, t0)}`);
    return;
  }
  s.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n');
}

// ---------------------------------------------------------------- HTTP/2
const h2srv = http2.createServer();
const meta = new WeakMap();
let pending = null;
h2srv.on('session', (session) => {
  const m = pending || { face: '?', port: '?' };
  meta.set(session, m);
  sessions.add(session);
  ev('session', m.face, m.port, `alpn=${session.alpnProtocol}`);
  session.on('close', () => sessions.delete(session));
  session.on('error', (e) => ev('session-error', m.face, m.port, `code=${e.code} ${escStr(e.message, 200)}`));
  session.on('goaway', (code) => ev('goaway', m.face, m.port, `received from the client, code=${code}`));
});
function h2Over(sock, face, port) {
  pending = { face, port };
  h2srv.emit('connection', sock);
  pending = null;
}
h2srv.on('stream', (stream, headers) => {
  stream.on('error', () => {});
  const m = meta.get(stream.session) || { face: '?', port: '?' };
  const { path, params } = parseTarget(headers[':path'] || '');
  const tag = params.get('tag') || '-';
  const hs = Object.entries(headers).map(([k, v]) => `${k}: ${v}`);
  ev('req', m.face, m.port, `proto=h2 stream=${stream.id} tag=${tag} ${headers[':method']} ${path} headers=${escStr(hs.join(' | '), 1024)}`);
  inflight++;
  dispatchH2(stream, m, path, params, tag).catch((err) => ev('error', m.face, m.port, String(err))).finally(() => { inflight--; });
});

async function dispatchH2(stream, m, path, params, tag) {
  if (path === '/hello') {
    stream.respond({ ':status': 200, 'content-length': '6' });
    await new Promise((res) => { stream.once('close', res); stream.end('hello\n'); });
    return;
  }
  if (path === '/body') {
    const p = bodyParams(params);
    const t0 = now();
    stream.respond({ ':status': 200, 'content-length': String(p.n) });
    const w = {
      write: (buf, cb) => stream.write(buf, cb),
      drain: () => new Promise((res) => {
        const d = () => { stream.off('close', c); res('drain'); };
        const c = () => { stream.off('drain', d); res('close'); };
        stream.once('drain', d);
        stream.once('close', c);
      }),
      gone: () => stream.destroyed || stream.closed,
    };
    const rec = await pump(w, p.data, p.k, p.gap, p.delay);
    if (!rec.aborted && !stream.destroyed) {
      await new Promise((res) => { stream.once('close', res); stream.end(() => { rec.flushed = now(); res(); }); });
    }
    ev('body', m.face, m.port, `proto=h2 stream=${stream.id} ${bodyRest(tag, p, rec, t0)}`);
    return;
  }
  stream.respond({ ':status': 404, 'content-length': '0' });
  stream.end();
}

// ---------------------------------------------------------------- faces
const h1 = net.createServer((tcp) => {
  track(tcp);
  tcp.setNoDelay(true);
  ev('accept', 'h1', tcp.remotePort);
  serveH1(tcp, 'h1', tcp.remotePort);
});

function tlsFace(face, choose) {
  const srv = tls.createServer({
    cert,
    key,
    // `this` is the TLS socket (Node's callALPNCallback); measured below by
    // the port it names, which must match the accept line's.
    ALPNCallback: function alpn({ protocols }) {
      const chose = choose(protocols);
      const port = this && this.remotePort !== undefined ? this.remotePort : '?';
      if (this) this.alpnSeen = true;
      ev('alpn', face, port, `offered=${protocols.join(',') || '(empty)'} n=${protocols.length} chose=${chose === undefined ? 'refused' : chose}`);
      return chose;
    },
  });
  srv.on('connection', (tcp) => {
    const port = tcp.remotePort;
    track(tcp);
    ev('accept', face, port);
    tcp.on('close', () => ev('close', face, port, 'tcp'));
  });
  srv.on('tlsClientError', (err, ts) => ev('tls-error', face, ts && ts.remotePort, `code=${err.code} ${escStr(err.message, 200)}`));
  srv.on('secureConnection', (ts) => {
    const port = ts.remotePort;
    ts.on('error', () => {});
    ev('tls', face, port, `alpn=${ts.alpnProtocol} callback_ran=${ts.alpnSeen ? 1 : 0} protocol=${ts.getProtocol()}`);
    if (ts.alpnProtocol === 'h2') h2Over(ts, face, port);
    else { ts.setNoDelay(true); serveH1(ts, face, port); }
  });
  return srv;
}
const tlsh2 = tlsFace('tlsh2', (ps) => (ps.includes('h2') ? 'h2' : ps.includes('http/1.1') ? 'http/1.1' : undefined));
const tlsh1 = tlsFace('tlsh1', (ps) => (ps.includes('http/1.1') ? 'http/1.1' : undefined));

const h2c = net.createServer((c) => {
  track(c);
  const port = c.remotePort;
  ev('accept', 'h2c', port);
  c.on('close', () => ev('close', 'h2c', port, 'h2c'));
  c.once('data', (d) => {
    c.pause();
    ev('first', 'h2c', port, `bytes=${d.length} ${escStr(d.toString('latin1'), 512)}`);
    c.unshift(d);
    h2Over(c, 'h2c', port);
  });
});

// ---------------------------------------------------------------- control
function summary(after, face) {
  const es = events.filter((e) => e.seq > after && e.face === face);
  const accepts = es.filter((e) => e.kind === 'accept').map((e) => e.port);
  const reqs = es.filter((e) => e.kind === 'req').map((e) => e.port);
  const rc = [...new Set(reqs)];
  return `accepts=${accepts.length} ports=${accepts.join(',') || '-'} req_conns=${rc.length} [${rc.join(',')}] reqs=${reqs.length}`;
}
const ctl = net.createServer((s) => {
  s.on('error', () => {});
  let buf = '';
  let answered = false;
  s.on('data', async (d) => {
    buf += d.toString('latin1');
    if (answered || buf.indexOf('\r\n\r\n') < 0) return;
    answered = true;
    const target = buf.split(' ')[1] || '/';
    const { path, params } = parseTarget(target);
    let body;
    if (path === '/seq') body = `${seq}\n`;
    else if (path === '/events') {
      const after = Number(params.get('after') || '0');
      const t = now();
      while (inflight > 0 && now() - t < 3000) await sleep(5);
      const ls = events.filter((e) => e.seq > after).map((e) => e.line);
      if (inflight > 0) ls.push(`ev - ${inflight} request(s) still open after 3 s`);
      body = ls.length ? `${ls.join('\n')}\n` : '';
    } else if (path === '/summary') {
      const t = now();
      while (inflight > 0 && now() - t < 3000) await sleep(5);
      body = `${summary(Number(params.get('after') || '0'), params.get('face') || '')}\n`;
    } else body = 'no such control path\n';
    s.end(`HTTP/1.0 200 OK\r\nContent-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
  });
});

// W-sibling's 80 MiB body, built before the ports are printed: built on
// first use, it held the event loop ~110 ms as the first variant's heads
// were due (measured; M6's W-sibling, the same server code, shows it too).
pattern(83886080);
const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const servers = [ctl, h1, tlsh2, tlsh1, h2c];
const ports = [];
for (const s of servers) ports.push(await listen(s));
process.stdout.write(`ctl=${ports[0]} h1=${ports[1]} tlsh2=${ports[2]} tlsh1=${ports[3]} h2c=${ports[4]}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const s of servers) s.close();
  process.exit(0);
});
