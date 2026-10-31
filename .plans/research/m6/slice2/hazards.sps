;;; M6 slice 2, items 3a and 3b (2026-10-30): the hazards the source reading
;;; found and no probe reached (the M6 plan, sections 2.2 and 5.1).
;;;
;;;   scheme --libdirs build/m6s2/src --program hazards.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; 3a, lost (curl #11769, fixed in 8.3.0): a connection lost under a
;;; paused upload. On an engine of its own, a streamed post of 1,000,000
;;; bytes, sized or chunked, to /drop?after=65536&how=HOW&delay=200 on the
;;; raw, https and h2 faces, timeout-ms 4,000: the producer waits for
;;; room-wait's #t, puts 65,536 bytes, then nothing, so the read callable
;;; pauses; 200 ms after the server has read 65,536 bytes it destroys the
;;; connection's TCP socket (fin) or resets it (reset). Each line: when the
;;; token was done, from the submit (done-ms), and with what; the read
;;; callable's last pause, from the submit; the event log; the server's log.
;;;
;;; 3b, one direction paused over HTTP/2 (cdd905a9, fixed in 8.6.0), on the
;;; h2 face, /duplex?n=4194304, which answers 200 and 4 MiB of i mod 251 as
;;; the headers arrive, 16 KiB a write, while it reads the body; a streamed
;;; post of 1,000,000 bytes, sized; the response streamed, its pieces taken
;;; by a consumer thread of its own; timeout-ms 20,000:
;;;
;;;   send-paused  stream-buffer 16 MiB, so the receive never pauses; the
;;;                producer puts 65,536 bytes, then nothing for 3 s, the
;;;                send paused, then the rest, then the end. Does the
;;;                response arrive while the send is paused (resp-bytes-at-3s,
;;;                resp-last-ms), and does the transfer end once it resumes?
;;;   recv-paused  stream-buffer 65,536, the consumer taking nothing for 3 s,
;;;                so the receive pauses; the producer puts the whole body at
;;;                once, then the end. Does the send go on while the receive
;;;                is paused (handed-at-2.9s, sampled by a thread of its
;;;                own, and the server's arrivals), and does the transfer
;;;                end once the consumer reads?
;;;   recv-paused-small  the control: as recv-paused, but a response of
;;;                128 KiB, which the kernel's buffers and libcurl's hold
;;;                whole, so the server's writes end and nothing it sends,
;;;                its WINDOW_UPDATE frames among them, waits behind them.
;;;                Where the send stalls in recv-paused but goes on here, the
;;;                stall is the connection's flow control, not the read
;;;                callable left uncalled.
;;;   recv-flowing  the other control: stream-buffer 16 MiB and the consumer
;;;                taking at once, so the receive never pauses, the producer
;;;                putting the whole body at once: the send's pace with
;;;                nothing paused.
;;; The server's line for each 3b case keeps every arrival of the body, as
;;; MS:BYTES from its head's arrival, and a duplex-state line at 1 s: its
;;; flow-control windows as its nghttp2 sees them.
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

(define (bad-at piece at)
  (let ((n (bytevector-length piece)))
    (let loop ((i 0) (v (mod at 251)))
      (cond ((= i n) #f)
            ((fx= (bytevector-u8-ref piece i) v) (loop (fx+ i 1) (if (fx= v 250) 0 (fx+ v 1))))
            (else (+ at i))))))

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
(define (done-ms token t0) (let ((d (stat token 'done-ns))) (and (> d 0) (ms (- d t0)))))

(define (event-text e t0)
  (define (at t) (ms (- t t0)))
  (case (car e)
    ((read) (let-values (((t room buf answer inp) (apply values (cdr e))))
              (format "R~a/~a:~a~a@~a" room buf answer (if inp "!" "") (at t))))
    ((seek) (let-values (((t off origin answer inp) (apply values (cdr e))))
              (format "S~a/~a:~a~a@~a" off origin answer (if inp "!" "") (at t))))
    ((prereq) (let-values (((t n port send answer handed) (apply values (cdr e))))
                (format "P~a:~a:port~a:send~a:handed~a@~a" n answer port (if send 1 0) handed (at t))))
    ((resume) (let-values (((called queued send returned answer) (apply values (cdr e))))
                (format "Z~a:send~a@~a" answer (if send 1 0) (at called))))
    ((end) (format "E@~a" (at (cadr e))))
    (else (format "~s" e))))

(define (events-text events t0)
  (let* ((n (length events))
         (shown (if (<= n 50)
                    (map (lambda (e) (event-text e t0)) events)
                    (append (map (lambda (e) (event-text e t0)) (list-head events 40))
                            (list (format "...~a-more..." (- n 50)))
                            (map (lambda (e) (event-text e t0)) (list-tail events (- n 10)))))))
    (apply string-append (map (lambda (s) (string-append s " ")) shown))))

(define (last-pause-ms token t0)
  (let ((pauses (filter (lambda (e) (and (eq? (car e) 'read) (eq? (list-ref e 4) 'pause)))
                        (curl-token-upload-events token))))
    (and (pair? pauses) (ms (- (cadr (list-ref pauses (- (length pauses) 1))) t0)))))

;; lost : Natural Symbol Symbol Symbol -> Void
(define (lost r face how framing)
  (let* ((n 1000000)
         (label (format "hazard run=~a case=lost face=~a how=~a framing=~a" r face how framing))
         (tag (format "hazard.lost.~a.~a.~a.r~a" face how framing r))
         (engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (request face 'post (format "/drop?after=65536&how=~a&delay=200" how) tag 4000)
                                     (if (eq? framing 'sized) n #f))))
         (asked (curl-token-room-wait token 5000))
         (puts (map (lambda (i) (curl-token-put-piece! token (pattern-piece (* i 16384) 16384) 2000)) '(0 1 2 3))))
    (curl-token-wait token 8000)
    (say "~a asked=~a puts=~a done-ms=~a ~a handed=~a reads=~a pauses=~a resumes=~a last-pause-ms=~a send-paused=~a"
         label asked puts (done-ms token t0) (outcome-text (curl-token-outcome token))
         (stat token 'handed) (stat token 'reads) (stat token 'pauses) (stat token 'resumes)
         (last-pause-ms token t0) (stat token 'send-paused))
    (say "~a events: ~a" label (events-text (curl-token-upload-events token) t0))
    (for-each (lambda (line) (unless (string=? line "") (say "~a server: ~a" label line))) (server-log tag))
    (curl-engine-stop engine)))

;; consumer : Token Integer (Vector ...) -> Thread
;; Takes every piece, checking each against its pattern; V holds, written
;; plainly by this thread alone: 0 bytes, 1 first-bad, 2 last piece's time,
;; 3 done (the eof seen), 4 the time of the first piece.
(define (consume! token v start-after)
  (fork-thread
   (lambda ()
     (sleep-ms start-after)
     (let loop ()
       (let ((piece (curl-token-next-piece token 100)))
         (cond ((bytevector? piece)
                (let ((at (vector-ref v 0)))
                  (unless (vector-ref v 1) (vector-set! v 1 (bad-at piece at)))
                  (unless (vector-ref v 4) (vector-set! v 4 (now-ns)))
                  (vector-set! v 0 (+ at (bytevector-length piece)))
                  (vector-set! v 2 (now-ns))
                  (loop)))
               ((eof-object? piece) (vector-set! v 3 #t))
               (else (loop))))))))

;; direction : Natural Symbol -> Void
(define (direction r which)
  (let* ((n 1000000)
         (resp (if (eq? which 'recv-paused-small) 131072 4194304))
         (label (format "hazard run=~a case=~a face=h2" r which))
         (tag (format "hazard.~a.r~a" which r))
         (engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (curl-request-with (request 'h2 'post (format "/duplex?n=~a&chunk=16384" resp) tag 20000)
                                                        'stream-buffer (if (memq which '(send-paused recv-flowing)) 16777216 65536))
                                     n)))
         (v (vector 0 #f #f #f #f #f #f))
         (asked (curl-token-room-wait token 5000)))
    (consume! token v (if (memq which '(send-paused recv-flowing)) 0 3000))
    ;; The sampler: at 2.9 s from the submit, before the consumer or the
    ;; producer goes on, the bytes handed (slot 5) and the receive bit (6).
    (fork-thread
     (lambda ()
       (sleep-ms (max 0 (- 2900 (round (/ (- (now-ns) t0) 1000000)))))
       (vector-set! v 5 (stat token 'handed))
       (vector-set! v 6 (cdr (assq 'paused (curl-token-stream-stats token))))))
    (case which
      ((send-paused)
       (for-each (lambda (i) (curl-token-put-piece! token (pattern-piece (* i 16384) 16384) 2000)) '(0 1 2 3))
       (sleep-ms 3000)
       (let ((at-3s (vector-ref v 0)) (paused (stat token 'send-paused)) (handed (stat token 'handed)))
         (let loop ((at 65536))
           (when (< at n)
             (let ((k (min 16384 (- n at))))
               (when (eq? #t (curl-token-put-piece! token (pattern-piece at k) 5000)) (loop (+ at k))))))
         (curl-token-end-body! token)
         (curl-token-wait token 20000)
         (sleep-ms 200)
         (say "~a asked=~a resp-bytes-at-3s=~a send-paused-at-3s=~a handed-at-3s=~a handed-at-2.9s=~a resp-first-ms=~a resp-last-ms=~a resp-bytes=~a resp-pattern=~a resp-eof=~a done-ms=~a ~a handed=~a reads=~a pauses=~a resumes=~a"
              label asked at-3s paused handed (vector-ref v 5) (and (vector-ref v 4) (ms (- (vector-ref v 4) t0)))
              (and (vector-ref v 2) (ms (- (vector-ref v 2) t0))) (vector-ref v 0) (or (vector-ref v 1) "ok")
              (vector-ref v 3) (done-ms token t0) (outcome-text (curl-token-outcome token))
              (stat token 'handed) (stat token 'reads) (stat token 'pauses) (stat token 'resumes))))
      (else
       (let loop ((at 0))
         (when (< at n)
           (let ((k (min 16384 (- n at))))
             (when (eq? #t (curl-token-put-piece! token (pattern-piece at k) 5000)) (loop (+ at k))))))
       (let ((put-ms (ms (- (now-ns) t0))))
         (curl-token-end-body! token)
         (sleep-ms (max 0 (- 3000 (round (/ (- (now-ns) t0) 1000000)))))
         (let ((handed (stat token 'handed))
               (recv (cdr (assq 'paused (curl-token-stream-stats token))))
               (resp (vector-ref v 0)))
           (curl-token-wait token 20000)
           (sleep-ms 200)
           (say "~a asked=~a all-put-ms=~a handed-after-puts=~a handed-at-2.9s=~a recv-paused-at-2.9s=~a resp-bytes-after-puts=~a resp-first-ms=~a resp-last-ms=~a resp-bytes=~a resp-pattern=~a resp-eof=~a done-ms=~a ~a handed=~a reads=~a pauses=~a resumes=~a recv-pauses=~a"
                label asked put-ms handed (vector-ref v 5) (vector-ref v 6) resp (and (vector-ref v 4) (ms (- (vector-ref v 4) t0)))
                (and (vector-ref v 2) (ms (- (vector-ref v 2) t0))) (vector-ref v 0) (or (vector-ref v 1) "ok")
                (vector-ref v 3) (done-ms token t0) (outcome-text (curl-token-outcome token))
                (stat token 'handed) (stat token 'reads) (stat token 'pauses) (stat token 'resumes)
                (cdr (assq 'pauses (curl-token-stream-stats token))))))))
    (say "~a events: ~a" label (events-text (curl-token-upload-events token) t0))
    (for-each (lambda (line) (unless (string=? line "") (say "~a server: ~a" label line))) (server-log tag))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (face)
              (for-each (lambda (how)
                          (for-each (lambda (framing) (lost r face how framing)) '(sized chunked)))
                        '(reset fin)))
            '(raw https h2))
  (direction r 'send-paused)
  (direction r 'recv-paused)
  (direction r 'recv-paused-small)
  (direction r 'recv-flowing))
(curl-engine-stop log-engine)
(say "hazards done")
