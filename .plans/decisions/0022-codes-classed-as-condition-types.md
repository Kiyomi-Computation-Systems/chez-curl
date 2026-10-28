# ADR-0022: libcurl's codes are classed as condition types

- **Status:** Accepted; amended 2026-10-26: after the plan's review; amended 2026-10-26: a failure carries its request size, and the table as built (M4 slice 1); amended 2026-10-27: 8.7.1 reports no request size; amended 2026-10-28: the request size and the classes over TLS and HTTP/2 (M5 slice 3)
- **Date:** 2026-10-26
- **Scope:** chez-curl v1, what a failed transfer raises, from M4
- **Settles:** the brief's "error taxonomy mapping `CURLE_*` to conditions" (§8, M4); the
  maintainer chose on 2026-10-26
- **Related:**
  - [ADR-0003](0003-libcurl-floor-7-85.md), the floor, whose headers name the codes every
    libcurl has;
  - [ADR-0020](0020-a-ci-lane-on-the-current-libcurl.md), amended 2026-10-26: 8.23.0's 55 on a
    server's silent close;
  - the M2 plan, §3.7, and the M3 plan, §3.4, which left the taxonomy to M4.

## Context

A failed transfer raises `&curl-transfer-error` today. Its reason is one of eight symbols, and
`perform-failed` carries libcurl's `CURLcode` as a number, with `curl_easy_strerror`'s text and
the error buffer's. Codes past the floor's have no name in chez-curl, so a code is a number.

Measured on 2026-10-26:

- **The floor's headers name codes 0 to 99.** 8.23.0's add 100, `CURLE_TOO_LARGE`, and 101,
  `CURLE_ECH_REQUIRED`, and rename 34 and 41 obsolete. Both lists were read from
  `include/curl/curl.h` of the floor's build and of the `current` lane's.
- **One failure can carry different codes by version.** From `test-transfer`'s version rows:
  - an oversized response head is refused with 27, `CURLE_OUT_OF_MEMORY`, on 7.85.0 and
    8.5.0, and with 100 on 8.7.1, 8.20.0 and 8.23.0;
  - 100,000 headers are answered 200 on 7.85.0, refused with 56, `CURLE_RECV_ERROR`, on 8.5.0
    and 8.7.1, and with 100 on 8.20.0 and 8.23.0.

  From the M4 plan's proxy measurement (`research/m4/proxy/`): a proxy that refuses a CONNECT
  gives 56 on 7.85.0 and 8.5.0, and 7, `CURLE_COULDNT_CONNECT`, on 8.20.0 and 8.23.0. And
  8.23.0 gives 55, `CURLE_SEND_ERROR`, where earlier libcurls reused no dead connection
  (ADR-0020, amended 2026-10-26).

Three shapes were offered:

- condition subtypes by class;
- one type with a `kind` field computed from the code;
- codes only, as named constants.

## Decision

1. **A class is a condition type under `&curl-transfer-error`.** It keeps every field the base
   has: the reason, the code and both texts. A caller catches a class with a guard on its
   predicate, or the family with `curl-transfer-error?`.
2. **The class follows the code, never the scenario.** The same failure may change class with
   the version, as the measurements above show. The version rows already pin each scenario's
   code, and so its class.
3. **A code no class names stays the base type.** That includes a code newer than any header
   the table was read from.
4. **Every code from 0 to 101 has a row in one table, written out in the suite:** its class, or
   none. A class's rows cite curl's description of the code, and each code a scenario can reach
   is measured.
5. **The classes, as first proposed** (the M4 plan, §3.4). M4's slice settles the table, and
   its review may move a row:
   - **timeout:** 28;
   - **connect:** the connection was never made: no name, no route, or a proxy that refused it;
   - **connection lost:** the connection broke after it was made: 52, 55 and 56;
   - **TLS:** the handshake, the peer's certificate, or the CA material;
   - **protocol:** the peer's reply broke HTTP;
   - **too large:** the body limit, both its reasons, and libcurl's 100;
   - **redirects:** 47, too many.
6. **The reasons stay.** `cancelled`, `stopped`, `setopt-failed`, `unknown-option` and
   `no-handle` raise the base type. `body-limit` raises the too-large class.
7. **Tests assert the type, the reason and the code,** never the texts, as now.

### Rejected

- **One type with a `kind` field.** It needs fewer exports, but every guard would test a symbol
  beside the predicate.
- **Codes only.** Every caller would rebuild the classes, from numbers that move by version.

## Consequences

- **`(curl)` exports one type, and one predicate, per class.**
- **M5's retry policy reads classes,** not codes.
- **A class is only as stable as libcurl's codes.** The rows record where they move. An
  oversized head is a too-large failure from 8.7.1 on, and the base type before it, since 27
  also means libcurl ran out of memory.
- **A libcurl that adds a code raises the base type with it,** until the table gains its row.

## Amendment, 2026-10-26: after the plan's review

An adversarial review of the M4 plan (Opus, read-only) found the proposed rows contradicted by
scenarios `test-transfer` already asserts, and three decisions loosely worded. The decision,
classes by code, stands. Revised:

- **Decision 5's classes are described in curl's own words for their codes, never by a
  cause.** The shared answers show why:
  - 56 is what libcurl answers for a bad chunk size, a protocol error;
  - `short-body` and `reset-mid-body` play the same bytes, and answer 18 after a clean close and
    56 after a reset;
  - and §Context's 56s, 100,000 headers and a refused CONNECT, are no lost connection either.

  So "connection lost" becomes a send-or-receive class, 18, 52, 55 and 56, and 18 leaves
  protocol. A connect error includes a proxy variable that names no proxy that answers, 5 or 7.
  The suite's table lists the scenarios that reach each code.
- **The redirects class is dropped.** The M4 plan owns `FOLLOWLOCATION`, after the review's
  probe showed libcurl resending a custom method without its body through a 301, 302 or 303
  (ADR-0023, amended). So libcurl never answers 47 in M4, nor 3, which it gives only while
  following. M5 follows redirects itself, and raises its own failure for too many.
- **Decision 2 holds for `perform-failed` alone.** `body-limit`'s code is 23, which no class
  names, and decision 6 makes it too-large: so the class follows the code for `perform-failed`,
  `body-limit` is too-large, and every other reason raises the base type, a `setopt-failed`
  whose code a class names among them. The suite writes the rule out.
- **Decision 4's table is keyed by name.** Every classed code is a constant in
  `(curl private constants)`, checked against the headers, as global-constraints requires of
  every constant. 100, `CURLE_TOO_LARGE`, carries its gate, 8.6.0, and 101,
  `CURLE_ECH_REQUIRED`, 8.8.0 (`docs/libcurl/symbols-in-versions`).
- **Decision 7 was wrong about texts.** Tests do assert texts where a version row pins one:
  `test-transfer`'s `error-text` rows, and ADR-0020's 55. So: tests assert the type, the reason
  and the code, and a text only where a version row pins it.
- **A class alone does not say whether a request was sent,** which M5's retry policy needs: 28
  covers a connect and a whole transfer. So a failed transfer's condition carries the timings
  the response would have, as far as the transfer got (the M4 plan, §3.3).

## Amendment, 2026-10-26: a failure carries its request size, not its timings, and the table as built (M4 slice 1)

The amendment above had a failed transfer carry its timings, so that M5's retry policy could
tell whether a request was sent. M4 slice 1 measured them first
([research](../research/m4/slice1/)): a C probe read the six `*_TIME_T` infos, as `curl_off_t`,
with `CURLINFO_REQUEST_SIZE` and `CURLINFO_HEADER_SIZE`, against the test origin, on 7.85.0,
Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0.

- **On a failure, the timings move with the version.** For a connect that was refused,
  8.20.0 reports a total of 0, 7.85.0 and 8.5.0 the time it took, and 8.23.0 fills
  pretransfer and starttransfer too, 95 µs, though nothing was sent. For a TLS handshake the
  server never answered, ended by the connect timeout, 8.23.0's pretransfer is 301 ms, and
  8.20.0 reports every timing but the name lookup 0. For a server that closed before answering, 52, starttransfer
  is set on 7.85.0 and 8.5.0 and 0 on 8.20.0 and 8.23.0.
- **`CURLINFO_REQUEST_SIZE` says it, on all five alike.** It is 0 on every failure that sent
  nothing: a refused connect, a name or a proxy that did not resolve, a proxy that refused, a
  TLS failure, 60 or 77, and a stalled handshake. Once the request is sent it is the head's
  length exactly, 75 bytes for `/raw/stall-before-head`, whether the transfer then timed out,
  got nothing, 52, or broke off, 18 and 56.
- **On a success, the timings agree:** every libcurl reports namelookup, connect, appconnect
  (0 over plaintext), pretransfer, starttransfer and total in that order, and a pause of
  300 ms mid-body puts total at least 300 ms past starttransfer.

**Decided by the maintainer, 2026-10-26:** a failed transfer's condition carries its request
size, `CURLINFO_REQUEST_SIZE`, the bytes of request libcurl sent, 0 when it sent none, and no
timings. M5's retry policy reads it to tell whether a request was sent. The timings stay on the
response alone.

**The table, settled as built.** Slice 1 read curl's description of every code in 8.23.0's
`libcurl-errors` against the plan's table (§3.4), and kept it whole. One note: curl describes 1,
`CURLE_UNSUPPORTED_PROTOCOL`, as a protocol this libcurl does not support. A submit refuses
every scheme but `http` and `https` (ADR-0008), so libcurl answers 1 only for a reply it cannot
speak, an HTTP/0.9 one or a bad status line, and 1 stays a protocol error. `(curl private
conditions)` holds the table, `curl-code-classes`, keyed by the constants' names, and
`make-classed-transfer-error` the reasons' rule; each class's constructor refuses a reason, or a
code, it does not take. `test-conditions` writes out every code from 0 to 101, and 102 and 999;
`test-transfer` derives each answer's class through a table of its own.

**After the slice's review** (Opus, read-only), which predicted, from libcurl's source, a
failure the `current` lane then showed:
- **The request size is the sum over every attempt libcurl made, the body's bytes among
  them.** The measurement above used a fresh handle per transfer. Through one engine, curl
  8.23.0 reused a raw-face connection that had gone back to its pool dead, sent the head on
  it, then again on a fresh one, and reported 150 for a 75-byte head
  ([`current-lane-request-size.log`](../research/m4/slice1/results/current-lane-request-size.log)).
  `Curl_initinfo`, which resets it, runs once per transfer, and every send adds to it (the
  review's reading of 8.23.0's `transfer.c`). On 8.20.0 a POST of 5 bytes that timed out
  before any answer reported 100, its 95-byte head and its body, and one of 100,000 bytes
  100,100 ([`review-checks-guix-8.20.0.log`](../research/m4/slice1/results/review-checks-guix-8.20.0.log)).
  So it is 0 exactly when nothing was sent, which is what M5's retry policy reads, and no more:
  not the head's length, nor the bytes the server got. `test-request` runs each request-size
  check on an engine of its own, its pool empty.
- **On a connection reused, the timings of the phases it skipped are 0:** a second GET over one
  https connection reported name-lookup, connect and tls-handshake 0, on 8.20.0 (the same log).

## Amendment, 2026-10-27: 8.7.1 reports no request size

The maintainer's Mac ran `make test` on M4 slice 3's PR, the first Mac run of slice 1's
request-size check: Apple's libcurl 8.7.1 answered 0 for a timeout before the head, a server
that closed before answering, the body limit and a raise in the callable, each of which sent
the head (`research/m4/slice3/results/mac.log`).

- **Measured, 2026-10-27:** upstream curl 8.7.1, built from its tarball with OpenSSL in Docker
  `ubuntu:24.04`, answered `CURLINFO_REQUEST_SIZE` 0 on all 21 of slice 1's probe transfers,
  a 200 among them (`research/m4/slice3/results/reqsize-8.7.1.log`). Guix's 8.6.0 answered the
  request's length, as 7.85.0, 8.5.0, 8.20.0 and 8.23.0 do
  (`research/m4/slice3/results/reqsize-guix-8.6.0.log`). So it is 8.7.1's, not Apple's, and
  the window lies after 8.6.0 and before 8.20.0.
- **Decided by the maintainer, 2026-10-27: on a libcurl whose request size is known broken, a
  failure carries `#f`, unknown.** The request size becomes `(U Natural #f)`. A table by version
  names the broken libcurls, 8.7.1 measured, the window's edges measured before its rows land.
  M5's retry policy reads `#f` as "whether the request was sent is unknown". `test-request` pins
  8.7.1's row.
  - **Rejected:** keeping 0 and documenting it: 0 would then lie on the Mac, the one platform
    that ships 8.7.1.
- **Decided by the maintainer, 2026-10-27: the fix lands in slice 3's PR,** so the Mac's `make
  test` can pass before the merge.
- **The window, measured 2026-10-27:** upstream 8.7.0, its library built alone, since its man
  pages failed to build, answered 0 on all 21 transfers too; 8.8.0 answered each request's
  length, row for row as 8.6.0 (`research/m4/slice3/results/reqsize-8.7.0.log`,
  `reqsize-8.8.0.log`). curl's own 8.8.0 `RELEASE-NOTES` list "CURLINFO_REQUEST_SIZE: fixed,
  add tests for transfer infos reported", curl bug 13269 (read from the 8.8.0 tarball). No
  release lies between 8.7.1 and 8.8.0, so the table holds the two measured, 8.7.0 and 8.7.1.
- **As built:** `request-size-unreliable`, in `(curl private transfer)`, holds `"8.7.0"` and
  `"8.7.1"`; `reported-request-size` answers `#f` for a transfer that ran on either, and the
  size libcurl counted elsewhere. A transfer refused while it was set up keeps 0 on every
  libcurl: chez-curl knows it sent nothing, without libcurl's count. `test-request` holds the
  table to its own copy, and the rule with synthetic versions, and pins each failure's size by
  the loaded libcurl's row.

## Amendment, 2026-10-28: the request size and the classes over TLS and HTTP/2 (M5 slice 3)

M5's retry policy reads a failure's class and its request size (ADR-0026). M4 measured the size
over plaintext and a stalled TLS handshake; M5 slice 3 measured each scenario a retry reads
over plaintext, TLS and HTTP/2 ([research](../research/m5/retry/)), through an engine of its
own per transfer, so no pool held a dead connection, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and
with GnuTLS, Guix's 8.20.0 and 8.23.0: 40 transfers each, a `get` and a `post` of each case.

- **The request size is 0 when nothing was sent, on all five:** a refused connect, 7, connect
  class, over plaintext and TLS, and a TLS handshake that stalled to the connect timeout, 28,
  timeout class, are 0; once the request went out, the size is above 0, over plaintext, TLS
  and HTTP/2 alike, a `post`'s 7-byte body counted.
- **The classes:** a close before the head, a reset before it and a reset after it are
  send-receive, 52 or 56; a stall before the head, at the transfer's bound, is a timeout, 28. A
  close over TLS answers 56, but 52 on 8.5.0 with OpenSSL; both are send-receive.
- **An HTTP/2 `GOAWAY` whose last stream is 0,** so the request was never processed, varies
  by class: 92, protocol, on 7.85.0; 56, send-receive, on 8.5.0, both builds; 16, protocol, on
  8.20.0 and 8.23.0. So a retry by class takes it on 8.5.0 alone.
- **An HTTP/2 `RST_STREAM` with `REFUSED_STREAM`** is resent by libcurl itself, 5 times more,
  then fails with 56, send-receive: the server counted six of each request, and its request
  size is six sends', on all five, a `post`'s among them (ADR-0026, amended).
