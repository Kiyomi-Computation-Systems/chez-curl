// M5 slice 3's retry probe server (2026-10-28; the M5 plan, section 6.1).
// node:net only, so each failure goes out as written. Run with the PKI
// directory tests/make-test-pki.sh made:
//   node server.mjs PKI
// Writes one line on stdout, the ports, then serves until stdin ends:
//   raw=PORT tls=PORT h2=PORT stall=PORT refused=PORT
//
// raw  plaintext HTTP/1.1; tls  the same in TLS, ALPN http/1.1 alone;
// h2   HTTP/2 in TLS, ALPN h2 alone, node:http2's secure server, which
//      hands over each TCP socket before its TLS, kept for a reset;
// stall accepts and never answers, so a TLS handshake stalls; refused is a
// port that was listened on, then closed.
//
// A request's last path segment names its scenario. On raw and tls, the
// request is read whole, its head and a Content-Length body; on h2, its
// stream to its end. Then:
//   ok                      200, Content-Length: 3, "ok\n"
//   close-before-response   the TCP connection ends, a FIN, nothing written
//   reset-before-response   the TCP connection is reset, nothing written
//   reset-after-head        a 200 head, Content-Length: 10, and "hello",
//                           then, 50 ms on, a reset
//   stall-before-head       nothing, ever
//   rst-stream (h2)         RST_STREAM, REFUSED_STREAM
//   goaway (h2)             GOAWAY, NO_ERROR, last stream 0, then the
//                           session closes
// A reset resets the TCP socket, under the TLS one where there is one.
//
// Each request read whole is counted, by its face, method and scenario,
// and logged on stderr as it comes: "request FACE METHOD SCENARIO #N". So
// a resend libcurl makes on its own shows as a count above 1 (the slice's
// review asked for it, 2026-10-28).
import { readFileSync } from 'node:fs';
import http2 from 'node:http2';
import net from 'node:net';
import tls from 'node:tls';

const pki = process.argv[2];
const cert = readFileSync(`${pki}/good.pem`);
const key = readFileSync(`${pki}/good.key`);
const sockets = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };

const scenario = (target) => (target || '/').split('?')[0].split('/').pop();
const counts = new Map();
const count = (face, method, name) => {
  const k = `${face} ${method} ${name}`;
  const n = (counts.get(k) || 0) + 1;
  counts.set(k, n);
  process.stderr.write(`request ${k} #${n}\n`);
};

// playRaw: STREAM, the socket HTTP/1.1 goes over, TCP, the one under it;
// FACE names it in the count.
function playRaw(stream, tcp, face) {
  let buf = Buffer.alloc(0);
  let need = -1;
  let name = null;
  let method = null;
  stream.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    if (need < 0) {
      const end = buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = buf.toString('latin1', 0, end);
      name = scenario(head.split('\r\n')[0].split(' ')[1]);
      method = head.split(' ')[0];
      const m = /\r\ncontent-length:\s*(\d+)/i.exec(head);
      need = end + 4 + (m ? Number(m[1]) : 0);
    }
    if (buf.length < need) return;
    stream.removeAllListeners('data');
    count(face, method, name);
    switch (name) {
      case 'ok': stream.end('HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n'); break;
      case 'close-before-response': tcp.end(); break;
      case 'reset-before-response': tcp.resetAndDestroy(); break;
      case 'reset-after-head':
        stream.write('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello');
        setTimeout(() => tcp.resetAndDestroy(), 50);
        break;
      case 'stall-before-head': break;
      default: stream.end('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    }
  });
}

const raw = net.createServer((tcp) => { track(tcp); playRaw(tcp, tcp, 'http'); });

const tlsFace = net.createServer((tcp) => {
  track(tcp);
  const t = new tls.TLSSocket(tcp, { isServer: true, cert, key, ALPNProtocols: ['http/1.1'] });
  t.on('error', () => {});
  playRaw(t, tcp, 'tls');
});

// h2: node:http2's secure server. Its connection event hands over each TCP
// socket before TLS, kept by its remote port for a reset. A TLS socket
// built by hand and handed to a plaintext http2 server never answered
// (measured on 8.20.0's lane: every h2 transfer, ok among them, timed out).
const h2server = http2.createSecureServer({ cert, key, ALPNProtocols: ['h2'], allowHTTP1: false });
const tcpOf = new Map();
h2server.on('connection', (tcp) => { track(tcp); tcpOf.set(tcp.remotePort, tcp); });
h2server.on('tlsClientError', () => {});
h2server.on('session', (session) => session.on('error', () => {}));
h2server.on('stream', (stream, headers) => {
  stream.on('error', () => {});
  const name = scenario(headers[':path']);
  const tcp = tcpOf.get(stream.session.socket.remotePort);
  stream.resume();
  stream.on('end', () => {
    count('h2', headers[':method'], name);
    switch (name) {
      case 'ok': stream.respond({ ':status': 200, 'content-length': '3' }); stream.end('ok\n'); break;
      case 'close-before-response': tcp.end(); break;
      case 'reset-before-response': tcp.resetAndDestroy(); break;
      case 'reset-after-head':
        stream.respond({ ':status': 200, 'content-length': '10' });
        stream.write('hello');
        setTimeout(() => tcp.resetAndDestroy(), 50);
        break;
      case 'stall-before-head': break;
      case 'rst-stream': stream.close(http2.constants.NGHTTP2_REFUSED_STREAM); break;
      case 'goaway':
        stream.session.goaway(http2.constants.NGHTTP2_NO_ERROR, 0);
        setTimeout(() => stream.session.destroy(), 50);
        break;
      default: stream.respond({ ':status': 404, 'content-length': '0' }); stream.end();
    }
  });
});
const h2 = h2server;

const stall = net.createServer((tcp) => track(tcp));

const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const refusedPort = await new Promise((resolve) => {
  const s = net.createServer();
  s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
});
const ports = [await listen(raw), await listen(tlsFace), await listen(h2), await listen(stall)];
process.stdout.write(`raw=${ports[0]} tls=${ports[1]} h2=${ports[2]} stall=${ports[3]} refused=${refusedPort}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of sockets) s.destroy();
  for (const s of [raw, tlsFace, h2, stall]) s.close();
  process.exit(0);
});
