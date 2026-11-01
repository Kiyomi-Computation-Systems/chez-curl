# ADR-0031: The high level's streams: `call-with-response-port`, a producer, and the call's bound

- **Status:** Accepted; amended 2026-10-31: a streamed call that sends a body cancels each hop at
  its head; libcurl's HTTP/2 3xx that never ends is documented, pinned and reported; and a
  producer's piece past `body-length` is `&http-request-error`, `body-length-mismatch`; and a
  streamed call whose retry runs out of time after a hop cancelled at its head fails with
  `&http-timeout`
- **Date:** 2026-10-29
- **Scope:** chez-curl v1, `(http-client)`, from M6
- **Settles:** three questions the M6 plan raised about streaming at the high level. The
  maintainer chose each on 2026-10-29, each the recommended option.
- **Related:**
  - brief §6.3, the third piece of thread sugar, `call-with-response-port`;
  - [ADR-0025](0025-the-high-levels-surface.md): the high level's surface;
  - [ADR-0030](0030-streams-are-request-keys-and-token-operations.md): the low level's streams;
  - chez-http-server's decisions 0013 and 0033: a body of unknown length is a thunk, and a
    sized body is a producer with a declared length.

## Context

The brief sketches `(call-with-response-port s req (lambda (port) ...))`, closing what it
opens. M5's calls take a method, a URL and keys, and the high level has no request record
(ADR-0025). M5's `body` is a bytevector or a string.

The M6 plan measured, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0
and 8.23.0 ([research](../research/m6/pause/)):

- **libcurl's `TIMEOUT_MS` runs while a transfer is paused,** and ends it with 28 at the
  bound: 999 to 1,007 ms for a bound of 1,000 ms, on every face. A body that has arrived whole
  but waits on its consumer times out too: the transfer cannot finish while paused.
- **A body that ends short of its declared length:** with `Content-Length` 1,000 and 500 bytes
  then the end, 7.85.0 and 8.5.0 stall until the bound, 28 at about 3,005 ms for a bound of
  3,000; 8.20.0 and 8.23.0 fail at once with 26. Over HTTP/2, 7.85.0 and 8.5.0 fail with 92.
- **A read callback that writes past the length:** 1,500 bytes into a `Content-Length` of
  1,000 sends the surplus on 7.85.0 and 8.5.0, over HTTP/1.1, and answers 0; 8.20.0 and 8.23.0
  offer 1,000 bytes at most.

chez-http-server streams a response body of unknown length from a thunk that answers a
bytevector or the eof object, "as `get-bytevector-some` does", and a sized body is that
producer with a declared length (its decisions 0013 and 0033).

## Decision

1. **`(call-with-response-port S METHOD URL KEY VALUE ... PROC)`** makes the call, as
   `http-request` takes one, and calls PROC with two arguments: the response, whose status,
   headers, URL and history are known and whose body is `#f`, and a binary input port over the
   body.
   - Redirects and retries are decided as each head arrives, by M5's rules. A hop's body is
     read whole into the history.
   - When PROC returns or escapes, the port is closed, and the transfer is cancelled if it is
     still running. The call answers PROC's values.
2. **`body` also takes a producer:** a procedure of no arguments, called on the caller's
   thread whenever the transfer has room, that answers a bytevector of a byte or more, or the
   eof object at the end. `(lambda () (get-bytevector-some port))` streams a port.
   - `body-length` gives the length, sent as `Content-Length`. Without it, HTTP/1.1 sends the
     body chunked, and HTTP/2 as DATA frames.
   - chez-curl counts the bytes: a producer that ends short of `body-length`, or gives more,
     fails the call by chez-curl's own refusal, alike on every libcurl, before libcurl's
     answer, a stall, 26, 92 or a surplus sent, can differ.
3. **A call's `timeout-ms` bounds the whole call, reading included,** as M5's rule says: from
   its start to its body's end, the consumer's time between reads among it. A consumer slow by
   design passes a longer bound, or `#f`.

### Rejected

- **For the response:** PROC called with the port alone, as the brief sketched, the head read
  from it by an accessor; and an `http-response` whose body is a port for this form alone, which
  makes the field's type depend on how the call was made.
- **For the body:** a binary input port, which the call reads; and both a port and a producer.
  A producer takes a port in one line, and is the family's form.
- **For the bound:** a bound until the head alone, with the body unbounded unless the caller
  adds an idle bound; and a clock the engine keeps, stopped while the consumer holds the
  transfer paused, which libcurl's own timeout does not do.

## Consequences

- **A streamed call blocks its caller's thread,** as every call does (brief §2 item 3). The
  producer and PROC run there, never on the engine's (ADR-0012).
- **A producer that blocks blocks the call,** and any group's other calls with it.
- **A consumer slower than the bound fails with `&http-timeout`.** README.org says so beside the
  form, with Go's `http.Client.Timeout` as the precedent.
- **Whether a streamed body can be sent twice,** by a retry, by a 307 or 308, or by libcurl's own
  resend, is the M6 plan's, settled separately.

## Amendment, 2026-10-31: a call that sends a body cancels each hop at its head

Decision 1 has a hop's body read whole into the history. M6 slice 3 measured, before it built,
how a hop's transfer ends while its request still owes a body (the M6 plan, §6.1, as measured;
[research](../research/m6/slice3/)):

- **On 8.20.0 and 8.23.0, over HTTP/2, a 3xx that arrives before the request's body is sent
  whole never ends the transfer.** A 301, 302, 303, 307 or 308 waited to the bound, 40 runs of
  40, where a 413 and a 503 ended at once. libcurl logs "HTTP error before end of send, stop
  sending", aborts the upload, and holds the whole response: "Operation timed out after 5006
  milliseconds with 10 out of 10 bytes received". A whole body meets it as a streamed one does,
  `Location` or not, and so does curl's own command-line tool, 8.20.0's and 8.23.0's alike
  ([verify](../research/m6/slice3/verify/results/)). 7.85.0 and 8.5.0 end such a hop.
- **7.85.0 and 8.5.0 end a hop libcurl had asked the body for only at the next put,** so a hop
  never fed waits to the bound, 40 of 40 on 7.85.0. And a hop whose head came before the first
  ask, never fed, waits there too when the server holds its own body until it has the request's.
- **Cancelling a hop once its head's `Content-Length` had arrived** ended each of 80 hops within
  4.158 ms of its head, and its next request came back whole.

**Decided by the maintainer, 2026-10-31, the recommended option:** a streamed call that sends a
body, a producer's or a whole one, cancels each hop at its head. A streamed call is one through
`call-with-response-port`, or one whose body is a producer; `http-request` with a whole body
keeps M5's drive, unchanged, as the second decision below keeps M5's path. Once the head decides a redirect the
call follows or a retry it takes, the drive cancels the hop's transfer and reads none of its
body; the hop's history entry holds its status, version, headers and URL, with a body and
timings of `#f`, as the response handed to PROC has. A call that sends no body reads each hop
whole, as decision 1 says. So no hop is fed: its next request either drops the body, or sends it
from the start, libcurl never having asked for it (ADR-0032).

**And libcurl's defect is documented, pinned by version and reported, not worked around**
(decided the same day, the recommended option). Where no hop takes the response, a final 3xx
that arrives over HTTP/2 before the body is sent whole ends only at the call's bound on 8.20.0
and 8.23.0, and never without one; `http-request`'s whole body meets it the same way, as
`(curl)`'s token does. 7.85.0 does the same after an early HTTP/2 200 while a whole body is
owed, as it does for a streamed one (the plan's §3.7). README.org says to pass `timeout-ms`; the
plan's §3.7 has the rows, and a test pins them by version. A curl bug report is drafted, for the
maintainer to file ([draft](../research/m6/slice3/verify/curl-bug-report.md)).
`KEEP_SENDING_ON_ERROR` ended the 3xx's wait on 8.20.0, 4 runs of 4, but it sends the rest of
every body a server answered early, and is not measured against a server that closes after a
413.

## Amendment, 2026-10-31: a producer's piece past `body-length`, and when its end is asked for

M6 slice 3's build found that decision 2's "gives more, fails the call" could not hold by
asking the producer only when `curl-token-room-wait` answers `#t`. Once its puts had taken the
length, the server's answer could end the transfer before libcurl had room again; `room-wait`
then answered `done`, the producer was never asked for its end, and one that would have given
more passed as a 200. That happened on raw, raw-tls and HTTP/2 with the drive's waits at their
whole bound, and once natively on raw-tls
([research](../research/m6/slice3-build/results/), `end-at-length-*`).
So the drive asks the producer for its end at once, in the step whose put takes the length, and
again at the final head, room or none. Libcurl has asked for the body by then, so the producer is
still never called before its first ask.

**Decided by the maintainer, 2026-10-31, the recommended option:** a producer's piece past
`body-length` is refused before any of it is put, as `&http-request-error` with field `body` and
reason `body-length-mismatch`, compounded with the call's `&http-exchange`, raised once its
transfer is cancelled. It mirrors the low level, where a put past the length raises
`&curl-request-error` with that reason. A body short of its length still fails as the low
level's `&curl-transfer-error`, `body-length-mismatch`, through `curl-token-end-body!`, compounded
with the call's `&http-exchange`. Both carry the one reason.

## Amendment, 2026-11-01: a retry that runs out of time after its hop was cancelled

M5's rule answers, when no time is left for a retry of a response, the response the retry would
repeat. A streamed call that sends a body cancels that hop at its head (above), so the response
it would repeat has no body: M6 slice 3's adversarial review found `http-request` with a
producer answering one whose body was `#f`, which `http-response-text` refuses and M5's callers
never meet. It is reachable when the wait overshoots the bound, the retry decided at the head
having fitted, and when the retry's transfer meets the bound's 28 having sent nothing.

**Decided by the maintainer, 2026-11-01, the recommended option:** such a call fails with
`&http-timeout`, as a call does with no time left for any request; `call-with-response-port`
then never calls PROC. A call that read its hop's body whole keeps M5's rule.

