;;; M6 slice 3, item 2 (2026-10-31): the drive's interleaving, through the
;;; engine (the M6 plan, sections 3.6 and 6.1).
;;;
;;;   scheme --libdirs src:tests:build/scheme-libs --program drive.sps HTTP RAW HTTPS H2 CLOSED CA KEY=VALUE...
;;;
;;; KEY=VALUE: cases=a,b,c,d (and a-control is no case: b-control and
;;; c-control are), slices=1,10,50 (S, ms), sched=strict or eager, runs=N,
;;; faces=raw,https,h2, framings=sized,chunked, bound=MS (each call's
;;; timeout-ms), control-bound=MS (a control's), mib-a=4, mib-b=16, mib-c=4,
;;; c-statuses=303,413 and c-wheres=raw-keep,raw-close,https-keep,https-close,h2
;;; (case c's), hop-cancel=0 or 1 (1: a hop whose head gave a Content-Length
;;; is cancelled once that many bytes of its body have arrived, the hop's
;;; read then waiting for the eof object as before; a variant, not the
;;; brief's drive).
;;;
;;; The drive is the high level's, at the low level alone, on this thread
;;; (the plan's section 3.6; the brief's item 2):
;;;
;;;   - the producer is a thunk answering a bytevector of 64 KiB, the last
;;;     shorter, of the pattern (byte i is i mod 251), then the eof object;
;;;     it counts every call, and any after its eof;
;;;   - it is called only after curl-token-room-wait answered #t, and then
;;;     only if no head is published, or the published head's bit is #t,
;;;     read after the room-wait; a head whose bit is #f stops the feeding
;;;     for good (state unasked). The drive holds the one piece it answered
;;;     until a put takes it, checks it against body-length before the put,
;;;     never calls the producer after the eof object, and then calls
;;;     curl-token-end-body!;
;;;   - it feeds wherever it waits: in its wait for the head, in a hop's
;;;     read whole, and inside its own port's read (a custom binary input
;;;     port over curl-token-next-piece) when no piece is ready;
;;;   - each wait is a bounded poll, unguarded, alternating: the response
;;;     side (head-wait or next-piece), then the request side (room-wait,
;;;     or put-piece! with a bound), each bounded by S ms. sched=eager
;;;     bounds a side's wait by 0 when the other side's last step made
;;;     progress, else by S (a variant, not the brief's drive).
;;;
;;; The cases, each on an engine of its own, stream-buffer 65,536:
;;;   a   sequential: post /seq, a body of mib-a MiB; the server reads it
;;;       whole, then answers 200 with mib-a MiB, read through the port;
;;;   b   full-duplex: post /echo, mib-b MiB; the server answers 200 as the
;;;       head arrives and writes each piece back as it arrives, its reading
;;;       paused while a write waits; read through the port;
;;;   b-control   b, its port never feeding: control-bound;
;;;   c   early 303 and 413 (c-statuses; any 3xx is a hop, the rest final):
;;;       post /answer-at, mib-c MiB, the server answering
;;;       once 65,536 body bytes arrived, keep-alive (raw-keep, https-keep)
;;;       or with a close (raw-close, https-close), or over h2. The 303's
;;;       body is read whole while feeding, then a get to its Location, no
;;;       body, read through a port; the 413 is read through the port while
;;;       feeding;
;;;   c-control   c, but the drive stops feeding once it sees the head:
;;;       control-bound;
;;;   d   a refused connect: post to the closed port; the producer must
;;;       never be called.
;;; Each response body is checked byte for byte against the pattern (a and
;;; b, and the 303's get) or the text "early S\n" (c); the server's log line
;;; for the request gives what it received (sha256, want_sha=ok when whole)
;;; and what it sent.
;;;
;;; One line a call, "drive ...": wall times from the submit, ms (head-ms:
;;; the head's publication, by the engine's clock; end-ms: the port's or the
;;; hop's end); MB/s, up and down bytes over the call's time; the process's
;;; CPU over the call, by Chez's time-process clock (every thread's) and
;;; /proc/self/stat (10 ms ticks); the producer's calls, those after a head,
;;; the bytes put, those after the head; the waits on each side and those
;;; that answered nothing; the outcome; then the server's log.
(import (chezscheme)
        (curl)
        (only (curl private engine) curl-token-upload-stats curl-token-stream-stats)
        (only (curl private counters) native-counts))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 closed) (list-head args 5)))
(define ca (list-ref args 5))
(define options
  (map (lambda (kv)
         (let loop ((i 0))
           (cond ((= i (string-length kv)) (error 'drive "not KEY=VALUE" kv))
                 ((char=? (string-ref kv i) #\=) (cons (string->symbol (substring kv 0 i))
                                                       (substring kv (+ i 1) (string-length kv))))
                 (else (loop (+ i 1))))))
       (list-tail args 6)))
(define (option key default)
  (let ((e (assq key options))) (if e (cdr e) default)))
(define (split s)
  (let loop ((cs (string->list s)) (cur '()) (acc '()))
    (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car cs) #\,) (loop (cdr cs) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr cs) (cons (car cs) cur) acc)))))
(define cases (map string->symbol (split (option 'cases "a,b,b-control,c,c-control,d"))))
(define slices (map string->number (split (option 'slices "10"))))
(define sched (string->symbol (option 'sched "strict")))
(define runs (string->number (option 'runs "1")))
(define face-list (map string->symbol (split (option 'faces "raw,https,h2"))))
(define framings (map string->symbol (split (option 'framings "sized,chunked"))))
(define bound (string->number (option 'bound "60000")))
(define control-bound (string->number (option 'control-bound "5000")))
(define mib 1048576)
(define size-a (* mib (string->number (option 'mib-a "4"))))
(define size-b (* mib (string->number (option 'mib-b "16"))))
(define size-c (* mib (string->number (option 'mib-c "4"))))
(define c-statuses (map string->number (split (option 'c-statuses "303,413"))))
(define c-wheres (map string->symbol (split (option 'c-wheres "raw-keep,raw-close,https-keep,https-close,h2"))))
(define hop-cancel? (string=? (option 'hop-cancel "0") "1"))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (cpu-ns) (ns-of (current-time 'time-process)))
(define (ms x) (and x (/ (round (/ x 1000)) 1000.0)))

;; proc-stat-ms : -> Natural
;; This process's utime plus stime, from /proc/self/stat, in ms (10 ms ticks);
;; 0 where there is no /proc (macOS).
(define (proc-stat-ms)
  (if (file-exists? "/proc/self/stat") (proc-stat-ms*) 0))
(define (proc-stat-ms*)
  (let* ((s (call-with-input-file "/proc/self/stat" get-line))
         (after (let loop ((i (- (string-length s) 1)))
                  (if (char=? (string-ref s i) #\)) (+ i 2) (loop (- i 1)))))
         (fields (let loop ((i after) (start after) (acc '()))
                   (cond ((= i (string-length s)) (reverse (cons (substring s start i) acc)))
                         ((char=? (string-ref s i) #\space) (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
                         (else (loop (+ i 1) start acc))))))
    (* 10 (+ (string->number (list-ref fields 11)) (string->number (list-ref fields 12))))))

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

(define (url face path tag)
  (string-append (if (memq face '(https h2)) "https://" "http://") (cdr (assq face faces)) path
                 (if (memv #\? (string->list path)) "&" "?") "tag=" tag))

(define (request face method path tag timeout . keys)
  (let ((r (apply make-curl-request (url face path tag) 'method method 'proxy #f 'timeout-ms timeout keys)))
    (if (memq face '(https h2)) (curl-request-with r 'ca-file ca) r)))

(define log-engine (make-curl-engine))
(define (server-log tag)
  (let* ((t (curl-submit log-engine
                         (make-curl-request (string-append "http://" (cdr (assq 'raw faces)) "/log?tag=" tag)
                                            'proxy #f 'timeout-ms 10000)))
         (o (begin (curl-token-wait t 15000) (curl-token-outcome t))))
    (if (curl-response? o)
        (split-lines (utf8->string (curl-response-body o)))
        (list (format "log fetch failed: ~a" (outcome-text o))))))

;; --- the producer -----------------------------------------------------------------------

(define piece-size 65536)
(define big
  (let ((bv (make-bytevector (+ piece-size 251))))
    (do ((i 0 (+ i 1))) ((= i (bytevector-length bv)) bv) (bytevector-u8-set! bv i (mod i 251)))))

;; make-producer : Natural -> (Values (-> (U Bytevector Eof)) (-> (Listof Any)))
;; A producer of TOTAL bytes of the pattern, 64 KiB a call, the last
;; shorter, then the eof object; and a thunk answering its calls, the bytes
;; it gave, and its calls after its eof.
(define (make-producer total)
  (let ((at 0) (calls 0) (eof-given #f) (after-eof 0))
    (values
     (lambda ()
       (set! calls (+ calls 1))
       (cond (eof-given (set! after-eof (+ after-eof 1)) (eof-object))
             ((>= at total) (set! eof-given #t) (eof-object))
             (else
              (let* ((n (min piece-size (- total at))) (bv (make-bytevector n)))
                (bytevector-copy! big (mod at 251) bv 0 n)
                (set! at (+ at n))
                bv))))
     (lambda () (list calls at after-eof)))))

;; --- the drive --------------------------------------------------------------------------

;; A drive: one transfer's request side and its counts. STATE is feeding,
;; ended (the eof given and curl-token-end-body! called), stopped (the
;; token done, or the control's stop at the head), unasked (a head whose
;; bit is #f), or none (a transfer with no streamed body).
(define-record-type drive
  (fields (immutable token) (immutable producer) (immutable length) (immutable slice)
          (mutable held) (mutable held-after-head) (mutable state)
          (mutable calls) (mutable calls-after-head) (mutable put) (mutable put-after-head)
          (mutable resp-waits) (mutable resp-empty) (mutable req-waits) (mutable req-empty)
          (mutable req-progress) (mutable resp-progress) (mutable unasked-at)))

(define (new-drive token producer length slice state)
  (make-drive token producer length slice #f #f state 0 0 0 0 0 0 0 0 #f #f #f))

(define (resp-bound d) (if (and (eq? sched 'eager) (drive-req-progress d)) 0 (drive-slice d)))
(define (req-bound d) (if (and (eq? sched 'eager) (drive-resp-progress d)) 0 (drive-slice d)))
(define (resp-wait! d got)
  (drive-resp-waits-set! d (+ 1 (drive-resp-waits d)))
  (unless got (drive-resp-empty-set! d (+ 1 (drive-resp-empty d))))
  (drive-resp-progress-set! d (and got #t)))
(define (req-wait! d got)
  (drive-req-waits-set! d (+ 1 (drive-req-waits d)))
  (unless got (drive-req-empty-set! d (+ 1 (drive-req-empty d)))))

;; put-held! : Drive Natural -> Boolean
(define (put-held! d ms)
  (let ((answer (curl-token-put-piece! (drive-token d) (drive-held d) ms)))
    (req-wait! d (eq? answer #t))
    (cond ((eq? answer #t)
           (let ((n (bytevector-length (drive-held d))))
             (drive-put-set! d (+ n (drive-put d)))
             (when (drive-held-after-head d) (drive-put-after-head-set! d (+ n (drive-put-after-head d)))))
           (drive-held-set! d #f)
           #t)
          ((eq? answer 'done) (drive-state-set! d 'stopped) #f)
          (else #f))))

;; feed! : Drive -> Boolean
;; One step of the request side, bounded by req-bound: whether it made
;; progress, a put taken or the body ended.
(define (feed! d)
  (let ((progress
         (and (eq? (drive-state d) 'feeding)
              (let ((token (drive-token d)) (ms (req-bound d)))
                (if (drive-held d)
                    (put-held! d ms)
                    (let ((room (curl-token-room-wait token ms)))
                      (req-wait! d (eq? room #t))
                      (cond
                        ((eq? room 'done) (drive-state-set! d 'stopped) #f)
                        ((not room) #f)
                        (else
                         (let ((head (curl-token-head token)))
                           (if (and head (not (curl-head-body-asked? head)))
                               (begin (drive-state-set! d 'unasked) (drive-unasked-at-set! d (now-ns)) #f)
                               (let ((p ((drive-producer d))) (len (drive-length d)))
                                 (drive-calls-set! d (+ 1 (drive-calls d)))
                                 (when head (drive-calls-after-head-set! d (+ 1 (drive-calls-after-head d))))
                                 (cond
                                   ((eof-object? p)
                                    (when (and len (< (drive-put d) len))
                                      (error 'drive "the producer ended short of body-length" (drive-put d) len))
                                    (curl-token-end-body! token)
                                    (drive-state-set! d 'ended)
                                    #t)
                                   ((and (bytevector? p) (> (bytevector-length p) 0))
                                    (when (and len (> (+ (drive-put d) (bytevector-length p)) len))
                                      (error 'drive "a piece past body-length" (drive-put d) len))
                                    (drive-held-set! d p)
                                    (drive-held-after-head-set! d (and head #t))
                                    (put-held! d ms))
                                   (else (error 'drive "a producer's bad answer" p))))))))))))))
    (drive-req-progress-set! d progress)
    progress))

;; wait-head! : Drive Integer -> Boolean
;; Waits for the head, or the token done, feeding between waits; #f past
;; DEADLINE, a monotonic time in ns.
(define (wait-head! d deadline)
  (let loop ()
    (let ((got (curl-token-head-wait (drive-token d) (resp-bound d))))
      (resp-wait! d got)
      (cond (got #t)
            ((> (now-ns) deadline) #f)
            (else (feed! d) (loop))))))

;; read-whole! : Drive Integer (U Natural #f) -> (Values Bytevector Boolean)
;; A hop's body, every piece, feeding between waits: its bytes, and
;; whether the eof object came before DEADLINE. With LENGTH, under
;; hop-cancel=1, the token is cancelled once LENGTH bytes have arrived.
(define (read-whole! d deadline length)
  (let loop ((pieces '()) (n 0))
    (let ((p (curl-token-next-piece (drive-token d) (resp-bound d))))
      (resp-wait! d (bytevector? p))
      (cond ((bytevector? p)
             (let ((n (+ n (bytevector-length p))))
               (when (and hop-cancel? length (>= n length) (not (curl-token-done? (drive-token d))))
                 (set! hop-cancels (+ hop-cancels 1))
                 (curl-token-cancel (drive-token d)))
               (loop (cons p pieces) n)))
            ((eof-object? p) (values (concat (reverse pieces)) #t))
            ((> (now-ns) deadline) (values (concat (reverse pieces)) #f))
            (else (feed! d) (loop pieces n))))))
(define hop-cancels 0)

(define (concat bvs)
  (let* ((n (apply + (map bytevector-length bvs))) (out (make-bytevector n)))
    (let loop ((bvs bvs) (at 0))
      (if (null? bvs)
          out
          (begin (bytevector-copy! (car bvs) 0 out at (bytevector-length (car bvs)))
                 (loop (cdr bvs) (+ at (bytevector-length (car bvs)))))))))

;; drive-port : Drive Boolean Integer -> Binary-Input-Port
;; The drive's port over the token's pieces: with none ready it waits a
;; slice, then, when FEED?, feeds, and waits again; at the end 0 for a
;; response, the outcome raised for a failure; past DEADLINE it raises
;; drive-bound.
(define (drive-port d feed? deadline)
  (let ((at-hand #f) (offset 0) (token (drive-token d)))
    (define (read! bv start count)
      (if (and at-hand (< offset (bytevector-length at-hand)))
          (let ((k (min count (- (bytevector-length at-hand) offset))))
            (bytevector-copy! at-hand offset bv start k)
            (set! offset (+ offset k))
            k)
          (let loop ()
            (let ((p (curl-token-next-piece token (resp-bound d))))
              (resp-wait! d (bytevector? p))
              (cond
                ((bytevector? p)
                 (let ((k (min count (bytevector-length p))))
                   (bytevector-copy! p 0 bv start k)
                   (set! at-hand p)
                   (set! offset k)
                   k))
                ((eof-object? p)
                 (let ((o (curl-token-outcome token))) (if (curl-response? o) 0 (raise o))))
                ((> (now-ns) deadline) (raise 'drive-bound))
                (else (when feed? (feed! d)) (loop)))))))
    (make-custom-binary-input-port "drive" read! #f #f #f)))

;; consume : Port Symbol -> (List Symbol Natural Any Any)
;; Reads PORT to its end by get-bytevector-some: (end N BAD TEXT), BAD the
;; first offset that is not the pattern's, or #f, when CHECK is pattern;
;; TEXT the bytes as a string when CHECK is text; or (raised N BAD CAUGHT).
(define (consume port check)
  (let ((n 0) (bad #f) (v 0) (texts '()))
    (guard (e (#t (list 'raised n bad e)))
      (let loop ()
        (let ((bv (get-bytevector-some port)))
          (if (eof-object? bv)
              (list 'end n bad (and (eq? check 'text) (utf8->string (concat (reverse texts)))))
              (let ((k (bytevector-length bv)))
                (if (eq? check 'pattern)
                    (set! v (let scan ((i 0) (v v))
                              (if (fx= i k)
                                  v
                                  (begin
                                    (when (and (not bad) (not (fx= (bytevector-u8-ref bv i) v))) (set! bad (+ n i)))
                                    (scan (fx+ i 1) (if (fx= v 250) 0 (fx+ v 1)))))))
                    (set! texts (cons bv texts)))
                (set! n (+ n k))
                (loop))))))))

;; --- one call -------------------------------------------------------------------------

;; head-location : Head -> (U String #f)
(define (head-location head)
  (let ((e (find (lambda (h) (string-ci=? (car h) "location")) (curl-head-headers head))))
    (and e (cdr e))))

;; head-length : Head -> (U Natural #f)
(define (head-length head)
  (let ((e (find (lambda (h) (string-ci=? (car h) "content-length")) (curl-head-headers head))))
    (and e (string->number (cdr e)))))

(define (raised-text x)
  (cond ((eq? x 'drive-bound) "drive-bound")
        (else (outcome-text x))))

(define (consumed-text c)
  (format "~a:~a:~a~a" (car c) (cadr c) (or (caddr c) "ok")
          (cond ((eq? (car c) 'raised) (format ":~a" (raised-text (cadddr c))))
                ((cadddr c) (format ":~s" (cadddr c)))
                (else ""))))

;; call : ... -> Void
;; One call, as the header says, printed as one line and the server's log.
(define (call label face path tag total framing slice timeout feed-port? stop-at-head? kind)
  (let*-values (((producer counts) (make-producer total))
                ((engine) (make-curl-engine))
                ((t0 cpu0 st0) (values (now-ns) (cpu-ns) (proc-stat-ms)))
                ((token) (curl-submit engine
                                      (request face 'post path tag timeout 'body 'stream 'stream-buffer 65536
                                               'body-length (and (eq? framing 'sized) total))))
                ((d) (new-drive token producer (and (eq? framing 'sized) total) slice 'feeding))
                ((deadline) (+ t0 (* (+ timeout 10000) 1000000)))
                ((got-head) (wait-head! d deadline))
                ((seen-head) (now-ns))
                ((head) (curl-token-head token)))
    (when (and head stop-at-head? (eq? (drive-state d) 'feeding)) (drive-state-set! d 'stopped))
    (let* ((status (and head (curl-head-status head)))
           (result
            (cond
              ((not head) (list 'no-head))
              ((and (eq? kind 'c) (<= 300 status 399))
               (let-values (((body ended) (read-whole! d deadline (head-length head))))
                 (let ((hop-end (now-ns)) (hop-outcome (curl-token-outcome token)) (to (head-location head)))
                   (if (and ended to)
                       (let* ((get (curl-submit engine (request face 'get to (string-append tag ".get") timeout
                                                                'stream-buffer 65536)))
                              (gd (new-drive get #f #f slice 'none))
                              (c (consume (drive-port gd #f deadline) 'pattern)))
                         (list 'hop (utf8->string body) ended hop-end hop-outcome c (curl-token-outcome get) (now-ns)))
                       (list 'hop (utf8->string body) ended hop-end hop-outcome #f #f #f)))))
              (else
               (list 'port (consume (drive-port d feed-port? deadline) (if (eq? kind 'c) 'text 'pattern))
                     (now-ns))))))
      (curl-token-wait token 15000)
      (let* ((t1 (now-ns)) (cpu1 (cpu-ns)) (st1 (proc-stat-ms))
             (st (curl-token-stream-stats token)) (up (curl-token-upload-stats token))
             (head-at (cdr (assq 'head-at st)))
             (pc (counts))
             (end-at (case (car result) ((hop) (cadddr result)) ((port) (caddr result)) (else t1)))
             (down (case (car result) ((port) (cadr (cadr result))) ((hop) (string-length (cadr result))) (else 0)))
             (secs (/ (- end-at t0) 1e9)))
        (say "drive ~a S=~a sched=~a head=~a bit=~a got-head=~a head-ms=~a seen-head-ms=~a end-ms=~a head-to-end-ms=~a total-ms=~a up=~a down=~a MBps=~a cpu-ms=~a proc-stat-ms=~a calls=~a calls-after-head=~a put=~a put-after-head=~a after-eof=~a state=~a resp-waits=~a/~a req-waits=~a/~a handed=~a asked=~a ~a outcome=~a"
             label slice sched status (and head (curl-head-body-asked? head)) got-head
             (and head-at (ms (- head-at t0))) (ms (- seen-head t0)) (ms (- end-at t0))
             (and head-at (ms (- end-at head-at))) (ms (- t1 t0))
             (drive-put d) down (/ (round (* 100 (/ (+ (drive-put d) down) 1e6 (max secs 1e-9)))) 100.0)
             (ms (- cpu1 cpu0)) (- st1 st0)
             (drive-calls d) (drive-calls-after-head d) (drive-put d) (drive-put-after-head d) (caddr pc)
             (drive-state d) (drive-resp-empty d) (drive-resp-waits d) (drive-req-empty d) (drive-req-waits d)
             (cdr (assq 'handed up)) (cdr (assq 'asked up))
             (case (car result)
               ((no-head) "result=no-head")
               ((port) (format "port=~a" (consumed-text (cadr result))))
               ((hop) (format "hop-body=~s hop-ended=~a hop-outcome=~a get=~a get-outcome=~a call-end-ms=~a"
                              (cadr result) (caddr result) (outcome-text (list-ref result 4))
                              (let ((c (list-ref result 5))) (if c (consumed-text c) "-"))
                              (outcome-text (list-ref result 6))
                              (let ((g (list-ref result 7))) (and g (ms (- g t0)))))))
             (outcome-text (curl-token-outcome token)))
        (for-each (lambda (line) (say "drive ~a server: ~a" label line)) (server-log tag))
        (when (and (eq? kind 'c) (eq? (car result) 'hop))
          (for-each (lambda (line) (say "drive ~a server-get: ~a" label line)) (server-log (string-append tag ".get"))))
        (curl-engine-stop engine)))))

;; --- the cases --------------------------------------------------------------------------

(define n 0)
(define (tag-for . parts)
  (set! n (+ n 1))
  (apply string-append "drive" (append (map (lambda (p) (format ".~a" p)) parts) (list (format ".~a" n)))))

(define (case-a r slice face framing)
  (call (format "case=a face=~a framing=~a run=~a" face framing r) face
        (format "/seq?n=~a&want=~a" size-a size-a) (tag-for 'a face framing slice r)
        size-a framing slice bound #t #f 'a))

(define (case-b r slice face framing control?)
  (call (format "case=~a face=~a framing=~a run=~a" (if control? "b-control" "b") face framing r) face
        (format "/echo?want=~a" size-b) (tag-for 'b face framing slice r)
        size-b framing slice (if control? control-bound bound) (not control?) #f 'b))

(define (case-c r slice where status framing control?)
  (let* ((face (case where ((raw-keep raw-close) 'raw) ((https-keep https-close) 'https) (else 'h2)))
         (close (if (memq where '(raw-close https-close)) "&close=1" ""))
         (to "&to=%2Fbody%3Fn%3D65536%26mode%3Dlength"))
    (call (format "case=~a where=~a status=~a framing=~a run=~a" (if control? "c-control" "c") where status framing r)
          face (format "/answer-at?status=~a&after=65536~a~a" status close (if (<= 300 status 399) to ""))
          (tag-for 'c where status framing slice r)
          size-c framing slice (if control? control-bound bound) #t control? 'c)))

(define (case-d r slice framing)
  (call (format "case=d face=closed framing=~a run=~a" framing r) 'closed "/refused" (tag-for 'd framing slice r)
        size-a framing slice bound #t #f 'd))

(say "drive libcurl ~a ~a cases=~a slices=~a sched=~a runs=~a faces=~a framings=~a bound=~a control-bound=~a sizes=~a,~a,~a c-statuses=~a c-wheres=~a hop-cancel=~a"
     (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl))
     cases slices sched runs face-list framings bound control-bound size-a size-b size-c c-statuses c-wheres hop-cancel?)
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each
   (lambda (slice)
     (for-each
      (lambda (c)
        (case c
          ((a) (for-each (lambda (face) (for-each (lambda (fr) (case-a r slice face fr)) framings)) face-list))
          ((b b-control)
           (for-each (lambda (face) (for-each (lambda (fr) (case-b r slice face fr (eq? c 'b-control))) framings))
                     face-list))
          ((c c-control)
           (for-each
            (lambda (where)
              (for-each (lambda (status)
                          (for-each (lambda (fr) (case-c r slice where status fr (eq? c 'c-control))) framings))
                        c-statuses))
            (filter (lambda (w) (memq (case w ((raw-keep raw-close) 'raw) ((https-keep https-close) 'https) (else 'h2))
                                      face-list))
                    c-wheres)))
          ((d) (for-each (lambda (fr) (case-d r slice fr)) framings))
          (else (error 'drive "no such case" c))))
      cases))
   slices))
(curl-engine-stop log-engine)
(collect)
(say "drive counts ~a hop-cancels=~a" (native-counts) hop-cancels)
(say "drive done")
