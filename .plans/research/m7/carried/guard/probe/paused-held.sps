;;; paused-held.sps [REPS]: (or HELD_REPS) paused-send.sps's question with the answer held,
;;; as M7 slice 4's races held it: HTTP/2's /answer?status=200&hold=KEY on
;;; h2c and h2, answered once /raw/release?key=KEY names KEY, the release
;;; sent from an engine of its own. Paths, each REPS (10) times on each
;;; face:
;;;   release-first  the release at once after the submit, then
;;;                  curl-token-head-wait 3000, before any room-wait
;;;   ask-then-N     libcurl's ask (curl-token-room-wait), N ms (0, 50 or
;;;                  250), the release, then curl-token-head-wait 3000,
;;;                  nothing put
;;;   release-first-long  the release at once, then curl-token-head-wait
;;;                  12000, past the transfer's 8000 ms timeout, and the
;;;                  body never ended: a stall that lasts until the timeout
;;; HELD_PATHS and HELD_FACES, when set, name the paths and faces run.
;;; Then, unless the transfer has ended, the body ended and the head waited
;;; for again, 3000 ms; then the transfer, 5000 ms. Prints
;;;   (held LIBCURL FACE PATH REP ASKED RELEASED WAIT AFTER-END OUTCOME)
;;; as paused-send.sps prints its rows, RELEASED the release's status and
;;; ms from the submit. Run from a copy's root; the origin with a PKI.
(import (chezscheme) (curl) (curl-testing) (curl private counters))

(define reps (or (let ((r (getenv "HELD_REPS"))) (and r (string->number r)))
                 (if (null? (command-line-arguments)) 10 (string->number (car (command-line-arguments))))))

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

(define keys 0)
(define (fresh-key)
  (set! keys (+ keys 1))
  (string-append "held" (number->string (get-process-id)) "x" (number->string keys)))

(define (request-for o face key)
  (let* ((f (origin-face o face))
         (tls (eq? face 'h2))
         (url (string-append (if tls "https://" "http://") (car f) ":" (number->string (cdr f))
                             "/answer?status=200&hold=" key))
         (r (make-curl-request url 'method 'post 'body 'stream 'stream-buffer 65536
                               'timeout-ms 8000 'proxy #f
                               'http-version (if tls 'http/2 'http/2-prior-knowledge))))
    (if tls (curl-request-with r 'ca-file ca) r)))

(define (release! releaser o key t0)
  (let* ((f (origin-face o 'raw))
         (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/raw/release?key=" key))
         (r (guard (e (#t (list 'raised (class-of e))))
              (curl-response-status (curl-token-await (curl-submit releaser (make-curl-request url 'proxy #f 'timeout-ms 5000)))))))
    (list r (- (now-ms) t0))))

(define (head-row token t0 bound)
  (let* ((got (curl-token-head-wait token bound))
         (ms (- (now-ms) t0))
         (head (curl-token-head token)))
    (if head (list 'head ms (curl-head-status head)) (list 'no-head ms (if got 'ended 'bound)))))

;; HELD_PATHS, when set, names the paths, and HELD_FACES the faces.
(define (listed name default)
  (let ((v (getenv name)))
    (if (and v (not (string=? v "")))
        (let ((p (open-string-input-port v)))
          (let loop ((acc '()))
            (let ((d (read p))) (if (eof-object? d) (reverse acc) (loop (cons d acc))))))
        default)))
(define paths (listed "HELD_PATHS" '(release-first ask-then-0 ask-then-50 ask-then-250)))
(define faces (listed "HELD_FACES" '(h2c h2)))

(define (one engine releaser o face path rep)
  (let* ((t0 (now-ms))
         (key (fresh-key))
         (token (curl-submit engine (request-for o face key)))
         (asked-ms #f)
         (released #f)
         (ask! (lambda ()
                 (let ((room (curl-token-room-wait token 3000)))
                   (set! asked-ms (if (eq? room #t) (- (now-ms) t0) (list 'not-asked room))))))
         (wait
          (guard (e (#t (list 'raised (class-of e))))
            (case path
              ((release-first-long)
               (set! released (release! releaser o key t0))
               (let ((row (head-row token t0 12000)))
                 (set! asked-ms (list 'asked-now (curl-token-room-wait token 0)))
                 row))
              ((release-first)
               (set! released (release! releaser o key t0))
               (let ((row (head-row token t0 3000)))
                 (let ((head (curl-token-head token)))
                   (set! asked-ms (if head
                                      (list 'asked-by-head (curl-head-body-asked? head))
                                      (list 'asked-now (curl-token-room-wait token 0)))))
                 row))
              (else
               (ask!)
               (let ((n (case path ((ask-then-0) 0) ((ask-then-50) 50) ((ask-then-250) 250))))
                 (unless (= n 0) (sleep (make-time 'time-duration (* n 1000000) 0)))
                 (set! released (release! releaser o key t0))
                 (head-row token t0 3000))))))
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
    (list 'held version face path rep asked-ms released wait after-end
          (cond ((not ended) (list 'not-ended end-ms))
                ((curl-response? outcome) (list 'response (curl-response-status outcome) end-ms))
                (else (list 'failed (class-of outcome) end-ms))))))

(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (let ((engine (make-curl-engine)) (releaser (make-curl-engine)))
       (for-each
        (lambda (face)
          (for-each
           (lambda (path)
             (do ((rep 1 (+ rep 1))) ((> rep reps))
               (write (one engine releaser o face path rep))
               (newline)
               (flush-output-port (current-output-port))))
           paths))
        faces)
       (curl-engine-stop engine)
       (curl-engine-stop releaser)))))
(write (list 'counts (native-counts)))
(newline)
