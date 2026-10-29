# ADR-0031: The high level's streams: `call-with-response-port`, a producer, and the call's bound

- **Status:** Accepted
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
