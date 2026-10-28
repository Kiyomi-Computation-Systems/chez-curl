# ADR-0028: A query is appended by writing the URL, then parsing it whole

- **Status:** Accepted
- **Date:** 2026-10-27
- **Scope:** chez-curl v1, `(curl)`'s `curl-url-append-query`, and so `(http-client)`'s
  `params`, from M5 slice 1
- **Settles:** how `params` reach a URL's query. M5 slice 1's measurement raised it; the
  maintainer chose on 2026-10-27, the recommended option.
- **Related:**
  - [ADR-0008](0008-curl-url-only.md): `curl_url` parses every URL a caller hands chez-curl;
  - [ADR-0025](0025-the-high-levels-surface.md): `params`, a list of name and value pairs,
    encoded and appended to the URL's query;
  - the M5 plan, §3.1 and §4.1.

## Context

The M5 plan had `curl-url-append-query` call `curl_url_set` with `CURLU_APPENDQUERY` and no
`CURLU_URLENCODE`, the part already encoded by the WHATWG form serializer, in upper-case hex.
Slice 1 measured it first ([research](../research/m5/url-parts/)), through `curl_url_set` and
`curl_url_get`, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and
8.23.0: 56 appends, 2 plain sets of a query and 44 URLs read back by part, the two 8.5.0 builds
alike.

- **Setting a part changes its hex case,** appended or not: 7.85.0, 8.5.0 and 8.20.0 write
  `%3D` as `%3d`, and 8.23.0 writes `%3d` as `%3D`. So no case an encoder picks goes out alike
  on all five.
- **Parsing a whole URL keeps the case it was given,** on all five: the path, the query and
  the fragment of `http://h.example/p%3D%3d?x=%3D&y=%3d#f%3D%3d` come back as written.
- **The rest of an append agrees on all five:** `&` is added unless the query ends in one, a
  bare or empty `?` takes the part with none, a fragment is kept, and a space or raw UTF-8 goes
  in as given. An empty part appends `&` to a query, and leaves a URL with none without one.

## Decision

1. **`curl-url-append-query` writes the new URL, then has `curl_url` parse it whole.** From one
   parse of the URL it reads `url`, `query` and `fragment` back by `curl_url_get`; it takes the
   fragment, with its `#`, off the end of the URL, adds `?` when the query is absent or empty,
   `&` unless the query ends in one, then the part, then the fragment again; and it parses that
   string whole, as `url-normalize` does, and answers what `curl_url_get` gives back. Two
   answers no measured libcurl gives are met too: a `?` kept for an empty query is dropped from
   the stem, and an empty fragment the URL leaves out adds no `#`.
2. **A check reads the query back:** the answer's query must be the old query, the separator
   and the part, exactly, or the call raises `&curl-url-error`, a new reason,
   `query-not-kept`. A part holding `#`, which would start a fragment, is one.
3. **The part is the caller's, encoded:** `curl-url-append-query` encodes nothing, and the
   whole parse refuses what `curl_url` refuses.

### Rejected

- **`CURLU_APPENDQUERY`, as the plan had it.** The URL on the wire, and the response's URL,
  would carry lower-case hex on 7.85.0, 8.5.0 and 8.20.0 and upper-case on 8.23.0: equivalent
  by RFC 3986 §6.2.2.1, but a URL signed or compared byte for byte would differ by libcurl.

## Consequences

- **`params` go out exactly as chez-curl encodes them,** upper-case hex, on every libcurl.
- **Every URL is still parsed by `curl_url`** (ADR-0008, decision 1): the string chez-curl
  writes holds only what `curl_url_get` gave back and the caller's part.
- **`test-url-parts` holds the append,** each parsed whole, on 78 cases: the probe's eight URLs,
  each with six of its parts, the query's other characters and a `#`; every byte encoded in
  each case; URLs whose other parts a parse could change; and the probe's space, on two of the
  eight. A version row holds each answer that differs by libcurl, the space's code among them.
- **The string is written by a pure function,** `appended-url`, which `test-url-parts` drives by
  tables, the two answers no libcurl gives among them, so deleting either branch fails it.
- **One equivalent mutant survives:** a read-back that compares without case passes every case,
  since no measured libcurl changes a part's case when it parses a whole URL.
