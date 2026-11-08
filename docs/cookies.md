# Cookies

A cookie jar keeps the cookies servers set, and sends them back where they
belong. Nothing keeps cookies unless you ask: no request sends or stores one
without a jar.

## At the high level

A session made with `cookies #t` keeps a jar on its engine. Every call of the
session carries it, and every request a redirect makes, to another origin
too: libcurl matches cookies to hosts. The session's close frees it.

```scheme fragment
(call-with-http-session 'cookies #t
  (lambda (session)
    (http-get session "https://example.com/login")
    (http-session-cookies session)))     ; its cookies, as lines
```

- `http-session-cookies` reads the jar out, and `http-session-load-cookies!`
  loads lines into it, as the low level's read-out and load do (below).
- A call takes no `cookies` key: the jar is the session's.
- A `Cookie` or `Host` header, the session's or a call's, is refused beside it,
  `cookie-beside-jar`.
- On a session made without cookies, both procedures are an assertion
  violation.

## At the low level

A jar is an engine's. Give it to each request whose cookies it should keep:

```scheme example=examples/cookie-jar.sps
(define engine (make-curl-engine))
(define jar (make-curl-cookie-jar engine))

;; fetch : String -> Response
(define (fetch path)
  (curl-token-await
   (curl-submit engine (make-curl-request (string-append base path)
                                          'cookie-jar jar 'timeout-ms 10000))))
```

Read it out, load lines into it, and close it:

```scheme example=examples/cookie-jar.sps
;; A load takes lines in the form a read-out gives them.
(curl-cookie-jar-load! jar '("127.0.0.1\tFALSE\t/\tFALSE\t0\tsize\tlarge"))
(for-each (lambda (line) (write line) (newline))
          (list-sort string<? (curl-cookie-jar-cookies jar)))

(curl-cookie-jar-close! jar)
(curl-engine-stop engine)
```

- **The rules are libcurl's:** which cookies are kept, and which go to which
  host and path. They [vary by version](libcurl-versions.md#cookies).
- **A jar holds cookies alone,** in memory: no file, and no HSTS entry.
- **A line is a Netscape line,** `DOMAIN TAILMATCH PATH SECURE EXPIRY NAME
  VALUE`, tab-separated, `#HttpOnly_` before an HttpOnly cookie's domain. It
  is a Latin-1 string both ways: each byte one char. Their order moves:
  compare them sorted.
- **A close frees the jar** once no transfer holds it, and an engine's stop
  frees every jar. A second close does nothing.
- **Each jar procedure waits for the engine,** with no bound, as a stop does,
  and none may run inside a critical section. A stopped or failed engine's
  jar raises as a submit to it would.
- **A load is slow for many lines,** about n², and runs on the engine's
  thread, so its other transfers wait for it.
- **A libcurl that refuses** a jar's make, read-out or load raises Chez's
  `&error`, no chez-curl condition.

## What a load takes

A load takes a line in the form a read-out writes it, and checks every line
before it loads any. A line needs:

- seven fields, none holding a control char, U+0000 to U+001F or U+007F;
- `TRUE` or `FALSE` in the second and the fourth, the domain starting with a
  dot exactly beside `TRUE` in the second;
- a domain, after any `#HttpOnly_`, neither empty nor starting with `#`, and
  no `Set-Cookie:` line;
- a path starting with `/`;
- an expiry of decimal digits, at most 9223372036854775807;
- a name; no `;` in the name or the value, and no `=` in the name;
- a name and value of 4,096 bytes at most together;
- a name starting `__Secure-` or `__Host-`, in any case, only beside `TRUE` in
  the fourth, and for `__Host-` the path `/` and `FALSE` in the second;
- no char above U+00FF.

Any other is refused, `cookie-line`, naming the line's index, from 0, never
its text: a cookie's value is a secret. Nothing is loaded then.

A read-out can give lines a load refuses, by version: see
[What varies by libcurl](libcurl-versions.md#cookies).

## Refusals

- **When you make the request:** a `Cookie` or `Host` header beside a jar, in
  any case, any value, `cookie-beside-jar`: libcurl would send a second
  `Cookie`, or match the jar against your `Host`.
- **When you submit:** another engine's jar, `cookie-jar-engine`, and a closed
  one, `cookie-jar-closed`. A close that crosses a submit fails its token so.
- **A long head on 7.85.0** can leave a request unended until its timeout:
  its cap on the `Cookie` line counts all the head written before it, the
  request line, `Host`, `Authorization` and `User-Agent` among it. Pass a
  `timeout-ms` ([What varies](libcurl-versions.md#cookies)).

## The hatch

`(curl unsupported)` refuses the options a jar sets, and those that would
reach into it: [The hatch](hatch.md) lists them, and the few it leaves.
