#!r6rs
;;; The port's thread rule, against Chez's own buffer (M6 slice 1's review).
;;; curl-token-body-port's docstring says a read from another thread raises
;;; &curl-wrong-thread. The check sits in read!, and Chez calls read! only
;;; when the port's own buffer is empty. Here the owner reads one byte with
;;; get-u8, which fills the port's buffer; then another thread reads with
;;; get-u8, get-bytevector-n and lookahead-u8. Prints one line per read:
;;;
;;;   (owner FIRST-BYTE)
;;;   (other OP ANSWER)   ANSWER (raised wrong-thread) or (returned VALUE)
;;;
;;; Run from a tree's root, in the container:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m6/slice1-review/port-thread.sps' < /dev/null
(import (chezscheme) (curl) (curl-testing))

(define (show d) (write d) (newline) (flush-output-port (current-output-port)))

(define (on-thread thunk)
  (let ((mx (make-mutex)) (answer #f))
    (fork-thread (lambda ()
                   (let ((a (guard (e ((curl-wrong-thread? e) '(raised wrong-thread))
                                      (#t (list 'raised (condition-message e))))
                              (list 'returned (thunk)))))
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
          (port (curl-token-body-port t)))
     (show (list 'owner (get-u8 port)))
     (show (list 'other 'get-u8 (on-thread (lambda () (get-u8 port)))))
     (show (list 'other 'lookahead-u8 (on-thread (lambda () (lookahead-u8 port)))))
     (show (list 'other 'get-bytevector-n-10 (on-thread (lambda () (get-bytevector-n port 10)))))
     (close-port port)
     (curl-engine-stop engine))))
