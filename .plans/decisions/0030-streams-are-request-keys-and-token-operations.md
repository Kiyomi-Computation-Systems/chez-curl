# ADR-0030: A streamed body is a request's key, and the token's operations

- **Status:** Accepted; amended 2026-10-29: no multiplexing on 8.7.0 and 8.7.1, from the Mac's run
- **Date:** 2026-10-29
- **Scope:** chez-curl v1, `(curl)`, from M6
- **Settles:** how the low level offers a body streamed in either direction (brief §2 item 7,
  §5 and §8's M6). The M6 plan raised it, and the maintainer chose on 2026-10-29, the
  recommended option.
- **Related:**
  - [ADR-0012](0012-engine-thread-owns-every-handle.md), decision 4: a full buffer pauses its
    transfer, and the consumer resumes it by message;
  - [ADR-0021](0021-completions-through-a-mailbox.md): completions through a mailbox;
  - [ADR-0023](0023-the-public-request.md): the request is made from a property list, and is
    data;
  - chez-http-server's decisions 0013 and 0036: a body read a piece at a time, and through a
    port.

## Context

The low level carries a whole body each way (ADR-0023): the write callback copies every chunk
into the token, and a request body is a bytevector libcurl copies. M6 streams them, with
backpressure through `CURL_WRITEFUNC_PAUSE`, `CURL_READFUNC_PAUSE` and `curl_easy_pause`, which
the engine calls on its own thread (ADR-0012).

The M6 plan measured the premise first ([research](../research/m6/pause/)), through a C probe
whose loop steps as the engine does, against a server with plaintext, TLS and HTTP/2 faces, on
7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, two runs each:

- a chunk the write callback refuses comes back whole, inside `curl_easy_pause`, every byte in
  order, on all five; every call held 16,384 bytes at most, at any `BUFFERSIZE`;
- over HTTP/1.1 a paused transfer stops reading its socket: libcurl's live bytes did not grow
  during a 2 s hold, and the server's writes stalled after 2,637,824 to 2,772,992 bytes,
  plaintext and TLS, the kernel's buffers, for the hold's 2 s;
- a read callback that answers `CURL_READFUNC_PAUSE` resumes after `curl_easy_pause`, its body
  whole and in order, over every face, length-framed and chunked.

chez-http-server, the family's server, hands a handler its body as pieces, each a bytevector
or the eof object, and as a custom binary input port over them (its decision 0036).

## Decision

1. **A request says whether each body streams, by keys, and stays data.**
   - **The response:** a key names the bytes the token buffers, `stream-buffer`, a positive
     integer; `#f`, the default, keeps the whole body, as before.
   - **The request body:** `body` may be `stream`, with `body-length`, a natural or `#f` for
     none.

   Each submit of such a request makes its own stream, so a request may be submitted twice.
2. **The one `curl-submit` answers the one kind of token,** which gains the stream's
   operations:
   - **the head:** a wait for the response's head, and the head read as data: its status, its
     version and its headers;
   - **the response's pieces:** the next piece, a bytevector of a byte or more, or the eof
     object at the end, within a bound; and a custom binary input port over them;
   - **the request's pieces:** a piece put, waiting while the buffer is full, and the body's
     end.
3. **The engine's callbacks only copy, and signal** (ADR-0012, decision 4). A full response
   buffer pauses its transfer, and so does an empty request buffer. A take that drains the
   buffer, or a put that fills it, resumes the transfer by a message, the fourth after submit,
   cancel and stop, and the engine calls `curl_easy_pause` itself.
4. **Every wait is a bounded poll, as every wait is** (ADR-0013, amended 2026-10-25), and
   answers as data: a piece, the end, or that its bound passed. None raises the transfer's
   failure, which the token's outcome holds, so a caller's interrupt handler's raise is never
   read as the stream's (`traps.md`). The port alone raises it, at a read past the last piece,
   as a port must.

5. **Below the token, the bound is libcurl's, and documented.** Streams share connections as
   every transfer does. Over HTTP/1.1 a paused transfer stops reading its socket. Over HTTP/2, a
   paused stream whose connection carries an active stream keeps receiving into libcurl's
   memory, up to the stream's flow-control window. Measured in 5 s of a pause beside a running
   stream, libcurl's live bytes reached 66.9 MB on 7.85.0, 10.6 MB on 8.5.0, 21.1 MB on 8.20.0
   and 33.5 MB on 8.23.0, as the server's writes stopped at 33,619,968, 10,551,296, 20,971,520
   and 20,971,520 bytes; alone on its connection, 75 to 154 KB. libcurl caps what it holds for a
   paused transfer at 64 MiB, failing it with 27 or 100 beyond; no lane reached the cap, and by
   its source Apple's 8.7.1, whose window stays open, can (the M6 plan, §2.2). README.org says
   so, and M7's HTTP/2 work revisits it. Decided by the maintainer, 2026-10-29, the recommended
   option.

The plan names each procedure and key, and the slices may revise the names.

### Rejected

- **For the bound below the token:** a streamed transfer that never shares its connection, at
  the cost of a connection and a TLS handshake per streamed call; and a streamed transfer over
  HTTP/1.1 alone, which never uses HTTP/2.
- **A separate stream submit,** `curl-submit-stream`, answering a stream token of its own. It
  leaves the request alone, but makes two kinds of token, which the waits and the mailbox must
  each take.
- **Pieces through the mailbox,** each a notice the caller acknowledges to release
  backpressure. It needs no new wait, but every consumer must drain a mailbox and acknowledge
  each piece.

## Consequences

- **The engine gains a message, and its turn a step:** resume, carried out after the cancels
  and before the perform.
- **The transfer gains a read callable and a header callable** beside `write-body`, and the
  seek and prerequest callables ADR-0032 adds, each `__collect_safe` and locked, in
  `(curl private transfer)` alone (ADR-0013).
- **A token that streams holds at most its buffer or one chunk, whichever is more,** and the
  piece a reader has in hand. What libcurl holds below it is libcurl's, and the M6 plan records
  it by protocol and version.
- **A request built for a whole body is unchanged,** and so is every M4 and M5 caller.

## Amendment, 2026-10-29: no multiplexing on 8.7.0 and 8.7.1, from the Mac's run

Decision 5 documented the memory a paused HTTP/2 stream holds beside an active one, as libcurl's
bound. The Mac then ran the plan's pause probe against Apple's 8.7.1, on the plan's PR
([log](../research/m6/pause/results/mac-8.7.1.log)), and the bound turned out to be no bound
there:

- **A paused stream beside an active one filled libcurl's 64 MiB cap and failed the connection:**
  its live bytes reached 67,187,470, the active stream ended 56 after 234 ms, and the paused one
  ended 18 once resumed, the server's writes stopping at 73,465,856 bytes. The source reading
  had predicted the open window (`curl-8.7.1/lib/http2.c:1255-1259`); the probe showed it takes
  the siblings with it.
- **A write callback's error on one HTTP/2 stream failed its sibling:** the stream that refused
  ended 56, and the other, on the same connection, 16 (curl #13292, fixed in 8.8.0, read in the
  source reading). chez-curl's body-limit refusal is such an error, so on the Mac a body limit on
  one HTTP/2 call could fail another call sharing its connection, before M6 too.
- **On separate connections** both ended 0, and the paused stream held 148,703 bytes.

**Decided by the maintainer, 2026-10-29, the recommended option:** when the loaded libcurl is
8.7.0 or 8.7.1, the engine sets `CURLMOPT_PIPELINING` to 0 on its multi handle, so every
HTTP/2 transfer there has a connection of its own. A pause stays bounded, and one stream's
error reaches no other. Elsewhere decision 5 stands. M6's first slice builds it, and measures it
on the Mac.

**Rejected:** a streamed transfer over HTTP/1.1 on 8.7.x, which bounds the pause but leaves the
body limit's error failing siblings; and documenting it, which leaves both.
