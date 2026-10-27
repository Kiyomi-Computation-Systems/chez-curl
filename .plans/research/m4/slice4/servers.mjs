// M4 slice 4's measurements: the servers, all on 127.0.0.1.
//
//   node servers.mjs PKI LOG SOCKET [ABSTRACT]
//
// PKI is a directory tests/make-test-pki.sh filled. It serves:
//   - capture, node:net, on a TCP port, on the Unix socket SOCKET, and, when
//     ABSTRACT is given, on the Linux abstract socket of that name: it reads
//     a request's head, up to the first CRLF CRLF, then the body its
//     Content-Length declares, or none, and answers 200 with one JSON line,
//     where it arrived ("tcp", "unix" or "abstract"), the head as Latin-1
//     text, and the body's length and Latin-1 text. A proxy request arrives here as any
//     other, so it stands in for an http:// proxy too;
//   - icy, node:net: to any request, "ICY 200 OK", a status line no HTTP
//     version starts, then a body, "icy";
//   - tls, node:https, with PKI's good leaf, for 127.0.0.1, which the run CA
//     signed: 200 "origin-tls".
// It appends a line to LOG for each request capture, icy and tls read, the
// head whole, its CR and LF escaped, and announces one JSON line,
// {"capture":PORT,"icy":PORT,"tls":PORT}. It exits 0 when its stdin ends.
import net from 'node:net';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';

const [pki, log, socketPath, abstractName] = process.argv.slice(2);
if (!pki || !log || !socketPath) {
  process.stderr.write('usage: node servers.mjs PKI LOG SOCKET\n');
  process.exit(2);
}
const note = (line) => fs.appendFileSync(log, `${line}\n`);
const escaped = (text) => text.replace(/\r/g, '\\r').replace(/\n/g, '\\n');

// reader : (Socket, Buffer head) -> void, (Socket, Buffer head, Buffer body)
// -> void: a connection's handler, which calls HEARD with a request's head as
// soon as it is read, then DONE once the body its Content-Length declares
// has arrived.
const reader = (heard, done) => (socket) => {
  let buffered = Buffer.alloc(0);
  let head = null;
  let need = 0;
  let finished = false;
  socket.on('error', () => socket.destroy());
  socket.on('data', (chunk) => {
    buffered = Buffer.concat([buffered, chunk]);
    if (head === null) {
      const end = buffered.indexOf('\r\n\r\n');
      if (end < 0) return;
      head = buffered.subarray(0, end + 4);
      buffered = buffered.subarray(end + 4);
      heard(socket, head);
      const length = /\r\ncontent-length:[ \t]*([0-9]+)\r\n/i.exec(head.toString('latin1'));
      need = length ? Number(length[1]) : 0;
    }
    if (!finished && buffered.length >= need) {
      finished = true;
      done(socket, head, buffered.subarray(0, need));
    }
  });
};

const capture = (via) => reader((socket, head) => {
  note(`capture ${via} ${escaped(head.toString('latin1'))}`);
}, (socket, head, body) => {
  const text = head.toString('latin1');
  if (body.length) note(`capture ${via} body ${escaped(body.toString('latin1'))}`);
  const json = JSON.stringify({ via, head: text, length: body.length, body: body.toString('latin1') });
  socket.end(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(json)}\r\nConnection: close\r\n\r\n${json}`);
});

const captureTcp = net.createServer(capture('tcp'));
const captureUnix = net.createServer(capture('unix'));
const captureAbstract = net.createServer(capture('abstract'));
const icy = net.createServer(reader((socket, head) => {
  note(`icy ${escaped(head.toString('latin1'))}`);
}, (socket) => {
  socket.end('ICY 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nicy');
}));
const tls = https.createServer({
  cert: fs.readFileSync(path.join(pki, 'good.pem')),
  key: fs.readFileSync(path.join(pki, 'good.key')),
}, (req, res) => {
  note(`tls ${req.method} ${req.url}`);
  res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': 10, Connection: 'close' });
  res.end('origin-tls');
});

const listen = (server) => new Promise((done) => server.listen(0, '127.0.0.1', () => done(server.address().port)));
const ports = { capture: await listen(captureTcp), icy: await listen(icy), tls: await listen(tls) };
await new Promise((done) => captureUnix.listen(socketPath, done));
if (abstractName) await new Promise((done) => captureAbstract.listen(`\0${abstractName}`, done));
process.stdout.write(`${JSON.stringify(ports)}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of [captureTcp, captureUnix, ...(abstractName ? [captureAbstract] : []), icy, tls]) {
    s.close();
    if (s.closeAllConnections) s.closeAllConnections();
  }
  process.exit(0);
});
