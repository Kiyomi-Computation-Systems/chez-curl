# Streams

A stream moves a body a piece at a time, so a big download or upload is
never held whole. Each level streams both ways.

## Reading a response as it arrives

**At the high level,** `call-with-response-port` makes the call, and hands
your procedure the response and a binary input port over its body:

```scheme example=examples/stream-download.sps
    (call-with-response-port session 'get (string-append base "/pattern/1000000")
      (lambda (response port)
        (display (http-response-status response))
        (newline)
        (let loop ((count 0) (ok #t))
          (let ((piece (get-bytevector-some port)))
            (if (eof-object? piece)
                (begin
                  (display count)
                  (display (if ok " bytes, pattern ok" " bytes, pattern bad"))
                  (newline))
                (loop (+ count (bytevector-length piece))
                      (and ok (pattern? piece count))))))))))
```

- **The response is its head:** status, headers, URL and history. Its body and
  timings are `#f`, and `http-response-text` refuses it: read the port.
- **Your procedure's values are the call's.** When it returns or escapes, the
  port is closed and the transfer cancelled. A Chez engine's expiry during the
  call is an escape too: once resumed, the port's reads raise that cancel,
  then Chez's error for a closed port.
- **`timeout-ms` bounds the whole call, your reading included,** as Go's
  `http.Client.Timeout` does. A reader slower than the bound meets
  `&http-timeout`. Read slowly by design? Pass a longer bound, or `#f`.
- **`stream-buffer` sets how much is held,** 64 KiB unless you say. A full
  buffer pauses the transfer.
- **Redirects and retries are decided as each response's head arrives,**
  its status line and headers. A redirect's or a retry's response is read
  whole into the history. One whose request sent a body is cut off as soon
  as its head arrives instead, and its history entry's body and timings are
  `#f`.
- **A retry that runs out of time** having sent nothing hands your procedure
  the response it retried, with a port over its body, read already. If that
  response was cut off at its head, the call raises `&http-timeout` instead.

**At the low level,** a request's `stream-buffer`, a size in bytes, makes its
token hand you the body in pieces:

```scheme fragment
(define token
  (curl-submit engine (make-curl-request "https://example.com/big" 'stream-buffer 65536)))

(when (curl-token-head-wait token 10000)     ; the final head came, or the end
  (let ((head (curl-token-head token)))      ; #f when the transfer failed first
    (when head (display (curl-head-status head)))))

(let loop ()
  (let ((piece (curl-token-next-piece token 10000)))
    (when (bytevector? piece)                ; the eof object at the end, #f at the bound
      (loop))))

(curl-token-outcome token)                   ; the response, its body #f, or the failure
```

- **A 1xx head and a proxy's `CONNECT` head are passed over:** the head is the
  final one.
- **Each wait answers as data** and never raises the transfer's failure: the
  outcome holds it.
- **`curl-token-body-port`** reads the pieces through a binary input port,
  made once per token. At the end it answers the eof object, and for a
  failure it raises the failure, every time.

**The rules both levels share:**

- **A full buffer pauses the transfer,** and reading resumes it. Over
  HTTP/1.1 the server then waits too. Over HTTP/2, a paused stream that shares
  its connection with a busy one keeps receiving into libcurl's memory, up to
  its window. Where no stream shares a connection, see
  [Choosing the HTTP version](http-version.md#connections).
- **The timeout runs while you are not reading.**
- **Read with `get-bytevector-some` or `get-u8`.** When the transfer fails,
  the read raises its failure, every time after, and a `get-bytevector-n`,
  `-n!` or `-all` call loses the bytes it had read.
- **The port is its thread's:** read and close it on the thread that made
  it, the call's at the high level. Another thread that tries is refused: at
  the low level it raises `&curl-wrong-thread`, and at the high level it is
  an assertion violation from the call. The one exception is bytes the port
  had already buffered, which any thread's read takes, so keep reads to the
  one thread.
- **Closing the port cancels the transfer.** A low-level port you never close
  leaves its transfer paused until its timeout, or its engine's stop.
- **One answer per transfer.** A stream is refused beside an `Expect` header
  holding `100-continue`, whose 417 would make libcurl send the request twice,
  `stream-with-rounds`; and beside Digest credentials, `digest-with-stream`.
  libcurl's own resend after a dead connection can still make a second
  request, which brings one head alone.

## Sending a body as it is produced

**At the high level,** a call's `body` may be a producer: a procedure of no
arguments that answers the next bytes, or the eof object at the end.
`body-length` sends its length; without it the body goes chunked over
HTTP/1.1, and as plain DATA frames over HTTP/2.

```scheme fragment
(call-with-http-session
 (lambda (s)
   (call-with-port (open-file-input-port "big.bin")
     (lambda (file)
       (http-put s "https://example.com/big.bin"
                 'body (lambda () (get-bytevector-some file))   ; the eof object ends it
                 'timeout-ms 60000)))))
```

- **It runs on your thread,** only once libcurl asks for the body, and never
  after it answered the eof object. It answers a bytevector of a byte or
  more, or the eof object; anything else is an assertion violation.
- **The length is checked.** A body short of `body-length` fails the
  transfer, `body-length-mismatch`; a piece past it raises that reason as
  `&http-request-error`, before any of it is sent.
- **It is sent at most once.** Once libcurl has asked for it, no retry takes
  the call, and a redirect that would resend it raises `body-not-replayable`.
- **Its raise leaves the call as raised,** once the transfer is cancelled.
- **Through `call-with-response-port`, the port feeds the producer while you
  read,** so a server that answers as the body arrives gets the rest. It feeds
  only when no bytes are waiting: a server that sends faster than you read
  holds the upload back, and a procedure that never reads, and never returns,
  starves it. A producer's raise inside the port's read sticks: every later
  read raises it. A producer that reads its own port is refused.
- **A request group takes no producer:** `go` and `http-parallel` refuse one,
  `stream-in-group`.

**At the low level,** a request's `body 'stream` makes its token take the
body from your puts, into a buffer of 64 KiB. `body-length` sends its
length; `#f` sends it chunked over HTTP/1.1, as plain DATA frames over HTTP/2.
A `body-length` beside a body that does not stream is refused,
`body-length-without-stream`.

```scheme example=examples/stream-upload.sps
(define token
  (curl-submit engine
               (make-curl-request (string-append base "/sink?key=example-upload")
                                  'method 'put 'body 'stream 'body-length size
                                  'timeout-ms 10000)))

;; Each put waits while the token's buffer is full; the end says the body
;; is whole.
(let loop ((at 0))
  (when (< at size)
    (let ((count (min 65536 (- size at))))
      (curl-token-put-piece! token (piece at count))
      (loop (+ at count)))))
(curl-token-end-body! token)
```

- **A put waits while the buffer is full.** Give it a bound, in milliseconds,
  and it answers `#f` when the bound passes. `curl-token-room-wait` answers
  `#t` once libcurl has asked for the body and there is room.
- **`done` means the transfer has ended:** a put that answers `done` took
  nothing, and `curl-token-outcome` tells how it ended.
- **The length is checked.** An end short of `body-length`, or a piece past
  it, fails the transfer, `body-length-mismatch`; the put past it raises.
- **`curl-token-body-count`** tells what your puts committed to the buffer,
  not what reached the server.

**The rules both levels share:**

- **It is sent at most once, on a fresh connection.** A piece handed to
  libcurl is gone, so a resend libcurl wants after that, for a dead connection
  or a refused HTTP/2 stream, fails the transfer, `body-not-replayable`. The
  upload never reuses a pooled connection: each opens one, and over TLS a
  handshake. Once it ends, a later transfer may reuse that connection.
- **The timeout runs while you are not putting.**
- **An early answer ends the upload.** A server may answer, a 413 say, before
  the body is sent; then every later put answers `done`. When the transfer
  ends, and whether libcurl still asks for the rest, varies by libcurl, as
  does whether an early 200 can end it as a success with the body cut. A
  server that must have the whole body should say so in its answer.
- **Over HTTP/2, a transfer that streams both ways sends only while you read**
  the response's pieces: else the upload stops at the peer's window.
- **Over HTTP/2, pass a `timeout-ms`:** on some libcurls an answer that comes
  before the body is sent whole never ends the transfer.

[What varies by libcurl](libcurl-versions.md#streams) has each of these by
version.
