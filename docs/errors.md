# Errors

**A status is data.** A 404 or a 503 is an answer: the call returns it. A call
raises when it was refused before it was sent; when its transfer failed; when
an answer came past what you allowed, a body past `body-limit` or headers past
the cap; and when it met a redirect it will not follow.

The examples on this page call the test server: start it first, with
`node tests/origin.mjs`, and give an example the address after `"http":` in
the line it prints, not `raw`'s or `h2c`'s ([The examples](README.md#the-examples)).

```scheme example=examples/errors.sps
    ;; A 404 is an answer, not an error.
    (show (http-response-status (http-get session (url "/status/404"))))
    ;; The call's timeout-ms passed: &http-timeout, with (curl)'s &curl-timeout.
    (show (guard (e ((http-timeout? e)
                     (list 'timeout (http-timeout-timeout-ms e) (curl-timeout? e))))
            (http-get session (url "/pattern/10?delay=2000") 'timeout-ms 200)))
    ;; A body past body-limit: &curl-too-large. This one's Content-Length
    ;; says so before any byte comes, so libcurl refuses it, perform-failed.
    (show (guard (e ((curl-too-large? e)
                     (list 'too-large (curl-transfer-error-reason e))))
            (http-get session (url "/pattern/100000") 'body-limit 1000)))
    ;; A request refused before anything is sent: &curl-request-error,
    ;; naming the field and the reason, never a secret.
    (show (guard (e ((curl-request-error? e)
                     (list (curl-request-error-field e) (curl-request-error-reason e))))
            (curl-request-check
             (make-curl-request "https://example.invalid/"
                                'http-version 'http/2-prior-knowledge))))
```

```text output=examples/expected/errors.out
404
(timeout 200 #t)
(too-large perform-failed)
(http-version prior-knowledge-over-https)
```

## The types

Every chez-curl condition type but `&http-exchange` is a `&curl-error`, under
R6RS's `&error`:

```text
&curl-error
  &curl-library-unavailable   libcurl was refused at the load
  &curl-request-error         a request's key or value refused
  &curl-url-error             a URL refused
  &curl-transfer-error        a transfer that failed
    &curl-timeout  &curl-connect-error  &curl-send-receive-error
    &curl-tls-error  &curl-protocol-error  &curl-too-large
  &curl-engine-error          an engine stopped, or failed
  &curl-wrong-thread          a port or handle used from another thread
  &curl-embedded-nul          a string holding U+0000, which C would read short
  &http-error                 the high level's own
    &http-request-error  &http-redirect-error  &http-timeout  &http-group-error
```

Each has a predicate, `curl-timeout?` and the like, and accessors for its
fields. Each type with reasons exports their list: `curl-request-error-reasons`
and the rest. A wrong argument is an assertion violation, as R6RS has it.

**What a call raises carries `&http-exchange`:** the method and URL as you
gave them, the history, and `http-exchange-transfers`, how many transfers it
made. A low-level condition passes through a call so compounded, so catch
`(curl)`'s types by importing `(curl)` too.

## Handling one

- **Read the reason, a symbol.** It is chez-curl's, and alike on every
  libcurl, but for two: a refused URL's reason is libcurl's code's name, which
  moves with the version ([What varies](libcurl-versions.md#urls)), and the
  hatch names an owned option this libcurl does not know `unknown-option` on
  7.85.0 ([What varies](libcurl-versions.md#the-hatch)). A failed transfer's
  code is libcurl's, and moves with the version, and its class moves with the
  code: a refused `CONNECT` fails 56, `&curl-send-receive-error`, on 7.85.0,
  8.5.0 and 8.7.1, and 7, `&curl-connect-error`, on 8.20.0 and 8.23.0; prior
  knowledge to an HTTP/1.1 server is a send-receive or a protocol failure, by
  version and by race. So to catch a failed transfer, catch
  `&curl-transfer-error`, then read its reason, and its connect code for a
  proxy. Never match a code, a class or a message alone.
- **Every refusal names a field, a kind or an index, never your secret.** A
  string where a key, a request or a response belongs is named by its kind,
  `(kind string)`; a refused URL by its field, `url`; a header's value by its
  header's name; a credential by its scheme and part. `curl-url-error-input`
  still holds the URL.
- **A `guard` around `curl-token-await`** also catches what your own Ctrl-C
  handler raises while it waits. To tell the two apart, wait with
  `curl-token-wait`, outside any guard, then read `curl-token-outcome`.

## A failed transfer

`&curl-transfer-error` holds a reason, libcurl's code, `-strerror` and
`-error-buffer`, libcurl's text, and two numbers:

- **`curl-transfer-error-request-size`:** the bytes of request sent, 0 when
  none was, which is what a retry policy reads. `#f` when it is unknown: a
  transfer cancelled or stopped, and any transfer on libcurl 8.7.0 and 8.7.1,
  the Mac's, whose count is broken. For a multipart body it counts
  differently by version ([What varies](libcurl-versions.md#multipart)).
- **`curl-transfer-error-connect-code`:** the status a proxy refused the
  transfer's `CONNECT` with, or `#f`.

| Reason | What |
|---|---|
| `perform-failed` | libcurl ended the transfer with a code: its class, below, by the code |
| `body-limit` | the body passed `body-limit`, as it arrived |
| `header-limit` | the response headers passed the cap: 1,000 lines or 102,400 bytes over the whole transfer |
| `callback-raised` | something raised inside chez-curl's callback; `-recorded` holds it |
| `setopt-failed` | libcurl refused an option's value; `-option` names it |
| `unknown-option` | the loaded libcurl does not know an option |
| `no-handle` | libcurl made no handle |
| `cancelled` | you cancelled it |
| `stopped` | its engine stopped |
| `pause-failed` | libcurl failed to resume a paused stream |
| `body-length-mismatch` | a streamed body ended short of `body-length`, or a piece went past it |
| `body-not-replayable` | libcurl wanted to send a streamed body again |
| `part-file` | a file part was no regular file as the engine started the transfer, did not open, or libcurl refused it |
| `mime-failed` | libcurl failed to make the multipart body |

**The classes,** for `perform-failed`, by libcurl's code; a code none names
raises the base type. A class is the kind of failure libcurl's code names, so
it moves when the code does:

| Class | Codes |
|---|---|
| `&curl-timeout` | 28 |
| `&curl-connect-error` | 5, 6, 7, 45, 96, 97 |
| `&curl-send-receive-error` | 18, 52, 55, 56 |
| `&curl-tls-error` | 35, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91, 98, 101 |
| `&curl-protocol-error` | 1, 8, 16, 61, 92, 95 |
| `&curl-too-large` | 63, 100, and the reasons `body-limit` and `header-limit` |

**A body too large** is `&curl-too-large` either way. When the response's
`Content-Length` already passes `body-limit`, libcurl refuses it before any
byte arrives: code 63, reason `perform-failed`. When the length is not known,
the body is refused as it arrives, reason `body-limit`.

**The header cap** is `&curl-too-large`, reason `header-limit`, whatever
libcurl's code beside it. A call raises it, `call-with-response-port` before
your procedure is called; and a stream whose cap falls in the head never
publishes the head, its port raising it instead. Some heads meet one of libcurl's own limits first,
and fail with its code instead, by version
([What varies](libcurl-versions.md#errors)).

## The other types

| Type | Reasons |
|---|---|
| `&curl-library-unavailable` | `invalid-override`, `not-found`, `load-failed`, `below-floor`, `no-ssl`, `missing-api` ([TLS and the environment](tls-and-environment.md)) |
| `&curl-url-error` | libcurl's own, by its code's name, `malformed-input`, `bad-port-number`, `unsupported-scheme`, `bad-hostname` and the rest, `#f` for a code newer than the floor's; and chez-curl's: `scheme-not-http`, `embedded-nul`, `not-utf-8`, `query-not-kept` |
| `&curl-engine-error` | `stopped`; `failed`, with the condition that broke the engine in `curl-engine-error-condition` |
| `&curl-wrong-thread` | none: `-who` names the operation, `-expected` and `-actual` the threads |
| `&http-redirect-error` | `too-many-redirects`, `bad-location`, `insecure-redirect`, `body-not-replayable` ([Redirects](redirects-and-retries.md)) |
| `&http-timeout` | none: `http-timeout-timeout-ms` is the bound that passed |
| `&http-group-error` | `wrong-thread`, `closed`, `cancelled` ([Groups](groups.md)) |

**`&http-request-error`,** a key or value the high level checks:
`unknown-key`, `repeated-key`, `missing-value`, `body-and-form`,
`multipart-beside-body`, `body-not-allowed`, `not-a-body`,
`not-name-value-pairs`, `not-a-redirect-count`, `not-a-boolean`,
`not-a-retry-policy`, `not-an-attempt-count`, `not-a-backoff`,
`not-a-status-list`, `not-a-method-list`, `not-a-limit`, `stream-in-group`
and `body-length-mismatch`. Each names the field and the value refused.

**`&curl-request-error`,** a request's field refused, as you make it, check
it or submit it. Each topic's page says when:

| Reasons | Page |
|---|---|
| `unknown-key`, `repeated-key`, `missing-value`, `body-not-allowed` | [The low level](low-level.md) |
| `embedded-nul`, `line-break`, `not-latin-1`, `not-a-token`, `surrounding-whitespace`, `duplicates-field`, `framing-header`: a header or a user agent | below |
| `part-bytes`, `part-empty`, `multipart-empty`, `multipart-content-type`, `part-file`, `multipart-unsupported` | [The high level](high-level.md#multipart) |
| `stream-with-rounds`, `body-length-without-stream`, `body-length-mismatch` | [Streams](streams.md) |
| `prior-knowledge-over-https`, `prior-knowledge-through-proxy` | [The HTTP version](http-version.md) |
| `credentials-bytes`, `credentials-empty`, `credentials-beside-userinfo`, `credentials-beside-authorization`, `digest-with-stream`, `proxy-url`, `proxy-scheme`, `proxy-url-parts`, `proxy-authorization-header`, `proxy-tls-without-https-proxy`, `proxy-tls-in-tls`, `https-proxy-unsupported` | [Auth and proxies](auth-and-proxies.md) |
| `cookie-line`, `cookie-jar-engine`, `cookie-jar-closed`, `cookie-beside-jar` | [Cookies](cookies.md) |
| `pkcs11-url`, `environment-override`, `keychain-fallback` | [TLS and the environment](tls-and-environment.md) |
| `owned-option`, `unsupported-type`, `unknown-option`, `repeated-option` | [The hatch](hatch.md) |

**A header** is a `(NAME . VALUE)` pair of Latin-1 strings. Refused: a NUL,
`embedded-nul`; a CR or LF, `line-break`; a char above U+00FF, `not-latin-1`;
a name that is empty or no HTTP token, `not-a-token`; a value that starts or
ends with a space, a tab, VT or FF, `surrounding-whitespace`; a `User-Agent` header
beside `user-agent`, or a second `Host`, `duplicates-field`; and a
`Content-Length` or `Transfer-Encoding`, which libcurl writes,
`framing-header`.
