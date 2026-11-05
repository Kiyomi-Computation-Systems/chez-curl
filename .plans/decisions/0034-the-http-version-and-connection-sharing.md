# ADR-0034: The HTTP version, and connection sharing

- **Status:** Accepted; amended 2026-11-02, measured through the engine (M7 slice 1)
- **Date:** 2026-11-02
- **Scope:** chez-curl v1, a request's HTTP version and how transfers share connections, in
  `(curl)` and `(http-client)`, from M7
- **Settles:** where HTTP/2 by prior knowledge may be used, and whether transfers wait to share
  one HTTP/2 connection (`PIPEWAIT`). The maintainer chose on 2026-11-02, the recommended option
  each time, from the M7 plan's probe ([research](../research/m7/http2/)). ADR-0033 had settled
  that a request field sets the version.
- **Related:**
  - [ADR-0033](0033-m7s-scope.md): M7's scope;
  - [ADR-0030](0030-streams-are-request-keys-and-token-operations.md), decision 5: a paused
    HTTP/2 stream's memory beside an active one;
  - [ADR-0023](0023-the-public-request.md), decision 3: the defaults set no policy.

## Context

A C probe that steps a multi handle as the engine does ran on 7.85.0, Ubuntu's 8.5.0 with
OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, two runs each, with no cell differing between
runs:

- **`HTTP_VERSION` unset and `NONE` behave as `2TLS` on all five.** Over `https://` they offer
  ALPN `h2,http/1.1`; over `http://` they send no `Upgrade`. `1_1` offers `http/1.1` alone. `2_0`
  over `http://` sends `Upgrade: h2c`.
- **`2_PRIOR_KNOWLEDGE` over `https://` changed after 8.5.0.** 7.85.0 and 8.5.0 offer
  `h2,http/1.1`, so an HTTP/1.1 origin still answers. 8.20.0 and 8.23.0 offer `h2` alone, and
  that origin refuses the handshake: 35. Over `http://` to an HTTP/1.1 server it fails on every
  lane, 52 on 7.85.0, 56 on 8.5.0 and 16 on 8.20.0 and 8.23.0. To an h2c server it gets HTTP/2,
  where every other setting sends HTTP/1.1 and fails 1.
- **Transfers added in one step to an HTTP/2 origin** open one connection each without
  `PIPEWAIT`, and share one with it, on all five. A transfer added after another's head, or after
  its end, reuses that connection either way.
- **`PIPEWAIT` against an `https://` origin offering HTTP/1.1 alone:** on 7.85.0 and 8.5.0 the
  second transfer opens its own connection once the first's handshake shows no multiplexing. On
  8.20.0 and 8.23.0 it waits for the first to end, then reuses its connection: its first byte
  came 508 ms after its add, beside a first transfer of about 500 ms.
- **ADR-0030's paused-stream bytes** came again within 19 bytes of M6's, and `PIPEWAIT` does not
  change them once two streams share a connection. On separate connections a paused stream held
  169 to 509 KB.

The maintainer's Mac ran it on 2026-11-02, twice, against Apple's 8.7.1, as libcurl comes and
with multiplexing off as the engine sets it there (ADR-0030, amended): unset and `NONE` act as
`2TLS`; prior knowledge over `https://` falls back to HTTP/1.1, as on 8.5.0, and fails 16 over
`http://` against an HTTP/1.1 server, as on 8.20.0; `PIPEWAIT` against an HTTP/1.1 origin does not
wait. A paused stream beside an active one on a shared connection held 78,274 bytes there, where
M6's case had filled the 64 MiB cap; the engine does not multiplex on 8.7.x either way.

## Decision

1. **The request's HTTP version field takes HTTP/1.1, HTTP/2, or HTTP/2 by prior knowledge, and
   is unset by default.** Unset, the transfer sets no `HTTP_VERSION`, as today.
2. **HTTP/2 by prior knowledge is for `http://` URLs alone.** A request that asks for it with an
   `https://` URL is refused when submitted. Plain HTTP/2 gets `h2` over `https://` by ALPN on
   every lane.
3. **No transfer sets `PIPEWAIT`,** and no field or engine setting offers it. Transfers started
   together open their own connections, and a later transfer reuses an open one.
4. **ADR-0030's decision 5 stands:** what a paused stream beside an active one holds is
   documented, by version.

## Rejected

- **Prior knowledge over `https://`, pinned by version:** what it does changed between 8.5.0 and
  8.20.0, and plain HTTP/2 covers the case.
- **`PIPEWAIT` as a per-request opt-in, or on for every transfer:** on 8.20.0 and 8.23.0 it
  serialises requests to an HTTP/1.1 origin over TLS, and a shared connection lets a paused stream
  hold up to 67 MB.

## Consequences

- M7's test of connection sharing asserts what the engine does: a later request reuses an HTTP/2
  connection, and requests started together open their own. On 8.7.x every request opens its own.
- The version field's mapping to `HTTP_VERSION` values, and the codes each lane answers, are the
  M7 plan's.

## Amendment, 2026-11-02: measured through the engine (M7 slice 1)

M7 slice 1 ran these questions again through chez-curl's engine, `HTTP_VERSION` set by the hatch,
on the five Linux libcurls, two runs each, with no cell split between the kept runs
([research](../research/m7/slice1/)). Every cell of the C probe came again. What it adds:

- **`1_1` to a server offering `h2` alone fails 35, with nothing sent,** on all five.
- **Prior knowledge's code against an HTTP/1.1 server is a race:** 52, 56 and 16 by version
  natively, every time, but mostly 55 under the memory gate's Valgrind
  ([research](../research/m7/slice1/valgrind-race/)); by the builder's reading, not measured, the
  server's answer and the end of its connection beat libcurl's next send there. A suite cannot
  tell which it runs under, so the test's rows hold every code seen. Apple's 8.7.1, 16 in every
  run through M7 slice 3, gave 56 through the engine at slice 4, three runs of three, and curl's
  own tool there 56 6 times of 200 against the origin as it was before that slice
  ([log](../research/m7/slice4/results/mac-8.7.1-pk-h1-and-test-version.log)): its row holds both.
- **Through a proxy that does not tunnel, prior knowledge is ignored** on all five, the
  environment's proxy and a named one alike: the request goes as HTTP/1.1 in absolute form and
  reads 200 over 1.1, even to an HTTP/1.1 server that prior knowledge fails directly. Through a
  `CONNECT` tunnel, `HTTPPROXYTUNNEL` at 1, it speaks HTTP/2 inside. A named proxy is slice 3's,
  so `prior-knowledge-through-proxy` is decided and built there; beside `proxy environment` this
  is documented.
- **Sharing:** to an `h2` server, unset and `2TLS`, two requests submitted in one batch open two
  connections, and a request submitted after another's head or its end reuses its connection,
  on all five. By prior knowledge over `http://`, 7.85.0 shares one connection between two
  submitted in one batch, every time; the others open two. So the consequence above, "requests
  started together open their own", holds over TLS on every lane, and is pinned by version for
  prior knowledge. Apple's 8.7.1, whose engine multiplexes nothing, opened two in the Mac's
  `make test` ([log](../research/m7/slice1/results/mac-8.7.1-make-test.log)).
- **The version's twins:** `SSL_ENABLE_ALPN`, `ALTSVC` and `ALTSVC_CTRL` change what the field
  sets, and are owned (ADR-0009, amended 2026-11-02).
- **A pooled connection made by prior knowledge serves later requests:** over `http://`, a request
  with the version unset or `2TLS`, to an origin the engine already holds an HTTP/2 connection to
  by prior knowledge, reuses it and reads HTTP/2, where alone it fails 1: on 8.20.0, by the
  slice's review ([probe](../research/m7/slice1/review/)).
