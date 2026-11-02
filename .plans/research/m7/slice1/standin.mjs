// M7 slice 1's stand-in (2026-11-02), Node's standard library alone, for the
// twins tests/origin.mjs has no face for: Alt-Svc, a face that offers both
// h2 and http/1.1, and a status line that is not HTTP's.
//
//   node standin.mjs PKI-DIR
//
// PKI-DIR is tests/make-test-pki.sh's: every TLS face serves its good leaf
// (localhost, 127.0.0.1, ::1). Each face listens on 127.0.0.1, port 0. Once
// all listen it writes one line on stdout, a flat JSON object of the faces,
// each "127.0.0.1:PORT", and exits 0 when its stdin ends.
//
// The faces:
//   alt1   node:https, ALPN http/1.1 alone. Every request: 200,
//          Alt-Svc: h2=":ALT2"; ma=3600, ALT2 being alt2's port, and the
//          body "face=alt1 conn=N version=V alpn=A path=P host=H\n". A path
//          that begins /slow has its head flushed, and its body 500 ms on.
//   alt1h  node:http, plaintext: as alt1, the same Alt-Svc header naming
//          alt2, "face=alt1h ...".
//   alt2   node:http2, secure, ALPN h2 alone, no HTTP/1.1: "face=alt2 conn=N
//          version=2.0 alpn=h2 path=P authority=H\n". A client that does not
//          choose h2 has its socket destroyed.
//   both   node:http2, secure, allowHTTP1, ALPN h2 then http/1.1: "face=both
//          conn=N version=V alpn=A path=P host=H\n", V the request's HTTP
//          version as Node read it, A the ALPN chosen, or none.
//   icy    node:net: reads a request head, then writes "ICY 200 OK",
//          Content-Length: 4 and Connection: close, then "icy\n", and ends.
//   ctl    node:http, plaintext, never counted: GET /events answers
//          "alt1 T/L/S alt1h T/L/S alt2 T/L/S both T/L/S icy T/L/S\n", each
//          face's TCP connections accepted (T), TLS handshakes completed
//          (L, 0 on a plaintext face) and requests answered (S) so far.
//   closed a port no face holds: listened on, then closed, before the
//          announcement.
//
// conn=N is the connection's number among its face's, from 1: on a TLS
// face, among its completed handshakes. Nothing is written to stderr but a
// fatal error, which exits 1.

import { readFileSync } from 'node:fs';
import http from 'node:http';
import http2 from 'node:http2';
import https from 'node:https';
import net from 'node:net';
import process from 'node:process';

const HOST = '127.0.0.1';
const fatal = (what, err) => {
  process.stderr.write(`standin: ${what}: ${(err && err.stack) || err}\n`);
  process.exit(1);
};
process.on('uncaughtException', (err) => fatal('uncaught exception', err));
process.on('unhandledRejection', (err) => fatal('unhandled rejection', err));

if (process.argv.length !== 3) fatal('usage', 'node standin.mjs PKI-DIR');
const pki = process.argv[2];
const leaf = { cert: readFileSync(`${pki}/good.pem`), key: readFileSync(`${pki}/good.key`) };

const sockets = new Set();
const sessions = new Set();
const counts = {};
function face(name, server, secure) {
  counts[name] = { tcp: 0, tls: 0, served: 0 };
  server.on('connection', (socket) => {
    counts[name].tcp += 1;
    if (!secure) socket.connNumber = counts[name].tcp;
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => socket.destroy());
  });
  if (secure) {
    server.on('secureConnection', (socket) => {
      counts[name].tls += 1;
      socket.connNumber = counts[name].tls;
      sockets.add(socket);
      socket.on('close', () => sockets.delete(socket));
    });
  }
  server.on('error', (err) => fatal(`face ${name}`, err));
  return server;
}

const ports = {};
const altSvc = () => `h2=":${ports.alt2}"; ma=3600`;

// connOf: the connection number of SOCKET, a request's socket or an HTTP/2
// session's: the TLS connection's number on a TLS face, the TCP one's on a
// plaintext face.
const connOf = (socket) => (socket && socket.connNumber !== undefined ? socket.connNumber : '?');

function h1Answer(name, withAltSvc) {
  return (req, res) => {
    req.on('data', () => {});
    req.on('end', () => {
      counts[name].served += 1;
      const alpn = req.socket.alpnProtocol || 'none';
      const body = Buffer.from(`face=${name} conn=${connOf(req.socket)} version=${req.httpVersion} alpn=${alpn} path=${req.url} host=${req.headers.host}\n`, 'latin1');
      const headers = ['Content-Length', String(body.length)];
      if (withAltSvc) headers.push('Alt-Svc', altSvc());
      res.sendDate = false;
      res.writeHead(200, headers);
      if (req.url.startsWith('/slow')) {
        res.flushHeaders();
        setTimeout(() => { if (!res.destroyed) res.end(body); }, 500);
      } else {
        res.end(body);
      }
    });
  };
}

const alt1 = face('alt1', https.createServer({ ...leaf, ALPNProtocols: ['http/1.1'] }, h1Answer('alt1', true)), true);
alt1.on('tlsClientError', (err, socket) => socket.destroy());
const alt1h = face('alt1h', http.createServer(h1Answer('alt1h', true)), false);

function trackSession(session) {
  sessions.add(session);
  session.on('close', () => sessions.delete(session));
  session.on('error', () => session.destroy());
}

const alt2 = face('alt2', http2.createSecureServer({ ...leaf, allowHTTP1: false }), true);
alt2.on('session', trackSession);
alt2.on('sessionError', (err, session) => session.destroy());
alt2.on('tlsClientError', (err, socket) => socket.destroy());
alt2.on('unknownProtocol', (socket) => socket.destroy());
alt2.on('stream', (stream, headers) => {
  stream.on('error', () => stream.destroy());
  stream.on('data', () => {});
  stream.on('end', () => {
    counts.alt2.served += 1;
    const conn = connOf(stream.session.socket);
    const body = Buffer.from(`face=alt2 conn=${conn} version=2.0 alpn=${stream.session.alpnProtocol} path=${headers[':path']} authority=${headers[':authority']}\n`, 'latin1');
    if (stream.destroyed) return;
    stream.respond({ ':status': 200, 'content-length': String(body.length) }, { sendDate: false });
    stream.end(body);
  });
});

const both = face('both', http2.createSecureServer({ ...leaf, allowHTTP1: true }, (req, res) => {
  req.on('data', () => {});
  req.on('end', () => {
    counts.both.served += 1;
    const v2 = req.httpVersion === '2.0';
    const socket = v2 ? req.stream.session.socket : req.socket;
    const alpn = (v2 ? req.stream.session.alpnProtocol : req.socket.alpnProtocol) || 'none';
    const host = v2 ? req.headers[':authority'] : req.headers.host;
    const body = Buffer.from(`face=both conn=${connOf(socket)} version=${req.httpVersion} alpn=${alpn} path=${req.url} host=${host}\n`, 'latin1');
    if (v2) {
      res.writeHead(200, { 'content-length': String(body.length) });
    } else {
      res.sendDate = false;
      res.writeHead(200, ['Content-Length', String(body.length)]);
    }
    res.end(body);
  });
}), true);
both.on('session', trackSession);
both.on('sessionError', (err, session) => session.destroy());
both.on('tlsClientError', (err, socket) => socket.destroy());

const icy = face('icy', net.createServer((socket) => {
  let head = Buffer.alloc(0);
  socket.on('data', (chunk) => {
    if (head === null) return;
    head = Buffer.concat([head, chunk]);
    if (head.indexOf('\r\n\r\n') >= 0 || head.length > 65536) {
      head = null;
      counts.icy.served += 1;
      socket.end('ICY 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nicy\n');
    }
  });
}), false);

const ctl = http.createServer((req, res) => {
  const text = req.url === '/events'
    ? `${['alt1', 'alt1h', 'alt2', 'both', 'icy'].map((n) => `${n} ${counts[n].tcp}/${counts[n].tls}/${counts[n].served}`).join(' ')}\n`
    : 'not found\n';
  res.sendDate = false;
  res.writeHead(req.url === '/events' ? 200 : 404, ['Content-Length', String(Buffer.byteLength(text))]);
  res.end(text);
});
ctl.on('connection', (socket) => {
  sockets.add(socket);
  socket.on('close', () => sockets.delete(socket));
  socket.on('error', () => socket.destroy());
});
ctl.on('error', (err) => fatal('face ctl', err));

const servers = [['alt1', alt1], ['alt1h', alt1h], ['alt2', alt2], ['both', both], ['icy', icy], ['ctl', ctl]];
await Promise.all(servers.map(([, s]) => new Promise((resolve) => s.listen(0, HOST, resolve))));
for (const [name, s] of servers) ports[name] = s.address().port;
const closer = net.createServer();
await new Promise((resolve) => closer.listen(0, HOST, resolve));
const closedPort = closer.address().port;
await new Promise((resolve) => closer.close(resolve));
const announcement = { ...Object.fromEntries(servers.map(([n, s]) => [n, `${HOST}:${s.address().port}`])), closed: `${HOST}:${closedPort}` };
process.stdout.write(`${JSON.stringify(announcement)}\n`, () => {
  process.stdin.on('data', () => {});
  process.stdin.on('end', () => {
    let open = servers.length;
    for (const [, s] of servers) s.close(() => { open -= 1; if (open === 0) process.exit(0); });
    for (const session of sessions) session.destroy();
    for (const socket of sockets) socket.destroy();
  });
});
