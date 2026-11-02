# ADR-0037: A proxy given by URL

- **Status:** Accepted
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

Apple's 8.7.1 has not run this probe.

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
  `CONNECT`'s code, the default port, which the plan may remove by requiring one, and GnuTLS
  8.5.0's stall inside a tunnel.
- ADR-0022's rule that `REQUEST_SIZE` 0 means nothing was sent counts a `CONNECT` on 7.85.0
  alone. The M7 plan rereads it for proxied transfers.
