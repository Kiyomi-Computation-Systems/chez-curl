#!r6rs
;;; child-probe.sps: an example's shape, for measuring what a child costs
;;; (M8 slice 4's measurement; not an example). One GET of URL/status/200
;;; through (http-client), printing the status and the body's text, then
;;; whether Valgrind is mapped into this process: (valgrind #t) when
;;; /proc/self/maps names a vgpreload library.
;;;   child-probe.sps URL
(import (rnrs) (http-client))

(define base (cadr (command-line)))

(call-with-http-session 'timeout-ms 10000
  (lambda (s)
    (let ((r (http-get s (string-append base "/status/200"))))
      (display (http-response-status r)) (newline)
      (display (http-response-text r)))))

(define (under-valgrind?)
  (let ((text (guard (e (#t ""))
                (call-with-port (open-file-input-port "/proc/self/maps" (file-options)
                                                      (buffer-mode block) (native-transcoder))
                  get-string-all))))
    (let loop ((i 0))
      (cond ((> (+ i 9) (string-length text)) #f)
            ((string=? (substring text i (+ i 9)) "vgpreload") #t)
            (else (loop (+ i 1)))))))

(write (list 'valgrind (under-valgrind?))) (newline)
