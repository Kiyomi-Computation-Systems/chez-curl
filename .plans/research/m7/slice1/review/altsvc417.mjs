// Review probe: does the hatch's ALTSVC_CTRL alone, with no ALTSVC file,
// move the second request of ONE transfer (a 417 resend) to an alternative?
//   node altsvc417.mjs PKI-DIR
// Faces, each 127.0.0.1, port 0:
//   a  https, http/1.1. A request with Expect: 100-continue gets 417 with
//      Alt-Svc naming c (h1) for /to-c, d (h2) for /to-d; one without
//      gets 200 "face=a ...".
//   c  https, http/1.1: 200 "face=c ...".
//   d  http2 secure, h2 alone: 200 "face=d ...".
// Writes one JSON line of ports, exits when stdin ends.
import { readFileSync } from 'node:fs';
import https from 'node:https';
import http2 from 'node:http2';
import process from 'node:process';
import tls from 'node:tls';

const pki = process.argv[2];
const leaf = { cert: readFileSync(`${pki}/good.pem`), key: readFileSync(`${pki}/good.key`) };
let pc = 0, pd = 0;
const reply = (name) => (req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks).toString('latin1');
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end(`face=${name} version=${req.httpVersion} method=${req.method} path=${req.url} body=${body}\n`);
  });
};
const a = tls.createServer({ ...leaf, ALPNProtocols: ['http/1.1'] }, (socket) => {
  let buf = Buffer.alloc(0);
  let refused = 0;
  socket.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      const end = buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = buf.subarray(0, end).toString('latin1');
      const lines = head.split('\r\n');
      const expect = lines.some((l) => /^expect:\s*100-continue/i.test(l));
      const cl = lines.map((l) => /^content-length:\s*(\d+)/i.exec(l)).find((m) => m);
      const len = cl ? Number(cl[1]) : 0;
      if (expect && refused === 0) {
        refused += 1;
        const alt = lines[0].includes('/to-d') ? `h2=":${pd}"; ma=3600` : `h1=":${pc}"; ma=3600`;
        buf = buf.subarray(end + 4);
        socket.write(`HTTP/1.1 417 Expectation Failed\r\nAlt-Svc: ${alt}\r\nContent-Length: 0\r\n\r\n`);
        continue;
      }
      if (buf.length < end + 4 + len) return;
      buf = buf.subarray(end + 4 + len);
      const body = `face=a ${lines[0]}\n`;
      socket.write(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n\r\n${body}`);
    }
  });
  socket.on('error', () => socket.destroy());
});
const c = https.createServer({ ...leaf, ALPNProtocols: ['http/1.1'] }, reply('c'));
const d = http2.createSecureServer({ ...leaf, ALPNProtocols: ['h2'] }, reply('d'));
const listen = (s) => new Promise((ok) => s.listen(0, '127.0.0.1', () => ok(s.address().port)));
const [pa, pc0, pd0] = await Promise.all([listen(a), listen(c), listen(d)]);
pc = pc0; pd = pd0;
process.stdout.write(JSON.stringify({ a: pa, c: pc, d: pd }) + '\n');
process.stdin.resume();
process.stdin.on('end', () => process.exit(0));
