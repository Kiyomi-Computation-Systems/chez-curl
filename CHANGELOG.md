# Changelog

All notable changes to chez-curl are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-11-13

A documentation release: the libraries are 0.1.0's, unchanged.

### Changed

- **Running the examples.** Each example's head comment, README.org, the
  [docs index](docs/README.md#the-examples), the [quick start](docs/quickstart.md)
  and each page with an example say to start the test server first, with
  `node tests/origin.mjs`, and to give an example the address after `"http":` in
  the line it prints: `raw`'s and `h2c`'s speak other protocols. `json-api.sps`
  alone needs `make deps`, and `src:build/scheme-libs` as its library path.
- **Node.js** runs only the test server, which the tests and the examples call:
  a program using chez-curl never needs it. The tests also need `openssl` and GNU
  `timeout`.
- **Installing** clones the release's tag, in README.org and the quick start,
  not `main`.
- README.org's mentions of libcurl link [its site](https://curl.se/libcurl/), and
  its Status names no version.

## [0.1.0] - 2026-11-10

The first release: an HTTP client for Chez Scheme, built on libcurl. It binds
libcurl through Chez's foreign interface, and checks what you hand it before any
of it reaches C. It has two levels: `(http-client)`, a session and a call per
request, and `(curl)` beneath it, where a request is data, an engine runs it,
and a token hands you the response. There is nothing to build: libcurl is
loaded when your program runs. It needs Chez Scheme 10.4.0 or later, built with
threads, and libcurl 7.85.0 or later, built with TLS; the tests need Node.js 20
or later.

### Added

- **Sessions.** `call-with-http-session` makes a session, hands it to your
  procedure, and closes it after; `make-http-session` makes one that lives until
  `http-session-close`. A session holds one engine, its one thread, and the
  defaults its calls share. A call's value replaces its session's
  ([The high level](docs/high-level.md)).
- **A call per request.** `http-request` takes a method, `get`, `head`, `post`,
  `put`, `patch` or `delete`, and `http-get`, `http-head`, `http-post`,
  `http-put`, `http-patch` and `http-delete` name it for you. A call blocks
  until the response, and answers it whatever the status: a 404 is data, not an
  error. A response holds its status, version, URL, headers, body, timings and
  the redirects it followed. A call that is escaped, by a Ctrl-C's handler or a
  timer, cancels its transfer ([The high level](docs/high-level.md)).
- **Bodies, forms and params.** `body` is a bytevector, a string sent as UTF-8,
  or a producer. `form` sends `(NAME . VALUE)` strings as
  `application/x-www-form-urlencoded`, and `params` appends them to the URL's
  query. No body waits for a 100: chez-curl takes away the
  `Expect: 100-continue` libcurl adds to a body past 1 MiB
  ([The high level](docs/high-level.md)).
- **Multipart.** `multipart` sends a `multipart/form-data` body, its parts a
  string, a bytevector or `(file PATH)`, each with an optional `filename` and
  `type`. Names, filenames and types are checked, and a file part must be a
  regular file as the call starts, at each submit, and as the engine starts the
  transfer. The low level takes the same parts as a request's `body`
  ([The high level](docs/high-level.md)).
- **Timeouts and limits.** `timeout-ms` bounds the whole call, its redirects and
  retries among it, and raises `&http-timeout`; a retry that runs out of time
  having sent nothing answers the last response, or raises the last failure.
  `connect-timeout-ms` bounds each connection, and `body-limit` the response
  body's bytes, past which a call raises `&curl-too-large` ([The high
  level](docs/high-level.md)).
- **A cap on response headers.** Every transfer caps its response headers at
  1,000 lines or 102,400 bytes, counted over the whole transfer: every head, a
  1xx, a proxy's `CONNECT` answer and each auth round's among them, and the
  trailers. Past either it raises `&curl-too-large`, reason `header-limit`.
  Some heads meet one of libcurl's own limits first, and fail with its code
  instead, by version ([The high level](docs/high-level.md),
  [What varies](docs/libcurl-versions.md#errors)).
- **Headers.** `headers` is a list of `(NAME . VALUE)` strings, on a session, a
  call or a request, and `user-agent` is a key of its own. A call's header
  replaces every session header of its name. Each is checked before anything is
  sent, and a refusal names the header, never its value. `http-response-header`
  reads a response's first header of a name, in any case
  ([Headers and JSON](docs/headers-and-json.md)).
- **A JSON API, through a JSON library.** chez-curl has no JSON of its own: a
  body is bytes. `examples/json-api.sps` calls a JSON API with jsonparse, a
  submodule for the example alone, and the page shows how to put it on the
  library path ([Headers and JSON](docs/headers-and-json.md)).
- **Redirects, by chez-curl's own rules.** A call follows a 301, 302, 303, 307
  or 308, up to `redirects` times, 20 unless you say. To another origin it drops
  `Authorization`, `Cookie` and its `credentials`. From `https` to `http` is
  refused unless `allow-downgrade` is `#t`, and a redirect the rules do not
  follow raises `&http-redirect-error`
  ([Redirects and retries](docs/redirects-and-retries.md)).
- **Retries, by a policy you give.** Nothing is retried unless the session or
  the call names a policy, made by `make-http-retry`: its attempts, a backoff
  that doubles, with jitter, and the statuses and methods it retries. A retried
  status's `Retry-After` sets the wait
  ([Redirects and retries](docs/redirects-and-retries.md)).
- **Credentials.** `credentials` sends Basic, Digest or Bearer:
  `(basic USER PASSWORD)`, `(digest USER PASSWORD)` or `(bearer TOKEN)`. Each
  string is checked, and a refusal names only the scheme and part, such as
  `(basic password)` ([Auth and proxies](docs/auth-and-proxies.md)).
- **Proxies.** `proxy` is `environment`, the default, through the proxy
  `http_proxy` and the like name; `#f`, direct; or an `http://` or `https://`
  proxy URL, whose user and password are its credentials. An `https://` proxy's
  TLS is its own: `proxy-ca-file` and `proxy-verify`. A refused proxy URL is
  named by its field, never its text
  ([Auth and proxies](docs/auth-and-proxies.md)).
- **Cookies.** A session made with `cookies #t` keeps a jar:
  `http-session-cookies` reads it out, and `http-session-load-cookies!` loads
  lines into it. At the low level, `make-curl-cookie-jar` makes an engine's jar,
  which each request takes as `cookie-jar`. A jar holds cookies alone, in
  memory, and a load checks every line before it loads any
  ([Cookies](docs/cookies.md)).
- **The HTTP version.** `http-version` asks for `http/1.1`, `http/2` or
  `http/2-prior-knowledge`. `#f`, the default, lets libcurl choose: HTTP/2 over
  `https://` when the server offers it, else HTTP/1.1. A response tells which
  version answered ([Choosing the HTTP version](docs/http-version.md)).
- **Streams, both ways, at both levels.** `call-with-response-port` hands your
  procedure the response's head and a binary input port over its body, and a
  call's `body` may be a producer, sent as it is made. At the low level, a
  request's `stream-buffer` hands its body over in pieces, and `body 'stream`
  takes its body from your puts. A full buffer pauses the transfer
  ([Streams](docs/streams.md)).
- **Many calls at once, on one thread.** An engine's one thread drives every
  transfer submitted to it. `call-with-request-group` hands your procedure `go`,
  which starts a call and answers its pending at once, and `http-await` gives
  its response. `http-parallel` runs a list of calls, at most `limit` at once,
  and answers in the list's order ([Groups](docs/groups.md)).
- **The low level: engines, requests and tokens.** `make-curl-engine` starts a
  thread that runs every transfer submitted to it, and `curl-engine-stop` ends
  it. `make-curl-request` makes a request, checked as you make it and again as
  you submit it. `curl-submit` answers a token at once: `curl-token-await` waits
  for its response, and `curl-token-cancel` ends it. Nothing is followed or
  retried for you ([The low level](docs/low-level.md)).
- **Mailboxes.** `make-curl-mailbox` makes a mailbox, which collects finished
  tokens, from any number of engines, oldest first. `curl-mailbox-take` takes
  the next, and `curl-mailbox-deliver` calls its callback on your thread
  ([The low level](docs/low-level.md)).
- **URLs, by libcurl's parser.** `curl-url-part`, `curl-url-append-query`,
  `curl-url-resolve` and `curl-url-with-fragment` read and build URLs with the
  parser a transfer uses. It is not RFC 3986's: compare origins by scheme,
  lower-cased host and port, never as strings
  ([The low level](docs/low-level.md)).
- **Errors.** Every chez-curl condition type but `&http-exchange`, which a
  call's raise carries, is a `&curl-error`, under R6RS's `&error`: a refused
  libcurl, request or URL; a failed transfer, by class, a timeout, a connect,
  send-receive, TLS or protocol error, or too large; an engine stopped or
  failed; a wrong thread; a string holding U+0000; and the high level's own. A
  reason is a symbol, chez-curl's and alike on every libcurl, but a refused
  URL's, which is libcurl's code's name, and the hatch's `unknown-option` on
  7.85.0. A refusal names a field, a kind or an index, never your secret. A
  printed request, token or engine shows its type alone
  ([Errors](docs/errors.md)).
- **TLS.** A request checks the server's certificate and name by default.
  `ca-file` names the only CA file to trust, and `verify #f` turns the check
  off. Where another anchor could sit beside your CA file, Guix's libcurl with
  `SSL_CERT_FILE` or `SSL_CERT_DIR` set, or Apple's LibreSSL, a request with a
  `ca-file` and `verify` on is refused, `environment-override` or
  `keychain-fallback` ([TLS and the environment](docs/tls-and-environment.md)).
- **Finding libcurl.** chez-curl loads the system's libcurl itself, once per
  process: Guix's profile on Guix, the usual library directories elsewhere on
  Linux, and Apple's on macOS. `CHEZ_CURL_LIBCURL` names another, by its
  absolute path. `loaded-libcurl` tells what was loaded, and a refusal,
  `&curl-library-unavailable`, says why
  ([TLS and the environment](docs/tls-and-environment.md)).
- **The hatch.** `(curl unsupported)`'s `curl-request-with-options` attaches a
  libcurl option to a request by its name, for what the keys do not cover. It
  refuses every option chez-curl owns, and each one's twin
  ([The hatch](docs/hatch.md)).
- **The docs and the examples.** [README.org](README.org),
  [a quick start](docs/quickstart.md), a page per topic, what varies by
  libcurl, and [a reference](docs/reference.md) with every export, its type and
  what it raises ([the docs' index](docs/README.md)). `examples/`
  holds eleven small programs to copy from, and `make test` runs each against
  the test server, its output held to `examples/expected/`.

### Known limitations

- **Platforms.** The suites run on Linux on amd64, on curl's own 7.85.0 and
  8.23.0, built from source, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, and
  Guix's 8.20.0; and on macOS on arm64, with Apple's libcurl 8.7.1. Linux on
  arm64 and macOS on amd64 have not run them. Windows is not supported.
- **Older distributions.** Ubuntu 22.04, Debian 11 and RHEL 9 ship a libcurl
  older than the floor: on them, build or install a newer one and set
  `CHEZ_CURL_LIBCURL` to it
  ([TLS and the environment](docs/tls-and-environment.md)).
- **One plain error.** A libcurl that refuses a cookie jar's make, read-out or
  load raises Chez's `&error`, no chez-curl condition
  ([Cookies](docs/cookies.md)).
- **Some behaviour varies by libcurl.** chez-curl hands most of a transfer to
  libcurl, so some of what a caller meets depends on which libcurl is loaded.
  [What varies by libcurl](docs/libcurl-versions.md) lists each, by topic. The
  ones you are most likely to meet:
  - A failed transfer's code moves with the version, and its class with the
    code: a refused `CONNECT` fails 56, `&curl-send-receive-error`, on 7.85.0,
    8.5.0 and 8.7.1, and 7, `&curl-connect-error`, on 8.20.0 and 8.23.0. Catch
    `&curl-transfer-error`, then read its reason.
  - On libcurl 8.7.0 and 8.7.1, the Mac's, a transfer's size is unknown, so one
    that ran counts as sent: a `post` there is not retried after a refused
    connect. There the engine does not multiplex.
  - An HTTP/2 3xx that comes before a body is sent whole never ends on 8.20.0
    and 8.23.0: over HTTP/2, pass a `timeout-ms`.
  - libcurl before 7.87.0 cannot leave a stalled lookup's thread behind, so
    there a cancel, a timeout or a stop during one waits for it, up to the
    resolver's own timeout.
  - Which cookies are kept, and which go to which host and path, are libcurl's
    rules, and vary by version.
- **Not supported.**
  - A method is `get`, `head`, `post`, `put`, `patch` or `delete`.
  - A multipart part is a string, a bytevector or a file: no part streams,
    nests parts, is encoded, or takes headers of its own.
  - No key sets the cap on response headers.
  - A `proxy` URL is `http://` or `https://`: `socks5://` is refused,
    `proxy-scheme`.
  - A cookie jar holds cookies in memory alone: no file, and no HSTS entry. A
    transfer reads no `.netrc`.
  - The hatch is unsupported: no promise it stays the same. The high level
    takes no hatch options.
- **What chez-curl does not prevent.**
  - A second Ctrl-C, or a timer, that interrupts a session's close can leave
    its engine running until the process exits; one during a group's wait for
    its cancelled calls leaves their transfers running.
  - An interrupt handler that escapes from a mailbox's take can leave that
    token out of the mailbox for good, though its outcome is kept.
  - A file part that changes after its last check is yours, and a path swapped
    for a FIFO then holds the engine's thread until a writer comes. If you
    cannot trust the file system, send the file's bytes as a bytevector part.
  - A call's checks pause Ctrl-C and every other thread's garbage collection,
    for longer the more you pass: bound what you take from untrusted input.
  - The environment's proxy is libcurl's to read: chez-curl checks none of its
    user and password, and does not refuse a stalling TLS-inside-TLS proxy a
    variable names.

[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-curl/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Kiyomi-Computation-Systems/chez-curl/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-curl/releases/tag/v0.1.0
