// M7 slice 4's stand-in (2026-11-03; the M7 plan, section 6.3): origins for
// the cookie jar's measurement, adapted from ../cookies/server.mjs and
// ../slice3/standin.mjs. Node 20 or later, ESM, the standard library only:
//   node standin.mjs PKI
//   node standin.mjs --selftest
// PKI is a directory tests/make-test-pki.sh filled. It writes one line on
// stdout, every face's port, NAME=PORT, and where each listens, then serves
// until stdin ends.
//
// Faces:
//   o     plaintext HTTP/1.1 on 127.0.0.1 and ::1, one port (o6= says
//         whether ::1 was bound)
//   v4    plaintext HTTP/1.1 on 127.0.0.1 alone
//   v6    plaintext HTTP/1.1 on ::1 alone, or none(CODE)
//   h2    plaintext HTTP/2 by prior knowledge (node:http2) on 127.0.0.1 and
//         ::1, one port
//   tls   HTTP/1.1 on 127.0.0.1 and ::1, one port: a connection whose first
//         byte is 0x16 is TLS (good.pem, ALPN http/1.1), any other
//         plaintext, so an http:// URL that HSTS upgrades lands here too
//
// The HTTP/1.1 faces parse requests themselves on node:net and keep each
// connection alive; a body is read by Content-Length. The query says what
// to answer; HEX values are bytes in hexadecimal, so no URL decoding stands
// between the program and the wire:
//   tag=T        the case's label: every request carrying it is logged
//   sc=HEX       (repeatable) a header line "Set-Cookie: " + the bytes,
//                on the answer, but a 401 or 417 of the routes below
//   h=HEX        (repeatable) a whole header line, the bytes as they are
//   st=N         the status, 200 by default
//   delay=MS     wait before answering
//   ch=digest    401 with a Digest challenge (MD5, qop=auth) unless the
//                request's Authorization is valid for ouser / opass;
//                sc401=HEX lines go on the 401 alone
//   e417=1       the tag's first request carrying Expect: 100-continue gets
//                417 at once, with the sc417=HEX lines, the connection kept
//                and its body never read; libcurl resends it on the same
//                connection, and that one, Expect or not, is read and
//                answered as any other
//   of=TAG       the answer's body is TAG's report, and this request is
//                logged under no tag: a poll of whether TAG's request came
// Any other request with Expect: 100-continue gets 100 Continue first.
// The HTTP/2 face takes tag, sc (values node:http2 accepts), st and delay.
//
// An answer's body (text/plain) reports every request the tag has seen,
// on any face, oldest first, then "end":
//   req #N face=F conn=C stream=S addr=v4|v6 scheme=http|https "REQUEST LINE"
//   host "VALUE"                 each Host header
//   authority "VALUE"            HTTP/2: each :authority field
//   expect "VALUE"               each Expect header
//   auth "SCHEME" VERDICT        each Authorization, its scheme and Digest's
//                                verdict
//   cookie-headers N             HTTP/1.1: the Cookie headers, any case
//   cookie "WHOLE HEADER LINE"   one per Cookie header, in order
//   cookie-fields N              HTTP/2: the cookie fields, as received
//   cookie "VALUE"               one per field, in order
//   answer STATUS                what the face wrote
//   unterminated head bytes=N last="BYTES"
//                                an HTTP/1.1 connection that closed holding
//                                bytes of a head with no blank line after
//                                it: they are reported, as a request's are,
//                                under the tag their request line names,
//                                which /poll?of=TAG then reads
// Bytes outside 0x20..0x7e, and \ and ", are written \xHH: a report holds
// every byte the header held, and no other.
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import net from 'node:net';
import tls from 'node:tls';
import http2 from 'node:http2';
import { Duplex } from 'node:stream';

// ---------------------------------------------------------------- bytes
function esc(buf) {
  let o = '';
  for (const c of buf) {
    if (c >= 0x20 && c <= 0x7e && c !== 0x5c && c !== 0x22) o += String.fromCharCode(c);
    else o += `\\x${c.toString(16).padStart(2, '0')}`;
  }
  return o;
}
const escs = (s) => esc(Buffer.from(s, 'latin1'));
const unhex = (s) => Buffer.from(s, 'hex');
const sleep = (n) => new Promise((r) => setTimeout(r, n));
const REASON = { 100: 'Continue', 200: 'OK', 302: 'Found', 401: 'Unauthorized', 404: 'Not Found', 417: 'Expectation Failed' };

// unesc: a report's escaped text back to its bytes.
function unesc(s) {
  const out = [];
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && s[i + 1] === 'x') { out.push(parseInt(s.slice(i + 2, i + 4), 16)); i += 3; }
    else out.push(s.charCodeAt(i));
  }
  return Buffer.from(out);
}

// ---------------------------------------------------------------- the log
const tagged = new Map(); // tag -> [report lines of each request]
let seq = 0;
function logged(tag, lines) {
  if (!tag) return;
  if (!tagged.has(tag)) tagged.set(tag, []);
  tagged.get(tag).push(lines);
}
function reportOf(tag) {
  const blocks = tagged.get(tag) || [];
  return blocks.map((b) => b.join('\n')).join('\n') + (blocks.length ? '\n' : '') + 'end\n';
}
function params(target) {
  const out = [];
  const q = target.indexOf('?');
  if (q < 0) return out;
  for (const kv of target.slice(q + 1).split('&')) {
    const e = kv.indexOf('=');
    out.push(e < 0 ? [kv, ''] : [kv.slice(0, e), kv.slice(e + 1)]);
  }
  return out;
}
const one = (ps, k) => { for (const [a, b] of ps) if (a === k) return b; return null; };
const all = (ps, k) => ps.filter(([a]) => a === k).map(([, b]) => b);
const family = (addr) => (addr && addr.includes(':') && !addr.startsWith('::ffff:') ? 'v6' : 'v4');

// ---------------------------------------------------------------- Digest
const nonces = new Set();
const md5 = (...parts) => createHash('md5').update(Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : Buffer.from(p, 'latin1'))))).digest('hex');
function parseDigest(s) {
  const out = {};
  const re = /([A-Za-z0-9_*-]+)\s*=\s*("((?:[^"\\]|\\.)*)"|[^,\s]*)/g;
  let m;
  while ((m = re.exec(s))) out[m[1].toLowerCase()] = m[3] !== undefined ? m[3].replace(/\\(.)/g, '$1') : m[2];
  return out;
}
function judgeDigest(value, method) {
  const sp = value.indexOf(' ');
  const scheme = (sp < 0 ? value : value.slice(0, sp)).toLowerCase();
  if (scheme !== 'digest') return [false, scheme, 'not-digest'];
  const p = parseDigest(value.slice(sp + 1));
  if (!nonces.has(p.nonce)) return [false, scheme, 'unknown-nonce'];
  if (p.username !== 'ouser') return [false, scheme, 'no-such-user'];
  const ha1 = md5('ouser:', p.realm || '', ':opass');
  const ha2 = md5(`${method}:${p.uri || ''}`);
  const exp = p.qop ? md5(`${ha1}:${p.nonce}:${p.nc}:${p.cnonce}:${p.qop}:${ha2}`) : md5(`${ha1}:${p.nonce}:${ha2}`);
  return exp === (p.response || '').toLowerCase() ? [true, scheme, 'valid'] : [false, scheme, 'wrong-response'];
}

// ---------------------------------------------------------------- HTTP/1.1
let connSeq = 0;
const refused417 = new Set();
// serve: one HTTP/1.1 connection of FACE over SOCK, SCHEME http or https,
// from ADDR.
function serve(face, sock, scheme, addr) {
  const conn = ++connSeq;
  sock.on('error', () => {});
  let buf = Buffer.alloc(0);
  let continued = false;
  let busy = false;
  const queue = [];
  const pump = async () => {
    if (busy) return;
    busy = true;
    while (queue.length) { const job = queue.shift(); await job(); }
    busy = false;
  };
  sock.on('close', () => { if (buf.length) unterminated(face, conn, scheme, addr, buf); });
  sock.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      const end = buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = buf.subarray(0, end);
      const lines = [];
      let start = 0;
      for (let i = 0; i + 1 < head.length; i++) {
        if (head[i] === 0x0d && head[i + 1] === 0x0a) { lines.push(head.subarray(start, i)); start = i + 2; i++; }
      }
      lines.push(head.subarray(start));
      const reqline = lines[0].toString('latin1');
      const target = reqline.split(' ')[1] || '';
      const ps = params(target);
      const fields = [];
      for (const l of lines.slice(1)) {
        const c = l.indexOf(0x3a);
        fields.push([(c < 0 ? l : l.subarray(0, c)).toString('latin1').toLowerCase(), l, c < 0 ? Buffer.alloc(0) : l.subarray(c + 1)]);
      }
      const values = (n) => fields.filter(([k]) => k === n).map(([, , v]) => v.toString('latin1').trim());
      const expects = values('expect').some((v) => /100-continue/i.test(v));
      const cl = values('content-length');
      const n = cl.length ? Number(cl[0]) : 0;
      let rest = buf.subarray(end + 4);
      const e417 = one(ps, 'e417') === '1' && !refused417.has(one(ps, 'tag'));
      if (expects && e417) refused417.add(one(ps, 'tag'));
      if (expects && e417) {
        // The body never comes: libcurl waits for a 100, gets the 417, and
        // resends on this connection.
        buf = rest;
        queue.push(() => answer(face, sock, conn, scheme, addr, reqline, ps, fields, 'e417'));
        pump();
        continue;
      }
      if (expects && !continued) {
        // Once per request: its head is parsed again at each chunk until
        // the body is whole.
        continued = true;
        sock.write('HTTP/1.1 100 Continue\r\n\r\n');
      }
      if (rest.length < n) return;
      continued = false;
      buf = rest.subarray(n);
      queue.push(() => answer(face, sock, conn, scheme, addr, reqline, ps, fields, null));
      pump();
    }
  });
}

// unterminated: BUF, the bytes a connection held as it closed, a head with
// no blank line, logged as its request's report, under its tag.
function unterminated(face, conn, scheme, addr, buf) {
  const lines = [];
  let start = 0;
  for (let i = 0; i + 1 < buf.length; i++) {
    if (buf[i] === 0x0d && buf[i + 1] === 0x0a) { lines.push(buf.subarray(start, i)); start = i + 2; i++; }
  }
  if (start < buf.length) lines.push(buf.subarray(start));
  const reqline = lines.length ? lines[0].toString('latin1') : '';
  const ps = params(reqline.split(' ')[1] || '');
  const out = [`req #${++seq} face=${face} conn=${conn} stream=- addr=${addr} scheme=${scheme} "${escs(reqline)}"`];
  const cookies = [];
  for (const l of lines.slice(1)) {
    const c = l.indexOf(0x3a);
    const name = (c < 0 ? l : l.subarray(0, c)).toString('latin1').toLowerCase();
    if (name === 'host') out.push(`host "${esc(Buffer.from(l.subarray(c + 1).toString('latin1').trim(), 'latin1'))}"`);
    if (name === 'cookie') cookies.push(l);
  }
  out.push(`cookie-headers ${cookies.length}`);
  for (const l of cookies) out.push(`cookie "${esc(l)}"`);
  out.push(`unterminated head bytes=${buf.length} last="${esc(buf.subarray(Math.max(0, buf.length - 40)))}"`);
  logged(one(ps, 'tag'), out);
}

async function answer(face, sock, conn, scheme, addr, reqline, ps, fields, mode) {
  const tag = one(ps, 'tag');
  const of = one(ps, 'of');
  if (of !== null) {
    const body = Buffer.from(reportOf(of), 'latin1');
    sock.write(Buffer.concat([Buffer.from(`HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ${body.length}\r\n\r\n`), body]));
    return;
  }
  const n = ++seq;
  const lines = [`req #${n} face=${face} conn=${conn} stream=- addr=${addr} scheme=${scheme} "${escs(reqline)}"`];
  for (const [k, , v] of fields) if (k === 'host') lines.push(`host "${esc(Buffer.from(v.toString('latin1').trim(), 'latin1'))}"`);
  for (const [k, , v] of fields) if (k === 'expect') lines.push(`expect "${esc(Buffer.from(v.toString('latin1').trim(), 'latin1'))}"`);
  const method = reqline.split(' ')[0];
  let digestOk = false;
  for (const [k, , v] of fields) {
    if (k !== 'authorization') continue;
    const [ok, s, verdict] = judgeDigest(v.toString('latin1').trim(), method);
    if (ok) digestOk = true;
    lines.push(`auth "${escs(s)}" ${verdict}`);
  }
  const cookies = fields.filter(([k]) => k === 'cookie');
  lines.push(`cookie-headers ${cookies.length}`);
  for (const [, whole] of cookies) lines.push(`cookie "${esc(whole)}"`);
  const extra = [];
  let status = Number(one(ps, 'st') || 200);
  let final = true;
  if (mode === 'e417') {
    final = false;
    status = 417;
    for (const v of all(ps, 'sc417')) extra.push(Buffer.concat([Buffer.from('Set-Cookie: '), unhex(v)]));
  } else if (one(ps, 'ch') === 'digest' && !digestOk) {
    final = false;
    status = 401;
    const nonce = randomBytes(8).toString('hex');
    nonces.add(nonce);
    extra.push(Buffer.from(`WWW-Authenticate: Digest realm="o", nonce="${nonce}", qop="auth", algorithm=MD5`));
    for (const v of all(ps, 'sc401')) extra.push(Buffer.concat([Buffer.from('Set-Cookie: '), unhex(v)]));
  }
  if (final) for (const v of all(ps, 'sc')) extra.push(Buffer.concat([Buffer.from('Set-Cookie: '), unhex(v)]));
  for (const v of all(ps, 'h')) extra.push(unhex(v));
  lines.push(`answer ${status}`);
  logged(tag, lines);
  const delay = Number(one(ps, 'delay') || 0);
  if (delay > 0) await sleep(delay);
  const body = Buffer.from(reportOf(tag), 'latin1');
  const parts = [Buffer.from(`HTTP/1.1 ${status} ${REASON[status] || 'Status'}\r\nContent-Type: text/plain\r\nContent-Length: ${body.length}\r\n`)];
  for (const e of extra) parts.push(e, Buffer.from('\r\n'));
  parts.push(Buffer.from('\r\n'), body);
  if (!sock.destroyed) sock.write(Buffer.concat(parts));
}

// ---------------------------------------------------------------- HTTP/2
let h2Seq = 0;
function h2Face(server) {
  server.on('session', (session) => {
    session.connId = `h2c${++h2Seq}`;
    session.on('error', () => {});
  });
  server.on('stream', async (stream, headers, flags, raw) => {
    stream.on('error', () => {});
    const path = headers[':path'] || '';
    const ps = params(path);
    const tag = one(ps, 'tag');
    const n = ++seq;
    const addr = family(stream.session.socket && stream.session.socket.remoteAddress);
    const lines = [`req #${n} face=h2 conn=${stream.session.connId} stream=${stream.id} addr=${addr} scheme=http "${escs(`${headers[':method']} ${path} HTTP/2`)}"`];
    const fieldsOf = (name) => { const v = []; for (let i = 0; i + 1 < raw.length; i += 2) if (raw[i] === name) v.push(raw[i + 1]); return v; };
    for (const v of fieldsOf(':authority')) lines.push(`authority "${escs(v)}"`);
    for (const v of fieldsOf('host')) lines.push(`host "${escs(v)}"`);
    const cookies = fieldsOf('cookie');
    lines.push(`cookie-fields ${cookies.length}`);
    for (const v of cookies) lines.push(`cookie "${escs(v)}"`);
    const status = Number(one(ps, 'st') || 200);
    lines.push(`answer ${status}`);
    logged(tag, lines);
    const delay = Number(one(ps, 'delay') || 0);
    if (delay > 0) await sleep(delay);
    const sc = all(ps, 'sc').map((v) => unhex(v).toString('latin1'));
    const head = { ':status': status, 'content-type': 'text/plain' };
    if (sc.length) head['set-cookie'] = sc;
    if (stream.destroyed) return;
    try {
      stream.respond(head);
      stream.end(Buffer.from(reportOf(tag), 'latin1'));
    } catch (e) {
      try { stream.respond({ ':status': 500 }); stream.end(`respond failed ${e.code}\n`); } catch (_) {}
    }
  });
}

// ---------------------------------------------------------------- listening
const listen = (srv, port, addr) => new Promise((resolve) => {
  const onError = (e) => resolve(e);
  srv.once('error', onError);
  srv.listen(port, addr, () => { srv.removeListener('error', onError); resolve(null); });
});

// dual: MAKE() twice, bound on 127.0.0.1 and on ::1 at one port: [port,
// v6], v6 '::1' or none(CODE).
async function dual(make) {
  for (let attempt = 0; attempt < 20; attempt++) {
    const s4 = make();
    const e4 = await listen(s4, 0, '127.0.0.1');
    if (e4) throw e4;
    const port = s4.address().port;
    const s6 = make();
    const e6 = await listen(s6, port, '::1');
    if (!e6) return [port, '::1'];
    if (e6.code === 'EADDRINUSE') { await new Promise((r) => s4.close(r)); continue; }
    return [port, `none(${e6.code})`];
  }
  throw new Error('no port free on both');
}

const plainServer = (face) => net.createServer((sock) => serve(face, sock, 'http', family(sock.remoteAddress)));

// wrapDuplex: SOCK behind a plain Duplex, so a TLSSocket reads through the
// stream, the first chunk given back by unshift among it: over the socket
// itself it reads the handle, and the unshifted ClientHello is lost
// (measured on Node 20.10.0 and 24.18.0).
function wrapDuplex(sock) {
  const d = new Duplex({
    read() { sock.resume(); },
    write(chunk, enc, cb) { sock.write(chunk, cb); },
    final(cb) { sock.end(); cb(); },
  });
  sock.on('data', (c) => { if (!d.push(c)) sock.pause(); });
  sock.on('end', () => d.push(null));
  sock.on('error', (e) => d.destroy(e));
  d.on('close', () => sock.destroy());
  return d;
}

// sniffing: the tls face's server, of KEY and CERT: a first byte 0x16 is
// TLS, any other plaintext.
function sniffing(key, cert) {
  return net.createServer((sock) => {
    sock.on('error', () => {});
    const addr = family(sock.remoteAddress);
    sock.once('data', (first) => {
      sock.pause();
      sock.unshift(first);
      if (first[0] === 0x16) {
        const t = new tls.TLSSocket(wrapDuplex(sock), { isServer: true, key, cert, ALPNProtocols: ['http/1.1'] });
        t.on('error', () => {});
        serve('tls', t, 'https', addr);
      } else {
        serve('tls', sock, 'http', addr);
        sock.resume();
      }
    });
  });
}

// ---------------------------------------------------------------- selftest
// The report against bytes written: Cookie headers of every byte class,
// sent raw on the o face, must come back whole, in order, in the report;
// and an HTTP/2 request's cookie crumbs must come back as fields.
async function selftest() {
  const [port] = await dual(() => plainServer('o'));
  const cookieLines = [
    Buffer.from('Cookie: a=1; b=2'),
    Buffer.concat([Buffer.from('cookie: ctl='), Buffer.from([0x01, 0x09, 0x1f, 0x7f]), Buffer.from(' end')]),
    Buffer.concat([Buffer.from('COOKIE: hi='), Buffer.from([0x80, 0xe9, 0xff, 0xc3, 0xa9]), Buffer.from(' ;=,"\\ x')]),
    Buffer.from('Cookie:'),
  ];
  const req = Buffer.concat([Buffer.from('GET /self?tag=selftest HTTP/1.1\r\nHost: 127.0.0.1\r\n'),
    ...cookieLines.flatMap((l) => [l, Buffer.from('\r\n')]), Buffer.from('\r\n')]);
  const body = await new Promise((resolve, reject) => {
    const s = net.connect(port, '127.0.0.1', () => s.write(req));
    let got = Buffer.alloc(0);
    s.on('data', (d) => {
      got = Buffer.concat([got, d]);
      const e = got.indexOf('\r\n\r\n');
      if (e >= 0) {
        const m = /content-length: (\d+)/i.exec(got.subarray(0, e).toString('latin1'));
        if (m && got.length >= e + 4 + Number(m[1])) { s.destroy(); resolve(got.subarray(e + 4).toString('latin1')); }
      }
    });
    s.on('error', reject);
    setTimeout(() => reject(new Error('selftest timeout')), 5000);
  });
  const fails = [];
  const got = body.split('\n').filter((l) => l.startsWith('cookie "')).map((l) => unesc(l.slice(8, -1)));
  const count = (/cookie-headers (\d+)/.exec(body) || [])[1];
  if (Number(count) !== cookieLines.length) fails.push(`cookie-headers ${count}, wrote ${cookieLines.length}`);
  if (got.length !== cookieLines.length) fails.push(`${got.length} cookie lines reported, wrote ${cookieLines.length}`);
  cookieLines.forEach((l, i) => { if (!got[i] || !got[i].equals(l)) fails.push(`line ${i}: wrote ${l.toString('hex')}, reported ${got[i] ? got[i].toString('hex') : 'none'}`); });
  // HTTP/2: crumbs as fields.
  const h2 = http2.createServer();
  h2Face(h2);
  await listen(h2, 0, '127.0.0.1');
  const h2body = await new Promise((resolve, reject) => {
    const c = http2.connect(`http://127.0.0.1:${h2.address().port}`);
    c.on('error', reject);
    const r = c.request({ ':path': '/self?tag=selftest2', cookie: ['x=1', 'y=2; z=3'] });
    let d = '';
    r.setEncoding('latin1');
    r.on('data', (x) => { d += x; });
    r.on('end', () => { c.close(); resolve(d); });
  });
  const h2got = h2body.split('\n').filter((l) => l.startsWith('cookie "')).map((l) => unesc(l.slice(8, -1)).toString('latin1'));
  if (JSON.stringify(h2got) !== JSON.stringify(['x=1', 'y=2; z=3'])) fails.push(`h2 fields ${JSON.stringify(h2got)}`);
  if (fails.length) { for (const f of fails) console.log(`selftest FAIL ${f}`); process.exit(1); }
  console.log(`selftest ok ${cookieLines.length} HTTP/1.1 lines and ${h2got.length} HTTP/2 fields came back whole`);
  process.exit(0);
}

if (process.argv[2] === '--selftest') await selftest();

if (process.argv.length < 3) {
  process.stderr.write('usage: node standin.mjs PKI | --selftest\n');
  process.exit(2);
}
const pki = process.argv[2];
const key = readFileSync(`${pki}/good.key`);
const cert = readFileSync(`${pki}/good.pem`);

const [oPort, o6] = await dual(() => plainServer('o'));
const v4 = plainServer('v4');
const e4 = await listen(v4, 0, '127.0.0.1');
if (e4) throw e4;
const v6 = plainServer('v6');
const e6 = await listen(v6, 0, '::1');
const v6Text = e6 ? `none(${e6.code})` : String(v6.address().port);
const [h2Port, h26] = await dual(() => { const s = http2.createServer(); h2Face(s); return s; });
const [tlsPort, tls6] = await dual(() => sniffing(key, cert));
process.stdout.write(`o=${oPort} v4=${v4.address().port} v6=${v6Text} h2=${h2Port} tls=${tlsPort} o6=${o6} h26=${h26} tls6=${tls6}\n`);
process.stdin.resume();
process.stdin.on('end', () => process.exit(0));
