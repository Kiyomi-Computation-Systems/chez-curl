;;; M6 slice 3, item 1 (2026-10-31): whether libcurl asks for a streamed
;;; body after a final head that came before its first ask (the M6 plan,
;;; sections 3.6 and 6.1).
;;;
;;;   scheme --libdirs src:tests:build/scheme-libs --program asked.sps HTTP RAW HTTPS H2 CLOSED CA PART RUNS
;;;
;;; Every case runs on an engine of its own, made by
;;; make-curl-engine-holding-prereq 200: a streamed body's prerequest
;;; callable, at its first attempt, connected and before the request is sent,
;;; holds the engine's thread 200 ms, so an answer written as the
;;; connection is accepted lands before the request leaves (slice 2's
;;; asked-early pattern). The streamed request: METHOD post or put, a body
;;; of 1,000 bytes, sized (body-length 1,000) or chunked (#f), stream-buffer
;;; 1,024, timeout-ms 10,000. Nothing is put. Then:
;;;
;;;   1. head-wait 5,000 ms; the head, its status and its body-asked bit;
;;;      the stream's head-at and the request stream's asked and asked-at,
;;;      both the engine's monotonic clock, and the read callable's verdicts
;;;      so far;
;;;   2. pieces taken by curl-token-next-piece for up to WINDOW (1,500 ms)
;;;      from the head-wait's return, until the eof object: whether the
;;;      transfer ended on its own, when (ms after head-at), the bytes, and
;;;      whether they are "early S\n" whole;
;;;   3. the read callable's verdicts again, and asked-at against head-at:
;;;      whether libcurl first asked after the head, and when;
;;;   4. if the token is not done: when libcurl has asked, the body is put
;;;      (1,000 bytes, a bound of 1,000 ms) and ended, and the pieces taken
;;;      for up to WINDOW again ("fed"), the token cancelled if it is still
;;;      not done ("then-cancelled"); when it has not asked, the token is
;;;      cancelled, as the plan's rule for a hop libcurl asks for would
;;;      ("cancelled"); either way the outcome.
;;;
;;; PART origin runs against tests/origin.mjs's /raw/arm, through
;;; (curl-testing)'s call-with-origin: statuses 200 (the control), 301,
;;; 302, 303, 307, 308, 413 and 503; post and put; sized and chunked; RUNS
;;; runs. The arm answers "HTTP/1.1 S Early", Content-Length, Connection:
;;; close and "early S\n" as the connection is accepted, then ends its side.
;;;
;;; PART faces runs against this directory's server.mjs, whose faces the
;;; runner passes:
;;;   raw-keep, raw-later   /arm on the plaintext face, mode keep (the
;;;       answer whole, keep-alive, the request read on) and later (the head
;;;       alone, the body once the request is read whole): every status,
;;;       both methods, both framings;
;;;   https-close, https-keep, https-later   /arm on the TLS face, answered
;;;       as its handshake ends: 200, 303, 307 and 413, post, both framings;
;;;   h2-headers   /answer-at?after=0 on the h2 face, answered as the
;;;       request's headers arrive, the stream ended, the DATA read on:
;;;       200, 303, 307, 413 and 503, both methods, both framings.
;;;
;;; One line a case, "asked ...", then the server's log for it (faces) and,
;;; at the end, the counts of native objects.
(import (chezscheme)
        (curl)
        (curl-testing)
        (only (curl private engine) make-curl-engine-holding-prereq curl-engine-prereq-holds
              curl-token-upload-stats curl-token-stream-stats)
        (only (curl private counters) native-counts))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 closed) (list-head args 5)))
(define ca (list-ref args 5))
(define part (string->symbol (list-ref args 6)))
(define runs (string->number (list-ref args 7)))
(define window 1500)

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms x) (and x (/ (round (/ x 1000)) 1000.0)))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (outcome-text o)
  (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
        ((curl-transfer-error? o)
         (format "failed:~a:~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
        ((condition? o) (format "condition:~a" (if (message-condition? o) (condition-message o) "?")))
        ((not o) "not-done")
        (else (format "other:~s" o))))

(define (stat token key) (cdr (assq key (curl-token-upload-stats token))))
(define (sstat token key) (cdr (assq key (curl-token-stream-stats token))))

;; verdicts : Token -> String
;; The read callable's calls so far, each verdict with its count.
(define (verdicts token)
  (let ((reads (stat token 'reads)))
    (if (null? reads)
        "none"
        (apply string-append
               (map (lambda (r) (format "~a~a:~a" (if (eq? r (car reads)) "" ",") (car r) (cadr r))) reads)))))

;; drain : Token Natural -> (Values (Listof Bytevector) Boolean (U Integer #f))
;; Pieces for up to MS ms: the pieces, newest first, whether the eof object
;; came, and when (monotonic ns).
(define (drain token bound)
  (let ((deadline (+ (now-ns) (* bound 1000000))))
    (let loop ((got '()))
      (let ((left (div (- deadline (now-ns)) 1000000)))
        (if (<= left 0)
            (values got #f #f)
            (let ((p (curl-token-next-piece token left)))
              (cond ((bytevector? p) (loop (cons p got)))
                    ((eof-object? p) (values got #t (now-ns)))
                    (else (values got #f #f)))))))))

(define (bytevector-append . bvs)
  (let* ((n (apply + (map bytevector-length bvs))) (out (make-bytevector n)))
    (let loop ((bvs bvs) (at 0))
      (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out at (bytevector-length (car bvs)))
                 (loop (cdr bvs) (+ at (bytevector-length (car bvs)))))))))

;; probe : String Engine (-> Any) (-> Request) Integer -> Void
;; One case, as the header says: ARM!, then MAKE's request on ENGINE.
(define (probe label engine arm! make status)
  (arm!)
  (let* ((t0 (now-ns))
         (token (curl-submit engine (make)))
         (waited (curl-token-head-wait token 5000))
         (head (curl-token-head token))
         (bit (if head (curl-head-body-asked? head) 'no-head))
         (head-at (sstat token 'head-at))
         (reads-at-head (verdicts token)))
    (let-values (((pieces ended at) (drain token window)))
      (let* ((asked (stat token 'asked))
             (asked-at (stat token 'asked-at))
             (reads-after (verdicts token))
             (want (format "early ~a\n" status))
             (body (apply bytevector-append (reverse pieces)))
             (whole (string=? (utf8->string body) want))
             (first-ask (cond ((not asked) "never")
                              ((not head-at) (format "at+~a-no-head" (ms (- asked-at t0))))
                              ((< asked-at head-at) (format "before-head:~a" (ms (- asked-at head-at))))
                              (else (format "after-head:+~a" (ms (- asked-at head-at))))))
             (then
              (cond
                (ended "-")
                (asked
                 (let* ((put (curl-token-put-piece! token (make-bytevector 1000 7) 1000))
                        (end (begin (unless (curl-token-done? token) (curl-token-end-body! token)) #t)))
                   (let-values (((more ended2 at2) (drain token window)))
                     (unless ended2 (curl-token-cancel token) (curl-token-wait token 5000))
                     (format "fed:put=~a:ended=~a:at=+~a:more=~a~a" put ended2 (and at2 head-at (ms (- at2 head-at)))
                             (apply + (map bytevector-length more)) (if ended2 "" ":then-cancelled")))))
                (else (curl-token-cancel token) (curl-token-wait token 5000) "cancelled"))))
        (curl-token-wait token 10000)
        (say "asked ~a head=~a bit=~a head-ms=~a reads-at-head=~a first-ask=~a reads-after=~a ended-own=~a end-ms=+~a body-whole=~a body=~s then=~a outcome=~a handed=~a holds=~a"
             label (and head (curl-head-status head)) bit (and head-at (ms (- head-at t0))) reads-at-head
             first-ask reads-after (if ended "yes" "no") (and ended head-at (ms (- at head-at))) (if whole "yes" "no")
             (utf8->string body) then (outcome-text (curl-token-outcome token)) (stat token 'handed)
             (curl-engine-prereq-holds engine))))))

(define statuses '(200 301 302 303 307 308 413 503))

;; --- PART origin: tests/origin.mjs's /raw/arm ---------------------------------------

(define (origin-part)
  (call-with-origin
   (lambda (o)
     (define (ourl path)
       (let ((f (origin-face o 'raw))) (string-append "http://" (car f) ":" (number->string (cdr f)) path)))
     (do ((r 1 (+ r 1))) ((> r runs))
       (for-each
        (lambda (status)
          (for-each
           (lambda (method)
             (for-each
              (lambda (framing)
                (let ((engine (make-curl-engine-holding-prereq 200)))
                  (probe (format "part=origin face=raw-arm status=~a method=~a framing=~a run=~a" status method framing r)
                         engine
                         (lambda ()
                           (let ((a (curl-token-await
                                     (curl-submit engine (make-curl-request (ourl (format "/raw/arm?status=~a" status))
                                                                            'proxy #f 'timeout-ms 10000)))))
                             (unless (and (curl-response? a) (= 200 (curl-response-status a)))
                               (say "asked arm-failed ~a" (outcome-text a)))))
                         (lambda ()
                           (make-curl-request (ourl "/raw/early-target") 'method method 'proxy #f 'timeout-ms 10000
                                              'stream-buffer 1024 'body 'stream
                                              'body-length (and (eq? framing 'sized) 1000)))
                         status)
                  (curl-engine-stop engine)))
              '(sized chunked)))
           '(post put)))
        statuses)))))

;; --- PART faces: this directory's server.mjs ----------------------------------------

(define log-engine #f)
(define (server-log tag)
  (let* ((t (curl-submit log-engine
                         (make-curl-request (string-append "http://" (cdr (assq 'raw faces)) "/log?tag=" tag)
                                            'proxy #f 'timeout-ms 10000)))
         (o (begin (curl-token-wait t 15000) (curl-token-outcome t))))
    (if (curl-response? o)
        (split-lines (utf8->string (curl-response-body o)))
        (list (format "log fetch failed: ~a" (outcome-text o))))))

(define (furl face path)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path))

(define (faces-part)
  (set! log-engine (make-curl-engine))
  (let ((n 0))
    (define (one where status method framing r)
      (set! n (+ n 1))
      (let* ((tag (format "asked.~a.~a.~a.~a.r~a.~a" where status method framing r n))
             (face (case where ((raw-keep raw-later) 'raw) ((https-close https-keep https-later) 'https) (else 'h2)))
             (mode (case where ((raw-keep https-keep) "keep") ((raw-later https-later) "later") (else "close")))
             (engine (make-curl-engine-holding-prereq 200))
             (label (format "part=faces face=~a status=~a method=~a framing=~a run=~a" where status method framing r)))
        (probe label engine
               (lambda ()
                 (unless (eq? where 'h2-headers)
                   (let ((a (curl-token-await
                             (curl-submit engine
                                          (make-curl-request
                                           (furl 'raw (format "/arm?status=~a&face=~a&mode=~a&tag=~a" status face mode tag))
                                           'proxy #f 'timeout-ms 10000)))))
                     (unless (and (curl-response? a) (= 200 (curl-response-status a)))
                       (say "asked arm-failed ~a" (outcome-text a))))))
               (lambda ()
                 (let ((req (make-curl-request
                             (furl face (if (eq? where 'h2-headers)
                                            (format "/answer-at?status=~a&after=0&tag=~a" status tag)
                                            (format "/sink?tag=~a" tag)))
                             'method method 'proxy #f 'timeout-ms 10000
                             'stream-buffer 1024 'body 'stream 'body-length (and (eq? framing 'sized) 1000))))
                   (if (memq face '(https h2)) (curl-request-with req 'ca-file ca) req)))
               status)
        (for-each (lambda (line) (say "asked ~a server: ~a" label line)) (server-log tag))
        (curl-engine-stop engine)))
    (do ((r 1 (+ r 1))) ((> r runs))
      (for-each
       (lambda (where)
         (for-each
          (lambda (status)
            (for-each
             (lambda (method)
               (for-each (lambda (framing) (one where status method framing r)) '(sized chunked)))
             (if (memq where '(https-close https-keep https-later)) '(post) '(post put))))
          (case where
            ((raw-keep raw-later) statuses)
            ((h2-headers) '(200 303 307 413 503))
            (else '(200 303 307 413)))))
       '(raw-keep raw-later https-close https-keep https-later h2-headers))))
  (curl-engine-stop log-engine))

(say "asked libcurl ~a ~a part=~a runs=~a window=~a" (libcurl-info-version (loaded-libcurl))
     (libcurl-info-ssl-version (loaded-libcurl)) part runs window)
(case part
  ((origin) (origin-part))
  ((faces) (faces-part))
  (else (error 'asked "no such part" part)))
(collect)
(say "asked counts ~a" (native-counts))
(say "asked done")
