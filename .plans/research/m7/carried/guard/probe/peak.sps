;;; peak.sps CASE: one call of CASE, stopped at its checks' exit as cost.sps
;;; stops it, in a process of its own; then Chez's (maximum-memory-bytes),
;;; the most memory the process ever held, and the same read before the
;;; call: a critical section defers the collections the checks' garbage
;;; would have had. Prints (peak CASE BEFORE-MB AFTER-MB). Run from a
;;; copy's root.
(import (chezscheme) (curl) (http-client) (curl private gate))

(define name (string->symbol (car (command-line-arguments))))
(define url "http://127.0.0.1:9/never")
(define session (make-http-session 'timeout-ms 20000))
(define (text n) (make-string n #\a))
(define (mixed n)
  (let ((s (make-string n)))
    (do ((i 0 (+ i 1))) ((= i n) s)
      (string-set! s i (string-ref "a b/\xE9;-c&d=e" (mod i 11))))))

(define thunk
  (case name
    ((post-bytevector-256MiB) (let ((b (make-bytevector (expt 2 28) 120))) (lambda () (http-post session url 'body b))))
    ((post-string-64Mi-chars) (let ((s (text (expt 2 26)))) (lambda () (http-post session url 'body s))))
    ((form-one-pair-16Mi-chars) (let ((f (list (cons "k" (mixed (expt 2 24)))))) (lambda () (http-post session url 'form f))))
    ((params-100000-pairs)
     (let ((p (map (lambda (i) (cons (string-append "k" (number->string i)) "v")) (iota 100000))))
       (lambda () (http-get session url 'params p))))
    ((headers-100000)
     (let ((h (map (lambda (i) (cons (string-append "X-H" (number->string i)) "value")) (iota 100000))))
       (lambda () (http-get session url 'headers h))))
    ((url-7.9MB-path) (let ((u (string-append "http://127.0.0.1:9/" (text 7900000)))) (lambda () (http-get session u))))
    (else (error 'peak "no case" name))))

(collect (collect-maximum-generation))
(define before (maximum-memory-bytes))
(gate-set! (lambda (w) (when (eq? w 'exit) (raise 'stop-here))))
(define r (guard (e (#t e)) (thunk) 'returned))
(gate-set! #f)
(define (mb n) (/ (round (/ n 10485.76)) 100.0))
(write (list 'peak name (if (eq? r 'stop-here) 'stopped r) (mb before) (mb (maximum-memory-bytes))))
(newline)
(http-session-close session)
