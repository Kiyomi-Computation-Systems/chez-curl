# ADR-0005: The test origin server is one Node file, standard library only

- **Status:** Accepted
- **Date:** 2026-10-04
- **Scope:** chez-curl's test instrument (brief §7, milestone M1) and every test lane
  after it
- **Settles:** D8. That decision was raised on 2026-10-04, after the brief was written.
- **Related:** brief §7 · [ADR-0002](0002-runtime-libcurl-discovery.md), whose override
  points the suite at a chosen libcurl · [ADR-0003](0003-libcurl-floor-7-85.md), whose floor
  lane runs this same server

## Context

Brief §7 asks for a local origin server that produces, on demand:

- chunked and close-delimited bodies;
- every redirect status;
- slow drips and oversized headers;
- HTTP/2 and TLS, including the expired, wrong-host and untrusted failure cases;
- deliberate protocol errors.

Later milestones add proxies, auth, cookies and multipart. "Node v20.10.0 is on this
machine" was measured on the maintainer's Mac. This repository's Linux host has no Node
outside Guix. What each environment provides, checked 2026-10-04:

| Environment | Node | Python | Python's HTTP/2 library (`h2`) |
|---|---|---|---|
| Maintainer's Mac (per the brief) | 20.10.0 | 3.9, the system copy | not installed |
| GitHub `ubuntu-24.04` (image 20260927) | 22.23.3 by default, 24.21.0 cached | 3.12.3 | via pip or apt |
| Guix, at the current pin | 24.18.0 | 3.12.12 | `python-h2` 4.3.0 |

Python's standard library has no HTTP/2 server. Node's has HTTP/2 (with ALPN and prior
knowledge), TLS, raw sockets and CONNECT handling. Neither sibling repository uses a helper
runtime in its test lanes, so there is no house precedent.

## Decision

1. **The test origin is a single Node ES module**, `tests/origin.mjs`. It uses only Node's
   standard library: no npm, no `package.json`, no `node_modules`.
2. **The Node floor is 20.** That is the oldest version any environment runs, and the server
   prints the Node version it runs under.
3. **The server's contract with the test suites:**
   - It binds loopback addresses only.
   - It takes ports from the OS (port 0) and announces them as one JSON line on stdout
     before serving.
   - It exits when its stdin closes, so it cannot outlive the suite that started it.
4. **It has two faces.**
   - **A well-formed face** is built on `node:http`, `node:https` and `node:http2`. It
     serves features: redirects, cookies, auth, HTTP/2 and proxies.
   - **A raw face** is built on `node:net` (and `node:tls` when the bytes travel over TLS).
     It writes scripted bytes for chunked and close-delimited bodies, slow drips, oversized
     headers and deliberate protocol errors.

   Node's HTTP servers normalise framing, so they cannot be trusted to emit malformed
   bytes. That includes HTTP/2 frames that nghttp2 would refuse to send.

### Rejected

- **Python with `h2`.** HTTP/2 would need a third-party library in every environment,
  driven by a hand-written server loop, and the Mac would need a virtualenv for it.
- **Go.** Its standard library would cover HTTP/2 and certificate generation. But it means
  installing a compiled toolchain in every environment, for a test fixture.
- **A Chez server built on chez-http-server.** The brief keeps the two projects independent
  (§3, D5). A test server written by the same family could also share the client's
  misunderstandings.
- **curl's own test servers.** They are built for curl's `runtests.pl` and need a C build.

## Consequences

- **JavaScript enters the repository, confined to `tests/`.** It comes with no package
  manager and nothing to install beyond Node itself.
- **The floor of 20 is tested only on the Mac.** Node 20 has been out of support since
  April 2026. A loopback-only test fixture needs no security fixes, so the Mac's 20.10.0
  stays in range. CI runs 22 and Guix runs 24.
- **On this host, Node comes from the development environment's Guix manifest.** The shape
  of that environment is a decision still to be made.
- **The server and the client share an HTTP/2 implementation.** Node's `http2` is built on
  nghttp2, and libcurl uses nghttp2 for HTTP/2 too. That is acceptable, because the suite
  tests chez-curl's binding and policy, not libcurl's HTTP/2 conformance. Where a test needs
  HTTP/2 behaviour nghttp2 will not produce, the raw face writes the frames itself.
- **TLS material comes from the `openssl` command line at test time, not from Node.** Node
  can parse certificates but cannot create them. Generating the test CA, leaf and failure
  certificates per run also means nothing in the repository can expire.
- **The instrument is tested before any client exists** (brief §7, M1). Each scenario gets
  a check of its own, so a fixture that has stopped producing what its name claims fails
  there, and not as a mysterious client bug later.
