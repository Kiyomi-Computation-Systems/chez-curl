;;; paused-send.sps [REPS]: a caller who waits for, or reads, a response
;;; while its own streamed body is unsent, against two servers that answer
;;; before they read the body, on the raw face (HTTP/1.1), raw-tls (over
;;; TLS), h2c (HTTP/2 by prior knowledge) and h2 (TLS, ALPN): answer, the
;;; raw face's /raw/answer?status=200&close=0 and HTTP/2's
;;; /answer?status=200, a whole answer as the head arrives, the server's
;;; side ended; mirror, /raw/mirror and HTTP/2's /mirror, a 200's head as
;;; the head arrives, then the body echoed, the server's side open until
;;; the request's end. Every request: a post, body
;;; stream, chunked, stream-buffer 65536, timeout-ms 8000, proxy #f.
;;;
;;; The low level's paths, each REPS (3) times on each face and server, the
;;; mirror's those that wait for the head alone:
;;;   head-first  curl-token-head-wait 3000 at once, before any room-wait
;;;   after-ask   curl-token-room-wait until libcurl asks, then
;;;               curl-token-head-wait 3000, nothing put
;;;   after-put   libcurl's ask, one put of 5 bytes, then curl-token-head-wait
;;;               3000, the body not ended
;;;   head-poll   libcurl's ask, then curl-token-head every 10 ms for 3000 ms
;;;   next-piece  libcurl's ask, then curl-token-next-piece 3000
;;;   port-read   libcurl's ask, then get-bytevector-some on the body port,
;;;               which has no bound of its own
;;;   long-wait   libcurl's ask, then curl-token-head-wait 12000, past the
;;;               transfer's 8000 ms timeout
;;; Then, unless the transfer has ended, the body ended, and the head waited
;;; for again, 3000 ms; then the transfer, 5000 ms. Prints
;;;   (paused LIBCURL FACE SERVER PATH REP ASKED WAIT AFTER-END OUTCOME)
;;; ASKED the ms from submit to libcurl's ask, or (not-asked); WAIT the
;;; path's own wait, (head MS STATUS) or (no-head MS), or a piece's, a
;;; read's; AFTER-END (head MS) or (no-head MS) or skipped; OUTCOME the
;;; transfer's, (response STATUS MS) or (failed CLASS MS), MS from submit.
;;; Run from a copy's root; the origin with a PKI of the run's.
(import (chezscheme) (curl) (curl-testing) (curl private counters))

(define reps (if (null? (command-line-arguments)) 3 (string->number (car (command-line-arguments)))))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))

(define version (libcurl-info-version (loaded-libcurl)))

(define (class-of c)
  (let ((code (and (curl-transfer-error? c) (curl-transfer-error-code c))))
    (list (cond ((curl-timeout? c) 'timeout) ((curl-connect-error? c) 'connect)
                ((curl-send-receive-error? c) 'send-receive) ((curl-tls-error? c) 'tls)
                ((curl-protocol-error? c) 'protocol)
                ((curl-transfer-error? c) (curl-transfer-error-reason c))
                ((condition? c) (if (message-condition? c) (condition-message c) 'condition))
                (else c))
          code)))

(define (request-for o face server)
  (let* ((f (origin-face o face))
         (tls (memq face '(raw-tls h2)))
         (raw (memq face '(raw raw-tls)))
         (path (case server
                 ((answer) (if raw "/raw/answer?status=200&close=0" "/answer?status=200"))
                 ((mirror) (if raw "/raw/mirror" "/mirror"))))
         (url (string-append (if tls "https://" "http://") (car f) ":" (number->string (cdr f)) path))
         (r (make-curl-request url 'method 'post 'body 'stream 'stream-buffer 65536
                               'timeout-ms 8000 'proxy #f
                               'http-version (case face
                                               ((raw raw-tls) 'http/1.1)
                                               ((h2c) 'http/2-prior-knowledge)
                                               (else 'http/2)))))
    (if tls (curl-request-with r 'ca-file ca) r)))

(define (head-row token t0 bound)
  (let* ((got (curl-token-head-wait token bound))
         (ms (- (now-ms) t0))
         (head (curl-token-head token)))
    (if head (list 'head ms (curl-head-status head)) (list 'no-head ms (if got 'ended 'bound)))))

(define (one engine o face server path rep)
  (let* ((t0 (now-ms))
         (token (curl-submit engine (request-for o face server)))
         (asked-ms #f)
         (ask! (lambda ()
                 (let ((room (curl-token-room-wait token 3000)))
                   (set! asked-ms (if (eq? room #t) (- (now-ms) t0) (list 'not-asked room))))))
         (wait
          (guard (e (#t (list 'raised (class-of e))))
            (case path
              ((head-first)
               (let ((row (head-row token t0 3000)))
                 (let ((head (curl-token-head token)))
                   (set! asked-ms (if head
                                      (list 'asked-by-head (curl-head-body-asked? head))
                                      (let ((room (curl-token-room-wait token 0)))
                                        (list 'asked-now room)))))
                 row))
              ((after-ask) (ask!) (head-row token t0 3000))
              ((after-put)
               (ask!)
               (let ((put (curl-token-put-piece! token (string->utf8 "hello") 1000)))
                 (list 'put put (head-row token t0 3000))))
              ((head-poll)
               (ask!)
               (let ((deadline (+ (now-ms) 3000)))
                 (let loop ()
                   (cond ((curl-token-head token)
                          => (lambda (h) (list 'head (- (now-ms) t0) (curl-head-status h))))
                         ((>= (now-ms) deadline) (list 'no-head (- (now-ms) t0) 'bound))
                         (else (sleep (make-time 'time-duration 10000000 0)) (loop))))))
              ((next-piece)
               (ask!)
               (let ((p (curl-token-next-piece token 3000)))
                 (list (cond ((bytevector? p) 'piece) ((eof-object? p) 'eof) (else 'none))
                       (- (now-ms) t0))))
              ((port-read)
               (ask!)
               (let* ((port (curl-token-body-port token))
                      (r (guard (e (#t (list 'raised (class-of e))))
                           (let ((b (get-bytevector-some port)))
                             (if (eof-object? b) 'eof (list 'bytes (bytevector-length b)))))))
                 (list 'read r (- (now-ms) t0))))
              ((long-wait) (ask!) (head-row token t0 12000))
              (else (error 'paused-send "no path" path)))))
         (after-end
          (if (curl-token-done? token)
              'skipped
              (begin
                (guard (e (#t #f)) (curl-token-end-body! token))
                (head-row token t0 3000))))
         (ended (curl-token-wait token 5000))
         (outcome (curl-token-outcome token))
         (end-ms (- (now-ms) t0)))
    (unless ended (curl-token-cancel token) (curl-token-wait token 5000))
    (list 'paused version face server path rep asked-ms wait after-end
          (cond ((not ended) (list 'not-ended end-ms))
                ((curl-response? outcome) (list 'response (curl-response-status outcome) end-ms))
                (else (list 'failed (class-of outcome) end-ms))))))

(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (let ((engine (make-curl-engine)))
       (for-each
        (lambda (face)
          (for-each
           (lambda (server)
             (for-each
              (lambda (path)
                (do ((rep 1 (+ rep 1))) ((> rep reps))
                  (write (one engine o face server path rep))
                  (newline)
                  (flush-output-port (current-output-port))))
              (if (eq? server 'answer)
                  '(head-first after-ask after-put head-poll next-piece port-read long-wait)
                  '(head-first after-ask after-put head-poll long-wait))))
           '(answer mirror)))
        '(raw raw-tls h2c h2))
       (curl-engine-stop engine)))))
(write (list 'counts (native-counts)))
(newline)
