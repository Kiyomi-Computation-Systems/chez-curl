#!r6rs
;;; Review probe (M6 slice 2, read-only review): test-upload's "an answer
;;; while the body is sent" cells, run RUNS times each, sized and chunked,
;;; exactly as the suite runs them: an engine of its own per case,
;;; timeout-ms 4000, room-wait 2000, a wait of 1000 for an own end, then
;;; the rest put in 16 KiB pieces at 500 ms each, the end, a wait of 10000.
;;; Prints one datum per run: (answer RUN CASE FRAMING OWN-OR-WAITS STATUS).
;;;   answer.sps RUNS [CASE ...]
(import (rnrs)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond
              command-line-arguments parameterize)
        (curl-testing)
        (curl)
        (curl private engine))

(define args (command-line-arguments))
(define runs (string->number (car args)))
(define only-cases (map string->symbol (cdr args)))

(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) bv) (bytevector-u8-set! bv i (mod (+ at i) 251)))))

(define cases
  '((raw-413-close raw "/raw/answer?status=413&close=1")
    (raw-413-keep raw "/raw/answer?status=413&close=0")
    (raw-200-close raw "/raw/answer?status=200&close=1")
    (raw-200-keep raw "/raw/answer?status=200&close=0")
    (h2-413 h2 "/answer?status=413")
    (h2-200 h2 "/answer?status=200")))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))

(define (url-of o face path)
  (let ((f (origin-face o face)))
    (string-append (if (memq face '(https h2)) "https://" "http://")
                   (car f) ":" (number->string (cdr f)) path)))

(define (put-all token from to piece ms)
  (let loop ((at from))
    (if (>= at to)
        'put
        (let* ((n (min piece (- to at)))
               (a (guard (e (#t (list 'raised))) (curl-token-put-piece! token (pattern-piece at n) ms))))
          (if (eq? a #t) (loop (+ at n)) (list at a))))))

(define (status-of t)
  (let ((r (curl-token-outcome t)))
    (cond ((curl-response? r) (curl-response-status r))
          ((curl-transfer-error? r) (list (curl-transfer-error-reason r) (curl-transfer-error-code r)))
          (else r))))

(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (do ((run 1 (+ run 1))) ((> run runs))
       (for-each
        (lambda (spec)
          (when (or (null? only-cases) (memq (car spec) only-cases))
            (for-each
             (lambda (framing)
               (let* ((own (make-curl-engine))
                      (n 1000000)
                      (r0 (make-curl-request (url-of o (cadr spec) (caddr spec)) 'method 'post 'proxy #f
                                             'timeout-ms 4000 'body 'stream
                                             'body-length (and (eq? framing 'sized) n)))
                      (r (if (eq? (cadr spec) 'h2) (curl-request-with r0 'ca-file ca) r0))
                      (t (curl-submit own r))
                      (room (curl-token-room-wait t 2000))
                      (early (curl-token-wait t 1000)))
                 (unless early
                   (put-all t 0 n 16384 500)
                   (curl-token-end-body! t))
                 (curl-token-wait t 10000)
                 (write (list 'answer run (car spec) framing (if early 'own 'waits) (status-of t) 'room room))
                 (newline)
                 (flush-output-port (current-output-port))
                 (curl-engine-stop own)))
             '(sized chunked))))
        cases))
     'done)))
