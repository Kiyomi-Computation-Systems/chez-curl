// M4 slice 3's measurements: an origin over plaintext and over TLS, and an
// https:// proxy, all on 127.0.0.1.
//
//   node servers.mjs PKI LOG
//
// PKI is a directory tests/make-test-pki.sh filled. The TLS origin and the
// proxy both serve its good leaf, for 127.0.0.1, which the run CA signed and
// no system store trusts. The origins answer every request 200 "origin" and
// 200 "origin-tls". The proxy answers every request 299 "proxy", and every
// CONNECT 403. It appends a line to LOG for each TLS handshake it completes,
// each one a client aborts (tlsClientError, with Node's message), each
// request, by its method and target, and each CONNECT. It announces one JSON
// line, {"origin":PORT,"origintls":PORT,"proxytls":PORT}, and exits 0 when
// its stdin ends.
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';

const [pki, log] = process.argv.slice(2);
if (!pki || !log) {
  process.stderr.write('usage: node servers.mjs PKI LOG\n');
  process.exit(2);
}
const leaf = {
  cert: fs.readFileSync(path.join(pki, 'good.pem')),
  key: fs.readFileSync(path.join(pki, 'good.key')),
};
const note = (line) => fs.appendFileSync(log, `${line}\n`);
const answer = (status, text) => (req, res) => {
  res.writeHead(status, { 'Content-Type': 'text/plain', 'Content-Length': text.length, Connection: 'close' });
  res.end(text);
};
const origin = http.createServer(answer(200, 'origin'));
const originTls = https.createServer(leaf, answer(200, 'origin-tls'));
const proxy = https.createServer(leaf, (req, res) => {
  note(`proxy ${req.method} ${req.url}`);
  answer(299, 'proxy')(req, res);
});
proxy.on('secureConnection', () => note('proxy handshake'));
proxy.on('tlsClientError', (e) => note(`proxy aborted handshake: ${e.code || ''} ${e.message}`.replace(/\s+/g, ' ')));
proxy.on('connect', (req, socket) => {
  note(`proxy CONNECT ${req.url}`);
  socket.end('HTTP/1.1 403 Probe\r\nContent-Length: 0\r\n\r\n');
});
const listen = (server) => new Promise((done) => server.listen(0, '127.0.0.1', () => done(server.address().port)));
const ports = { origin: await listen(origin), origintls: await listen(originTls), proxytls: await listen(proxy) };
process.stdout.write(`${JSON.stringify(ports)}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of [origin, originTls, proxy]) {
    s.close();
    s.closeAllConnections();
  }
  process.exit(0);
});
