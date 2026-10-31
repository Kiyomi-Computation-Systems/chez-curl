;;; M6 slice 2, item 1 (2026-10-30): an answer while the body is still being
;;; sent, through the engine (the M6 plan, sections 2.1 and 5.1).
;;;
;;;   scheme --libdirs build/m6s2/src --program answer.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; Each case on an engine of its own: a streamed post of 1,000,000 bytes,
;;; sized (body-length 1,000,000) or chunked (#f), to /answer, which answers
;;; as the request's head arrives: on the raw face 413 or 200, then a FIN
;;; (close=1) or keep-alive; on h2, 413 or 200, the stream ended. The
;;; transfer's bound, timeout-ms, is 8,000, and each case waits 10 s after
;;; its producer, so a transfer that never ends on its own ends at the bound,
;;; 28. The producer:
;;;
;;;   paused-rest  waits for room-wait's #t, puts nothing, and waits 3 s for
;;;                the token to be done; if it is not, puts the rest, 16 KiB
;;;                a put, each with a bound of 2,000 ms, then ends the body;
;;;   paused-end   as paused-rest, but at 3 s ends the body at once, with
;;;                nothing put;
;;;   paused-head  as paused-rest, its response streamed too, at a
;;;                stream-buffer of 1 MiB, so the head's arrival shows
;;;                (head-ms, from the submit) though the transfer may not
;;;                have ended; its pieces are taken at the end;
;;;   giving       waits for room-wait's #t, then puts 16 KiB every 10 ms,
;;;                each with a bound of 1,000 ms, until 1,000,000 bytes or a
;;;                put answers other than #t, then ends the body.
;;;
;;; Each line: whether the token was done within the first 3 s (the paused
;;; modes), when it was done, from the submit, by the engine's completion
;;; (done-ms); the outcome; the bytes committed and handed; the read
;;; callable's calls and pauses, the resumes, and whether a resume was
;;; carried out before the token was done; each put that answered other than
;;; #t, with when; what a put, room-wait and end-body! answered once the
;;; token was done; and the server's log for the case.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2) (list-head args 4)))
(define ca (list-ref args 4))
(define runs (string->number (list-ref args 5)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms x) (/ (round (/ x 1000)) 1000.0))
(define (sleep-ms n) (when (> n 0) (sleep (make-time 'time-duration (* (mod n 1000) 1000000) (div n 1000)))))

(define (url face path tag)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path
                 (if (memv #\? (string->list path)) "&" "?") "tag=" tag))

(define (request face method path tag timeout)
  (let ((r (make-curl-request (url face path tag) 'method method 'proxy #f 'timeout-ms timeout)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define (pattern-piece at n)
  (let ((bv (make-bytevector n)))
    (let loop ((i 0) (v (mod at 251)))
      (when (< i n) (bytevector-u8-set! bv i v) (loop (+ i 1) (if (= v 250) 0 (+ v 1)))))
    bv))

(define (split-lines s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))

(define (outcome-text o)
  (cond ((curl-response? o) (format "status=~a version=~a" (curl-response-status o) (curl-response-http-version o)))
        ((curl-transfer-error? o)
         (format "failed reason=~a code=~a request-size=~a error=~s" (curl-transfer-error-reason o)
                 (curl-transfer-error-code o) (curl-transfer-error-request-size o)
                 (curl-transfer-error-error-buffer o)))
        ((curl-engine-error? o) (format "engine ~a" (curl-engine-error-reason o)))
        ((not o) "not-done")
        (else (format "other ~s" o))))

(define log-engine (make-curl-engine))
(define (server-log tag)
  (let* ((t (curl-submit log-engine
                         (make-curl-request (string-append "http://" (cdr (assq 'raw faces)) "/log?tag=" tag)
                                            'proxy #f 'timeout-ms 10000)))
         (o (begin (curl-token-wait t 15000) (curl-token-outcome t))))
    (if (curl-response? o)
        (split-lines (utf8->string (curl-response-body o)))
        (list (format "log fetch failed: ~a" (outcome-text o))))))

(define (stat token key) (cdr (assq key (curl-token-upload-stats token))))

;; done-ms : Token Integer -> (U Number #f)
(define (done-ms token t0)
  (let ((d (stat token 'done-ns))) (and (> d 0) (ms (- d t0)))))

;; resumes-before-done : Token -> Natural
;; The resume step's calls logged before the token completed.
(define (resumes-before-done token)
  (let ((d (stat token 'done-ns)))
    (length (filter (lambda (e) (and (eq? (car e) 'resume) (or (= d 0) (< (cadr e) d))))
                    (curl-token-upload-events token)))))

;; put-rest : Token Natural Natural Integer -> (Listof (List Natural Any Number))
;; Puts 16 KiB pieces from AT to N, each with a bound of BOUND ms; the
;; answers other than #t, each (OFFSET ANSWER MS), stopping at the first.
(define (put-rest token at n bound t0 gap)
  (let loop ((at at))
    (if (>= at n)
        '()
        (let* ((k (min 16384 (- n at)))
               (a (guard (e (#t (list 'raised (if (curl-request-error? e) (curl-request-error-reason e) e))))
                    (curl-token-put-piece! token (pattern-piece at k) bound))))
          (if (eq? a #t)
              (begin (sleep-ms gap) (loop (+ at k)))
              (list (list at a (ms (- (now-ns) t0)))))))))

;; one : Natural Symbol String Symbol Symbol -> Void
(define (one r face path mode framing)
  (let* ((n 1000000)
         (label (format "answer run=~a face=~a path=~a mode=~a framing=~a" r face path mode framing))
         (tag (format "answer.~a.~a.~a.~a.r~a" face
                      (list->string (map (lambda (c) (if (memv c '(#\/ #\? #\& #\=)) #\. c)) (string->list path)))
                      mode framing r))
         (engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (let ((q (request face 'post path tag 8000)))
                                       (if (eq? mode 'paused-head) (curl-request-with q 'stream-buffer 1048576) q))
                                     (if (eq? framing 'sized) n #f))))
         (asked (curl-token-room-wait token 5000))
         (early
          (case mode
            ((giving) #f)
            (else (curl-token-wait token 3000))))
         (refused
          (case mode
            ((giving) (put-rest token 0 n 1000 t0 10))
            ((paused-rest paused-head) (if early '() (put-rest token 0 n 2000 t0 0)))
            (else '())))
         (committed-at-end (curl-token-body-count token)))
    (curl-token-end-body! token)
    (curl-token-wait token 10000)
    (let* ((head (and (eq? mode 'paused-head)
                      (let ((at (cdr (assq 'head-at (curl-token-stream-stats token)))))
                        (let drain () (when (bytevector? (curl-token-next-piece token 100)) (drain)))
                        (list (and at (ms (- at t0)))
                              (let ((h (curl-token-head token))) (and h (curl-head-status h)))))))
           (o (curl-token-outcome token))
           (after-put (and (curl-token-done? token)
                           (guard (e (#t (list 'raised e))) (curl-token-put-piece! token (pattern-piece 0 16) 100))))
           (after-room (and (curl-token-done? token) (curl-token-room-wait token 0))))
      (curl-token-end-body! token)
      (say "~a asked=~a done-within-3s=~a done-ms=~a head-ms=~a head-status=~a ~a committed=~a committed-before-end=~a handed=~a reads=~a pauses=~a resumes=~a resumes-before-done=~a put-answers=~s after-done-put=~a after-done-room-wait=~a ended=~a"
           label asked (if (eq? mode 'giving) "-" early) (done-ms token t0)
           (if head (car head) "-") (if head (cadr head) "-") (outcome-text o)
           (stat token 'committed) committed-at-end (stat token 'handed) (stat token 'reads)
           (stat token 'pauses) (stat token 'resumes) (resumes-before-done token)
           refused after-put after-room (stat token 'ended))
      (for-each (lambda (line) (unless (string=? line "") (say "~a server: ~a" label line)))
                (server-log tag)))
    (curl-engine-stop engine)))

(define cases
  '((raw "/answer?status=413&close=1") (raw "/answer?status=413")
    (raw "/answer?status=200&close=1") (raw "/answer?status=200")
    (h2 "/answer?status=413") (h2 "/answer?status=200")))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (c)
              (for-each (lambda (mode)
                          (for-each (lambda (framing) (one r (car c) (cadr c) mode framing)) '(sized chunked)))
                        '(paused-rest paused-head paused-end giving)))
            cases))
(curl-engine-stop log-engine)
(say "answer done")
