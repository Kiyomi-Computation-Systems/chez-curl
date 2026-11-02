// M7's proxy probe stand-ins (2026-11-02; the M7 plan's measurements). Node
// 20 or later, ESM, the standard library only:
//   node server.mjs PKI
// PKI is a directory tests/make-test-pki.sh filled. Writes one line on
// stdout, every face's port, then serves on 127.0.0.1 until stdin ends:
//   ctl=P o-raw=P o-tls=P p-open=P ... refused=P
//
// Every face parses HTTP/1.1 itself on node:net (Node's http server reads
// nothing more on a socket after a `connect` event), keeps connections
// alive, and skips a request body by Content-Length. Bytes whose first
// cannot start a request line (A to Z), such as a TLS ClientHello, get 400
// and a close, logged as not-http.
//
// Origins, which answer 200 "origin FACE METHOD TARGET\n":
//   o-raw   plaintext
//   o-tls   TLS, the good leaf (localhost, 127.0.0.1, ::1, by the run CA),
//           ALPN http/1.1 alone
// Proxies, plaintext:
//   p-open    no auth. An absolute-form request is answered by the proxy
//             itself, 200 "proxy FACE METHOD TARGET\n": nothing is forwarded.
//             CONNECT 127.0.0.1:PORT, PORT one of the origins', gets "HTTP/1.1
//             200 Connection established", then both ways are piped and
//             counted; any other target gets 502.
//   p-other   the same, under another name: the proxy the environment names
//   p-basic   as p-open once the request carries a valid Basic
//             Proxy-Authorization; else 407, Proxy-Authenticate: Basic
//             realm="m7", a 20-byte body, keep-alive
//   p-digest  the same for Digest, MD5, qop=auth: Proxy-Authenticate: Digest
//             realm="m7", nonce="N", qop="auth", algorithm=MD5
//   p-both    407 offers Basic, then Digest; either valid one passes
//   p-403     403 to every request, a body, keep-alive
//   p-502     502 to every request, a body, keep-alive
//   p-close   reads a request's head, then closes the socket, nothing written
//             (destroy(): a FIN)
//   p-partial reads a request's head, writes "HTTP/1.1 200" with no line end,
//             then ends (FIN)
// Proxies over TLS, each as p-open, each serving one leaf, ALPN http/1.1:
//   tp-good tp-expired tp-wrong tp-untrusted
// refused: a port that was bound and closed before the announcement, so a
// connect to it is refused.
//
// The credentials a proxy takes, as bytes: alice / s3cret; al@ice / p:ss%w;
// and UTF-8 "élève" (c3 a9 6c c3 a8 76 65) / "päss" (70 c3 a4 73 73). Each
// Proxy-Authorization value is judged alone, and the request passes when any
// one is valid.
//
// Control, plaintext on ctl, HTTP/1.0 is fine, and it closes:
//   GET /begin?case=NAME   every connection accepted from now on, on any
//                          face, and every upstream it opens, logs under NAME
//   GET /end?case=NAME     waits until every socket of NAME has closed
//                          (bounded at 3 s, and says so), then answers its
//                          lines, and the count of requests per face
// Log lines, under the case of the connection's accept:
//   conn FACE#ID open peer=PORT
//   tls FACE#ID handshake alpn=A sni=S | tls FACE#ID error CODE MESSAGE
//   req FACE#ID #N "HEAD"        the whole head as it came, request line to
//                                its blank line, \r \n and every byte outside
//                                0x20..0x7e escaped (\xHH)
//   auth FACE#ID VERDICT ...     each Proxy-Authorization value, decoded
//   answer FACE#ID STATUS ...    what the face wrote
//   tunnel FACE#ID open to=PORT local=PORT | tunnel FACE#ID closed up=N down=M
//   conn FACE#ID close in=N out=N   raw bytes on the face's own TCP socket
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import net from 'node:net';
import tls from 'node:tls';

const pki = process.argv[2];
if (!pki) {
  process.stderr.write('usage: node server.mjs PKI\n');
  process.exit(2);
}
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

// track: SOCK belongs to the case E until it closes.
function track(e, sock) {
  e.open.add(sock);
  sock.on('close', () => e.open.delete(sock));
  sock.on('error', () => {});
}

// ---------------------------------------------------------------- auth
const USERS = [
  [Buffer.from('alice'), Buffer.from('s3cret')],
  [Buffer.from('al@ice'), Buffer.from('p:ss%w')],
  [Buffer.from('élève', 'utf8'), Buffer.from('päss', 'utf8')],
];
const passOf = (user) => {
  for (const [u, p] of USERS) if (u.equals(user)) return p;
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

// judge: one Proxy-Authorization value (a latin1 string, so its bytes) for
// the face's SCHEMES. Answers [valid, a note].
function judge(value, schemes, method, target) {
  const sp = value.indexOf(' ');
  const scheme = (sp < 0 ? value : value.slice(0, sp)).toLowerCase();
  const rest = sp < 0 ? '' : value.slice(sp + 1).trim();
  if (scheme === 'basic') {
    const raw = Buffer.from(rest, 'base64');
    const i = raw.indexOf(0x3a);
    const user = i < 0 ? raw : raw.subarray(0, i);
    const pass = i < 0 ? Buffer.alloc(0) : raw.subarray(i + 1);
    const want = passOf(user);
    const ok = schemes.includes('basic') && want !== null && want.equals(pass);
    const why = !schemes.includes('basic') ? 'basic-not-offered' : want === null ? 'no-such-user' : ok ? 'ok' : 'wrong-password';
    return [ok, `basic decoded="${esc(raw)}" user="${esc(user)}" pass="${esc(pass)}" ${ok ? 'valid' : `invalid(${why})`}`];
  }
  if (scheme === 'digest') {
    const d = parseDigest(rest);
    const user = Buffer.from(d.username || '', 'latin1');
    const want = passOf(user);
    let ok = false;
    let why;
    if (!schemes.includes('digest')) why = 'digest-not-offered';
    else if (!nonces.has(d.nonce)) why = 'unknown-nonce';
    else if (want === null) why = 'no-such-user';
    else {
      const ha1 = md5(user, ':', d.realm || '', ':', want);
      const ha2 = md5(`${method}:${d.uri || ''}`);
      const exp = d.qop ? md5(`${ha1}:${d.nonce}:${d.nc}:${d.cnonce}:${d.qop}:${ha2}`) : md5(`${ha1}:${d.nonce}:${ha2}`);
      ok = exp === (d.response || '').toLowerCase();
      why = ok ? 'ok' : 'wrong-response';
    }
    const keys = Object.keys(d).sort().join(',');
    return [ok, `digest user="${esc(user)}" realm="${escs(d.realm || '')}" uri="${escs(d.uri || '')}" target="${escs(target)}" uri_is_target=${d.uri === target} qop=${d.qop || '-'} nc=${d.nc || '-'} algorithm=${d.algorithm || '-'} params=${keys} ${ok ? 'valid' : `invalid(${why})`}`];
  }
  return [false, `scheme="${escs(scheme)}" invalid(unknown-scheme)`];
}

// ---------------------------------------------------------------- HTTP/1.1
const PORTS = {};
let nextId = 0;

// serve: one connection of FACE. SOCK is what the face reads and writes,
// TCP the socket under it (the same one on a plaintext face). The counts
// in= and out= are SOCK's bytes: plaintext, on a TLS face after the TLS.
function serve(face, kind, sock, tcp, e) {
  const c = { face, kind, sock, tcp, e, id: `${face}#${++nextId}`, buf: Buffer.alloc(0), n: 0, inB: 0, outB: 0, up: null, upBytes: 0, downBytes: 0, closed: false, skip: 0 };
  const log = (line) => e.lines.push(line);
  c.log = log;
  log(`conn ${c.id} open peer=${tcp.remotePort}`);
  tcp.on('close', () => {
    if (c.up) c.up.destroy();
    log(`conn ${c.id} close in=${c.inB} out=${c.outB}${c.buf.length ? ` unparsed=${c.buf.length} "${esc(c.buf.subarray(0, 200))}"` : ''}`);
  });
  sock.on('error', () => {});
  sock.on('data', (d) => {
    c.inB += d.length;
    if (c.up) { c.upBytes += d.length; c.up.write(d); return; }
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
    if (c.skip > 0) {
      const k = Math.min(c.skip, c.buf.length);
      c.buf = c.buf.subarray(k);
      c.skip -= k;
      if (c.skip > 0) return;
    }
    if (c.buf.length && (c.buf[0] < 0x41 || c.buf[0] > 0x5a)) {
      // No request line starts so (a TLS ClientHello's first byte is 0x16):
      // answered as an HTTP server answers bytes it cannot parse.
      c.log(`not-http ${c.id} first=0x${c.buf[0].toString(16).padStart(2, '0')} bytes=${c.buf.length}`);
      answer(c, 400, 'Bad Request', [], 'not http\n', true);
      return;
    }
    const end = c.buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const headBuf = c.buf.subarray(0, end + 4);
    c.buf = c.buf.subarray(end + 4);
    const head = headBuf.toString('latin1');
    const lines = head.slice(0, -4).split('\r\n');
    const [method = '', target = '', version = ''] = lines[0].split(' ');
    const headers = [];
    for (const l of lines.slice(1)) {
      const i = l.indexOf(':');
      if (i > 0) headers.push([l.slice(0, i).trim().toLowerCase(), l.slice(i + 1).trim()]);
    }
    const get = (name) => headers.filter(([k]) => k === name).map(([, v]) => v);
    c.n += 1;
    c.e.counts.set(c.face, (c.e.counts.get(c.face) || 0) + 1);
    c.log(`req ${c.id} #${c.n} "${esc(headBuf)}"`);
    const cl = get('content-length');
    if (cl.length) c.skip = Number(cl[0]) || 0;
    const req = { method, target, version, headers, get };
    dispatch(c, req);
  }
}

function answer(c, status, reason, extra, body, close) {
  let h = `HTTP/1.1 ${status} ${reason}\r\n`;
  for (const x of extra) h += `${x}\r\n`;
  h += `Content-Length: ${Buffer.byteLength(body, 'latin1')}\r\n`;
  if (close) h += 'Connection: close\r\n';
  write(c, `${h}\r\n${body}`);
  c.log(`answer ${c.id} ${status}${extra.length ? ` [${extra.map(escs).join(' | ')}]` : ''} body=${Buffer.byteLength(body, 'latin1')}${close ? ' close' : ''}`);
  if (close) { c.closed = true; c.sock.end(); }
}

function dispatch(c, req) {
  const close = req.get('connection').some((v) => /close/i.test(v)) || req.get('proxy-connection').some((v) => /close/i.test(v));
  if (c.kind === 'origin') {
    answer(c, 200, 'OK', [], `origin ${c.face} ${req.method} ${req.target}\n`, close);
    return;
  }
  if (c.kind === '403') { answer(c, 403, 'Forbidden', [], 'proxy p-403 forbids\n', close); return; }
  if (c.kind === '502') { answer(c, 502, 'Bad Gateway', [], 'proxy p-502 bad gateway\n', close); return; }
  if (c.kind === 'close') {
    c.log(`answer ${c.id} none: closing (destroy, a FIN)`);
    c.closed = true;
    c.sock.destroy();
    return;
  }
  if (c.kind === 'partial') {
    c.log(`answer ${c.id} partial: "HTTP/1.1 200" with no line end, then end (FIN)`);
    c.closed = true;
    c.sock.end(Buffer.from('HTTP/1.1 200', 'latin1'));
    return;
  }
  const schemes = c.kind === 'basic' ? ['basic'] : c.kind === 'digest' ? ['digest'] : c.kind === 'both' ? ['basic', 'digest'] : [];
  const pa = req.get('proxy-authorization');
  let ok = schemes.length === 0;
  for (const v of pa) {
    const [valid, note] = judge(v, schemes, req.method, req.target);
    c.log(`auth ${c.id} ${note}`);
    if (valid) ok = true;
  }
  if (!pa.length && schemes.length) c.log(`auth ${c.id} none`);
  if (!ok) {
    const ch = [];
    if (schemes.includes('basic')) ch.push('Proxy-Authenticate: Basic realm="m7"');
    if (schemes.includes('digest')) {
      const n = randomBytes(8).toString('hex');
      nonces.add(n);
      ch.push(`Proxy-Authenticate: Digest realm="m7", nonce="${n}", qop="auth", algorithm=MD5`);
    }
    answer(c, 407, 'Proxy Authentication Required', ch, 'proxy auth required\n', close);
    return;
  }
  if (req.method === 'CONNECT') {
    const m = /^127\.0\.0\.1:(\d+)$/.exec(req.target);
    const port = m ? Number(m[1]) : 0;
    if (port !== PORTS['o-raw'] && port !== PORTS['o-tls']) {
      answer(c, 502, 'Bad Gateway', [], `proxy ${c.face}: no upstream ${req.target}\n`, close);
      return;
    }
    c.pending = true;
    const up = net.connect({ host: '127.0.0.1', port });
    track(c.e, up);
    up.on('connect', () => {
      c.log(`tunnel ${c.id} open to=${port} local=${up.localPort}`);
      write(c, 'HTTP/1.1 200 Connection established\r\n\r\n');
      c.log(`answer ${c.id} 200 Connection established`);
      c.up = up;
      c.pending = false;
      if (c.buf.length) { c.upBytes += c.buf.length; up.write(c.buf); c.buf = Buffer.alloc(0); }
    });
    up.on('data', (d) => { c.downBytes += d.length; send(c, d); });
    up.on('close', () => {
      c.log(`tunnel ${c.id} closed up=${c.upBytes} down=${c.downBytes}`);
      c.sock.end();
    });
    up.on('error', (err) => c.log(`tunnel ${c.id} upstream error ${err.code}`));
    return;
  }
  answer(c, 200, 'OK', [], `proxy ${c.face} ${req.method} ${req.target}\n`, close);
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
  ['ctl', control],
  ['o-raw', plain('o-raw', 'origin')],
  ['o-tls', secure('o-tls', 'origin', 'good')],
  ['p-open', plain('p-open', 'open')],
  ['p-other', plain('p-other', 'open')],
  ['p-basic', plain('p-basic', 'basic')],
  ['p-digest', plain('p-digest', 'digest')],
  ['p-both', plain('p-both', 'both')],
  ['p-403', plain('p-403', '403')],
  ['p-502', plain('p-502', '502')],
  ['p-close', plain('p-close', 'close')],
  ['p-partial', plain('p-partial', 'partial')],
  ['tp-good', secure('tp-good', 'open', 'good')],
  ['tp-expired', secure('tp-expired', 'open', 'expired')],
  ['tp-wrong', secure('tp-wrong', 'open', 'wrong-host')],
  ['tp-untrusted', secure('tp-untrusted', 'open', 'untrusted')],
];
const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
for (const [name, server] of faces) PORTS[name] = await listen(server);
{
  const s = net.createServer();
  PORTS.refused = await listen(s);
  await new Promise((r) => s.close(r));
}
process.stdout.write(`${Object.entries(PORTS).map(([k, v]) => `${k}=${v}`).join(' ')}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const [name, e] of cases) if (name !== '-' && e.lines.length) process.stderr.write(`unfetched case=${name} lines=${e.lines.length}\n`);
  process.exit(0);
});
