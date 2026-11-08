// tests/origin.mjs: chez-curl's test origin (ADR-0005, amended; M1 plan,
// sections 3, 4 and 8). One ES module, Node's standard library only, for Node
// 20 and later (measured on 20.10.0 and 24.18.0).
//
// The contract:
//   - `node tests/origin.mjs [--pki DIR | --selftest [PLANT]]`. With no
//     argument it serves the plaintext faces. --pki DIR adds the TLS faces,
//     which read their leaves from DIR, as tests/make-test-pki.sh makes it.
//     --selftest serves nothing: it checks the auth route's Digest
//     arithmetic (below) against RFC 2617's and RFC 7616's published
//     vectors, and four controls that must each change the answer, and
//     prints "selftest ok 13" and exits 0, or prints "selftest FAIL WHAT"
//     for each check that failed and exits 1. With PLANT it plants that
//     fault in the arithmetic first, so the self-test is seen to fail:
//     nc-before-nonce swaps the nonce and nc in a qop response, and
//     sess-ignored makes -sess change nothing. Any other argument, or a
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
//         Connection: close back when Node will close. It is also a proxy,
//         as every https face is (the proxy, below).
//           GET /status/CODE             200-599: status CODE, body "status CODE\n"
//           GET /redirect/CODE?to=TARGET 300-308: Location: TARGET, decoded,
//                                        body "redirect CODE\n"
//           GET /chunked                 three writes, each its own chunk
//           ANY /echo                    the request as Node parsed it
//           ANY /json[?QUERY]            the JSON route, below
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
//           ANY /auth?key=K&ch=CH[&...]  the auth route, below
//           GET /auth-log?key=K          the auth route's log for K, below
//           GET /proxy-log?from=N        the proxy's log from line N, below
//           GET /proxy-arm?n=N[&line=L]  arms the proxy: the next CONNECT it
//                                        answers 200 carries N header lines,
//                                        0 to 100000, of L bytes, 13 to 65536,
//                                        16 when left out, as the head
//                                        routes make them (below), once; 200,
//                                        body "armed\n"
//           ANY /parts?key=K[&hold=1][&lines=N][&fail=F]  the parts route,
//                                        below
//           ANY /cookies[/P]?key=K[&...] the cookie route, below
//           GET /cookie-log?key=K        the cookie route's log for K, below
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
//         /raw/location?code=CODE[&ms=N][&key=K][&to=BYTES]... reads its own
//         query: code once, 200 to 599; ms at most once, 0 to 60000, 0 when
//         left out; key at most once, as retry takes it, counted for K as the
//         head arrives, as /sink counts, so /seen?key=K tells the request
//         came; to any number of times, each percent-decoded, %XX in either
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
//         on it writes its last byte, and every HTTP/2 /answer held on it
//         answers. It writes "HTTP/1.1 200 OK",
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
//         /raw/head?SPEC writes the head SPEC names (the head routes,
//         below), status 200, and ends. /raw/head-auth?a.SPEC&b.SPEC, a
//         Digest round's two answers: a request with no Authorization header
//         gets a 401 by a., www-authenticate: Digest realm="chez-curl-test",
//         qop="auth", nonce="n0", algorithm=MD5 first; one with any, unchecked,
//         a 200 by b.; then the end. /raw/head417?key=KEY&a.SPEC&b.SPEC, KEY as
//         retry takes it, a 417 and its resend: KEY's first request whose
//         Expect holds 100-continue gets a 417 by a. as its head arrives, kept
//         alive, and the next bytes decide as auth417's do (below); every
//         later request for KEY, on that connection or another, gets
//         "HTTP/1.1 100 Continue" when its Expect holds 100-continue, its body
//         read by its Content-Length, then a 200 by b.; so does a first
//         request without that Expect; then the end. A spec the head routes
//         refuse, or no key, gets the fixed 400.
//         /raw/auth417?key=KEY, KEY as retry takes it, serves the
//         connection's requests one after another, kept alive: one whose
//         Expect holds 100-continue, in any ASCII case, gets "HTTP/1.1 417
//         Expectation Failed", Content-Length: 19 and "expectation failed\n"
//         as its head arrives, and the next bytes decide: a first byte A to
//         Z begins the next request, any other begins the refused request's
//         body, read by its Content-Length and dropped; any other request
//         has its body read by its Content-Length, none without one, and
//         gets "HTTP/1.1 200 OK", Content-Length: 8 and "auth ok\n". Each
//         request is logged to KEY's auth log, as the auth route's are
//         (below), judged by the default account. The client's end ends it.
//   h2c   node:http2, plaintext, by prior knowledge: the HTTP/2 routes. Its
//         send limit, maxSendHeaderBlockLength, raised to 64 MiB, as h2's is.
//         Half-open (allowHalfOpen), as h2 is: a client's end, its FIN, or
//         over TLS its close_notify, ends the connection at the next
//         immediate, once Node has written what waited on a write it had in
//         progress. Node's own end came at once, and over TLS lost an
//         RST_STREAM queued behind the SETTINGS ACK (M7's carried races).
//   With --pki DIR:
//   https, https-expired, https-wrong-host, https-untrusted
//         node:https, serving DIR's good, expired, wrong-host and untrusted
//         leaf, with ALPN http/1.1 alone: http's routes and bytes, and the
//         proxy, so each serves as an https:// proxy, the last three as
//         failing ones.
//   raw-tls
//         node:net, each socket wrapped in a server tls.TLSSocket with the
//         good leaf and ALPN http/1.1: raw's scripts. A reset resets the TCP
//         socket under the TLS one: resetAndDestroy() on a TLS socket throws
//         ERR_INVALID_HANDLE_TYPE (measured).
//   h2    node:http2, secure, with the good leaf, ALPN h2 alone and no
//         HTTP/1.1: the HTTP/2 routes, half-open as h2c is. A client that
//         does not choose h2 has its socket destroyed at once, with no byte
//         written. Without the unknownProtocol listener, Node 20.10.0 and
//         24.18.0 write "HTTP/1.0 403 Forbidden ... Missing ALPN Protocol
//         ..." to it, then close (measured), and a client would read that as
//         a response.
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
// with content-length. /answer?status=S[&hold=KEY], HTTP/2's alone,
// answers S, content-length and "answer S\n", or for 204, 304 and 205 as
// /status does, as the headers arrive, ending its side; with hold=KEY, KEY
// as retry takes it, at most once, the answer waits until /raw/release
// names KEY, at once when it has, and never comes once the stream has
// closed; it reads the body meanwhile, and after, if any, and answers
// nothing more. It counts nothing.
// /refuse?key=K&at=N, HTTP/2's alone, N 0 to 268435456, counts as /sink
// does; the first request for K is reset with RST_STREAM REFUSED_STREAM
// once N DATA bytes have come, N 0 as its headers arrive, before any DATA;
// a later one, or a first whose body ends short of N, is answered as /sink.
// A client's end that comes with the request leaves the RST_STREAM written
// first (h2c's, above).
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
// /head?SPEC and /head-auth?a.SPEC&b.SPEC, HTTP/2's alone, answer as the
// raw face's /raw/head and /raw/head-auth do (the head routes, below), a
// trailer block in a trailers HEADERS frame, a 1xx head in a HEADERS frame of
// its own; a spec they refuse, or one naming hname, tname or v10, is 404.
// /seq?key=K&bytes=N, HTTP/2's alone, N 0 to 268435456, counts as /sink
// does and reads the body whole; then answers :status 200, a sink header
// holding the summary line without its newline, content-length N, and N
// bytes of the pattern, as /pattern/N writes them.
// /parts and /json are http's, below.
// Anything else, /chunked, /connects and /close-after included, is 404,
// "not found\n". No date, and no header beyond these.
//
// The parts route (M8 slice 3; the M8 plan, section 6), on http, the https faces, h2c and
// h2 alike: ANY /parts?key=K[&hold=1][&lines=N][&fail=F], each name once at
// most, K a key as retry takes it. It counts for K as its head arrives, as /sink does,
// so /seen?key=K tells that the head came. A request whose Expect holds
// 100-continue, in any ASCII case, gets a 100 at once; with hold=1, only once
// /raw/release names K, and none once the request has gone. The body is read
// whole, then the answer is 200 with its report, which a multipart body's
// parts fill, by the first boundary= of its Content-Type:
//   parts FACE method=M cl=CL te=TE expect=E ct=CT bytes=N sha256=HEX boundary=B preamble=P closed=C epilogue=Q count=K
//   part I headers=ESC len=L sha256=H pattern=P data=ESC
// CL, TE, E and CT as the sink's line; B the boundary, - for none; P the
// bytes before the first delimiter; C 1 when the closing delimiter came, 0
// when the body ended first; Q the bytes after it; then each part, ESC its
// header lines escaped as the auth log escapes bytes, but | as \x7c, joined
// by |, L its data's bytes, H their SHA-256's first 16 hex digits, P ok
// when byte k is k mod 251 for every k, else bad@k for the first that is not, and ESC
// its data escaped so, or - past 256 bytes; a part the body ended inside is
// "unterminated", its data to the body's end. With lines=N, 2 to 100000, the
// answer carries N header lines in all, its framing ones among them: http's
// Content-Length and Connection, HTTP/2's content-length, then x-pI: v.
// With fail=F, 1 to 10, the answer's status is 503, its report as ever,
// while K's count, this request's own among it, is F or less, so a retry
// policy's resends each show what they sent; 200 after.
//
// The JSON route (M8 slice 5; the M8 plan, section 3.10), on http, the https
// faces, h2c and h2 alike: ANY /json, with any query or none, a stand-in for
// a JSON API that insists on its headers. It counts and keeps nothing, so a
// request gets the same bytes every time. A header's value is the values of
// every header of its name, in any case, joined by ", ", each as Node read
// it, Latin-1; a media type is a value's text before its first ;, spaces and
// tabs trimmed, A to Z folded. The answer, the first rule that holds:
//   406 unless Accept, split at each comma, holds a range whose media type is
//       application/json: */* alone is not enough, and a range's parameters,
//       q among them, are ignored;
//   415 for a POST, PUT or PATCH unless Content-Type's media type is
//       application/json, its parameters ignored;
//   400 for a POST, PUT or PATCH unless its body is UTF-8, every sequence
//       well formed, that JSON.parse takes whole: a byte-order mark is kept,
//       and is no JSON;
//   201 for a POST, PUT or PATCH; 200 for any other method, its body unread.
// Each is Content-Type: application/json (content-type over HTTP/2), then
// Content-Length (content-length), then http's Connection, and its body one
// line of JSON, with no newline, as JSON.stringify writes it, the members in
// this order: M the method and T the target as received, :path over HTTP/2;
// A and CT the Accept and Content-Type values, or null for none; N the body's
// bytes; V the body as JSON.parse read it:
//   406  {"error":"not-acceptable","accept":A}
//   415  {"error":"unsupported-media-type","content-type":CT}
//   400  {"error":"not-utf-8","bytes":N} or {"error":"not-json","bytes":N}
//   200  {"method":M,"target":T,"accept":A}
//   201  {"method":M,"target":T,"content-type":CT,"bytes":N,"json":V}
//
// The auth route (M7 slice 2; the M7 plan, section 5.2), on http, the https
// faces, h2c and h2 alike: ANY /auth, its query NAME=VALUE pairs as /sink's are,
// each name once at most:
//   key=K    required, as /sink's: the log the request joins
//   ch=CH    required: the scheme a request must pass, basic, digest or
//            bearer; or none, a 401 with no challenge, always; or open, a
//            200, always
//   u=, p=, tok=  the account's user, password and token, each its bytes
//            percent-decoded, %XX in either case, every other char its own
//            byte, empty allowed; user, pass and tok123 when left out
//   alg=A    Digest's algorithm, MD5, MD5-sess, SHA-256, SHA-256-sess,
//            SHA-512-256 or SHA-512-256-sess; MD5 when left out
//   qop=Q    auth, offered as qop="auth", or none, no qop; auth when left out
//   nonce=N  the challenge's nonce, as a key is spelt, and a stale one's
//            N-J, J the stale challenges the key's log has had, from 1; a
//            fresh one, n then a count of every challenge, for each when
//            left out
//   stale=forever  every Digest answer that passes gets a 401 with a fresh
//            nonce and stale=true in place of its 200
//   size=N   a 200's body is N bytes of the pattern, 1 to 268435456,
//            written as /pattern/N's; "auth ok\n" when left out
// A request's credentials are its first Authorization header's, judged by
// its own scheme: Basic, its base64 decoding the account's user, a colon
// and its password; Bearer, the bytes after "Bearer " the token; Digest,
// by RFC 7616's arithmetic (RFC 2069's with no qop), against a nonce this
// origin issued, the realm chez-curl-test, the request's own target as uri,
// the opaque opq5ccb, the algorithm the query names, the qop offered, and
// the account. A request whose credentials pass in the scheme CH names
// gets 200; any other, 401, with the challenge, one WWW-Authenticate
// header (www-authenticate over HTTP/2):
//   Basic realm="chez-curl-test"
//   Bearer realm="chez-curl-test"
//   Digest realm="chez-curl-test", [qop="auth", ]nonce="N", opaque="opq5ccb", algorithm=A[, stale=true]
// and the body "unauthorized\n". Each request is numbered for its key from
// 1, as its head arrives, and logged, once answered, as one line:
//   request N face=FACE conn=C method=M body=B verdict=V status=S authorization=VALUE
// FACE the face's name; C its connection's number among that face's, from
// 1, a TLS face's counted at each handshake, h2's by session, a raw face's
// among its /raw/auth417 connections; B the body's bytes read, then :bad@I
// when byte I is not the pattern's, or - for a 417 that read none; V none,
// for no Authorization, ok, bad, other, for a scheme but these three, or
// bad(ISSUES) for Digest, each of nonce, realm, uri, opaque, algorithm,
// username, qop, nc, cnonce and response that failed, in that order; S the
// status answered; VALUE the first
// Authorization's bytes, printable ASCII as it is but \ as \\, every
// other byte as \xNN in lower case, then " (+K more)" for K more such
// headers, or - for none. GET /auth-log?key=K answers 200 with "log K N\n",
// N the requests counted for K, then the first 64 lines, each ending
// "\n", in their order, then "more M\n" when M more were counted. Logs and
// nonces live as long as the origin. The raw faces' /raw/auth417?key=K,
// above, logs to the same logs: a node:http face cannot keep a connection
// whose request's body never comes, which a 417's resend needs, and libcurl
// resends after a 417 only on a connection it keeps.
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
// The proxy (M7 slice 3; the M7 plan, section 6.2), on http and the https
// faces alike. A CONNECT is answered by its target, HOST:PORT:
//   127.0.0.1:PORT, PORT one of this origin's faces: "HTTP/1.1 200
//            Connection Established", then both ways piped to that face,
//            whatever Proxy-Authorization it carries;
//   localhost:PORT, PORT one of them: the same, when its first
//            Proxy-Authorization is Basic for alice and s3cret or for bob
//            and hunter2, byte for byte; else 407, below. The face reached
//            is 127.0.0.1's: a TLS face's leaf names localhost;
//   refuse-S.invalid:PORT, S 403, 407, 502 or 503, any port: "HTTP/1.1 S
//            REASON", for 407 Proxy-Authenticate: Basic
//            realm="chez-curl-proxy", then Content-Length and the body
//            "proxy S\n", the connection kept, so a refusal is no close;
//            a byte the client sends after it, or its end, ends the
//            connection;
//   close.invalid:PORT: the connection ended, nothing written;
//   anything else: 403, Content-Length: 0, Connection: close, and the end.
// A request whose target is in absolute form, http://, is the face's own,
// routed by its path (http, above). Each client connection a CONNECT or such
// a request comes on is the proxy's from then on, numbered from 1 among the
// proxy's, across faces, as the first arrives. The proxy's log, one line
// each, in the order they happen:
//   connect FACE conn=C target=T answer=A head=N auth=V
//   request FACE conn=C method=M target=T auth=V
//   inner FACE via=C method=M target=T
//   close FACE conn=C
// connect: a CONNECT, A its answer's status, or close; N the head's bytes as
// libcurl sends one, the request line and each header "NAME: VALUE", CRLF
// each, then CRLF, rebuilt from what Node parsed. request: a request in
// absolute form. inner: a request on FACE, http's, an https face's or h2's,
// that came through the tunnel of the proxy's connection C, found by the
// tunnel's live socket to the face, dropped as it closes, so a later
// connection on its ephemeral port is never taken for it. close: one of the
// proxy's connections closed. T is the target as received and V the first
// Proxy-Authorization, - for none, basic: and its base64 decoded, else
// other: and its value, each as the auth log escapes bytes, then
// " (+K more)" for K more. GET /proxy-log?from=N, N 0 or more, answers 200
// "proxy-log L open K\n", L the lines so far and K the proxy's connections
// open now, then lines N + 1 to L, each ending "\n". The log lives as long
// as the origin.
//
// The cookie route (M7 slice 4; the M7 plan, section 6.4), on http and the
// https faces alike: ANY /cookies, or any path below it, /cookies/a/b/page
// say, the path a cookie's default path is made from, its query NAME=VALUE
// pairs:
//   key=K      required, once, as /sink's: the log the request joins
//   status=S   at most once, 200 to 599; 200 when left out
//   to=TARGET  at most once: a Location header, TARGET decoded as /redirect's
//   set=BYTES  any number of times, in order: a Set-Cookie header each, its
//              value BYTES percent-decoded as the auth route's u= is, %XX in
//              either case, every other char its own byte, written byte for
//              byte; a value holding a byte no header carries, 0x00 to 0x08,
//              0x0A to 0x1F or 0x7F, is refused, and so is a malformed %
//   pad=P      at most once, P 1 to 60000 of the letter p: nothing but the
//              request line's length
// A query that breaks these gets the 404. The answer: S, then each
// Set-Cookie in order, then Location when to is given, then Content-Length
// and Connection, and as its body the request's log line and "\n", but for
// 204 and 304, which carry no body. Each request is numbered for its key
// from 1, as its head arrives, and logged once its body is read, one line:
//   request N face=FACE host=HOST cookies=C cookie="VALUE" ...
// HOST the first Host header's value, quoted as a VALUE is, or - for none;
// C the request's Cookie headers, in any case, and then each one's value,
// as Node parsed it, in order, its bytes as the auth log escapes them, a "
// as \x22. GET /cookie-log?key=K answers 200 with "cookie-log K N\n", N the
// lines logged for K, then each line, ending "\n", in their order. On the
// http face, a connection that closes holding bytes after its last blank
// line, a head whose blank line never came, whose request line is a
// /cookies request's, logs to that request's key, in its turn:
//   open-head face=http bytes=B headers="BYTES"
// B the bytes it held, its request line among them, and BYTES those after
// the request line's CRLF, quoted as a VALUE is: libcurl's head left open,
// by a Cookie line past its cap, which no complete-head log would show.
// The face keeps its connections alive, as Node does, so no transfer meets
// a connection the origin closed unsaid. The logs live as long as the
// origin.
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
  process.stderr.write(`origin: ${problem}\nusage: node tests/origin.mjs [--pki DIR | --selftest [PLANT]]\n`);
  process.exit(2);
}

// The faults --selftest PLANT can plant in the Digest arithmetic.
const PLANTS = ['nc-before-nonce', 'sess-ignored'];

const args = process.argv.slice(2);
let pki = null;
// selftestPlant: undefined to serve; null for --selftest; a plant's name.
let selftestPlant;
if (args.length === 2 && args[0] === '--pki') {
  if (args[1] === '') refuse('--pki takes DIR, a directory, and was given an empty one');
  pki = args[1];
} else if (args.length === 1 && args[0] === '--selftest') {
  selftestPlant = null;
} else if (args.length === 2 && args[0] === '--selftest') {
  if (!PLANTS.includes(args[1])) {
    refuse(`--selftest plants ${PLANTS.join(' or ')}, and was given ${JSON.stringify(args[1])}`);
  }
  selftestPlant = args[1];
} else if (args.length !== 0) {
  refuse(`it takes no argument, --pki DIR, or --selftest [PLANT], and was given ${JSON.stringify(args)}`);
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
  if (path === '/json') return { kind: 'json' };
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
    return queried('answer', queryOf(query, { status: (v) => decimal(v, 200, 599), hold: keyValue }, ['status']));
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
  if (path === '/auth') {
    const one = (allowed) => (v) => (allowed.includes(v) ? v : null);
    return queried('auth', queryOf(query, {
      key: keyValue,
      ch: one(['basic', 'digest', 'bearer', 'none', 'open']),
      u: accountBytes,
      p: accountBytes,
      tok: accountBytes,
      alg: one(DIGEST_ALGORITHMS),
      qop: one(['auth', 'none']),
      nonce: keyValue,
      stale: one(['forever']),
      size: (v) => decimal(v, 1, 268435456),
    }, ['key', 'ch']));
  }
  if (path === '/auth-log') return queried('auth-log', queryOf(query, { key: keyValue }, ['key']));
  if (path === '/head') {
    const spec = headQuery(query);
    return spec === null || rawOnly(spec) ? { kind: 'not-found' } : { kind: 'head', spec };
  }
  if (path === '/head-auth') {
    const specs = flowQuery(query);
    return specs === null || rawOnly(specs.a) || rawOnly(specs.b) ? { kind: 'not-found' } : { kind: 'head-auth', ...specs };
  }
  if (path === '/proxy-arm') {
    return queried('proxy-arm', queryOf(query, { n: (v) => decimal(v, 0, 100000), line: (v) => decimal(v, 13, 65536) }, ['n']));
  }
  if (path === '/proxy-log') {
    return queried('proxy-log', queryOf(query, { from: (v) => decimal(v, 0, 1000000000) }, ['from']));
  }
  if (path === '/parts') {
    return queried('parts', queryOf(query, { key: keyValue, hold: oneValue, lines: (v) => decimal(v, 2, 100000),
                                             fail: (v) => decimal(v, 1, 10) }, ['key']));
  }
  if (path === '/cookies' || path.startsWith('/cookies/')) return queried('cookies', cookieQuery(query));
  if (path === '/cookie-log') return queried('cookie-log', queryOf(query, { key: keyValue }, ['key']));
  return { kind: 'not-found' };
}

// cookieQuery: the cookie route's query, its pairs NAME=VALUE, the value
// after the first =: key, once and required, a key as retry takes it;
// status, at most once, 200 to 599; to, at most once, decoded as
// headerTarget decodes; set, any number of times, accountBytes' bytes, none
// of 0x00 to 0x08, 0x0A to 0x1F and 0x7F; pad, at most once, 1 to 60000 of
// the letter p. The answer: { key, status, to, set }, status 200 and to
// null when left out, set the values in order; or null for a pair with no
// =, a name it does not take, a repeat, or a value refused.
function cookieQuery(query) {
  if (query === undefined) return null;
  const found = { status: 200, to: null, set: [] };
  const seen = new Set();
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    const name = pair.slice(0, at);
    const value = pair.slice(at + 1);
    if (name !== 'set') {
      if (seen.has(name)) return null;
      seen.add(name);
    }
    if (name === 'key') {
      if (!retryKey(value)) return null;
      found.key = value;
    } else if (name === 'status') {
      const status = decimal(value, 200, 599);
      if (status === null) return null;
      found.status = status;
    } else if (name === 'to') {
      const to = headerTarget(value);
      if (to === null) return null;
      found.to = to;
    } else if (name === 'set') {
      const bytes = accountBytes(value);
      if (bytes === null || bytes.some((b) => (b < 0x20 && b !== 0x09) || b === 0x7f)) return null;
      found.set.push(bytes);
    } else if (name === 'pad') {
      if (!/^p{1,60000}$/.test(value)) return null;
    } else {
      return null;
    }
  }
  return found.key === undefined ? null : found;
}

// accountBytes: a query value's bytes, each %XX, in either case, the byte
// it names, every other char its own byte; or null for a malformed %. An
// empty value is no bytes.
function accountBytes(text) {
  const bytes = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '%') {
      if (!/^[0-9A-Fa-f]{2}$/.test(text.slice(i + 1, i + 3))) return null;
      bytes.push(parseInt(text.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      bytes.push(text.charCodeAt(i) & 0xff);
    }
  }
  return Buffer.from(bytes);
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

// --- the parts route (M8 slice 3) -------------------------------------------

// partsEscaped: BYTES as the parts report shows them.
function partsEscaped(bytes) {
  let text = '';
  for (const b of bytes) {
    if (b === 0x5c) text += '\\\\';
    else if (b >= 0x20 && b < 0x7f && b !== 0x7c) text += String.fromCharCode(b);
    else text += `\\x${b.toString(16).padStart(2, '0')}`;
  }
  return text;
}

// partsReport: the parts route's answer for a request on FACE, with
// METHOD, the header PAIRS and the whole BODY.
function partsReport(face, method, pairs, body) {
  const field = (name) => {
    const value = headerValue(pairs, name);
    return value === null ? '-' : value.replace(/[\t\n\v\f\r ]/g, '_');
  };
  const ct = headerValue(pairs, 'content-type') || '';
  const m = /boundary=([^;]*)/i.exec(ct);
  const boundary = m ? m[1] : null;
  const lines = [];
  let preamble = '-';
  let closed = 0;
  let epilogue = '-';
  if (boundary !== null && boundary !== '') {
    const delim = Buffer.from(`--${boundary}`, 'latin1');
    const next = Buffer.from(`\r\n--${boundary}`, 'latin1');
    let at = body.indexOf(delim);
    if (at >= 0) {
      preamble = at;
      let i = 0;
      for (;;) {
        const after = at + delim.length;
        const tail = body.subarray(after, after + 2).toString('latin1');
        if (tail === '--') {
          closed = 1;
          epilogue = body.length - (after + 2);
          break;
        }
        if (tail !== '\r\n') {
          lines.push(`part ${i} malformed-after-delimiter`);
          break;
        }
        const start = after + 2;
        const headEnd = body.indexOf(Buffer.from('\r\n\r\n', 'latin1'), start);
        const end = body.indexOf(next, start);
        let headers;
        let dataStart;
        if (headEnd >= 0 && (end < 0 || headEnd < end)) {
          headers = body.subarray(start, headEnd);
          dataStart = headEnd + 4;
        } else {
          headers = Buffer.alloc(0);
          dataStart = start;
        }
        const heads = [];
        let from = 0;
        for (;;) {
          const crlf = headers.indexOf(Buffer.from('\r\n', 'latin1'), from);
          if (crlf < 0) { if (from < headers.length) heads.push(headers.subarray(from)); break; }
          heads.push(headers.subarray(from, crlf));
          from = crlf + 2;
        }
        const data = body.subarray(dataStart, end < 0 ? body.length : end);
        const hash = createHash('sha256').update(data).digest('hex').slice(0, 16);
        let bad = -1;
        for (let k = 0; k < data.length; k++) if (data[k] !== k % 251) { bad = k; break; }
        lines.push(`part ${i} headers=${heads.map(partsEscaped).join('|')} len=${data.length} sha256=${hash} pattern=${bad < 0 ? 'ok' : `bad@${bad}`} data=${data.length <= 256 ? partsEscaped(data) : '-'}${end < 0 ? ' unterminated' : ''}`);
        if (end < 0) break;
        at = end + 2;
        i += 1;
      }
    }
  }
  const head = [`parts ${face}`, `method=${method}`, `cl=${field('content-length')}`, `te=${field('transfer-encoding')}`,
                `expect=${field('expect')}`, `ct=${field('content-type')}`, `bytes=${body.length}`,
                `sha256=${createHash('sha256').update(body).digest('hex')}`, `boundary=${boundary === null ? '-' : partsEscaped(Buffer.from(boundary, 'latin1'))}`,
                `preamble=${preamble}`, `closed=${closed}`, `epilogue=${epilogue}`,
                `count=${lines.filter((l) => l.startsWith('part ')).length}`].join(' ');
  return [head, ...lines].map((l) => `${l}\n`).join('');
}

// partsPads: the x-pI header pairs that bring an answer of FRAMING framing
// lines to LINES in all, none when LINES is absent.
function partsPads(lines, framing) {
  const pads = [];
  if (lines !== undefined) for (let i = 0; i < lines - framing; i++) pads.push(`x-p${i}`, 'v');
  return pads;
}

// partsStatus: the parts route's status for route R, the request counted
// N-th for its key: 503 while N is F or less, with fail=F, else 200.
function partsStatus(r, n) {
  return r.fail !== undefined && n <= r.fail ? 503 : 200;
}

// partsContinues: whether a request's Expect, as PAIRS hold it, holds
// 100-continue, A to Z folded.
function partsContinues(pairs) {
  const value = headerValue(pairs, 'expect');
  return value !== null && value.toLowerCase().includes('100-continue');
}

// --- the auth route: Digest's arithmetic, the verdicts, the log ----------
// The arithmetic, its self-test and its parser are M7 slice 2's stand-in's
// (.plans/research/m7/slice2/standin.mjs), unchanged but for the plants.

const REALM = 'chez-curl-test';
const OPAQUE = 'opq5ccb';

// DIGEST_ALGORITHMS: the algorithms alg= names, each a challenge's token.
const DIGEST_ALGORITHMS = ['MD5', 'MD5-sess', 'SHA-256', 'SHA-256-sess', 'SHA-512-256', 'SHA-512-256-sess'];

// The hash each algorithm's base names, in node:crypto's names.
const HASHES = { md5: 'md5', 'sha-256': 'sha256', 'sha-512-256': 'sha512-256' };

const latin1 = (s) => Buffer.from(s, 'latin1');
const joined = (...parts) => Buffer.concat(parts.map((p) => (Buffer.isBuffer(p) ? p : latin1(String(p)))));
const hasher = (name) => (bytes) => createHash(name).update(bytes).digest('hex');

// escaped: BYTES as a log shows them: printable ASCII as it is, but \ as
// \; every other byte as \xNN, lower case.
function escaped(bytes) {
  let text = '';
  for (const b of bytes) {
    if (b === 0x5c) text += '\\\\';
    else if (b < 0x20 || b > 0x7e) text += `\\x${b.toString(16).padStart(2, '0')}`;
    else text += String.fromCharCode(b);
  }
  return text;
}

// algorithmOf: NAME's hash and whether it is -sess, or null.
function algorithmOf(name) {
  const lower = name.toLowerCase();
  const sess = lower.endsWith('-sess');
  const base = sess ? lower.slice(0, -5) : lower;
  return HASHES[base] ? { base: HASHES[base], sess } : null;
}

// The plant --selftest PLANT set, or null: the route's arithmetic is never
// planted.
let plant = null;

// digestResponse: RFC 7616, section 3.4.1, with RFC 2069's form when there
// is no qop: the response, in lower-case hex, for USER and PASS, bytes, and
// the rest as the credentials carry them; BODY for auth-int.
function digestResponse(hashName, sess, user, realm, pass, nonce, cnonce, nc, qop, method, uri, body) {
  const h = hasher(hashName);
  let ha1 = h(joined(user, ':', realm, ':', pass));
  if (sess && plant !== 'sess-ignored') ha1 = h(joined(ha1, ':', nonce, ':', cnonce));
  const ha2 = qop === 'auth-int' ? h(joined(method, ':', uri, ':', h(body))) : h(joined(method, ':', uri));
  if (!qop) return h(joined(ha1, ':', nonce, ':', ha2));
  return plant === 'nc-before-nonce'
    ? h(joined(ha1, ':', nc, ':', nonce, ':', cnonce, ':', qop, ':', ha2))
    : h(joined(ha1, ':', nonce, ':', nc, ':', cnonce, ':', qop, ':', ha2));
}

// parseParams: a challenge's or credentials' auth-params, after the scheme,
// each value a latin1 string, so it keeps its bytes, a quoted one with its
// quoted-pairs undone.
function parseParams(text) {
  const found = {};
  const re = /\s*([A-Za-z0-9_*-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^,]*?))\s*(?:,|$)/gy;
  let m;
  while (re.lastIndex < text.length && (m = re.exec(text))) {
    const name = m[1].toLowerCase();
    found[name] = m[2] !== undefined ? m[2].replace(/\\(.)/g, '$1') : m[3];
  }
  return found;
}

// selftest: the arithmetic against RFC 2617's and RFC 7616's worked
// examples, and four controls that must change the answer; the parser and
// the escaping. Prints "selftest ok N" and exits 0, or "selftest FAIL WHAT"
// for each failure and exits 1. PLANTED, a plant's name or null, is set
// first.
function selftest(planted) {
  plant = planted;
  const fails = [];
  let n = 0;
  const check = (label, got, want) => {
    n += 1;
    if (got !== want) fails.push(`${label}: got ${got}, want ${want}`);
  };
  // RFC 2617, section 3.5.
  check('rfc2617 md5 auth',
        digestResponse('md5', false, latin1('Mufasa'), 'testrealm@host.com', latin1('Circle Of Life'),
                       'dcd98b7102dd2f0e8b11d0f600bfb0c093', '0a4f113b', '00000001', 'auth', 'GET',
                       '/dir/index.html', Buffer.alloc(0)),
        '6629fae49393a05397450978507c4ef1');
  // RFC 7616, section 3.9.1, MD5 and SHA-256.
  const r7616 = (h) => [h, false, latin1('Mufasa'), 'http-auth@example.org', latin1('Circle of Life'),
    '7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v', 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ',
    '00000001', 'auth', 'GET', '/dir/index.html', Buffer.alloc(0)];
  check('rfc7616 md5 auth', digestResponse(...r7616('md5')), '8ca523f5e9506fed4657c9700eebdbec');
  check('rfc7616 sha-256 auth', digestResponse(...r7616('sha256')),
        '753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1');
  // RFC 7616, section 3.9.2's SHA-512-256 example carries an erratum: FIPS
  // 180-4's SHA-512/256 of nothing stands for it.
  check('sha512-256 of nothing', hasher('sha512-256')(Buffer.alloc(0)),
        'c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a');
  // The controls: each must differ from the good answer.
  const good = digestResponse(...r7616('sha256'));
  const control = (label, changed) => {
    n += 1;
    if (changed === good) fails.push(label);
  };
  const w1 = r7616('sha256'); w1[4] = latin1('Circle of life');
  control('a wrong password passed', digestResponse(...w1));
  const w2 = r7616('sha256'); w2[8] = 'auth-int'; w2[11] = latin1('x');
  const w3 = r7616('sha256'); w3[8] = 'auth-int';
  n += 1;
  if (digestResponse(...w2) === digestResponse(...w3)) fails.push('auth-int ignored the body');
  control('the hash function made no difference', digestResponse(...r7616('sha512-256')));
  const w4 = r7616('sha256'); w4[1] = true;
  control('-sess made no difference', digestResponse(...w4));
  // The parser: a quoted-pair, a bare token, a comma inside quotes.
  const parsed = parseParams('username="a\\"b", qop=auth, nc=00000001, uri="/x?a=1,b=2", algorithm=SHA-256');
  check('parse username', parsed.username, 'a"b');
  check('parse qop', parsed.qop, 'auth');
  check('parse uri', parsed.uri, '/x?a=1,b=2');
  check('parse algorithm', parsed.algorithm, 'SHA-256');
  check('escaped', escaped(Buffer.from([0x41, 0x5c, 0x22, 0x00, 0xc3, 0xbc, 0x7f])), 'A\\\\"\\x00\\xc3\\xbc\\x7f');
  if (fails.length > 0) {
    for (const f of fails) process.stdout.write(`selftest FAIL ${f}\n`);
    process.exit(1);
  }
  process.stdout.write(`selftest ok ${n}\n`);
  process.exit(0);
}

if (selftestPlant !== undefined) selftest(selftestPlant);

// The nonces this origin has issued, and the count that names a fresh one.
const nonces = new Set();
let noncesMade = 0;

// The auth logs, by key: the requests counted, and each one's line by its
// number, once answered.
const authLogs = new Map();

// authNumber: the next number for KEY's log, counting this request.
function authNumber(key) {
  let log = authLogs.get(key);
  if (!log) {
    log = { count: 0, lines: new Map() };
    authLogs.set(key, log);
  }
  log.count += 1;
  return log.count;
}

// authLogText: KEY's log, as /auth-log answers it.
function authLogText(key) {
  const log = authLogs.get(key) || { count: 0, lines: new Map() };
  let text = `log ${key} ${log.count}\n`;
  for (let i = 1; i <= Math.min(log.count, 64); i++) text += `${log.lines.get(i) || `request ${i} unanswered`}\n`;
  if (log.count > 64) text += `more ${log.count - 64}\n`;
  return text;
}

// account: the route R's user, password and token, as bytes.
function account(r) {
  return {
    user: r.u || latin1('user'),
    pass: r.p || latin1('pass'),
    tok: r.tok || latin1('tok123'),
  };
}

// digestChallenge: a fresh Digest challenge for R, its nonce the query's;
// a stale one's, the query's, - and the count of stale challenges R's key
// has had, from 1; with none named, n and a count of every challenge so
// far. Each is issued.
function digestChallenge(r, stale) {
  noncesMade += 1;
  let nonce = `n${noncesMade}`;
  if (r.nonce !== undefined) {
    const log = authLogs.get(r.key);
    if (stale) log.stales = (log.stales || 0) + 1;
    nonce = stale ? `${r.nonce}-${log.stales}` : r.nonce;
  }
  nonces.add(nonce);
  const parts = [`realm="${REALM}"`];
  if (r.qop !== 'none') parts.push('qop="auth"');
  parts.push(`nonce="${nonce}"`, `opaque="${OPAQUE}"`, `algorithm=${r.alg || 'MD5'}`);
  if (stale) parts.push('stale=true');
  return `Digest ${parts.join(', ')}`;
}

// challengeOf: the WWW-Authenticate value R's 401 carries, or null for
// none.
function challengeOf(r, stale) {
  switch (r.ch) {
    case 'basic': return `Basic realm="${REALM}"`;
    case 'bearer': return `Bearer realm="${REALM}"`;
    case 'digest': return digestChallenge(r, stale);
    default: return null;
  }
}

// digestIssues: what fails in the Digest credentials TEXT, after the
// scheme, for R's account, on a request of METHOD to TARGET with BODY.
function digestIssues(r, method, target, text, body) {
  const { user, pass } = account(r);
  const f = parseParams(text);
  const name = r.alg || 'MD5';
  const algorithm = algorithmOf(name);
  const issues = [];
  if (!nonces.has(f.nonce)) issues.push('nonce');
  if (f.realm !== REALM) issues.push('realm');
  if (f.uri !== target) issues.push('uri');
  if (f.opaque !== OPAQUE) issues.push('opaque');
  if ((f.algorithm || '').toLowerCase() !== name.toLowerCase()) issues.push('algorithm');
  if (!latin1(f.username ?? '').equals(user)) issues.push('username');
  if (r.qop !== 'none') {
    if (f.qop !== 'auth') issues.push('qop');
    if (!/^[0-9A-Fa-f]{8}$/.test(f.nc || '')) issues.push('nc');
    if (!f.cnonce) issues.push('cnonce');
  } else if (f.qop !== undefined) {
    issues.push('qop');
  }
  const expected = digestResponse(algorithm.base, algorithm.sess, user, REALM, pass, f.nonce || '',
                                  f.cnonce || '', f.nc || '', f.qop, method, f.uri || '', body);
  if ((f.response || '').toLowerCase() !== expected) issues.push('response');
  return issues;
}

// judged: the credentials VALUE, an Authorization header's, as a latin1
// string, judged by its own scheme for R: { scheme, verdict }.
function judged(r, method, target, value, body) {
  const at = value.indexOf(' ');
  const scheme = (at < 0 ? value : value.slice(0, at)).toLowerCase();
  const rest = at < 0 ? '' : value.slice(at + 1);
  const { user, pass, tok } = account(r);
  if (scheme === 'basic') {
    return { scheme, verdict: Buffer.from(rest.trim(), 'base64').equals(joined(user, ':', pass)) ? 'ok' : 'bad' };
  }
  if (scheme === 'bearer') return { scheme, verdict: latin1(rest).equals(tok) ? 'ok' : 'bad' };
  if (scheme === 'digest') {
    const issues = digestIssues(r, method, target, rest, body);
    return { scheme, verdict: issues.length === 0 ? 'ok' : `bad(${issues.join(',')})` };
  }
  return { scheme, verdict: 'other' };
}

// authorizations: every Authorization value among PAIRS, a flat list of
// names and values as received, in order.
function authorizations(pairs) {
  const values = [];
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    if (pairs[i].toLowerCase() === 'authorization') values.push(pairs[i + 1]);
  }
  return values;
}

// expectsContinue: whether PAIRS hold an Expect whose value holds
// 100-continue, A to Z folded.
function expectsContinue(pairs) {
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    if (pairs[i].toLowerCase() === 'expect' && pairs[i + 1].replace(/[A-Z]/g, (c) => c.toLowerCase()).includes('100-continue')) {
      return true;
    }
  }
  return false;
}

// authLine: request N's line, as the log keeps it.
function authLine(n, face, conn, method, body, verdict, status, values) {
  let bodyText = '-';
  if (body !== null) {
    let bad = -1;
    for (let i = 0; i < body.length; i++) {
      if (body[i] !== i % 251) {
        bad = i;
        break;
      }
    }
    bodyText = bad < 0 ? `${body.length}` : `${body.length}:bad@${bad}`;
  }
  const authorization = values.length === 0 ? '-'
    : `${escaped(latin1(values[0]))}${values.length > 1 ? ` (+${values.length - 1} more)` : ''}`;
  return `request ${n} face=${face} conn=${conn} method=${method} body=${bodyText} verdict=${verdict} status=${status} authorization=${authorization}`;
}

// authLogged: the line for request N of R's key, kept.
function authLogged(r, n, line) {
  authLogs.get(r.key).lines.set(n, line);
}

// authAnswer: what R answers request N on FACE, connection CONN, of METHOD
// to TARGET with the header PAIRS and BODY, read whole: { status,
// challenge, size }, size a 200's pattern bytes or null; the request
// logged.
function authAnswer(r, n, face, conn, method, target, pairs, body) {
  const values = authorizations(pairs);
  const verdict = values.length === 0 ? { scheme: null, verdict: 'none' } : judged(r, method, target, values[0], body);
  let answer;
  if (r.ch === 'open') {
    answer = { status: 200, challenge: null };
  } else if (r.ch === 'none') {
    answer = { status: 401, challenge: null };
  } else if (verdict.scheme === r.ch && verdict.verdict === 'ok') {
    answer = r.ch === 'digest' && r.stale === 'forever'
      ? { status: 401, challenge: challengeOf(r, true) }
      : { status: 200, challenge: null };
  } else {
    answer = { status: 401, challenge: challengeOf(r, false) };
  }
  authLogged(r, n, authLine(n, face, conn, method, body, verdict.verdict, answer.status, values));
  return { ...answer, size: answer.status === 200 && r.size !== undefined ? r.size : null };
}

// The raw faces' /raw/auth417 connections, counted on each face.
const auth417Connections = { raw: 0, 'raw-tls': 0 };

// --- the cookie route: its numbers, its lines and its log -----------------

// The cookie route's requests counted for each key, and each key's lines.
const cookieNumbers = new Map();
const cookieLogs = new Map();

// cookieNumber: one more request for KEY, numbered as its head arrives.
function cookieNumber(key) {
  const n = (cookieNumbers.get(key) || 0) + 1;
  cookieNumbers.set(key, n);
  return n;
}

// cookieLogged: LINE at the end of KEY's log.
function cookieLogged(key, line) {
  if (!cookieLogs.has(key)) cookieLogs.set(key, []);
  cookieLogs.get(key).push(line);
}

// cookieLogText: the answer of /cookie-log?key=KEY.
function cookieLogText(key) {
  const lines = cookieLogs.get(key) || [];
  return `cookie-log ${key} ${lines.length}\n${lines.map((line) => `${line}\n`).join('')}`;
}

// quoted: BYTES, quoted, as the auth log escapes them, a " as \x22.
const quoted = (bytes) => `"${escaped(bytes).replace(/"/g, '\\x22')}"`;

// cookieLine: request N's line on FACE, from its header PAIRS, a flat list
// of names and values as received: its first Host, and each Cookie header's
// value, in order.
function cookieLine(n, face, pairs) {
  const hosts = [];
  const cookies = [];
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    const name = pairs[i].toLowerCase();
    if (name === 'host') hosts.push(pairs[i + 1]);
    if (name === 'cookie') cookies.push(pairs[i + 1]);
  }
  return [`request ${n}`, `face=${face}`, `host=${hosts.length > 0 ? quoted(latin1(hosts[0])) : '-'}`,
          `cookies=${cookies.length}`, ...cookies.map((value) => `cookie=${quoted(latin1(value))}`)].join(' ');
}

// cookieRespond: the cookie route's answer for its request R, numbered N,
// on FACE: logged, then written.
function cookieRespond(res, r, n, face, pairs) {
  const line = cookieLine(n, face, pairs);
  cookieLogged(r.key, line);
  const headers = [];
  for (const bytes of r.set) headers.push('Set-Cookie', bytes.toString('latin1'));
  if (r.to !== null) headers.push('Location', r.to);
  return text(res, r.status, `${line}\n`, headers);
}

// CRLFCRLF: the blank line that ends a head.
const CRLFCRLF = Buffer.from('\r\n\r\n', 'latin1');

// OPEN_HEAD_LIMIT: the most bytes a connection's open head keeps.
const OPEN_HEAD_LIMIT = 64 * 1024;

// openHead: BYTES, which a connection on FACE held after its last blank
// line as it closed, logged as an open head when its first line is a
// /cookies request's, to that request's key.
function openHead(face, bytes) {
  const end = bytes.indexOf('\r\n', 0, 'latin1');
  if (end < 0) return;
  const m = /^[A-Z]+ ([^ ]+) HTTP\/1\.1$/.exec(bytes.subarray(0, end).toString('latin1'));
  const r = m ? route(m[1]) : { kind: 'not-found' };
  if (r.kind !== 'cookies') return;
  cookieLogged(r.key, `open-head face=${face} bytes=${bytes.length} headers=${quoted(bytes.subarray(end + 2))}`);
}

// headTracker: FACE's connection listener: each connection's bytes after
// its last blank line, kept to OPEN_HEAD_LIMIT, seen as they arrive, and
// handed to openHead as it closes. A 'data' listener of its own: Node then
// feeds its parser from the same events, so the requests go on as before.
function headTracker(face) {
  return (socket) => {
    let pending = Buffer.alloc(0);
    socket.on('data', (chunk) => {
      const at = chunk.lastIndexOf(CRLFCRLF);
      if (at >= 0) {
        pending = Buffer.from(chunk.subarray(at + 4, at + 4 + OPEN_HEAD_LIMIT));
        return;
      }
      const kept = Math.min(3, pending.length);
      const seam = Buffer.concat([pending.subarray(pending.length - kept), chunk.subarray(0, 3)]);
      const across = seam.lastIndexOf(CRLFCRLF);
      if (across >= 0) {
        const from = across + 4 - kept;
        pending = Buffer.from(chunk.subarray(from, from + OPEN_HEAD_LIMIT));
      } else if (pending.length < OPEN_HEAD_LIMIT) {
        pending = Buffer.concat([pending, chunk.subarray(0, OPEN_HEAD_LIMIT - pending.length)]);
      }
    });
    socket.on('close', () => {
      if (pending.length > 0) openHead(face, pending);
    });
  };
}

// --- the JSON route (the M8 plan, section 3.10) ---------------------------

// JSON_TYPE: the media type /json reads and writes.
const JSON_TYPE = 'application/json';

// asciiFolded: TEXT with A to Z as a to z, every other char as it is.
const asciiFolded = (text) => text.replace(/[A-Z]/g, (c) => c.toLowerCase());

// fieldValue: the values of every header of PAIRS, a flat list of names and
// values as received, named NAME, lower case, in any case, joined by ", ";
// or null for none.
function fieldValue(pairs, name) {
  const values = [];
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    if (asciiFolded(pairs[i]) === name) values.push(pairs[i + 1]);
  }
  return values.length === 0 ? null : values.join(', ');
}

// mediaType: TEXT's media type: its text before the first ;, spaces and
// tabs trimmed, A to Z folded.
const mediaType = (text) => asciiFolded(text.split(';')[0].replace(/^[ \t]+|[ \t]+$/g, ''));

// acceptsJson: whether ACCEPT, an Accept value or null, holds a range, split
// at each comma, whose media type is application/json.
const acceptsJson = (accept) => accept !== null && accept.split(',').some((range) => mediaType(range) === JSON_TYPE);

// jsonUtf8: a UTF-8 decoder that refuses any malformed sequence, and keeps a
// byte-order mark, which JSON.parse then refuses.
const jsonUtf8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

// jsonAnswer: /json's answer to METHOD on TARGET, with header PAIRS, a flat
// list of names and values as received, and BODY, its bytes: { status,
// bytes }, the bytes JSON.stringify's, as UTF-8.
function jsonAnswer(method, target, pairs, body) {
  const answer = (status, value) => ({ status, bytes: Buffer.from(JSON.stringify(value), 'utf8') });
  const accept = fieldValue(pairs, 'accept');
  if (!acceptsJson(accept)) return answer(406, { error: 'not-acceptable', accept });
  if (!['POST', 'PUT', 'PATCH'].includes(method)) return answer(200, { method, target, accept });
  const type = fieldValue(pairs, 'content-type');
  if (type === null || mediaType(type) !== JSON_TYPE) {
    return answer(415, { error: 'unsupported-media-type', 'content-type': type });
  }
  let text;
  try {
    text = jsonUtf8.decode(body);
  } catch {
    return answer(400, { error: 'not-utf-8', bytes: body.length });
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    return answer(400, { error: 'not-json', bytes: body.length });
  }
  return answer(201, { method, target, 'content-type': type, bytes: body.length, json });
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
    case 'auth-log':
      return text(res, 200, authLogText(r.key));
    case 'proxy-log':
      return text(res, 200, proxyLogText(r.from));
    case 'cookie-log':
      return text(res, 200, cookieLogText(r.key));
    case 'proxy-arm':
      connectArm = headLines({ n: r.n, line: r.line }, null, 0);
      return text(res, 200, 'armed\n');
    case 'echo': {
      let lines = `${req.method} ${req.url} HTTP/${req.httpVersion}\n`;
      for (let i = 0; i < req.rawHeaders.length; i += 2) {
        lines += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\n`;
      }
      lines += '\n';
      const bytes = Buffer.concat([Buffer.from(lines, 'latin1'), body]);
      return send(res, 200, ['Content-Length', String(bytes.length)], bytes);
    }
    case 'json': {
      const answer = jsonAnswer(req.method, req.url, req.rawHeaders, body);
      return send(res, answer.status, ['Content-Type', JSON_TYPE, 'Content-Length', String(answer.bytes.length)],
                  answer.bytes);
    }
    default:
      // /answer, /refuse, /answer-at, /mirror, /seq, /head and /head-auth
      // are HTTP/2's routes, and /close-after http's, which wellFormed
      // serves.
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

// connectionNumbers: each HTTP/1.1 face's connections, by socket, numbered
// from 1 among that face's as each is accepted, a TLS face's at its
// handshake: the auth route's conn.
const connectionNumbers = new WeakMap();

// numbered: SERVER's sockets numbered as EVENT hands each over.
function numbered(server, event) {
  let seen = 0;
  server.on(event, (socket) => {
    seen += 1;
    connectionNumbers.set(socket, seen);
  });
  return server;
}

// authRespond: the auth route's answer on an HTTP/1.1 face, as authAnswer
// decides it.
function authRespond(res, answer) {
  if (answer.size !== null) return pattern(res, answer.size, 0);
  if (answer.status === 200) return text(res, 200, 'auth ok\n');
  return text(res, 401, 'unauthorized\n', answer.challenge === null ? [] : ['WWW-Authenticate', answer.challenge]);
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
    proxyLogRequest(face, socket, req);
    const mark = marks.get(socket);
    marks.delete(socket);
    const r = route(req.url);
    if (r.kind === 'sink') countFor(r.key);
    const partsN = r.kind !== 'parts' ? null : req.partsCounted ? req.partsN : countFor(r.key);
    const authN = r.kind === 'auth' ? authNumber(r.key) : null;
    const cookieN = r.kind === 'cookies' ? cookieNumber(r.key) : null;
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
      if (r.kind === 'parts') {
        return text(res, partsStatus(r, partsN), partsReport(face, req.method, req.rawHeaders, Buffer.concat(chunks)),
                    partsPads(r.lines, 2));
      }
      if (r.kind === 'auth') {
        return authRespond(res, authAnswer(r, authN, face, connectionNumbers.get(socket), req.method, req.url,
                                           req.rawHeaders, Buffer.concat(chunks)));
      }
      if (closeAfter) return text(res, 200, 'ok\n');
      if (r.kind === 'cookies') return cookieRespond(res, r, cookieN, face, req.rawHeaders);
      return respond(req, res, Buffer.concat(chunks));
    });
  };
}

// partsContinue: FACE's checkContinue listener, for LISTENER, its request
// listener: as Node's own, a 100 then the request, but for a parts request
// with hold=1, counted as its head arrives and its 100 held until its key is
// released.
function partsContinue(listener) {
  return (req, res) => {
    const r = route(req.url);
    if (r.kind !== 'parts' || r.hold === undefined) {
      res.writeContinue();
      return listener(req, res);
    }
    req.partsN = countFor(r.key);
    req.partsCounted = true;
    releasedFor(r.key, req.socket)
      .then((how) => {
        if (how === 'released' && !req.socket.destroyed) {
          res.writeContinue();
          listener(req, res);
        }
      })
      .catch((err) => fatal('a held parts request failed', err));
    return undefined;
  };
}

const httpServer = numbered(http.createServer(wellFormed('http')), 'connection');
httpServer.on('checkContinue', partsContinue(wellFormed('http')));
httpServer.on('connection', track);
httpServer.on('connection', headTracker('http'));

// --- the proxy (the M7 plan, section 6.2) ---------------------------------

// The proxy's log, its lines in order; its connections, numbered as each
// becomes the proxy's, and those open now; and each tunnel's live socket
// to a face, by its local port, which the face sees as its peer's.
const proxyLog = [];
const proxyNumbers = new WeakMap();
let proxyConnections = 0;
const proxyOpen = new Set();
const tunnelPorts = new Map();

// The accounts a CONNECT to localhost must carry, as Basic's decoded bytes.
const PROXY_ACCOUNTS = ['alice:s3cret', 'bob:hunter2'];

const REASONS = { 403: 'Forbidden', 407: 'Proxy Authentication Required', 502: 'Bad Gateway', 503: 'Service Unavailable' };

// proxyConn: SOCKET's number among the proxy's connections, on FACE, given
// it as its first CONNECT or absolute-form request arrives; its close
// logged once.
function proxyConn(face, socket) {
  let n = proxyNumbers.get(socket);
  if (n === undefined) {
    proxyConnections += 1;
    n = proxyConnections;
    proxyNumbers.set(socket, n);
    proxyOpen.add(socket);
    socket.on('close', () => {
      proxyOpen.delete(socket);
      proxyLog.push(`close ${face} conn=${n}`);
    });
  }
  return n;
}

// proxyAuthorizations: every Proxy-Authorization value among PAIRS, a
// flat list of names and values as received, in order.
function proxyAuthorizations(pairs) {
  const values = [];
  for (let i = 0; i + 1 < pairs.length; i += 2) {
    if (pairs[i].toLowerCase() === 'proxy-authorization') values.push(pairs[i + 1]);
  }
  return values;
}

// basicBytes: VALUE's credentials, base64-decoded, when it is Basic, the
// scheme in any case, then one space; else null.
function basicBytes(value) {
  const m = /^basic (.*)$/i.exec(value);
  return m ? Buffer.from(m[1], 'base64') : null;
}

// proxyAuthText: the first Proxy-Authorization among PAIRS as the log
// shows it.
function proxyAuthText(pairs) {
  const values = proxyAuthorizations(pairs);
  if (values.length === 0) return '-';
  const basic = basicBytes(values[0]);
  const shown = basic === null ? `other:${escaped(latin1(values[0]))}` : `basic:${escaped(basic)}`;
  return `${shown}${values.length > 1 ? ` (+${values.length - 1} more)` : ''}`;
}

// accountPasses: whether PAIRS' first Proxy-Authorization is Basic for one
// of the accounts, byte for byte.
function accountPasses(pairs) {
  const values = proxyAuthorizations(pairs);
  const basic = values.length === 0 ? null : basicBytes(values[0]);
  return basic !== null && PROXY_ACCOUNTS.some((account) => basic.equals(latin1(account)));
}

// headBytes: the bytes of REQ's head as libcurl writes one: the request
// line, each header "NAME: VALUE", CRLF each, then CRLF.
function headBytes(req) {
  let head = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
  for (let i = 0; i + 1 < req.rawHeaders.length; i += 2) head += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
  return latin1(`${head}\r\n`).length;
}

// proxyLogRequest: REQ, on FACE's SOCKET, logged when its target is in
// absolute form, as the proxy's, or when it came through a tunnel, as an
// inner one.
function proxyLogRequest(face, socket, req) {
  if (req.url.startsWith('http://')) {
    const conn = proxyConn(face, socket);
    proxyLog.push(`request ${face} conn=${conn} method=${req.method} target=${escaped(latin1(req.url))} auth=${proxyAuthText(req.rawHeaders)}`);
  } else {
    proxyLogInner(face, socket, req.method, req.url);
  }
}

// proxyLogInner: a request of METHOD to TARGET on FACE's SOCKET, logged
// when SOCKET's peer is a tunnel's live socket.
function proxyLogInner(face, socket, method, target) {
  const tunnel = socket ? tunnelPorts.get(socket.remotePort) : undefined;
  if (tunnel && !tunnel.far.destroyed) {
    proxyLog.push(`inner ${face} via=${tunnel.conn} method=${method} target=${escaped(latin1(String(target)))}`);
  }
}

// proxyLogText: the answer of /proxy-log?from=FROM.
function proxyLogText(from) {
  return `proxy-log ${proxyLog.length} open ${proxyOpen.size}\n${proxyLog.slice(from).map((line) => `${line}\n`).join('')}`;
}

// proxyRefuse: STATUS written to CLIENT, the connection kept; a byte the
// client sends after it, or its end, ends the connection: a node:http
// face's socket is half-open, and would stay so after the client's FIN.
function proxyRefuse(client, status) {
  const body = `proxy ${status}\n`;
  const challenge = status === 407 ? 'Proxy-Authenticate: Basic realm="chez-curl-proxy"\r\n' : '';
  client.on('data', () => client.destroy());
  client.on('end', () => client.destroy());
  client.write(`HTTP/1.1 ${status} ${REASONS[status]}\r\n${challenge}Content-Length: ${body.length}\r\n\r\n${body}`);
}

// proxyConnect: FACE's CONNECT listener, by its target, as the header has
// it. A tunnel is counted, logged and entered by its far socket's local
// port once that socket connects, the 200 written then, so no request can
// come through it before; its entry goes as that socket closes.
function proxyConnect(face) {
  return (req, client, early) => {
    track(client);
    client.on('error', () => client.destroy());
    const conn = proxyConn(face, client);
    const head = headBytes(req);
    const auth = proxyAuthText(req.rawHeaders);
    const logged = (answer) => {
      proxyLog.push(`connect ${face} conn=${conn} target=${escaped(latin1(req.url))} answer=${answer} head=${head} auth=${auth}`);
    };
    const target = /^([^:]+):([1-9][0-9]*)$/.exec(req.url);
    const host = target ? target[1] : null;
    const port = target ? Number(target[2]) : null;
    const refusal = host === null ? null : /^refuse-(403|407|502|503)\.invalid$/.exec(host);
    if (refusal) {
      logged(refusal[1]);
      proxyRefuse(client, Number(refusal[1]));
      return;
    }
    if (host === 'close.invalid') {
      logged('close');
      client.destroy();
      return;
    }
    const ports = new Set(faces.map(([, server]) => server.address() && server.address().port));
    if ((host === '127.0.0.1' || host === 'localhost') && ports.has(port)) {
      if (host === 'localhost' && !accountPasses(req.rawHeaders)) {
        logged('407');
        proxyRefuse(client, 407);
        return;
      }
      const far = net.connect(port, HOST, () => {
        const localPort = far.localPort;
        tunnelPorts.set(localPort, { conn, far });
        far.on('close', () => {
          const entry = tunnelPorts.get(localPort);
          if (entry && entry.far === far) tunnelPorts.delete(localPort);
        });
        connects += 1;
        logged('200');
        const armed = connectArm || [];
        connectArm = null;
        client.write(ascii(`HTTP/1.1 200 Connection Established\r\n${armed.map(([k, v]) => `${k}: ${v}\r\n`).join('')}\r\n`));
        if (early && early.length > 0) far.write(early);
        far.pipe(client);
        client.pipe(far);
      });
      track(far);
      far.on('error', () => { far.destroy(); client.destroy(); });
      client.on('close', () => far.destroy());
      far.on('close', () => client.destroy());
      return;
    }
    logged('403');
    client.end('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
  };
}

httpServer.on('connect', proxyConnect('http'));

// httpsServer: the https face NAME serving LEAF, with ALPN http/1.1 alone.
// A TLS error ends that connection only.
function httpsServer(name, leafOf) {
  const server = numbered(https.createServer({ ...leafOf.options, ALPNProtocols: ['http/1.1'] }, wellFormed(name)),
                          'secureConnection');
  server.on('connection', track);
  server.on('secureConnection', track);
  server.on('tlsClientError', (err, socket) => socket.destroy());
  server.on('connect', proxyConnect(name));
  server.on('checkContinue', partsContinue(wellFormed(name)));
  return server;
}

// --- the head routes (M8 slice 2; ADR-0040) ------------------------------
//
// A head's spec, read from a query's pairs, each name once at most, and no
// other; the same on the raw face and the HTTP/2 faces, as the M8 caps
// probe's stand-in reads it, so its measured sizes carry over:
//   n=N      the head's header lines, its framing line among them, 1 to
//            100000; 1 when left out
//   line=L   each generated line's bytes as libcurl hands it, CR LF in, 13 to
//            65536; 16 when left out. Names x-000001 on, each value v
//            repeated, so every line is L bytes; same=1 makes every one
//            x-same: vvv..., one pair
//   total=T  in place of n: lines of L bytes until the head, its status line
//            (slen=S bytes, 1 to 64, as libcurl hands it: 17, HTTP/1.1 200
//            OK, on raw, 13, HTTP/2 200, on HTTP/2, when left out) and its
//            empty line in, holds T bytes, 0 to 4194304; the last line takes
//            what is left, and a remainder too short for a line goes to the
//            line before
//   big=B    one more line, x-big: a..., of B bytes, 9 to 1048576; bigch=C,
//            its value C repeated in place of a, C a letter or a digit
//   pre=C:N:L,...  up to 16 1xx heads before the final one, each status C,
//            100 or 103, with N lines, 0 to 100000, of L bytes, 13 to 65536
//   tn=N     N trailers, 0 to 100000, of tl=L bytes, 13 to 65536, 16 when
//            left out: on HTTP/1.1 a chunked body of no data, on HTTP/2 a
//            trailers HEADERS frame
// and, on the raw face alone, since nghttp2 refuses a / in a name:
//   hname=1  every generated line named HTTP/1.1 x-000001 on, in place of
//            x-000001, as a status line begins, its line 22 bytes or more:
//            libcurl takes it as a header, its name holding the space
//   tname=1  the first trailer named HTTP/x, with tn
//   v10=1    every head's status line HTTP/1.0, in place of HTTP/1.1
// The framing line is content-length: 0, or, with trailers on HTTP/1.1,
// transfer-encoding: chunked; on HTTP/2 there is none with trailers.
// Prefixed a. and b., the specs of a flow's first and second response
// (/raw/head-auth, /raw/head417 and HTTP/2's /head-auth).
const HEAD_REASONS = { 100: 'Continue', 103: 'Early Hints', 200: 'OK', 401: 'Unauthorized', 417: 'Expectation Failed' };
const HEAD_DIGEST = 'Digest realm="chez-curl-test", qop="auth", nonce="n0", algorithm=MD5';

// headSpecOf: the spec of PAIRS, [name, value] as given, or null.
function headSpecOf(pairs) {
  const spec = {};
  const ranged = (v, low, high) => decimal(v, low, high);
  for (const [name, value] of pairs) {
    if (Object.hasOwn(spec, name)) return null;
    let read;
    switch (name) {
      case 'n': read = ranged(value, 1, 100000); break;
      case 'line': case 'tl': read = ranged(value, 13, 65536); break;
      case 'total': read = ranged(value, 0, 4194304); break;
      case 'slen': read = ranged(value, 1, 64); break;
      case 'same': read = value === '1' ? true : null; break;
      case 'big': read = ranged(value, 9, 1048576); break;
      case 'bigch': read = /^[A-Za-z0-9]$/.test(value) ? value : null; break;
      case 'tn': read = ranged(value, 0, 100000); break;
      case 'hname': case 'tname': case 'v10': read = value === '1' ? true : null; break;
      case 'pre': {
        const heads = value.split(',').map((h) => {
          const m = /^(100|103):(0|[1-9][0-9]*):(0|[1-9][0-9]*)$/.exec(h);
          if (!m) return null;
          const n = decimal(m[2], 0, 100000);
          const l = decimal(m[3], 13, 65536);
          return n === null || l === null ? null : { status: Number(m[1]), n, line: l };
        });
        read = heads.length <= 16 && heads.every((h) => h !== null) ? heads : null;
        break;
      }
      default: read = null;
    }
    if (read === null) return null;
    spec[name] = read;
  }
  if ((Object.hasOwn(spec, 'n') && Object.hasOwn(spec, 'total')) || (Object.hasOwn(spec, 'bigch') && !Object.hasOwn(spec, 'big'))
      || (Object.hasOwn(spec, 'tl') && !Object.hasOwn(spec, 'tn')) || (spec.tname && !Object.hasOwn(spec, 'tn'))
      || (spec.hname && (spec.line === undefined || spec.line < 22))) {
    return null;
  }
  return spec;
}

// rawOnly: whether SPEC names what the raw face alone writes.
const rawOnly = (spec) => Boolean(spec.hname || spec.tname || spec.v10);

// queryPairs: QUERY's pairs, [name, value], or null for a pair with no =.
function queryPairs(query) {
  if (query === undefined || query === '') return [];
  const pairs = [];
  for (const pair of query.split('&')) {
    const at = pair.indexOf('=');
    if (at < 0) return null;
    pairs.push([pair.slice(0, at), pair.slice(at + 1)]);
  }
  return pairs;
}

// headQuery: the one spec QUERY holds, or null.
function headQuery(query) {
  const pairs = queryPairs(query);
  return pairs === null ? null : headSpecOf(pairs);
}

// flowQuery: the two specs, a. and b., QUERY holds, or null: every pair
// prefixed a. or b.
function flowQuery(query) {
  const pairs = queryPairs(query);
  if (pairs === null) return null;
  const a = [];
  const b = [];
  for (const [name, value] of pairs) {
    if (name.startsWith('a.')) a.push([name.slice(2), value]);
    else if (name.startsWith('b.')) b.push([name.slice(2), value]);
    else return null;
  }
  const specs = { a: headSpecOf(a), b: headSpecOf(b) };
  return specs.a === null || specs.b === null ? null : specs;
}

// headLine: a generated line, [name, value], of LENGTH bytes as
// "name: value\r\n" counts them.
const headLine = (name, length, ch) => [name, ch.repeat(Math.max(0, length - name.length - 4))];
const headLineBytes = (l) => l[0].length + 2 + l[1].length + 2;

// headLines: SPEC's generated lines, after FIXED, the framing line, or
// null; with SLEN, the status line's bytes as libcurl hands it, for total.
function headLines(spec, fixed, slen) {
  const L = spec.line === undefined ? 16 : spec.line;
  const name = (i) => (spec.same ? 'x-same' : `${spec.hname ? 'HTTP/1.1 ' : ''}x-${String(i).padStart(6, '0')}`);
  const out = [];
  if (spec.total !== undefined) {
    let left = spec.total - (spec.slen === undefined ? slen : spec.slen) - 2 - (fixed ? headLineBytes(fixed) : 0)
      - (spec.big === undefined ? 0 : spec.big);
    let i = 1;
    while (left >= L) { out.push(headLine(name(i), L, 'v')); i += 1; left -= L; }
    if (left > 0) {
      if (left >= name(i).length + 5) out.push(headLine(name(i), left, 'v'));
      else if (out.length > 0) out[out.length - 1][1] += 'v'.repeat(left);
    }
  } else {
    const n = (spec.n === undefined ? 1 : spec.n) - (fixed ? 1 : 0);
    for (let i = 1; i <= n; i++) out.push(headLine(name(i), L, 'v'));
  }
  if (spec.big !== undefined) out.push(headLine('x-big', spec.big, spec.bigch || 'a'));
  return out;
}

// preHeads: SPEC's 1xx heads, each { status, lines }.
const preHeads = (spec) => (spec.pre || []).map((h) => ({ status: h.status, lines: headLines({ n: h.n, line: h.line }, null, 0) }));

// trailerLines: SPEC's trailers, or null for none; with tname, the first
// named HTTP/x, its bytes kept.
function trailerLines(spec) {
  if (spec.tn === undefined) return null;
  const lines = headLines({ n: spec.tn, line: spec.tl }, null, 0);
  if (spec.tname && lines.length > 0) lines[0] = headLine('HTTP/x', spec.tl === undefined ? 16 : spec.tl, 'v');
  return lines;
}

// h1Head: an HTTP/1.1 head, its status line, LINES and its empty line;
// with V10, an HTTP/1.0 one.
function h1Head(status, lines, v10) {
  let s = `HTTP/1.${v10 ? 0 : 1} ${status} ${HEAD_REASONS[status]}\r\n`;
  for (const [k, v] of lines) s += `${k}: ${v}\r\n`;
  return `${s}\r\n`;
}

// h1Response: the whole HTTP/1.1 response SPEC makes, STATUS's, EXTRA lines
// first: its 1xx heads, its head, and, with trailers, a chunked body of no
// data and the trailers.
function h1Response(status, spec, extra) {
  const trailers = trailerLines(spec);
  const fixed = trailers ? ['transfer-encoding', 'chunked'] : ['content-length', '0'];
  let out = '';
  for (const h of preHeads(spec)) out += h1Head(h.status, h.lines, spec.v10);
  out += h1Head(status, [...extra, fixed, ...headLines(spec, fixed, 17)], spec.v10);
  if (trailers) {
    out += '0\r\n';
    for (const [k, v] of trailers) out += `${k}: ${v}\r\n`;
    out += '\r\n';
  }
  return ascii(out);
}

// h2Object: Node's header object for STATUS, or none, and LINES, a name
// given twice an array of its values.
function h2Object(status, lines) {
  const o = status === undefined ? {} : { ':status': status };
  for (const [k, v] of lines) {
    if (o[k] === undefined) o[k] = v;
    else if (Array.isArray(o[k])) o[k].push(v);
    else o[k] = [o[k], v];
  }
  return o;
}

// h2Head: the HTTP/2 response SPEC makes on STREAM, STATUS's, EXTRA lines
// first: its 1xx heads, its HEADERS, and its trailers, or none.
function h2Head(stream, status, spec, extra) {
  if (stream.destroyed) return;
  for (const h of preHeads(spec)) stream.additionalHeaders(h2Object(h.status, h.lines));
  const trailers = trailerLines(spec);
  const fixed = trailers ? null : ['content-length', '0'];
  const lines = [...extra, ...(fixed ? [fixed] : []), ...headLines(spec, fixed, 13)];
  if (trailers) {
    stream.respond(h2Object(status, lines), { waitForTrailers: true, sendDate: false });
    // A trailer block Node cannot send throws: it ends this stream only.
    stream.on('wantTrailers', () => {
      try { stream.sendTrailers(h2Object(undefined, trailers)); } catch { stream.destroy(); }
    });
    stream.end();
  } else {
    stream.respond(h2Object(status, lines), { endStream: true, sendDate: false });
  }
}

// head417Keys: the keys /raw/head417 has answered 417, for as long as the
// origin lives.
const head417Keys = new Set();

// connectArm: what /proxy-arm set for the proxy's next CONNECT it answers
// 200, the lines its answer carries, or null.
let connectArm = null;

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
    case 'auth-log':
      return h2Text(stream, 200, authLogText(r.key));
    case 'head':
      return h2Head(stream, 200, r.spec, []);
    case 'head-auth':
      return headers.authorization === undefined
        ? h2Head(stream, 401, r.a, [['www-authenticate', HEAD_DIGEST]])
        : h2Head(stream, 200, r.b, []);
    case 'echo': {
      let lines = '';
      for (let i = 0; i < rawHeaders.length; i += 2) lines += `${rawHeaders[i]}: ${rawHeaders[i + 1]}\n`;
      lines += '\n';
      const bytes = Buffer.concat([Buffer.from(lines, 'latin1'), body]);
      return h2Send(stream, 200, ['content-length', String(bytes.length)], bytes);
    }
    case 'json': {
      const answer = jsonAnswer(headers[':method'], headers[':path'], rawHeaders, body);
      return h2Send(stream, answer.status,
                    ['content-type', JSON_TYPE, 'content-length', String(answer.bytes.length)], answer.bytes);
    }
    default:
      // /chunked, /close-after and /proxy-arm are HTTP/1.1 routes.
      return h2Text(stream, 404, 'not found\n');
  }
}

// h2Stream: FACE's stream listener. /answer answers as the headers arrive,
// or with hold=KEY once /raw/release names KEY, then reads the body; /answer-at once N DATA bytes have come; /mirror
// writes each DATA chunk back as it comes; /sink, /refuse and /seq count
// as they arrive, and read the body, or refuse the stream; every other
// route reads the body whole, then answers.
function h2Stream(face) {
  return (stream, headers, flags, rawHeaders) => {
    const headAt = performance.now();
    // A stream error ends this stream only.
    stream.on('error', () => stream.destroy());
    proxyLogInner(face, stream.session && stream.session.socket, headers[':method'], headers[':path']);
    const r = route(headers[':path']);
    if (r.kind === 'answer') {
      // Read while the answer goes, so that Node, which closes a stream it
      // has answered when nothing reads it, keeps the stream open.
      stream.on('data', () => {});
      if (r.hold === undefined) return h2Text(stream, r.status, `answer ${r.status}\n`);
      // Held: the answer once its key is released, or none once the stream
      // has closed first.
      releasedFor(r.hold, stream)
        .then((how) => {
          if (how === 'released' && !stream.destroyed) h2Text(stream, r.status, `answer ${r.status}\n`);
        })
        .catch((err) => fatal('a held answer failed', err));
      return undefined;
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
    if (r.kind === 'auth') {
      const n = authNumber(r.key);
      const conn = stream.session.connectionNumber;
      const chunks = [];
      stream.on('data', (chunk) => chunks.push(chunk));
      stream.on('end', () => {
        const answer = authAnswer(r, n, face, conn, headers[':method'], headers[':path'], rawHeaders,
                                  Buffer.concat(chunks));
        if (answer.size !== null) return h2Pattern(stream, answer.size, 0);
        if (answer.status === 200) return h2Text(stream, 200, 'auth ok\n');
        return h2Text(stream, 401, 'unauthorized\n',
                      answer.challenge === null ? [] : ['www-authenticate', answer.challenge]);
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
    if (r.kind === 'parts') {
      const partsN = countFor(r.key);
      const chunks = [];
      stream.on('data', (chunk) => chunks.push(chunk));
      stream.on('end', () => {
        const report = Buffer.from(partsReport(face, headers[':method'], rawHeaders, Buffer.concat(chunks)), 'latin1');
        h2Send(stream, partsStatus(r, partsN), ['content-length', String(report.length), ...partsPads(r.lines, 1)],
               report);
      });
      if (partsContinues(rawHeaders)) {
        if (r.hold === undefined) stream.additionalHeaders({ ':status': 100 });
        else {
          releasedFor(r.key, stream)
            .then((how) => {
              if (how === 'released' && !stream.destroyed) stream.additionalHeaders({ ':status': 100 });
            })
            .catch((err) => fatal('a held parts stream failed', err));
        }
      }
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

// h2EndNext: SOCKET, an HTTP/2 session's, ended at the next immediate, as its
// client's end comes. Node's native immediates run first, in that check
// phase, and drain whatever they queue: a TLS write that finished at once
// completes there (TLSWrap simulates the asynchronous finish), and so does
// the session's write of what waited for it, an RST_STREAM among them. Node's
// own end, at once, came first: a refusal whose request came in one read with
// the client's close_notify lost its RST_STREAM, the SETTINGS ACK written
// before it still in progress (M7's carried races, research/m7/carried/races).
// A write the kernel holds, to a client that has stopped reading, can still
// be in progress then; and so can any write chained on drains, which a
// client's half-close can still cut: a stream body over 16 KiB, written one
// write at a time, and /mirror's closing empty DATA, which goes once the
// last write has gone (test-origin-tls's comments on the stream routes and
// on /mirror).
function h2EndNext(socket) {
  setImmediate(() => {
    if (!socket.destroyed && !socket.writableEnded) socket.end();
  });
}

// h2Face: SERVER, the face NAME, with the listeners every HTTP/2 face
// shares. Each session is numbered, from 1, among its face's, for
// /connection. SERVER is half-open: a client's end ends the connection at
// the next immediate (h2EndNext). The listener's this is the session's
// socket itself: session.socket is a proxy, which refuses end.
function h2Face(server, name) {
  let sessionsSeen = 0;
  server.on('connection', track);
  server.on('session', (session) => {
    sessionsSeen += 1;
    session.connectionNumber = sessionsSeen;
    trackSession(session);
    session.socket.on('end', function clientEnded() { h2EndNext(this); });
  });
  server.on('sessionError', (err, session) => session.destroy());
  server.on('stream', h2Stream(name));
  return server;
}

// Both HTTP/2 faces raise Node's send limit, maxSendHeaderBlockLength, from
// 64 KiB to 64 MiB, so a head or a trailer block past 64 KiB is sent whole:
// at the default, a head past it is never sent, and a trailer block past it
// is dropped, the stream ended cleanly on Node 24.18.0 and reset on 20.10.0
// (M8 slice 2; traps.md). Node's two receive limits stay their defaults: the
// SETTINGS frame each face sends first stays empty, as tests hold it.
const H2_SEND_LIMIT = 64 << 20;
const h2cServer = h2Face(http2.createServer({ allowHalfOpen: true, maxSendHeaderBlockLength: H2_SEND_LIMIT }), 'h2c');

function h2Server(name, leafOf) {
  const server = h2Face(http2.createSecureServer({ ...leafOf.options, allowHTTP1: false, allowHalfOpen: true,
                                                 maxSendHeaderBlockLength: H2_SEND_LIMIT }), name);
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
    play: ({ code, ms, to, key }) => {
      if (key !== null) countFor(key);
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
  // The auth route's 417 loop, kept alive (the auth route, above): its
  // connection's requests one after another, each logged to KEY's log.
  'auth417': {
    query: (query) => queryOf(query, { key: keyValue }, ['key']),
    play: ({ key }, head, conn) => {
      conn.input = inputOf();
      auth417Connections[conn.face] += 1;
      return [{ step: 'auth417', conn, head, key, number: auth417Connections[conn.face] }, END];
    },
  },
  // The head routes (M8 slice 2): a head of a chosen size and shape; a
  // Digest round's two responses; a 417 and its resend's.
  'head': {
    query: headQuery,
    play: (spec) => [write(h1Response(200, spec, [])), END],
  },
  'head-auth': {
    query: flowQuery,
    play: ({ a, b }, head) => [
      write(authorizations(headPairs(head)).length === 0
        ? h1Response(401, a, [['www-authenticate', HEAD_DIGEST]])
        : h1Response(200, b, [])),
      END,
    ],
  },
  'head417': {
    query: (query) => {
      const pairs = queryPairs(query);
      if (pairs === null) return null;
      const keys = pairs.filter(([name]) => name === 'key');
      if (keys.length !== 1 || !retryKey(keys[0][1])) return null;
      const rest = pairs.filter(([name]) => name !== 'key').map(([name, value]) => `${name}=${value}`).join('&');
      const specs = flowQuery(rest === '' ? undefined : rest);
      return specs === null ? null : { key: keys[0][1], ...specs };
    },
    play: ({ key, a, b }, head, conn) => {
      conn.input = inputOf();
      return [{ step: 'head417', conn, head, key, a, b }, END];
    },
  },
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
// a key released already; or 'gone' once SOCKET, a socket or an HTTP/2
// stream, closes first.
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
// exactly once, 200 to 599; ms at most once, 0 to 60000, 0 when absent; key
// at most once, as retry takes it, null when absent; to any number of times,
// in order, each value's bytes. Every pair is NAME=VALUE, the value after the
// first =.
function locationQuery(query) {
  if (query === undefined) return null;
  const found = { code: null, ms: null, key: null, to: [] };
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
    } else if (name === 'key') {
      if (found.key !== null || keyValue(value) === null) return null;
      found.key = value;
    } else if (name === 'to') {
      const bytes = percentDecoded(value);
      if (bytes === null) return null;
      found.to.push(bytes);
    } else {
      return null;
    }
  }
  if (found.code === null) return null;
  return { code: found.code, ms: found.ms === null ? 0 : found.ms, key: found.key, to: found.to };
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
        case 'auth417': {
          // Each request on the connection, from the first: one whose
          // Expect holds 100-continue gets a 417 as its head arrives, kept
          // alive, and the next bytes decide, a letter A to Z beginning the
          // next request, any other byte the refused request's body, read
          // by its Content-Length and dropped; any other request has its
          // body read by its Content-Length, none without one, and gets a
          // 200, kept alive. Each is logged to KEY's log, judged as the auth
          // route judges, by the default account. The client's end, or a
          // head past HEAD_LIMIT, ends it.
          const judging = { key: s.key, ch: 'basic' };
          let buffer = Buffer.alloc(0);
          const more = async () => {
            const item = await nextItem(s.conn.input);
            if (item === null) return false;
            buffer = Buffer.concat([buffer, item[0]]);
            return true;
          };
          const send = (bytes) => new Promise((resolve) => socket.write(bytes, () => resolve()));
          let head = s.head;
          for (;;) {
            const text = head.toString('latin1');
            const [method, target] = text.slice(0, text.indexOf('\r\n')).split(' ');
            const pairs = headPairs(head);
            const n = authNumber(s.key);
            const values = authorizations(pairs).map((v) => v.replace(/^[ \t]+|[ \t]+$/g, ''));
            const verdict = values.length === 0 ? 'none' : judged(judging, method, target, values[0], Buffer.alloc(0)).verdict;
            const framing = framingOf(pairs);
            const length = framing !== null && framing.kind === 'length' ? framing.length : 0;
            if (expectsContinue(pairs)) {
              authLogged(judging, n, authLine(n, s.conn.face, s.number, method, null, verdict, 417, values));
              await send(ascii('HTTP/1.1 417 Expectation Failed\r\nContent-Length: 19\r\n\r\nexpectation failed\n'));
              while (buffer.length === 0) if (!(await more())) return;
              if (!(buffer[0] >= 0x41 && buffer[0] <= 0x5a)) {
                while (buffer.length < length) if (!(await more())) return;
                buffer = buffer.subarray(length);
              }
            } else {
              while (buffer.length < length) if (!(await more())) return;
              const body = Buffer.from(buffer.subarray(0, length));
              buffer = buffer.subarray(length);
              authLogged(judging, n, authLine(n, s.conn.face, s.number, method, body, verdict, 200, values));
              await send(ascii('HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nauth ok\n'));
            }
            let end;
            while ((end = buffer.indexOf('\r\n\r\n')) < 0) {
              if (buffer.length >= HEAD_LIMIT || !(await more())) return;
            }
            head = Buffer.from(buffer.subarray(0, end + 4));
            buffer = buffer.subarray(end + 4);
            if (socket.destroyed || !socket.writable) return;
          }
        }
        case 'head417': {
          // KEY's first request whose Expect holds 100-continue gets a 417
          // by spec a. as its head arrives, kept alive, and the next bytes
          // decide, as auth417's do: a letter A to Z the next request, any
          // other byte the refused request's body, read by its
          // Content-Length and dropped. Every later request for KEY, on this
          // connection or another, gets a 100 Continue when its Expect holds
          // 100-continue, has its body read by its Content-Length, and gets a
          // 200 by spec b.; so does a first request without that Expect.
          // Then the script ends. The key, not the connection, holds the
          // 417: libcurl may resend on a new connection (M8 slice 2's build:
          // under Valgrind, 8.20.0 did).
          let buffer = Buffer.alloc(0);
          const more = async () => {
            const item = await nextItem(s.conn.input);
            if (item === null) return false;
            buffer = Buffer.concat([buffer, item[0]]);
            return true;
          };
          const send = (bytes) => new Promise((resolve) => socket.write(bytes, () => resolve()));
          let head = s.head;
          for (;;) {
            const pairs = headPairs(head);
            const framing = framingOf(pairs);
            const length = framing !== null && framing.kind === 'length' ? framing.length : 0;
            if (!head417Keys.has(s.key) && expectsContinue(pairs)) {
              head417Keys.add(s.key);
              await send(h1Response(417, s.a, []));
              while (buffer.length === 0) if (!(await more())) return;
              if (!(buffer[0] >= 0x41 && buffer[0] <= 0x5a)) {
                while (buffer.length < length) if (!(await more())) return;
                buffer = buffer.subarray(length);
              }
              let end;
              while ((end = buffer.indexOf('\r\n\r\n')) < 0) {
                if (buffer.length >= HEAD_LIMIT || !(await more())) return;
              }
              head = Buffer.from(buffer.subarray(0, end + 4));
              buffer = buffer.subarray(end + 4);
              if (socket.destroyed || !socket.writable) return;
              continue;
            }
            if (expectsContinue(pairs)) await send(ascii('HTTP/1.1 100 Continue\r\n\r\n'));
            while (buffer.length < length) if (!(await more())) return;
            await send(h1Response(200, s.b, []));
            break;
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
