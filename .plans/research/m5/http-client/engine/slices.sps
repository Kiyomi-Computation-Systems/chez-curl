;; slices.sps: the engine test's first version, which ran the call 1000
;; ticks at a time, ten times: prints (run SEEN ANSWER), SEEN the first
;; expiry that found the transfer live, or never-live, and ANSWER what the
;; call answered.
(import (chezscheme) (curl-testing) (curl) (http-client) (curl private counters))
(define (show . xs) (write xs) (newline) (flush-output-port (current-output-port)))
(define (count-of k) (cdr (assq k (native-counts))))
(call-with-origin
 (lambda (o)
   (define f (origin-face o 'raw))
   (define url (string-append "http://" (car f) ":" (number->string (cdr f)) "/raw/pause-mid-body?ms=10000"))
   (let loop ((i 0))
     (when (< i 10)
       (let* ((own (make-http-session 'timeout-ms 30000))
              (seen 'never-live)
              (answer
               (let run ((eng (make-engine (lambda ()
                                             (guard (e (#t (list 'raised (and (curl-transfer-error? e) (curl-transfer-error-reason e))
                                                                 (and (http-exchange? e) (http-exchange-transfers e)))))
                                               (http-get own url) 'returned)))))
                 (eng 1000 (lambda (ticks v) v)
                      (lambda (next)
                        (when (and (eq? seen 'never-live) (= (count-of 'transfer) 1)) (set! seen 'live-at-an-expiry))
                        (run next))))))
         (http-session-close own)
         (show i seen answer))
       (loop (+ i 1))))))
