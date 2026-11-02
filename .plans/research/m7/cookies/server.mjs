// M7's cookie probe server (2026-11-02; the M7 plan's measurements). Node 20
// or later, ESM, the standard library only. Run:
//   node server.mjs
// Listens on one port on 127.0.0.1 and on ::1 (libcurl 8.x tries ::1 first
// for localhost and *.localhost), writes one line on stdout:
//   port=PORT v4=127.0.0.1 v6=::1        or   v6=none(CODE)
// then serves until stdin ends.
//
// Plaintext HTTP/1.1 on node:net, keep-alive, every head written byte for
// byte, so a Set-Cookie may carry any bytes. Any path; the query says what
// to answer. Values marked HEX are the bytes in hexadecimal, so no URL
// decoding stands between the probe and the wire:
//   sc=HEX      (repeatable) one header line "Set-Cookie: " + the bytes
//   h=HEX       (repeatable) one whole header line, the bytes as they are
//   st=N        the status, default 200
//   loc=HEX     a Location header
//   delay=MS    wait before writing the answer
//   many=N&mname=P&msize=S[&mattr=HEX]
//               N more Set-Cookie lines, "P<i>=" + S bytes of 'v' + attr
//   tag=T       a label, unused but echoed in the request line
// The answer's body (text/plain, Content-Length) reports the request as it
// arrived:
//   req METHOD TARGET VERSION
//   remote ADDR conn=PORT
//   host "HOST HEADER VALUE"
//   cookie-headers N
//   cookie "WHOLE HEADER LINE"        one per Cookie header, in order
//   end
// Bytes outside 0x20..0x7e, and \ and ", are written \xHH.
import net from 'node:net';

const esc = (buf) => {
  let s = '';
  for (const b of buf) {
    if (b >= 0x20 && b <= 0x7e && b !== 0x5c && b !== 0x22) s += String.fromCharCode(b);
    else s += '\\x' + b.toString(16).padStart(2, '0');
  }
  return s;
};
const unhex = (s) => Buffer.from(s, 'hex');
const sleep = (n) => new Promise((r) => setTimeout(r, n));
const REASON = { 200: 'OK', 301: 'Moved Permanently', 302: 'Found', 303: 'See Other', 307: 'Temporary Redirect', 308: 'Permanent Redirect', 404: 'Not Found' };

function parseQuery(target) {
  const q = target.indexOf('?');
  const out = [];
  if (q < 0) return out;
  for (const kv of target.slice(q + 1).split('&')) {
    const e = kv.indexOf('=');
    out.push(e < 0 ? [kv, ''] : [kv.slice(0, e), kv.slice(e + 1)]);
  }
  return out;
}

async function answer(sock, head, remote, rport) {
  // head: a Buffer, the request's head without its final CRLF CRLF.
  const lines = [];
  let start = 0;
  for (let i = 0; i + 1 < head.length; i++) {
    if (head[i] === 0x0d && head[i + 1] === 0x0a) { lines.push(head.subarray(start, i)); start = i + 2; i++; }
  }
  lines.push(head.subarray(start));
  const reqline = lines[0].toString('latin1');
  const [method, target, version] = reqline.split(' ');
  let host = null;
  const cookies = [];
  for (const l of lines.slice(1)) {
    const c = l.indexOf(0x3a);
    const name = (c < 0 ? l : l.subarray(0, c)).toString('latin1').toLowerCase();
    if (name === 'host') host = l.subarray(c + 1).toString('latin1').trim();
    if (name === 'cookie') cookies.push(l);
  }
  const params = parseQuery(target || '');
  let status = 200, delay = 0, many = 0, mname = 'm', msize = 1, mattr = Buffer.alloc(0);
  const extra = [];
  for (const [k, v] of params) {
    if (k === 'sc') extra.push(Buffer.concat([Buffer.from('Set-Cookie: '), unhex(v)]));
    else if (k === 'h') extra.push(unhex(v));
    else if (k === 'st') status = Number(v);
    else if (k === 'loc') extra.push(Buffer.concat([Buffer.from('Location: '), unhex(v)]));
    else if (k === 'delay') delay = Number(v);
    else if (k === 'many') many = Number(v);
    else if (k === 'mname') mname = v;
    else if (k === 'msize') msize = Number(v);
    else if (k === 'mattr') mattr = unhex(v);
  }
  for (let i = 0; i < many; i++)
    extra.push(Buffer.concat([Buffer.from(`Set-Cookie: ${mname}${i}=${'v'.repeat(msize)}`), mattr]));
  let body = `req ${esc(Buffer.from(method || '', 'latin1'))} ${esc(Buffer.from(target || '', 'latin1'))} ${version}\n`;
  body += `remote ${remote} conn=${rport}\n`;
  body += `host "${host === null ? '(none)' : esc(Buffer.from(host, 'latin1'))}"\n`;
  body += `cookie-headers ${cookies.length}\n`;
  for (const c of cookies) body += `cookie "${esc(c)}"\n`;
  body += 'end\n';
  const b = Buffer.from(body, 'latin1');
  const parts = [Buffer.from(`HTTP/1.1 ${status} ${REASON[status] || 'Status'}\r\nContent-Type: text/plain\r\nContent-Length: ${b.length}\r\n`)];
  for (const e of extra) parts.push(e, Buffer.from('\r\n'));
  parts.push(Buffer.from('\r\n'), b);
  if (delay > 0) await sleep(delay);
  if (!sock.destroyed) sock.write(Buffer.concat(parts));
}

function serve(sock) {
  sock.on('error', () => {});
  const remote = sock.remoteAddress, rport = sock.remotePort;
  let buf = Buffer.alloc(0);
  let chain = Promise.resolve();
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      const end = buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = buf.subarray(0, end);
      let rest = buf.subarray(end + 4);
      const m = /\r\ncontent-length:\s*(\d+)/i.exec(head.toString('latin1'));
      const n = m ? Number(m[1]) : 0;
      if (rest.length < n) return;
      rest = rest.subarray(n);
      buf = rest;
      chain = chain.then(() => answer(sock, head, remote, rport));
    }
  });
}

const s4 = net.createServer(serve);
const listen = (srv, port, addr) => new Promise((resolve) => {
  srv.once('error', (e) => resolve(e));
  srv.listen(port, addr, () => resolve(null));
});
let port = 0, v6 = 'none';
for (let attempt = 0; attempt < 20; attempt++) {
  const e4 = await listen(s4, 0, '127.0.0.1');
  if (e4) { console.error(`listen 127.0.0.1: ${e4.code}`); process.exit(1); }
  port = s4.address().port;
  const s6 = net.createServer(serve);
  const e6 = await listen(s6, port, '::1');
  if (!e6) { v6 = '::1'; break; }
  if (e6.code === 'EADDRINUSE') { await new Promise((r) => s4.close(r)); continue; }
  v6 = `none(${e6.code})`;
  break;
}
process.stdout.write(`port=${port} v4=127.0.0.1 v6=${v6}\n`);
process.stdin.resume();
process.stdin.on('end', () => process.exit(0));
