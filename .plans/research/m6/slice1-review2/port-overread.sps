#!r6rs
;;; M6 slice 1's second review: the port's thread rule, for another thread's
;;; read that asks for more than Chez's buffer holds. The fix round's docs
;;; say another thread's read raises "once the port's own buffer is empty"
;;; (README.org), and that bytes the port buffered "go to whichever thread
;;; reads them". Here the owner reads one byte with get-u8, which fills the
;;; port's buffer with N bytes; another thread asks get-bytevector-n for
;;; N + 10, which must call read! past the buffer; then the owner reads one
;;; byte. The body is the pattern, byte i being i mod 251. Prints:
;;;
;;;   (owner FIRST N)              the first byte, and what Chez buffered
;;;   (other ANSWER)               (raised wrong-thread) or (returned LENGTH)
;;;   (owner-next BYTE EXPECTED)   the owner's next byte, and byte 1's value
;;;
;;; Run from the repository's root, in the container:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m6/slice1-review2/port-overread.sps' < /dev/null
(import (chezscheme) (curl) (curl-testing))

(define (show d) (write d) (newline) (flush-output-port (current-output-port)))

(define (on-thread thunk)
  (let ((mx (make-mutex)) (answer #f))
    (fork-thread (lambda ()
                   (let ((a (guard (e ((curl-wrong-thread? e) '(raised wrong-thread))
                                      (#t (list 'raised (condition-message e))))
                              (list 'returned (let ((v (thunk))) (if (bytevector? v) (bytevector-length v) v))))))
                     (with-mutex mx (set! answer a)))))
    (let loop ((i 0))
      (or (with-mutex mx answer)
          (and (< i 5000) (begin (sleep (make-time 'time-duration 1000000 0)) (loop (+ i 1))))))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'http))
          (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/pattern/600"))
          (engine (make-curl-engine))
          (t (curl-submit engine (make-curl-request url 'proxy #f 'timeout-ms 20000 'stream-buffer 65536)))
          (port (curl-token-body-port t))
          (first (get-u8 port))
          (n (binary-port-input-count port)))
     (show (list 'owner first n))
     (show (list 'other (on-thread (lambda () (get-bytevector-n port (+ n 10))))))
     (show (list 'owner-next (get-u8 port) 1))
     (close-port port)
     (curl-engine-stop engine))))
