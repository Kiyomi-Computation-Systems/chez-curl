# ADR-0032: A streamed body is sent at most once

- **Status:** Accepted; amended 2026-10-29: after the plan's review, a seek callable refuses the
  rewind, and after its second review, decision 3's redirects
- **Date:** 2026-10-29
- **Scope:** chez-curl v1, a request whose body streams (ADR-0030), in `(curl)` and
  `(http-client)`, from M6
- **Settles:** whether a streamed request body may be sent twice, by libcurl's own resend, a
  retry or a redirect. The M6 plan raised it, and the maintainer chose on 2026-10-29, the
  recommended option.
- **Related:**
  - [ADR-0026](0026-retries-off-unless-asked.md): retries, and libcurl's own resend;
  - [ADR-0020](0020-a-ci-lane-on-the-current-libcurl.md): 8.23.0's unchecked reuse of a pooled
    connection;
  - [ADR-0030](0030-streams-are-request-keys-and-token-operations.md) and
    [ADR-0031](0031-the-high-levels-streams.md): the streams, and the producer.

## Context

A whole body is a bytevector libcurl holds, so libcurl can send it again. A streamed body is
taken from a producer once: a piece handed to libcurl is gone from chez-curl.

libcurl resends a request on its own when a reused connection dies before any response byte
arrives, and when an HTTP/2 server refuses the stream (ADR-0026, amended 2026-10-28). To send a
read callback's body again it must rewind it, by `SEEKFUNCTION`. The M6 plan measured it
([research](../research/m6/pause/)) on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS,
Guix's 8.20.0 and 8.23.0, two runs each:

- **a pooled connection the server closed after reading the whole request:** a streamed `POST`
  with no `SEEKFUNCTION` fails with 65, `CURLE_SEND_FAIL_REWIND`, on all five; with one that
  answers `CURL_SEEKFUNC_CANTSEEK`, 65 too; with one that restarts the producer, the server
  receives the request twice;
- **a pooled connection the server closed cleanly 200 ms after its last response:** 0 on a new
  connection on four libcurls; 65 on 8.23.0, which reuses a connection pooled under 1 s before
  without checking it;
- **an HTTP/2 stream refused with `REFUSED_STREAM` after 32 KiB of DATA:** 65 without a seek on
  8.5.0, 8.20.0 and 8.23.0, 56 on 7.85.0; the server's count 1;
- **`CURLOPT_FRESH_CONNECT` on the streamed `POST`:** every one of 120 runs ended 0, on a new
  connection, with one request at the server and no seek;
- **`CURLOPT_PREREQFUNCTION`** runs once per attempt, after any seek. Where a seek restarted the
  producer, answering `CURL_PREREQFUNC_ABORT` on the second call ended the transfer with 42, and
  the server saw one request. With no seek, or one that answers `CANTSEEK`, it ran once: the
  failed rewind ends the transfer first (the amendment below).

Read in 8.7.1's source: its follow step drops the result of the reset that rewinds the body
(`lib/transfer.c:915`), so a resend may read on from mid-stream without rewinding, and send a
request whose body is not the one given. The Mac measured it on the plan's PR, 2026-10-29
([log](../research/m6/pause/results/mac-8.7.1-split.log)): after a reset 81,920 bytes into an
8 MiB body, libcurl logged the failed rewind, 65, and sent a second request carrying the body's
last 7,389,184 bytes, which ended 26 when the body ran out; an HTTP/2 refused stream reached the
server twice. The prerequest callable ran for each second attempt, before its head was sent.

## Decision

1. **A transfer whose body streams never goes on a pooled connection:** it sets
   `FRESH_CONNECT`, which chez-curl owns. So a connection that died in the pool costs it
   nothing.
2. **A seek callable refuses the rewind, and a `PREREQFUNCTION` refuses a second attempt,** each
   once the read callable has handed libcurl a byte (amended after the plan's review). Each then
   records `body-not-replayable`, as the write callable records `body-limit`, and answers
   `CURL_SEEKFUNC_CANTSEEK` or `CURL_PREREQFUNC_ABORT`, so a resend libcurl wants, for a dead
   connection, an HTTP/2 refused stream, or 8.7.1's without a rewind, ends the transfer with
   chez-curl's own refusal, alike on every libcurl: never a body sent twice, nor from its middle.
   Before the first byte is handed, a rewind is a no-op, so each answers OK, and libcurl's
   resend goes on, sending nothing twice.
3. **The high level never sends a streamed body again** once its producer has been called, or
   libcurl had asked for the body by a head (amended after the plan's second review):
   - no retry takes such a call again, whatever its policy says;
   - a redirect whose next request keeps the body raises `&http-redirect-error`, a new reason,
     `body-not-replayable`: a 307 or 308, which keeps every method's, and a 301 or 302 of every
     method but `post`, which M5 follows with its body (the M5 plan, §3.4);
   - a redirect that drops the body, a `post` through a 301 or 302 and any method through a 303,
     is followed, by M5's rules.

   A call whose producer was never called, a refused connect among them, is retried as any call
   is.

### Rejected

- **Replaying what still fits:** a buffer of the producer's pieces up to a bound, and a seek
  that replays from it while all that was sent is held. Pooled connections would stay usable,
  at the cost of memory and of a replay path in both libraries.
- **Restartable producers:** a second key giving a thunk that restarts the producer, which
  would enable the seek, retries and 307 and 308. It moves the contract to the caller, and the
  call without one still needs this record's rules.

## Consequences

- **A streamed upload costs a connection of its own,** and over TLS a handshake. The README says
  so.
- **The transfer gains two callables, the seek's and `PREREQFUNCTION`'s,** beside the read,
  write and header ones, each `__collect_safe` and locked (ADR-0013).
- **A streamed upload's failure says why:** `body-not-replayable` from either library, never
  libcurl's 65 or 56, which name a rewind, nor its 42.

## Amendment, 2026-10-29: after the plan's review, a seek callable refuses the rewind

Decision 2 first read: "It has no `SEEKFUNCTION`, and a `PREREQFUNCTION` refuses any second
attempt." The plan's review (Opus, read-only) found that it could not work, from the probe's own
logs (`research/m6/pause/results/round2/`): to resend a read callback's body libcurl rewinds it
before the next attempt reaches the step where `PREREQFUNCTION` runs, and a failed rewind ends the
transfer there. On all five libcurls, a pooled connection the server closed after reading the
request gave `prereq_calls=1` and 65 with no seek, and `prereq_calls=1`, `seeks=1` and 65 with a
seek that answers `CANTSEEK`; an HTTP/2 refused stream gave `prereq_calls=1` and 65, or 56 on
7.85.0. The record's 42 came only where the seek had restarted the producer. So the transfer
would have ended with libcurl's 65, or 56, never chez-curl's refusal.

**Decided by the maintainer, 2026-10-29, the recommended option:** a seek callable, which
records `body-not-replayable` and answers `CANTSEEK` once the read callable has handed libcurl a
byte, and answers OK before that, when the rewind is a no-op; the transfer's recorded reason wins
over libcurl's code, as `body-limit`'s does. `PREREQFUNCTION` stays, by the same test, for a
resend that skips the rewind: 8.7.1's dropped result, read in its source, and an HTTP/2 stream
redone over HTTP/1.1. `FRESH_CONNECT` stays.

**After the plan's second review,** the same day: the prerequest callable is not redundant
beside the seek, since 7.85.0 rewinds only once body bytes were sent, and drops on a resend the
bytes handed but not sent (`curl-7.85.0/lib/transfer.c:1910-1916`), so a refused HTTP/2 stream
in that window resends with no seek at all; the seek answers OK only for an offset of 0 from
`SEEK_SET`; and decision 3 now counts libcurl's ask by a head as the producer called, and names
every redirect that keeps the body, a 301 or 302 of a `put`, `patch` or `delete` among them.

**Rejected:** a seek that always refuses, and a prerequest callable that refuses every second
attempt, which would also refuse libcurl's resends of a body nothing was taken from; and no seek
callable, a streamed upload's 65 read as `body-not-replayable`, which 7.85.0's 56 on an HTTP/2
refused stream would escape.
