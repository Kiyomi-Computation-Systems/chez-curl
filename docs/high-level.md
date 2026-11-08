# The high level: `(http-client)`

A session holds one engine, and the defaults its calls share. A call takes
its session first, blocks its thread until the response, and answers it
whatever the status: a status is data.

```scheme example=examples/quick-start.sps
(call-with-http-session
 (lambda (session)
   (let ((response (http-get session (string-append base "/status/200"))))
     (display (http-response-status response))
     (newline)
     (display (http-response-text response)))))
```

## Sessions

- **`call-with-http-session KEY VALUE ... PROC`** makes a session, calls PROC
  with it, and closes it when PROC returns or escapes.
- **`make-http-session KEY VALUE ...`** makes one that lives until
  `http-session-close`. The close stops its engine: each call in flight ends
  as stopped, and a later call raises `&curl-engine-error`. It does not wait
  for calls to finish. A second close returns.
- **There is no default session,** and nothing starts a thread you did not ask
  for: the session's engine is its one thread. Threads may share a session.
- **Its keys are checked before its engine is made,** so a refusal leaves none.
- **A second Ctrl-C, or a timer, that interrupts the close itself** can leave
  the engine running until the process exits. chez-curl does not prevent
  this.

A session takes the low level's keys, each a default for its calls:
`headers`, `user-agent`, `timeout-ms`, `connect-timeout-ms`, `body-limit`,
`ca-file`, `verify`, `proxy`, `proxy-ca-file`, `proxy-verify`, `http-version`
and `credentials` ([Reference](reference.md) has each), and four of its own:

| Key | What | Default |
|---|---|---|
| `redirects` | the most redirects a call follows; `#f` follows none | 20 |
| `allow-downgrade` | follow a redirect from `https` to `http` | `#f` |
| `retry` | a policy from `make-http-retry`, or `#f` | `#f` |
| `cookies` | keep a cookie jar ([Cookies](cookies.md)) | `#f` |

A call's value replaces its session's. A call's header replaces every session
header of its name, in any case; a call's `User-Agent` header sets no
`user-agent`, and a call's `user-agent` drops the session's `User-Agent`
header ([Headers and JSON](headers-and-json.md)).
[Redirects and retries](redirects-and-retries.md) has the first three.

## Verbs and responses

`(http-request SESSION METHOD URL KEY VALUE ...)` makes a call: METHOD one of
`get`, `head`, `post`, `put`, `patch` and `delete`, URL an `http://` or
`https://` URL. `http-get`, `http-head`, `http-post`, `http-put`, `http-patch`
and `http-delete` name the method for you.

A response holds:

- `http-response-status`, an integer, and `http-response-http-version`;
- `http-response-url`, the URL its transfer asked for: the call's, its params
  appended, or a redirect's;
- `http-response-headers`, a list of `(NAME . VALUE)` Latin-1 strings, and
  `http-response-header`, the first of a name, in any case, or `#f`;
- `http-response-body`, a bytevector, and `http-response-text`, the body as
  UTF-8: U+FFFD for a malformed sequence, a leading byte-order mark dropped,
  no charset read;
- `http-response-timings`, each phase's microseconds from the start;
- `http-response-history`, the redirects it followed, oldest first.

## Bodies, forms and params

- **`body`** is a bytevector, sent as it is; a string, sent as UTF-8, with no
  `Content-Type` of its own; or a producer, which [streams](streams.md).
- **`form`** is a list of `(NAME . VALUE)` strings, sent as the body,
  encoded as `application/x-www-form-urlencoded`, with that `Content-Type`
  unless your headers name one.
- **`params`** is a list of the same, encoded the same way and appended to
  the URL's query.
- **No body waits for a 100.** libcurl adds `Expect: 100-continue` to a body
  past 1 MiB, and chez-curl takes it away; an `Expect` header of yours is
  sent instead.

```scheme example=examples/form-and-params.sps
    ;; params are encoded and appended to the URL's query.
    (let ((echo (lines (http-response-text
                        (http-get session (string-append base "/echo")
                                  'params '(("q" . "chez scheme") ("page" . "2")))))))
      (display (car echo))
      (newline))
    ;; form is sent as application/x-www-form-urlencoded.
    (let ((echo (lines (http-response-text
                        (http-post session (string-append base "/echo")
                                   'form '(("name" . "Ada Lovelace") ("lang" . "Scheme")))))))
```

```text output=examples/expected/form-and-params.out
GET /echo?q=chez+scheme&page=2 HTTP/1.1
POST /echo HTTP/1.1
Content-Type: application/x-www-form-urlencoded
name=Ada+Lovelace&lang=Scheme
```

A `get` or `head` refuses a `body`, a `form` and a `multipart` body,
`body-not-allowed`, and `body` and `form` together are refused,
`body-and-form`.

## Multipart

`multipart` sends a `multipart/form-data` body, a list of parts. libcurl
frames it, and writes its `Content-Type` and boundary.

```scheme example=examples/multipart.sps
           (http-post session (string-append base "/parts?key=example-multipart")
                      'multipart
                      '(("title" "Holiday")
                        ("notes" #vu8(104 105) filename "notes.txt")
                        ("doc" (file "examples/data/hello.txt"))
                        ("blob" #vu8(1 2 3) type "application/x-thing")))))
```

- **A part is `(NAME SOURCE OPTION ...)`:** SOURCE a string, sent as UTF-8, a
  bytevector, or `(file PATH)`; each OPTION `filename STRING` or
  `type STRING`, at most once. A file part's filename is its path's last
  component unless you give one.
- **Its strings are checked:** a name, filename or type holding a control
  char, U+0000 to U+001F or U+007F, or a name or filename holding `"`, is
  refused, `part-bytes`; an empty one, `part-empty`; no part at all,
  `multipart-empty`. A refusal names the part, `(part 2 filename)`, never the
  string.
- **A part's type** is the `type` you give. Else libcurl picks one by the
  filename's last extension, in any case: `.gif`, `.jpg`, `.jpeg`, `.png`,
  `.svg`, `.txt`, `.htm`, `.html`, `.pdf` and `.xml` alone. A file part with
  none of those takes its path's, else `application/octet-stream`; a data
  part gets no `Content-Type`. Alike on every libcurl.
- **A `Content-Type` header beside it** is refused, `multipart-content-type`;
  a session's is dropped. Beside `body` or `form` it is refused,
  `multipart-beside-body`, and `get` and `head` refuse it.
- **It is a whole body,** sent once per request: a retry resends it, a 307
  or 308 keeps it, a 303 drops it, and a group takes one.

**Files.** A relative path is resolved against the current directory once,
as the call starts. A data part's bytes are copied then, so a retry or a
redirect sends what the call began with. A file part is read again by each
transfer, so a retry or a redirect sends what the file holds by then. Each
path must name a regular file, symbolic links followed, as the call starts,
at each submit, and as the engine starts the transfer, else `part-file`.
libcurl reads the file as the body goes, so:

- **A file that changes after that check is yours.** What libcurl then sends,
  grown, shrunk or removed, [varies by libcurl](libcurl-versions.md#multipart).
- **A file whose size is not its content,** in `/proc` or `/sys`, was seen
  to send what a shrunk one sends; no test holds it.
- **A path swapped for a FIFO after the check** holds the engine's thread
  until a writer comes, perhaps for ever: every transfer on that engine
  stalls, and its stop, a session's close among them, never returns.

The checks narrow that window, and cannot close it. If you cannot trust the
file system, read the file yourself and send its bytes as a bytevector part.

A libcurl built without multipart support refuses it when you submit,
`multipart-unsupported`. The low level takes the same parts as a request's
body. Its relative paths are resolved as the request is made, a data part's
bytes are copied at each submit, and a file part is read by each transfer:

```scheme fragment
(make-curl-request url 'method 'post
                   'body '(multipart ("title" "Holiday") ("doc" (file "/tmp/a.txt"))))
```

## Timeouts and limits

- **`timeout-ms` bounds the whole call,** from its start: each transfer, a
  redirect's and a retry's among them, gets the time left. At the bound the
  call raises `&http-timeout`, with `(curl)`'s `&curl-timeout`. `#f`, the
  default, is no bound.
- **`connect-timeout-ms`** bounds each connection, its TLS handshake among it.
- **`body-limit`** bounds the response body's bytes: past it the call raises
  `&curl-too-large` ([Errors](errors.md)).
- **Every transfer caps its response headers** at 1,000 lines or 102,400
  bytes, counted over the whole transfer: every head, a 1xx, a proxy's
  `CONNECT` answer and each auth round's among them, and the trailers. Past
  either it raises `&curl-too-large`, reason `header-limit`. No key sets the
  cap.

**A call's checks pause Ctrl-C and garbage collection.** While a call checks
what you passed, a Ctrl-C waits, and so does every other thread's garbage
collection. For an ordinary call that is brief, but it grows with what you
pass: a large body, a long form, many headers or params,
a long URL. So bound what you take from untrusted input before you pass it.
A URL past libcurl's cap of 8,000,000 bytes is refused at once,
`malformed-input`.

**A call that is escaped cancels its transfer:** a Ctrl-C whose handler
escapes, a timer's, a continuation, or a Chez engine's expiry. A call made
inside a critical section is refused before it sends anything: its wait
could not end there.
