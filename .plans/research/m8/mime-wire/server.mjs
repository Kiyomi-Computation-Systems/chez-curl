// M8's mime wire probe server (2026-11-06; the M8 plan's measurements, area
// multipart: what a curl_mime body set by MIMEPOST puts on the wire). Node 20
// or later, ESM, the standard library only. Faces, PKI and lifecycle are M7's
// HTTP/2 probe's (../../m7/http2/server.mjs); the byte log is new.
//
//   node server.mjs PKI
//     serves, with PKI's good.pem and good.key (tests/make-test-pki.sh);
//     writes one line on stdout, the ports, then serves until stdin ends:
//       ctl=PORT h1=PORT tlsh1=PORT tlsh2=PORT h2c=PORT
//
// Faces:
//   h1     plaintext HTTP/1.1 on node:net, each request parsed from its bytes
//          by hand, keep-alive.
//   tlsh1  TLS, the good leaf; ALPN http/1.1 when offered, else refused;
//          then the h1 handler.
//   tlsh2  TLS, the good leaf; ALPN h2 when offered, else http/1.1, else
//          refused; h2 goes to node:http2.
//   h2c    plaintext, handed to node:http2: HTTP/2 by prior knowledge.
//   ctl    plaintext control, never logged:
//            GET /log?tag=TAG  every line logged under TAG, once no request of
//                              TAG is open (bounded at 6 s), then a line
//                              "count n=K open=J".
//
// Every route on h1, tlsh1, tlsh2 and h2c is one handler. Its query:
//   tag=TAG   names the request's log lines (default "-");
//   cont=1    the default: a request whose Expect holds 100-continue, in any
//             case, is answered 100 Continue as its head arrives (HTTP/2: an
//             informational :status 100 by additionalHeaders);
//   cont=0    no 100 is ever sent: the server waits for the body.
// The body is read whole by its framing, Content-Length or chunked over
// HTTP/1.1 (no framing: no body), DATA frames over HTTP/2; then 200, "ok\n",
// Content-Length 3, no body for HEAD. A body not whole 4 s after its head is
// logged as such and answered anyway, with Connection: close over HTTP/1.1.
//
// Log lines, under the request's tag, in order:
//   req     n=N face=F proto=h1|h2 conn=PORT method=M target="..."
//           version=V (h1)
//   head    h1: bytes=N and the whole head, request line to the blank line,
//           as it arrived; h2: n=K and each header in rawHeaders' order,
//           pseudo-headers too, as "name: value" joined by " | "
//   hdr     the request's content-type, content-length, transfer-encoding and
//           expect, each "none" when absent, and how many of each arrived
//   ctype   the content-type's boundary parameters: every boundary= in it, in
//           order, the first one's length and its form (24 dashes then N hex
//           or alphanumeric characters), the first taken as the boundary
//   continue  sent at t=MS (from the head's arrival), or withheld (cont=0),
//           or not asked
//   body    framing=length|chunked|none|h2 bytes=N (the body's own bytes)
//           wire=N (h1: with chunk framing) chunks=[sizes] (h1 chunked) or
//           data_events=K (h2), sha256 (first 16 hex), the head's arrival to
//           the first body byte (first_ms) and to the last (last_ms),
//           incomplete=0|1, and stdin=1 when the probe's stdin marker
//           (PROBE-STDIN-MARKER) is in it, readfn=1 when its read callback's
//           marker (READFUNCTION-BODY) is
//   bodybytes  the whole body, when it is 8 KiB or less
//   mp      the body read as multipart/form-data by the first boundary sent:
//           parse=ok parts=K, or parse=fail why=...; and the boundary the
//           body's own first line names, which may differ
//   mpl     the body read as RFC 2046 lets a reader, by the same boundary,
//           a preamble skipped: the preamble's length, the parts found and
//           each one's name
//   part    one per part: its header block as it arrived, its data's length,
//           sha256 and first 48 bytes
//   pline   one per header line of each part, as it arrived
//   answer  the status sent, and when
//   close   a connection that closed with a request open
//
// Escaping, in every log line: printable ASCII as is, but \ as \\ and " as
// \"; CR as \r, LF as \n; every other byte as \xNN, lower case: the probe's
// own rule.
import { createHash } from 'node:crypto';
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
const BODY_BOUND = 4000;

const escBuf = (b, max = Infinity) => {
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
  if (b.length > n) o += `...(${b.length} bytes)`;
  return `"${o}"`;
};
const escStr = (s, max) => escBuf(Buffer.from(String(s), 'latin1'), max);
const sha = (b) => createHash('sha256').update(b).digest('hex').slice(0, 16);

const sockets = new Set();
const sessions = new Set();
const track = (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); s.on('error', () => {}); };

// ---------------------------------------------------------------- the log
const logs = new Map();   // tag -> lines
const open = new Map();   // tag -> requests open
let reqN = 0;
function tagLines(tag) {
  let l = logs.get(tag);
  if (!l) { l = []; logs.set(tag, l); }
  return l;
}
function newReq(face, proto, conn, method, target, version) {
  const q = target.indexOf('?');
  const params = new URLSearchParams(q < 0 ? '' : target.slice(q + 1));
  const r = {
    n: ++reqN, face, proto, conn, method, target, tag: params.get('tag') || '-',
    cont: params.get('cont') !== '0', tHead: now(), tFirst: null, tLast: null, done: false,
  };
  r.log = (s) => tagLines(r.tag).push(`${s}`);
  open.set(r.tag, (open.get(r.tag) || 0) + 1);
  r.log(`req n=${r.n} t=${ms(r.tHead - T0)} face=${face} proto=${proto} conn=${conn} method=${escStr(method)} target=${escStr(target)}${version ? ` version=${escStr(version)}` : ''}`);
  return r;
}
function endReq(r) {
  if (r.done) return;
  r.done = true;
  open.set(r.tag, (open.get(r.tag) || 1) - 1);
}

// headerInfo: the hdr and ctype lines, from LIST, [name, value] pairs, the
// value a latin1 string.
function headerInfo(r, list) {
  const pick = (n) => list.filter(([k]) => k.toLowerCase() === n).map(([, v]) => v);
  const one = (n) => { const vs = pick(n); return vs.length ? `${escStr(vs.join(' , '))}(x${vs.length})` : 'none'; };
  r.log(`hdr content-type=${one('content-type')} content-length=${one('content-length')} transfer-encoding=${one('transfer-encoding')} expect=${one('expect')}`);
  const ct = pick('content-type')[0];
  r.boundary = null;
  if (ct === undefined) { r.log('ctype none'); return; }
  const all = [];
  const re = /(?:^|;)\s*boundary\s*=\s*("([^"]*)"|[^;\s]*)/gi;
  let m;
  while ((m = re.exec(ct))) all.push(m[2] !== undefined ? m[2] : m[1]);
  const media = ct.split(';')[0].trim();
  if (!all.length) { r.log(`ctype media=${escStr(media)} boundaries=0`); return; }
  const b = all[0];
  r.boundary = b;
  const form = /^-{24}[0-9a-f]+$/.test(b) ? `24-dashes+${b.length - 24}-hex`
    : /^-{24}[0-9A-Za-z]+$/.test(b) ? `24-dashes+${b.length - 24}-alnum` : 'other';
  r.log(`ctype media=${escStr(media)} boundaries=${all.length} [${all.map((x) => escStr(x)).join(',')}] first_len=${b.length} first_form=${form}`);
}

// lenient: the mpl line, BODY read as RFC 2046 lets a reader: by the first
// boundary sent, skipping a preamble, the first delimiter at the body's
// start or after a CRLF. Each part's name is its Content-Disposition's
// name="..." parameter as it arrived.
function lenient(r, body) {
  const delim = Buffer.from(`--${r.boundary}`, 'latin1');
  const sep = Buffer.concat([Buffer.from('\r\n'), delim]);
  let pos = body.subarray(0, delim.length).equals(delim) ? 0 : -1;
  if (pos < 0) { const i = body.indexOf(sep); if (i >= 0) pos = i + 2; }
  if (pos < 0) { r.log('mpl delimiters=0'); return; }
  const preamble = pos;
  const names = [];
  pos += delim.length;
  let closed = 0;
  for (;;) {
    const two = body.subarray(pos, pos + 2).toString('latin1');
    if (two === '--') { closed = 1; break; }
    if (two !== '\r\n') break;
    pos += 2;
    const next = body.indexOf(sep, pos);
    if (next < 0) break;
    const head = body.subarray(pos, next).toString('latin1').split('\r\n\r\n')[0];
    const m = /name="([^"]*)"/.exec(head);
    names.push(m ? escStr(m[1]) : 'none');
    pos = next + sep.length;
  }
  r.log(`mpl preamble=${preamble} parts=${names.length} closed=${closed} names=[${names.join(',')}]`);
}

// multipart: the mp, mpl, part and pline lines for BODY read by the
// boundary r.boundary.
function multipart(r, body) {
  const firstEnd = body.indexOf('\r\n');
  const firstLine = body.subarray(0, firstEnd < 0 ? Math.min(body.length, 120) : firstEnd);
  const own = firstLine.length > 2 && firstLine[0] === 45 && firstLine[1] === 45 ? escBuf(firstLine.subarray(2), 120) : 'none';
  const sent = r.boundary === null ? 'none' : escStr(r.boundary);
  const fail = (why) => r.log(`mp parse=fail why=${why} boundary_sent=${sent} body_first_line_boundary=${own} same=${own === sent ? 1 : 0}`);
  if (r.boundary === null) { fail('no-boundary-in-content-type'); return; }
  const delim = Buffer.from(`--${r.boundary}`, 'latin1');
  if (!body.subarray(0, delim.length).equals(delim)) { fail('body-does-not-begin-with-the-delimiter'); lenient(r, body); return; }
  const sep = Buffer.concat([Buffer.from('\r\n'), delim]);
  const parts = [];
  let pos = delim.length;
  for (;;) {
    const two = body.subarray(pos, pos + 2).toString('latin1');
    if (two === '--') {
      const epi = body.subarray(pos + 2);
      r.log(`mp parse=ok parts=${parts.length} boundary_sent=${sent} body_first_line_boundary=${own} same=${own === sent ? 1 : 0} epilogue=${escBuf(epi, 64)}`);
      break;
    }
    if (two !== '\r\n') { fail(`no-CRLF-after-a-delimiter-at-${pos}`); lenient(r, body); return; }
    pos += 2;
    const next = body.indexOf(sep, pos);
    if (next < 0) { fail(`no-delimiter-after-part-${parts.length + 1}`); lenient(r, body); return; }
    parts.push(body.subarray(pos, next));
    pos = next + sep.length;
  }
  lenient(r, body);
  parts.forEach((p, i) => {
    const he = p.indexOf('\r\n\r\n');
    const head = he < 0 ? p : p.subarray(0, he);
    const data = he < 0 ? Buffer.alloc(0) : p.subarray(he + 4);
    r.log(`part ${i + 1} headers=${escBuf(head, 2048)} header_end=${he < 0 ? 'none' : 'found'} data_len=${data.length} data_sha=${sha(data)} data_head=${escBuf(data, 48)}`);
    let k = 0;
    for (let off = 0; off <= head.length;) {
      const e = head.indexOf('\r\n', off);
      const line = head.subarray(off, e < 0 ? head.length : e);
      if (line.length || e >= 0) r.log(`pline ${i + 1}.${++k} ${escBuf(line, 2048)}`);
      if (e < 0) break;
      off = e + 2;
    }
  });
}

function bodyDone(r, body, extra) {
  const marker = (s) => (body.indexOf(s) >= 0 ? 1 : 0);
  r.log(`body ${extra} bytes=${body.length} sha=${sha(body)} first_ms=${r.tFirst === null ? '-' : ms(r.tFirst - r.tHead)} last_ms=${r.tLast === null ? '-' : ms(r.tLast - r.tHead)} incomplete=${r.incomplete ? 1 : 0} stdin=${marker('PROBE-STDIN-MARKER')} readfn=${marker('READFUNCTION-BODY')}`);
  if (body.length <= 8192) r.log(`bodybytes ${escBuf(body)}`);
  if (body.length) multipart(r, body);
  else r.log('mp empty-body');
}

// ---------------------------------------------------------------- HTTP/1.1
function serveH1(stream, face, port) {
  const c = { face, stream, port, buf: Buffer.alloc(0), r: null, st: 'head' };
  stream.on('data', (chunk) => { c.buf = c.buf.length ? Buffer.concat([c.buf, chunk]) : chunk; pumpH1(c); });
  stream.on('close', () => {
    if (c.r && !c.r.done) {
      c.r.log(`close the connection closed with the request open, in state ${c.st}, ${c.got ? c.got.length : 0} body bytes read`);
      clearTimeout(c.timer);
      endReq(c.r);
    }
  });
}

function answerH1(c, incomplete) {
  const r = c.r;
  clearTimeout(c.timer);
  r.incomplete = incomplete;
  bodyDone(r, Buffer.concat(c.got), c.framing === 'chunked' ? `framing=chunked wire=${c.wire} chunks=[${c.chunks.join(',')}] trailer=${escBuf(c.trailer || Buffer.alloc(0), 200)}` : `framing=${c.framing} wire=${c.wire}`);
  const close = incomplete ? 'Connection: close\r\n' : '';
  const head = `HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n${close}\r\n`;
  c.stream.write(r.method === 'HEAD' ? head : `${head}ok\n`);
  r.log(`answer status=200 at_ms=${ms(now() - r.tHead)}${incomplete ? ' (body incomplete; connection closed)' : ''}`);
  endReq(r);
  c.r = null;
  c.st = 'head';
  if (incomplete) { c.st = 'dead'; c.stream.end(); }
}

function pumpH1(c) {
  for (;;) {
    if (c.st === 'dead') return;
    if (c.st === 'head') {
      const end = c.buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const raw = c.buf.subarray(0, end + 4);
      c.buf = c.buf.subarray(end + 4);
      const text = raw.toString('latin1');
      const lines = text.slice(0, -4).split('\r\n');
      const [method = '', target = '', version = ''] = lines[0].split(' ');
      const r = newReq(c.face, 'h1', c.port, method, target, version);
      r.log(`head bytes=${raw.length} ${escBuf(raw)}`);
      const list = [];
      for (const l of lines.slice(1)) {
        const i = l.indexOf(':');
        if (i < 0) { list.push([l, '']); continue; }
        list.push([l.slice(0, i).trim(), l.slice(i + 1).trim()]);
      }
      headerInfo(r, list);
      const get = (n) => list.filter(([k]) => k.toLowerCase() === n).map(([, v]) => v);
      const te = get('transfer-encoding').join(',');
      const cl = get('content-length');
      c.r = r;
      c.got = [];
      c.wire = 0;
      c.chunks = [];
      c.trailer = null;
      if (/chunked/i.test(te)) { c.framing = 'chunked'; c.st = 'chunk-size'; }
      else if (cl.length) { c.framing = 'length'; c.need = Number(cl[0]); c.st = c.need > 0 ? 'length' : 'done'; }
      else { c.framing = 'none'; c.st = 'done'; }
      const ex = get('expect').join(',');
      if (/100-continue/i.test(ex)) {
        if (r.cont && c.st !== 'done') { c.stream.write('HTTP/1.1 100 Continue\r\n\r\n'); r.log(`continue sent at_ms=${ms(now() - r.tHead)}`); }
        else r.log(`continue withheld (${r.cont ? 'no body framed' : 'cont=0'})`);
      } else r.log('continue not-asked');
      c.timer = setTimeout(() => { if (c.r === r && !r.done) { r.log(`bound the body was not whole ${BODY_BOUND} ms after the head`); answerH1(c, true); } }, BODY_BOUND);
      continue;
    }
    if (c.st === 'done') { answerH1(c, false); continue; }
    if (!c.buf.length) return;
    const r = c.r;
    if (r.tFirst === null) r.tFirst = now();
    if (c.st === 'length') {
      const take = Math.min(c.need, c.buf.length);
      c.got.push(c.buf.subarray(0, take));
      c.wire += take;
      c.buf = c.buf.subarray(take);
      c.need -= take;
      r.tLast = now();
      if (c.need === 0) c.st = 'done';
      continue;
    }
    if (c.st === 'chunk-size') {
      const e = c.buf.indexOf('\r\n');
      if (e < 0) return;
      const line = c.buf.subarray(0, e).toString('latin1');
      c.wire += e + 2;
      c.buf = c.buf.subarray(e + 2);
      const size = parseInt(line.split(';')[0].trim(), 16);
      c.chunks.push(Number.isNaN(size) ? `bad:${escStr(line)}` : size);
      if (Number.isNaN(size)) { r.log(`chunk a bad chunk-size line ${escStr(line)}`); answerH1(c, true); return; }
      if (size === 0) { c.st = 'trailer'; c.tstart = c.wire; continue; }
      c.need = size;
      c.st = 'chunk-data';
      continue;
    }
    if (c.st === 'chunk-data') {
      const take = Math.min(c.need, c.buf.length);
      c.got.push(c.buf.subarray(0, take));
      c.wire += take;
      c.buf = c.buf.subarray(take);
      c.need -= take;
      r.tLast = now();
      if (c.need === 0) c.st = 'chunk-crlf';
      continue;
    }
    if (c.st === 'chunk-crlf') {
      if (c.buf.length < 2) return;
      c.wire += 2;
      c.buf = c.buf.subarray(2);
      c.st = 'chunk-size';
      continue;
    }
    if (c.st === 'trailer') {
      const e = c.buf.indexOf('\r\n');
      if (e < 0) return;
      const line = c.buf.subarray(0, e);
      c.trailer = c.trailer ? Buffer.concat([c.trailer, line, Buffer.from('\r\n')]) : (line.length ? Buffer.concat([line, Buffer.from('\r\n')]) : Buffer.alloc(0));
      c.wire += e + 2;
      c.buf = c.buf.subarray(e + 2);
      r.tLast = now();
      if (!line.length) c.st = 'done';
      continue;
    }
    return;
  }
}

// ---------------------------------------------------------------- HTTP/2
const h2srv = http2.createServer();
const meta = new WeakMap();
let pending = null;
h2srv.on('session', (session) => {
  const m = pending || { face: '?', port: '?' };
  meta.set(session, m);
  sessions.add(session);
  session.on('close', () => sessions.delete(session));
  session.on('error', () => {});
});
function h2Over(sock, face, port) {
  pending = { face, port };
  h2srv.emit('connection', sock);
  pending = null;
}
h2srv.on('stream', (stream, headers, flags, rawHeaders) => {
  const m = meta.get(stream.session) || { face: '?', port: '?' };
  const raw = Array.isArray(rawHeaders) ? rawHeaders : Object.entries(headers).flat();
  const list = [];
  for (let i = 0; i + 1 < raw.length; i += 2) list.push([String(raw[i]), String(raw[i + 1])]);
  const r = newReq(m.face, 'h2', m.port, headers[':method'] || '', headers[':path'] || '', '');
  r.log(`head n=${list.length} stream=${stream.id} ${escStr(list.map(([k, v]) => `${k}: ${v}`).join(' | '), 4096)}`);
  headerInfo(r, list);
  const ex = list.filter(([k]) => k.toLowerCase() === 'expect').map(([, v]) => v).join(',');
  if (/100-continue/i.test(ex)) {
    if (r.cont) { stream.additionalHeaders({ ':status': 100 }); r.log(`continue sent at_ms=${ms(now() - r.tHead)}`); }
    else r.log('continue withheld (cont=0)');
  } else r.log('continue not-asked');
  const got = [];
  let events = 0;
  let finished = false;
  const finish = (incomplete, why) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    r.incomplete = incomplete;
    if (why) r.log(why);
    bodyDone(r, Buffer.concat(got), `framing=h2 data_events=${events} end_stream_seen=${incomplete ? 0 : 1}`);
    if (!stream.destroyed && !stream.closed) {
      try {
        stream.respond({ ':status': 200, 'content-type': 'text/plain', 'content-length': '3' }, { endStream: r.method === 'HEAD' });
        if (r.method !== 'HEAD') stream.end('ok\n');
        r.log(`answer status=200 at_ms=${ms(now() - r.tHead)}`);
      } catch (e) { r.log(`answer failed ${escStr(e.message)}`); }
    } else r.log('answer none: the stream was gone');
    endReq(r);
  };
  const timer = setTimeout(() => finish(true, `bound the body was not whole ${BODY_BOUND} ms after the head`), BODY_BOUND);
  stream.on('data', (d) => { events++; if (r.tFirst === null) r.tFirst = now(); r.tLast = now(); got.push(d); });
  stream.on('end', () => finish(false));
  stream.on('error', (e) => { r.log(`stream-error code=${e.code} ${escStr(e.message, 200)}`); });
  stream.on('close', () => { if (!finished) finish(true, `close the stream closed before its end, rstCode=${stream.rstCode}`); });
});

// ---------------------------------------------------------------- faces
const h1 = net.createServer((tcp) => { track(tcp); tcp.setNoDelay(true); serveH1(tcp, 'h1', tcp.remotePort); });

function tlsFace(face, choose) {
  const srv = tls.createServer({ cert, key, ALPNCallback: ({ protocols }) => choose(protocols) });
  srv.on('connection', (tcp) => track(tcp));
  srv.on('tlsClientError', () => {});
  srv.on('secureConnection', (ts) => {
    ts.on('error', () => {});
    if (ts.alpnProtocol === 'h2') h2Over(ts, face, ts.remotePort);
    else { ts.setNoDelay(true); serveH1(ts, face, ts.remotePort); }
  });
  return srv;
}
const tlsh1 = tlsFace('tlsh1', (ps) => (ps.includes('http/1.1') ? 'http/1.1' : undefined));
const tlsh2 = tlsFace('tlsh2', (ps) => (ps.includes('h2') ? 'h2' : ps.includes('http/1.1') ? 'http/1.1' : undefined));
const h2c = net.createServer((c) => { track(c); h2Over(c, 'h2c', c.remotePort); });

// ---------------------------------------------------------------- control
const ctl = net.createServer((s) => {
  s.on('error', () => {});
  let buf = '';
  let answered = false;
  s.on('data', async (d) => {
    buf += d.toString('latin1');
    if (answered || buf.indexOf('\r\n\r\n') < 0) return;
    answered = true;
    const target = buf.split(' ')[1] || '/';
    const q = target.indexOf('?');
    const path = q < 0 ? target : target.slice(0, q);
    const params = new URLSearchParams(q < 0 ? '' : target.slice(q + 1));
    let body;
    if (path === '/log') {
      const tag = params.get('tag') || '-';
      const t = now();
      while ((open.get(tag) || 0) > 0 && now() - t < 6000) await sleep(5);
      const ls = logs.get(tag) || [];
      logs.delete(tag);
      body = `${ls.join('\n')}${ls.length ? '\n' : ''}count n=${ls.length} open=${open.get(tag) || 0}\n`;
    } else body = 'no such control path\n';
    s.end(`HTTP/1.0 200 OK\r\nContent-Length: ${Buffer.byteLength(body, 'latin1')}\r\n\r\n${body}`);
  });
});

const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const servers = [ctl, h1, tlsh1, tlsh2, h2c];
const ports = [];
for (const s of servers) ports.push(await listen(s));
process.stdout.write(`ctl=${ports[0]} h1=${ports[1]} tlsh1=${ports[2]} tlsh2=${ports[3]} h2c=${ports[4]}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const [tag, ls] of logs) if (ls.length) process.stderr.write(`unfetched tag ${tag}: ${ls.length} lines\n`);
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const s of servers) s.close();
  process.exit(0);
});
