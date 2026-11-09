# The low level: `(curl)`

`(curl)` is what `(http-client)` is built on. A request is data. An engine
runs it, on a thread of its own, and hands you a token at once. The token
gives you the response when the transfer ends. Nothing is followed or retried
for you.

```scheme example=examples/engine-and-tokens.sps
;; One engine: a thread of its own, which runs every transfer submitted.
(define engine (make-curl-engine))

;; A request is data; curl-request-with makes another from it.
(define ok (make-curl-request (string-append base "/status/200") 'timeout-ms 10000))
(define created (curl-request-with ok 'url (string-append base "/status/201")))
(define accepted (curl-request-with ok 'url (string-append base "/status/202")))

;; A submit answers a token at once; an await waits for its response.
(display (curl-response-status (curl-token-await (curl-submit engine ok))))
(newline)
```

## Engines

- **`(make-curl-engine)`** starts a thread, which runs every transfer
  submitted to it, many at once. It loads libcurl first, on your thread.
- **`(curl-engine-stop ENGINE)`** ends every transfer the engine holds as
  stopped, frees them all, and returns once its thread has ended. A later
  stop returns at once, and a later submit raises `&curl-engine-error`,
  `stopped`. An engine that failed ended its transfers as failed when it did;
  a submit to it raises its failure.
- **Stop every engine you make.** Its thread, its connections and its jars are
  native objects, and nothing frees them for you.
- **Reference `(curl)` on one thread before others use it.** A program that
  imports it loads it before its first line. Code that reaches it first by
  `eval`, or at the REPL, from several threads at once can meet Chez's
  `cyclic dependency` error.

What engines do on some libcurls, a stalled name lookup's wait among it, is on
[What varies by libcurl](libcurl-versions.md#engines-and-groups).

## Requests

`(make-curl-request URL KEY VALUE ...)` makes a request for an `http://` or
`https://` URL. Each key is given once at most; each left out takes its
default, libcurl's own. [Reference](reference.md) lists every key, and
[Headers and JSON](headers-and-json.md) says what `headers` sends and
refuses.

- **It is checked as you make it:** a key it does not take, one given twice,
  or one with no value is refused by name, `unknown-key`, `repeated-key` or
  `missing-value`; then each value, a body beside `get` or `head` among them,
  `body-not-allowed`. A submit checks it again, on copies of your strings and
  lists, and refuses one changed since.
- **`(curl-request-with REQUEST KEY VALUE ...)`** makes a new request, the keys
  given replaced, `url` among them, the rest kept.
- **`(curl-request-check REQUEST)`** runs the checks a submit makes, and
  raises what they raise, sending nothing: check a batch before you submit
  any of it.
- **Each key has an accessor,** `curl-request-url` to
  `curl-request-cookie-jar`, which answers what the request holds: the very
  strings and lists you gave it, but for the proxy URL, the proxy's CA file,
  the credentials and a multipart body, which come back as fresh copies.
- **A printed request, token or engine shows its type alone,**
  `#<curl-request>`, never what it holds.

## Tokens

`(curl-submit ENGINE REQUEST [MAILBOX [CALLBACK]])` queues the transfer and
answers its token at once.

- **`curl-token-await`** waits for the transfer, and answers its response, or
  raises what it ended with. Any thread may await a token, any number of
  times.
- **`curl-token-wait TOKEN MS`** tells whether it ended within MS
  milliseconds; it runs on either way.
- **`curl-token-done?`** and **`curl-token-outcome`** never wait and never
  raise: the outcome is the response, or the condition the await would raise,
  as data, or `#f` before the end.
- **`curl-token-cancel`** ends the transfer as cancelled, and returns at once.
  One that has ended keeps its outcome.
- **Every wait sleeps between its looks,** so Ctrl-C reaches it. None may run
  inside a critical section.

A response holds `curl-response-status`, `curl-response-http-version`,
`curl-response-effective-url`, `curl-response-headers`, `curl-response-body`,
a bytevector, and `curl-response-timings`: the microseconds from the start to
the end of `name-lookup`, `connect`, `tls-handshake`, `first-byte` and
`total`, 0 for a phase skipped.

A streamed body is a token's too: see [Streams](streams.md).

## Mailboxes

A mailbox collects finished tokens, from any number of engines, oldest first:

```scheme example=examples/engine-and-tokens.sps
;; With a mailbox, each token goes there when its transfer ends. They end
;; in no fixed order: sort what they answer.
(define mailbox (make-curl-mailbox))
(for-each (lambda (request) (curl-submit engine request mailbox))
          (list ok created accepted))
(let loop ((left 3) (statuses '()))
  (if (= left 0)
      (begin (write (list-sort < statuses)) (newline))
      (let ((token (curl-mailbox-take mailbox 10000)))
        (loop (- left 1)
              (cons (curl-response-status (curl-token-await token)) statuses)))))
```

- **`curl-mailbox-take MAILBOX MS`** takes the next finished token out,
  waiting up to MS milliseconds, or answers `#f`.
- **`curl-mailbox-deliver MAILBOX MS`** takes one the same way, then calls its
  callback, the one given to `curl-submit`, with it, on your thread. The
  callback's raise leaves through it. A callback needs a mailbox.
- **If an interrupt handler escapes from a take,** that token may never come
  out of the mailbox, though its outcome is kept. Where a handler can escape,
  keep your tokens, and await them.

## URLs

These read and build URLs with libcurl's own URL parser, the one a transfer
uses:

```scheme fragment
(curl-url-part "https://u@example.com:8443/a?b#c" 'port)      ; 8443
(curl-url-part "https://example.com/a" 'port)                 ; 443
(curl-url-append-query "https://example.com/s?q=1" "page=2")  ; "https://example.com/s?q=1&page=2"
(curl-url-resolve "http://example.com/a/b/c" "../d?x=2")      ; "http://example.com/a/d?x=2"
(curl-url-with-fragment "http://example.com/a" "top")         ; "http://example.com/a#top"
```

- **`curl-url-part URL PART`** gives one part: `url`, the whole URL; `scheme`,
  `user`, `password`, `host`, `path`, `query`, `fragment` or `zoneid`, a
  string, or `#f` for one the URL lacks; or `port`, a number, the scheme's
  default when the URL names none. An IPv6 host comes without its zone ID.
- **`curl-url-append-query URL PART`** appends PART, already encoded, to the
  query, after a `&` unless the query is empty or ends in one. It goes out as
  written, and the fragment is kept.
- **`curl-url-resolve BASE REFERENCE`** resolves REFERENCE against BASE. A
  string is sent as UTF-8; a bytevector, a header's bytes, has each byte at
  or below 0x20, 0x7F and above encoded as `%XX` first.
- **`curl-url-with-fragment URL FRAGMENT`** replaces the fragment, or clears
  it with `#f` or `""`. A bytevector is encoded the same way.

A refusal raises `&curl-url-error`, holding the input, a reason and a code
([Errors](errors.md)).

**libcurl's parser is not RFC 3986's.** It takes `http://example.com/a%zz`
unchanged, makes `http:/example.com/x` into `http://example.com/x`, and keeps
a host's case and an explicit default port: `HTTP://Example.COM:80/x` comes
back as `http://Example.COM:80/x`. So compare origins by scheme, lower-cased
host and port, never as strings. For a strict RFC 3986 verdict, check the
string with a strict parser, such as uriparse, before you hand it over. More
of its answers [vary by libcurl](libcurl-versions.md#urls).
