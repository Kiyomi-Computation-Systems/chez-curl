# ADR-0033: M7's scope

- **Status:** Accepted
- **Date:** 2026-11-02
- **Scope:** chez-curl v1, M7: HTTP/2, cookies, auth and proxies (the brief, §8)
- **Settles:** what M7 builds in each of its four areas. The maintainer chose on 2026-11-02,
  the recommended option each time, from two read-only surveys: of the code and its records,
  and of the test instrument.
- **Related:**
  - [ADR-0005](0005-node-test-origin.md): the origin, Node's standard library alone;
  - [ADR-0007](0007-one-repo-checked-seam.md): policy, auth and cookies among it, lives in
    the high level;
  - [ADR-0009](0009-typed-escape-hatch.md): the options chez-curl owns;
  - [ADR-0024](0024-what-a-transfer-reads-from-its-environment.md): a proxy given by URL,
    and its TLS, stay M7's;
  - [ADR-0030](0030-streams-are-request-keys-and-token-operations.md), decision 5: a paused
    HTTP/2 stream's memory beside an active one.

## Context

On `main` at `80bb2a9`:

- **HTTP/2:** no request field sets the HTTP version, so libcurl's default applies: `2TLS` from
  7.62.0 and `NONE` from 8.13.0, by curl 8.20.0's `CURLOPT_HTTP_VERSION(3)`. Two HTTP/2
  transfers started together opened two connections without `PIPEWAIT` and one with it, on the
  five Linux libcurls and Apple's 8.7.1 (`D-hold-mux` in
  [research/m6/pause/](../research/m6/pause/)).
- **Cookies:** no cookie engine runs. Each transfer's easy handle is fresh, `COOKIEFILE` and
  `COOKIEJAR` are owned, and there is no `curl_share`. One multi handle shares no cookies by
  default (`CURLSHOPT_SHARE(3)`).
- **Auth:** credentials reach libcurl in the URL's userinfo or a caller's `Authorization`
  header alone. `HTTPAUTH` and `PROXYAUTH` are reachable by the hatch only, and are refused
  beside a stream.
- **Proxies:** a proxy comes from the environment, or there is none (ADR-0024). Its TLS is
  libcurl's verified default, against the system store.

What the lanes can show, by the feature words in `tests/known-libcurls.sexp`:

- NTLM is built on 7.85.0, Ubuntu's 8.5.0 and Apple's 8.7.1, and not on Guix's 8.20.0 nor on
  8.23.0;
- Negotiate needs a Kerberos KDC, which no lane has;
- PSL, which moves cookie domain rules, is built on Guix's 8.20.0 and Ubuntu's 8.5.0 alone.

## Decision

1. **Auth:** Basic, Bearer and Digest. A stand-in in Node's standard library serves each, on
   every lane. Not NTLM, and not Negotiate.
2. **Proxies:** a caller names an `http://` or an `https://` proxy by URL, with its credentials
   and the proxy's own TLS fields, which ADR-0024 promised. Not SOCKS.
3. **Cookies:** one jar per session, in memory, whose cookies a caller can read out and load as
   data. No file paths: file I/O stays the caller's, and `COOKIEFILE` and `COOKIEJAR`, whose
   `"-"` reads stdin and writes stdout, stay refused.
4. **HTTP/2:** a request field for the HTTP version, unset by default, taking 1.1, 2, and 2 by
   prior knowledge; a test of connection sharing. `PIPEWAIT` and ADR-0030's paused-stream
   memory are measured before they are decided.

How each is built, the jar's mechanism, the fields' shapes and layers and `PIPEWAIT` among it,
is the M7 plan's, after its probes.

## Rejected

- **NTLM:** two of the five Linux lanes do not build it, and its stand-in needs MD4, which Node
  24.18.0's OpenSSL refuses, `ERR_OSSL_EVP_UNSUPPORTED` (measured).
- **SOCKS4 and SOCKS5:** a new face for the origin, with its stop checks. Later, if asked.
- **Cookie file paths:** `COOKIEJAR` writes only at cleanup and reports no error, by its man
  page.
- **Leaving the HTTP version to libcurl:** its default moved at 8.13.0.
- **Engine settings for `PIPEWAIT` and connection limits, now:** `make-curl-engine` takes none,
  and neither is measured through the engine.

## Consequences

- Each area's tests run on every lane. A rule that varies by version, a Digest variant or a
  cookie rule, is held in a per-version table (ADR-0017).
- An `https://` proxy under Apple's SecureTransport is unmeasured. The Mac runs M7's probes.
