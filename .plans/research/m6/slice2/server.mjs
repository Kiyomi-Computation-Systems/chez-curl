// M6 slice 2's probe server (2026-10-30; the M6 plan, section 5.1): a copy
// of ../pause/server.mjs, which stays as it is, with a node:http face and the
// routes below marked (slice 2). Node 20 or later, ESM, the standard library
// only. Run with the PKI directory tests/make-test-pki.sh made:
//   node server.mjs PKI
// Writes one line on stdout, a flat JSON object, then serves until stdin
// ends:
//   {"node":"v24.18.0","pid":N,"http":"127.0.0.1:P","raw":...,"https":...,"h2":...}
//
// http   node:http, keep-alive as Node keeps it: /sink, /log and /conns
//        alone (slice 2);
// raw    plaintext HTTP/1.1 on node:net, every head written byte for byte,
//        keep-alive; https the same in TLS, ALPN http/1.1 alone (the pause
//        server's tls face, renamed); h2 node:http2's secure server, ALPN h2
//        alone.
//
// Every request may carry tag=TAG in its query. The server keeps each
// request's log lines under its tag, and GET /log?tag=TAG, on any face,
// answers them, once every request of that tag has ended (bounded at 3 s),
// with a count per path. Lines of a tag never fetched go to stderr as stdin
// ends, with every face's count per path, so nothing is lost.
//
// Routes:
//   /body?n=BYTES&mode=length|chunked|close&chunk=K&gap=MS&delay=MS[&gzip=1]
//     200; body byte i is i mod 251. Framed by Content-Length, chunked, or
//     the close (Connection: close, then FIN) on raw and tls; DATA frames on
//     h2, with content-length when mode=length. delay ms between the head
//     and the first body byte; then K bytes a write, gap ms apart. gzip=1
//     sends the body gzip-encoded, Content-Encoding: gzip, K bytes of it a
//     write. Logs: the bytes written when a write first returned false; each
//     drain wait (those of 5 ms or more one by one, as WRITTEN:MS, the
//     shorter counted and summed); the total time from the head's arrival to
//     the last write's flush. A write returns false once Node holds its
//     highWaterMark (16 KiB) unsent, so with K under 16 KiB the first false
//     marks the kernel no longer taking bytes at once; with K of 16 KiB or
//     more every write returns false.
//   /early?kind=100|103
//     an unsolicited 100 Continue, or a 103 Early Hints with a Link header,
//     then 50 ms on a 200 with "early\n". Every face sends both: on h2 by
//     additionalHeaders.
//   /empty
//     a 204, no body.
//   /sink[?want=N]
//     reads the request body whole (Content-Length, chunked, or h2 DATA to
//     the stream's end); a 100 Continue goes out first when the request
//     says Expect: 100-continue (raw, tls). Logs the method, Content-Length,
//     Transfer-Encoding, Expect and Content-Type as they came, the byte
//     count, the SHA-256, whether every byte is i mod 251, whether the SHA
//     is that of N such bytes, and each arrival as MS:BYTES, MS from the
//     head's arrival. Answers 200 with that summary, one line.
//   /close-after[?then=kill]
//     a keep-alive 200, Content-Length: 3, "ok\n"; then the server closes
//     that connection silently, 50 ms on (the TCP socket destroyed, a FIN;
//     on h2 the session destroyed). With then=kill it keeps the connection
//     instead, and the next request on it is read whole, its body too, then
//     cut with no answer: the TCP socket destroyed (on h2 the session), so
//     the client has sent every byte and meets the close reading the
//     answer. (A cut at the first body byte raced the client's send: one
//     run of four met it as a send failure, the rest as a recv failure.)
//   /log?tag=TAG   above; HTTP/1.0 is fine, and it closes.
//   /conns?prefix=P   (M6 slice 1) one line, "conns prefix=P n=N LIST": the
//     connections every tag beginning P used, each FACE:PORT, the client's
//     port, sorted; counted as /log is not, and taken as /log is. Nothing
//     else changed: no other answer reads the set it keeps.
// Slice 2 (2026-10-30):
//   /sink?arr=0   as /sink, its summary without each arrival, only their count.
//   /close-after?then=cuthead|resethead   as then=kill, but the next request
//     on the connection is cut (FIN, destroy) or reset (RST) as its head
//     arrives, no body read; on h2, the session destroyed as the next
//     stream's headers arrive.
//   /drop?after=N&how=fin|reset[&delay=MS]   this request, on its own
//     connection: once at least N body bytes arrived (N may be 0, at the
//     head), and DELAY ms more, its TCP socket destroyed (fin) or reset
//     (reset, resetAndDestroy of the TCP socket under TLS). raw, https and
//     h2 (the session's TCP socket).
//   /refuse?at=N  (h2) as /refuse, at N DATA bytes; at=0 refuses the stream
//     as its headers arrive, before any DATA.
//   /duplex?n=N&chunk=K&gap=MS  (h2) a 200 with content-length N as the
//     headers arrive, then N bytes of i mod 251, K a write, GAP ms apart,
//     each write that returns false awaiting its drain, while it reads the
//     request body; one line once both ends are done, with the body's
//     summary and the writes' backpressure.
// Round 2 (2026-10-29), each new route used only by round 2's cases:
//   /close-after?then=reset[&at=N]
//     as then=kill, but the next request on the connection is reset (RST,
//     resetAndDestroy) once at least N body bytes (default 32768) arrived.
//   /answer?status=S[&close=1]
//     answers S at once, as the head arrives, before any body; with close=1
//     it then ends the connection (FIN), else it keeps reading the body,
//     which it never answers again. On h2, respond and end the stream as
//     the headers arrive.
//   /expect417[?close=1]
//     a request with Expect: 100-continue gets 417 at once, its body never
//     read: keep-alive, so the next request on the connection is parsed;
//     with close=1, Connection: close and FIN. One without Expect is read
//     whole and answered as /sink. (libcurl 8.8.0's http.c retries a 417
//     only on a connection not marked to close.)
//   /refuse (h2)
//     the first stream of a tag is reset with REFUSED_STREAM once at least
//     32768 DATA bytes arrived; later ones are answered as /sink.
//   mono=1 on any request adds mono=NS, process.hrtime.bigint() at the
//   head's arrival, to its req line: CLOCK_MONOTONIC on Linux.
//   An h1 connection that closes holding unparsed bytes logs them, as
//   conn-close, under the tag of its last request.
// A write's first false: Node's own buffer fills first on tls and h2 (its
// highWaterMark, 64 KiB on Node 22 and later, 16 KiB on 20), so there the
// first long drain, WRITTEN:MS, marks where the kernel or HTTP/2 flow
// control stopped taking bytes; on raw, net.Socket writes straight to the
// kernel, and the first false marks it.
// Each request is counted on arrival of its head, by face and path, and
// each count per tag too. A request line in the log reads:
//   req FACE METHOD PATH #N conn=PORT
// where N counts that path on that face for that tag, and PORT is the
// client's port, so a reused connection shows.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import http2 from 'node:http2';
import net from 'node:net';
import tls from 'node:tls';
import zlib from 'node:zlib';

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

// tags: TAG -> { lines, inflight, fetched, counts }
const tags = new Map();
const tagOf = (t) => {
  let e = tags.get(t);
  if (!e) { e = { lines: [], inflight: 0, fetched: false, counts: new Map() }; tags.set(t, e); }
  return e;
};
const faceCounts = new Map();

function parseTarget(target) {
  const q = target.indexOf('?');
  const path = q < 0 ? target : target.slice(0, q);
  const params = new URLSearchParams(q < 0 ? '' : target.slice(q + 1));
  return { path, params };
}

// begin: a request's head has arrived. Answers a record whose log() keeps
// lines under its tag and whose end() closes it, once.
function begin(face, method, target, connPort, t0) {
  const { path, params } = parseTarget(target);
  const tag = params.get('tag') || '-';
  const r = { face, method, path, params, tag, t0: t0 === undefined ? now() : t0, ended: false, dispatching: false };
  if (path === '/log' || path === '/conns') { r.log = () => {}; r.end = () => {}; return r; }
  const e = tagOf(tag);
  const fk = `${face} ${path}`;
  const n = (e.counts.get(fk) || 0) + 1;
  e.counts.set(fk, n);
  faceCounts.set(fk, (faceCounts.get(fk) || 0) + 1);
  r.log = (line) => e.lines.push(line);
  r.end = () => { if (!r.ended) { r.ended = true; e.inflight--; } };
  e.inflight++;
  r.log(`req ${face} ${method} ${path} #${n} conn=${connPort} at=${ms(r.t0 - T0)}${params.get('mono') === '1' ? ` mono=${process.hrtime.bigint()}` : ''}`);
  if (!e.conns) e.conns = new Set();
  e.conns.add(`${face}:${connPort}`);
  r.entry = e;
  return r;
}

const patternCache = new Map();
function pattern(n) {
  let b = patternCache.get(n);
  if (!b) {
    b = Buffer.alloc(n);
    for (let i = 0; i < n; i++) b[i] = i % 251;
    patternCache.set(n, b);
  }
  return b;
}
const gzipCache = new Map();
function gzipped(n) {
  let b = gzipCache.get(n);
  if (!b) { b = zlib.gzipSync(pattern(n)); gzipCache.set(n, b); }
  return b;
}
const shaOf = (buf) => createHash('sha256').update(buf).digest('hex');

// A body under test: count, hash, pattern check, arrivals.
function bodyRec() {
  return {
    bytes: 0, hash: createHash('sha256'), bad: -1, arrivals: [],
    add(buf) {
      for (let i = 0; i < buf.length && this.bad < 0; i++) {
        if (buf[i] !== (this.bytes + i) % 251) this.bad = this.bytes + i;
      }
      this.bytes += buf.length;
      this.hash.update(buf);
    },
  };
}

function sinkSummary(r, h, b) {
  const sha = b.hash.digest('hex');
  const want = r.params.get('want');
  const wantOk = want == null ? '-' : (shaOf(pattern(Number(want))) === sha ? 'ok' : 'bad');
  const arr = r.params.get('arr') === '0' ? 'omitted' : b.arrivals.map(([t, n]) => `${ms(t)}:${n}`).join(',');
  const one = (k) => (h[k] == null ? '-' : String(h[k]).replace(/\s/g, '_'));
  const span = b.arrivals.length ? `first=${ms(b.arrivals[0][0])} last=${ms(b.arrivals[b.arrivals.length - 1][0])}` : 'first=- last=-';
  return `sink ${r.face} method=${r.method} cl=${one('content-length')} te=${one('transfer-encoding')} expect=${one('expect')} ct=${one('content-type')} bytes=${b.bytes} sha=${sha} pattern=${b.bad < 0 ? 'ok' : `bad@${b.bad}`} want_sha=${wantOk} arrivals=${b.arrivals.length} ${span} arr=${arr || '-'}`;
}

// pump: write DATA to W, K bytes a write, GAP ms apart, after DELAY ms,
// logging backpressure. W: { write(buf, cb) -> bool, drain() -> Promise,
// gone() -> bool, frame(buf) -> buf }.
async function pump(r, w, data, k, gap, delay) {
  const rec = { written: 0, firstFalse: null, long: [], shortN: 0, shortMs: 0, aborted: 0, flushed: null };
  let flushed;
  rec.lastP = new Promise((res) => { flushed = res; });
  if (delay > 0) await sleep(delay);
  if (data.length === 0) flushed();
  for (let off = 0; off < data.length; off += k) {
    if (w.gone()) { rec.aborted = 1; flushed(); break; }
    const piece = data.subarray(off, Math.min(off + k, data.length));
    const last = off + k >= data.length;
    const ok = w.write(w.frame(piece), last ? () => { rec.flushed = now(); flushed(); } : undefined);
    rec.written = off + piece.length;
    if (!ok) {
      if (rec.firstFalse === null) rec.firstFalse = rec.written;
      const t = now();
      const why = await w.drain();
      const d = now() - t;
      if (d >= 5) rec.long.push(`${rec.written}:${ms(d)}`); else { rec.shortN++; rec.shortMs += d; }
      if (why === 'close') { rec.aborted = rec.written < data.length ? 1 : 0; flushed(); if (rec.aborted) break; }
    }
    if (gap > 0 && !last) await sleep(gap);
  }
  return rec;
}

function bodyLine(r, data, rec, k, gap, delay, mode, gz) {
  const total = rec.flushed == null ? '-' : ms(rec.flushed - r.t0);
  return `body ${r.face} n=${r.params.get('n')} mode=${mode} chunk=${k} gap=${gap} delay=${delay} gzip=${gz ? 1 : 0} wire=${data.length} written=${rec.written} first_false=${rec.firstFalse === null ? 'none' : rec.firstFalse} drains_long=${rec.long.length} [${rec.long.join(',')}] drains_short=${rec.shortN} sum=${ms(rec.shortMs)}ms total=${total}ms aborted=${rec.aborted}`;
}

function bodyParams(r) {
  const n = Number(r.params.get('n') || '0');
  const mode = r.params.get('mode') || 'length';
  const k = Math.max(1, Number(r.params.get('chunk') || '16384'));
  const gap = Number(r.params.get('gap') || '0');
  const delay = Number(r.params.get('delay') || '0');
  const gz = r.params.get('gzip') === '1';
  return { n, mode, k, gap, delay, gz, data: gz ? gzipped(n) : pattern(n) };
}

function answerConns(params) {
  const prefix = params.get('prefix') || '';
  const all = new Set();
  for (const [tag, e] of tags) if (tag.startsWith(prefix) && e.conns) for (const c of e.conns) all.add(c);
  return `conns prefix=${prefix} n=${all.size} ${[...all].sort().join(',') || '-'}\n`;
}

async function answerLog(params) {
  const tag = params.get('tag') || '-';
  const e = tagOf(tag);
  const t = now();
  while (e.inflight > 0 && now() - t < 3000) await sleep(5);
  e.fetched = true;
  const lines = [...e.lines];
  if (e.inflight > 0) lines.push(`log: ${e.inflight} request(s) of this tag still open after 3 s`);
  const cs = [...e.counts].map(([k, v]) => `${k.replace(' ', ':')}=${v}`).join(' ');
  lines.push(`count ${cs || 'none'}`);
  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------- HTTP/1.1
function serveH1(stream, tcp, face) {
  const conn = { face, stream, tcp, buf: Buffer.alloc(0), req: null, busy: false, killNext: false, resetNext: 0, cutHeadNext: null, port: tcp.remotePort, bytesIn: 0, lastR: null };
  stream.on('data', (chunk) => {
    conn.bytesIn += chunk.length;
    conn.buf = conn.buf.length ? Buffer.concat([conn.buf, chunk]) : chunk;
    parseH1(conn, now());
  });
  stream.on('close', () => {
    if (conn.lastR && !conn.req && conn.buf.length > 0) {
      conn.lastR.log(`conn-close ${face} conn=${conn.port} bytes_in=${conn.bytesIn} unparsed=${conn.buf.length}`);
    }
    if (conn.req) {
      const q = conn.req;
      q.r.log(`aborted ${face} ${q.r.path} conn=${conn.port} head+${q.b.bytes} body bytes, then the connection closed`);
      q.r.end();
    }
    if (conn.onClose) conn.onClose();
  });
}

function parseH1(conn, t) {
  for (;;) {
    if (conn.busy || conn.dead) return;
    if (!conn.req) {
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
        const name = l.slice(0, i).trim().toLowerCase();
        const v = l.slice(i + 1).trim();
        h[name] = h[name] == null ? v : `${h[name]},${v}`;
      }
      const r = begin(conn.face, method, target, conn.port, t);
      const q = { r, h, b: bodyRec(), framing: 'none', need: 0, cstate: 'size', cleft: 0, kill: conn.killNext, resetAt: conn.resetNext };
      conn.killNext = false;
      conn.resetNext = 0;
      conn.lastR = r;
      if (/chunked/i.test(h['transfer-encoding'] || '')) q.framing = 'chunked';
      else if (h['content-length'] != null) { q.framing = 'length'; q.need = Number(h['content-length']); }
      conn.req = q;
      if (conn.cutHeadNext) {
        const how = conn.cutHeadNext;
        conn.cutHeadNext = null;
        r.log(`cut-head ${conn.face} ${r.path} conn=${conn.port} at its head, framing ${q.framing}, by ${how === 'reset' ? 'RST' : 'FIN'}, at ${ms(now() - r.t0)}ms`);
        r.end();
        conn.req = null;
        conn.dead = true;
        if (how === 'reset') conn.tcp.resetAndDestroy(); else conn.tcp.destroy();
        return;
      }
      if (r.path === '/drop') {
        q.dropAt = Number(r.params.get('after') || '0');
        q.dropHow = r.params.get('how') === 'reset' ? 'reset' : 'fin';
        q.dropDelay = Number(r.params.get('delay') || '0');
      }
      if (r.path === '/expect417' && /100-continue/i.test(h.expect || '')) {
        const close = r.params.get('close') === '1';
        r.log(`expect417 ${conn.face} conn=${conn.port} answered 417 to Expect: ${h.expect}, framing ${q.framing}, ${close ? 'and closed' : 'keep-alive'}`);
        r.end();
        conn.req = null;
        if (close) {
          conn.stream.end('HTTP/1.1 417 Expectation Failed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
          conn.dead = true;
          return;
        }
        conn.stream.write('HTTP/1.1 417 Expectation Failed\r\nContent-Length: 0\r\n\r\n');
        continue;
      }
      if (r.path === '/answer') {
        const st = Number(r.params.get('status') || '413');
        const close = r.params.get('close') === '1';
        const body = `answer ${st}\n`;
        const out = `HTTP/1.1 ${st} ${st === 200 ? 'OK' : 'Payload Too Large'}\r\nContent-Length: ${body.length}\r\n${close ? 'Connection: close\r\n' : ''}\r\n${body}`;
        if (close) conn.stream.end(out); else conn.stream.write(out);
        q.answered = true;
        r.log(`answer ${conn.face} conn=${conn.port} sent ${st} as the head arrived, framing ${q.framing} cl=${h['content-length'] || '-'}, ${close ? 'then FIN' : 'keep-alive'}`);
      }
      if (/100-continue/i.test(h.expect || '')) {
        conn.stream.write('HTTP/1.1 100 Continue\r\n\r\n');
        r.log(`sent 100 Continue ${conn.face} for Expect: ${h.expect}`);
      }
    }
    const q = conn.req;
    const before = q.b.bytes;
    let complete = false;
    if (q.framing === 'none') complete = true;
    else if (q.framing === 'length') {
      const k = Math.min(q.need - q.b.bytes, conn.buf.length);
      if (k > 0) { q.b.add(conn.buf.subarray(0, k)); conn.buf = conn.buf.subarray(k); }
      complete = q.b.bytes >= q.need;
    } else {
      for (;;) {
        if (q.cstate === 'size') {
          const i = conn.buf.indexOf('\r\n');
          if (i < 0) break;
          const n = parseInt(conn.buf.toString('latin1', 0, i).split(';')[0], 16);
          conn.buf = conn.buf.subarray(i + 2);
          if (n === 0) q.cstate = 'trailer'; else { q.cleft = n; q.cstate = 'data'; }
        } else if (q.cstate === 'data') {
          const k = Math.min(q.cleft, conn.buf.length);
          if (k === 0) break;
          q.b.add(conn.buf.subarray(0, k));
          conn.buf = conn.buf.subarray(k);
          q.cleft -= k;
          if (q.cleft === 0) q.cstate = 'crlf';
        } else if (q.cstate === 'crlf') {
          if (conn.buf.length < 2) break;
          conn.buf = conn.buf.subarray(2);
          q.cstate = 'size';
        } else {
          const i = conn.buf.indexOf('\r\n');
          if (i < 0) break;
          conn.buf = conn.buf.subarray(i + 2);
          if (i === 0) { complete = true; break; }
        }
      }
    }
    if (q.b.bytes > before) q.b.arrivals.push([t - q.r.t0, q.b.bytes - before]);
    if (q.dropAt != null && !q.dropArmed && q.b.bytes >= q.dropAt) {
      q.dropArmed = true;
      const go = () => {
        q.r.log(`drop ${conn.face} conn=${conn.port} after ${q.b.bytes} body bytes (after=${q.dropAt} delay=${q.dropDelay}), framing ${q.framing}, by ${q.dropHow === 'reset' ? 'RST' : 'FIN'}, at ${ms(now() - q.r.t0)}ms`);
        q.r.end();
        conn.req = null;
        conn.dead = true;
        if (q.dropHow === 'reset') conn.tcp.resetAndDestroy(); else conn.tcp.destroy();
      };
      if (q.dropDelay > 0) { setTimeout(go, q.dropDelay); return; }
      go();
      return;
    }
    if (q.dropArmed) return;
    if (q.resetAt && q.b.bytes >= q.resetAt) {
      q.r.log(`reset ${conn.face} ${q.r.path} conn=${conn.port} after its head and ${q.b.bytes} body bytes, at ${ms(now() - q.r.t0)}ms; RST`);
      q.r.end();
      conn.req = null;
      conn.dead = true;
      conn.tcp.resetAndDestroy();
      return;
    }
    if (!complete) return;
    if (q.answered) {
      q.r.log(`answer ${conn.face} body read whole after the early answer: ${q.b.bytes} bytes`);
      q.r.end();
      conn.req = null;
      continue;
    }
    if (q.kill) { kill(conn, q); return; }
    conn.req = null;
    conn.busy = true;
    dispatchH1(conn, q).catch((err) => { q.r.log(`error ${String(err)}`); q.r.end(); conn.tcp.destroy(); });
  }
}

function kill(conn, q) {
  q.r.log(`killed ${conn.face} ${q.r.path} conn=${conn.port} after reading it whole, its head and ${q.b.bytes} body bytes, at ${ms(now() - q.r.t0)}ms; no answer`);
  q.r.end();
  conn.req = null;
  conn.dead = true;
  conn.tcp.destroy();
}

function h1Writer(conn, chunked) {
  return {
    write: (buf, cb) => conn.stream.write(buf, cb),
    drain: () => new Promise((res) => {
      const d = () => { conn.stream.off('close', c); res('drain'); };
      const c = () => { conn.stream.off('drain', d); res('close'); };
      conn.stream.once('drain', d);
      conn.stream.once('close', c);
    }),
    gone: () => conn.stream.destroyed,
    frame: chunked ? (b) => Buffer.concat([Buffer.from(`${b.length.toString(16)}\r\n`), b, Buffer.from('\r\n')]) : (b) => b,
  };
}

function next(conn) {
  conn.busy = false;
  setImmediate(() => parseH1(conn, now()));
}

async function dispatchH1(conn, q) {
  const { r } = q;
  const s = conn.stream;
  switch (r.path) {
    case '/body': {
      const p = bodyParams(r);
      let head = 'HTTP/1.1 200 OK\r\n';
      if (p.gz) head += 'Content-Encoding: gzip\r\n';
      if (p.mode === 'chunked') head += 'Transfer-Encoding: chunked\r\n';
      else if (p.mode === 'close') head += 'Connection: close\r\n';
      else head += `Content-Length: ${p.data.length}\r\n`;
      s.write(`${head}\r\n`);
      const rec = await pump(r, h1Writer(conn, p.mode === 'chunked'), p.data, p.k, p.gap, p.delay);
      if (!rec.aborted && !s.destroyed) {
        await new Promise((res) => {
          s.once('close', res);
          if (p.mode === 'chunked') s.write('0\r\n\r\n', () => { rec.flushed = now(); res(); });
          else rec.lastP.then(res);
        });
      }
      if (p.mode === 'close' && !rec.aborted) s.end();
      r.log(bodyLine(r, p.data, rec, p.k, p.gap, p.delay, p.mode, p.gz));
      r.end();
      if (p.mode !== 'close' && !rec.aborted) next(conn);
      return;
    }
    case '/early': {
      const kind = r.params.get('kind');
      if (kind === '103') s.write('HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload; as=style\r\n\r\n');
      else s.write('HTTP/1.1 100 Continue\r\n\r\n');
      await sleep(50);
      s.write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nearly\n');
      r.log(`early ${r.face} kind=${kind} sent`);
      r.end();
      next(conn);
      return;
    }
    case '/empty':
      s.write('HTTP/1.1 204 No Content\r\n\r\n');
      r.log(`empty ${r.face} 204 sent`);
      r.end();
      next(conn);
      return;
    case '/sink':
    case '/refuse':
    case '/expect417': {
      const line = sinkSummary(r, q.h, q.b);
      r.log(line);
      const body = `${line}\n`;
      s.write(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
      r.end();
      next(conn);
      return;
    }
    case '/close-after': {
      s.write('HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\n');
      if (r.params.get('then') === 'cuthead' || r.params.get('then') === 'resethead') {
        conn.cutHeadNext = r.params.get('then') === 'resethead' ? 'reset' : 'fin';
        r.log(`close-after ${r.face} then=${r.params.get('then')} conn=${conn.port}: the next request on it is cut at its head`);
        r.end();
        next(conn);
      } else if (r.params.get('then') === 'reset') {
        conn.resetNext = Number(r.params.get('at') || '32768');
        r.log(`close-after ${r.face} then=reset conn=${conn.port}: the next request on it is reset after ${conn.resetNext} body bytes`);
        r.end();
        next(conn);
      } else if (r.params.get('then') === 'kill') {
        conn.killNext = true;
        r.log(`close-after ${r.face} then=kill conn=${conn.port}: the next request on it is cut`);
        r.end();
        next(conn);
      } else {
        r.log(`close-after ${r.face} then=fin conn=${conn.port}: closing 50 ms on`);
        r.end();
        next(conn);
        setTimeout(() => { conn.dead = true; conn.tcp.destroy(); }, 50);
      }
      return;
    }
    case '/log': {
      const body = await answerLog(r.params);
      s.end(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`);
      return;
    }
    case '/conns': {
      const body = answerConns(r.params);
      s.end(`HTTP/1.1 200 OK\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`);
      return;
    }
    default:
      s.write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n');
      r.log(`404 ${r.face} ${r.path}`);
      r.end();
      next(conn);
  }
}

const raw = net.createServer((tcp) => { track(tcp); serveH1(tcp, tcp, 'raw'); });
const tlsFace = net.createServer((tcp) => {
  track(tcp);
  const t = new tls.TLSSocket(tcp, { isServer: true, cert, key, ALPNProtocols: ['http/1.1'] });
  t.on('error', () => {});
  serveH1(t, tcp, 'https');
});

// ---------------------------------------------------------------- HTTP/2
const h2server = http2.createSecureServer({ cert, key, ALPNProtocols: ['h2'], allowHTTP1: false });
const h2tcp = new Map();
h2server.on('connection', (tcp) => { track(tcp); h2tcp.set(tcp.remotePort, tcp); tcp.on('close', () => h2tcp.delete(tcp.remotePort)); });
h2server.on('tlsClientError', () => {});
h2server.on('session', (session) => {
  sessions.add(session);
  session.on('close', () => sessions.delete(session));
  session.on('error', () => {});
});
h2server.on('stream', (stream, headers) => {
  stream.on('error', () => {});
  const session = stream.session;
  const port = session.socket.remotePort;
  const r = begin('h2', headers[':method'], headers[':path'], port);
  const b = bodyRec();
  if (session.cutHeadNext) {
    session.cutHeadNext = false;
    r.log(`cut-head h2 ${r.path} conn=${port} at its headers: the session destroyed`);
    r.end();
    session.destroy();
    return;
  }
  const refuseAt = r.path === '/refuse' ? Number(r.params.get('at') || '32768') : -1;
  if (refuseAt === 0 && !r.entry.refusedOnce) {
    r.refused = true;
    r.entry.refusedOnce = true;
    r.log(`refuse h2 conn=${port} RST_STREAM REFUSED_STREAM at its headers, before any DATA`);
    r.end();
    stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
    return;
  }
  const dropAt = r.path === '/drop' ? Number(r.params.get('after') || '0') : -1;
  const dropHow = r.params.get('how') === 'reset' ? 'reset' : 'fin';
  const dropDelay = Number(r.params.get('delay') || '0');
  const drop = () => {
    if (r.dropped) return;
    r.dropped = true;
    const go = () => {
      r.log(`drop h2 conn=${port} after ${b.bytes} DATA bytes (after=${dropAt} delay=${dropDelay}), by ${dropHow === 'reset' ? 'RST' : 'FIN'} of its TCP socket, at ${ms(now() - r.t0)}ms`);
      r.end();
      const tcp = h2tcp.get(port);
      if (!tcp) { session.destroy(); return; }
      if (dropHow === 'reset') tcp.resetAndDestroy(); else tcp.destroy();
    };
    if (dropDelay > 0) setTimeout(go, dropDelay); else go();
  };
  if (dropAt === 0) { drop(); return; }
  if (r.path === '/duplex') { duplexH2(stream, headers, r, b, port); return; }
  if (r.path === '/answer') {
    const st = Number(r.params.get('status') || '413');
    const body = `answer ${st}\n`;
    stream.respond({ ':status': st, 'content-length': String(body.length) });
    stream.end(body);
    r.answered = true;
    r.log(`answer h2 conn=${port} sent ${st} as the headers arrived, content-length ${headers['content-length'] || '-'}`);
  }
  stream.on('data', (chunk) => {
    b.arrivals.push([now() - r.t0, chunk.length]);
    b.add(chunk);
    if (dropAt > 0 && !r.dropped && b.bytes >= dropAt) { drop(); return; }
    if (r.path === '/refuse' && !r.refused && !r.entry.refusedOnce && b.bytes >= refuseAt) {
      r.refused = true;
      r.entry.refusedOnce = true;
      r.log(`refuse h2 conn=${port} RST_STREAM REFUSED_STREAM after ${b.bytes} DATA bytes`);
      r.end();
      stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
    }
  });
  stream.on('close', () => {
    if (!r.ended && !r.dispatching) { r.log(`aborted h2 ${r.path} conn=${port} head+${b.bytes} body bytes, then the stream closed`); r.end(); }
  });
  stream.on('end', () => {
    if (r.refused || r.dropped) return;
    if (r.answered) { r.log(`answer h2 body read whole after the early answer: ${b.bytes} bytes`); r.end(); return; }
    if (session.killNext) {
      session.killNext = false;
      r.log(`killed h2 ${r.path} conn=${port} after reading it whole, its head and ${b.bytes} body bytes; no answer`);
      r.end();
      session.destroy();
      return;
    }
    dispatchH2(stream, headers, r, b, session).catch((err) => { r.log(`error ${String(err)}`); r.end(); });
  });
});

async function dispatchH2(stream, headers, r, b, session) {
  switch (r.path) {
    case '/body': {
      const p = bodyParams(r);
      const h = { ':status': 200 };
      if (p.gz) h['content-encoding'] = 'gzip';
      if (p.mode === 'length') h['content-length'] = String(p.data.length);
      stream.respond(h);
      const w = {
        write: (buf, cb) => stream.write(buf, cb),
        drain: () => new Promise((res) => {
          const d = () => { stream.off('close', c); res('drain'); };
          const c = () => { stream.off('drain', d); res('close'); };
          stream.once('drain', d);
          stream.once('close', c);
        }),
        gone: () => stream.destroyed || stream.closed,
        frame: (x) => x,
      };
      r.dispatching = true;
      const rec = await pump(r, w, p.data, p.k, p.gap, p.delay);
      if (!rec.aborted && !stream.destroyed) {
        await new Promise((res) => { stream.once('close', res); stream.end(() => { rec.flushed = now(); res(); }); });
      }
      r.log(bodyLine(r, p.data, rec, p.k, p.gap, p.delay, `h2-${p.mode}`, p.gz));
      r.end();
      return;
    }
    case '/early': {
      const kind = r.params.get('kind');
      try {
        if (kind === '103') stream.additionalHeaders({ ':status': 103, link: '</style.css>; rel=preload; as=style' });
        else stream.additionalHeaders({ ':status': 100 });
        r.log(`early h2 kind=${kind} sent`);
      } catch (err) {
        r.log(`early h2 kind=${kind} refused by node: ${err.code || err.message}`);
      }
      await sleep(50);
      stream.respond({ ':status': 200, 'content-length': '6' });
      stream.end('early\n');
      r.end();
      return;
    }
    case '/empty':
      stream.respond({ ':status': 204 }, { endStream: true });
      r.log('empty h2 204 sent');
      r.end();
      return;
    case '/sink':
    case '/refuse': {
      const line = sinkSummary(r, headers, b);
      r.log(line);
      const body = `${line}\n`;
      stream.respond({ ':status': 200, 'content-length': String(Buffer.byteLength(body)) });
      stream.end(body);
      r.end();
      return;
    }
    case '/close-after': {
      stream.respond({ ':status': 200, 'content-length': '3' });
      stream.end('ok\n');
      if (r.params.get('then') === 'cuthead' || r.params.get('then') === 'resethead') {
        session.cutHeadNext = true;
        r.log(`close-after h2 then=${r.params.get('then')} conn=${session.socket.remotePort}: the next stream on it is cut at its headers`);
      } else if (r.params.get('then') === 'kill') {
        session.killNext = true;
        r.log(`close-after h2 then=kill conn=${session.socket.remotePort}: the next stream on it is cut`);
      } else {
        r.log(`close-after h2 then=fin conn=${session.socket.remotePort}: destroying the session 50 ms on`);
        setTimeout(() => session.destroy(), 50);
      }
      r.end();
      return;
    }
    case '/log': {
      const body = await answerLog(r.params);
      stream.respond({ ':status': 200, 'content-length': String(Buffer.byteLength(body)) });
      stream.end(body);
      return;
    }
    default:
      stream.respond({ ':status': 404, 'content-length': '0' });
      stream.end();
      r.log(`404 h2 ${r.path}`);
      r.end();
  }
}

// duplexH2: the 200 and its body at once, while the request body is read.
function duplexH2(stream, headers, r, b, port) {
  const session = stream.session;
  const n = Number(r.params.get('n') || '0');
  const k = Math.max(1, Number(r.params.get('chunk') || '16384'));
  const gap = Number(r.params.get('gap') || '0');
  const data = pattern(n);
  let bodyDone = false, respDone = false, rec = null, ended = null;
  const finish = () => {
    if (!bodyDone || !respDone || r.ended) return;
    r.log(`duplex h2 conn=${port} body_end=${ended == null ? '-' : ms(ended - r.t0)} ${sinkSummary(r, headers, b)}`);
    r.log(`duplex h2 conn=${port} ${bodyLine(r, data, rec, k, gap, 0, 'h2-length', false)}`);
    r.end();
  };
  stream.on('data', (chunk) => { b.arrivals.push([now() - r.t0, chunk.length]); b.add(chunk); });
  stream.on('end', () => { ended = now(); bodyDone = true; finish(); });
  stream.on('close', () => { bodyDone = true; respDone = true; if (!r.ended) { r.log(`duplex h2 conn=${port} the stream closed: body ${b.bytes} bytes, response written ${rec ? rec.written : 0}`); r.end(); } });
  stream.respond({ ':status': 200, 'content-length': String(n) });
  // At 1 s: the flow-control windows as this server's nghttp2 sees them.
  // A stream localWindowSize back near its initial 65,535 after the body's
  // first 65,535 bytes were consumed means this server granted more window
  // (a WINDOW_UPDATE); outboundQueueSize 0 means nothing it sent waits.
  setTimeout(() => {
    if (r.ended) return;
    const ss = stream.destroyed ? {} : stream.state;
    const se = session.destroyed ? {} : session.state;
    r.log(`duplex-state h2 conn=${port} at=1000 body_bytes=${b.bytes} written=${rec ? rec.written : 'pumping'} stream.localWindowSize=${ss.localWindowSize} session.localWindowSize=${se.localWindowSize} session.effectiveLocalWindowSize=${se.effectiveLocalWindowSize} session.remoteWindowSize=${se.remoteWindowSize} session.outboundQueueSize=${se.outboundQueueSize} session.effectiveRecvDataLength=${se.effectiveRecvDataLength}`);
  }, 1000);
  const w = {
    write: (buf, cb) => stream.write(buf, cb),
    drain: () => new Promise((res) => {
      const d = () => { stream.off('close', c); res('drain'); };
      const c = () => { stream.off('drain', d); res('close'); };
      stream.once('drain', d);
      stream.once('close', c);
    }),
    gone: () => stream.destroyed || stream.closed,
    frame: (x) => x,
  };
  pump(r, w, data, k, gap, 0).then((x) => {
    rec = x;
    if (!x.aborted && !stream.destroyed) stream.end(() => { x.flushed = now(); respDone = true; finish(); });
    else { respDone = true; finish(); }
  });
}

// ---------------------------------------------------------------- http (node:http)
const httpFace = http.createServer((req, res) => {
  req.on('error', () => {});
  res.on('error', () => {});
  const t0 = now();
  const r = begin('http', req.method, req.url, req.socket.remotePort, t0);
  const b = bodyRec();
  if (r.path === '/log' || r.path === '/conns') {
    const go = async () => {
      const body = r.path === '/log' ? await answerLog(r.params) : answerConns(r.params);
      res.writeHead(200, { 'content-length': String(Buffer.byteLength(body)), connection: 'close' });
      res.end(body);
    };
    go();
    return;
  }
  req.on('data', (chunk) => { b.arrivals.push([now() - r.t0, chunk.length]); b.add(chunk); });
  req.on('end', () => {
    if (r.path === '/sink') {
      const line = sinkSummary(r, req.headers, b);
      r.log(line);
      const body = `${line}\n`;
      res.writeHead(200, { 'content-length': String(Buffer.byteLength(body)) });
      res.end(body);
    } else {
      res.writeHead(404, { 'content-length': '0' });
      res.end();
      r.log(`404 http ${r.path}`);
    }
    r.end();
  });
  req.on('close', () => { if (!r.ended) { r.log(`aborted http ${r.path} head+${b.bytes} body bytes, then the request closed`); r.end(); } });
});
httpFace.on('connection', track);

const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const ports = [await listen(httpFace), await listen(raw), await listen(tlsFace), await listen(h2server)];
process.stdout.write(`${JSON.stringify({ node: process.version, pid: process.pid, http: `127.0.0.1:${ports[0]}`, raw: `127.0.0.1:${ports[1]}`, https: `127.0.0.1:${ports[2]}`, h2: `127.0.0.1:${ports[3]}` })}\n`);
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  for (const [tag, e] of tags) {
    if (e.fetched || tag === '-') continue;
    const cs = [...e.counts].map(([k, v]) => `${k.replace(' ', ':')}=${v}`).join(' ');
    process.stderr.write(`unfetched tag=${tag} count ${cs}\n`);
  }
  const cs = [...faceCounts].sort().map(([k, v]) => `${k.replace(' ', ':')}=${v}`).join(' ');
  process.stderr.write(`counts ${cs}\n`);
  for (const s of sessions) s.destroy();
  for (const s of sockets) s.destroy();
  for (const s of [httpFace, raw, tlsFace, h2server]) s.close();
  process.exit(0);
});
