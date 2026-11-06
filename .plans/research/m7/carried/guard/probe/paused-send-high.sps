;;; paused-send-high.sps [REPS]: the high level's streamed calls whose
;;; producer is slow, against the faces and the two servers paused-send.sps
;;; uses, answer and mirror, each answering before it reads the body. Producers: slow-first sleeps 1500 ms,
;;; then answers "hello", then the eof object; paced answers three pieces,
;;; each after 500 ms, then the eof object; fast answers "hello", then the
;;; eof object, with no sleep. Calls: port, call-with-response-port, whose
;;; PROC reads the port to its end; whole, http-post, its body read whole.
;;; Each session: timeout-ms 8000, proxy #f, the face's http-version, the
;;; run's CA file for TLS. Prints
;;;   (high LIBCURL FACE SERVER CALL PRODUCER REP PRODUCED PROC END)
;;; PRODUCED the ms, from the call's start, of each producer call's return;
;;; PROC the ms PROC was called at, or n/a; END (status S MS) or
;;; (raised CLASS MS). Run from a copy's root.
(import (chezscheme) (curl) (http-client) (curl-testing) (curl private counters))

(define reps (if (null? (command-line-arguments)) 2 (string->number (car (command-line-arguments)))))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (pause ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))
(define version (libcurl-info-version (loaded-libcurl)))

(define (class-of c)
  (let ((code (and (curl-transfer-error? c) (curl-transfer-error-code c))))
    (list (cond ((http-timeout? c) 'http-timeout)
                ((curl-timeout? c) 'timeout) ((curl-connect-error? c) 'connect)
                ((curl-send-receive-error? c) 'send-receive) ((curl-tls-error? c) 'tls)
                ((curl-protocol-error? c) 'protocol)
                ((curl-transfer-error? c) (curl-transfer-error-reason c))
                ((condition? c) (if (message-condition? c) (condition-message c) 'condition))
                (else c))
          code)))

(define (url-for o face server)
  (let* ((f (origin-face o face))
         (tls (memq face '(raw-tls h2)))
         (raw (memq face '(raw raw-tls)))
         (path (case server
                 ((answer) (if raw "/raw/answer?status=200&close=0" "/answer?status=200"))
                 ((mirror) (if raw "/raw/mirror" "/mirror")))))
    (string-append (if tls "https://" "http://") (car f) ":" (number->string (cdr f)) path)))

(define (session-for face)
  (apply make-http-session 'timeout-ms 8000 'proxy #f
         'http-version (case face ((raw raw-tls) 'http/1.1) ((h2c) 'http/2-prior-knowledge) (else 'http/2))
         (if (memq face '(raw-tls h2)) (list 'ca-file ca) '())))

;; producer-of : Symbol (-> Natural) (Box (Listof Natural)) -> ( -> (U Bytevector Eof))
(define (producer-of kind ms-now log)
  (let ((n 0))
    (lambda ()
      (set! n (+ n 1))
      (let ((answer
             (case kind
               ((slow-first) (if (= n 1) (begin (pause 1500) (string->utf8 "hello")) (eof-object)))
               ((paced) (if (<= n 3) (begin (pause 500) (string->utf8 "piece")) (eof-object)))
               ((fast) (if (= n 1) (string->utf8 "hello") (eof-object))))))
        (set-box! log (cons (ms-now) (unbox log)))
        answer))))

(define (one o face server call kind rep)
  (let* ((session (session-for face))
         (t0 (now-ms))
         (ms-now (lambda () (- (now-ms) t0)))
         (log (box '()))
         (proc-ms 'n/a)
         (end
          (guard (e (#t (list 'raised (class-of e) (ms-now))))
            (case call
              ((port)
               (call-with-response-port session 'post (url-for o face server) 'body (producer-of kind ms-now log)
                 (lambda (r p)
                   (set! proc-ms (ms-now))
                   (let loop ()
                     (unless (eof-object? (get-bytevector-some p)) (loop)))
                   (list 'status (http-response-status r) (ms-now)))))
              ((whole)
               (let ((r (http-post session (url-for o face server) 'body (producer-of kind ms-now log))))
                 (list 'status (http-response-status r) (ms-now))))))))
    (http-session-close session)
    (list 'high version face server call kind rep (reverse (unbox log)) proc-ms end)))

(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (for-each
      (lambda (face)
        (for-each
         (lambda (server)
           (for-each
            (lambda (call)
              (for-each
               (lambda (kind)
                 (do ((rep 1 (+ rep 1))) ((> rep reps))
                   (write (one o face server call kind rep))
                   (newline)
                   (flush-output-port (current-output-port))))
               '(slow-first paced fast)))
            '(port whole)))
         '(answer mirror)))
      '(raw raw-tls h2c h2)))))
(write (list 'counts (native-counts)))
(newline)
