# ADR-0022: libcurl's codes are classed as condition types

- **Status:** Accepted; amended 2026-10-26: after the plan's review
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
