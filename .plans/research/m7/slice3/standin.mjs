// M7 slice 3's stand-ins (2026-11-02; the M7 plan, section 6.1): origins and
// proxies on 127.0.0.1, adapted from ../proxies/server.mjs. Node 20 or later,
// ESM, the standard library only:
//   node standin.mjs PKI [--low-ports]
//   node standin.mjs --selftest
// PKI is a directory tests/make-test-pki.sh filled. Writes one line on stdout,
// every face's port, NAME=PORT, then serves until stdin ends. --low-ports
// (root, in Docker alone) adds p80 on port 80 and p1080 on 1080, plaintext
// open proxies, and tp443 on 443, an open proxy over TLS with the good leaf.
//
// Every HTTP/1.1 face parses HTTP/1.1 itself on node:net, keeps connections
// alive, and reads a request body by Content-Length. A connection whose
// first bytes are a PROXY protocol v1 line has it logged and taken off.
// Bytes whose first cannot start a request line (A to Z), such as a TLS
// ClientHello, get 400 and a close, logged as not-http.
//
// Origins:
//   o-raw, o-raw2  plaintext HTTP/1.1, two origins
//   o-tls          TLS, the good leaf, ALPN http/1.1 alone
//   o-h2           TLS, the good leaf, ALPN h2 alone (node:http2)
//   o-h2c          plaintext HTTP/2 by prior knowledge (node:http2)
// An HTTP/1.1 origin answers by the query: go=URL, a redirect (code=, 302 by
// default) to URL; ch=basic or ch=digest, 401 with that challenge unless the
// request carries valid credentials for ouser / opass (Digest MD5,
// qop=auth); else 200 "origin FACE#ID METHOD TARGET body=N". Every answer
// carries X-Origin: FACE#ID. The HTTP/2 origins answer 200 alone.
//
// Proxies, plaintext:
//   p-open, p-other  no auth
//   p-basic          Basic for alice / s3cret and bob / hunter2; else 407,
//                    Proxy-Authenticate: Basic realm="m7s3", keep-alive
//   p-403, p-502     that status to every request, keep-alive
//   p-close          reads a request's head, then closes, nothing written
//   p-partial        reads a request's head, writes "HTTP/1.1 200" with no
//                    line end, then ends
// Proxies over TLS, ALPN http/1.1: tp-good, tp-expired, tp-wrong,
// tp-untrusted (open, each with one leaf), tp-basic (Basic, the good leaf).
// refused: a port bound and closed before the announcement.
// A proxy, once a request passes its auth:
//   - CONNECT 127.0.0.1:PORT, PORT an origin's, gets "HTTP/1.1 200
//     Connection established" with X-Tunnel: PROXY#ID, then both ways are
//     piped; any other target gets 502;
//   - an absolute-form http://127.0.0.1:PORT/... to o-raw or o-raw2 is
//     forwarded: on an upstream connection of this proxy connection's to that
//     origin, in origin form, every header but Proxy-Authorization and
//     Proxy-Connection, and the origin's answer relayed as it came; to any
//     other face, and an origin-form request, the proxy answers itself, 200
//     "proxy FACE#ID METHOD TARGET".
//
// Control, plaintext on ctl, which closes after each answer:
//   GET /begin?case=NAME  every connection accepted from now on, on any face,
//                         and every upstream a proxy opens, logs under NAME
//   GET /end?case=NAME    waits until every socket of NAME has closed (3 s at
//                         most, and says so), then answers its lines and the
//                         requests per face
// Log lines, under the case of the connection's accept:
//   conn FACE#ID open peer=PORT | conn FACE#ID close in=N out=N
//   tls FACE#ID handshake alpn=A sni=S | tls FACE#ID error CODE MESSAGE
//   haproxy FACE#ID "LINE"
//   req FACE#ID #N via=V "HEAD"     the head as it came, \r \n \\ \" and every
//                                   byte outside 0x20..0x7e escaped (\xHH);
//                                   V is direct, or the proxy connection whose
//                                   tunnel or forward it came through
//   req FACE#ID stream=S #N via=V "NAME: VALUE\r\n..."   an HTTP/2 request,
//                                   its header list as it came
//   hdr FACE#ID #N NAME value="V" scheme=S hex=H user-hex=U pass-hex=P colon=yes|no canonical=yes|no
//                                   each Proxy-Authorization and Authorization;
//                                   Basic decoded, byte for byte
//   auth FACE#ID #N VERDICT         a proxy's or an origin's judgement
//   body FACE#ID #N len=N
//   answer FACE#ID #N STATUS ...    what the face wrote
//   tunnel FACE#ID open to=FACE local=PORT | first-up "BYTES" | closed up=N down=M
//   forward FACE#ID #N to=FACE local=PORT dropped=NAMES | relayed STATUS
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import net from 'node:net';
import tls from 'node:tls';
import http2 from 'node:http2';

// ---------------------------------------------------------------- bytes
function esc(buf) {
  let o = '';
  for (const c of buf) {
    if (c === 0x0d) o += '\\r';
    else if (c === 0x0a) o += '\\n';
    else if (c === 0x5c) o += '\\\\';
    else if (c === 0x22) o += '\\"';
    else if (c < 0x20 || c > 0x7e) o += `\\x${c.toString(16).padStart(2, '0')}`;
    else o += String.fromCharCode(c);
  }
  return o;
}
const escs = (s) => esc(Buffer.from(s, 'latin1'));
const hex = (b) => b.toString('hex');

// decodeAuth: one Authorization or Proxy-Authorization value, a latin1
// string, so its bytes. Basic's credentials are base64-decoded byte for
// byte, and split at the first colon; canonical says whether the base64 is
// what an encoder writes for those bytes.
function decodeAuth(value) {
  const sp = value.indexOf(' ');
  const scheme = (sp < 0 ? value : value.slice(0, sp)).toLowerCase();
  const rest = sp < 0 ? '' : value.slice(sp + 1).trim();
  if (scheme !== 'basic') return { scheme, rest };
  const raw = Buffer.from(rest, 'base64');
  const i = raw.indexOf(0x3a);
  return {
    scheme,
    rest,
    raw,
    user: i < 0 ? raw : raw.subarray(0, i),
    pass: i < 0 ? Buffer.alloc(0) : raw.subarray(i + 1),
    colon: i >= 0,
    canonical: raw.toString('base64') === rest,
  };
}
function authText(name, value) {
  const d = decodeAuth(value);
  if (d.scheme !== 'basic') return `${name} value="${escs(value)}" scheme=${escs(d.scheme)}`;
  return `${name} value="${escs(value)}" scheme=basic hex=${hex(d.raw)} user-hex=${hex(d.user)} pass-hex=${hex(d.pass)} colon=${d.colon ? 'yes' : 'no'} canonical=${d.canonical ? 'yes' : 'no'}`;
}

// ---------------------------------------------------------------- selftest
// The decoder against bytes written here, each vector's base64 made by the
// shell's base64(1), its hex by od(1), never by this file; and one planted
// vector whose expected hex is a byte short, which must fail.
function selftest() {
  const vectors = [
    ['Basic YWxpY2U6czNjcmV0', '616c6963653a733363726574', '616c696365', '733363726574', true],
    ['Basic Ym9iOmh1bnRlcjI=', '626f623a68756e74657232', '626f62', '68756e74657232', true],
    ['Basic dQ0KeDr/cA==', '750d0a783aff70', '750d0a78', 'ff70', true],
    ['Basic Og==', '3a', '', '', true],
    ['Basic w6lsw6h2ZTpww6Rzcw==', 'c3a96cc3a876653a70c3a47373', 'c3a96cc3a87665', '70c3a47373', true],
    ['Basic YTpiOmM=', '613a623a63', '61', '623a63', true],
    ['Basic dQB4OnA=', '7500783a70', '750078', '70', true],
    ['basic YWxpY2U6czNjcmV0', '616c6963653a733363726574', '616c696365', '733363726574', true],
  ];
  const planted = [['Basic YWxpY2U6czNjcmV0', '616c6963653a7333637265', '616c696365', '733363726574', true]];
  const fails = [];
  let n = 0;
  const check = (v) => {
    const d = decodeAuth(v[0]);
    return d.scheme === 'basic' && hex(d.raw) === v[1] && hex(d.user) === v[2] && hex(d.pass) === v[3] && d.canonical === v[4];
  };
  for (const v of vectors) { n++; if (!check(v)) fails.push(`vector ${v[0]}`); }
  for (const v of planted) { n++; if (check(v)) fails.push(`planted vector passed: ${v[0]} ${v[1]}`); }
  // A value of another scheme decodes no bytes; Digest is passed on as given.
  n++; if (decodeAuth('Digest username="alice"').scheme !== 'digest' || decodeAuth('Digest username="alice"').raw) fails.push('digest');
  // authText's line, whole, for one vector.
  n++;
  const line = authText('proxy-authorization', 'Basic dQ0KeDr/cA==');
  if (line !== 'proxy-authorization value="Basic dQ0KeDr/cA==" scheme=basic hex=750d0a783aff70 user-hex=750d0a78 pass-hex=ff70 colon=yes canonical=yes') fails.push(`line ${line}`);
  // esc, whole.
  n++;
  if (esc(Buffer.from([0x41, 0x0d, 0x0a, 0x5c, 0x22, 0x00, 0x7f, 0xff])) !== 'A\\r\\n\\\\\\"\\x00\\x7f\\xff') fails.push('esc');
  if (fails.length) { for (const f of fails) console.log(`selftest FAIL ${f}`); process.exit(1); }
  console.log(`selftest ok ${n} (1 planted vector caught)`);
  process.exit(0);
}
if (process.argv[2] === '--selftest') selftest();

const pki = process.argv[2];
if (!pki) {
  process.stderr.write('usage: node standin.mjs PKI [--low-ports] | --selftest\n');
  process.exit(2);
}
const lowPorts = process.argv.includes('--low-ports');
const leaf = (name) => ({ cert: readFileSync(`${pki}/${name}.pem`), key: readFileSync(`${pki}/${name}.key`) });

// ---------------------------------------------------------------- the log
let current = '-';
const cases = new Map(); // NAME -> { lines, open: Set, counts: Map }
const caseOf = (name) => {
  let e = cases.get(name);
  if (!e) { e = { lines: [], open: new Set(), counts: new Map() }; cases.set(name, e); }
  return e;
};
const sleep = (n) => new Promise((r) => setTimeout(r, n));
function track(e, sock) {
  e.open.add(sock);
  sock.on('close', () => e.open.delete(sock));
  sock.on('error', () => {});
}
const count = (e, face) => e.counts.set(face, (e.counts.get(face) || 0) + 1);

// viaByPort: an upstream socket's local port -> the proxy connection that
// opened it, for a tunnel or a forward. An origin reads it at its first
// request, by then always set: the proxy writes its 200, or the forwarded
// request, only once the upstream has connected.
const viaByPort = new Map();
let nextId = 0;
const PORTS = {};
const faceOfPort = new Map();

// ---------------------------------------------------------------- auth
const PROXY_USERS = [[Buffer.from('alice'), Buffer.from('s3cret')], [Buffer.from('bob'), Buffer.from('hunter2')]];
const ORIGIN_USERS = [[Buffer.from('ouser'), Buffer.from('opass')]];
const passOf = (users, user) => {
  for (const [u, p] of users) if (u.equals(user)) return p;
  return null;
};
const nonces = new Set();
const md5 = (...parts) => createHash('md5').update(Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : Buffer.from(p, 'latin1'))))).digest('hex');
function parseDigest(s) {
  const out = {};
  const re = /([A-Za-z0-9_*-]+)\s*=\s*("((?:[^"\\]|\\.)*)"|[^,\s]*)/g;
  let m;
  while ((m = re.exec(s))) out[m[1].toLowerCase()] = m[3] !== undefined ? m[3].replace(/\\(.)/g, '$1') : m[2];
  return out;
}
// judgeBasic: VALUES, the header's values, against USERS: [valid, note].
function judgeBasic(values, users) {
  let ok = false;
  const notes = [];
  for (const v of values) {
    const d = decodeAuth(v);
    if (d.scheme !== 'basic') { notes.push('not-basic'); continue; }
    const want = passOf(users, d.user);
    const valid = want !== null && want.equals(d.pass);
    notes.push(valid ? 'valid' : want === null ? 'invalid(no-such-user)' : 'invalid(wrong-password)');
    if (valid) ok = true;
  }
  return [ok, notes.length ? notes.join(',') : 'none'];
}
function judgeDigest(values, method) {
  for (const v of values) {
    const d = decodeAuth(v);
    if (d.scheme !== 'digest') continue;
    const p = parseDigest(d.rest);
    const user = Buffer.from(p.username || '', 'latin1');
    const want = passOf(ORIGIN_USERS, user);
    if (!nonces.has(p.nonce)) return [false, 'invalid(unknown-nonce)'];
    if (want === null) return [false, 'invalid(no-such-user)'];
    const ha1 = md5(user, ':', p.realm || '', ':', want);
    const ha2 = md5(`${method}:${p.uri || ''}`);
    const exp = p.qop ? md5(`${ha1}:${p.nonce}:${p.nc}:${p.cnonce}:${p.qop}:${ha2}`) : md5(`${ha1}:${p.nonce}:${ha2}`);
    return exp === (p.response || '').toLowerCase() ? [true, `valid user="${esc(user)}" uri="${escs(p.uri || '')}"`] : [false, 'invalid(wrong-response)'];
  }
  return [false, values.length ? 'not-digest' : 'none'];
}

// ---------------------------------------------------------------- HTTP/1.1
// serve: one connection of FACE, of KIND. SOCK is what the face reads and
// writes, TCP the socket under it (the same one on a plaintext face).
function serve(face, kind, sock, tcp, e) {
  const c = { face, kind, sock, tcp, e, id: `${face}#${++nextId}`, buf: Buffer.alloc(0), n: 0, inB: 0, outB: 0, up: null,
    upBytes: 0, downBytes: 0, closed: false, want: null, pending: false, hapDone: false, ups: new Map(), via: null, firstUp: false };
  c.log = (line) => e.lines.push(line);
  c.log(`conn ${c.id} open peer=${tcp.remotePort}`);
  tcp.on('close', () => {
    if (c.up) c.up.destroy();
    for (const u of c.ups.values()) u.sock.destroy();
    c.log(`conn ${c.id} close in=${c.inB} out=${c.outB}${c.buf.length ? ` unparsed=${c.buf.length} "${esc(c.buf.subarray(0, 200))}"` : ''}`);
  });
  sock.on('error', () => {});
  sock.on('data', (d) => {
    c.inB += d.length;
    if (c.up) {
      if (!c.firstUp) { c.firstUp = true; c.log(`tunnel ${c.id} first-up "${esc(d.subarray(0, 64))}"`); }
      c.upBytes += d.length;
      c.up.write(d);
      return;
    }
    c.buf = c.buf.length ? Buffer.concat([c.buf, d]) : d;
    parse(c);
  });
  return c;
}
function send(c, buf) { c.outB += buf.length; c.sock.write(buf); }
function write(c, s) { send(c, Buffer.from(s, 'latin1')); }

function parse(c) {
  for (;;) {
    if (c.closed || c.up || c.pending) return;
    if (!c.hapDone) {
      if (c.buf.length < 6) {
        if (c.buf.length === 0 || 'PROXY '.startsWith(c.buf.toString('latin1'))) return;
        c.hapDone = true;
      } else if (c.buf.subarray(0, 6).toString('latin1') === 'PROXY ') {
        const end = c.buf.indexOf('\r\n');
        if (end < 0) return;
        c.log(`haproxy ${c.id} "${esc(c.buf.subarray(0, end))}"`);
        c.buf = c.buf.subarray(end + 2);
        c.hapDone = true;
        continue;
      } else c.hapDone = true;
    }
    if (c.want) {
      if (c.buf.length < c.want.need) return;
      const req = c.want.req;
      req.body = c.buf.subarray(0, c.want.need);
      c.buf = c.buf.subarray(c.want.need);
      c.want = null;
      c.log(`body ${c.id} #${req.n} len=${req.body.length}`);
      dispatch(c, req);
      continue;
    }
    if (c.buf.length && (c.buf[0] < 0x41 || c.buf[0] > 0x5a)) {
      c.log(`not-http ${c.id} first=0x${c.buf[0].toString(16).padStart(2, '0')} bytes=${c.buf.length}`);
      answer(c, null, 400, 'Bad Request', [], 'not http\n', true);
      return;
    }
    const end = c.buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const headBuf = c.buf.subarray(0, end + 4);
    c.buf = c.buf.subarray(end + 4);
    const head = headBuf.toString('latin1');
    const lines = head.slice(0, -4).split('\r\n');
    const [method = '', target = '', version = ''] = lines[0].split(' ');
    const raw = [];
    for (const l of lines.slice(1)) {
      const i = l.indexOf(':');
      if (i > 0) raw.push([l.slice(0, i), l.slice(i + 1).trim()]);
    }
    const headers = raw.map(([k, v]) => [k.trim().toLowerCase(), v]);
    const get = (name) => headers.filter(([k]) => k === name).map(([, v]) => v);
    c.n += 1;
    count(c.e, c.face);
    if (c.via === null) c.via = (c.kind === 'origin' && viaByPort.get(c.tcp.remotePort)) || 'direct';
    c.log(`req ${c.id} #${c.n} via=${c.via} "${esc(headBuf)}"`);
    for (const [k, v] of headers) if (k === 'proxy-authorization' || k === 'authorization') c.log(`hdr ${c.id} #${c.n} ${authText(k, v)}`);
    const req = { n: c.n, method, target, version, raw, headers, get, body: Buffer.alloc(0) };
    if (get('transfer-encoding').length) {
      c.log(`answer ${c.id} #${c.n} chunked bodies are not read here`);
      answer(c, req, 501, 'Not Implemented', [], 'no chunked\n', true);
      return;
    }
    const cl = get('content-length');
    const need = cl.length ? Number(cl[0]) || 0 : 0;
    if (need > 0) { c.want = { req, need }; continue; }
    dispatch(c, req);
  }
}

function answer(c, req, status, reason, extra, body, close) {
  let h = `HTTP/1.1 ${status} ${reason}\r\n`;
  for (const x of extra) h += `${x}\r\n`;
  h += `Content-Length: ${Buffer.byteLength(body, 'latin1')}\r\n`;
  if (close) h += 'Connection: close\r\n';
  write(c, `${h}\r\n${body}`);
  c.log(`answer ${c.id} #${req ? req.n : 0} ${status}${extra.length ? ` [${extra.map(escs).join(' | ')}]` : ''} body=${Buffer.byteLength(body, 'latin1')}${close ? ' close' : ''}`);
  if (close) { c.closed = true; c.sock.end(); }
}

const wantsClose = (req) => req.get('connection').some((v) => /close/i.test(v)) || req.get('proxy-connection').some((v) => /close/i.test(v));
const ORIGINS = ['o-raw', 'o-raw2', 'o-tls', 'o-h2', 'o-h2c'];
const FORWARDED = ['o-raw', 'o-raw2'];

function originRoute(c, req) {
  const close = wantsClose(req);
  const u = new URL(req.target, 'http://x');
  const q = u.searchParams;
  const tagged = [`X-Origin: ${c.id}`];
  if (q.get('go')) {
    const code = Number(q.get('code') || 302);
    answer(c, req, code, 'Redirect', [...tagged, `Location: ${q.get('go')}`], 'redirect\n', close);
    return;
  }
  const ch = q.get('ch');
  if (ch === 'basic') {
    const [ok, note] = judgeBasic(req.get('authorization'), ORIGIN_USERS);
    c.log(`auth ${c.id} #${req.n} origin-basic ${note}`);
    if (!ok) { answer(c, req, 401, 'Unauthorized', [...tagged, 'WWW-Authenticate: Basic realm="o"'], 'origin auth required\n', close); return; }
  } else if (ch === 'digest') {
    const [ok, note] = judgeDigest(req.get('authorization'), req.method);
    c.log(`auth ${c.id} #${req.n} origin-digest ${note}`);
    if (!ok) {
      const n = randomBytes(8).toString('hex');
      nonces.add(n);
      answer(c, req, 401, 'Unauthorized', [...tagged, `WWW-Authenticate: Digest realm="o", nonce="${n}", qop="auth", algorithm=MD5`], 'origin auth required\n', close);
      return;
    }
  }
  answer(c, req, 200, 'OK', tagged, `origin ${c.id} ${req.method} ${req.target} body=${req.body.length}\n`, close);
}

function dispatch(c, req) {
  const close = wantsClose(req);
  if (c.kind === 'origin') { originRoute(c, req); return; }
  if (c.kind === '403') { answer(c, req, 403, 'Forbidden', [], 'proxy p-403 forbids\n', close); return; }
  if (c.kind === '502') { answer(c, req, 502, 'Bad Gateway', [], 'proxy p-502 bad gateway\n', close); return; }
  if (c.kind === 'close') {
    c.log(`answer ${c.id} #${req.n} none: closing (destroy, a FIN)`);
    c.closed = true;
    c.sock.destroy();
    return;
  }
  if (c.kind === 'partial') {
    c.log(`answer ${c.id} #${req.n} partial: "HTTP/1.1 200" with no line end, then end (FIN)`);
    c.closed = true;
    c.sock.end(Buffer.from('HTTP/1.1 200', 'latin1'));
    return;
  }
  if (c.kind === 'basic') {
    const [ok, note] = judgeBasic(req.get('proxy-authorization'), PROXY_USERS);
    c.log(`auth ${c.id} #${req.n} proxy-basic ${note}`);
    if (!ok) { answer(c, req, 407, 'Proxy Authentication Required', ['Proxy-Authenticate: Basic realm="m7s3"'], 'proxy auth required\n', close); return; }
  }
  if (req.method === 'CONNECT') { tunnel(c, req); return; }
  const m = /^http:\/\/127\.0\.0\.1:(\d+)(\/.*)?$/i.exec(req.target);
  const face = m ? faceOfPort.get(Number(m[1])) : null;
  if (face && FORWARDED.includes(face)) { forward(c, req, Number(m[1]), face, m[2] || '/'); return; }
  answer(c, req, 200, 'OK', [`X-Proxy: ${c.id}`], `proxy ${c.id} ${req.method} ${req.target}\n`, close);
}

function tunnel(c, req) {
  const close = wantsClose(req);
  const m = /^127\.0\.0\.1:(\d+)$/.exec(req.target);
  const port = m ? Number(m[1]) : 0;
  const face = faceOfPort.get(port);
  if (!face || !ORIGINS.includes(face)) {
    answer(c, req, 502, 'Bad Gateway', [], `proxy ${c.id}: no upstream ${req.target}\n`, close);
    return;
  }
  c.pending = true;
  const up = net.connect({ host: '127.0.0.1', port });
  track(c.e, up);
  let local = null;
  up.on('connect', () => {
    local = up.localPort;
    viaByPort.set(local, `${c.id}/tunnel`);
    c.log(`tunnel ${c.id} open to=${face} local=${up.localPort}`);
    write(c, `HTTP/1.1 200 Connection established\r\nX-Tunnel: ${c.id}\r\n\r\n`);
    c.log(`answer ${c.id} #${req.n} 200 Connection established`);
    c.up = up;
    c.pending = false;
    if (c.buf.length) {
      if (!c.firstUp) { c.firstUp = true; c.log(`tunnel ${c.id} first-up "${esc(c.buf.subarray(0, 64))}"`); }
      c.upBytes += c.buf.length; up.write(c.buf); c.buf = Buffer.alloc(0);
    }
  });
  up.on('data', (d) => { c.downBytes += d.length; send(c, d); });
  up.on('close', () => {
    if (local !== null && viaByPort.get(local) === `${c.id}/tunnel`) viaByPort.delete(local);
    c.log(`tunnel ${c.id} closed up=${c.upBytes} down=${c.downBytes}`);
    c.sock.end();
  });
  up.on('error', (err) => c.log(`tunnel ${c.id} upstream error ${err.code}`));
}

// upstream: this proxy connection's upstream to PORT, made once and kept;
// it reads one response at a time, by its Content-Length.
function upstream(c, port) {
  let u = c.ups.get(port);
  if (u && !u.dead) return u;
  const sock = net.connect({ host: '127.0.0.1', port });
  track(c.e, sock);
  u = { sock, buf: Buffer.alloc(0), waiting: null, ready: false, queue: [], dead: false };
  c.ups.set(port, u);
  sock.on('connect', () => {
    u.local = sock.localPort;
    viaByPort.set(u.local, `${c.id}/forward`);
    u.ready = true;
    for (const f of u.queue) f();
    u.queue = [];
  });
  sock.on('data', (d) => {
    u.buf = u.buf.length ? Buffer.concat([u.buf, d]) : d;
    if (!u.waiting) return;
    const end = u.buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const head = u.buf.subarray(0, end + 4).toString('latin1');
    const m = /\r\ncontent-length:\s*(\d+)/i.exec(head);
    const need = end + 4 + (m ? Number(m[1]) : 0);
    if (u.buf.length < need) return;
    const resp = u.buf.subarray(0, need);
    u.buf = u.buf.subarray(need);
    const w = u.waiting;
    u.waiting = null;
    w(resp, head);
  });
  sock.on('close', () => {
    if (u.local !== undefined && viaByPort.get(u.local) === `${c.id}/forward`) viaByPort.delete(u.local);
    u.dead = true;
    if (u.waiting) { const w = u.waiting; u.waiting = null; w(null, null); }
  });
  return u;
}

function forward(c, req, port, face, path) {
  c.pending = true;
  const u = upstream(c, port);
  const go = () => {
    const dropped = [];
    let head = `${req.method} ${path} ${req.version || 'HTTP/1.1'}\r\n`;
    for (const [k, v] of req.raw) {
      const low = k.trim().toLowerCase();
      if (low === 'proxy-authorization' || low === 'proxy-connection') { dropped.push(k.trim()); continue; }
      head += `${k}: ${v}\r\n`;
    }
    head += '\r\n';
    c.log(`forward ${c.id} #${req.n} to=${face} local=${u.sock.localPort} dropped=${dropped.length ? dropped.join(',') : 'none'}`);
    u.waiting = (resp, rhead) => {
      c.pending = false;
      if (!resp) {
        answer(c, req, 502, 'Bad Gateway', [], `proxy ${c.id}: upstream closed\n`, true);
        return;
      }
      c.log(`forward ${c.id} #${req.n} relayed ${rhead.split('\r\n')[0].split(' ')[1]} bytes=${resp.length}`);
      send(c, resp);
      if (wantsClose(req)) { c.closed = true; c.sock.end(); return; }
      parse(c);
    };
    u.sock.write(Buffer.concat([Buffer.from(head, 'latin1'), req.body]));
  };
  if (u.ready) go(); else u.queue.push(go);
}

// ---------------------------------------------------------------- faces
function plain(face, kind) {
  return net.createServer((tcp) => {
    const e = caseOf(current);
    track(e, tcp);
    serve(face, kind, tcp, tcp, e);
  });
}
function secure(face, kind, leafName) {
  const { cert, key } = leaf(leafName);
  return net.createServer((tcp) => {
    const e = caseOf(current);
    track(e, tcp);
    const t = new tls.TLSSocket(tcp, { isServer: true, cert, key, ALPNProtocols: ['http/1.1'] });
    const c = serve(face, kind, t, tcp, e);
    t.on('secure', () => c.log(`tls ${c.id} handshake alpn=${t.alpnProtocol || '-'} sni=${t.servername || '-'}`));
    t.on('error', (err) => c.log(`tls ${c.id} error ${err.code || '-'} ${String(err.message).split('\n')[0].replace(/^[0-9A-Fa-f]+:error:/, '')}`));
  });
}
// h2: an HTTP/2 origin, over TLS (ALPN h2 alone) or plaintext by prior
// knowledge.
function h2(face, overTls) {
  const server = overTls
    ? http2.createSecureServer({ ...leaf('good'), ALPNProtocols: ['h2'], allowHTTP1: false })
    : http2.createServer({});
  const byPort = new Map();
  server.on('connection', (tcp) => {
    const e = caseOf(current);
    track(e, tcp);
    const info = { id: `${face}#${++nextId}`, e, n: 0, via: null, port: tcp.remotePort };
    byPort.set(tcp.remotePort, info);
    e.lines.push(`conn ${info.id} open peer=${tcp.remotePort}`);
    tcp.on('close', () => { e.lines.push(`conn ${info.id} close`); });
  });
  if (overTls) {
    server.on('secureConnection', (t) => {
      const info = byPort.get(t.remotePort);
      if (info) info.e.lines.push(`tls ${info.id} handshake alpn=${t.alpnProtocol || '-'} sni=${t.servername || '-'}`);
    });
    server.on('tlsClientError', (err, t) => {
      const info = t && byPort.get(t.remotePort);
      if (info) info.e.lines.push(`tls ${info.id} error ${err.code || '-'} ${String(err.message).split('\n')[0]}`);
    });
    server.on('unknownProtocol', (t) => {
      const info = byPort.get(t.remotePort);
      if (info) info.e.lines.push(`tls ${info.id} unknown-protocol alpn=${t.alpnProtocol || '-'}`);
      t.destroy();
    });
  }
  server.on('session', (session) => {
    session.on('error', () => {});
  });
  server.on('stream', (stream, headers, flags, rawHeaders) => {
    const port = stream.session.socket.remotePort;
    const info = byPort.get(port) || { id: `${face}#?`, e: caseOf(current), n: 0, via: null };
    if (info.via === null) info.via = viaByPort.get(port) || 'direct';
    info.n += 1;
    count(info.e, face);
    let shown = '';
    const pairs = [];
    for (let i = 0; i < rawHeaders.length; i += 2) { shown += `${rawHeaders[i]}: ${rawHeaders[i + 1]}\r\n`; pairs.push([rawHeaders[i], rawHeaders[i + 1]]); }
    info.e.lines.push(`req ${info.id} stream=${stream.id} #${info.n} via=${info.via} "${escs(shown)}"`);
    for (const [k, v] of pairs) if (k === 'proxy-authorization' || k === 'authorization') info.e.lines.push(`hdr ${info.id} #${info.n} ${authText(k, v)}`);
    stream.on('error', () => {});
    let len = 0;
    stream.on('data', (d) => { len += d.length; });
    stream.on('end', () => {
      const body = `origin ${info.id} stream ${stream.id} ${headers[':method']} ${headers[':path']} body=${len}\n`;
      stream.respond({ ':status': 200, 'x-origin': info.id, 'content-length': Buffer.byteLength(body) });
      stream.end(body);
      info.e.lines.push(`answer ${info.id} #${info.n} 200 stream=${stream.id} body=${Buffer.byteLength(body)}`);
    });
  });
  return server;
}

const control = net.createServer((sock) => {
  let buf = '';
  sock.on('error', () => {});
  sock.on('data', async (d) => {
    buf += d.toString('latin1');
    if (!buf.includes('\r\n\r\n')) return;
    const target = buf.split(' ')[1] || '/';
    const u = new URL(target, 'http://x');
    const name = u.searchParams.get('case') || '-';
    let body;
    if (u.pathname === '/begin') {
      current = name;
      caseOf(name);
      body = `begun ${name}\n`;
    } else if (u.pathname === '/end') {
      const e = caseOf(name);
      const t = Date.now();
      while (e.open.size > 0 && Date.now() - t < 3000) await sleep(5);
      const lines = [...e.lines];
      if (e.open.size > 0) lines.push(`log: ${e.open.size} socket(s) of this case still open after 3 s`);
      const counts = [...e.counts].map(([k, v]) => `${k}=${v}`).join(' ');
      lines.push(`requests ${counts || 'none'}`);
      body = `${lines.join('\n')}\n`;
      cases.delete(name);
      current = '-';
    } else body = 'no such control\n';
    sock.end(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(body, 'latin1')}\r\nConnection: close\r\n\r\n${body}`, 'latin1');
  });
});

const faces = [
  ['ctl', control, 0],
  ['o-raw', plain('o-raw', 'origin'), 0],
  ['o-raw2', plain('o-raw2', 'origin'), 0],
  ['o-tls', secure('o-tls', 'origin', 'good'), 0],
  ['o-h2', h2('o-h2', true), 0],
  ['o-h2c', h2('o-h2c', false), 0],
  ['p-open', plain('p-open', 'open'), 0],
  ['p-other', plain('p-other', 'open'), 0],
  ['p-basic', plain('p-basic', 'basic'), 0],
  ['p-403', plain('p-403', '403'), 0],
  ['p-502', plain('p-502', '502'), 0],
  ['p-close', plain('p-close', 'close'), 0],
  ['p-partial', plain('p-partial', 'partial'), 0],
  ['tp-good', secure('tp-good', 'open', 'good'), 0],
  ['tp-expired', secure('tp-expired', 'open', 'expired'), 0],
  ['tp-wrong', secure('tp-wrong', 'open', 'wrong-host'), 0],
  ['tp-untrusted', secure('tp-untrusted', 'open', 'untrusted'), 0],
  ['tp-basic', secure('tp-basic', 'basic', 'good'), 0],
];
if (lowPorts) {
  faces.push(['p80', plain('p80', 'open'), 80], ['p1080', plain('p1080', 'open'), 1080], ['tp443', secure('tp443', 'open', 'good'), 443]);
}
const listen = (server, port) => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(port, '127.0.0.1', () => resolve(server.address().port));
});
for (const [name, server, port] of faces) {
  PORTS[name] = await listen(server, port);
  faceOfPort.set(PORTS[name], name);
}
{
  const s = net.createServer();
  PORTS.refused = await listen(s, 0);
  await new Promise((r) => s.close(r));
}
process.stdout.write(`${Object.entries(PORTS).map(([k, v]) => `${k}=${v}`).join(' ')}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const [name, e] of cases) if (name !== '-' && e.lines.length) process.stderr.write(`unfetched case=${name} lines=${e.lines.length}\n`);
  process.exit(0);
});
