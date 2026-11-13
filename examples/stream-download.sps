#!r6rs
;;; stream-download.sps: a response's body read from a port as it arrives,
;;; never held whole. The test server's /pattern/N sends N bytes, byte i
;;; being i mod 251; this counts them and checks each.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src --program examples/stream-download.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

;; pattern? : Bytevector Natural -> Boolean
;; Whether each byte of PIECE, which starts AT bytes into the body, is its
;; place in the body mod 251.
(define (pattern? piece at)
  (let loop ((i 0))
    (or (= i (bytevector-length piece))
        (and (= (bytevector-u8-ref piece i) (mod (+ at i) 251))
             (loop (+ i 1))))))

(call-with-http-session 'timeout-ms 10000
  (lambda (session)
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
