# ADR-0037: A proxy given by URL

- **Status:** Accepted; amended 2026-11-02, after the M7 plan's review: a pooled tunnel; and
  decisions 6 and 7, the maintainer's, each the recommended option; amended 2026-11-03, measured
  through the engine, with decisions 8 to 10, and after the slice's review, decision 11 (M7 slice 3)
- **Date:** 2026-11-02
- **Scope:** chez-curl v1, a proxy a caller names, in `(curl)` and `(http-client)`, from M7
- **Settles:** whether the environment's `no_proxy` applies to a named proxy, how a caller gives
  a proxy's credentials, and what becomes of a caller's own `Proxy-Authorization` header. The
  maintainer chose on 2026-11-02, the recommended option each time, from the M7 plan's probe
  ([research](../research/m7/proxies/)). ADR-0033 had settled `http://` and `https://` proxies by
  URL, with credentials and the proxy's TLS fields.
- **Related:**
  - [ADR-0033](0033-m7s-scope.md): M7's scope;
  - [ADR-0024](0024-what-a-transfer-reads-from-its-environment.md): the proxy variables, and
    the proxy's TLS until M7;
  - [ADR-0018](0018-ca-file-is-the-only-anchor.md): the origin's CA file is its only anchor;
  - [ADR-0022](0022-codes-classed-as-condition-types.md): the codes' classes, and whether a
    request was sent.

## Context

Today a transfer's `proxy` is `environment`, libcurl's reading of the proxy variables, or `#f`,
none. A C probe that steps a multi handle as the engine does ran on 7.85.0, Ubuntu's 8.5.0 with
OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, two runs each, against a proxy stand-in that
parses its own requests, plaintext and over TLS. No case differed between runs.

- **`PROXY` does not override `no_proxy`.** With `PROXY` set, `no_proxy` or `NO_PROXY` naming the
  origin's host, or `*`, sent the transfer direct on all five; `NOPROXY ""` sent it through the
  proxy. A proxy variable naming another proxy lost to `PROXY`.
- **Proxy URLs:** no scheme is read as `http://`; `foo://` and `ftp://` fail 7 before any
  connect. With no port, 7.85.0, 8.5.0 and 8.20.0 try 1080, and 8.23.0 tries 80.
- **Credentials:** the proxy URL's userinfo is percent-decoded alike on all five, and wins over
  every option. `PROXYUSERNAME` and `PROXYPASSWORD` are percent-decoded on 7.85.0 and 8.5.0, and
  sent as given on 8.20.0 and 8.23.0. With `PROXYAUTH` unset, Basic goes on the first request,
  with no 407 round. A Digest user name in UTF-8 is sent percent-encoded but hashed raw on 8.23.0.
- **A caller's headers inside a tunnel:** over `CONNECT`, a caller's `Proxy-Authorization` and
  every other caller header go to the origin inside the tunnel, never on the `CONNECT`, on all
  five. The proxy's password leaks to the origin. `PROXYHEADER` reaches the proxy alone.
- **The proxy's TLS is its own:** the origin's CA and verification never reach the proxy, nor the
  proxy's the origin. `PROXY_CAINFO` set to the run's CA passes on all five; a default
  `PROXY_CAPATH` also trusts the system store on Ubuntu's 8.5.0 and on 8.23.0; Guix's 8.20.0
  takes `SSL_CERT_FILE` over a set `PROXY_CAINFO`, as it does over `CAINFO` (ADR-0024).
- **An `https://` origin through an `https://` proxy timed out, 28, on Ubuntu's 8.5.0 with GnuTLS
  alone,** every time, though the tunnel carried the response. An `http://` origin through the
  same proxy passed.
- **Failures:** a refused `CONNECT`, 403, 407 or 502, ends 56 on 7.85.0 and 8.5.0 and 7 on 8.20.0
  and 8.23.0, the status in `HTTP_CONNECTCODE`. `REQUEST_SIZE` counts a `CONNECT` on 7.85.0 alone.

The maintainer's Mac ran it on 2026-11-02, with LibreSSL and with SecureTransport, against
Apple's 8.7.1: with LibreSSL as Ubuntu's OpenSSL 8.5.0, but for two origin-verify cases where that
build's 35 is 60 here; a refused `CONNECT` 56. Under SecureTransport an `https://` proxy works and
a tunnel inside it does not stall; it ignores a `PROXY_CAPATH` directory, and with peer
verification off checks no host, which a cleared `PROXY_CAPATH` and one `proxy-verify` for both
switches make moot. Neither run could show a keychain fallback for a proxy.

## Decision

1. **`proxy` takes a URL beside `environment` and `#f`, whose scheme is `http://` or
   `https://`.** Any other is refused when the request is submitted.
2. **A named proxy takes every transfer:** with a proxy URL, the transfer sets `NOPROXY ""`, so
   no environment variable sends it direct.
3. **A proxy's credentials are its URL's userinfo, sent by Basic on the first request.** No field
   carries them, and no transfer sets `PROXYAUTH`, `PROXYUSERNAME`, `PROXYPASSWORD` or
   `PROXYUSERPWD`.
4. **A caller's `Proxy-Authorization` header is refused** when the request is submitted, whatever
   proxy it names.
5. **A named proxy's own CA and verification are request fields,** as ADR-0024 promised, on the
   origin's model (ADR-0018): `PROXY_CAINFO` with `PROXY_CAPATH` cleared, and the verify
   switches. They are the M7 plan's to shape.
6. **A proxy URL that names no port gets its scheme's,** 80 or 443, in the URL chez-curl hands
   `PROXY`, so every lane connects alike.
7. **An `https://` origin through an `https://` proxy is refused at submit on Ubuntu's 8.5.0 with
   GnuTLS,** where it never finished, every run, while its control passed; without a bound the
   transfer would wait for ever. The rule is keyed by version and backend, as 8.7.x's
   multiplexing rule is (ADR-0030, amended), and grows by measurement.

## Rejected

- **`no_proxy` beside a named proxy, libcurl's default, or a field of its own:** an ambient
  variable would send a transfer around the caller's proxy.
- **A `proxy-headers` field, or leaving the header as it is:** a header meant for the proxy
  reached the origin.
- **Proxy credentials by field, or Digest at a proxy:** the options decode differently by
  version, and Digest's UTF-8 user name fails on 8.23.0.

## Consequences

- `PROXY`, `NOPROXY` and the proxy TLS options a field sets become owned, with their twins.
- What varies by version or backend is pinned in per-version tables and documented: the refused
  `CONNECT`'s code, and which builds stall inside a tunnel.
- ADR-0022's rule that `REQUEST_SIZE` 0 means nothing was sent counts a `CONNECT` on 7.85.0
  alone. The M7 plan rereads it for proxied transfers.
- **A pooled tunnel may carry another request's proxy credentials:** 7.85.0 matches a pooled
  proxy connection by type, host and port alone, where 8.20.0 and 8.23.0 compare the user and
  password too (read in source). The M7 plan measures it on every lane, and the transfer sets
  `FRESH_CONNECT` beside proxy userinfo where a tunnel is reused.

## Amendment, 2026-11-03: measured through the engine (M7 slice 3)

M7 slice 3 ran these questions again through chez-curl's engine, a named proxy given by a
prototype's `proxy` string, on the five Linux libcurls, two runs each, and its pooled, refused and
TLS items once more under the memory gate's Valgrind on Ubuntu's 8.5.0 with OpenSSL, whose 301
rows ended as they did natively ([research](../research/m7/slice3/)). What it adds, and corrects:

- **A control byte in the proxy's userinfo sends the transfer around the proxy.** Percent-decoded,
  a byte from 0x00 to 0x1F in the user or the password makes 7.85.0 and both 8.5.0 builds drop the
  proxy and go direct: the origin answered 200, and the proxy got nothing. 8.20.0 and 8.23.0 fail
  3. 7.85.0's `parse_proxy` jumps to its error path with its result still `CURLE_OK` when the
  decode fails (`lib/url.c:2512-2517`, read in source). 0x7F, a space, and every byte above 0x7F,
  UTF-8 or not, go out as given, carried by base64; a decoded `:` in the user ends the user at the
  proxy; `@` and `:@` send `:` on both 8.5.0s and 8.20.0, and nothing on 7.85.0 and 8.23.0; `u@`
  and `:p@` go out alike on all five. chez-curl's `curl-url-part` reports the parts still
  encoded.
- **A pooled tunnel carries another user's request on 7.85.0.** A second transfer a turn after the
  first, with another user's userinfo, a wrong password, or none, rode the first's authenticated
  tunnel with no `CONNECT` of its own and got 200: by `CONNECT` to `https://`, by
  `HTTPPROXYTUNNEL`, through an `https://` proxy, and to an HTTP/2 origin as stream 3 of the
  first's connection. Both 8.5.0 builds, 8.20.0 and 8.23.0 opened a new connection and sent the
  second's own credentials. It is [CVE-2026-3784](https://curl.se/docs/CVE-2026-3784.html), "wrong
  proxy connection reuse with credentials", in curl 7.7 to 8.18.0 and fixed in 8.19.0. Ubuntu's
  8.5.0 carries the fix from `8.5.0-2ubuntu10.8`
  ([UBUNTU-CVE-2026-3784](https://osv.dev/vulnerability/UBUNTU-CVE-2026-3784)), and the lanes ran
  `10.16`. Apple's 8.7.1 source compares no HTTP proxy's user (`lib/url.c:701-710`, read in
  source); the Mac measures it. By absolute form each request carries its own credentials, and
  the proxy judges each. `FRESH_CONNECT` on the second, or `FORBID_REUSE` on the first, opened a
  new connection on all five. 7.85.0 reads `FORBID_REUSE` only as a transfer ends
  (`lib/multi.c:703`), so it cannot keep a later transfer off a live connection.
- **A refused `CONNECT`:** 403, 407 and 502 end 56 on 7.85.0 and both 8.5.0 builds, and 7 on
  8.20.0 and 8.23.0. The request size is the `CONNECT`'s on 7.85.0, 89 bytes, or 134 with
  credentials, and 0 elsewhere. So by the high level's retry rule as it stood, a `post` through it
  was tried three times on 8.5.0 and later, and once on 7.85.0; a 407 for a wrong password, three
  times. A proxy that closes, or writes a partial status line, ends 56 everywhere. By absolute
  form the proxy's status is the response, code 0.
- **TLS inside TLS:** through an `https://` proxy, on Ubuntu's 8.5.0 with GnuTLS, an `https://`
  origin and an HTTP/2 one each failed 28 at their 10 s timeout, ten times of ten in each run, the
  request sent and the answer tunnelled back. 7.85.0 stalled the same way for an HTTP/2 origin
  alone, 7 of 50 across five runs, and passed HTTP/1.1 50 of 50. The other three never stalled.
- **The proxy's TLS is its own,** and Guix's 8.20.0 takes `SSL_CERT_FILE` and `SSL_CERT_DIR` over
  `PROXY_CAINFO`, as the Context had it. Every proxy TLS setopt answered 0, GnuTLS's included. The
  failing leaves end 60 with nothing sent.
- **Proxy URLs by chez-curl's parse:** `curl_url` refuses a URL with no scheme, 27, and a scheme
  it does not know, 5, `foo://` among them; `ftp://` parses; `socks5://` parses on 8.23.0 alone,
  which registers the SOCKS schemes. With no port, listeners on 80 and 1080 saw `http://` reach
  1080 on 7.85.0 and both 8.5.0s, and 80 on 8.23.0, as the Context said; `https://` reached 443.
- **The twins:**
  - `HTTPPROXYTUNNEL` 1 moves an `http://` origin's request from the proxy, in absolute form,
    into a tunnel to the origin, a caller's headers with it, and lets prior knowledge speak
    HTTP/2 through a named proxy;
  - `HAPROXYPROTOCOL` writes its line to the proxy by absolute form, and inside a tunnel to the
    origin, which breaks a TLS origin, 35; `HAPROXY_CLIENT_IP` rewrites the line's addresses;
  - `SUPPRESS_CONNECT_HEADERS`, `PROXY_SERVICE_NAME` and `SOCKS5_AUTH` changed no byte either
    side got, and nothing chez-curl read.
- **`REQUEST_SIZE`** of a tunnelled transfer counts the `CONNECT` on 7.85.0 alone, as the
  Consequences said, even one whose origin then refused the TLS handshake.
- **The high level:** a session's `proxy`, and a call's in its place, reach every hop, another
  origin's too, the proxy URL's credentials with it; `credentials` go within one origin and drop
  across, as ADR-0036 has it.

**Decided by the maintainer, 2026-11-03,** each the recommended option:

8. **Before 8.19.0, no tunnel through a named proxy is shared.** On a libcurl older than 8.19.0,
   every transfer that tunnels through a named proxy, an `https://` origin's, sets
   `FRESH_CONNECT`, so it joins no connection, live or pooled; and one whose proxy URL holds
   userinfo sets `FORBID_REUSE` too, so it leaves none behind. Both are owned. A version cannot
   show a backport, so Ubuntu's patched 8.5.0 pays for the new connection too. From 8.19.0,
   libcurl's own match keeps another user's request off a tunnel.
9. **A refused `CONNECT` is judged by its status.** The transfer reads `HTTP_CONNECTCODE`, and
   the high level's retry treats a `CONNECT` the proxy refused with a status as a response with
   that status: it is retried when the policy's statuses hold it and the method is among its
   methods, alike on every version. The default policy never retries a 403 or a 407. A proxy that
   ends a `CONNECT` with no status keeps the class rule, where 7.85.0's size, the `CONNECT`'s,
   errs toward not repeating a `post` (ADR-0026, amended).
10. **On 7.85.0, an `https://` origin through an `https://` proxy is refused unless the request
    asks for `http/1.1`,** `proxy-tls-in-tls`, beside decision 7's refusal on Ubuntu's 8.5.0
    with GnuTLS, whatever the version asked there. Unset, or `http/2`, lets the server choose
    HTTP/2, which stalled.

**Following from decisions already made:**

- The proxy URL's userinfo is checked percent-decoded, by ADR-0036's decisions 5 to 7: UTF-8, no
  control byte, no `:` in the user, and not both parts empty. Encoded, every form is ASCII and
  would pass.
- `HTTPPROXYTUNNEL`, `HAPROXYPROTOCOL` and `HAPROXY_CLIENT_IP` are owned, since each changes what
  the field sends; `SUPPRESS_CONNECT_HEADERS`, `PROXY_SERVICE_NAME` and `SOCKS5_AUTH` stay the
  hatch's, documented.
- A proxy URL's scheme is chez-curl's to judge: any scheme but `http` or `https` is
  `proxy-scheme` on every version, `socks5://` and `foo://` among them; a URL with none is
  `proxy-url`.

**After the slice's review, 2026-11-03.** Decision 8 kept a named proxy's tunnelled transfer off
other connections, and an authenticated one from leaving its own pooled; it kept no other
transfer off a live one. On 7.85.0 a transfer through `proxy environment`, `https_proxy` naming
the same proxy with no userinfo, submitted while a named proxy's transfer with alice's userinfo
had its HTTP/2 stream live, got 200 as a second stream on alice's connection, the proxy logging
alice's `CONNECT` alone; alone, it was refused 407. Both 8.5.0 builds, 8.20.0 and 8.23.0 sent a
`CONNECT` of their own, refused 407. The review's probe, two runs; my rerun, alike
([review](../research/m7/slice3/review/), [verify](../research/m7/slice3/verify/)). The same case
on an engine that does not multiplex, `CURLMOPT_PIPELINING` 0 as 8.7.x's engines run, sent the
second transfer's own `CONNECT`, refused 407, on 7.85.0, two runs of two
([verify](../research/m7/slice3/verify/), `env-join-fix.sps`).

**Decided by the maintainer, 2026-11-03, the recommended option:**

11. **Before 8.19.0, an engine stops multiplexing at its first transfer through a proxy URL that
    holds userinfo, and never resumes,** as 8.7.x's engines run (ADR-0030, amended). So no
    transfer joins a live authenticated tunnel, whatever its `proxy`; the cost falls on the
    programs that use an authenticated proxy on an older libcurl. When the switch takes effect
    against a transfer already live is the slice's to measure.

**As built** (M7 slice 3's build, its review and two fix rounds;
[build](../research/m7/slice3/build/), [verify](../research/m7/slice3/verify/)):

- **The proxy URL** is parsed by `curl_url` with `CURLU_NON_SUPPORT_SCHEME`, so every scheme
  parses on all five and chez-curl's own compare, A to Z folded, answers `proxy-scheme` alike;
  without the flag the SOCKS schemes parse on 8.23.0 alone and `foo://` nowhere. A URL with no
  scheme is `proxy-url`, by codes that vary, 27, 28 or 3. The refusals come in order: the parse,
  and a `%` not followed by two hex digits in the user or the password, which parses on all five
  and would go out as written (`proxy-url`); the scheme; the parts, where an empty query or
  fragment counts as none, since 7.85.0 and 8.5.0 report `""` for `/?` and later ones none; the
  user; the password. A raw control byte, space or 0x7F in the userinfo fails the parse itself.
  7.85.0 reports no user for `@` and `:@`, which pass there with no `Proxy-Authorization`, and
  gives `u:@` back as `u@`; from 8.5.0 both are `credentials-empty`. A refusal's field is
  `proxy`, its value `proxy`, `(proxy user)` or `(proxy password)`, never the URL.
- **A caller's `Proxy-Authorization`** is refused when the request is made, not at submit, as the
  other header rules are: a request's own shape, needing no libcurl.
- **The proxy's TLS:** the verify pair is set for every proxy URL, inert beside an `http://` one;
  `proxy-tls-without-https-proxy` reads `proxy-ca-file`, then `proxy-verify #f`. `proxy-ca-file`
  is copied and checked as `ca-file` is; `environment-override` is pinned by a Guix child test,
  and `keychain-fallback` by none, since the Mac's suites run SecureTransport.
- **An `https://` proxy on a libcurl without `CURL_VERSION_HTTPS_PROXY`** is refused at submit,
  `https-proxy-unsupported`: libcurl writes such a proxy URL whole, its userinfo with it, into
  its error buffer (the review, read in source; no lane lacks the feature).
- **TLS inside TLS** is keyed by the loaded libcurl's version and its backend's name, read after
  the init, as the multiplexing rule reads them; a backend that cannot be read refuses where the
  version has a row. A redirect hop that meets it fails the call as the hop is submitted.
- **Decision 8:** below `#x081300`, a transfer to an `https://` URL through a proxy URL sets
  `FRESH_CONNECT`, and with userinfo `FORBID_REUSE`, once each beside the streamed body's.
- **Decision 9:** `curl-transfer-error-connect-code` is public, `#f` for 0 or a 2xx; the retry
  reads it before the class rule, and waits the backoff, never a `Retry-After`.
- **Decision 11:** the switch holds for a proxy URL with userinfo of any scheme, an `http://`
  one sent by absolute form too. The engine sets `CURLMOPT_PIPELINING` 0 on its thread in
  `set-up!`, before the transfer starts, and never sets it back. Measured on 7.85.0 and both
  8.5.0s, two runs each: two streams live on one HTTP/2 connection when the switch came ended 200
  on it, whole, and a later transfer to the same origin opened a connection of its own, where
  without the switch it joined theirs. In a child with `https_proxy` set, the environment's
  transfer sent its own `CONNECT` there, refused 407; on 8.20.0 and 8.23.0 no switch, and
  libcurl's own match refused it 407.
- **The twins:** `HAPROXY_CLIENT_IP`, unknown to 7.85.0, has no id there, so its attachment is
  refused first as `unknown-option`. `rounds-option-names` went with `PROXYAUTH` owned;
  `stream-with-rounds` stays, raised by `follow` beside `stream-buffer`. `CONNECT_TO` stays the
  hatch's, documented: it moves the host and port a `CONNECT` names.
- **The Mac's first run, 2026-11-03,** refused every `https://` proxy, `https-proxy-unsupported`:
  the check read the features word the load had read before `curl_global_init`, where Apple's
  MultiSSL 8.7.1 reports `CURL_VERSION_HTTPS_PROXY` clear. The check now reads the word from the
  call after the init that reads the backend, `loaded-features`, and the decoy libcurl's MultiSSL
  build holds it on Linux ([Mac log](../research/m7/slice3/results/mac-8.7.1-make-test.log)). Eight
  8.7.1 rows came from that run's two passes, through `http://` proxies, which the bug did not
  touch. Its second run, at `043ef4e`, gave the last, `8.7.1/SecureTransport`, refusing none:
  SecureTransport reached an `https://` proxy, its good leaf 200, the failing ones 60, each
  passing with verification off, and an `https://` URL inside it answered 200 for each
  `http-version`, no stall ([log](../research/m7/slice3/results/mac-8.7.1-make-test-2.log)). Its
  backend in use read SecureTransport with `CURL_SSL_BACKEND` unset, where ADR-0024's 2026-10-27
  amendment had the init put LibreSSL in use; carried, not traced.
