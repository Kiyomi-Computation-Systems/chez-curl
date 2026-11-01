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
//         Connection: close back when Node will close. It is also a CONNECT
//         proxy to this origin's own faces alone: CONNECT 127.0.0.1:PORT, PORT
//         one of them, gets "HTTP/1.1 200 Connection Established", then both
//         ways piped; any other target gets a 403, and the end.
//           GET /status/CODE             200-599: status CODE, body "status CODE\n"
//           GET /redirect/CODE?to=TARGET 300-308: Location: TARGET, decoded,
//                                        body "redirect CODE\n"
//           GET /chunked                 three writes, each its own chunk
//           ANY /echo                    the request as Node parsed it
//           GET /pattern/N[?delay=MS]    1 to 268435456: 200, Content-Length N,
//                                        the body N bytes, byte i being i mod
//                                        251, written 16384 bytes a write, a
//                                        write Node holds awaiting its drain;
//                                        the head flushed first, then MS ms, 0
//                                        to 60000, before the body: Node holds
//                                        a head back until a body's first write
//           GET /early                   a 100 Continue, a 103 Early Hints with
//                                        a Link header, then 200, body "early\n"
//           GET /connects                200, body "connects N\n": the CONNECT
//                                        tunnels the http face has opened
//           ANY /sink?key=K[&list=1]     the body read whole, then 200 with
//                                        its summary line (the sinks, below)
//           GET /seen?key=K              200, body "seen C\n", C the count for
//                                        K so far, 0 for one never counted;
//                                        it counts nothing
//           GET /close-after?then=HOW    http's alone: 200, Content-Length: 3,
//                                        "ok\n", kept alive; and by HOW, fin
//                                        destroys the socket 50 ms after the
//                                        response is written; kill reads the
//                                        connection's next request whole, then
//                                        destroys it unanswered; cuthead
//                                        destroys it, resethead resets it, as
//                                        its head arrives. That request counts
//                                        as any does; the mark is used once
//           anything else                404, body "not found\n"
//         The queries of these three, and of HTTP/2's /answer, /refuse,
//         /answer-at and /seq, are NAME=VALUE pairs, each name once at most
//         and one the route names, every name it requires given, else 404.
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
//         /raw/retry?key=KEY&fail=N&how=HOW[&code=CODE][&after=BYTES][&slow=MS][&then=THEN]
//         fails the first N requests for KEY, then answers 200, or stalls.
//         Its query, every pair NAME=VALUE, each name once at most: key, 1
//         to 64 of A-Z, a-z, 0-9, ., _ and -; fail, 0 to 100; how, close,
//         reset or status; code, 200 to 599, with how=status alone, which
//         needs it; after, with how=status alone, percent-decoded as
//         location's to is; slow, 0 to 60000, with how=status alone; then,
//         ok, the default, or stall. The
//         origin counts each request for KEY whose query it takes, on raw
//         and raw-tls alike, and C is the count with this one. While C is N
//         or less, the request fails by HOW: close ends the connection with
//         nothing written; reset resets it with nothing written; status
//         writes "HTTP/1.1 CODE Retry", a Retry-After header holding after's
//         bytes as they are when after is given, then Content-Length,
//         Connection: close and the body "attempt C\n", and ends; with
//         slow, that answer's head and its body's first byte, then MS ms,
//         then the rest of the body, and the end. Past N,
//         with then=ok, it writes "HTTP/1.1 200 OK", Content-Length,
//         Connection: close and the body "attempt C\n", and ends; with
//         then=stall it writes nothing, and leaves the connection to the
//         client. A query it refuses gets the fixed 400, and counts nothing.
//         /raw/attempts?key=KEY, KEY as retry takes it, writes "HTTP/1.1
//         200 OK", Content-Length, Connection: close and the body "attempts
//         C\n", C the count so far, 0 for a key never counted, and ends. It
//         counts nothing. A count lives as long as the origin.
//         /raw/hold?key=KEY&ms=N holds a request N ms, 0 to 60000, counting
//         it for KEY, as retry takes it, among the requests held now, and
//         the most held at once. Its query is exactly key and ms, each
//         once, in any order. The hold ends after N ms, or when the
//         connection closes, and the request is then no longer held; it
//         writes "HTTP/1.1 200 OK", Content-Length, Connection: close and
//         the body "held\n", and ends. A query it refuses gets the fixed
//         400, and counts nothing.
//         /raw/most?key=KEY writes "HTTP/1.1 200 OK", Content-Length,
//         Connection: close and the body "held H most M\n": for KEY, the
//         requests held now, and the most held at once so far, 0 and 0
//         for a key never held, and ends. It counts nothing. The counts
//         live as long as the origin.
//         /raw/pattern?key=KEY&bytes=N&chunk=C[&delay=MS][&gap=MS][&framing=F]
//         writes "HTTP/1.1 200 OK", Content-Length: N, or with
//         framing=chunked Transfer-Encoding: chunked, then Connection: close,
//         and the head's end; then MS ms; then the body, N bytes, byte i
//         being i mod 251, C bytes a write, each its own chunk when chunked,
//         GAP ms apart, each write awaited until the kernel takes it; then
//         the last chunk, when chunked, and the end. Its query, every pair
//         NAME=VALUE, each name once at most: key, as retry takes it; bytes,
//         1 to 268435456; chunk, 1 to 1048576; delay and gap, 0 to 60000, 0
//         when left out; framing, length, the default, or chunked. For KEY it
//         records the body's bytes the kernel has taken, and where its writes
//         first stalled: the body's offset at a write the kernel had not
//         taken 100 ms after it began, the client reading no more. A query it
//         refuses gets the fixed 400, and records nothing.
//         /raw/stalls?key=KEY writes "HTTP/1.1 200 OK", Content-Length,
//         Connection: close and the body "written W stalled S\n": for KEY's
//         latest pattern, the bytes the kernel took, and the offset where its
//         writes first stalled, or none; 0 and none for a key never seen. It
//         records nothing. The records live as long as the origin.
//         /raw/early writes a 100 Continue, a 103 Early Hints with a Link
//         header, waits 50 ms, then writes a 200 with Content-Length: 6,
//         Connection: close and the body "early\n", and ends.
//         /raw/sink?key=KEY[&hold=MS][&list=1], KEY as retry takes it, counts
//         for KEY as its head arrives (the sinks, below); with hold, reads
//         nothing for MS ms, 0 to 60000, the socket paused, so the kernel's
//         buffers fill and the client's writes stall; then reads the body by
//         the head's framing: Content-Length, Transfer-Encoding: chunked, its
//         extensions and trailers taken and dropped, or none, no body; then
//         writes "HTTP/1.1 200 OK", Content-Length, Connection: close and the
//         summary line, and ends. Framing it cannot read gets the fixed 400,
//         the request counted all the same. A client that closes or resets
//         first ends the script, which writes nothing more. The body's bytes
//         are recorded for KEY as they are read, the latest sink's for a key,
//         the client gone first or not, for /raw/sunk.
//         /raw/sunk?key=KEY writes "HTTP/1.1 200 OK", Content-Length,
//         Connection: close and the body "sunk N\n": the body bytes KEY's
//         latest /raw/sink has read so far, 0 for a key no sink has read. It
//         records nothing; the records live as long as the origin.
//         /raw/answer?status=S&close=C, S 200 to 599, C 0 or 1, each once,
//         writes, as the head arrives, "HTTP/1.1 S Answer", Content-Length,
//         Connection: close when C is 1, and the body "answer S\n"; then, C
//         1, ends; C 0, reads the body to its framing's end, then ends.
//         /raw/answer-at?status=S&after=N[&close=C][&to=BYTES], S 200 to 599
//         and N 0 to 268435456 exactly once each, C 0 or 1 and to at most
//         once each, C 0 when absent, to percent-decoded as location's is,
//         reads the body by the head's framing, as /raw/sink does, and once
//         N body bytes have come, N 0 as the head arrives, or at the body's
//         end when it is shorter, writes "HTTP/1.1 S Early", a Location
//         header holding to's bytes as they are when to is given,
//         Content-Length, Connection: close when C is 1, and the body
//         "early S\n". Then, C 1, it ends its side, and drops what the
//         client sends until the client ends; C 0, it reads the body to its
//         framing's end, then ends. Framing it cannot read gets the fixed
//         400, in place of the answer when the answer has not gone. With
//         hold=KEY, KEY as retry takes it, at most once, the answer's last
//         byte waits until /raw/release names KEY, at once when it has; the
//         reading goes on meanwhile, and the script ends only once that byte
//         is written, or the client has gone: a response kept live after the
//         body's end until a test lets it go.
//         /raw/release?key=KEY releases KEY, for good: every answer-at held
//         on it writes its last byte. It writes "HTTP/1.1 200 OK",
//         Content-Length: 9, Connection: close and "released\n", and ends.
//         /raw/mirror, which takes no query, writes, as the head arrives,
//         "HTTP/1.1 200 OK", then Content-Length: L, L the request's own,
//         or Transfer-Encoding: chunked for a chunked request, or
//         Content-Length: 0 for one with no body, then Connection: close;
//         then each data event's body pieces, as they are decoded, written
//         back, each its own chunk when chunked; and at the body's end the
//         last chunk, when chunked, and the end. While a write waits for the
//         kernel to take it, the socket is paused, so a client that stops
//         reading stops its own upload. Framing it cannot read gets the
//         fixed 400.
//         /raw/seq?key=KEY&bytes=N, KEY as retry takes it and N 0 to
//         268435456, each exactly once, counts for KEY as its head arrives
//         and reads the body whole, as /raw/sink does; then writes "HTTP/1.1
//         200 OK", a Sink header holding the summary line without its
//         newline, Content-Length: N and Connection: close; then N bytes of
//         the pattern, byte i being i mod 251, 16384 bytes a write, each
//         awaited until the kernel takes it; then ends. Framing it cannot
//         read gets the fixed 400, the request counted all the same.
//         /raw/cut?key=KEY&after=N, KEY as retry takes it and N 0 to
//         268435456, each exactly once, counts for KEY as its head arrives,
//         as a sink does; then, once N bytes of what follows the head have
//         come, or the client has ended, or at once for N 0, ends the
//         connection, socket.destroy(), with nothing written: a server that
//         dies under a body it has begun to read.
//         The scripts that read a body, these six and the arm's kept
//         connection, alone keep the bytes that follow the head; every other
//         script reads none.
//         /raw/arm?status=S[&mode=MODE][&to=BYTES], S 200 to 599, once, MODE
//         close, the default, or keep, and to, percent-decoded as location's
//         is, at most once each, arms the raw face, whichever face the
//         request came on: the next connection the raw face accepts gets
//         "HTTP/1.1 S Early", a Location header holding to's bytes as they
//         are when to is given, Content-Length, Connection: close for mode
//         close, and the body "early S\n" as it is accepted, before a byte
//         of its request is read. Mode close: then the face ends its side
//         and drops what the client sends, until the client ends. Mode keep:
//         then it reads the connection's request, its head and its body to
//         its framing's end, as /raw/sink reads one, and ends its side. Mode
//         cut, which alone takes after=N, 0 to 268435456, and needs it: no
//         Connection, then it reads the request's head, and ends the
//         connection, nothing more written, once N bytes of what follows that
//         head have come, as /raw/cut does: an answer before libcurl's first
//         ask, then a server that dies under the body. One
//         connection, then the face plays scripts again; a second arm before
//         that replaces the first. The arm itself writes "HTTP/1.1 200 OK",
//         Content-Length: 6, Connection: close and "armed\n", and ends.
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
// content-length: 0. /pattern/N[?delay=MS] answers :status and
// content-length, then the body as http writes it; /early sends a 100's
// HEADERS, a 103's with link, then :status 200 and content-length, and
// "early\n"; /connection[?delay=MS], HTTP/2's alone, answers :status and
// content-length at once, then, MS ms on, "connection K\n", K the
// connection's number among this face's, from 1, so two streams share a
// connection exactly when they answer one K. /sink and /seen are http's,
// with content-length. /answer?status=S, HTTP/2's alone, answers S,
// content-length and "answer S\n", or for 204, 304 and 205 as /status does,
// as the headers arrive, ending its side; it then reads the body, if any,
// and answers nothing more. It counts nothing.
// /refuse?key=K&at=N, HTTP/2's alone, N 0 to 268435456, counts as /sink
// does; the first request for K is reset with RST_STREAM REFUSED_STREAM
// once N DATA bytes have come, N 0 as its headers arrive, before any DATA;
// a later one, or a first whose body ends short of N, is answered as /sink.
// /answer-at?status=S&after=N[&to=PATH], HTTP/2's alone, S 200 to 599 and
// N 0 to 268435456 exactly once each, PATH at most once, decoded as
// /redirect's TARGET is, answers once N DATA bytes have come, N 0 as the
// headers arrive, or at the stream's end when the body is shorter: S,
// location PATH when given, content-length and "early S\n", or for 204,
// 304 and 205 as /status does, ending its side; it then reads the DATA on
// and answers nothing more. It counts nothing.
// /mirror, HTTP/2's alone, no query, answers :status 200, and the
// request's content-length when it gave one, as the headers arrive; then
// each DATA chunk, written back as it arrives, the stream paused while a
// write waits for its drain, so a client that stops reading stops its own
// upload; and ends its side at the request's end.
// /seq?key=K&bytes=N, HTTP/2's alone, N 0 to 268435456, counts as /sink
// does and reads the body whole; then answers :status 200, a sink header
// holding the summary line without its newline, content-length N, and N
// bytes of the pattern, as /pattern/N writes them.
// Anything else, /chunked, /connects and /close-after included, is 404,
// "not found\n". No date, and no header beyond these.
//
// The sinks. A body's summary is one line, then "\n":
//   sink FACE method=M cl=CL te=TE expect=E ct=CT bytes=N sha256=HEX pattern=P arrivals=A gap=G@B seen=C
// with " list=T:N,..." after it, each arrival in order, for list=1. FACE is
// the face's name; M the method as received; CL, TE, E and CT the request's
// Content-Length, Transfer-Encoding, Expect and Content-Type: the name in
// any case, each value trimmed of spaces and tabs, repeats joined by ",",
// whitespace in a value as "_", and "-" when absent. N is the body's bytes,
// HEX their SHA-256 in lower-case hex, and P ok when every byte i is i mod
// 251, else bad@I, I the first that is not. An arrival is the body bytes of
// one data event: node:http's, an HTTP/2 stream's, or the bytes one socket
// data event decodes to on the raw faces; A counts them. G is the longest
// wait between one arrival and the next, the head's arrival the first, and
// B the body bytes before it, the first such wait when two are longest, or
// "-" for no body. T is an arrival's time since the head's, and G, ms to
// one decimal. One count for each key K, across every face, lives as long as
// the origin: each /sink, /refuse, /seq, /raw/sink and /raw/seq request
// whose query names key=K counts once for K as its head arrives, and C is
// K's count as the line is written. A query a route refuses counts nothing.
//
// The suites (tests/test-origin.sps, tests/test-origin-tls.sps) hold their
// own copy of each scenario's bytes, written separately from these. They
// never read them from here, so changing a script here fails them.

import { createHash } from 'node:crypto';
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
  if ((m = /^\/pattern\/([1-9][0-9]*)$/.exec(path))) {
    const bytes = decimal(m[1], 1, 268435456);
    const delay = delayQuery(query);
    return bytes === null || delay === null ? { kind: 'not-found' } : { kind: 'pattern', bytes, delay };
  }
  if (path === '/early' && query === undefined) return { kind: 'early' };
  if (path === '/connects' && query === undefined) return { kind: 'connects' };
  if (path === '/connection') {
    const delay = delayQuery(query);
    return delay === null ? { kind: 'not-found' } : { kind: 'connection', delay };
  }
  const queried = (kind, found) => (found === null ? { kind: 'not-found' } : { kind, ...found });
  if (path === '/sink') return queried('sink', queryOf(query, { key: keyValue, list: oneValue }, ['key']));
  if (path === '/seen') return queried('seen', queryOf(query, { key: keyValue }, ['key']));
  if (path === '/answer') {
    return queried('answer', queryOf(query, { status: (v) => decimal(v, 200, 599) }, ['status']));
  }
  if (path === '/refuse') {
    return queried('refuse', queryOf(query, { key: keyValue, at: (v) => decimal(v, 0, 268435456) }, ['key', 'at']));
  }
  if (path === '/answer-at') {
    return queried('answer-at', queryOf(query, {
      status: (v) => decimal(v, 200, 599),
      after: (v) => decimal(v, 0, 268435456),
      to: headerTarget,
    }, ['status', 'after']));
  }
  if (path === '/mirror' && query === undefined) return { kind: 'mirror' };
  if (path === '/seq') {
    return queried('seq', queryOf(query, { key: keyValue, bytes: (v) => decimal(v, 0, 268435456) }, ['key', 'bytes']));
  }
  if (path === '/close-after') {
    const then = (v) => (['fin', 'kill', 'cuthead', 'resethead'].includes(v) ? v : null);
    return queried('close-after', queryOf(query, { then }, ['then']));
  }
  return { kind: 'not-found' };
}

// queryOf: QUERY's pairs, each NAME=VALUE, the value after the first =, as
// READERS read them, by name; or null for a pair with no =, a name READERS
// does not hold, a name twice, a value its reader refuses (answers null),
// or a name of REQUIRED missing. A name left out is absent from the answer.
function queryOf(query, readers, required) {
  if (query === undefined) return required.length === 0 ? {} : null;
  const found = {};
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    const name = pair.slice(0, at);
    if (!Object.hasOwn(readers, name) || Object.hasOwn(found, name)) return null;
    const value = readers[name](pair.slice(at + 1));
    if (value === null) return null;
    found[name] = value;
  }
  return required.every((name) => Object.hasOwn(found, name)) ? found : null;
}

// keyValue: a key, as retry takes it, or null. oneValue: true for 1, the
// one value list takes, or null.
const keyValue = (text) => (retryKey(text) ? text : null);
const oneValue = (text) => (text === '1' ? true : null);

// delayQuery: MS from a query that is exactly delay=MS, 0 to 60000; 0 for
// no query; null for any other.
function delayQuery(query) {
  if (query === undefined) return 0;
  if (!query.startsWith('delay=')) return null;
  return decimal(query.slice(6), 0, 60000);
}

// patternBlock: 251 bytes, 0 to 250, which the pattern repeats.
const patternBlock = Buffer.from(Array.from({ length: 251 }, (_, i) => i));

// patternBytes: the first N bytes of the pattern, byte i being i mod 251.
function patternBytes(n) {
  return Buffer.alloc(n).fill(patternBlock);
}

// sleep: resolves after MS ms.
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// The CONNECT tunnels the http face has opened, for as long as it runs.
let connects = 0;

// redirectTarget: the decoded TARGET of a query that is exactly to=TARGET,
// or null.
function redirectTarget(query) {
  if (query === undefined || !query.startsWith('to=')) return null;
  const raw = query.slice(3);
  if (raw.includes('&')) return null;
  return headerTarget(raw);
}

// headerTarget: RAW, a query value, decoded, when it is printable ASCII
// with no space, which a header value carries unchanged; or null, for an
// empty one too.
function headerTarget(raw) {
  if (raw === '') return null;
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

// --- the sinks: a body's record, its summary, and the counts by key -------

// counts: the sink requests counted for each key, by key, on every face,
// for as long as the origin runs.
const counts = new Map();

// countFor: counts one more request for KEY; answers the count with it.
function countFor(key) {
  const n = (counts.get(key) || 0) + 1;
  counts.set(key, n);
  return n;
}

// tenthsSince: the ms from START, a performance.now(), to now, in tenths,
// rounded. tenthsText: tenths T as ms to one decimal.
const tenthsSince = (start) => Math.round((performance.now() - start) * 10);
const tenthsText = (t) => `${Math.floor(t / 10)}.${t % 10}`;

// bodyRecord: an empty record of a request's body: its bytes, their
// SHA-256, the first byte that is not the pattern's, and its arrivals, each
// [TENTHS, BYTES], TENTHS since the head's arrival.
function bodyRecord() {
  return { bytes: 0, hash: createHash('sha256'), bad: null, arrivals: [] };
}

// arrive: one arrival into RECORD, AT tenths since the head: PIECES, the
// body bytes of one data event, in order. No bytes, no arrival.
function arrive(record, pieces, at) {
  let n = 0;
  for (const piece of pieces) {
    if (record.bad === null) {
      for (let i = 0; i < piece.length; i++) {
        if (piece[i] !== (record.bytes + i) % 251) {
          record.bad = record.bytes + i;
          break;
        }
      }
    }
    record.hash.update(piece);
    record.bytes += piece.length;
    n += piece.length;
  }
  if (n > 0) record.arrivals.push([at, n]);
}

// headerValue: NAME's value among PAIRS, a flat list of names and values as
// received: the name in any case, each value trimmed of spaces and tabs,
// repeats joined by ","; null when absent.
function headerValue(pairs, name) {
  const values = [];
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    if (pairs[i].toLowerCase() === name) values.push(pairs[i + 1].replace(/^[ \t]+|[ \t]+$/g, ''));
  }
  return values.length === 0 ? null : values.join(',');
}

// summary: the sink's line for a request on FACE, with METHOD, the header
// PAIRS and the body's RECORD, then "\n": its fields as the header says, C
// being KEY's count now, and the arrivals listed when LIST.
function summary(face, method, pairs, record, key, list) {
  const field = (name) => {
    const value = headerValue(pairs, name);
    return value === null ? '-' : value.replace(/[\t\n\v\f\r ]/g, '_');
  };
  let gap = '-';
  let previous = 0;
  let longest = -1;
  let before = 0;
  let sum = 0;
  for (const [at, n] of record.arrivals) {
    if (at - previous > longest) {
      longest = at - previous;
      before = sum;
    }
    previous = at;
    sum += n;
  }
  if (record.arrivals.length > 0) gap = `${tenthsText(longest)}@${before}`;
  const pattern = record.bad === null ? 'ok' : `bad@${record.bad}`;
  const line = [`sink ${face}`, `method=${method}`, `cl=${field('content-length')}`,
                `te=${field('transfer-encoding')}`, `expect=${field('expect')}`, `ct=${field('content-type')}`,
                `bytes=${record.bytes}`, `sha256=${record.hash.digest('hex')}`, `pattern=${pattern}`,
                `arrivals=${record.arrivals.length}`, `gap=${gap}`, `seen=${counts.get(key) || 0}`];
  if (list) line.push(`list=${record.arrivals.map(([at, n]) => `${tenthsText(at)}:${n}`).join(',')}`);
  return `${line.join(' ')}\n`;
}

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
    case 'pattern':
      return pattern(res, r.bytes, r.delay);
    case 'early':
      res.writeContinue();
      res.writeEarlyHints({ link: '</style.css>; rel=preload; as=style' });
      return text(res, 200, 'early\n');
    case 'connects':
      return text(res, 200, `connects ${connects}\n`);
    case 'seen':
      return text(res, 200, `seen ${counts.get(r.key) || 0}\n`);
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
      // /answer, /refuse, /answer-at, /mirror and /seq are HTTP/2's routes,
      // and /close-after http's, which wellFormed serves.
      return text(res, 404, 'not found\n');
  }
}

// pattern: a 200 whose body is the first BYTES of the pattern, its head
// flushed, then, DELAY ms on, the body, 16384 bytes a write, a write Node
// holds back awaiting its drain. A response the client has gone from writes
// no more.
function pattern(res, bytes, delay) {
  res.sendDate = false;
  const connection = res.shouldKeepAlive ? 'keep-alive' : 'close';
  res.writeHead(200, ['Content-Length', String(bytes), 'Connection', connection]);
  res.flushHeaders();
  const body = patternBytes(bytes);
  const gone = () => res.destroyed || res.writableEnded;
  (async () => {
    if (delay > 0) await sleep(delay);
    for (let at = 0; at < bytes; at += 16384) {
      if (gone()) return;
      if (!res.write(body.subarray(at, Math.min(at + 16384, bytes)))) {
        await new Promise((resolve) => {
          const done = () => { res.off('drain', done); res.off('close', done); resolve(); };
          res.on('drain', done);
          res.on('close', done);
        });
      }
    }
    if (!gone()) res.end();
  })().catch((err) => fatal('a pattern failed', err));
}

// marks: the http face's connections a /close-after has marked, by socket,
// and how the next request on each is cut: kill, cuthead or resethead.
const marks = new WeakMap();

// wellFormed: FACE's request listener. A request on a marked connection is
// counted as any is, then cut, the mark used: as its head arrives, or, for
// kill, once its body is read whole.
function wellFormed(face) {
  return (req, res) => {
    const headAt = performance.now();
    const socket = req.socket;
    const mark = marks.get(socket);
    marks.delete(socket);
    const r = route(req.url);
    if (r.kind === 'sink') countFor(r.key);
    req.on('error', () => res.destroy());
    if (mark === 'cuthead') return socket.destroy();
    if (mark === 'resethead') return socket.resetAndDestroy();
    const closeAfter = mark === undefined && r.kind === 'close-after' && face === 'http';
    if (closeAfter) {
      // The mark goes on as the head arrives, so a request sent behind this
      // one, before its answer, is cut too.
      if (r.then !== 'fin') marks.set(socket, r.then);
      else res.on('finish', () => pause(socket, 50).then(() => socket.destroy()));
    }
    const record = bodyRecord();
    const chunks = [];
    req.on('data', (chunk) => {
      if (r.kind === 'sink') arrive(record, [chunk], tenthsSince(headAt));
      else chunks.push(chunk);
    });
    req.on('end', () => {
      if (mark === 'kill') return socket.destroy();
      if (r.kind === 'sink') return text(res, 200, summary(face, req.method, req.rawHeaders, record, r.key, r.list));
      if (closeAfter) return text(res, 200, 'ok\n');
      return respond(req, res, Buffer.concat(chunks));
    });
  };
}

const httpServer = http.createServer(wellFormed('http'));
httpServer.on('connection', track);

// The CONNECT proxy, to this origin's own faces alone: a target of
// 127.0.0.1:PORT, PORT one of theirs, is tunnelled, both ways piped, and
// counted once its far end connects; any other gets a 403, and the end.
httpServer.on('connect', (req, client, early) => {
  track(client);
  client.on('error', () => client.destroy());
  const m = /^127\.0\.0\.1:([1-9][0-9]*)$/.exec(req.url);
  const ports = new Set(faces.map(([, server]) => server.address() && server.address().port));
  if (!m || !ports.has(Number(m[1]))) {
    client.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
    return;
  }
  const far = net.connect(Number(m[1]), HOST, () => {
    connects += 1;
    client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    if (early && early.length > 0) far.write(early);
    far.pipe(client);
    client.pipe(far);
  });
  track(far);
  far.on('error', () => { far.destroy(); client.destroy(); });
  client.on('close', () => far.destroy());
  far.on('close', () => client.destroy());
});

// httpsServer: the https face NAME serving LEAF, with ALPN http/1.1 alone.
// A TLS error ends that connection only.
function httpsServer(name, leafOf) {
  const server = https.createServer({ ...leafOf.options, ALPNProtocols: ['http/1.1'] }, wellFormed(name));
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

// h2Pattern: an HTTP/2 200 whose body is the first BYTES of the pattern,
// its HEADERS sent at once, HEADERS' pairs between :status and
// content-length, then, DELAY ms on, the body as http writes it.
function h2Pattern(stream, bytes, delay, headers = []) {
  if (stream.destroyed) return;
  const head = { ':status': 200 };
  for (let i = 0; i < headers.length; i += 2) head[headers[i]] = headers[i + 1];
  head['content-length'] = String(bytes);
  stream.respond(head, { sendDate: false });
  const body = patternBytes(bytes);
  const gone = () => stream.destroyed || stream.writableEnded;
  (async () => {
    if (delay > 0) await sleep(delay);
    for (let at = 0; at < bytes; at += 16384) {
      if (gone()) return;
      if (!stream.write(body.subarray(at, Math.min(at + 16384, bytes)))) {
        await new Promise((resolve) => {
          const done = () => { stream.off('drain', done); stream.off('close', done); resolve(); };
          stream.on('drain', done);
          stream.on('close', done);
        });
      }
    }
    if (!gone()) stream.end();
  })().catch((err) => fatal('a pattern failed', err));
}

function h2Respond(stream, headers, rawHeaders, body) {
  const r = route(headers[':path']);
  switch (r.kind) {
    case 'pattern':
      return h2Pattern(stream, r.bytes, r.delay);
    case 'early':
      if (stream.destroyed) return;
      stream.additionalHeaders({ ':status': 100 });
      stream.additionalHeaders({ ':status': 103, link: '</style.css>; rel=preload; as=style' });
      return h2Text(stream, 200, 'early\n');
    case 'connection': {
      if (stream.destroyed) return;
      const bytes = Buffer.from(`connection ${stream.session.connectionNumber}\n`, 'latin1');
      stream.respond({ ':status': 200, 'content-length': String(bytes.length) }, { sendDate: false });
      (async () => {
        if (r.delay > 0) await sleep(r.delay);
        if (!stream.destroyed) stream.end(bytes);
      })().catch((err) => fatal('a connection answer failed', err));
      return;
    }
    case 'status':
      return h2Text(stream, r.code, `status ${r.code}\n`);
    case 'redirect':
      return h2Text(stream, r.code, `redirect ${r.code}\n`, ['location', r.target]);
    case 'seen':
      return h2Text(stream, 200, `seen ${counts.get(r.key) || 0}\n`);
    case 'echo': {
      let lines = '';
      for (let i = 0; i < rawHeaders.length; i += 2) lines += `${rawHeaders[i]}: ${rawHeaders[i + 1]}\n`;
      lines += '\n';
      const bytes = Buffer.concat([Buffer.from(lines, 'latin1'), body]);
      return h2Send(stream, 200, ['content-length', String(bytes.length)], bytes);
    }
    default:
      // /chunked and /close-after are HTTP/1.1 routes.
      return h2Text(stream, 404, 'not found\n');
  }
}

// h2Stream: FACE's stream listener. /answer answers as the headers arrive,
// then reads the body; /answer-at once N DATA bytes have come; /mirror
// writes each DATA chunk back as it comes; /sink, /refuse and /seq count
// as they arrive, and read the body, or refuse the stream; every other
// route reads the body whole, then answers.
function h2Stream(face) {
  return (stream, headers, flags, rawHeaders) => {
    const headAt = performance.now();
    // A stream error ends this stream only.
    stream.on('error', () => stream.destroy());
    const r = route(headers[':path']);
    if (r.kind === 'answer') {
      // Read while the answer goes, so that Node, which closes a stream it
      // has answered when nothing reads it, keeps the stream open.
      stream.on('data', () => {});
      return h2Text(stream, r.status, `answer ${r.status}\n`);
    }
    if (r.kind === 'answer-at') {
      // Read before and after the answer, as /answer does, and answer once.
      let bytes = 0;
      let answered = false;
      const answer = () => {
        if (answered) return;
        answered = true;
        h2Text(stream, r.status, `early ${r.status}\n`, r.to === undefined ? [] : ['location', r.to]);
      };
      stream.on('data', (chunk) => {
        bytes += chunk.length;
        if (bytes >= r.after) answer();
      });
      stream.on('end', answer);
      if (r.after === 0) answer();
      return undefined;
    }
    if (r.kind === 'mirror') {
      // Each DATA chunk written back as it arrives; while a write waits for
      // its drain the stream is paused, so its window stays shut and the
      // client's upload stops.
      const head = { ':status': 200 };
      if (headers['content-length'] !== undefined) head['content-length'] = headers['content-length'];
      stream.respond(head, { sendDate: false });
      let paused = false;
      stream.on('data', (chunk) => {
        if (!stream.write(chunk) && !paused) {
          paused = true;
          stream.pause();
          stream.once('drain', () => {
            paused = false;
            stream.resume();
          });
        }
      });
      stream.on('end', () => {
        if (!stream.destroyed) stream.end();
      });
      return undefined;
    }
    if (r.kind === 'seq') {
      countFor(r.key);
      const record = bodyRecord();
      stream.on('data', (chunk) => arrive(record, [chunk], tenthsSince(headAt)));
      stream.on('end', () => {
        const line = summary(face, headers[':method'], rawHeaders, record, r.key, false);
        h2Pattern(stream, r.bytes, 0, ['sink', line.slice(0, -1)]);
      });
      return undefined;
    }
    if (r.kind === 'sink' || r.kind === 'refuse') {
      const seenNow = countFor(r.key);
      const refuseAt = r.kind === 'refuse' && seenNow === 1 ? r.at : null;
      if (refuseAt === 0) return stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
      const record = bodyRecord();
      let refused = false;
      stream.on('data', (chunk) => {
        if (refused) return;
        arrive(record, [chunk], tenthsSince(headAt));
        if (refuseAt !== null && record.bytes >= refuseAt) {
          refused = true;
          stream.close(http2.constants.NGHTTP2_REFUSED_STREAM);
        }
      });
      stream.on('end', () => {
        if (!refused) h2Text(stream, 200, summary(face, headers[':method'], rawHeaders, record, r.key, r.list));
      });
      return undefined;
    }
    const chunks = [];
    stream.on('data', (chunk) => chunks.push(chunk));
    stream.on('end', () => h2Respond(stream, headers, rawHeaders, Buffer.concat(chunks)));
    return undefined;
  };
}

// h2Face: SERVER, the face NAME, with the listeners every HTTP/2 face
// shares. Each session is numbered, from 1, among its face's, for
// /connection.
function h2Face(server, name) {
  let sessionsSeen = 0;
  server.on('connection', track);
  server.on('session', (session) => {
    sessionsSeen += 1;
    session.connectionNumber = sessionsSeen;
    trackSession(session);
  });
  server.on('sessionError', (err, session) => session.destroy());
  server.on('stream', h2Stream(name));
  return server;
}

const h2cServer = h2Face(http2.createServer(), 'h2c');

function h2Server(name, leafOf) {
  const server = h2Face(http2.createSecureServer({ ...leafOf.options, allowHTTP1: false }), name);
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

// A script is a list of steps: write these bytes, wait N ms, hold for a key
// N ms (count it as held for KEY while it waits), end (FIN), reset (RST),
// or stall (write nothing until the client goes); the pattern's, write
// bytes of a body, recording for a pattern's record the bytes the kernel
// took and where a write first stalled; and the sinks', read nothing for N
// ms, read the request's body and write its summary, or read it and drop
// it, each of these two ending the script when the client goes first; and
// answer-at, mirror and seq, which read the body too, their scripts'.
const write = (s) => ({ step: 'write', bytes: typeof s === 'string' ? ascii(s) : s });
const measured = (record, bytes, offset) => ({ step: 'measured', record, bytes, offset });
const wait = (ms) => ({ step: 'wait', ms });
const hold = (key, ms) => ({ step: 'hold', key, ms });
const pauseReading = (ms) => ({ step: 'pause-reading', ms });
const sinkBody = (conn, head, key, list) => ({ step: 'sink', conn, head, key, list });
const readOut = (conn, head) => ({ step: 'read-out', conn, head });
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
// gets the parameters, the request head's bytes and the connection's
// record, whose input a script that reads the body sets.
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
    play: ({ key, fail, how, code, after, then, slow }) => {
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
      const answer = Buffer.concat(head);
      if (slow === null) return [write(answer), END];
      // The head and the body's first byte, then SLOW ms, then the rest.
      const cut = answer.length - body.length + 1;
      return [write(answer.subarray(0, cut)), wait(slow), write(answer.subarray(cut)), END];
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

  // concurrency: a key's requests held at once, and the most so far
  'hold': {
    query: holdQuery,
    play: ({ key, ms }) => [
      hold(key, ms),
      write('HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nheld\n'),
      END,
    ],
  },
  'most': {
    query: attemptsQuery,
    play: ({ key }) => {
      const count = holds.get(key) || { now: 0, most: 0 };
      const body = `held ${count.now} most ${count.most}\n`;
      return [write(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`),
              END];
    },
  },

  // streams: a large body a write at a time, and where its writes stalled
  'pattern': {
    query: patternQuery,
    play: ({ key, bytes, chunk, delay, gap, framing }) => {
      const record = { written: 0, stalled: null };
      stalls.set(key, record);
      const chunked = framing === 'chunked';
      const steps = [write(`HTTP/1.1 200 OK\r\n${chunked ? 'Transfer-Encoding: chunked' : `Content-Length: ${bytes}`}\r\nConnection: close\r\n\r\n`)];
      if (delay > 0) steps.push(wait(delay));
      const body = patternBytes(bytes);
      for (let at = 0; at < bytes; at += chunk) {
        if (at > 0 && gap > 0) steps.push(wait(gap));
        const piece = body.subarray(at, Math.min(at + chunk, bytes));
        if (chunked) steps.push(write(`${piece.length.toString(16)}\r\n`));
        steps.push(measured(record, piece, at));
        if (chunked) steps.push(write('\r\n'));
      }
      if (chunked) steps.push(write('0\r\n\r\n'));
      steps.push(END);
      return steps;
    },
  },
  'stalls': {
    query: attemptsQuery,
    play: ({ key }) => {
      const record = stalls.get(key) || { written: 0, stalled: null };
      const body = `written ${record.written} stalled ${record.stalled === null ? 'none' : record.stalled}\n`;
      return [write(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`),
              END];
    },
  },

  // heads before the final one
  'early': {
    play: () => [write('HTTP/1.1 100 Continue\r\n\r\n'
                       + 'HTTP/1.1 103 Early Hints\r\nLink: </style.css>; rel=preload; as=style\r\n\r\n'),
                 wait(50),
                 write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nearly\n'),
                 END],
  },

  // sinks: a key's request body, read and summed up; and an answer that
  // comes before the body
  'sink': {
    query: (query) => queryOf(query, { key: keyValue, hold: (v) => decimal(v, 0, 60000), list: oneValue }, ['key']),
    play: ({ key, hold: ms, list }, head, conn) => {
      countFor(key);
      conn.input = inputOf();
      return [...(ms > 0 ? [pauseReading(ms)] : []), sinkBody(conn, head, key, list === true), END];
    },
  },
  'arm': {
    query: (query) => {
      const found = queryOf(query, {
        status: (v) => decimal(v, 200, 599),
        mode: (v) => (['close', 'keep', 'cut'].includes(v) ? v : null),
        to: percentDecoded,
        after: (v) => decimal(v, 0, 268435456),
      }, ['status']);
      // after with mode cut alone, which needs it
      if (found === null || (found.mode === 'cut') !== Object.hasOwn(found, 'after')) return null;
      return found;
    },
    play: ({ status, mode, to, after }) => {
      earlyArm = { status, mode: mode || 'close', to: to || null, after: after === undefined ? null : after };
      return [write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\narmed\n'), END];
    },
  },
  // An answer once the body's first N bytes have come, before the rest
  // a connection ended under a body, once N bytes of it have come
  'cut': {
    query: (query) => queryOf(query, { key: keyValue, after: (v) => decimal(v, 0, 268435456) }, ['key', 'after']),
    play: ({ key, after }, head, conn) => {
      countFor(key);
      conn.input = inputOf();
      return [{ step: 'cut', conn, after }];
    },
  },
  'answer-at': {
    query: (query) => queryOf(query, {
      status: (v) => decimal(v, 200, 599),
      after: (v) => decimal(v, 0, 268435456),
      close: (v) => decimal(v, 0, 1),
      to: percentDecoded,
      hold: keyValue,
    }, ['status', 'after']),
    play: ({ status, after, close, to, hold }, head, conn) => {
      conn.input = inputOf();
      const shut = close === 1;
      return [{ step: 'answer-at', conn, head, after, close: shut, answer: earlyAnswer(status, to || null, shut),
                hold: hold === undefined ? null : hold }, END];
    },
  },
  // a raw sink's bytes read for a key, its client gone or not
  'sunk': {
    query: attemptsQuery,
    play: ({ key }) => {
      const record = sunk.get(key);
      const body = `sunk ${record === undefined ? 0 : record.bytes}\n`;
      return [write(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`),
              END];
    },
  },
  // an answer-at's held last byte let go, for its key
  'release': {
    query: attemptsQuery,
    play: ({ key }) => {
      const entry = releaseEntry(key);
      entry.released = true;
      for (const waiter of [...entry.waiters]) waiter();
      return [write('HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\nreleased\n'), END];
    },
  },
  // full duplex: the body written back as it comes, reading paused while a
  // write waits for the kernel
  'mirror': {
    play: (_, head, conn) => {
      const framing = framingOf(headPairs(head));
      if (framing === null) return badRequest;
      conn.input = inputOf();
      const field = framing.kind === 'chunked' ? 'Transfer-Encoding: chunked'
        : `Content-Length: ${framing.kind === 'length' ? framing.length : 0}`;
      return [write(`HTTP/1.1 200 OK\r\n${field}\r\nConnection: close\r\n\r\n`),
              { step: 'mirror', conn, framing }, END];
    },
  },
  // a sink, then a body: the summary in a header, then N bytes of the pattern
  'seq': {
    query: (query) => queryOf(query, { key: keyValue, bytes: (v) => decimal(v, 0, 268435456) }, ['key', 'bytes']),
    play: ({ key, bytes }, head, conn) => {
      countFor(key);
      conn.input = inputOf();
      return [{ step: 'seq', conn, head, key, bytes }, END];
    },
  },
  'answer': {
    query: (query) => queryOf(query, {
      status: (v) => decimal(v, 200, 599),
      close: (v) => decimal(v, 0, 1),
    }, ['status', 'close']),
    play: ({ status, close }, head, conn) => {
      const body = `answer ${status}\n`;
      const answer = write(`HTTP/1.1 ${status} Answer\r\nContent-Length: ${body.length}\r\n`
                           + `${close === 1 ? 'Connection: close\r\n' : ''}\r\n${body}`);
      if (close === 1) return [answer, END];
      conn.input = inputOf();
      return [answer, readOut(conn, head), END];
    },
  },
};

// --- the raw faces' request bodies -----------------------------------------

// inputOf: a body-reading script's input: the bytes of each socket data
// event after the head, with when it came, a performance.now(), in order,
// and whether the client has ended or the socket closed.
function inputOf() {
  return { items: [], ended: false, wake: null };
}

function wakeInput(input) {
  const wake = input.wake;
  input.wake = null;
  if (wake) wake();
}

function feed(input, chunk, at) {
  input.items.push([chunk, at]);
  wakeInput(input);
}

function closeInput(input) {
  input.ended = true;
  wakeInput(input);
}

// nextItem: INPUT's next [CHUNK, AT], waiting for one; null once the
// client has ended and every one is taken.
async function nextItem(input) {
  while (input.items.length === 0) {
    if (input.ended) return null;
    await new Promise((resolve) => { input.wake = resolve; });
  }
  return input.items.shift();
}

// headPairs: the request head HEAD's header lines as a flat list of names
// and values, each value all after the line's first colon; a line with no
// name before a colon is skipped.
function headPairs(head) {
  const pairs = [];
  for (const line of head.toString('latin1').split('\r\n').slice(1)) {
    const at = line.indexOf(':');
    if (at > 0) pairs.push(line.slice(0, at), line.slice(at + 1));
  }
  return pairs;
}

// framingOf: a request body's framing from its header PAIRS: chunked for a
// Transfer-Encoding of chunked, in any case; a length for a Content-Length
// of decimal digits; none for neither; null for any other.
function framingOf(pairs) {
  const te = headerValue(pairs, 'transfer-encoding');
  if (te !== null) return te.toLowerCase() === 'chunked' ? { kind: 'chunked' } : null;
  const cl = headerValue(pairs, 'content-length');
  if (cl !== null) return /^[0-9]{1,15}$/.test(cl) ? { kind: 'length', length: Number(cl) } : null;
  return { kind: 'none' };
}

// readBody: reads a request's body from INPUT by FRAMING, handing TAKE each
// data event's body bytes, as PIECES and AT, when they came. Answers done at
// the framing's end, gone when the client ends first, or bad for chunked
// framing it cannot read: a size line that is not 1 to 8 hex digits and an
// extension, no CRLF after a chunk's bytes, or a line past HEAD_LIMIT; or
// stopped, short of the end, once TAKE answers true.
async function readBody(input, framing, take) {
  if (framing.kind === 'none') return 'done';
  if (framing.kind === 'length') {
    let left = framing.length;
    while (left > 0) {
      const item = await nextItem(input);
      if (item === null) return 'gone';
      const piece = item[0].subarray(0, Math.min(left, item[0].length));
      left -= piece.length;
      if (take([piece], item[1]) === true && left > 0) return 'stopped';
    }
    return 'done';
  }
  // chunked: a size line, its bytes and a CRLF, and so on, to a size of 0,
  // then trailer lines to an empty one
  let state = 'size';
  let left = 0;
  let line = [];
  let lineBytes = 0;
  for (;;) {
    const item = await nextItem(input);
    if (item === null) return 'gone';
    const [chunk, at] = item;
    const pieces = [];
    let i = 0;
    while (i < chunk.length) {
      if (state === 'data') {
        const piece = chunk.subarray(i, i + Math.min(left, chunk.length - i));
        pieces.push(piece);
        i += piece.length;
        left -= piece.length;
        if (left === 0) state = 'data-end';
      } else {
        const lf = chunk.indexOf(0x0a, i);
        const stop = lf < 0 ? chunk.length : lf + 1;
        line.push(chunk.subarray(i, stop));
        lineBytes += stop - i;
        i = stop;
        if (lineBytes > HEAD_LIMIT) return 'bad';
        if (lf >= 0) {
          const text = Buffer.concat(line).toString('latin1');
          line = [];
          lineBytes = 0;
          if (!text.endsWith('\r\n')) return 'bad';
          const content = text.slice(0, -2);
          if (state === 'size') {
            const m = /^([0-9A-Fa-f]{1,8})(?:[ \t]*;.*)?$/.exec(content);
            if (!m) return 'bad';
            left = parseInt(m[1], 16);
            state = left === 0 ? 'trailers' : 'data';
          } else if (state === 'data-end') {
            if (content !== '') return 'bad';
            state = 'size';
          } else if (content === '') {
            take(pieces, at);
            return 'done';
          }
        }
      }
    }
    if (take(pieces, at) === true) return 'stopped';
  }
}

// earlyAnswer: "HTTP/1.1 STATUS Early", a Location header holding TO's
// bytes as they are when TO is not null, Content-Length, Connection: close
// when CLOSE, and the body "early STATUS\n".
function earlyAnswer(status, to, close) {
  const body = `early ${status}\n`;
  return Buffer.concat([
    ascii(`HTTP/1.1 ${status} Early\r\n`),
    ...(to === null ? [] : [ascii('Location: '), to, ascii('\r\n')]),
    ascii(`Content-Length: ${body.length}\r\n${close ? 'Connection: close\r\n' : ''}\r\n${body}`),
  ]);
}

// stalls: the pattern script's latest record for each key, by key, for as
// long as the origin runs: written, the body's bytes the kernel took, and
// stalled, the offset of the first write it had not taken 100 ms after the
// write began, or null.
const stalls = new Map();

// sunk: each raw sink's body record, by its key, the latest for a key, for
// as long as the origin runs: its bytes grow as they are read, so a client
// that goes first leaves the bytes that had come (the slice's fourth
// review: what reached the server of a body refused past its length).
const sunk = new Map();

// releases: for each key /raw/release has named, or an answer-at's hold
// waits on, whether it is released and the holds waiting for it, for as
// long as the origin runs. A release holds for good: a hold that comes
// after it writes at once.
const releases = new Map();

// releaseEntry: KEY's entry in releases, made empty when it has none.
function releaseEntry(key) {
  let entry = releases.get(key);
  if (entry === undefined) {
    entry = { released: false, waiters: new Set() };
    releases.set(key, entry);
  }
  return entry;
}

// releasedFor: resolves 'released' once /raw/release names KEY, at once for
// a key released already; or 'gone' once SOCKET closes first.
function releasedFor(key, socket) {
  const entry = releaseEntry(key);
  if (entry.released) return Promise.resolve('released');
  return new Promise((resolve) => {
    const done = (how) => {
      entry.waiters.delete(onRelease);
      socket.off('close', onClose);
      resolve(how);
    };
    const onRelease = () => done('released');
    const onClose = () => done('gone');
    entry.waiters.add(onRelease);
    socket.once('close', onClose);
    if (socket.destroyed) done('gone');
  });
}

// patternQuery: the pattern script's parameters from QUERY, or null: key,
// as retry takes it, bytes, 1 to 268435456, and chunk, 1 to 1048576, each
// exactly once; delay and gap, 0 to 60000, and framing, length or chunked,
// at most once each, 0, 0 and length when absent.
function patternQuery(query) {
  if (query === undefined) return null;
  const found = { key: null, bytes: null, chunk: null, delay: null, gap: null, framing: null };
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);
    if (!Object.hasOwn(found, name) || found[name] !== null) return null;
    let read;
    switch (name) {
      case 'key': read = retryKey(value) ? value : null; break;
      case 'bytes': read = decimal(value, 1, 268435456); break;
      case 'chunk': read = decimal(value, 1, 1048576); break;
      case 'framing': read = ['length', 'chunked'].includes(value) ? value : null; break;
      default: read = decimal(value, 0, 60000); break;
    }
    if (read === null) return null;
    found[name] = read;
  }
  if (found.key === null || found.bytes === null || found.chunk === null) return null;
  return { key: found.key, bytes: found.bytes, chunk: found.chunk, delay: found.delay || 0,
           gap: found.gap || 0, framing: found.framing || 'length' };
}

// attempts: the retry script's count of the requests it has read for each
// key, by key, for as long as the origin runs.
const attempts = new Map();

// holds: the hold script's counts for each key, by key, for as long as the
// origin runs: now, the requests held now, and most, the most held at once.
const holds = new Map();

// holdQuery: the hold script's parameters from QUERY, or null: key, as
// retry takes it, and ms, 0 to 60000, each exactly once, in any order, and
// nothing else.
function holdQuery(query) {
  if (query === undefined) return null;
  const found = { key: null, ms: null };
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);
    if (!Object.hasOwn(found, name) || found[name] !== null) return null;
    const read = name === 'key' ? (retryKey(value) ? value : null) : decimal(value, 0, 60000);
    if (read === null) return null;
    found[name] = read;
  }
  return found.key === null || found.ms === null ? null : found;
}

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
// otherwise; after at most once, with how=status alone, its bytes; slow at
// most once, 0 to 60000, with how=status alone; then at most once, ok or
// stall, ok when absent.
function retryQuery(query) {
  if (query === undefined) return null;
  const found = { key: null, fail: null, how: null, code: null, after: null, then: null, slow: null };
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
      case 'slow': read = decimal(value, 0, 60000); break;
      default: read = percentDecoded(value); break;
    }
    if (read === null) return null;
    found[name] = read;
  }
  if (found.key === null || found.fail === null || found.how === null) return null;
  if (found.how === 'status' ? found.code === null
    : found.code !== null || found.after !== null || found.slow !== null) {
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

// scriptFor: the steps for the request head HEAD, its CRLF CRLF included, on
// the connection CONN.
function scriptFor(head, conn) {
  const text = head.toString('latin1');
  const parts = text.slice(0, text.indexOf('\r\n')).split(' ');
  if (parts.length !== 3) return badRequest;
  const m = /^\/raw\/([a-z0-9-]+)(?:\?(.*))?$/.exec(parts[1]);
  if (!m || !Object.hasOwn(scripts, m[1])) return badRequest;
  const script = scripts[m[1]];
  const found = script.query ? script.query(m[2]) : parameters(script.params || {}, m[2]);
  return found === null ? badRequest : script.play(found, head, conn);
}

// sinkAnswer: the sink's whole response for the request head HEAD on CONN,
// its header PAIRS and its body's RECORD.
function sinkAnswer(conn, head, pairs, record, key, list) {
  const method = head.toString('latin1').split(' ', 1)[0];
  const body = ascii(summary(conn.face, method, pairs, record, key, list));
  return Buffer.concat([ascii(`HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n`),
                        body]);
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
        case 'measured': {
          // The kernel takes the bytes when the write's callback comes, with
          // no error; a write it has not taken 100 ms on is where the
          // client stopped reading, and the first such is recorded.
          const record = s.record;
          const timer = setTimeout(() => {
            if (record.stalled === null) record.stalled = s.offset;
          }, 100);
          await new Promise((resolve) => socket.write(s.bytes, (err) => {
            clearTimeout(timer);
            if (!err) record.written += s.bytes.length;
            resolve();
          }));
          break;
        }
        case 'wait':
          await pause(socket, s.ms);
          break;
        case 'hold': {
          const count = holds.get(s.key) || { now: 0, most: 0 };
          holds.set(s.key, count);
          count.now += 1;
          count.most = Math.max(count.most, count.now);
          try {
            await pause(socket, s.ms);
          } finally {
            count.now -= 1;
          }
          break;
        }
        case 'pause-reading':
          // Nothing read: the kernel's buffers fill, and the client's
          // writes stall.
          socket.pause();
          await pause(socket, s.ms);
          socket.resume();
          break;
        case 'sink': {
          const record = bodyRecord();
          sunk.set(s.key, record);
          const pairs = headPairs(s.head);
          const framing = framingOf(pairs);
          const result = framing === null ? 'bad' : await readBody(s.conn.input, framing, (pieces, at) => {
            arrive(record, pieces, Math.round((at - s.conn.headAt) * 10));
          });
          if (result === 'gone' || socket.destroyed || !socket.writable) return;
          const bytes = result === 'bad' ? badRequest[0].bytes : sinkAnswer(s.conn, s.head, pairs, record, s.key, s.list);
          await new Promise((resolve) => socket.write(bytes, () => resolve()));
          break;
        }
        case 'read-out': {
          const framing = framingOf(headPairs(s.head));
          if (framing !== null && (await readBody(s.conn.input, framing, () => {})) === 'gone') return;
          break;
        }
        case 'cut': {
          // The bytes after the head, counted as they come, to AFTER; then
          // the connection ended, with nothing written.
          let n = 0;
          while (n < s.after) {
            const item = await nextItem(s.conn.input);
            if (item === null) break;
            n += item[0].length;
          }
          socket.destroy();
          return;
        }
        case 'answer-at': {
          // The answer once AFTER body bytes have come, or at the body's
          // end when it is shorter; with close, the reading then stops, and
          // what the client sends after is dropped.
          const framing = framingOf(headPairs(s.head));
          if (framing === null) {
            await new Promise((resolve) => socket.write(badRequest[0].bytes, () => resolve()));
            break;
          }
          let answered = null;
          // With hold, every byte of the answer but its last, then the last
          // once /raw/release names the hold's key; the client gone first,
          // nothing more.
          const answer = () => {
            const cut = s.hold === null ? s.answer.length : s.answer.length - 1;
            answered = (async () => {
              await new Promise((resolve) => socket.write(s.answer.subarray(0, cut), () => resolve()));
              if (cut === s.answer.length) return;
              if ((await releasedFor(s.hold, socket)) !== 'released' || socket.destroyed || !socket.writable) return;
              await new Promise((resolve) => socket.write(s.answer.subarray(cut), () => resolve()));
            })();
          };
          if (s.after === 0) answer();
          let bytes = 0;
          const result = answered !== null && s.close ? 'stopped' : await readBody(s.conn.input, framing, (pieces) => {
            for (const piece of pieces) bytes += piece.length;
            if (answered === null && bytes >= s.after) answer();
            return answered !== null && s.close;
          });
          if (result === 'stopped') s.conn.input = null;
          if (answered === null && result === 'done' && !socket.destroyed && socket.writable) answer();
          if (answered === null && result === 'bad' && !socket.destroyed && socket.writable) {
            await new Promise((resolve) => socket.write(badRequest[0].bytes, () => resolve()));
          }
          if (answered !== null) await answered;
          if (result === 'gone') return;
          break;
        }
        case 'mirror': {
          // Each data event's body pieces written back, each its own chunk
          // when chunked; while a write waits for the kernel, the socket is
          // paused, so a client that stops reading stops its own upload.
          const chunked = s.framing.kind === 'chunked';
          let waiting = 0;
          const result = await readBody(s.conn.input, s.framing, (pieces) => {
            const out = [];
            for (const piece of pieces) {
              if (piece.length === 0) continue;
              if (chunked) out.push(ascii(`${piece.length.toString(16)}\r\n`), piece, ascii('\r\n'));
              else out.push(piece);
            }
            if (out.length === 0) return;
            if (waiting === 0) socket.pause();
            waiting += 1;
            socket.write(Buffer.concat(out), () => {
              waiting -= 1;
              if (waiting === 0) socket.resume();
            });
          });
          if (result === 'gone') return;
          if (result === 'done' && chunked && !socket.destroyed && socket.writable) {
            await new Promise((resolve) => socket.write('0\r\n\r\n', () => resolve()));
          }
          break;
        }
        case 'seq': {
          const record = bodyRecord();
          const pairs = headPairs(s.head);
          const framing = framingOf(pairs);
          const result = framing === null ? 'bad' : await readBody(s.conn.input, framing, (pieces, at) => {
            arrive(record, pieces, Math.round((at - s.conn.headAt) * 10));
          });
          if (result === 'gone' || socket.destroyed || !socket.writable) return;
          if (result === 'bad') {
            await new Promise((resolve) => socket.write(badRequest[0].bytes, () => resolve()));
            break;
          }
          const method = s.head.toString('latin1').split(' ', 1)[0];
          const line = ascii(summary(s.conn.face, method, pairs, record, s.key, false));
          const head = Buffer.concat([ascii('HTTP/1.1 200 OK\r\nSink: '), line.subarray(0, line.length - 1),
                                      ascii(`\r\nContent-Length: ${s.bytes}\r\nConnection: close\r\n\r\n`)]);
          await new Promise((resolve) => socket.write(head, () => resolve()));
          const body = patternBytes(s.bytes);
          for (let at = 0; at < s.bytes; at += 16384) {
            if (socket.destroyed || !socket.writable) return;
            await new Promise((resolve) => socket.write(body.subarray(at, Math.min(at + 16384, s.bytes)), () => resolve()));
          }
          break;
        }
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

// serveRaw: reads a request head from SOCKET, on the raw face FACE, and
// plays its script, with RESET as the script's reset. The bytes after the
// head go to the script's input when it has one, and nowhere otherwise.
// SCRIPT gives the steps for a head and its connection, scriptFor's unless
// given; OVERLONG, the steps for a head past HEAD_LIMIT, the fixed 400's.
function serveRaw(face, socket, reset, script = scriptFor, overlong = badRequest) {
  // With allowHalfOpen, the client's FIN leaves this side open: a script that
  // is playing goes on; otherwise this side ends too.
  const state = { playing: false, clientEnded: false };
  const conn = { face, headAt: 0, input: null };
  socket.on('end', () => {
    state.clientEnded = true;
    if (conn.input) closeInput(conn.input);
    if (!state.playing) socket.end();
  });
  socket.on('close', () => {
    if (conn.input) closeInput(conn.input);
  });
  let head = Buffer.alloc(0);
  let started = false;
  socket.on('data', (chunk) => {
    const at = performance.now();
    if (started) {
      if (conn.input) feed(conn.input, chunk, at);
      return;
    }
    head = Buffer.concat([head, chunk]);
    const end = head.subarray(0, HEAD_LIMIT).indexOf('\r\n\r\n');
    if (end >= 0) {
      started = true;
      conn.headAt = at;
      const request = Buffer.from(head.subarray(0, end + 4));
      const rest = Buffer.from(head.subarray(end + 4));
      head = null;
      const steps = script(request, conn);
      if (conn.input && rest.length > 0) feed(conn.input, rest, at);
      play(socket, reset, state, steps).catch((err) => fatal('a script failed', err));
    } else if (head.length >= HEAD_LIMIT) {
      started = true;
      head = null;
      play(socket, reset, state, overlong).catch((err) => fatal('a script failed', err));
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

// earlyArm: what /raw/arm set for the raw face's next connection, its
// status, mode and Location bytes, or null.
let earlyArm = null;

// answerAtOnce: SOCKET's whole answer by ARM, written as it is accepted,
// before any byte of its request is read. Mode close: Connection: close,
// then this side ended, and the client's bytes read and dropped until it
// ends. Mode keep: no Connection, then its request read, its head and its
// body to its framing's end, and this side ended. Mode cut: no Connection,
// then its request's head read, and the connection ended, nothing more
// written, once ARM's after bytes of what follows that head have come.
function answerAtOnce(socket, arm) {
  if (arm.mode === 'cut') {
    socket.write(earlyAnswer(arm.status, arm.to, false));
    serveRaw('raw', socket, () => socket.resetAndDestroy(), (head, conn) => {
      conn.input = inputOf();
      return [{ step: 'cut', conn, after: arm.after }];
    }, [END]);
    return;
  }
  if (arm.mode === 'keep') {
    socket.write(earlyAnswer(arm.status, arm.to, false));
    serveRaw('raw', socket, () => socket.resetAndDestroy(), (head, conn) => {
      conn.input = inputOf();
      return [readOut(conn, head), END];
    }, [END]);
    return;
  }
  socket.on('data', () => {});
  socket.on('end', () => { if (!socket.destroyed) socket.end(); });
  socket.end(earlyAnswer(arm.status, arm.to, true));
}

const rawServer = net.createServer({ allowHalfOpen: true }, (socket) => {
  rawSocket(socket);
  if (earlyArm !== null) {
    const arm = earlyArm;
    earlyArm = null;
    answerAtOnce(socket, arm);
    return;
  }
  serveRaw('raw', socket, () => socket.resetAndDestroy());
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
    serveRaw('raw-tls', socket, () => raw.resetAndDestroy());
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
  faces.push(['https', httpsServer('https', good)],
             ['https-expired', httpsServer('https-expired', expired)],
             ['https-wrong-host', httpsServer('https-wrong-host', wrongHost)],
             ['https-untrusted', httpsServer('https-untrusted', untrusted)],
             ['raw-tls', rawTlsServer(good)],
             ['h2', h2Server('h2', good)]);
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
