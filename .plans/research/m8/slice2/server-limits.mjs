// M8's header-caps probe server (2026-11-06; the M8 plan's measurements,
// ADR-0038 decision 2). Node 20 or later, ESM, the standard library alone.
// Run with the PKI directory tests/make-test-pki.sh made:
//   node server.mjs PKI
// Writes one line on stdout, the ports, then serves until stdin ends:
//   ctl=PORT h1=PORT h1tls=PORT h2=PORT proxy=PORT
//
// Faces:
//   h1     plaintext HTTP/1.1 on node:net, parsed and written by hand, so
//          every byte of a head is the server's: keep-alive, Content-Length
//          request bodies.
//   h1tls  TLS (the good leaf), ALPN http/1.1 alone, then h1's handler.
//   h2     node:http2's secure server, ALPN h2 alone, with
//          maxSendHeaderBlockLength 64 MiB, maxHeaderListPairs 2^20 and
//          SETTINGS_MAX_HEADER_LIST_SIZE 64 MiB, and sendDate off, so a head
//          holds the headers asked and no date. nghttp2 encodes the block:
//          HPACK, Huffman where it is shorter, a repeated pair indexed.
//   proxy  plaintext HTTP/1.1: a CONNECT is answered 200 with the head the
//          last /arm named, then tunnelled to 127.0.0.1:PORT, the target it
//          names. Anything else is answered 400.
//   ctl    plaintext control, never logged:
//            GET /seq              the last event's number
//            GET /events?after=N   every event after N, one a line, once no
//                                  request is open (bounded at 3 s)
//            GET /arm?QUERY        the head the proxy's next CONNECT answer
//                                  carries, by QUERY's spec (below)
//
// A head's spec, from a query (h1, h1tls and h2, and the proxy's /arm):
//   n=N        the final head's header lines, its framing line among them
//              (content-length: 0, or transfer-encoding: chunked with
//              trailers; none on h2 with trailers, nor in a CONNECT answer)
//   line=L     each generated line's bytes as libcurl hands them, CR LF
//              included, at least 13; 16 by default. Names x-000001 on, the
//              value v repeated, so every line is L bytes
//   total=T    in place of n: lines of L bytes until the head, its status
//              line (slen=S bytes, 17 by default, as libcurl renders it) and
//              its empty line included, holds T bytes exactly; the last line
//              takes the remainder
//   same=1     every generated line is x-same: vvvv..., the same pair
//   big=B      one more line, x-big: aaaa..., of B bytes in all; bigch=C,
//              its value C repeated in place of a
//   pre=C:N:L,...  informational heads before the final one: status C
//              (100 or 103), N lines of L bytes each
//   tn=N&tl=L  N trailers of L bytes each (h1: a chunked body, 0 bytes of
//              data; h2: a trailers HEADERS frame)
// Prefixed a. and b., the spec of a flow's first and second response:
//   /head?SPEC       one response
//   /auth?a.&b.      no Authorization: 401, WWW-Authenticate Digest and a.;
//                    with one, unchecked: 200 and b.
//   /expect?a.&b.    a request with Expect: 100-continue, the tag's first:
//                    417 and a., the body unread; the tag's second: 100
//                    Continue, the body read, then 200 and b.
//   /redir?a.&b.     302 to /head?b.'s spec (tag and slen kept), with a.
// Every request may carry tag=TAG in its query, which its event lines name.
//
// Event lines: "ev SEQ t=MS KIND face=F conn=PORT ...". h1 logs each head it
// writes: status, lines, bytes. h2 logs each stream's heads by entries, and
// at its close any frameError, stream error or rst code; and each TCP
// connection's bytes on the wire as it closes, h2-wire (TLS records, the
// handshake among them).
import { readFileSync } from 'node:fs';
import http2 from 'node:http2';
import net from 'node:net';
import tls from 'node:tls';

const pki = process.argv[2];
const cert = readFileSync(`${pki}/good.pem`);
const key = readFileSync(`${pki}/good.key`);
const T0 = performance.now();
const now = () => performance.now();
const ms = (x) => x.toFixed(1);
const sleep = (n) => new Promise((r) => setTimeout(r, n));

const sockets = new Set();
const sessions = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };

const events = [];
let seq = 0;
let inflight = 0;
const ev = (kind, face, port, rest) => {
  seq++;
  events.push({ seq, line: `ev ${seq} t=${ms(now() - T0)} ${kind} face=${face} conn=${port}${rest ? ` ${rest}` : ''}` });
};
const esc = (s, max = 200) => {
  let o = '';
  for (let i = 0; i < s.length && i < max; i++) {
    const c = s.charCodeAt(i);
    if (c === 13) o += '\\r';
    else if (c === 10) o += '\\n';
    else if (c === 92 || c === 34 || c < 0x20 || c > 0x7e) o += `\\x${(c & 0xff).toString(16).padStart(2, '0')}`;
    else o += s[i];
  }
  if (s.length > max) o += `...(${s.length})`;
  return `"${o}"`;
};

function parseTarget(target) {
  const q = target.indexOf('?');
  return { path: q < 0 ? target : target.slice(0, q), params: new URLSearchParams(q < 0 ? '' : target.slice(q + 1)) };
}

// sub: the params under PREFIX ("a." or "b."), the prefix taken off; tag and
// slen carried.
function sub(params, prefix) {
  const o = new URLSearchParams();
  for (const [k, v] of params) if (k.startsWith(prefix)) o.set(k.slice(prefix.length), v);
  for (const k of ['tag', 'slen']) if (params.has(k) && !o.has(k)) o.set(k, params.get(k));
  return o;
}

const num = (p, k, d) => (p.has(k) ? Number(p.get(k)) : d);

// gen: the generated lines, each [name, value], of a spec, after FIXED, the
// framing line's bytes ([name, value] or null). A line's bytes are
// name + ": " + value + "\r\n".
function lineOf(name, vlen, ch) { return [name, ch.repeat(Math.max(0, vlen))]; }
const lineBytes = (l) => l[0].length + 2 + l[1].length + 2;
function gen(p, fixed) {
  const L = Math.max(13, num(p, 'line', 16));
  const same = p.get('same') === '1';
  const name = (i) => (same ? 'x-same' : `x-${String(i).padStart(6, '0')}`);
  const out = [];
  const one = (i, len) => { const nm = name(i); out.push(lineOf(nm, len - nm.length - 4, 'v')); };
  if (p.has('total')) {
    const T = num(p, 'total', 0);
    const slen = num(p, 'slen', 17);
    let left = T - slen - 2 - (fixed ? lineBytes(fixed) : 0) - (p.has('big') ? num(p, 'big', 0) : 0);
    let i = 1;
    while (left >= L) { one(i++, L); left -= L; }
    if (left > 0) {
      const nm = name(i);
      if (left >= nm.length + 4 + 1) one(i, left);
      else if (out.length) { const last = out[out.length - 1]; last[1] += 'v'.repeat(left); }
    }
  } else {
    const n = num(p, 'n', 1) - (fixed ? 1 : 0);
    for (let i = 1; i <= n; i++) one(i, L);
  }
  if (p.has('big')) { const B = num(p, 'big', 0); out.push(lineOf('x-big', B - 9, p.get('bigch') || 'a')); }
  return out;
}
function genPre(p) {
  if (!p.has('pre')) return [];
  return p.get('pre').split(',').filter(Boolean).map((s) => {
    const [c, n, l] = s.split(':').map(Number);
    const q = new URLSearchParams({ n: String(n), line: String(l || 16) });
    return { status: c, lines: gen(q, null) };
  });
}
function genTrailers(p) {
  if (!p.has('tn')) return null;
  const q = new URLSearchParams({ n: p.get('tn'), line: p.get('tl') || '16' });
  return gen(q, null);
}

const REASON = { 100: 'Continue', 103: 'Early Hints', 200: 'OK', 302: 'Found', 400: 'Bad Request', 401: 'Unauthorized', 404: 'Not Found', 417: 'Expectation Failed' };
const DIGEST = 'Digest realm="caps", nonce="0123456789abcdef", qop="auth", algorithm=MD5';

// ---------------------------------------------------------------- HTTP/1.1
function h1Head(status, lines) {
  let s = `HTTP/1.1 ${status} ${REASON[status] || 'Status'}\r\n`;
  for (const [k, v] of lines) s += `${k}: ${v}\r\n`;
  return `${s}\r\n`;
}

// h1Write: the response P's spec makes, with STATUS and EXTRA lines first;
// logs each head.
function h1Write(conn, tag, status, p, extra) {
  const pre = genPre(p);
  const trailers = genTrailers(p);
  const fixed = trailers ? ['transfer-encoding', 'chunked'] : ['content-length', '0'];
  const lines = [...extra, fixed, ...gen(p, fixed)];
  let out = '';
  const parts = [];
  for (const h of pre) { const s = h1Head(h.status, h.lines); out += s; parts.push(`${h.status}:${h.lines.length}:${s.length}`); }
  const head = h1Head(status, lines);
  out += head;
  parts.push(`${status}:${lines.length}:${head.length}`);
  if (trailers) {
    let t = '0\r\n';
    for (const [k, v] of trailers) t += `${k}: ${v}\r\n`;
    t += '\r\n';
    out += t;
    parts.push(`trailers:${trailers.length}:${t.length - 3}`);
  }
  conn.stream.write(Buffer.from(out, 'latin1'));
  ev('wrote', conn.face, conn.port, `tag=${tag} proto=h1 heads=[${parts.join(',')}] bytes=${out.length}`);
}

function serveH1(stream, face, port) {
  const conn = { face, stream, port, buf: Buffer.alloc(0), dead: false, need: 0, after: null, expectSeen: new Map() };
  stream.on('data', (chunk) => {
    conn.buf = conn.buf.length ? Buffer.concat([conn.buf, chunk]) : chunk;
    parseH1(conn);
  });
  stream.on('close', () => ev('close', face, port, 'h1'));
}

const expectCount = new Map();

function parseH1(conn) {
  for (;;) {
    if (conn.dead) return;
    if (conn.need > 0) {
      const k = Math.min(conn.need, conn.buf.length);
      conn.buf = conn.buf.subarray(k);
      conn.need -= k;
      if (conn.need > 0) return;
      if (conn.after) { const f = conn.after; conn.after = null; f(); }
      continue;
    }
    if (conn.skipIfBody) {
      // After a 417 answered before the body: the next bytes begin a request
      // (A to Z) when the client sent no body; else they are the body.
      if (conn.buf.length === 0) return;
      const c = conn.buf[0];
      const len = conn.skipIfBody;
      conn.skipIfBody = 0;
      if (!(c >= 0x41 && c <= 0x5a)) { conn.need = len; ev('note', conn.face, conn.port, `the client sent the body after the 417: ${len} bytes skipped`); continue; }
    }
    const end = conn.buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    const head = conn.buf.toString('latin1', 0, end);
    conn.buf = conn.buf.subarray(end + 4);
    const lines = head.split('\r\n');
    const [method, target] = lines[0].split(' ');
    const h = {};
    for (const l of lines.slice(1)) {
      const i = l.indexOf(':');
      if (i < 0) continue;
      h[l.slice(0, i).trim().toLowerCase()] = l.slice(i + 1).trim();
    }
    const { path, params } = parseTarget(target || '');
    const tag = params.get('tag') || '-';
    const cl = Number(h['content-length'] || '0');
    ev('req', conn.face, conn.port, `proto=h1 tag=${tag} ${method} ${path} auth=${h.authorization ? 'yes' : 'no'} expect=${h.expect || 'none'} cl=${cl}`);
    if (path === '/head') { conn.need = cl; h1Write(conn, tag, 200, params, []); continue; }
    if (path === '/auth') {
      conn.need = cl;
      if (h.authorization) h1Write(conn, tag, 200, sub(params, 'b.'), []);
      else h1Write(conn, tag, 401, sub(params, 'a.'), [['www-authenticate', DIGEST]]);
      continue;
    }
    if (path === '/redir') {
      conn.need = cl;
      const b = sub(params, 'b.');
      h1Write(conn, tag, 302, sub(params, 'a.'), [['location', `/head?${b.toString()}`]]);
      continue;
    }
    if (path === '/expect') {
      const k = expectCount.get(tag) || 0;
      expectCount.set(tag, k + 1);
      if (/100-continue/i.test(h.expect || '') && k === 0) {
        h1Write(conn, tag, 417, sub(params, 'a.'), []);
        conn.skipIfBody = cl;
        continue;
      }
      if (/100-continue/i.test(h.expect || '')) { conn.stream.write('HTTP/1.1 100 Continue\r\n\r\n'); ev('wrote', conn.face, conn.port, `tag=${tag} proto=h1 heads=[100:0:25] bytes=25`); }
      conn.need = cl;
      conn.after = () => h1Write(conn, tag, 200, sub(params, 'b.'), []);
      if (cl === 0) { const f = conn.after; conn.after = null; f(); }
      continue;
    }
    conn.need = cl;
    conn.stream.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n');
  }
}

// ---------------------------------------------------------------- HTTP/2
// The h2 face's limits from H2_LIMITS, a comma-separated list of send,
// pairs and settings (the caps stand-in's three: maxSendHeaderBlockLength 64
// MiB, maxHeaderListPairs 2^20, SETTINGS_MAX_HEADER_LIST_SIZE 64 MiB), or
// none for Node's defaults. M8 slice 2's variant of the caps stand-in.
const h2limits = (process.env.H2_LIMITS || 'send,pairs,settings').split(',');
const h2opts = { cert, key, ALPNProtocols: ['h2'] };
if (h2limits.includes('send')) h2opts.maxSendHeaderBlockLength = 64 << 20;
if (h2limits.includes('pairs')) h2opts.maxHeaderListPairs = 1 << 20;
if (h2limits.includes('settings')) h2opts.settings = { maxHeaderListSize: 64 << 20 };
process.stderr.write(`h2 limits: ${h2limits.join(',')}\n`);
const h2srv = http2.createSecureServer(h2opts);
h2srv.on('session', (session) => {
  sessions.add(session);
  const port = session.socket ? session.socket.remotePort : '?';
  session.on('close', () => sessions.delete(session));
  session.on('error', (e) => ev('session-error', 'h2', port, `code=${e.code} ${esc(e.message)}`));
  session.on('goaway', (code, last) => ev('goaway', 'h2', port, `received from the client, code=${code} last_stream=${last}`));
  session.on('frameError', (type, code, id) => ev('session-frame-error', 'h2', port, `type=${type} code=${code} stream=${id}`));
});
// The wire: each TCP connection's bytes, written and read, as it closes,
// with the tag of the last stream it carried. An open connection counts as
// a request in flight, so /events waits for libcurl's close of it.
const lastTag = new Map();
h2srv.on('connection', (tcp) => {
  const port = tcp.remotePort;
  track(tcp);
  inflight++;
  tcp.on('close', () => {
    inflight--;
    ev('h2-wire', 'h2', port, `tag=${lastTag.get(port) || '-'} wire_bytes_written=${tcp.bytesWritten} wire_bytes_read=${tcp.bytesRead}`);
    lastTag.delete(port);
  });
});
h2srv.on('sessionError', (e) => ev('server-session-error', 'h2', '-', `code=${e.code} ${esc(e.message)}`));
h2srv.on('tlsClientError', (e) => ev('tls-error', 'h2', '-', `code=${e.code} ${esc(e.message)}`));

const h2obj = (status, lines) => {
  const o = status === undefined ? {} : { ':status': status };
  for (const [k, v] of lines) {
    if (o[k] === undefined) o[k] = v;
    else if (Array.isArray(o[k])) o[k].push(v);
    else o[k] = [o[k], v];
  }
  return o;
};

h2srv.on('stream', (stream, headers) => {
  const session = stream.session;
  const port = session && session.socket ? session.socket.remotePort : '?';
  const { path, params } = parseTarget(headers[':path'] || '');
  const tag = params.get('tag') || '-';
  lastTag.set(port, tag);
  const parts = [];
  let errs = '';
  stream.on('error', (e) => { errs += ` stream-error=${e.code}`; });
  stream.on('frameError', (type, code, id) => { errs += ` frame-error=type${type}:code${code}:stream${id}`; });
  inflight++;
  stream.on('close', () => {
    inflight--;
    ev('h2-close', 'h2', port, `tag=${tag} heads=[${parts.join(',')}] rst=${stream.rstCode}${errs}`);
  });
  ev('req', 'h2', port, `proto=h2 stream=${stream.id} tag=${tag} ${headers[':method']} ${path} auth=${headers.authorization ? 'yes' : 'no'}`);
  let p = params;
  let status = 200;
  const extra = [];
  if (path === '/auth') {
    if (headers.authorization) p = sub(params, 'b.');
    else { p = sub(params, 'a.'); status = 401; extra.push(['www-authenticate', DIGEST]); }
  } else if (path === '/redir') {
    const b = sub(params, 'b.');
    p = sub(params, 'a.');
    status = 302;
    extra.push(['location', `/head?${b.toString()}`]);
  } else if (path !== '/head') {
    stream.respond({ ':status': 404, 'content-length': '0' }, { endStream: true, sendDate: false });
    return;
  }
  try {
    for (const hd of genPre(p)) {
      stream.additionalHeaders(h2obj(hd.status, hd.lines));
      parts.push(`${hd.status}:${hd.lines.length}`);
    }
    const trailers = genTrailers(p);
    const fixed = trailers ? null : ['content-length', '0'];
    const lines = [...extra, ...(fixed ? [fixed] : []), ...gen(p, fixed)];
    parts.push(`${status}:${lines.length}`);
    if (trailers) {
      stream.respond(h2obj(status, lines), { waitForTrailers: true, sendDate: false });
      stream.on('wantTrailers', () => {
        try { stream.sendTrailers(h2obj(undefined, trailers)); parts.push(`trailers:${trailers.length}`); } catch (e) { errs += ` sendTrailers-threw=${e.code}`; }
      });
      stream.end();
    } else {
      stream.respond(h2obj(status, lines), { endStream: true, sendDate: false });
    }
  } catch (e) {
    errs += ` respond-threw=${e.code}:${esc(e.message, 80)}`;
    try { stream.close(); } catch { /* gone */ }
  }
});

// ---------------------------------------------------------------- faces
const h1 = net.createServer((tcp) => {
  track(tcp);
  tcp.setNoDelay(true);
  ev('accept', 'h1', tcp.remotePort);
  serveH1(tcp, 'h1', tcp.remotePort);
});

const h1tls = tls.createServer({ cert, key, ALPNProtocols: ['http/1.1'] }, (ts) => {
  const port = ts.remotePort;
  ts.on('error', () => {});
  ts.setNoDelay(true);
  ev('tls', 'h1tls', port, `alpn=${ts.alpnProtocol} protocol=${ts.getProtocol()}`);
  serveH1(ts, 'h1tls', port);
});
h1tls.on('connection', (tcp) => { track(tcp); ev('accept', 'h1tls', tcp.remotePort); });
h1tls.on('tlsClientError', (e, ts) => ev('tls-error', 'h1tls', ts && ts.remotePort, `code=${e.code} ${esc(e.message)}`));

let armed = new URLSearchParams();
const proxy = net.createServer((c) => {
  track(c);
  c.setNoDelay(true);
  const port = c.remotePort;
  ev('accept', 'proxy', port);
  let buf = Buffer.alloc(0);
  const onData = (d) => {
    buf = buf.length ? Buffer.concat([buf, d]) : d;
    const end = buf.indexOf('\r\n\r\n');
    if (end < 0) return;
    c.off('data', onData);
    const head = buf.toString('latin1', 0, end);
    const rest = buf.subarray(end + 4);
    const [method, target] = head.split('\r\n')[0].split(' ');
    if (method !== 'CONNECT') { c.end('HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'); return; }
    const tport = Number((target || '').split(':').pop());
    const p = armed;
    const tag = p.get('tag') || '-';
    const lines = gen(p, null);
    const ans = `HTTP/1.1 200 Connection established\r\n${lines.map(([k, v]) => `${k}: ${v}\r\n`).join('')}\r\n`;
    const up = net.connect(tport, '127.0.0.1', () => {
      c.write(Buffer.from(ans, 'latin1'));
      ev('connect-answered', 'proxy', port, `tag=${tag} target=${target} lines=${lines.length} bytes=${ans.length}`);
      if (rest.length) up.write(rest);
      c.pipe(up);
      up.pipe(c);
    });
    track(up);
    up.on('close', () => c.destroy());
    c.on('close', () => up.destroy());
    c.on('end', () => c.destroy());
  };
  c.on('data', onData);
});

// ---------------------------------------------------------------- control
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
    else if (path === '/arm') { armed = params; body = 'armed\n'; }
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
const servers = [ctl, h1, h1tls, h2srv, proxy];
const ports = [];
for (const s of servers) ports.push(await listen(s));
process.stdout.write(`ctl=${ports[0]} h1=${ports[1]} h1tls=${ports[2]} h2=${ports[3]} proxy=${ports[4]}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const s of servers) s.close();
  process.exit(0);
});
