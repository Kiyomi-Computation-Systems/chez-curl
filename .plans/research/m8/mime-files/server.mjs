// M8's mime-files probe server (2026-11-06; the M8 plan's measurements, probe
// 2: file parts, resends, lifetime, and a libcurl without mime). Node 20 or
// later, ESM, the standard library only:
//   node server.mjs
// Writes one line on stdout, the ports, then serves until stdin ends:
//   ctl=PORT raw=PORT h2c=PORT
//
// Faces:
//   raw  plaintext HTTP/1.1 on node:net, each head parsed from its bytes by
//        hand, keep-alive, TCP_NODELAY. A body is read by its framing:
//        Content-Length, chunked (decoded; the chunk count logged), or none.
//        Bytes that follow a request and do not begin a request line (A to Z)
//        are logged as "garbage" and the connection is destroyed: a body
//        longer than its Content-Length shows there.
//   h2c  node:http2's plaintext server: HTTP/2 by prior knowledge.
//   ctl  plaintext control, never logged:
//          GET /seq             the last event's number
//          GET /events?after=N  every event after N, one a line, once no
//                               request is open (bounded at 3 s)
//
// Every request carries tag=TAG in its query, which its event lines name.
// Routes, on raw unless noted; each reads the whole body before it answers,
// but where it says otherwise:
//   /hello[?idleclose=MS]  200 "hello\n"; with idleclose, the connection is
//                          destroyed MS ms after the answer if no request
//                          came meanwhile (a pooled connection closed idle).
//   /sink                  200 "ok\n".
//     &expect=417[&times=N] the tag's first N (default 1) requests with
//                          Expect: 100-continue are answered
//                          417 as the head arrives, before any body byte,
//                          and the connection kept; the next bytes decide:
//                          A to Z begin the next request, anything else is
//                          the refused request's body, read by its framing
//                          and logged (refused-body). Every later request is
//                          served as /sink is (100 Continue to an Expect).
//     &expect=late417[&times=N] the tag's first N requests with Expect:
//                          100-continue get no 100; the body is read whole,
//                          then answered 417, the connection kept.
//     &drop=N&at=body|head the first N requests of the tag are never
//                          answered: the connection is destroyed once the
//                          body is read whole (body) or as the head arrives
//                          (head).
//   /redir?code=307|308    the body read, then CODE with Location
//                          /sink?tag=TAG.hop (Content-Length 0).
//   /digest[?stale=1]      HTTP Digest, MD5, qop=auth, realm "m8probe",
//                          account user:pass. A request without a valid
//                          Authorization is answered 401 with a fresh nonce
//                          (its body read first). With stale=1, the tag's
//                          first valid response is answered 401 stale=true
//                          with a new nonce. A valid one gets 200.
//   /slow?ms=MS            as /sink, but the socket is paused for MS ms as
//                          the head arrives (the client's send stalls).
//   anything else          404.
//   A request with Expect: 100-continue to a route that is not expect=417 or
//   late417 is answered 100 Continue as its head arrives.
//
//   h2c: /sink as above, and /refuse?n=N&at=head|end: the first N streams of
//   the tag are reset RST_STREAM REFUSED_STREAM as their headers arrive
//   (head) or once their body ended (end); the rest get 200.
//
// Event lines: "ev SEQ t=MS KIND face=F conn=PORT ...". KIND: accept, req,
// body, part, answer, drop, refused-body, garbage, partial, close, idleclose,
// stream, rst, error. A body line names the framing, the declared length,
// the bytes received and their FNV-1a 32-bit hash; each part line one part
// of a multipart/form-data body (split by the Content-Type's boundary): its
// headers, length, hash, seed (when its bytes are the probe's blob of a seed,
// probe.c's "Content"), and first and last bytes; a part the body ends inside,
// with no closing delimiter, is "unterminated", its content counted to the
// body's end.
//
// Escaping: printable ASCII as is, but \ as \\ and " as \"; CR as \r, LF as
// \n; every other byte as \xNN.
import { createHash, randomBytes } from 'node:crypto';
import http2 from 'node:http2';
import net from 'node:net';

const T0 = performance.now();
const now = () => performance.now();
const ms = (x) => x.toFixed(1);
const sockets = new Set();
const sessions = new Set();
const events = [];
let seq = 0;
let inflight = 0;
const ev = (kind, face, port, rest) => {
  seq++;
  events.push({ seq, line: `ev ${seq} t=${ms(now() - T0)} ${kind} face=${face} conn=${port}${rest ? ` ${rest}` : ''}` });
};
const esc = (b, max = 160) => {
  let o = '';
  const n = Math.min(b.length, max);
  for (let i = 0; i < n; i++) {
    const c = b[i];
    if (c === 13) o += '\\r';
    else if (c === 10) o += '\\n';
    else if (c === 92) o += '\\\\';
    else if (c === 34) o += '\\"';
    else if (c < 0x20 || c > 0x7e) o += `\\x${c.toString(16).padStart(2, '0')}`;
    else o += String.fromCharCode(c);
  }
  if (b.length > max) o += `...(${b.length} bytes)`;
  return `"${o}"`;
};
const fnv = (b) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < b.length; i++) { h ^= b[i]; h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16).padStart(8, '0');
};
const md5 = (s) => createHash('md5').update(s).digest('hex');
// seedOf: S when every byte i of B is 'a' + (i + S) mod 26, the probe's blob
// of seed S (mod 26); "no" otherwise, or "empty".
const seedOf = (b) => {
  if (b.length === 0) return 'empty';
  const s0 = b[0] - 0x61;
  if (s0 < 0 || s0 > 25) return 'no';
  for (let i = 0; i < b.length; i++) if (b[i] !== 0x61 + ((i + s0) % 26)) return 'no';
  return String(s0);
};
function parseTarget(target) {
  const q = target.indexOf('?');
  return { path: q < 0 ? target : target.slice(0, q), params: new URLSearchParams(q < 0 ? '' : target.slice(q + 1)) };
}

// parts: the multipart body B split by BOUNDARY, as event lines.
function partLines(tag, ct, b) {
  const m = /boundary=("?)([^";]+)\1/i.exec(ct || '');
  if (!m) return [`tag=${tag} multipart=no boundary-in-content-type`];
  const delim = Buffer.from(`--${m[2]}`);
  const out = [];
  let pos = b.indexOf(delim);
  if (pos < 0) return [`tag=${tag} multipart=no-delimiter boundary=${m[2]}`];
  const pre = pos;
  let i = 0;
  let closed = 0;
  for (;;) {
    let after = pos + delim.length;
    if (b.subarray(after, after + 2).toString('latin1') === '--') { closed = 1; break; }
    if (b.subarray(after, after + 2).toString('latin1') !== '\r\n') { out.push(`tag=${tag} i=${i} malformed-after-delimiter ${esc(b.subarray(after, after + 16))}`); break; }
    after += 2;
    const next = b.indexOf(Buffer.concat([Buffer.from('\r\n'), delim]), after);
    if (next < 0) {
      const rest = b.subarray(after);
      const he = rest.indexOf('\r\n\r\n');
      const content = he < 0 ? Buffer.alloc(0) : rest.subarray(he + 4);
      out.push(`tag=${tag} i=${i} unterminated headers=${esc(he < 0 ? rest : rest.subarray(0, he), 400)} len_to_end=${content.length} fnv=${fnv(content)} seed=${seedOf(content)} first=${esc(content.subarray(0, 24))} last=${esc(content.subarray(Math.max(0, content.length - 12)))}`);
      break;
    }
    const part = b.subarray(after, next);
    const he = part.indexOf('\r\n\r\n');
    const heads = he < 0 ? part : part.subarray(0, he);
    const content = he < 0 ? Buffer.alloc(0) : part.subarray(he + 4);
    out.push(`tag=${tag} i=${i} headers=${esc(heads, 400)} len=${content.length} fnv=${fnv(content)} seed=${seedOf(content)} first=${esc(content.subarray(0, 24))} last=${esc(content.subarray(Math.max(0, content.length - 12)))}`);
    i++;
    pos = next + 2;
  }
  const tail = closed ? b.length - (pos + delim.length + 2) : '-';
  out.push(`tag=${tag} summary parts=${i} closed=${closed} preamble=${pre} after_close=${tail} boundary=${m[2]} boundary_len=${m[2].length}`);
  return out;
}

// ---------------------------------------------------------------- Digest
const REALM = 'm8probe';
const nonces = new Set();
const staleDone = new Set();
const challenge = (stale) => {
  const n = randomBytes(12).toString('hex');
  nonces.add(n);
  return `Digest realm="${REALM}", qop="auth", algorithm=MD5, nonce="${n}", opaque="op8"${stale ? ', stale=true' : ''}`;
};
function digestVerdict(method, auth) {
  if (!auth || !/^Digest /i.test(auth)) return 'none';
  const p = {};
  for (const m of auth.slice(7).matchAll(/([a-zA-Z]+)=("([^"]*)"|[^,\s]+)/g)) p[m[1].toLowerCase()] = m[3] !== undefined ? m[3] : m[2];
  if (p.username !== 'user' || p.realm !== REALM || !nonces.has(p.nonce)) return `bad-params(user=${p.username},nonce_known=${nonces.has(p.nonce)})`;
  const ha1 = md5(`user:${REALM}:pass`);
  const ha2 = md5(`${method}:${p.uri}`);
  const want = p.qop ? md5(`${ha1}:${p.nonce}:${p.nc}:${p.cnonce}:${p.qop}:${ha2}`) : md5(`${ha1}:${p.nonce}:${ha2}`);
  return want === p.response ? 'valid' : 'bad-response';
}

// ---------------------------------------------------------------- raw HTTP/1.1
const tagCount = new Map();
const bump = (k) => { const n = (tagCount.get(k) || 0) + 1; tagCount.set(k, n); return n; };

function serveRaw(sock) {
  const port = sock.remotePort;
  const c = { sock, port, buf: Buffer.alloc(0), busy: false, dead: false, refused: null, idx: 0, idleTimer: null, mode: 'head', want: null };
  ev('accept', 'raw', port);
  sock.on('data', (d) => {
    c.buf = c.buf.length ? Buffer.concat([c.buf, d]) : d;
    if (c.idleTimer) { clearTimeout(c.idleTimer); c.idleTimer = null; }
    pump(c);
  });
  sock.on('close', () => {
    if (c.want && !c.want.done) { ev('partial', 'raw', port, `tag=${c.want.tag} framing=${c.want.framing} declared=${c.want.declared} got=${c.want.got()} first=${esc(c.want.peek())}`); c.want.done = true; inflight--; }
    ev('close', 'raw', port, `requests=${c.idx}`);
  });
}

// readBody: resolve with the body of request R on C, by its framing.
function bodyReader(c, r) {
  const st = { framing: r.te ? 'chunked' : r.cl !== null ? 'cl' : 'none', declared: r.cl === null ? '-' : r.cl, parts: [], chunks: 0, done: false, tag: r.tag, size: 0, cstate: 'size', crem: 0 };
  st.got = () => st.size;
  st.peek = () => Buffer.concat(st.parts).subarray(0, 32);
  return st;
}
// feed: consume what C's buffer holds for its body; answers true once whole.
function feed(c) {
  const st = c.want;
  if (st.framing === 'none') return true;
  if (st.framing === 'cl') {
    const need = st.declared - st.size;
    const take = Math.min(need, c.buf.length);
    if (take > 0) { st.parts.push(c.buf.subarray(0, take)); st.size += take; c.buf = c.buf.subarray(take); }
    return st.size === st.declared;
  }
  for (;;) {
    if (st.cstate === 'size') {
      const e = c.buf.indexOf('\r\n');
      if (e < 0) return false;
      const n = parseInt(c.buf.toString('latin1', 0, e).split(';')[0], 16);
      c.buf = c.buf.subarray(e + 2);
      if (Number.isNaN(n)) { st.bad = 1; return true; }
      if (n === 0) st.cstate = 'trailer';
      else { st.chunks++; st.crem = n; st.cstate = 'data'; }
    } else if (st.cstate === 'data') {
      const take = Math.min(st.crem, c.buf.length);
      if (take > 0) { st.parts.push(c.buf.subarray(0, take)); st.size += take; st.crem -= take; c.buf = c.buf.subarray(take); }
      if (st.crem > 0) return false;
      st.cstate = 'crlf';
    } else if (st.cstate === 'crlf') {
      if (c.buf.length < 2) return false;
      c.buf = c.buf.subarray(2);
      st.cstate = 'size';
    } else {
      const e = c.buf.indexOf('\r\n');
      if (e < 0) return false;
      const line = c.buf.subarray(0, e);
      c.buf = c.buf.subarray(e + 2);
      if (line.length === 0) return true;
    }
  }
}

function pump(c) {
  for (;;) {
    if (c.dead || c.busy) return;
    if (c.mode === 'body') {
      if (!feed(c)) return;
      const st = c.want;
      st.done = true;
      c.mode = 'head';
      c.want = null;
      inflight--;
      st.resolve(Buffer.concat(st.parts), st);
      continue;
    }
    if (c.mode === 'peek417') {
      if (c.buf.length === 0) return;
      const b0 = c.buf[0];
      c.mode = 'head';
      if (!(b0 >= 0x41 && b0 <= 0x5a)) {
        const r = c.refused;
        c.refused = null;
        startBody(c, r, (body, st) => {
          ev('refused-body', 'raw', c.port, `tag=${r.tag} idx=${r.idx} framing=${st.framing} got=${body.length} fnv=${fnv(body)}`);
        });
        continue;
      }
      continue;
    }
    if (c.buf.length === 0) return;
    const b0 = c.buf[0];
    if (!(b0 >= 0x41 && b0 <= 0x5a)) {
      ev('garbage', 'raw', c.port, `bytes=${c.buf.length} first=${esc(c.buf.subarray(0, 48))}`);
      c.dead = true;
      c.sock.destroy();
      return;
    }
    const end = c.buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const headBytes = c.buf.subarray(0, end + 4);
    c.buf = c.buf.subarray(end + 4);
    const lines = headBytes.toString('latin1', 0, end).split('\r\n');
    const [method, target] = lines[0].split(' ');
    const hs = {};
    for (const l of lines.slice(1)) {
      const i = l.indexOf(':');
      if (i < 0) continue;
      const k = l.slice(0, i).trim().toLowerCase();
      hs[k] = hs[k] === undefined ? l.slice(i + 1).trim() : `${hs[k]}, ${l.slice(i + 1).trim()}`;
    }
    const { path, params } = parseTarget(target || '');
    const r = {
      method, path, params, tag: params.get('tag') || '-', idx: c.idx++, hs,
      cl: hs['content-length'] !== undefined ? Number(hs['content-length']) : null,
      te: /chunked/i.test(hs['transfer-encoding'] || ''),
      expect: /100-continue/i.test(hs.expect || ''),
    };
    ev('req', 'raw', c.port, `tag=${r.tag} idx=${r.idx} ${method} ${path} cl=${r.cl === null ? '-' : r.cl} te=${r.te ? 'chunked' : '-'} expect=${r.expect ? '100-continue' : '-'} ct=${esc(Buffer.from(hs['content-type'] || '-', 'latin1'), 200)} auth=${hs.authorization ? 'yes' : 'no'} head=${esc(headBytes, 2000)}`);
    route(c, r);
  }
}

function startBody(c, r, done) {
  const st = bodyReader(c, r);
  st.resolve = done;
  c.want = st;
  c.mode = 'body';
  inflight++;
}

function answer(c, r, status, extra, body) {
  const b = Buffer.from(body || '');
  const reason = { 200: 'OK', 307: 'Temporary Redirect', 308: 'Permanent Redirect', 401: 'Unauthorized', 404: 'Not Found', 417: 'Expectation Failed' }[status] || 'X';
  c.sock.write(`HTTP/1.1 ${status} ${reason}\r\n${extra || ''}Content-Length: ${b.length}\r\n\r\n`);
  if (b.length) c.sock.write(b);
  ev('answer', 'raw', c.port, `tag=${r.tag} idx=${r.idx} status=${status}`);
}

function logBody(face, port, r, body, framing, chunks) {
  ev('body', face, port, `tag=${r.tag} idx=${r.idx} framing=${framing} declared=${r.cl === null ? '-' : r.cl} got=${body.length} chunks=${chunks} fnv=${fnv(body)} first=${esc(body.subarray(0, 40))}`);
  if (/multipart/i.test(r.hs['content-type'] || '') || body.length > 0) {
    for (const l of partLines(r.tag, r.hs['content-type'], body)) ev('part', face, port, l);
  }
}

function route(c, r) {
  const p = r.params;
  const withBody = (fn) => {
    startBody(c, r, (body, st) => { logBody('raw', c.port, r, body, st.framing, st.chunks); fn(body); });
  };
  if (r.path === '/hello') {
    answer(c, r, 200, '', 'hello\n');
    const idle = Number(p.get('idleclose') || '0');
    if (idle > 0) {
      c.idleTimer = setTimeout(() => {
        if (c.buf.length === 0 && c.mode === 'head') { ev('idleclose', 'raw', c.port, `tag=${r.tag} after_ms=${idle}`); c.dead = true; c.sock.destroy(); }
      }, idle);
    }
    return;
  }
  if (r.path === '/sink' || r.path === '/slow') {
    const ex = p.get('expect');
    const firstN = Number(p.get('times') || '1');
    if (r.expect && ex === '417' && bump(`417:${r.tag}`) <= firstN) {
      answer(c, r, 417, '', '');
      c.refused = r;
      c.mode = 'peek417';
      return;
    }
    const drop = Number(p.get('drop') || '0');
    if (drop > 0 && bump(`drop:${r.tag}`) <= drop) {
      if (p.get('at') === 'head') {
        ev('drop', 'raw', c.port, `tag=${r.tag} idx=${r.idx} at=head buffered_body_bytes=${c.buf.length}`);
        c.dead = true;
        c.sock.destroy();
        return;
      }
      if (r.expect) c.sock.write('HTTP/1.1 100 Continue\r\n\r\n');
      withBody(() => { ev('drop', 'raw', c.port, `tag=${r.tag} idx=${r.idx} at=body`); c.dead = true; c.sock.destroy(); });
      return;
    }
    const late = r.expect && ex === 'late417' && bump(`late417:${r.tag}`) <= firstN;
    if (r.expect && !late) c.sock.write('HTTP/1.1 100 Continue\r\n\r\n');
    if (r.path === '/slow') {
      const hold = Number(p.get('ms') || '1000');
      c.sock.pause();
      ev('pause', 'raw', c.port, `tag=${r.tag} ms=${hold}`);
      setTimeout(() => { if (!c.sock.destroyed) c.sock.resume(); }, hold);
    }
    withBody(() => {
      if (late) answer(c, r, 417, '', '');
      else answer(c, r, 200, '', 'ok\n');
    });
    return;
  }
  if (r.path === '/redir') {
    const code = Number(p.get('code') || '307');
    if (r.expect) c.sock.write('HTTP/1.1 100 Continue\r\n\r\n');
    withBody(() => answer(c, r, code, `Location: /sink?tag=${r.tag}.hop\r\n`, ''));
    return;
  }
  if (r.path === '/digest') {
    if (r.expect) c.sock.write('HTTP/1.1 100 Continue\r\n\r\n');
    withBody(() => {
      const v = digestVerdict(r.method, r.hs.authorization);
      if (v === 'valid' && p.get('stale') === '1' && !staleDone.has(r.tag)) {
        staleDone.add(r.tag);
        ev('digest', 'raw', c.port, `tag=${r.tag} idx=${r.idx} verdict=valid answered=401-stale`);
        answer(c, r, 401, `WWW-Authenticate: ${challenge(true)}\r\n`, '');
        return;
      }
      ev('digest', 'raw', c.port, `tag=${r.tag} idx=${r.idx} verdict=${v}`);
      if (v === 'valid') answer(c, r, 200, '', 'ok\n');
      else answer(c, r, 401, `WWW-Authenticate: ${challenge(false)}\r\n`, '');
    });
    return;
  }
  withBody(() => answer(c, r, 404, '', ''));
}

const raw = net.createServer((sock) => {
  sockets.add(sock);
  sock.on('close', () => sockets.delete(sock));
  sock.on('error', (e) => ev('error', 'raw', sock.remotePort, `code=${e.code}`));
  sock.setNoDelay(true);
  serveRaw(sock);
});

// ---------------------------------------------------------------- h2c
const h2c = http2.createServer();
h2c.on('session', (s) => {
  sessions.add(s);
  const port = s.socket && s.socket.remotePort;
  ev('session', 'h2c', port);
  s.on('close', () => { sessions.delete(s); ev('close', 'h2c', port, 'session'); });
  s.on('error', (e) => ev('error', 'h2c', port, `session code=${e.code}`));
});
h2c.on('stream', (stream, headers) => {
  stream.on('error', () => {});
  const port = stream.session && stream.session.socket ? stream.session.socket.remotePort : '?';
  const { path, params } = parseTarget(headers[':path'] || '');
  const tag = params.get('tag') || '-';
  const hs = {};
  for (const [k, v] of Object.entries(headers)) hs[k] = String(v);
  const r = { tag, idx: stream.id, hs, cl: hs['content-length'] !== undefined ? Number(hs['content-length']) : null };
  ev('stream', 'h2c', port, `tag=${tag} stream=${stream.id} ${headers[':method']} ${path} cl=${r.cl === null ? '-' : r.cl} ct=${esc(Buffer.from(hs['content-type'] || '-', 'latin1'), 200)} headers=${esc(Buffer.from(Object.entries(headers).map(([k, v]) => `${k}: ${v}`).join(' | '), 'latin1'), 1200)}`);
  const n = Number(params.get('n') || '0');
  const at = params.get('at') || 'head';
  const refuse = path === '/refuse' && bump(`refuse:${tag}`) <= n;
  if (refuse && at === 'head') {
    ev('rst', 'h2c', port, `tag=${tag} stream=${stream.id} at=head code=REFUSED_STREAM`);
    stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
    return;
  }
  inflight++;
  const parts = [];
  stream.on('data', (d) => parts.push(d));
  stream.on('end', () => {
    inflight--;
    const body = Buffer.concat(parts);
    logBody('h2c', port, r, body, 'h2', '-');
    if (refuse) {
      ev('rst', 'h2c', port, `tag=${tag} stream=${stream.id} at=end code=REFUSED_STREAM`);
      stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
      return;
    }
    stream.respond({ ':status': 200, 'content-length': '3' });
    stream.end('ok\n');
    ev('answer', 'h2c', port, `tag=${tag} stream=${stream.id} status=200`);
  });
  stream.on('aborted', () => { ev('partial', 'h2c', port, `tag=${tag} stream=${stream.id} aborted got=${Buffer.concat(parts).length}`); });
});

// ---------------------------------------------------------------- control
const sleep = (n) => new Promise((r) => setTimeout(r, n));
const ctl = net.createServer((s) => {
  s.on('error', () => {});
  let buf = '';
  let answered = false;
  s.on('data', async (d) => {
    buf += d.toString('latin1');
    if (answered || buf.indexOf('\r\n\r\n') < 0) return;
    answered = true;
    const { path, params } = parseTarget(buf.split(' ')[1] || '/');
    let body;
    if (path === '/seq') body = `${seq}\n`;
    else if (path === '/events') {
      const after = Number(params.get('after') || '0');
      const t = now();
      while (inflight > 0 && now() - t < 3000) await sleep(5);
      const ls = events.filter((e) => e.seq > after).map((e) => e.line);
      if (inflight > 0) ls.push(`ev - ${inflight} request(s) still open after 3 s`);
      body = ls.length ? `${ls.join('\n')}\n` : '';
    } else body = 'no such control path\n';
    s.end(`HTTP/1.0 200 OK\r\nContent-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
  });
});

const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const servers = [ctl, raw, h2c];
const ports = [];
for (const s of servers) ports.push(await listen(s));
process.stdout.write(`ctl=${ports[0]} raw=${ports[1]} h2c=${ports[2]}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const s of servers) s.close();
  process.exit(0);
});
