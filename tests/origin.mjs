// tests/origin.mjs: chez-curl's test origin (ADR-0005, amended; M1 plan,
// sections 3, 4 and 8). One ES module, Node's standard library only, for Node
// 20 and later (measured on 20.10.0 and 24.18.0).
//
// The contract:
//   - `node tests/origin.mjs [--pki DIR]`. With no argument it serves the
//     plaintext faces. --pki DIR adds the TLS faces, which read their leaves
//     from DIR, as tests/make-test-pki.sh makes it. Any other argument, or a
//     PKI file it cannot read or use, exits 2, naming it on stderr.
//   - Each face listens on 127.0.0.1, port 0, so the OS picks the port.
//   - Once every face listens, it writes one line on stdout, a flat JSON
//     object, and nothing else ever goes there:
//       {"node":"v24.18.0","pid":12345,"http":"127.0.0.1:40001","raw":"127.0.0.1:40002","h2c":"127.0.0.1:40003"}
//     node is process.version and pid process.pid. Each face is ADDRESS:PORT,
//     both read back from server.address() once it listens. The keys come in
//     this order: node, pid, http, raw, h2c, then, with --pki, https,
//     https-expired, https-wrong-host, https-untrusted, raw-tls and h2.
//   - It exits 0 when its stdin ends, after closing every listener and
//     destroying every open socket and HTTP/2 session, of every face. Its
//     stdin ends once every process holding the pipe's write end has gone:
//     its suite, and, when the suite dies, any probe or command the suite was
//     running, each ended by its own bound.
//   - A client that misbehaves ends only its own connection: a reset, a
//     half-close, garbage, a TLS error, an HTTP/2 session or stream error.
//     Any other error goes to stderr and exits 1, so a suite sees the origin
//     die, not hang.
//
// The faces:
//   http  node:http. Deterministic: no Date, headers in a fixed order, and
//         Connection: close back when Node will close.
//           GET /status/CODE             200-599: status CODE, body "status CODE\n"
//           GET /redirect/CODE?to=TARGET 300-308: Location: TARGET, decoded,
//                                        body "redirect CODE\n"
//           GET /chunked                 three writes, each its own chunk
//           ANY /echo                    the request as Node parsed it
//           anything else                404, body "not found\n"
//         A target in absolute form, http://AUTHORITY then its path, as a
//         client sends one to a proxy, is routed by that path, / when it
//         has none, so the face can stand in for a plain proxy; /echo's
//         first line shows the target as it came. https:// is not taken.
//         204 and 304 carry no body and no Content-Length; 205 carries
//         Content-Length: 0 and no body.
//   raw   node:net. Reads the request head, up to the first CRLF CRLF, and
//         gives up on one longer than 64 KiB. Plays the script that
//         /raw/NAME?QUERY names, then closes: no keep-alive. An unknown NAME
//         or parameter, or one out of range, gets the fixed 400. A client
//         that half-closes after its request still gets its whole script
//         (allowHalfOpen); once the script has ended or stalls, the client's
//         FIN closes the connection. /raw/pause-mid-body?ms=N, 1 to 60000,
//         writes a head with Content-Length: 11 and hello, waits N ms, then
//         writes " world" and ends: a script still playing, between two of
//         its writes, for as long as a check needs.
//         /raw/reset-after-pause?ms=N, 1 to 60000, writes the same head and
//         hello, waits N ms, then writes " wor" and resets: its last write
//         and its reset come together, after a pause long enough for a
//         check to stop the client across both.
//         /raw/location?code=CODE[&ms=N][&to=BYTES]... reads its own query:
//         code once, 200 to 599; ms at most once, 0 to 60000, 0 when left
//         out; to any number of times, each percent-decoded, %XX in either
//         case, every other char its own byte, so any byte can be sent. It
//         waits N ms, then writes "HTTP/1.1 CODE Redirect", a Location header
//         for each to, in order, its value the bytes as they are, then
//         Content-Length: 0 and Connection: close, and ends. A pair that is
//         no NAME=VALUE, an unknown name, a repeat of code or ms, a value out
//         of range, and a malformed %, get the fixed 400.
//         /raw/retry?key=KEY&fail=N&how=HOW[&code=CODE][&after=BYTES][&then=THEN]
//         fails the first N requests for KEY, then answers 200, or stalls.
//         Its query, every pair NAME=VALUE, each name once at most: key, 1
//         to 64 of A-Z, a-z, 0-9, ., _ and -; fail, 0 to 100; how, close,
//         reset or status; code, 200 to 599, with how=status alone, which
//         needs it; after, with how=status alone, percent-decoded as
//         location's to is; then, ok, the default, or stall. The
//         origin counts each request for KEY whose query it takes, on raw
//         and raw-tls alike, and C is the count with this one. While C is N
//         or less, the request fails by HOW: close ends the connection with
//         nothing written; reset resets it with nothing written; status
//         writes "HTTP/1.1 CODE Retry", a Retry-After header holding after's
//         bytes as they are when after is given, then Content-Length,
//         Connection: close and the body "attempt C\n", and ends. Past N,
//         with then=ok, it writes "HTTP/1.1 200 OK", Content-Length,
//         Connection: close and the body "attempt C\n", and ends; with
//         then=stall it writes nothing, and leaves the connection to the
//         client. A query it refuses gets the fixed 400, and counts nothing.
//         /raw/attempts?key=KEY, KEY as retry takes it, writes "HTTP/1.1
//         200 OK", Content-Length, Connection: close and the body "attempts
//         C\n", C the count so far, 0 for a key never counted, and ends. It
//         counts nothing. A count lives as long as the origin.
//   h2c   node:http2, plaintext, by prior knowledge: the HTTP/2 routes.
//   With --pki DIR:
//   https, https-expired, https-wrong-host, https-untrusted
//         node:https, serving DIR's good, expired, wrong-host and untrusted
//         leaf, with ALPN http/1.1 alone: http's routes and bytes.
//   raw-tls
//         node:net, each socket wrapped in a server tls.TLSSocket with the
//         good leaf and ALPN http/1.1: raw's scripts. A reset resets the TCP
//         socket under the TLS one: resetAndDestroy() on a TLS socket throws
//         ERR_INVALID_HANDLE_TYPE (measured).
//   h2    node:http2, secure, with the good leaf, ALPN h2 alone and no
//         HTTP/1.1: the HTTP/2 routes. A client that does not choose h2 has
//         its socket destroyed at once, with no byte written. Without the
//         unknownProtocol listener, Node 20.10.0 and 24.18.0 write
//         "HTTP/1.0 403 Forbidden ... Missing ALPN Protocol ..." to it, then
//         close (measured), and a client would read that as a response.
//
// The HTTP/2 routes follow http's, with the same paths, ranges and bodies:
// /status/CODE answers :status, then content-length; /redirect/CODE?to=TARGET
// answers :status, location, content-length; /echo's body is each rawHeaders
// pair as "name: value\n", pseudo-headers included, in order, then "\n", then
// the request body. 204 and 304 send no content-length and no body, 205
// content-length: 0. Anything else, /chunked included, is 404, "not found\n".
// No date, and no header beyond these.
//
// The suites (tests/test-origin.sps, tests/test-origin-tls.sps) hold their
// own copy of each scenario's bytes, written separately from these. They
// never read them from here, so changing a script here fails them.

import { readFileSync } from 'node:fs';
import http from 'node:http';
import http2 from 'node:http2';
import https from 'node:https';
import net from 'node:net';
import process from 'node:process';
import tls from 'node:tls';

const HOST = '127.0.0.1';

// fatal: the one way out on an error that is not a client's: stderr, exit 1.
function fatal(what, err) {
  process.stderr.write(`origin: ${what}: ${(err && err.stack) || err}\n`);
  process.exit(1);
}

process.on('uncaughtException', (err) => fatal('uncaught exception', err));
process.on('unhandledRejection', (err) => fatal('unhandled rejection', err));

// refuse: a wrong argument or PKI file: stderr, exit 2.
function refuse(problem) {
  process.stderr.write(`origin: ${problem}\nusage: node tests/origin.mjs [--pki DIR]\n`);
  process.exit(2);
}

const args = process.argv.slice(2);
let pki = null;
if (args.length === 2 && args[0] === '--pki') {
  if (args[1] === '') refuse('--pki takes DIR, a directory, and was given an empty one');
  pki = args[1];
} else if (args.length !== 0) {
  refuse(`it takes no argument, or --pki DIR, and was given ${JSON.stringify(args)}`);
}

// leaf: NAME's certificate and key from the PKI directory, as a server's
// options and as a secure context. Exits 2 on a file it cannot read, or a
// pair that is no certificate and its key.
function leaf(name) {
  const read = (file) => {
    const path = `${pki}/${file}`;
    try {
      return readFileSync(path);
    } catch (err) {
      return refuse(`cannot read the PKI file ${path}: ${err.code || err.message}`);
    }
  };
  const options = { cert: read(`${name}.pem`), key: read(`${name}.key`) };
  try {
    return { options, context: tls.createSecureContext(options) };
  } catch (err) {
    return refuse(`the PKI files ${pki}/${name}.pem and ${pki}/${name}.key are not a certificate and its key: ${err.code || err.message}`);
  }
}

// Every open socket and HTTP/2 session, of every face, so that stdin's end
// can destroy them. A TLS face's sockets are tracked twice: the TCP socket,
// and the TLS socket over it.
const sockets = new Set();
function track(socket) {
  sockets.add(socket);
  socket.on('close', () => sockets.delete(socket));
}
const sessions = new Set();
function trackSession(session) {
  sessions.add(session);
  session.on('close', () => sessions.delete(session));
  // An HTTP/2 error ends this session only.
  session.on('error', () => session.destroy());
}

// --- the routes -----------------------------------------------------------

// route: what the well-formed faces answer for the request target URL.
// TARGET must decode to printable ASCII with no space, which is what a header
// value can carry unchanged.
function route(target) {
  if (typeof target !== 'string') return { kind: 'not-found' };
  const absolute = /^http:\/\/[^/?#]*(.*)$/.exec(target);
  const url = absolute ? (absolute[1].startsWith('/') ? absolute[1] : `/${absolute[1]}`) : target;
  const at = url.indexOf('?');
  const path = at < 0 ? url : url.slice(0, at);
  const query = at < 0 ? undefined : url.slice(at + 1);
  let m;
  if ((m = /^\/status\/([2-5][0-9][0-9])$/.exec(path)) && query === undefined) {
    return { kind: 'status', code: Number(m[1]) };
  }
  if ((m = /^\/redirect\/(30[0-8])$/.exec(path))) {
    const target = redirectTarget(query);
    return target === null ? { kind: 'not-found' } : { kind: 'redirect', code: Number(m[1]), target };
  }
  if (path === '/chunked' && query === undefined) return { kind: 'chunked' };
  if (path === '/echo') return { kind: 'echo' };
  return { kind: 'not-found' };
}

// redirectTarget: the decoded TARGET of a query that is exactly to=TARGET,
// or null.
function redirectTarget(query) {
  if (query === undefined || !query.startsWith('to=')) return null;
  const raw = query.slice(3);
  if (raw === '' || raw.includes('&')) return null;
  let target;
  try {
    target = decodeURIComponent(raw);
  } catch {
    return null;
  }
  return /^[\x21-\x7e]+$/.test(target) ? target : null;
}

// noBody: the statuses that carry no body.
const noBody = new Set([204, 304]);

// --- the well-formed HTTP/1.1 faces: http and the https faces -------------

// send: writes one whole response, its headers in the order given, then
// Connection, from Node's own decision whether to keep the connection.
function send(res, status, headers, body) {
  res.sendDate = false;
  const connection = res.shouldKeepAlive ? 'keep-alive' : 'close';
  res.writeHead(status, [...headers, 'Connection', connection]);
  res.end(body);
}

// text: a whole response with the body BODY, or none for a status that
// carries none.
function text(res, status, body, headers = []) {
  if (noBody.has(status)) {
    send(res, status, headers, undefined);
  } else if (status === 205) {
    send(res, status, [...headers, 'Content-Length', '0'], undefined);
  } else {
    const bytes = Buffer.from(body, 'latin1');
    send(res, status, [...headers, 'Content-Length', String(bytes.length)], bytes);
  }
}

function respond(req, res, body) {
  const r = route(req.url);
  switch (r.kind) {
    case 'status':
      return text(res, r.code, `status ${r.code}\n`);
    case 'redirect':
      return text(res, r.code, `redirect ${r.code}\n`, ['Location', r.target]);
    case 'chunked': {
      res.sendDate = false;
      const connection = res.shouldKeepAlive ? 'keep-alive' : 'close';
      res.writeHead(200, ['Transfer-Encoding', 'chunked', 'Connection', connection]);
      res.write('alpha\n');
      res.write('beta\n');
      res.write('gamma\n');
      return res.end();
    }
    case 'echo': {
      let lines = `${req.method} ${req.url} HTTP/${req.httpVersion}\n`;
      for (let i = 0; i < req.rawHeaders.length; i += 2) {
        lines += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\n`;
      }
      lines += '\n';
      const bytes = Buffer.concat([Buffer.from(lines, 'latin1'), body]);
      return send(res, 200, ['Content-Length', String(bytes.length)], bytes);
    }
    default:
      return text(res, 404, 'not found\n');
  }
}

function wellFormed(req, res) {
  const chunks = [];
  req.on('error', () => res.destroy());
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => respond(req, res, Buffer.concat(chunks)));
}

const httpServer = http.createServer(wellFormed);
httpServer.on('connection', track);

// httpsServer: an https face serving LEAF, with ALPN http/1.1 alone. A TLS
// error ends that connection only.
function httpsServer(leafOf) {
  const server = https.createServer({ ...leafOf.options, ALPNProtocols: ['http/1.1'] }, wellFormed);
  server.on('connection', track);
  server.on('secureConnection', track);
  server.on('tlsClientError', (err, socket) => socket.destroy());
  return server;
}

// --- the HTTP/2 faces: h2c and h2 -----------------------------------------

// h2Send: one whole HTTP/2 response, :status then HEADERS' pairs in order,
// and BODY in DATA, or none, ending the stream on the HEADERS frame.
function h2Send(stream, status, headers, body) {
  if (stream.destroyed) return;
  const head = { ':status': status };
  for (let i = 0; i < headers.length; i += 2) head[headers[i]] = headers[i + 1];
  if (body === undefined) {
    stream.respond(head, { endStream: true, sendDate: false });
  } else {
    stream.respond(head, { sendDate: false });
    stream.end(body);
  }
}

function h2Text(stream, status, body, headers = []) {
  if (noBody.has(status)) {
    h2Send(stream, status, headers, undefined);
  } else if (status === 205) {
    h2Send(stream, status, [...headers, 'content-length', '0'], undefined);
  } else {
    const bytes = Buffer.from(body, 'latin1');
    h2Send(stream, status, [...headers, 'content-length', String(bytes.length)], bytes);
  }
}

function h2Respond(stream, headers, rawHeaders, body) {
  const r = route(headers[':path']);
  switch (r.kind) {
    case 'status':
      return h2Text(stream, r.code, `status ${r.code}\n`);
    case 'redirect':
      return h2Text(stream, r.code, `redirect ${r.code}\n`, ['location', r.target]);
    case 'echo': {
      let lines = '';
      for (let i = 0; i < rawHeaders.length; i += 2) lines += `${rawHeaders[i]}: ${rawHeaders[i + 1]}\n`;
      lines += '\n';
      const bytes = Buffer.concat([Buffer.from(lines, 'latin1'), body]);
      return h2Send(stream, 200, ['content-length', String(bytes.length)], bytes);
    }
    default:
      // /chunked is an HTTP/1.1 route.
      return h2Text(stream, 404, 'not found\n');
  }
}

function h2Stream(stream, headers, flags, rawHeaders) {
  const chunks = [];
  // A stream error ends this stream only.
  stream.on('error', () => stream.destroy());
  stream.on('data', (chunk) => chunks.push(chunk));
  stream.on('end', () => h2Respond(stream, headers, rawHeaders, Buffer.concat(chunks)));
}

// h2Face: SERVER, with the listeners every HTTP/2 face shares.
function h2Face(server) {
  server.on('connection', track);
  server.on('session', trackSession);
  server.on('sessionError', (err, session) => session.destroy());
  server.on('stream', h2Stream);
  return server;
}

const h2cServer = h2Face(http2.createServer());

function h2Server(leafOf) {
  const server = h2Face(http2.createSecureServer({ ...leafOf.options, allowHTTP1: false }));
  server.on('secureConnection', track);
  server.on('tlsClientError', (err, socket) => socket.destroy());
  // A client that did not choose h2: destroyed with nothing written. With
  // no listener, Node writes it an HTTP/1.0 403 first (measured).
  server.on('unknownProtocol', (socket) => socket.destroy());
  return server;
}

// --- the raw faces: raw and raw-tls ---------------------------------------

// The longest request head the raw faces read, its CRLF CRLF included.
const HEAD_LIMIT = 64 * 1024;

const ascii = (s) => Buffer.from(s, 'latin1');

// A script is a list of steps: write these bytes, wait N ms, end (FIN),
// reset (RST), or stall (write nothing until the client goes).
const write = (s) => ({ step: 'write', bytes: typeof s === 'string' ? ascii(s) : s });
const wait = (ms) => ({ step: 'wait', ms });
const END = { step: 'end' };
const RESET = { step: 'reset' };
const STALL = { step: 'stall' };

const badRequest = [
  write('HTTP/1.1 400 Bad Request\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n'),
  END,
];

// The scripts, by NAME. Each takes its parameters, by name: every one listed,
// each a decimal natural within its range, and no other; or, with a query
// function, what that reads from the query, null for one it refuses. play
// gets the parameters and the request head's bytes.
const scripts = {
  // framing
  'content-length': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n'), END] },
  'chunked': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
                       + '5\r\nhello\r\n1\r\n\n\r\n0\r\n\r\n'), END],
  },
  'chunked-extensions-trailers': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Trailer\r\n\r\n'
                       + 'C;name=value\r\nhello world\n\r\n0;last\r\nX-Trailer: done\r\n\r\n'), END],
  },
  'chunked-tiny': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
                       + [...'hello\n'].map((c) => `1\r\n${c}\r\n`).join('') + '0\r\n\r\n'), END],
  },
  'close-delimited': { play: () => [write('HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nhello\n'), END] },
  'http10': { play: () => [write('HTTP/1.0 200 OK\r\n\r\nhello\n'), END] },

  // drips
  'drip': {
    params: { bytes: [1, 4096], gap: [1, 5000] },
    play: ({ bytes, gap }) => {
      const steps = [write(`HTTP/1.1 200 OK\r\nContent-Length: ${bytes}\r\n\r\n`)];
      for (let i = 0; i < bytes; i++) {
        steps.push(wait(gap), write(String.fromCharCode(97 + (i % 26))));
      }
      steps.push(END);
      return steps;
    },
  },
  'stall-after-head': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n'), STALL] },
  // A script still playing, between two of its writes, for as long as ms
  // says: the stop checks hold a connection there for 60 s.
  'pause-mid-body': {
    params: { ms: [1, 60000] },
    play: ({ ms }) => [write('HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello'), wait(ms), write(' world'), END],
  },
  // Its last write and its reset come together, after a pause long enough
  // for a check to stop the client across both: that client's reader then
  // finds the last bytes and the reset waiting at once.
  'reset-after-pause': {
    params: { ms: [1, 60000] },
    play: ({ ms }) => [write('HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello'), wait(ms), write(' wor'), RESET],
  },
  'stall-before-head': { play: () => [STALL] },

  // oversized
  'big-header': {
    params: { bytes: [1, 1048576] },
    play: ({ bytes }) => [write(Buffer.concat([ascii('HTTP/1.1 200 OK\r\nX-Big: '),
                                               Buffer.alloc(bytes, 'a'), ascii('\r\n\r\n')])), END],
  },
  'many-headers': {
    params: { count: [1, 100000] },
    play: ({ count }) => {
      const lines = ['HTTP/1.1 200 OK\r\n'];
      for (let i = 1; i <= count; i++) lines.push(`X-H-${i}: v\r\n`);
      lines.push('\r\n');
      return [write(lines.join('')), END];
    },
  },

  // protocol errors
  'bad-status-line': { play: () => [write('HTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n'), END] },
  'bad-status-code': { play: () => [write('HTTP/1.1 2000 OK\r\nContent-Length: 6\r\n\r\nhello\n'), END] },
  'bad-chunk-size': {
    play: () => [write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\n\r\n0\r\n\r\n'), END],
  },
  'short-body': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello'), END] },
  'reset-mid-body': { play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello'), RESET] },
  'conflicting-content-length': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello\n'), END],
  },
  'chunked-and-content-length': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n'
                       + '6\r\nhello\n\r\n0\r\n\r\n'), END],
  },
  'header-no-colon': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nX-No-Colon\r\n\r\nhello\n'), END],
  },
  'nul-in-header': {
    play: () => [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nX-Nul: a\0b\r\n\r\nhello\n'), END],
  },
  // One header whose value holds every byte from 0x01 to 0xFF but CR and LF,
  // in order, between an a and a z: where Latin-1 and UTF-8 part, and the
  // control bytes. libcurl hands each back as sent (ADR-0001, amended
  // 2026-10-23).
  'header-bytes': {
    play: () => {
      const bytes = [];
      for (let b = 0x01; b <= 0xff; b++) if (b !== 0x0a && b !== 0x0d) bytes.push(b);
      return [write(Buffer.concat([ascii('HTTP/1.1 200 OK\r\nX-Bytes: a'), Buffer.from(bytes),
                                   ascii('z\r\nContent-Length: 0\r\n\r\n')])), END];
    },
  },
  'close-before-response': { play: () => [END] },
  'http09': { play: () => [write('hello\n'), END] },

  // tolerated
  'bare-lf': { play: () => [write('HTTP/1.1 200 OK\nContent-Length: 6\n\nhello\n'), END] },

  // echo
  'echo': {
    play: (_, head) => [write(Buffer.concat([ascii(`HTTP/1.1 200 OK\r\nContent-Length: ${head.length}\r\n\r\n`),
                                             head])), END],
  },

  // redirects: a status and Location headers of any bytes, after a wait
  'location': {
    query: locationQuery,
    play: ({ code, ms, to }) => {
      const head = [ascii(`HTTP/1.1 ${code} Redirect\r\n`)];
      for (const bytes of to) head.push(ascii('Location: '), bytes, ascii('\r\n'));
      head.push(ascii('Content-Length: 0\r\nConnection: close\r\n\r\n'));
      return [...(ms > 0 ? [wait(ms)] : []), write(Buffer.concat(head)), END];
    },
  },

  // retries: a key's first requests fail, then it answers 200; and its count
  'retry': {
    query: retryQuery,
    play: ({ key, fail, how, code, after, then }) => {
      const count = (attempts.get(key) || 0) + 1;
      attempts.set(key, count);
      const body = `attempt ${count}\n`;
      const tail = `Content-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`;
      if (count > fail) return then === 'stall' ? [STALL] : [write(`HTTP/1.1 200 OK\r\n${tail}`), END];
      if (how === 'close') return [END];
      if (how === 'reset') return [RESET];
      const head = [ascii(`HTTP/1.1 ${code} Retry\r\n`)];
      if (after !== null) head.push(ascii('Retry-After: '), after, ascii('\r\n'));
      head.push(ascii(tail));
      return [write(Buffer.concat(head)), END];
    },
  },
  'attempts': {
    query: attemptsQuery,
    play: ({ key }) => {
      const body = `attempts ${attempts.get(key) || 0}\n`;
      return [write(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`),
              END];
    },
  },
};

// attempts: the retry script's count of the requests it has read for each
// key, by key, for as long as the origin runs.
const attempts = new Map();

// retryKey: whether TEXT is a key the retry script takes.
const retryKey = (text) => /^[A-Za-z0-9._-]{1,64}$/.test(text);

// decimal: TEXT's value when it is a decimal natural with no leading zero,
// within LOW to HIGH, or null.
function decimal(text, low, high) {
  if (!/^(0|[1-9][0-9]*)$/.test(text)) return null;
  const n = Number(text);
  return n >= low && n <= high ? n : null;
}

// retryQuery: the retry script's parameters from QUERY, or null: key, fail
// and how exactly once; code exactly once with how=status, and never
// otherwise; after at most once, with how=status alone, its bytes; then at
// most once, ok or stall, ok when absent.
function retryQuery(query) {
  if (query === undefined) return null;
  const found = { key: null, fail: null, how: null, code: null, after: null, then: null };
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);
    if (!Object.hasOwn(found, name) || found[name] !== null) return null;
    let read;
    switch (name) {
      case 'key': read = retryKey(value) ? value : null; break;
      case 'fail': read = decimal(value, 0, 100); break;
      case 'how': read = ['close', 'reset', 'status'].includes(value) ? value : null; break;
      case 'code': read = decimal(value, 200, 599); break;
      case 'then': read = ['ok', 'stall'].includes(value) ? value : null; break;
      default: read = percentDecoded(value); break;
    }
    if (read === null) return null;
    found[name] = read;
  }
  if (found.key === null || found.fail === null || found.how === null) return null;
  if (found.how === 'status' ? found.code === null : found.code !== null || found.after !== null) {
    return null;
  }
  if (found.then === null) found.then = 'ok';
  return found;
}

// attemptsQuery: the attempts script's key from QUERY, exactly key=KEY, or
// null.
function attemptsQuery(query) {
  if (query === undefined || !query.startsWith('key=')) return null;
  const key = query.slice(4);
  return retryKey(key) ? { key } : null;
}

// percentDecoded: TEXT, a query value read as Latin-1, as bytes: each %XX,
// in either case, its byte, and every other char its own; null for a %
// without two hex digits after it.
function percentDecoded(text) {
  const bytes = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '%') {
      const hex = text.slice(i + 1, i + 3);
      if (!/^[0-9A-Fa-f]{2}$/.test(hex)) return null;
      bytes.push(parseInt(hex, 16));
      i += 2;
    } else {
      bytes.push(text.charCodeAt(i));
    }
  }
  return Buffer.from(bytes);
}

// locationQuery: the location script's parameters from QUERY, or null: code
// exactly once, 200 to 599; ms at most once, 0 to 60000, 0 when absent; to
// any number of times, in order, each value's bytes. Every pair is
// NAME=VALUE, the value after the first =.
function locationQuery(query) {
  if (query === undefined) return null;
  const found = { code: null, ms: null, to: [] };
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);
    if (name === 'code' || name === 'ms') {
      if (found[name] !== null || !/^(0|[1-9][0-9]*)$/.test(value)) return null;
      const n = Number(value);
      if (name === 'code' ? !(n >= 200 && n <= 599) : !(n <= 60000)) return null;
      found[name] = n;
    } else if (name === 'to') {
      const bytes = percentDecoded(value);
      if (bytes === null) return null;
      found.to.push(bytes);
    } else {
      return null;
    }
  }
  if (found.code === null) return null;
  return { code: found.code, ms: found.ms === null ? 0 : found.ms, to: found.to };
}

// parameters: the query's parameters as SPEC asks for them, or null.
function parameters(spec, query) {
  const names = Object.keys(spec);
  if (query === undefined) return names.length === 0 ? {} : null;
  const found = {};
  for (const pair of query.split('&')) {
    const m = /^([a-z]+)=(0|[1-9][0-9]*)$/.exec(pair);
    if (!m || !Object.hasOwn(spec, m[1]) || Object.hasOwn(found, m[1])) return null;
    const value = Number(m[2]);
    const [low, high] = spec[m[1]];
    if (!(value >= low && value <= high)) return null;
    found[m[1]] = value;
  }
  return names.every((name) => Object.hasOwn(found, name)) ? found : null;
}

// scriptFor: the steps for the request head HEAD, its CRLF CRLF included.
function scriptFor(head) {
  const text = head.toString('latin1');
  const parts = text.slice(0, text.indexOf('\r\n')).split(' ');
  if (parts.length !== 3) return badRequest;
  const m = /^\/raw\/([a-z0-9-]+)(?:\?(.*))?$/.exec(parts[1]);
  if (!m || !Object.hasOwn(scripts, m[1])) return badRequest;
  const script = scripts[m[1]];
  const found = script.query ? script.query(m[2]) : parameters(script.params || {}, m[2]);
  return found === null ? badRequest : script.play(found, head);
}

// pause: resolves after MS ms by the clock, never sooner, or when SOCKET
// closes. A timer can fire early by the loop's cached time, so it is rearmed
// for what is left.
function pause(socket, ms) {
  return new Promise((resolve) => {
    const start = performance.now();
    let timer;
    const done = () => {
      clearTimeout(timer);
      socket.off('close', done);
      resolve();
    };
    const check = () => {
      const left = ms - (performance.now() - start);
      if (left > 0) timer = setTimeout(check, Math.ceil(left));
      else done();
    };
    socket.on('close', done);
    timer = setTimeout(check, ms);
  });
}

// play: runs STEPS on SOCKET, whose STATE says whether the client has
// half-closed. A write waits until its bytes are handed to the kernel. It
// stops as soon as the socket can take no more. A reset is RESET's: the TCP
// socket's resetAndDestroy(). A stall writes nothing more, and leaves the
// connection to the client's FIN.
async function play(socket, reset, state, steps) {
  state.playing = true;
  try {
    for (const s of steps) {
      if (socket.destroyed || !socket.writable) return;
      switch (s.step) {
        case 'write':
          await new Promise((resolve) => socket.write(s.bytes, () => resolve()));
          break;
        case 'wait':
          await pause(socket, s.ms);
          break;
        case 'end':
          socket.end();
          return;
        case 'reset':
          reset();
          return;
        case 'stall':
          return;
        default:
          throw new Error(`no such step: ${s.step}`);
      }
    }
  } finally {
    state.playing = false;
    if (state.clientEnded && !socket.destroyed && socket.writable) socket.end();
  }
}

// serveRaw: reads a request head from SOCKET, and plays its script, with
// RESET as the script's reset.
function serveRaw(socket, reset) {
  // With allowHalfOpen, the client's FIN leaves this side open: a script that
  // is playing goes on; otherwise this side ends too.
  const state = { playing: false, clientEnded: false };
  socket.on('end', () => {
    state.clientEnded = true;
    if (!state.playing) socket.end();
  });
  let head = Buffer.alloc(0);
  let started = false;
  socket.on('data', (chunk) => {
    if (started) return;
    head = Buffer.concat([head, chunk]);
    const end = head.subarray(0, HEAD_LIMIT).indexOf('\r\n\r\n');
    if (end >= 0) {
      started = true;
      const request = Buffer.from(head.subarray(0, end + 4));
      head = null;
      play(socket, reset, state, scriptFor(request)).catch((err) => fatal('a script failed', err));
    } else if (head.length >= HEAD_LIMIT) {
      started = true;
      head = null;
      play(socket, reset, state, badRequest).catch((err) => fatal('a script failed', err));
    }
  });
}

// rawSocket: a raw face's TCP socket, set up: tracked, each write sent as
// written (Nagle's algorithm may hold a small write back while one is
// unacknowledged, which would join a drip's bytes), and an error, a reset or
// a write after the client went, ending this connection only.
function rawSocket(socket) {
  track(socket);
  socket.setNoDelay(true);
  socket.on('error', () => socket.destroy());
  return socket;
}

const rawServer = net.createServer({ allowHalfOpen: true }, (socket) => {
  rawSocket(socket);
  serveRaw(socket, () => socket.resetAndDestroy());
});

// rawTlsServer: raw's scripts over TLS, with LEAF and ALPN http/1.1 alone.
// The TLS socket is half-open as the TCP socket under it is. Its error, a
// TLS one among them, ends both.
function rawTlsServer(leafOf) {
  return net.createServer({ allowHalfOpen: true }, (raw) => {
    rawSocket(raw);
    const socket = new tls.TLSSocket(raw, {
      isServer: true,
      secureContext: leafOf.context,
      ALPNProtocols: ['http/1.1'],
    });
    track(socket);
    socket.on('error', () => {
      socket.destroy();
      raw.destroy();
    });
    serveRaw(socket, () => raw.resetAndDestroy());
  });
}

// --- the lifecycle --------------------------------------------------------

// The faces, by name, in the announcement's order.
const faces = [['http', httpServer], ['raw', rawServer], ['h2c', h2cServer]];
if (pki !== null) {
  const good = leaf('good');
  const expired = leaf('expired');
  const wrongHost = leaf('wrong-host');
  const untrusted = leaf('untrusted');
  faces.push(['https', httpsServer(good)],
             ['https-expired', httpsServer(expired)],
             ['https-wrong-host', httpsServer(wrongHost)],
             ['https-untrusted', httpsServer(untrusted)],
             ['raw-tls', rawTlsServer(good)],
             ['h2', h2Server(good)]);
}

function listen(server, name) {
  return new Promise((resolve) => {
    server.on('error', (err) => fatal(`the ${name} face failed`, err));
    server.listen(0, HOST, resolve);
  });
}

function address(server) {
  const { address: host, port } = server.address();
  return `${host}:${port}`;
}

let stopping = false;
function stop(code) {
  if (stopping) return;
  stopping = true;
  let open = faces.length;
  const closed = () => {
    open -= 1;
    if (open === 0) process.exit(code);
  };
  for (const [, server] of faces) server.close(closed);
  for (const session of sessions) session.destroy();
  for (const socket of sockets) socket.destroy();
}

await Promise.all(faces.map(([name, server]) => listen(server, name)));

const announcement = JSON.stringify({
  node: process.version,
  pid: process.pid,
  ...Object.fromEntries(faces.map(([name, server]) => [name, address(server)])),
});

// stdin is read only once the announcement is out, so its end cannot come
// first.
process.stdout.write(`${announcement}\n`, () => {
  process.stdin.on('data', () => {});
  process.stdin.on('end', () => stop(0));
  process.stdin.on('error', (err) => {
    process.stderr.write(`origin: stdin failed: ${err && err.stack}\n`);
    stop(1);
  });
});
