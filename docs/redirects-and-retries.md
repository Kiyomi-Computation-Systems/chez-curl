# Redirects and retries

`(http-client)` follows redirects by its own rules, not libcurl's, and
retries only by a policy you give. Each request a redirect or a retry makes
is a transfer of its own.

The examples on this page call the test server: start it first, with
`node tests/origin.mjs`, and give an example the address after `"http":` in
the line it prints, not `raw`'s or `h2c`'s ([The examples](README.md#the-examples)).

```scheme example=examples/session-retries.sps
(call-with-http-session 'timeout-ms 10000
                        'retry (make-http-retry 'attempts 3 'backoff-ms 10 'statuses '(503))
  (lambda (session)
    ;; A redirect is followed; the 302 joins the response's history.
    (let ((response (http-get session (string-append base "/redirect/302?to=/status/200"))))
      (show (http-response-status response) " "
            (map http-response-status (http-response-history response))))
    ;; The server answers this URL 503 twice, then 200.
    (let ((url (string-append base "/parts?key=" (unseen-key session "example-retry-")
                              "&fail=2")))
      ;; A call's retry #f overrides the session's policy: the 503 is answered.
      (show (http-response-status (http-get session url 'retry #f)))
      ;; With the policy, the second 503 is retried, and the 200 after it is
      ;; answered. A retried response joins no history.
      (let ((response (http-get session url)))
        (show (http-response-status response) " " (http-response-history response))))))
```

```text output=examples/expected/session-retries.out
200 (302)
503
200 ()
```

The test server's `/parts?key=K&fail=2` answers 503 to K's first two
requests, and counts each key for as long as it runs: `unseen-key` picks one
it has never counted, so every run of the example prints the same.

## Redirects

A call follows a 301, 302, 303, 307 or 308 whose first `Location` is neither
empty nor blank, up to `redirects` times: 20, unless the session or the call
says otherwise. `#f` follows none, and answers the redirect. Each response it
followed joins the history, oldest first.

- **The `Location` is resolved** against the URL the transfer asked for. One
  that is `#` and a fragment keeps that URL with the new fragment; one with no
  `#` keeps that URL's own fragment.
- **To another origin,** another scheme, host or port, the call drops
  `Authorization`, `Cookie` and its `credentials`, and `Host` when the host
  changes. A header dropped stays dropped, even back on the first origin.
  **Every other header follows,** so an `X-Api-Key` reaches the new origin
  too. No request holds a `Proxy-Authorization` header: it is refused when
  you make one.
- **A `user:pass@` in the URL** stays for a `Location` that is a path or a
  query. One that names a host, `//host/p` or a whole URL, carries its own, or
  none.
- **From `https` to `http` is refused,** unless `allow-downgrade` is `#t`.
- **A 303 makes a `get` of anything but a `head`,** and so do a 301 and a 302
  of a `post`. The body goes, and with it your `Content-` headers, `Digest`,
  `Last-Modified` and `Expect`.
- **Every other key follows:** the HTTP version, the proxy and its
  credentials, and a session's cookie jar, to another origin too. So the
  next request can be refused as any request would be:
  `prior-knowledge-over-https` for an `https://` one by prior knowledge,
  `credentials-beside-userinfo` for one within the origin to a URL holding a
  user, `proxy-tls-in-tls`.
- **A producer's body is never sent twice.** Once libcurl has asked for it, a
  307 or 308, or a 301 or 302 of anything but a `post`, raises
  `body-not-replayable` ([Streams](streams.md)).

A redirect the rules do not follow raises `&http-redirect-error`:
`too-many-redirects`, `bad-location` (a `Location` that is no URL, or names
a scheme but `http` or `https`), `insecure-redirect` or
`body-not-replayable`. `http-redirect-error-response` holds the response,
and `http-redirect-error-location` its `Location`. Which `Location` is no URL
[varies by libcurl](libcurl-versions.md#redirects-and-retries): 7.85.0
follows `javascript:alert(1)` as a relative path, where later ones refuse
it, `bad-location`. Two `Location` headers vary too: 7.85.0, 8.5.0 and 8.7.1
follow the first, and 8.20.0 and 8.23.0 fail the transfer, 8.

## Retries

Nothing is retried unless the session or the call names a policy, made by
`make-http-retry`. A call's `retry #f` turns its session's off.

| Key | What | Default |
|---|---|---|
| `attempts` | transfers per step, the first among them | 3 |
| `backoff-ms` | the first retry's wait, doubling for each later one | 200 |
| `max-backoff-ms` | the longest wait, a `Retry-After`'s too | 10000 |
| `jitter` | `#t` waits a random share of the backoff; `#f` the backoff itself | `#t` |
| `statuses` | the statuses retried, 400 to 599 | `(429 503)` |
| `methods` | the methods a status, or a failure after a request was sent, is retried for | `(get head put delete)` |

- **A step is one URL.** It makes the policy's attempts at most, and a
  redirect starts the count again.
- **A status is retried** when the policy's `statuses` hold it and its
  `methods` the call's. A proxy that refused a `CONNECT` with a status counts
  as a response with that status.
- **A failure is retried** when it is a connect, send-receive or timeout
  failure, but the call's own bound: for any method when nothing was sent,
  and otherwise only for one of `methods`. On libcurl 8.7.0 and 8.7.1 a
  transfer's size is unknown, so one that ran counts as sent: a `post` there
  is not retried after a refused connect.
- **The wait** is the backoff, capped, a random share with `jitter`; or a
  retried status's `Retry-After`, seconds or a date. A wait longer than
  `max-backoff-ms`, or than the time the call has left, makes no retry.
- **A retried response joins no history.** `http-exchange-transfers`, on what
  a call raises, counts every transfer.
- **A retry that runs out of time** having sent nothing answers the last
  response it retried, or raises the last failure; one whose request may have
  gone out raises `&http-timeout`.
- **A producer's body** is never retried once libcurl has asked for it. A
  refused connect, before any ask, is still retried.

**libcurl resends on its own,** with no policy: a request on a reused
connection that died before any response byte, and an HTTP/2 stream the
server refused with `REFUSED_STREAM`, up to five times more, a `post`'s
among them. A policy's attempts multiply them: a `get` retried 3 times can
reach such a server 18 times.
