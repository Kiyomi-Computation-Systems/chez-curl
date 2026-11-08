# What varies by libcurl

chez-curl hands most of a transfer to libcurl, so some of what a caller meets
depends on which libcurl is loaded. This page lists each such behaviour, by
topic. Everything here was measured on these libcurls, the ones the suites
run:

| Column | The libcurl |
|---|---|
| 7.85.0 | curl 7.85.0 built from source with OpenSSL |
| 8.5.0 | Ubuntu 24.04's 8.5.0, with OpenSSL and with GnuTLS, alike unless a cell says |
| 8.7.1 | Apple's 8.7.1, on macOS, with `CURL_SSL_BACKEND=secure-transport`, which `make test` sets there |
| 8.20.0 | Guix's 8.20.0, with GnuTLS |
| 8.23.0 | curl 8.23.0 built from source with OpenSSL |

A number in a cell is libcurl's code: the transfer fails with
`&curl-transfer-error`, reason `perform-failed`, of the class
[Errors](errors.md) gives that code. "Alike" means every libcurl answered the
same. A cell with two answers raced: either can come.

The tables are held by the suites, by version. Each section then lists what
was seen and no test holds by version, and where libcurls differ but
chez-curl answers alike on every one, which no test holds by version either:
the tests hold chez-curl's answer.

## Multipart

A file part is read as the body goes, after the engine's last check. A file
changed after that check:

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| grown, HTTP/1.1 | the extra bytes sent past `Content-Length`: the server's answer | as 7.85.0 | 200, the body never closed | as 8.7.1 | as 8.7.1 |
| grown, HTTP/2 | 92 | the server's answer: 92 or 56 | 200, never closed | as 8.7.1 | as 8.7.1 |
| shrunk, HTTP/1.1 | waits until `timeout-ms`, 28, or for ever with none | as 7.85.0 | 26, at once | as 8.7.1 | as 8.7.1 |
| shrunk, HTTP/2 | 92, at once | as 7.85.0 | 26 | 26 | 26 |
| removed | 26, alike | | | | |
| swapped for a FIFO | held until a writer comes, then 200: alike | | | | |

- **A resend,** on a kept connection that died or an HTTP/2 stream refused at
  its head, sends the whole body again, alike.
- **A connection reset** as a 4 MiB file part's request arrives is resent, or
  fails 55, by a race, alike.
- **The request size** of a failed multipart transfer counts the head alone on
  7.85.0 and 8.5.0, the head and the body sent on 8.20.0 and 8.23.0, and is
  `#f` on 8.7.1.
- **The default part types** are alike on every libcurl: see
  [The high level](high-level.md#multipart).

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- A file part's path libcurl refuses, 26, is still sent, as an empty field on
  8.20.0 and 8.23.0: chez-curl fails the transfer, `part-file`, on any answer
  but 0.
- libcurl's escaping option sends CR and LF raw in a part's name on 7.85.0,
  8.5.0, 8.7.1 and 8.20.0: chez-curl owns it, never sets it, and refuses those
  bytes.

## Redirects and retries

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| a 302 to `javascript:alert(1)` | followed, as a relative path | `bad-location`, URL error 5 | as 8.5.0 | as 8.5.0 | as 8.5.0 |
| a 302 to `http://[::1/x` | `bad-location`, URL error 4 | `bad-location`, URL error 22 | as 8.5.0 | as 8.5.0 | as 8.5.0 |
| two `Location` headers | the first followed | as 7.85.0 | as 7.85.0 | 8 | 8 |
| a `post` to a refused port, retried | 3 transfers | 3 | 1: its size is unknown, so counted as sent | 3 | 3 |
| a retry that runs out of time having sent nothing | the last failure, 28, no `&http-timeout` | as 7.85.0 | `&http-timeout` | as 7.85.0 | as 7.85.0 |
| a proxy that closes a `CONNECT`, a `post` outside the policy's methods | tried once: the size counts the `CONNECT` | 3 times | once | 3 | 3 |
| the same, a `get` in the methods | 3 times, alike | | | | |

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- A `Location` of `#` and a fragment drops the last segment and the query on
  7.85.0, 8.5.0 and 8.7.1: the high level sets the fragment itself.
- 7.85.0 follows inside one transfer without bound, a 417 or a stale Digest
  challenge for ever: chez-curl pins the bound at 30 on every libcurl.

## Auth

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| Digest MD5, MD5-sess, SHA-256, SHA-256-sess | 200, alike | | | | |
| Digest SHA-512-256 | 401: it sends SHA-256's answer | 401 | 200 | 200 | 200 |
| a Digest user `üser` | 200, sent raw | 200 | 200 | 200 | 401: sent percent-encoded, the raw bytes hashed |
| a URL `http://@h/` or `http://:@h/` beside credentials | taken: your credentials sent | refused, `credentials-beside-userinfo` | as 8.5.0 | as 8.5.0 | as 8.5.0 |
| a URL `:p@`, `u@` or `u:@` beside credentials | refused, alike | | | | |
| a 1 MiB Basic password or Bearer token | 27, nothing sent | 27 | 100 | 100 | 100 |

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- Credentials both `""`: 8.23.0 sends no header. chez-curl refuses them,
  `credentials-empty`.

## Proxies

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| a proxy URL `http://@p` or `http://:@p` | taken: no `Proxy-Authorization` | refused, `credentials-empty` | as 8.5.0 | as 8.5.0 | as 8.5.0 |
| `https://` through an `https://` proxy URL | refused, `proxy-tls-in-tls`, unless `http/1.1` | OpenSSL: runs; GnuTLS: refused, always | runs | runs | runs |
| a `CONNECT` refused, 403, 407, 502 or 503 | 56, the size the `CONNECT`'s bytes | 56, size 0 | 56, size `#f` | 7, size 0 | 7, size 0 |
| a proxy that closes a `CONNECT` | 56, no status, alike | | | | |
| two `https://` requests in turn through one proxy URL | each its own `CONNECT`; with credentials the first closes as it ends | as 7.85.0 | as 7.85.0 | the second rides the first's tunnel | as 8.20.0 |
| credentials in a proxy URL, two HTTP/2 streams live | the engine stops multiplexing, for good | as 7.85.0 | never multiplexes | nothing changes | as 8.20.0 |
| `https_proxy` set, beside a live tunnel opened with credentials | its own `CONNECT`, refused 407: 56 | as 7.85.0 | 56 | its own `CONNECT`, refused 407: 7 | as 8.20.0 |

`curl-transfer-error-connect-code` holds the proxy's status on every libcurl.

Seen, and no test holds it by version:

- A proxy variable whose user or password decodes to a control byte sends
  the transfer around the proxy, direct, on 7.85.0 and 8.5.0; 8.20.0 and
  8.23.0 fail it, 3.

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- A proxy URL with no port: libcurl tries 1080, and 8.23.0 80. chez-curl
  gives it its scheme's.
- `socks5://` parses on 8.23.0 alone: chez-curl refuses every scheme but
  `http` and `https`, `proxy-scheme`.
- An empty `@` sent `:` on 8.5.0 and 8.20.0, and nothing on 8.23.0: chez-curl
  refuses it there when you submit, `credentials-empty`. 7.85.0 reports no
  user for it, so it is taken there, as the table says.
- A user that decodes to a control byte went direct on 7.85.0 and 8.5.0:
  chez-curl refuses it on every libcurl when you submit, `credentials-bytes`.
- 7.85.0 let a request ride a tunnel another user's credentials opened
  (CVE-2026-3784): before 8.19.0 chez-curl shares no tunnel.

## Cookies

A read-out line marked "refused by a load" is one `curl-cookie-jar-load!`
refuses, `cookie-line`.

| What a server sets | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| `Path=`, `Path=TRUE`, `Path=FALSE`, `Path=rel` | listed as given, refused by a load; sent | as 7.85.0 | as 7.85.0 | listed with `/`; sent | as 8.20.0 |
| a tab in a name or a value | listed as eight fields, refused by a load; sent | dropped | dropped | dropped | dropped |
| a tab in `Path` | eight fields, refused by a load; not sent | dropped | dropped | dropped | dropped |
| `__secure-a`, `__SECURE-b`, `__host-c` with a path, `__HOST-d` with a domain, none `Secure` | listed, refused by a load; sent | dropped | dropped | as 7.85.0 | as 7.85.0 |
| a loaded line already expired | listed until a cookie is added | as 7.85.0 | as 7.85.0 | dropped at once | as 8.20.0 |
| a 4,003-byte cookie, then a URL past 4,200 bytes or a 4,300-byte `User-Agent` | the head never ends: 28 at `timeout-ms` | 200 | 200 | 200 | 200 |
| `Domain=localhost` set at `a.localhost` | kept, not sent there | dropped | as 7.85.0 | dropped | as 7.85.0 |
| `Domain=localhost` set at `localhost` | `.localhost`; sent | host-only; sent | as 7.85.0 | as 7.85.0 | as 7.85.0 |
| `__Host-dom; Secure; Path=/; Domain=localhost` at `localhost` | dropped | kept, host-only; sent | dropped | dropped | dropped |
| the default path, set at `/cookies/a/b/page` | `/cookies/a/b/` | as 7.85.0 | as 7.85.0 | `/cookies/a/b` | as 8.20.0 |
| `Max-Age` of 1,000 days | kept past 400 days | as 7.85.0 | as 7.85.0 | capped at 400 days | as 8.20.0 |
| `Max-Age=-1` | kept, a session cookie, sent | listed with expiry 1, not sent | as 8.5.0 | dropped | dropped |
| deleted by `Max-Age=0` | listed, expiry 1, until the next request | as 7.85.0 | as 7.85.0 | gone at once | as 8.20.0 |

What `Domain=localhost` does turns on the public suffix list a libcurl is
built with: 8.5.0 and 8.20.0 have one, the others do not.

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- A loaded line with a control byte, empty fields, a relative path, or a
  prefix in another case is stored, merged, kept or dropped by version: the
  load refuses each.
- A loaded cookie past the `Cookie` line's 8,190 bytes left the head open on
  every libcurl: the load caps a name and value at 4,096 bytes.
- A share holding HSTS carried an entry to the next transfer on 8.5.0 and
  later: a jar shares cookies alone.

## The HTTP version

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| `http/2-prior-knowledge` to an HTTP/1.1 server | 52 | 56 | 16 or 56 | 16 | 16 |
| two prior-knowledge requests in one batch | one connection | two | two | two | two |
| a request started once a live one's head is in | reuses its connection | reuses | opens its own | reuses | reuses |
| two transfers at once to one HTTP/2 origin | share a connection | share | each its own | share | share |

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- Prior knowledge over `https://`: 8.20.0 and 8.23.0 offer HTTP/2 alone, and
  an HTTP/1.1 server fails it, 35. chez-curl refuses it everywhere,
  `prior-knowledge-over-https`.

## Streams

At the high level:

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| a final HTTP/2 303, unfollowed, once 64 KiB of a 4 MiB body went | the 303 and its body | as 7.85.0 | as 7.85.0 | never ends: the call's bound, 28, `&http-timeout` | as 8.20.0 |

At the low level, an answer that comes while a streamed body is still being
put. "At once" ends the transfer as the answer comes; "at your put" ends it
only at your next put or end:

| The answer | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| HTTP/1.1 413, closing | at your put, 413 | at once, 413 | at once, 413 | at once, 413 | at once, 413 |
| HTTP/1.1 413, kept alive | at your put, 413 | at your put, 413 | at your put, 413 | at once, 413 | at once, 413 |
| HTTP/1.1 200, closing | at your put, 200 | at once, 200, the body cut | at once, 200, cut | at once, 200, cut | at once, 200, cut |
| HTTP/1.1 200, kept alive | at your put, 200, alike | | | | |
| HTTP/2 413 | at your put, 413 | at your put, 413 | at your put, 413 | at once, 413 | at once, 413 |
| HTTP/2 200 | at your put, then the timeout, 28 | at once, 200, cut | at your put, 200, or 55 | at your put, 200, or 55 | at your put, 200 |

Where it ends at your put, libcurl still asks for the rest of the body: a
producer is fed it.

Seen, and no test holds it by version:

- 8.5.0 over HTTP/2 can read nothing from a transfer paused for sending until
  the body resumes, rarely. A head wait then answers `#f` at its bound. Put or end the body first, or bound the wait and then put.
- 7.85.0: an early HTTP/2 200 while a whole bytevector body is still owed
  never ends.
- At the low level, an HTTP/2 3xx that comes before a body is sent whole
  never ends on 8.20.0 and 8.23.0, as the high level's row above.

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- 7.85.0 and 8.5.0 lose a refusal of a piece made while a paused transfer
  resumes, and 8.7.1 hands a refused piece again: the reason chez-curl
  recorded wins on every libcurl.
- Ubuntu's 8.5.0 spins the CPU while a transfer is paused, and 7.85.0 during a
  paused HTTP/2 upload: the engine paces its poll.
- On 8.7.1 one HTTP/2 stream's failure fails its neighbours, and a paused one
  fills libcurl's 64 MiB cap: on 8.7.0 and 8.7.1 the engine does not
  multiplex.
- An `Expect: 100-continue` anywhere in the value counts on 7.85.0 and 8.5.0,
  as a list element alone on 8.20.0 and 8.23.0: a stream refuses either.

## Engines and groups

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| a request right after 8 pooled connections the server closed unannounced | 200 | 200 | 200 | 200 | 55: "Connection died, tried 5 times before giving up" |
| a name lookup that stalls: a cancel, a transfer beside it, a 500 ms timeout | each waits for the lookup | prompt | not measured | prompt | prompt |

libcurl before 7.87.0 cannot leave a stalled lookup's thread behind, so there
a cancel, a timeout or a stop during one waits for it, up to the resolver's
own timeout.

Seen, and no test holds it by version:

- On 7.85.0 a stalled lookup holds a group's wait for its calls, as it holds
  the engine's cancel, up to glibc's resolver timeout.
- On 8.20.0 each stopped engine leaves two resolver threads running for about
  2 s.

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- Guix's 8.20.0 reads back a wake-up made before its perform, then waits up
  to 1 s: the engine looks at its queue first.

## Errors

The cap on response headers, and libcurl's own limits that can come first.
"hl" is reason `header-limit`, class `&curl-too-large`, with the code beside
it:

| The response | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| 1,001 header lines, HTTP/1.1 | hl 23 | hl 23 | hl 23 | hl 23 | hl 23 |
| the cap passed in an HTTP/2 head | hl 23 | hl 23 | hl 56 | hl 23 | hl 23 |
| the cap passed in HTTP/2 trailers | hl 23 | hl 0 | hl 23 | hl 23 | hl 23 |
| one header line of 102,400 bytes, HTTP/1.1, or of 1 MiB | 27 | 27 | 100 | 100 | 100 |
| that line over HTTP/2 | 27 | 27 | 56 | 16 | 56 |
| that line over HTTP/2, not Huffman-codable | 52 | 56 | 16 | 16 | 16 |
| an HTTP/2 head of 131,072 bytes | 56 | hl 23 | hl 56 | hl 23 | hl 23 |
| an HTTP/2 head of 307,199 bytes | 56 | 56 | hl 56 | hl 23 | hl 23 |
| HTTP/2 trailers past nghttp2's limit | 56 | 56 | 56 | 16 | 56 |
| a trailer line of 5,000 bytes, HTTP/1.1 | 56 | 56 | 100 | 100 | 100 |
| a trailer line of 5,000 bytes, HTTP/2 | 200, the trailers among the headers | 200 | 200 | 200 | 200 |
| 6,000 HTTP/2 trailers | hl 23 | hl 0 | hl 23 | hl 23 | 56 |

Other answers:

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| a status line `HTTP/1.1 2000 OK` | 1 | 1 | 1 | 200, the body kept | 200 |
| two different `Content-Length`s | 200, both headers kept | 200 | 200 | 8 | 8 |
| a NUL in a header: the error buffer | `Nul byte in header` | as 7.85.0 | as 7.85.0 | as 7.85.0 | `NUL byte in header` |
| the request size of a transfer that ran | its bytes, 0 if none | as 7.85.0 | `#f`, unknown, 8.7.0 too | as 7.85.0 | as 7.85.0 |

## Responses and requests

Seen, and no test holds it by version:

- On a reused connection 8.20.0 reported the name-lookup, connect and
  TLS-handshake timings as 0, and 7.85.0 a small connect time.
- 8.5.0 hands a response header's empty value over as a lone CR, in
  `curl-response-headers` too.
- Reading many headers costs about n² before 8.23.0. The cap's 1,000 lines
  bounds it.
- A request URL past about 131,000 chars waited until its timeout on 8.5.0;
  7.85.0, 8.20.0 and 8.23.0 sent ones of about a million.

## URLs

A refusal is `&curl-url-error`, its code and reason the URL API's: 3
`malformed-input`, 4 `bad-port-number`, 5 `unsupported-scheme`, 20
`bad-fragment`, 21 `bad-hostname`, 22 `bad-ipv6`, 25 `bad-path`, 26
`bad-query`, 28 `bad-slashes`. These are a direct call's answers; the high
level's redirects answer alike everywhere.

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| resolve `#frag` against `http://example.com/a/b/c?q=1`, and any `#` reference so | `http://example.com/a/b/#frag` | as 7.85.0 | as 7.85.0 | `http://example.com/a/b/c?q=1#frag` | as 8.20.0 |
| resolve `""` against `http://a/b/c/d;p?q` | `http://a/b/c/` | refused, 3 | refused, 3 | the base | as 8.20.0 |
| resolve `g:h` | `http://a/b/c/g:h` | refused, 5 | refused, 5 | refused, 5 | refused, 5 |
| resolve `http:g` | `http://a/b/c/http:g` | refused, 28 | refused, 28 | refused, 28 | refused, 28 |
| resolve the bytes `javascript:alert(1)` | `.../a/b/c/javascript:alert(1)` | refused, 5 | refused, 5 | refused, 5 | refused, 5 |
| resolve the bytes `http://[::1/x` | refused, 4 | refused, 22 | refused, 22 | refused, 22 | refused, 22 |
| resolve `é`, `?q=λ` or `?q=😀` | lower-case hex, `%c3%a9` | lower | lower | upper, `%C3%A9` | upper |
| parse `http://example.com/a b` | refused, 25 | refused, 3 | refused, 3 | refused, 3 | refused, 25 |
| parse `http://exa mple.com/` | refused, 21 | refused, 3 | refused, 3 | refused, 3 | refused, 21 |
| `curl-url-with-fragment` of a string holding a space, a tab, CR, 0x01 or 0x7F | refused, 20 | refused, 3 | refused, 3 | refused, 3 | refused, 20 |
| `curl-url-append-query` of `s=a b` | refused, 26 | refused, 3 | refused, 3 | refused, 3 | refused, 26 |
| `curl-url-part` `user` of `http://:pw@h.example/` | `#f` | `""` | `""` | `""` | `""` |
| `curl-url-part` of `http://u:@h.example/`: `url`, `password` | `http://u@h.example/`, `#f` | `http://u:@h.example/`, `""` | as 8.5.0 | as 8.5.0 | as 8.5.0 |
| `curl-url-part` `query` of `http://h.example/p?` | `""` | `""` | `""` | `#f` | `#f` |

Seen, and no test holds it by version:

- `curl-url-part` `host` of `[FE80::1%25ETH0]` keeps its case on 7.85.0 and
  8.5.0 alone; an empty zone, or `%25` or `%30` inside one, vary on 8.23.0.
- `curl-url-resolve` of a string holding 0x01 or 0x7F is refused on 7.85.0
  and 8.5.0. Bytes are encoded first, alike.
- `curl-url-resolve` of `#` and a fragment holding `%XX`: 8.20.0 and 8.23.0
  give lower-case hex.

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- Setting one part moves its `%XX` case, to lower on 7.85.0, 8.5.0 and 8.20.0,
  and to upper on 8.23.0: `curl-url-append-query`'s part goes out as written.

## TLS and finding libcurl

| What | Where |
|---|---|
| a `ca-file`, `verify` on, `SSL_CERT_FILE` or `SSL_CERT_DIR` set at the load | refused on any Guix libcurl, `environment-override`; ignored elsewhere |
| a `ca-file`, `verify` on, on macOS | refused while LibreSSL is in use, `keychain-fallback`; runs with `CURL_SSL_BACKEND=secure-transport` |
| a libcurl older than the floor; one without TLS | refused at the load, `below-floor`; `no-ssl` |
| a libcurl without multipart support | a multipart body refused at submit, `multipart-unsupported`; every other request runs |
| a libcurl without the header API | refused at the load, `missing-api` |

Seen, and no test holds it by version:

- On a libcurl built without HTTPS-proxy support an `https://` proxy is
  refused, `https-proxy-unsupported`. Every libcurl measured has it; Apple's
  8.7.1 reports it only after its init, which is when chez-curl reads it.

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- Ubuntu's libcurl trusts its own CA directory beside a CA file: the transfer
  clears it, so a `ca-file` is the only anchor.
- GnuTLS reads a `pkcs11:` path as a token: refused on every TLS library,
  `pkcs11-url`.

## The hatch

| What | 7.85.0 | 8.5.0 | 8.7.1 | 8.20.0 | 8.23.0 |
|---|---|---|---|---|---|
| `ISSUERCERT_BLOB` at the right CA | 200 | 200 | 200 | `setopt-failed`, 4 | 200 |
| `ISSUERCERT_BLOB` at another CA | 83 | OpenSSL: 83; GnuTLS: 200, ignored | 200, ignored | `setopt-failed`, 4 | 83 |
| `SSLCERT_BLOB` at bytes that are no certificate | 58 | OpenSSL: 58; GnuTLS: 200, ignored | 58 | 200, ignored | 58 |
| an owned option this libcurl does not know, `QUICK_EXIT` or `HAPROXY_CLIENT_IP` | `unknown-option` | `owned-option` | `owned-option` | `owned-option` | `owned-option` |

Where libcurls differ, and chez-curl answers alike; no test holds these by version:

- `RESUME_FROM` beside a body reads stdin on 7.85.0, and `UPLOAD` or `POST`
  after a multipart body reads stdin: chez-curl owns all three.
