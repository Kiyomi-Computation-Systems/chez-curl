# ADR-0024: What a transfer reads from its environment

- **Status:** Accepted
- **Date:** 2026-10-26
- **Scope:** chez-curl v1, every transfer, from M4
- **Settles:** the environment policy ADR-0018 handed to M4: the proxy variables, Guix's
  `SSL_CERT_FILE` and `SSL_CERT_DIR`, `SSLKEYLOGFILE`, `OPENSSL_CONF`, and GnuTLS's `pkcs11:`
  CA paths. The maintainer chose each on 2026-10-26.
- **Related:**
  - [ADR-0002](0002-runtime-libcurl-discovery.md), the worlds;
  - [ADR-0009](0009-typed-escape-hatch.md): owned options and their twins;
  - [ADR-0018](0018-ca-file-is-the-only-anchor.md), whose measurements of the TLS variables and
    `pkcs11:` this record rests on;
  - [ADR-0023](0023-the-public-request.md), the public request.

## Context

libcurl, and the TLS library under it, read several variables from the process's environment.
chez-curl cannot unset them: `setenv` is not safe beside other threads, and the environment is
the caller's (ADR-0018, Rejected).

**The proxy variables, measured on 2026-10-26** (`research/m4/proxy/`) on 7.85.0, Ubuntu's
8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, each alike. A C probe made one
transfer under `env -i` with only the variables a case named; a stand-in proxy answered 299
and logged every request it got.
- A transfer reads `http_proxy`, `https_proxy`, `HTTPS_PROXY`, `all_proxy` and `ALL_PROXY`, and
  goes through the proxy each names: the proxy logged one request per case.
- A lone `HTTP_PROXY` is ignored: the transfer went to the origin.
- `no_proxy` and `NO_PROXY` naming the origin's host send it direct.
- `CURLOPT_PROXY` set to `""` sends it direct with each variable set, and so does
  `CURLOPT_NOPROXY` set to `"*"`. The proxy logged nothing.

The Mac's 8.7.1 has not run the probe.

**The TLS variables and `pkcs11:`,** measured for ADR-0018 on the four Linux libcurls:
- Guix's 8.20.0 writes `SSL_CERT_FILE` over a transfer's `CAINFO`, and adds `SSL_CERT_DIR`, when
  the transfer starts, after every setopt. Guix's 8.6.0 lets the request win. Outside Guix both
  are ignored, and so they were on the Mac's 8.7.1 (ADR-0018, amended 2026-10-26). Guix's patch
  reads both at `curl_global_init` (`traps.md`).
- `SSLKEYLOGFILE` made every libcurl write each transfer's TLS secrets to the file it names.
- `OPENSSL_CONF` at security level 0 let a 1024-bit leaf pass on the OpenSSL builds.
- On GnuTLS, a CA file starting `pkcs11:` is read as a PKCS#11 URL: it answered 60, where a
  missing file answers 77. No widening of trust was shown.

## Decision

1. **A transfer honours the proxy variables, by libcurl's own rules,** as curl itself does. A
   request field turns them off, for that transfer, by setting `CURLOPT_PROXY` to `""`. The
   field's option is owned, and its twins, among them `NOPROXY`, are refused by the hatch
   (ADR-0009). A proxy given by URL stays M7's.
2. **Where Guix's override would replace a request's CA file, the request is refused at submit.**
   - The variables are read when libcurl loads, beside `curl_global_init`, which is when Guix's
     patch reads them, and recorded.
   - A table by ADR-0002's world and the libcurl's version says which libcurls override:
     Guix's 8.20.0 does, its 8.6.0 does not, and outside Guix none does. A Guix libcurl with
     no row is taken to override.
   - On a libcurl that overrides, with either variable recorded as set, a request with a CA
     file is refused at submit as `&curl-request-error`, naming the variable. A request with
     no CA file, which trusts the system store, goes ahead.
3. **`SSLKEYLOGFILE` and `OPENSSL_CONF` are documented, not refused.** They are the operator's
   to set, and the TLS library reads them in every program that links it. README.org names
   both, with what was measured.
4. **A CA file's path that begins `pkcs11:`, in any ASCII case, is refused when the request is
   made,** on every backend, as `&curl-request-error`. So the field always names a file. A file
   really named that way is still reached as `./pkcs11:…`.

### Rejected

- **Ignoring the proxy variables unless a request asks.** The operator's proxy settings would
  not apply by default.
- **Documenting Guix's override, or reporting it in `loaded-libcurl`.** The CA field's promise,
  the only trust anchor, would fail silently on such a profile.
- **Refusing to load with `SSLKEYLOGFILE` set.** Key logging, a common debugging aid, would
  never work with chez-curl.
- **Taking a PKCS#11 URL on GnuTLS.** The field would mean different things on different
  backends.

## Consequences

- **The suites still fail first when a proxy variable is set.** A test sets one for a child,
  against a stand-in proxy, and shows both the default and the field by the proxy's own log.
- **On Guix with `nss-certs` in the profile, a request with a CA file fails at submit,** naming
  the variable, until the caller unsets it before starting the program.
- **The override table moves from `test-transfer-tls` into `src/`,** and the suite holds the
  library's table to its own copy.
- **The Mac runs the proxy probe** with its next run, and its answers join this record.
