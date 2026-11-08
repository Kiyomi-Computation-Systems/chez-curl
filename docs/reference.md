# API reference

Every name `(curl)`, `(curl unsupported)` and `(http-client)` export, one
entry each. `(http-client)` is the high level, for most programs. `(curl)` is
the low level beneath it. `(curl unsupported)` is the escape hatch. The
[index](README.md) lists the guide pages that explain each part.

Types are written as Typed Racket writes them: `[x]` is an optional
argument, `(U a b)` is either one, `a -> b` is a procedure, `Any ...` is any
number more, and `'name` is that symbol. These names stand for:

```text
Natural           an exact integer, 0 or more
Positive-Integer  an exact integer, 1 or more
Headers           (Listof (Pairof String String)), each name and value Latin-1
Libcurl-Info      what loaded-libcurl reports
Request           a low-level request, made by make-curl-request
Engine            a thread that runs transfers, made by make-curl-engine
Token             one transfer, curl-submit's answer
Mailbox           a box of finished tokens, made by make-curl-mailbox
Head              a streamed response's final head, curl-token-head's answer
Jar               a cookie jar, made by make-curl-cookie-jar
Multipart         (multipart PART ...), a multipart/form-data body
Part              (NAME SOURCE OPTION ...), one part of a multipart body
Session           a high-level session, made by make-http-session
Retry             a retry policy, made by make-http-retry
Go                the procedure call-with-request-group hands its PROC
Pending           a call a group started, go's answer
Producer          (-> (U Bytevector Eof)), a body made as it is sent
Response          (curl)'s response in (curl)'s entries, (http-client)'s in its own
Condition         a condition, as raise raises it
Void              no useful value
```

Two things hold for every entry, and no entry says them again:

- **Loading.** Every name but the condition types, their predicates and
  accessors, the reason lists and the `libcurl-info` accessors loads libcurl
  the first time a program refers to it, before the program's first line
  runs. A libcurl that is refused raises `&curl-library-unavailable` there,
  and again at every later reference, so a `guard` in the program cannot
  catch it. See [TLS and the environment](tls-and-environment.md).
- **Importing.** Each library refuses, as a syntax violation, a Chez that is
  not threaded or is older than the floor in
  [Requirements](../README.org).

And a procedure that waits, for a transfer, a token, a mailbox or the
engine, refuses to run inside a critical section, as an assertion
violation: there its wait would hold up every thread's collections.

## `(curl)`: the libcurl loaded

### `loaded-libcurl`

```text
loaded-libcurl : -> Libcurl-Info
```

The libcurl this process loaded and accepted, as a report the
`libcurl-info` accessors read. Raises nothing once the program runs: a
refused libcurl raises before it, as above. See
[TLS and the environment](tls-and-environment.md).

### `libcurl-info?`, `libcurl-info-path`, `libcurl-info-source`, `libcurl-info-version`, `libcurl-info-version-number`, `libcurl-info-features`, `libcurl-info-feature-names`, `libcurl-info-ssl-version`, `libcurl-info-host`

```text
libcurl-info? : Any -> Boolean
libcurl-info-path : Libcurl-Info -> String
libcurl-info-source : Libcurl-Info -> Symbol
libcurl-info-version : Libcurl-Info -> String
libcurl-info-version-number : Libcurl-Info -> Natural
libcurl-info-features : Libcurl-Info -> Natural
libcurl-info-feature-names : Libcurl-Info -> (Listof (U Symbol Positive-Integer))
libcurl-info-ssl-version : Libcurl-Info -> (U String #f)
libcurl-info-host : Libcurl-Info -> (U String #f)
```

What the report says: the file loaded, and where it was found (`override`,
`guix-environment`, `guix-profile`, `guix-home`, `guix-user-profile`,
`guix-system`, `system` or `macos-system`); then libcurl's version, its
version number, its feature bits as a number and as names, a bit with no
name as its number, its TLS library and its host. libcurl answers these
before it starts, so on Apple's libcurl, which has two TLS backends, the TLS
library named is its first, and the features show none of a backend's bits.
They load nothing, so a refusal's report can be read. Raises an assertion
violation for anything but a report; `libcurl-info?` raises nothing. See
[TLS and the environment](tls-and-environment.md).

## `(curl)`: requests

### `make-curl-request`

```text
make-curl-request : String Any ... -> Request
```

`(make-curl-request URL KEY VALUE ...)` makes a request for an `http://` or
`https://` URL, and sends nothing: `curl-submit` runs it. Each key may be
given once, and one left out takes its default, libcurl's own:

| Key | Type | Default |
|:--|:--|:--|
| `method` | `(U 'get 'head 'post 'put 'patch 'delete)` | `get` |
| `headers` | `Headers` | `()` |
| `body` | `(U Bytevector 'stream Multipart #f)` | `#f` |
| `user-agent` | `(U String #f)`, a non-empty Latin-1 string | `#f` |
| `timeout-ms` | `(U Positive-Integer #f)`, the whole transfer's bound | `#f` |
| `connect-timeout-ms` | `(U Positive-Integer #f)`, the connection's bound, its TLS handshake among it | `#f` |
| `body-limit` | `(U Natural #f)`, the most bytes of response body | `#f` |
| `ca-file` | `(U String #f)`, the only CA file to trust; `#f` is the system's store | `#f` |
| `verify` | `Boolean`, whether to check the server's certificate | `#t` |
| `proxy` | `(U 'environment #f String)`: the proxy the variables name, none, or this proxy URL | `environment` |
| `stream-buffer` | `(U Positive-Integer #f)`: stream the response's body through the token, buffering this many bytes | `#f` |
| `body-length` | `(U Natural #f)`, a streamed body's `Content-Length` | `#f` |
| `http-version` | `(U 'http/1.1 'http/2 'http/2-prior-knowledge #f)` | `#f` |
| `credentials` | `(U (List 'basic String String) (List 'digest String String) (List 'bearer String) #f)` | `#f` |
| `proxy-ca-file` | `(U String #f)`, an `https://` proxy's only CA file | `#f` |
| `proxy-verify` | `Boolean`, whether to check an `https://` proxy's certificate | `#t` |
| `cookie-jar` | `(U Jar #f)`, the jar whose cookies it sends and keeps | `#f` |

A body of `stream` is given by the token's puts. A multipart body is
`(multipart PART ...)`, each `PART` `(NAME SOURCE OPTION ...)`: `SOURCE` a
string, sent as UTF-8, a bytevector, or `(file PATH)`, and each `OPTION`
`filename STRING` or `type STRING`. A `post`, `put` or `patch` with no body
sends an empty one. The URL is checked to be a string here, and parsed at
submit.

Raises an assertion violation for a value of the wrong type or shape, and
`&curl-request-error` for these reasons, the keys' first:

- `unknown-key`, `repeated-key`, `missing-value`: a key it does not take, one
  given twice, or one given last with no value;
- `body-not-allowed`: a body with `get` or `head`;
- `body-length-without-stream`: a `body-length` beside a body that does not
  stream;
- `stream-with-rounds`: a `stream-buffer` beside an `Expect` header that
  holds `100-continue`;
- `not-a-token`, `embedded-nul`, `line-break`, `not-latin-1`,
  `surrounding-whitespace`, `duplicates-field`, `framing-header`,
  `proxy-authorization-header`: a header, or the user agent, it refuses;
- `credentials-bytes`, `credentials-empty`,
  `credentials-beside-authorization`, `digest-with-stream`: credentials it
  refuses;
- `cookie-beside-jar`: a `Cookie` or `Host` header beside a jar;
- `multipart-content-type`, `multipart-empty`, `part-bytes`, `part-empty`,
  `part-file`: a multipart body it refuses, a file part's path that names no
  regular file among them;
- `embedded-nul`, `pkcs11-url`: a CA file, or a proxy CA file, it refuses.

See [The low level](low-level.md), and [Errors](errors.md) for
each reason.

### `curl-request-with`

```text
curl-request-with : Request Any ... -> Request
```

A new request: this one, with the keys given replaced and the rest kept. A
multipart body it is not given is kept as it is, its files not looked at
again until submit. Its keys:

| Key | Type | Default |
|:--|:--|:--|
| `url` | `String`, the new URL | this request's |
| `method`, `headers`, `body`, `user-agent`, `timeout-ms`, `connect-timeout-ms`, `body-limit`, `ca-file`, `verify`, `proxy`, `stream-buffer`, `body-length`, `http-version`, `credentials`, `proxy-ca-file`, `proxy-verify`, `cookie-jar` | as `make-curl-request`'s | this request's |

Raises an assertion violation for anything but a request, and what
`make-curl-request` raises, naming `curl-request-with`. See
[The low level](low-level.md).

### `curl-request?`, `curl-request-url`, `curl-request-method`, `curl-request-headers`, `curl-request-body`, `curl-request-user-agent`

```text
curl-request? : Any -> Boolean
curl-request-url : Request -> String
curl-request-method : Request -> (U 'get 'head 'post 'put 'patch 'delete)
curl-request-headers : Request -> Headers
curl-request-body : Request -> (U Bytevector 'stream Multipart #f)
curl-request-user-agent : Request -> (U String #f)
```

What the request holds for each key. A multipart body comes back as a copy,
its paths resolved. Raises an assertion violation for anything but a
request; `curl-request?` raises nothing. See [The low level](low-level.md).

### `curl-request-timeout-ms`, `curl-request-connect-timeout-ms`, `curl-request-body-limit`, `curl-request-stream-buffer`, `curl-request-body-length`, `curl-request-http-version`

```text
curl-request-timeout-ms : Request -> (U Positive-Integer #f)
curl-request-connect-timeout-ms : Request -> (U Positive-Integer #f)
curl-request-body-limit : Request -> (U Natural #f)
curl-request-stream-buffer : Request -> (U Positive-Integer #f)
curl-request-body-length : Request -> (U Natural #f)
curl-request-http-version : Request -> (U 'http/1.1 'http/2 'http/2-prior-knowledge #f)
```

What the request holds for each key. Raises an assertion violation for
anything but a request. See [The low level](low-level.md) and
[Choosing the HTTP version](http-version.md).

### `curl-request-ca-file`, `curl-request-verify`, `curl-request-proxy`, `curl-request-proxy-ca-file`, `curl-request-proxy-verify`, `curl-request-credentials`, `curl-request-cookie-jar`

```text
curl-request-ca-file : Request -> (U String #f)
curl-request-verify : Request -> Boolean
curl-request-proxy : Request -> (U 'environment #f String)
curl-request-proxy-ca-file : Request -> (U String #f)
curl-request-proxy-verify : Request -> Boolean
curl-request-credentials : Request -> (U (List 'basic String String) (List 'digest String String) (List 'bearer String) #f)
curl-request-cookie-jar : Request -> (U Jar #f)
```

What the request holds for each key. A proxy URL, the proxy CA file and the
credentials come back as fresh copies, so changing one changes no request.
Raises an assertion violation for anything but a request. See
[Auth and proxies](auth-and-proxies.md) and
[TLS and the environment](tls-and-environment.md).

## `(curl)`: URLs

### `curl-url-part`

```text
curl-url-part : String Symbol -> (U String Natural #f)
```

`(curl-url-part URL PART)` is one part of the URL, as libcurl parses it:
`url`, the whole URL; `scheme`, `user`, `password`, `host`, `path`, `query`,
`fragment` or `zoneid`, a string, or `#f` when the URL has none; or `port`,
a number, the scheme's own when the URL names none. Raises an assertion
violation for a URL that is no string, or a part it does not know; and
`&curl-url-error` for a URL libcurl refuses, its reason libcurl's code's
name, for one holding U+0000, `embedded-nul`, for one of more than
8,000,000 characters, `malformed-input`, and for an answer whose bytes are
not UTF-8, `not-utf-8`. See [The low level](low-level.md).

### `curl-url-append-query`

```text
curl-url-append-query : String String -> String
```

`(curl-url-append-query URL PART)` is the URL with `PART`, already encoded,
added to its query, after a `&` unless the query is empty or ends in one.
The fragment is kept. Raises an assertion violation for a URL or a part
that is no string; and `&curl-url-error` as `curl-url-part` raises it, and
for a part that would not come back as written, one holding `#`,
`query-not-kept`. See [The low level](low-level.md).

### `curl-url-resolve`

```text
curl-url-resolve : String (U String Bytevector) -> String
```

`(curl-url-resolve BASE REFERENCE)` is the reference resolved against the
base URL, as a browser follows a link. A string is sent as UTF-8. A
bytevector, such as a `Location` header's bytes, has each byte at or below
0x20, 0x7F, and each above encoded as `%XX` first. Raises an assertion
violation for a base that is no string, or a reference of another kind; and
`&curl-url-error` as `curl-url-part` raises it, a bytevector holding 0x00
among it, `embedded-nul`. See [The low level](low-level.md).

### `curl-url-with-fragment`

```text
curl-url-with-fragment : String (U String Bytevector #f) -> String
```

`(curl-url-with-fragment URL FRAGMENT)` is the URL with its fragment
replaced, or cleared by `#f` or `""`. A bytevector is encoded as
`curl-url-resolve` encodes one; a string goes in as written. Raises an
assertion violation for a URL that is no string, or a fragment that is no
string, bytevector or `#f`; and `&curl-url-error` as `curl-url-part` raises
it, a bytevector holding 0x00 among it, `embedded-nul`. See
[The low level](low-level.md).

## `(curl)`: engines

### `make-curl-engine`, `curl-engine?`

```text
make-curl-engine : -> Engine
curl-engine? : Any -> Boolean
```

A fresh engine: a thread of its own that runs every transfer submitted to
it, many at once. Stop it with `curl-engine-stop`. Raises an assertion
violation inside a critical section, and `&curl-engine-error`, `failed`,
when its thread can make no libcurl multi handle; `curl-engine?` raises
nothing.
See [The low level](low-level.md).

### `curl-engine-stop`

```text
curl-engine-stop : Engine -> Void
```

Ends every transfer the engine holds as stopped, frees all it holds, and
returns once its thread has ended. A second stop returns at once. Raises an
assertion violation for anything but an engine, or inside a critical
section. See [The low level](low-level.md).

### `curl-submit`

```text
curl-submit : Engine Request [(U Mailbox #f) [(U (Token -> Any) #f)]] -> Token
```

Queues the request on the engine, and answers its token at once. With a
mailbox, the token goes there when it is done; with a callback too, a
delivery from the mailbox calls it with the token. The request is copied,
and the copy checked on this thread. Raises an assertion violation for
anything but an engine, a request, a mailbox or a procedure where each
goes, and for a callback without a mailbox; what `make-curl-request` raises,
its checks run again on the copy; `&curl-url-error` for the URL, as
`curl-url-part` raises it, and for a scheme but `http` or `https`,
`scheme-not-http`; `&curl-engine-error`, `stopped`, for a stopped engine,
and a failed engine's own failure; and `&curl-request-error` for these
reasons:

- `environment-override`, `keychain-fallback`: a CA file the environment, or
  Apple's TLS library, would replace or add to;
- `proxy-url`, `proxy-scheme`, `proxy-url-parts`, `credentials-bytes`,
  `credentials-empty`: a proxy URL it refuses, naming the field, never the
  URL;
- `https-proxy-unsupported`, `proxy-tls-without-https-proxy`,
  `proxy-tls-in-tls`, `prior-knowledge-through-proxy`: a proxy setting this
  libcurl, or this proxy, cannot carry;
- `prior-knowledge-over-https`: `http/2-prior-knowledge` with an `https://`
  URL;
- `credentials-beside-userinfo`: credentials beside a URL that holds a user
  or a password;
- `multipart-unsupported`, `part-file`: a multipart body this libcurl cannot
  send, or a file part that is no regular file now;
- `cookie-jar-engine`, `cookie-jar-closed`: another engine's jar, or a
  closed one.

See [The low level](low-level.md).

### `curl-request-check`

```text
curl-request-check : Request -> Void
```

Runs the checks `curl-submit` makes of a request, on this thread, and queues
nothing, so a batch can be checked before any of it is sent. A submit still
checks its own copy, and an engine's state can still refuse it. Raises an
assertion violation for anything but a request, and what `curl-submit`
raises for the request and its URL, naming `curl-request-check`, never an
engine's or a jar's refusal. See [The low level](low-level.md).

## `(curl)`: tokens and responses

### `curl-token?`, `curl-token-await`

```text
curl-token? : Any -> Boolean
curl-token-await : Token -> Response
```

Waits for the transfer to end, and answers its response, whatever the
status: a 404 is a response too. Any thread may await a token, any number
of times. Raises an assertion violation for anything but a token; and what
the transfer ended with: `&curl-transfer-error`, or one of its classes, for
a transfer that failed, was cancelled or was stopped; `&curl-engine-error`,
`failed`, when its engine failed; and `&curl-request-error`,
`cookie-jar-closed` or `cookie-jar-engine`, for a jar closed after the
submit. `curl-token?` raises nothing. See [The low level](low-level.md).

### `curl-token-wait`

```text
curl-token-wait : Token Natural -> Boolean
```

Whether the transfer ends within that many milliseconds. It runs on either
way. Raises an assertion violation for anything but a token, or a wait that
is no natural number. See [The low level](low-level.md).

### `curl-token-cancel`

```text
curl-token-cancel : Token -> Void
```

Ends the transfer as cancelled, and returns at once. One that has already
ended keeps what it ended with. Raises an assertion violation for anything
but a token. See [The low level](low-level.md).

### `curl-token-done?`, `curl-token-outcome`

```text
curl-token-done? : Token -> Boolean
curl-token-outcome : Token -> (U Response Condition #f)
```

Whether the transfer has ended; and once it has, the response, or the
condition `curl-token-await` would raise, as a value, `#f` before. Neither
waits. Raises an assertion violation for anything but a token. See
[The low level](low-level.md).

### `curl-response?`, `curl-response-status`, `curl-response-http-version`, `curl-response-effective-url`, `curl-response-headers`, `curl-response-body`, `curl-response-timings`

```text
curl-response? : Any -> Boolean
curl-response-status : Response -> Integer
curl-response-http-version : Response -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
curl-response-effective-url : Response -> (U String #f)
curl-response-headers : Response -> Headers
curl-response-body : Response -> (U Bytevector #f)
curl-response-timings : Response -> (Listof (Pairof Symbol Natural))
```

What a transfer answered: its status, its HTTP version, its URL, its
headers in libcurl's order, and its body, `#f` for one that streamed. The
timings are `name-lookup`, `connect`, `tls-handshake`, `first-byte` and
`total`, each in microseconds from the start, 0 for a phase it skipped.
Raises an assertion violation for anything but a response;
`curl-response?` raises nothing. See [The low level](low-level.md).

## `(curl)`: mailboxes

### `make-curl-mailbox`, `curl-mailbox?`

```text
make-curl-mailbox : -> Mailbox
curl-mailbox? : Any -> Boolean
```

An empty mailbox, which collects finished tokens from any number of
engines, oldest first. Raises nothing. See [The low level](low-level.md).

### `curl-mailbox-take`

```text
curl-mailbox-take : Mailbox Natural -> (U Token #f)
```

The next finished token, taken out, waiting up to that many milliseconds;
or `#f`. It calls no callback. Raises an assertion violation for anything
but a mailbox, or a wait that is no natural number. See
[The low level](low-level.md).

### `curl-mailbox-deliver`

```text
curl-mailbox-deliver : Mailbox Natural -> (U Token #f)
```

Takes a token as `curl-mailbox-take` does, then calls its callback, if it
has one, with the token, on this thread. Raises what `curl-mailbox-take`
raises, and whatever the callback raises. See [The low level](low-level.md).

## `(curl)`: streamed responses

### `curl-token-head-wait`

```text
curl-token-head-wait : Token Natural -> Boolean
```

Whether the final head has arrived, or the transfer has ended, within that
many milliseconds. Raises an assertion violation for anything but a token
whose request streams its response, or a wait that is no natural number.
See [Streams](streams.md).

### `curl-token-head`, `curl-head?`, `curl-head-status`, `curl-head-http-version`, `curl-head-headers`, `curl-head-body-asked?`

```text
curl-token-head : Token -> (U Head #f)
curl-head? : Any -> Boolean
curl-head-status : Head -> Integer
curl-head-http-version : Head -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
curl-head-headers : Head -> Headers
curl-head-body-asked? : Head -> Boolean
```

The final head, once it has arrived, without waiting; a 1xx head and a
proxy's are passed over. Its status, version and headers read as a
response's do. `curl-head-body-asked?` says whether libcurl had asked for a
streamed request body by then. Raises an assertion violation for anything
but a token whose request streams its response, or a head;
`curl-head?` raises nothing. See [Streams](streams.md).

### `curl-token-next-piece`

```text
curl-token-next-piece : Token Natural -> (U Bytevector Eof #f)
```

The next piece of the body, the caller's to keep; the end of file once
every piece is taken and the transfer has ended, however it ended; or `#f`
once that many milliseconds pass. Raises an assertion violation for
anything but a token whose request streams its response, or a wait that is
no natural number. See [Streams](streams.md).

### `curl-token-body-port`

```text
curl-token-body-port : Token -> Binary-Input-Port
```

A binary input port over the body as it arrives, made once per token. Read
it and close it on the thread that made it; its close cancels the
transfer. At the end it answers the end of file for a response, and raises
the failure for one that failed, every time. Raises an assertion violation
for anything but a token whose request streams its response, or a second
port; its reads raise the transfer's failure, and `&curl-wrong-thread` for
a read that needs more, or a close, from another thread. See
[Streams](streams.md).

## `(curl)`: streamed request bodies

### `curl-token-room-wait`

```text
curl-token-room-wait : Token Natural -> (U #t #f 'done)
```

`#t` once libcurl has asked for the body and the buffer has room; `done`
once the transfer has ended; `#f` once that many milliseconds pass. Raises
an assertion violation for anything but a token whose request streams its
body, or a wait that is no natural number. See [Streams](streams.md).

### `curl-token-put-piece!`

```text
curl-token-put-piece! : Token Bytevector [Natural] -> (U #t #f 'done)
```

Copies the piece, a byte or more, into the body's buffer, waiting while it
is full, at most that many milliseconds when given: `#t` once taken, `#f`
once they pass, `done` once the transfer has ended. Raises an assertion
violation for anything but a token whose request streams its body, a piece
that is no bytevector of a byte or more, a wait that is no natural number,
or a put after the body's end; and `&curl-request-error`,
`body-length-mismatch`, for a piece past the `body-length`, which fails the
transfer too. See [Streams](streams.md).

### `curl-token-end-body!`

```text
curl-token-end-body! : Token -> Void
```

Ends the body; a second end, or one after the transfer has ended, does
nothing. An end short of the `body-length` fails the transfer,
`body-length-mismatch`. Raises an assertion violation for anything but a
token whose request streams its body. See [Streams](streams.md).

### `curl-token-body-count`

```text
curl-token-body-count : Token -> Natural
```

The bytes the puts have handed over so far. Raises an assertion violation
for anything but a token whose request streams its body. See
[Streams](streams.md).

## `(curl)`: cookie jars

### `make-curl-cookie-jar`, `curl-cookie-jar?`

```text
make-curl-cookie-jar : Engine -> Jar
curl-cookie-jar? : Any -> Boolean
```

A fresh, empty jar on the engine, for a request's `cookie-jar` key. Each
jar procedure waits for the engine to do its work, with no bound. Raises an
assertion violation for anything but an engine; `&curl-engine-error`,
`stopped`, or the engine's own failure, for an engine stopping, stopped or
failed; and Chez's `&error`, no chez-curl condition, when libcurl refuses to
make the jar. `curl-cookie-jar?` raises nothing. See [Cookies](cookies.md).

### `curl-cookie-jar-cookies`

```text
curl-cookie-jar-cookies : Jar -> (Listof String)
```

The jar's cookies, as Netscape lines: `DOMAIN TAILMATCH PATH SECURE EXPIRY
NAME VALUE`, tab-separated, one char per byte, in libcurl's order, which
moves, so compare them sorted. What some libcurls list varies by version.
Raises an assertion violation for anything but a jar;
`&curl-engine-error` as `make-curl-cookie-jar` raises it;
`&curl-request-error`, `cookie-jar-closed`, for a closed jar; and Chez's
`&error` when libcurl refuses the read. See [Cookies](cookies.md) and
[What varies by libcurl](libcurl-versions.md).

### `curl-cookie-jar-load!`

```text
curl-cookie-jar-load! : Jar (Listof String) -> Void
```

Loads the lines, in order, once every one is checked: each must be in the
form a read-out writes. Raises an assertion violation for anything but a
jar, or lines that are no list of strings; `&curl-request-error`,
`cookie-line`, for a line not in that form, naming its index from 0, never
its text, with nothing loaded; `&curl-engine-error` as
`make-curl-cookie-jar` raises it; `&curl-request-error`,
`cookie-jar-closed`, for a closed jar; and Chez's `&error` when libcurl
refuses a line, the lines before it loaded. See [Cookies](cookies.md).

### `curl-cookie-jar-close!`

```text
curl-cookie-jar-close! : Jar -> Void
```

Closes the jar: freed at once, or once the last transfer that holds it
ends. A later submit with it, or a read or a load, is refused; a second
close does nothing. Raises an assertion violation for anything but a jar,
and `&curl-engine-error` as `make-curl-cookie-jar` raises it. See
[Cookies](cookies.md).

## `(curl)`: conditions

Each condition type below is a `&curl-error`, which is an `&error`. Its
accessors raise an assertion violation for anything of another kind,
naming it by its kind, never its value.

### `&curl-error`, `curl-error?`

```text
curl-error? : Any -> Boolean
```

The base of every chez-curl condition type but `&http-exchange`, the high
level's among them. Raises nothing. See [Errors](errors.md).

### `&curl-library-unavailable`, `curl-library-unavailable?`, `curl-library-unavailable-reason`, `curl-library-unavailable-path`, `curl-library-unavailable-source`, `curl-library-unavailable-detail`, `curl-library-unavailable-candidates`, `curl-library-unavailable-library`, `curl-library-unavailable-reasons`

```text
curl-library-unavailable? : Any -> Boolean
curl-library-unavailable-reason : &curl-library-unavailable -> Symbol
curl-library-unavailable-path : &curl-library-unavailable -> (U String #f)
curl-library-unavailable-source : &curl-library-unavailable -> (U Symbol #f)
curl-library-unavailable-detail : &curl-library-unavailable -> Any
curl-library-unavailable-candidates : &curl-library-unavailable -> (Listof String)
curl-library-unavailable-library : &curl-library-unavailable -> (U Libcurl-Info #f)
curl-library-unavailable-reasons : (Listof Symbol)
```

libcurl was refused: why, the file, where it was found, a detail by reason,
every path tried, and the library's report when it was read. The reasons:
`invalid-override`, `not-found`, `load-failed`, `below-floor`, `no-ssl`,
`missing-api`. Raises an assertion violation, from an accessor, for
anything of another kind. See [Errors](errors.md) and
[TLS and the environment](tls-and-environment.md).

### `&curl-wrong-thread`, `curl-wrong-thread?`, `curl-wrong-thread-who`, `curl-wrong-thread-expected`, `curl-wrong-thread-actual`

```text
curl-wrong-thread? : Any -> Boolean
curl-wrong-thread-who : &curl-wrong-thread -> Symbol
curl-wrong-thread-expected : &curl-wrong-thread -> Integer
curl-wrong-thread-actual : &curl-wrong-thread -> Integer
```

Something used on another thread than its own; a caller meets it from a
token's body port, read or closed on another thread than the one that made
it. It carries what refused, and the two threads' ids. Raises an
assertion violation,
from an accessor, for anything of another kind. See
[Errors](errors.md).

### `&curl-embedded-nul`, `curl-embedded-nul?`, `curl-embedded-nul-string`

```text
curl-embedded-nul? : Any -> Boolean
curl-embedded-nul-string : &curl-embedded-nul -> String
```

A string C would read short, since it holds U+0000. The request's and the
URL's own checks refuse such a string first, as `&curl-request-error` or
`&curl-url-error`, `embedded-nul`. Raises an assertion violation, from an
accessor, for anything of another kind. See [Errors](errors.md).

### `&curl-url-error`, `curl-url-error?`, `curl-url-error-input`, `curl-url-error-reason`, `curl-url-error-code`, `curl-url-error-message`

```text
curl-url-error? : Any -> Boolean
curl-url-error-input : &curl-url-error -> String
curl-url-error-reason : &curl-url-error -> (U Symbol #f)
curl-url-error-code : &curl-url-error -> (U Integer #f)
curl-url-error-message : &curl-url-error -> (U String #f)
```

A URL refused: the text refused, why, and libcurl's code and message when
the refusal was libcurl's. The reason is libcurl's code's name, `#f` for a
code newer than the floor's, or chez-curl's own: `scheme-not-http`,
`embedded-nul`, `not-utf-8` or `query-not-kept`. Raises an assertion
violation, from an accessor, for anything of another kind. See
[Errors](errors.md).

### `&curl-request-error`, `curl-request-error?`, `curl-request-error-field`, `curl-request-error-value`, `curl-request-error-reason`, `curl-request-error-reasons`

```text
curl-request-error? : Any -> Boolean
curl-request-error-field : &curl-request-error -> Symbol
curl-request-error-value : &curl-request-error -> Any
curl-request-error-reason : &curl-request-error -> Symbol
curl-request-error-reasons : (Listof Symbol)
```

A request's key or field refused: which one, its value, and why. A value
that could hold a secret is named by its field alone. The reasons:
`embedded-nul`, `line-break`, `not-latin-1`, `not-a-token`,
`surrounding-whitespace`, `duplicates-field`, `framing-header`,
`owned-option`, `unsupported-type`, `unknown-option`, `repeated-option`,
`unknown-key`, `repeated-key`, `missing-value`, `body-not-allowed`,
`pkcs11-url`, `environment-override`, `keychain-fallback`,
`stream-with-rounds`, `body-length-without-stream`, `body-length-mismatch`,
`prior-knowledge-over-https`, `credentials-bytes`, `credentials-empty`,
`credentials-beside-userinfo`, `credentials-beside-authorization`,
`digest-with-stream`, `prior-knowledge-through-proxy`, `proxy-url`,
`proxy-scheme`, `proxy-url-parts`, `proxy-authorization-header`,
`proxy-tls-without-https-proxy`, `proxy-tls-in-tls`,
`https-proxy-unsupported`, `cookie-line`, `cookie-jar-engine`,
`cookie-jar-closed`, `cookie-beside-jar`, `part-bytes`, `part-empty`,
`multipart-empty`, `multipart-content-type`, `part-file`,
`multipart-unsupported`. Raises an assertion violation, from an accessor,
for anything of another kind. See [Errors](errors.md).

### `&curl-transfer-error`, `curl-transfer-error?`, `curl-transfer-error-reason`, `curl-transfer-error-code`, `curl-transfer-error-option`, `curl-transfer-error-strerror`, `curl-transfer-error-error-buffer`, `curl-transfer-error-recorded`, `curl-transfer-error-request-size`, `curl-transfer-error-connect-code`, `curl-transfer-error-reasons`

```text
curl-transfer-error? : Any -> Boolean
curl-transfer-error-reason : &curl-transfer-error -> Symbol
curl-transfer-error-code : &curl-transfer-error -> (U Integer #f)
curl-transfer-error-option : &curl-transfer-error -> (U String #f)
curl-transfer-error-strerror : &curl-transfer-error -> (U String #f)
curl-transfer-error-error-buffer : &curl-transfer-error -> (U String #f)
curl-transfer-error-recorded : &curl-transfer-error -> Any
curl-transfer-error-request-size : &curl-transfer-error -> (U Natural #f)
curl-transfer-error-connect-code : &curl-transfer-error -> (U Positive-Integer #f)
curl-transfer-error-reasons : (Listof Symbol)
```

A transfer that failed: why; libcurl's code, the option it refused, and
its two texts about it; what a callback raised; the bytes of request sent,
0 when none was, `#f` when that is unknown, as for a transfer cancelled or
stopped, and on libcurl 8.7.0 and 8.7.1; and the status a proxy refused a
tunnel with. The reasons: `perform-failed`, `body-limit`,
`callback-raised`, `setopt-failed`, `unknown-option`, `no-handle`,
`cancelled`, `stopped`, `pause-failed`, `body-length-mismatch`,
`body-not-replayable`, `header-limit`, `part-file`, `mime-failed`. Raises
an assertion violation, from an accessor, for anything of another kind.
See [Errors](errors.md).

### `&curl-timeout`, `curl-timeout?`

```text
curl-timeout? : Any -> Boolean
```

A `&curl-transfer-error`, `perform-failed`, for libcurl's code 28: a bound
passed. Raises nothing. See [Errors](errors.md).

### `&curl-connect-error`, `curl-connect-error?`

```text
curl-connect-error? : Any -> Boolean
```

A `&curl-transfer-error`, `perform-failed`, for libcurl's codes 5, 6, 7,
45, 96 and 97: no connection was made. Raises nothing. See
[Errors](errors.md).

### `&curl-send-receive-error`, `curl-send-receive-error?`

```text
curl-send-receive-error? : Any -> Boolean
```

A `&curl-transfer-error`, `perform-failed`, for libcurl's codes 18, 52, 55
and 56: the connection failed while sending or receiving. Raises nothing.
See [Errors](errors.md).

### `&curl-tls-error`, `curl-tls-error?`

```text
curl-tls-error? : Any -> Boolean
```

A `&curl-transfer-error`, `perform-failed`, for libcurl's codes 35, 53,
54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91, 98 and 101: TLS failed.
Raises nothing. See [Errors](errors.md).

### `&curl-protocol-error`, `curl-protocol-error?`

```text
curl-protocol-error? : Any -> Boolean
```

A `&curl-transfer-error`, `perform-failed`, for libcurl's codes 1, 8, 16,
61, 92 and 95: the server's answer broke HTTP's rules. Raises nothing. See
[Errors](errors.md).

### `&curl-too-large`, `curl-too-large?`

```text
curl-too-large? : Any -> Boolean
```

A `&curl-transfer-error` for too much: libcurl's codes 63 and 100,
`perform-failed`; a body past the `body-limit`, `body-limit`; and response
headers past the cap, `header-limit`. A `body-limit` below a declared
`Content-Length` is libcurl's 63, before any of the body arrives. Raises
nothing. See [Errors](errors.md).

### `&curl-engine-error`, `curl-engine-error?`, `curl-engine-error-reason`, `curl-engine-error-condition`, `curl-engine-error-reasons`

```text
curl-engine-error? : Any -> Boolean
curl-engine-error-reason : &curl-engine-error -> Symbol
curl-engine-error-condition : &curl-engine-error -> Any
curl-engine-error-reasons : (Listof Symbol)
```

An engine that stopped, or failed, and for `failed` what raised inside it.
The reasons: `stopped`, `failed`. Raises an assertion violation, from an
accessor, for anything of another kind. See [Errors](errors.md).

## `(curl unsupported)`: the hatch

### `curl-request-with-options`

```text
curl-request-with-options : Request (Listof (Pairof String Any)) -> Request
```

`(curl-request-with-options REQUEST ((NAME . VALUE) ...))` is a new request
that also sets libcurl options chez-curl does not wrap, by name, without
`CURLOPT_`, in any case. The engine sets them last. A value is an exact
integer, a string, a list of strings, or a bytevector, by the option's
type. Nothing here is promised to stay. Raises an assertion violation for
anything but a request, options that are no list of pairs, or a value of
the wrong shape or range; and `&curl-request-error`, field `options`, for a
name or a string it refuses: `unknown-option`, `owned-option`,
`unsupported-type`, `repeated-option`, `embedded-nul` or `line-break`. A
value libcurl refuses fails the transfer, `setopt-failed`. See
[The hatch](hatch.md).

## `(http-client)`: sessions

### `make-http-session`

```text
make-http-session : Any ... -> Session
```

`(make-http-session KEY VALUE ...)` is a session: one engine, and the
defaults its calls share. Each key may be given once:

| Key | Type | Default |
|:--|:--|:--|
| `headers`, `user-agent`, `timeout-ms`, `connect-timeout-ms`, `body-limit`, `ca-file`, `verify`, `proxy`, `http-version`, `credentials`, `proxy-ca-file`, `proxy-verify` | as `make-curl-request`'s | `make-curl-request`'s |
| `redirects` | `(U Natural #f)`, the most redirects a call follows; `#f` follows none | `20` |
| `allow-downgrade` | `Boolean`, whether a redirect from `https` to `http` is followed | `#f` |
| `retry` | `(U Retry #f)`, the policy a call retries by | `#f` |
| `cookies` | `Boolean`, whether the session keeps cookies, in a jar of its own | `#f` |

Close it with `http-session-close`, or use `call-with-http-session`. Raises
`&http-request-error` for `unknown-key`, `repeated-key` and
`missing-value`, then `not-a-redirect-count`, `not-a-boolean` and
`not-a-retry-policy`; then what `make-curl-request` raises for its keys;
then what `make-curl-engine` raises; and with `cookies`, what
`make-curl-cookie-jar` raises, and `&curl-request-error`,
`cookie-beside-jar`, for a `Cookie` or `Host` header. A refusal leaves no
engine running. See [The high level](high-level.md).

### `http-session?`

```text
http-session? : Any -> Boolean
```

Whether it is a session. Raises nothing. See [The high level](high-level.md).

### `http-session-close`

```text
http-session-close : Session -> Void
```

Stops the session's engine: each call in flight ends as stopped, and a
later call raises `&curl-engine-error`, `stopped`. A second close returns.
Raises an assertion violation for anything but a session. See
[The high level](high-level.md).

### `call-with-http-session`

```text
call-with-http-session : Any ... (Session -> Any) -> Any
```

`(call-with-http-session KEY VALUE ... PROC)` makes a session from the
keys, calls `PROC` with it, and closes it when `PROC` returns or escapes.
Raises an assertion violation for a last argument that is no procedure;
what `make-http-session` raises; and whatever `PROC` raises, once the
session is closed. See [The high level](high-level.md).

## `(http-client)`: cookies

### `http-session-cookies`

```text
http-session-cookies : Session -> (Listof String)
```

The session's cookies, as `curl-cookie-jar-cookies` reads them. Raises an
assertion violation for anything but a session, or a session made without
`cookies`; and what `curl-cookie-jar-cookies` raises, `&curl-engine-error`,
`stopped`, for a closed session among it. See [Cookies](cookies.md).

### `http-session-load-cookies!`

```text
http-session-load-cookies! : Session (Listof String) -> Void
```

Loads the lines into the session's jar, as `curl-cookie-jar-load!` does.
Raises an assertion violation for anything but a session, or a session
made without `cookies`; and what `curl-cookie-jar-load!` raises,
`cookie-line` and, for a closed session, `&curl-engine-error`, `stopped`,
among it. See [Cookies](cookies.md).

## `(http-client)`: requests

### `http-request`

```text
http-request : Session Symbol String Any ... -> Response
```

`(http-request SESSION METHOD URL KEY VALUE ...)` makes one call: `METHOD`,
one of `get`, `head`, `post`, `put`, `patch` and `delete`, on an `http` or
`https` URL. It blocks until the response, which it answers whatever the
status, following redirects and retrying as the session says. Its keys:

| Key | Type | Default |
|:--|:--|:--|
| `headers`, `user-agent`, `timeout-ms`, `connect-timeout-ms`, `body-limit`, `ca-file`, `verify`, `proxy`, `http-version`, `credentials`, `proxy-ca-file`, `proxy-verify`, `redirects`, `allow-downgrade`, `retry` | as `make-http-session`'s | the session's |
| `body` | `(U Bytevector String Producer)`: bytes, a string sent as UTF-8, or a producer | none |
| `form` | `(Listof (Pairof String String))`, sent as `application/x-www-form-urlencoded` | none |
| `params` | `(Listof (Pairof String String))`, encoded and added to the URL's query | none |
| `body-length` | `(U Natural #f)`, a producer's `Content-Length`; `#f` sends it chunked | `#f` |
| `multipart` | `(Listof Part)`, the parts of a `multipart/form-data` body | none |

A producer is called as libcurl asks, and its body is sent at most once.
Its `timeout-ms` bounds the whole call, every redirect and retry among it.
Every condition it raises carries `&http-exchange`, the call's context.
Raises an assertion violation for anything but a session, a call inside a
critical section, or a producer's answer that is no bytevector of a byte
or more nor the end of file; `&http-request-error` for `unknown-key`,
`repeated-key`, `missing-value`, `not-a-body`, `not-name-value-pairs`,
`not-a-redirect-count`, `not-a-boolean`, `not-a-retry-policy`,
`body-and-form`, `multipart-beside-body` and `body-not-allowed`, and
`body-length-mismatch` for a producer's piece past its `body-length`; what
`make-curl-request` and `curl-submit` raise, for the call and each hop;
`&curl-url-error` for the URL, the params added; what each transfer ended
with, as `curl-token-await` raises it; `&http-timeout` when the
`timeout-ms` passes, with `&curl-timeout` when libcurl's 28 was the bound;
and `&http-redirect-error` for a redirect it does not follow. See
[The high level](high-level.md) and
[Redirects and retries](redirects-and-retries.md).

### `http-get`, `http-head`, `http-post`, `http-put`, `http-patch`, `http-delete`

```text
http-get : Session String Any ... -> Response
http-head : Session String Any ... -> Response
http-post : Session String Any ... -> Response
http-put : Session String Any ... -> Response
http-patch : Session String Any ... -> Response
http-delete : Session String Any ... -> Response
```

`http-request` with the method each name says:
`(http-get SESSION URL KEY VALUE ...)`. Raises what `http-request` raises.
See [The high level](high-level.md).

## `(http-client)`: responses

### `http-response?`, `http-response-status`, `http-response-http-version`, `http-response-url`, `http-response-headers`, `http-response-body`, `http-response-timings`, `http-response-history`

```text
http-response? : Any -> Boolean
http-response-status : Response -> Integer
http-response-http-version : Response -> (U 'http/1.0 'http/1.1 'http/2 'http/3 Integer #f)
http-response-url : Response -> String
http-response-headers : Response -> Headers
http-response-body : Response -> (U Bytevector #f)
http-response-timings : Response -> (U (Listof (Pairof Symbol Natural)) #f)
http-response-history : Response -> (Listof Response)
```

What a call answered: its status, version, the URL its last request asked
for, its headers and its body; its timings, as `curl-response-timings`;
and the redirects it followed, oldest first. The body and timings are
`#f` for a streamed response, and for a hop cancelled at its head. Raises
an assertion violation for anything but a response; `http-response?`
raises nothing. See [The high level](high-level.md).

### `http-response-header`

```text
http-response-header : Response String -> (U String #f)
```

The first header of that name, in any A to Z case, or `#f`. Raises an
assertion violation for anything but a response, or a name that is no
string. See [The high level](high-level.md).

### `http-response-text`

```text
http-response-text : Response -> String
```

The body as UTF-8 text: U+FFFD for a bad sequence, a leading byte-order
mark dropped, no charset read. Raises an assertion violation for anything
but a response, or one whose body is `#f`. See
[The high level](high-level.md).

## `(http-client)`: streams

### `call-with-response-port`

```text
call-with-response-port : Session Symbol String Any ... (Response Binary-Input-Port -> Any ...) -> Any ...
```

`(call-with-response-port SESSION METHOD URL KEY VALUE ... PROC)` makes the
call as `http-request` does, then calls `PROC` with the final response and
a port over its body as it arrives, and answers `PROC`'s values. When
`PROC` returns or escapes, the port is closed and the transfer cancelled.
Its keys:

| Key | Type | Default |
|:--|:--|:--|
| `headers`, `user-agent`, `timeout-ms`, `connect-timeout-ms`, `body-limit`, `ca-file`, `verify`, `proxy`, `http-version`, `credentials`, `proxy-ca-file`, `proxy-verify`, `redirects`, `allow-downgrade`, `retry`, `body`, `form`, `params`, `body-length`, `multipart` | as `http-request`'s | as `http-request`'s |
| `stream-buffer` | `Positive-Integer`, the bytes of the body it buffers | `65536` |

Raises an assertion violation for
a last argument that is no procedure, before anything else, and for a
`stream-buffer` of `#f`; what `http-request` raises; and, from the port's
reads, the transfer's failure, with `&http-exchange`, and `&http-timeout`
when the bound passed, and an assertion violation for a read from another
thread or from the producer. See [Streams](streams.md).

## `(http-client)`: retries

### `make-http-retry`

```text
make-http-retry : Any ... -> Retry
```

`(make-http-retry KEY VALUE ...)` is a retry policy, data alone, for a
session's or a call's `retry` key. Each key may be given once:

| Key | Type | Default |
|:--|:--|:--|
| `attempts` | `Positive-Integer`, the transfers per step, the first among them | `3` |
| `backoff-ms` | `Natural`, the first retry's wait, doubling after | `200` |
| `max-backoff-ms` | `Natural`, the most a wait, or a `Retry-After`, may be | `10000` |
| `jitter` | `Boolean`: `#t` waits a random share of the backoff | `#t` |
| `statuses` | `(Listof Integer)`, from 400 to 599, the statuses retried | `(429 503)` |
| `methods` | `(Listof Symbol)`, the methods a status or a sent request is retried for | `(get head put delete)` |

Raises `&http-request-error` for `unknown-key`, `repeated-key` and
`missing-value`, then `not-an-attempt-count`, `not-a-backoff`,
`not-a-boolean`, `not-a-status-list` and `not-a-method-list`. See
[Redirects and retries](redirects-and-retries.md).

### `http-retry?`

```text
http-retry? : Any -> Boolean
```

Whether it is a retry policy. Raises nothing. See
[Redirects and retries](redirects-and-retries.md).

## `(http-client)`: groups

### `call-with-request-group`

```text
call-with-request-group : Session Any ... (Go -> Any) -> Any
go : Symbol String Any ... -> Pending
```

`(call-with-request-group SESSION KEY VALUE ... PROC)` calls `PROC` with
`go`, which starts a call, as `http-request` takes one, and answers its
pending at once. Every call runs on this one thread. It returns once every
call it started has ended. Its one key:

| Key | Type | Default |
|:--|:--|:--|
| `limit` | `(U Positive-Integer #f)`, the most calls in flight | `#f` |

Raises an assertion violation
inside a critical section, before anything else, and for no session or a
last argument that is no procedure; `&http-request-error` for
`unknown-key`, `repeated-key`, `missing-value` and `not-a-limit`; from
`go`, what `http-request`'s checks raise, and `stream-in-group` for a
producer; `&http-group-error`, `wrong-thread`, for `go` from another
thread, and `closed` for `go` once `PROC` has returned; and, once `PROC`
returns, the first failure no await answered. See [Groups](groups.md).

### `http-pending?`, `http-await`

```text
http-pending? : Any -> Boolean
http-await : Pending -> Response
```

Waits for the call, driving the whole group meanwhile, and answers its
response, any number of times. Raises an assertion violation for anything
but a pending, or inside a critical section; `&http-group-error`,
`wrong-thread`, from another thread; the call's failure, as `http-request`
raises it; and `&http-group-error`, `cancelled`, for a cancelled call.
`http-pending?` raises nothing. See [Groups](groups.md).

### `http-pending-done?`

```text
http-pending-done? : Pending -> Boolean
```

Moves the group on one turn, without waiting, then says whether the call
has ended. Raises an assertion violation for anything but a pending, or
inside a critical section; and `&http-group-error`, `wrong-thread`, from
another thread. See [Groups](groups.md).

### `http-pending-cancel`

```text
http-pending-cancel : Pending -> Void
```

Ends the call as cancelled, without waiting. A call that has ended keeps
its answer. Raises an assertion violation for anything but a pending, and
`&http-group-error`, `wrong-thread`, from another thread. See
[Groups](groups.md).

### `http-parallel`

```text
http-parallel : Session (Listof (Pairof Symbol (Pairof String (Listof Any)))) Any ... -> (Listof Response)
```

`(http-parallel SESSION SPECS KEY VALUE ...)` runs each spec,
`(METHOD URL KEY VALUE ...)`, in one group, and answers the responses in
the specs' order. Every spec is checked before any is sent. Its one key:

| Key | Type | Default |
|:--|:--|:--|
| `limit` | as `call-with-request-group`'s | `#f` |

Raises an assertion violation
inside a critical section, before anything else, for no session, and for
specs that are not a list of lists, each of a method, a URL, then keys;
`&http-request-error` for `unknown-key`,
`repeated-key`, `missing-value` and `not-a-limit`; each spec's refusal, as
`http-request` and `curl-request-check` make it, and `stream-in-group` for
a producer; and the first call to fail, once the rest have ended. See
[Groups](groups.md).

## `(http-client)`: conditions

Each condition type below but `&http-exchange` is an `&http-error`, under
`&curl-error`. Its accessors raise an assertion violation for anything of
another kind, naming it by its kind, never its value.

### `&http-error`, `http-error?`

```text
http-error? : Any -> Boolean
```

The base of the high level's own conditions. Raises nothing. See
[Errors](errors.md).

### `&http-request-error`, `http-request-error?`, `http-request-error-field`, `http-request-error-value`, `http-request-error-reason`, `http-request-error-reasons`

```text
http-request-error? : Any -> Boolean
http-request-error-field : &http-request-error -> Symbol
http-request-error-value : &http-request-error -> Any
http-request-error-reason : &http-request-error -> Symbol
http-request-error-reasons : (Listof Symbol)
```

A key or a value the high level checks, refused: which one, its value, and
why. The reasons: `unknown-key`, `repeated-key`, `missing-value`,
`body-and-form`, `multipart-beside-body`, `body-not-allowed`, `not-a-body`,
`not-name-value-pairs`, `not-a-redirect-count`, `not-a-boolean`,
`not-a-retry-policy`, `not-an-attempt-count`, `not-a-backoff`,
`not-a-status-list`, `not-a-method-list`, `not-a-limit`, `stream-in-group`,
`body-length-mismatch`. Raises an assertion violation, from an accessor,
for anything of another kind. See [Errors](errors.md).

### `&http-redirect-error`, `http-redirect-error?`, `http-redirect-error-reason`, `http-redirect-error-response`, `http-redirect-error-location`, `http-redirect-error-reasons`

```text
http-redirect-error? : Any -> Boolean
http-redirect-error-reason : &http-redirect-error -> Symbol
http-redirect-error-response : &http-redirect-error -> Response
http-redirect-error-location : &http-redirect-error -> (U String #f)
http-redirect-error-reasons : (Listof Symbol)
```

A redirect the rules do not follow: why, the response that asked for it,
and its `Location`. The reasons: `too-many-redirects`, `bad-location`,
`insecure-redirect`, `body-not-replayable`. Raises an assertion violation,
from an accessor, for anything of another kind. See
[Redirects and retries](redirects-and-retries.md) and
[Errors](errors.md).

### `&http-timeout`, `http-timeout?`, `http-timeout-timeout-ms`

```text
http-timeout? : Any -> Boolean
http-timeout-timeout-ms : &http-timeout -> Positive-Integer
```

A call's `timeout-ms` passed, and which it was. Raises an assertion
violation, from an accessor, for anything of another kind. See
[Errors](errors.md).

### `&http-group-error`, `http-group-error?`, `http-group-error-reason`, `http-group-error-reasons`

```text
http-group-error? : Any -> Boolean
http-group-error-reason : &http-group-error -> Symbol
http-group-error-reasons : (Listof Symbol)
```

A request group's refusal, or the await of a call it cancelled. The
reasons: `wrong-thread`, `closed`, `cancelled`. Raises an assertion
violation, from an accessor, for anything of another kind. See
[Groups](groups.md) and [Errors](errors.md).

### `&http-exchange`, `http-exchange?`, `http-exchange-method`, `http-exchange-url`, `http-exchange-history`, `http-exchange-transfers`

```text
http-exchange? : Any -> Boolean
http-exchange-method : &http-exchange -> Any
http-exchange-url : &http-exchange -> Any
http-exchange-history : &http-exchange -> (Listof Response)
http-exchange-transfers : &http-exchange -> Natural
```

The context every condition a call raises carries, under `&condition`: the
method and URL as the caller gave them, the responses that redirected,
oldest first, and how many transfers the engine took for the call. Raises
an assertion violation, from an accessor, for anything of another kind. See
[Errors](errors.md).
