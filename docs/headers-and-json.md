# Headers and JSON

A header is a `(NAME . VALUE)` pair of strings. This page says how to send
them, what is refused, how to read a response's, and then how to call a JSON
API.

## Setting headers

`headers` is a list of `(NAME . VALUE)` strings. A session's go with every
call it makes; a call's go with that call; the low level's
`make-curl-request` takes the same key, for that request alone.

```scheme fragment
(call-with-http-session 'headers '(("Accept" . "application/json"))
  (lambda (session)
    (http-get session "https://example.com/items" 'headers '(("X-Request-Id" . "42")))))
```

- **A call's header replaces every session header of its name,** in any A to
  Z case. The session's others go first, in their order, then the call's.
  Two keys alone drop a session's header from a call: `user-agent`, below,
  drops its `User-Agent`, and `multipart` its `Content-Type`. Any other a
  call can send empty.
- **Two headers of one name** are both sent, in order. A second `Host` is
  refused.
- **`user-agent`** is a key of its own, which sets libcurl's `User-Agent`. A
  `User-Agent` header beside it, in one request, is refused. A call's
  `User-Agent` header replaces a session's `user-agent`. A call's
  `user-agent` replaces a session's, and drops a session's `User-Agent`
  header, so a call's `user-agent` of `#f` sends none.
- **libcurl adds `Host` and `Accept: */*`** to every request, `Host` as
  `:authority` over HTTP/2, and frames a body: its `Content-Length`, or for
  a [stream](streams.md) with no `body-length`, `Transfer-Encoding: chunked`
  over HTTP/1.1. It sends no `User-Agent` unless you give one. A header you
  name replaces libcurl's of that name: your `Host`, your `Accept`.
- **A body has no `Content-Type` unless you name one.** chez-curl takes away
  the form type libcurl would add. A `form` sends
  `application/x-www-form-urlencoded` unless your headers, a session's among
  them, name a `Content-Type`, and `multipart` writes its own. A session's
  `Content-Type` goes with every call, a `GET`'s and a form's too.
- **An empty value is sent empty:** `("Accept" . "")` sends `Accept:` with
  nothing after it, and libcurl's `*/*` goes.
- **A header libcurl adds cannot be dropped:** name it to replace it, or
  send it empty. But libcurl's framing, `Content-Length` and
  `Transfer-Encoding`, cannot be named at all (`framing-header`, below).
  chez-curl takes away two itself: a body's form type, and the
  `Expect: 100-continue` libcurl adds to a body past 1 MiB
  ([The high level](high-level.md#bodies-forms-and-params)).
- **A redirect keeps your headers,** but for two cases. To another origin it
  drops `Authorization`, `Cookie` and, when the host changes, `Host`. And a
  redirect that sends the next request as a `get` with no body, a 303 of any
  method but `head`, or a 301 or 302 of a `post`, drops the body's headers
  with it: `Content-*`, a JSON `Content-Type` among them, `Digest`,
  `Last-Modified` and `Expect`
  ([Redirects and retries](redirects-and-retries.md#redirects)).

## What is refused

A header is checked as you make the request, or the session or the call,
before anything is sent. A refusal raises `&curl-request-error`
([Errors](errors.md)): its `curl-request-error-field` is `header-name`,
`header-value` or `user-agent`, and for a header its
`curl-request-error-value` is the header's name, never its value, which can
be a secret.

| Reason | What |
|---|---|
| `not-a-token` | a name that is empty, or holds a char no HTTP token holds: a space, a `:`, a char past ASCII |
| `embedded-nul` | a value holding U+0000, where C would end it |
| `line-break` | a value holding CR or LF, which would end its line |
| `not-latin-1` | a value holding a char above U+00FF, which has no byte |
| `surrounding-whitespace` | a value that starts or ends with a space, a tab, VT or FF, which libcurl would trim; one inside is the value's |
| `duplicates-field` | a `User-Agent` header beside `user-agent`, or a second `Host` |
| `framing-header` | a `Content-Length` or `Transfer-Encoding`: libcurl frames the body itself |
| `proxy-authorization-header` | a `Proxy-Authorization`: a proxy's credentials go in its URL ([Auth and proxies](auth-and-proxies.md)) |

A name is matched in any case. `user-agent` takes the value rules, and is a
non-empty string or `#f`: anything else, `""` among it, is an assertion
violation, and so are headers that are no list of string pairs. Other keys
refuse a header beside them: `credentials` an `Authorization`, a cookie jar a
`Cookie` or a `Host`, `multipart` a call's `Content-Type`, and
`stream-buffer`, a streamed response's, an `Expect` that holds
`100-continue` ([Errors](errors.md) lists each). Every high-level stream
sets `stream-buffer`: `call-with-response-port`'s, and a call whose body is a
producer. The low level's `body 'stream` with no `stream-buffer` takes such
an `Expect`.

## Reading response headers

- **`http-response-headers`** is every header of the response, as
  `(NAME . VALUE)` strings, in libcurl's order. A redirect's are its own, in
  `http-response-history`.
- **`http-response-header RESPONSE NAME`** is the first header of that name,
  in any A to Z case, or `#f`. For a name that comes more than once, such as
  `Set-Cookie`, read the list.
- **Each name and value is Latin-1:** one char per byte, so no byte is lost.
  A value the server wrote in UTF-8 comes as one char per byte; to read it
  as UTF-8:

  ```scheme fragment
  (utf8->string (string->bytevector value (make-transcoder (latin-1-codec))))
  ```

- **Every transfer caps its response headers** at 1,000 lines or 102,400
  bytes, else it raises `&curl-too-large`, reason `header-limit`
  ([The high level](high-level.md#timeouts-and-limits)).
- At the low level, `curl-response-headers` is the same list. On libcurl
  8.5.0 an empty value comes as a lone CR
  ([What varies by libcurl](libcurl-versions.md#responses-and-requests)).

## A JSON API

**chez-curl has no JSON of its own.** A body is bytes, and what they hold is
yours. To send and read JSON, use a JSON library: the example uses
[jsonparse](https://github.com/Kiyomi-Computation-Systems/jsonparse), an
R6RS one, through `(jsonparse easy)`.

**Getting jsonparse:** it is a submodule of this repository, for the example
alone, with byte-machine, which its parser imports, a submodule of its own.
Fetch both once, on a clone, and link them into `build/scheme-libs`; then
run the example against the test server ([the examples](README.md#the-examples)):

```sh
git submodule update --init --recursive
make deps
scheme --libdirs src:build/scheme-libs --program examples/json-api.sps http://127.0.0.1:PORT
```

In a program of your own, put jsonparse's `src` and byte-machine's on the
library path, beside chez-curl's: here, `vendor/jsonparse/src` and
`vendor/jsonparse/vendor/byte-machine/src`, whose libraries `make deps`
links into `build/scheme-libs`.

The test server's `/json` stands in for an API that insists on its headers:
a 406 unless `Accept` names `application/json`, and for a body a 415 unless
its `Content-Type` does. A session's `Accept` goes with every call; the
`POST` adds its `Content-Type`, and sends the bytes `json->bytevector` writes:

```scheme example=examples/json-api.sps
;; Every call of this session sends its Accept.
(call-with-http-session 'headers '(("Accept" . "application/json")) 'timeout-ms 10000
  (lambda (session)
    (define url (string-append base "/json"))
    ;; A GET: the API answers what it got.
    (let ((got (json-answer (http-get session url) 200)))
      (show (list (json-ref got "method") (json-ref got "accept"))))
    ;; A POST adds its Content-Type, and sends JSON's bytes.
    (let ((got (json-answer
                (http-post session url
                           'headers '(("Content-Type" . "application/json"))
                           'body (json->bytevector '(("name" . "Ada") ("langs" . #("Scheme" "C")))))
                201)))
      (show (list (json-ref got "bytes") (json-ref got "json" "name") (json-ref got "json" "langs" 1))))
    ;; A call's header replaces the session's of its name: this API says 406.
    (let ((got (json-answer (http-get session url 'headers '(("Accept" . "text/html"))) 406)))
      (show (list (json-ref got "error") (json-ref got "accept"))))
    ;; A body that is no JSON raises &json-error, its reason and byte offset.
    (show (guard (e ((json-error? e) (list (json-error-reason e) (json-error-offset e))))
            (bytevector->json (http-response-body (http-get session (string-append base "/status/200"))))))))
```

Each answer is checked by its status and its `Content-Type`'s media type,
its parameters left aside, then decoded:

```scheme example=examples/json-api.sps
;; media-type : String -> String
;; A Content-Type's type and subtype: its text before any ;, which begins
;; its parameters, such as charset, with no space or tab at either end, and
;; A to Z as a to z.
(define (media-type value)
  (define (before-semicolon cs)
    (if (or (null? cs) (char=? (car cs) #\;)) '() (cons (car cs) (before-semicolon (cdr cs)))))
  (define (drop-blanks cs)
    (if (and (pair? cs) (memv (car cs) '(#\space #\tab))) (drop-blanks (cdr cs)) cs))
  (list->string
   (map (lambda (c) (if (char<=? #\A c #\Z) (integer->char (+ (char->integer c) 32)) c))
        (reverse (drop-blanks (reverse (drop-blanks (before-semicolon (string->list value)))))))))

;; json-answer : Response Integer -> Any
;; The response's body, decoded from its bytes, once its status is STATUS
;; and its Content-Type's media type application/json; else an error.
(define (json-answer response status)
  (let ((type (http-response-header response "Content-Type")))
    (unless (and (= (http-response-status response) status)
                 type (string=? (media-type type) "application/json"))
      (error 'json-answer "not the JSON answer expected" (http-response-status response) type))
    (bytevector->json (http-response-body response))))
```

```text output=examples/expected/json-api.out
("GET" "application/json")
(37 "Ada" "C")
("not-acceptable" "text/html")
(unexpected-byte 0)
```

- **Decode the body's bytes,** `http-response-body` with `bytevector->json`,
  not `http-response-text` with `string->json`. The text puts U+FFFD in place
  of a malformed sequence and drops a leading byte-order mark, so a broken
  body reads as a whole one. `bytevector->json` refuses both, at the byte.
- **A body that is no JSON raises `&json-error`:** `json-error-reason`, such
  as `unexpected-byte`, `invalid-utf8` or `unexpected-eof`, and
  `json-error-offset`, its byte. The last line above is `/status/200`'s
  body, `status 200`, which is no JSON from its first byte.
- **Check the status and the type first.** A 404 or a proxy's error page can
  be HTML.
- **Name `Content-Type` on the call that sends the body.** A session's
  headers go with every call, a `GET` among them.
