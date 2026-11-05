#!r6rs
;; build/m7s4b/probe/failed-jar-state.sps: a jar's state read as soon as a
;; token its engine's failure completed is done, and again once the
;; engine's stop has returned, 100 times, on an engine whose fault is
;; planted at take-out!'s free step. Prints how often each read saw each
;; state.
(import (rnrs) (rnrs mutable-pairs) (only (chezscheme) iota) (curl) (curl-testing)
        (only (curl private engine) make-faulty-curl-engine curl-cookie-jar-state))
(define (tally xs)
  (fold-left (lambda (acc x) (let ((hit (assq x acc))) (if hit (begin (set-cdr! hit (+ (cdr hit) 1)) acc) (cons (cons x 1) acc))))
             '() xs))
(call-with-origin
 (lambda (o)
   (let* ((port (number->string (cdr (origin-face o 'http))))
          (runs (map (lambda (i)
                       (let* ((e (make-faulty-curl-engine 'free))
                              (jar (make-curl-cookie-jar e))
                              (t (curl-submit e (make-curl-request (string-append "http://a.localhost:" port "/cookies?key=s")
                                                                   'cookie-jar jar 'proxy #f 'timeout-ms 10000))))
                         (curl-token-wait t 15000)
                         (let ((early (curl-cookie-jar-state jar)))
                           (guard (x (#t #f)) (curl-engine-stop e))
                           (list early (curl-cookie-jar-state jar)))))
                     (iota 100))))
     (write (list 'as-done (tally (map car runs)) 'after-stop (tally (map cadr runs))))
     (newline))))
