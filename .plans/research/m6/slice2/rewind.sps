;;; M6 slice 2, item 2 (2026-10-30): the seek and prerequest callables
;;; through the engine (the M6 plan, sections 2.1, 3.3 and 5.1; ADR-0032).
;;;
;;;   scheme --libdirs build/m6s2/src --program rewind.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; The pooled cases, the C probe's U-rewind shape, on the raw face: on an
;;; engine of its own, a GET of /close-after?then=THEN, then GAP ms on, the
;;; streamed post to /sink?want=SIZE, both under one tag, so the post meets
;;; the GET's pooled connection unless FRESH_CONNECT keeps it off it:
;;;
;;;   fin        the server closed the pooled connection 50 ms after its
;;;              answer;
;;;   kill       it reads the post whole, its body too, then cuts it;
;;;   cuthead    it cuts the post as its head arrives, a FIN, no body read;
;;;   resethead  the same by RST;
;;;   reset      it resets the post's connection once AT body bytes arrived.
;;;
;;; The producer is fast, room-wait then every 16 KiB piece at once, or late:
;;; room-wait, then 500 ms with nothing put, then every piece; then the end.
;;; Each pooled case runs with the prototype's FRESH_CONNECT switch off, so
;;; the dead connection is met, and on, the plan's.
;;;
;;; The HTTP/2 cases, on the h2 face, on an engine of their own: /refuse,
;;; whose first stream of a tag is reset with REFUSED_STREAM once 32 KiB of
;;; DATA arrived (fast), or at its headers, before any DATA (at=0, late);
;;; FRESH_CONNECT on and off; the late refusal also with the prerequest
;;; callable's clearing of the send bit switched off; and the control, /sink
;;; with the late producer and no refusal, where nothing resumes the read for
;;; 500 ms.
;;;
;;; Each line: the outcome, the prerequest calls, seeks, reads, pauses and
;;; resumes, the bytes handed, whether a read came after the second
;;; prerequest call with no resume between (resend-read-unpaused), and the
;;; event log, each event's time in ms from the post's submit:
;;;   R<room>/<buffered>:<answer>   a read call, ! when inside curl_easy_pause
;;;   S<offset>/<origin>:<answer>   a seek call
;;;   P<n>:<answer>:port<p>:send<bit>:handed<h>   a prerequest call, the
;;;                                 send bit as it found it
;;;   Z<code>:send<bit>             the resume step's curl_easy_pause
;;;   E                             the body's end
;;; then the server's log for the tag.
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

;; events-text : (Listof List) Integer -> String
;; The first 60 events and the last 10, with a count between.
(define (events-text events t0)
  (let* ((n (length events))
         (shown (if (<= n 70)
                    (map (lambda (e) (event-text e t0)) events)
                    (append (map (lambda (e) (event-text e t0)) (list-head events 60))
                            (list (format "...~a-more..." (- n 70)))
                            (map (lambda (e) (event-text e t0)) (list-tail events (- n 10)))))))
    (apply string-append (map (lambda (s) (string-append s " ")) shown))))

;; resend-read-unpaused : (Listof List) -> Symbol
;; After the second prerequest call: yes, a read came with no resume
;; between; no, a resume came first, or no read came; na, no second call.
(define (resend-read-unpaused events)
  (let ((after (let loop ((es events))
                 (cond ((null? es) #f)
                       ((and (eq? (caar es) 'prereq) (= (caddr (car es)) 2)) (cdr es))
                       (else (loop (cdr es)))))))
    (if (not after)
        'na
        (let loop ((es after))
          (cond ((null? es) 'no-read)
                ((eq? (caar es) 'read) 'yes)
                ((eq? (caar es) 'resume) 'resume-first)
                (else (loop (cdr es))))))))

;; produce : Token Natural Symbol -> (Listof Any)
;; The producer: room-wait, then, late, 500 ms with nothing put; then every
;; 16 KiB piece, each with a bound of 2,000 ms, stopping at an answer other
;; than #t; then the end. Answers the answers other than #t.
(define (produce token n how)
  (let ((asked (curl-token-room-wait token 5000)))
    (when (eq? how 'late) (sleep-ms 500))
    (let loop ((at 0) (odd (if (eq? asked #t) '() (list (list 'room-wait asked)))))
      (if (>= at n)
          (begin (curl-token-end-body! token) (reverse odd))
          (let* ((k (min 16384 (- n at)))
                 (a (guard (e (#t (list 'raised (if (curl-request-error? e) (curl-request-error-reason e) e))))
                      (curl-token-put-piece! token (pattern-piece at k) 2000))))
            (if (eq? a #t)
                (loop (+ at k) odd)
                (begin (curl-token-end-body! token) (reverse (cons (list at a) odd)))))))))

(define (report label token t0 tag odd)
  (let ((events (curl-token-upload-events token)))
    (say "~a ~a attempts=~a seeks=~a reads=~a pauses=~a resumes=~a handed=~a committed=~a resend-read-unpaused=~a odd-answers=~s"
         label (outcome-text (curl-token-outcome token)) (stat token 'attempts) (stat token 'seeks)
         (stat token 'reads) (stat token 'pauses) (stat token 'resumes) (stat token 'handed)
         (stat token 'committed) (resend-read-unpaused events) odd)
    (say "~a events: ~a" label (events-text events t0))
    (for-each (lambda (line) (unless (string=? line "") (say "~a server: ~a" label line)))
              (server-log tag))))

;; pooled : Natural String String Natural Natural Symbol Boolean -> Void
(define (pooled r name then gap size how fresh)
  (set-upload-fresh-connect! fresh)
  (set-prereq-clears-send! #t)
  (let* ((label (format "rewind run=~a case=pooled-~a fresh=~a" r name (if fresh "on" "off")))
         (tag (format "rewind.pooled.~a.~a.r~a" name (if fresh "on" "off") r))
         (engine (make-curl-engine))
         (get (curl-submit engine (request 'raw 'get (string-append "/close-after?then=" then) tag 10000))))
    (curl-token-wait get 10000)
    (say "~a get ~a" label (outcome-text (curl-token-outcome get)))
    (sleep-ms gap)
    (let* ((t0 (now-ns))
           (token (curl-submit engine (curl-request-with-body-stream
                                       (request 'raw 'post (format "/sink?want=~a&arr=0" size) tag 20000)
                                       size)))
           (odd (produce token size how)))
      (curl-token-wait token 20000)
      (report label token t0 tag odd))
    (curl-engine-stop engine)
    (set-upload-fresh-connect! #t)))

;; h2 : Natural String String Natural Symbol Boolean Boolean -> Void
(define (h2 r name path size how fresh clears)
  (set-upload-fresh-connect! fresh)
  (set-prereq-clears-send! clears)
  (let* ((label (format "rewind run=~a case=h2-~a fresh=~a clears-send=~a" r name (if fresh "on" "off") (if clears "on" "off")))
         (tag (format "rewind.h2.~a.~a.~a.r~a" name (if fresh "on" "off") (if clears "on" "off") r))
         (engine (make-curl-engine))
         (t0 (now-ns))
         (token (curl-submit engine (curl-request-with-body-stream (request 'h2 'post path tag 20000) size)))
         (odd (produce token size how)))
    (curl-token-wait token 20000)
    (report label token t0 tag odd)
    (curl-engine-stop engine)
    (set-upload-fresh-connect! #t)
    (set-prereq-clears-send! #t)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (fresh)
              (pooled r "fin-gap200" "fin" 200 262144 'fast fresh)
              (pooled r "fin-gap1500" "fin" 1500 262144 'fast fresh)
              (pooled r "fin-gap200-late" "fin" 200 262144 'late fresh)
              (pooled r "kill-gap200" "kill" 200 262144 'fast fresh)
              (pooled r "kill-gap1500" "kill" 1500 262144 'fast fresh)
              (pooled r "cuthead-gap200-late" "cuthead" 200 262144 'late fresh)
              (pooled r "resethead-gap200-late" "resethead" 200 262144 'late fresh)
              (pooled r "reset-at32768" "reset&at=32768" 100 262144 'fast fresh)
              (pooled r "reset-at32768-8MiB" "reset&at=32768" 100 8388608 'fast fresh)
              (pooled r "reset-at262144" "reset&at=262144" 100 262144 'fast fresh))
            '(#f #t))
  (for-each (lambda (fresh)
              (h2 r "refuse-at32768" "/refuse?want=262144&arr=0" 262144 'fast fresh #t)
              (h2 r "refuse-at0-late" "/refuse?want=262144&at=0&arr=0" 262144 'late fresh #t))
            '(#t #f))
  (h2 r "refuse-at0-late" "/refuse?want=262144&at=0&arr=0" 262144 'late #t #f)
  (h2 r "control-sink-late" "/sink?want=262144&arr=0" 262144 'late #t #t))
(curl-engine-stop log-engine)
(say "rewind done")
