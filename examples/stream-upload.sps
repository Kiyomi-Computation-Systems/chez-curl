#!r6rs
;;; stream-upload.sps: with (curl), a PUT whose body is put a piece at a
;;; time while the transfer runs. The test server's /sink reads the body
;;; and answers one summary line; this prints a few of its fields.
;;; Start the test server first, from the repository's root, in a terminal
;;; of its own, and leave it running:
;;;   node tests/origin.mjs
;;; It prints one line, {"node":...,"http":"127.0.0.1:PORT","raw":...}, PORT
;;; a new one at each start, and serves until Ctrl-D. Then run this from the
;;; root, URL being http:// and the address after "http": (raw's and h2c's
;;; speak other protocols), with no trailing /:
;;;   scheme --libdirs src --program examples/stream-upload.sps URL
(import (rnrs) (curl))

(define base (cadr (command-line)))
(define size 300000)

;; piece : Natural Natural -> Bytevector
;; COUNT bytes of the body from AT on, byte i being i mod 251.
(define (piece at count)
  (let ((bytes (make-bytevector count)))
    (do ((i 0 (+ i 1))) ((= i count) bytes)
      (bytevector-u8-set! bytes i (mod (+ at i) 251)))))

;; field : String String -> String
;; The value of NAME= in LINE, a line of space-separated NAME=VALUE words.
(define (field line name)
  (let ((key (string-append name "=")))
    (let loop ((i 0))
      (cond ((> (+ i (string-length key)) (string-length line)) "")
            ((and (or (= i 0) (char=? (string-ref line (- i 1)) #\space))
                  (string=? key (substring line i (+ i (string-length key)))))
             (let end ((j (+ i (string-length key))))
               (if (or (= j (string-length line))
                       (memv (string-ref line j) '(#\space #\newline)))
                   (substring line (+ i (string-length key)) j)
                   (end (+ j 1)))))
            (else (loop (+ i 1)))))))

(define engine (make-curl-engine))

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

(let* ((response (curl-token-await token))
       (line (utf8->string (curl-response-body response))))
  (display (curl-response-status response))
  (newline)
  (display (string-append "method=" (field line "method")
                          " cl=" (field line "cl")
                          " bytes=" (field line "bytes")
                          " pattern=" (field line "pattern")))
  (newline))

(curl-engine-stop engine)
