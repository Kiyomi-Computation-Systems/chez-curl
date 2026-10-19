# ADR-0005: The test origin server is one Node file, standard library only

- **Status:** Accepted; amended 2026-10-18: the byte probe checks the instrument, and CI tests the Node floor (M1); amended again 2026-10-18: `openssl` checks certificates portably, with no hostname code (M1 slice 2)
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

## Amendment, 2026-10-18: how the instrument is checked, and the Node floor in CI (M1)

The maintainer settled two questions for M1 ([M1 plan](../2026-10-18-m1-plan.md)).

- **What checks the instrument, with no client: a byte probe and `openssl`.**
  - Chez has no sockets. No name with `socket`, `tcp` or `connect` in it is in Chez
    10.4.0's `(scheme-environment)` (measured 2026-10-18). So a Chez suite reaches the
    origin only through another process.
  - That process is `tests/wire-probe.mjs`, a second Node file confined to `tests/`. It
    connects, sends the bytes it is given, and prints every byte it receives, with timings,
    as Scheme data. It has no HTTP code, so nothing normalises framing between the origin
    and the suite.
  - The suites hold their own copy of each scenario's expected bytes, and assert whole
    outputs.
  - Certificates are checked by `openssl`'s verify codes.
  - No check uses libcurl or the `curl` command line. The instrument is not judged by the
    library it will test.
  - Rejected: the `curl` command line as the checker. Its verdicts change between 7.85 and
    8.20, a malformed response would show only as an exit code, and the instrument would be
    checked by the thing it tests.
- **The Node floor is tested in CI, not only on the Mac.** That replaces this record's
  consequence "The floor of 20 is tested only on the Mac".
  - CI's `floor` lane installs Node at `packaging/floors.sexp`'s version through a pinned
    `actions/setup-node`, reading it with `scripts/ci/floor.sh node`.
  - CI has never run, so M1's builder also runs the origin's suite under Node 20.10.0 in
    Docker, with Chez built by `scripts/ci/build-chez.sh`.
- **The contract is made exact.**
  - Each face listens on `127.0.0.1`.
  - The announcement is one flat JSON object: `node`, `pid`, then each face as
    `ADDRESS:PORT`. Each address is read back from the listening socket.
  - Nothing else is written to stdout.
  - A client that misbehaves ends only its own connection.
- **Measured for the TLS material** (2026-10-18). One script, with EC keys and a config
  file, worked unchanged on three implementations:

  | Implementation | Where |
  |---|---|
  | OpenSSL 3.5.7 | the container |
  | OpenSSL 3.0.13 | Docker `ubuntu:24.04` |
  | LibreSSL 3.3.6 | Docker `alpine:3.14` |

  It made a CA, a good leaf, a wrong-host leaf, and an expired leaf through
  `ca -startdate/-enddate`. `openssl verify` gave the same verdicts on all three, except for
  a self-signed leaf: error 18 on OpenSSL, 20 on LibreSSL. So the untrusted leaf is signed
  by a second CA that is never trusted. The Mac's own `openssl` is not measured.

## Amendment, 2026-10-18: how `openssl` checks the TLS faces (M1 slice 2)

The maintainer chose portable checks only ([M1 plan](../2026-10-18-m1-plan.md), §8).

- **Measured.** Node served each leaf, and `openssl` checked it. The same commands ran on
  OpenSSL 3.5.7 (the container), 3.0.13 (Docker `ubuntu:24.04`, as on CI's runner) and
  3.0.11 (Docker `node:20.10.0-bookworm`). They ran on LibreSSL 3.3.6 twice: built from its
  tarball in that image, and on Alpine 3.14.
  - All of them agreed on `s_client`'s exit status, verify errors, final code and ALPN
    line, on the served leaf, and on `x509 -text`'s SAN line.
  - **LibreSSL 3.3.6, the Mac's `/usr/bin/openssl`, cannot check a hostname.** It has no
    `-verify_hostname`, `-verify_ip`, `-checkhost` or `-ext`. So OpenSSL's code 62, hostname
    mismatch, cannot be had on the Mac.
  - LibreSSL's `s_client -verify_return_error` exits 0 when verification fails.
- **So each TLS face is checked by three portable facts:**
  - `s_client`'s verify errors and final code against the run CA: none and 0 for a good
    leaf, 10 and 10 expired, 20 and 21 untrusted;
  - the leaf it serves, compared with its file;
  - that leaf's SAN line.

  The code is the first `Verify return code` line. OpenSSL 3 prints one more for each
  TLS 1.3 session ticket it reads before stdin ends, a number that depends on timing. So
  each later line must sit under its own ticket header and agree with the first. It did on
  every face, measured on OpenSSL 3.5.7 and 3.0.11, and LibreSSL printed only one.

  The wrong-host leaf verifies (0) and names only `wrong-host.invalid`. Each failing leaf
  has one fault the good one lacks, and every leaf has the same subject, which names no
  host. No check reads a hostname code, an exit status
  under `-verify_return_error`, or the `-subject` line, whose format differs between
  OpenSSL and LibreSSL. Names are read from `x509 -text`'s `Subject:` and `Issuer:`
  lines instead, once ` = ` is folded to `=`: OpenSSL 3.0 writes `CN = x`, and 3.5.7 and
  LibreSSL write `CN=x`.
- **The untrusted leaf is signed by a second CA,** as the first amendment found: a
  self-signed leaf is error 18 on OpenSSL and 20 on LibreSSL. That leaf verifies against
  the second CA, so trust is its only fault.
- **`OPENSSL` names the checker,** else `openssl`, as `NODE` names Node.
- **Rejected:**
  - **`-verify_hostname` where it exists, skipped by name on LibreSSL.** That means two paths,
    and the Mac would run fewer checks.
  - **Requiring an OpenSSL checker on the Mac,** through Homebrew's `openssl@3`. That adds
    a dependency, and the check could not run on stock macOS.
- **Measured for the faces** (Node 20.10.0 and 24.18.0 alike):
  - an `https` server accepts `http/1.1` by ALPN by default;
  - an HTTP/2 server with no HTTP/1.1 answers a client that does not choose `h2` with an
    `HTTP/1.0 403 Forbidden` text, unless an `unknownProtocol` listener takes the socket.
    So the origin destroys that socket at once, and no client reads the text as a
    response. This record first said Node would wait 10 s. That came from a measurement
    with a listener attached, and the slice's review corrected it;
  - `resetAndDestroy()` on a TLS socket throws `ERR_INVALID_HANDLE_TYPE`. A server resets
    the TCP socket it wrapped. A client that resets its TCP socket that way still reaches
    the server as a FIN, so the probe has no TLS reset.
  - Both versions send an empty SETTINGS frame by default, and write the same HTTP/2 bytes.
  - **One difference:** after an HTTP/2 connection error the origin sent, Node 24.18.0
    emits `sessionError` and closes. Node 20.10.0 emits nothing and leaves the connection
    open until the client goes (M1 plan, §8.8).
