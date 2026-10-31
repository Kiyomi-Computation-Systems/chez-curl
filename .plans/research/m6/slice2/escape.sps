;;; M6 slice 2, item 5 (2026-10-30): the put's escape (the M6 plan, section
;;; 3.5): the first review's SIGINT recipe (research/m6/review/take-escape.sps;
;;; traps.md, "a Chez timer that runs out inside a critical section ..."),
;;; as slice 1's escape.sps used it against the take, here against the put
;;; that commits inside its hold.
;;;
;;;   scheme --libdirs build/m6s2/src --program escape.sps HTTP RAW HTTPS H2 CA RUNS
;;;
;;; Linux alone: it binds libc's kill and getpid. Each case, on an engine of
;;; its own: a streamed post, chunked, to /sink?want=15 on the raw face. Once
;;; room-wait answers #t, libcurl has asked and the read callable has
;;; paused. Another thread holds the request stream's mutex through
;;; call-with-upload-held, the prototype's seam; once this thread is about
;;; to put, it sleeps 100 ms, so the put blocks on the mutex inside its
;;; critical section, sends SIGINT to the process (Linux offers it to the
;;; main thread), sleeps 100 ms more, and lets go. The keyboard-interrupt
;;; handler raises, escaping as the put's section ends, or returns. The
;;; first put is piece 1, bytes 0 to 4 of i mod 251; then, the handler
;;; quiet again, pieces 2 and 3, bytes 5 to 14, and the end. Each line: how
;;; the first put ended, curl-token-body-count right after it and at the
;;; end, the bytes handed, and what the server received: 15 bytes in
;;; order (pattern=ok) when piece 1 was committed; 10, bytes 5 to 14
;;; (pattern=bad@0), when it was lost.
;;;
;;; Each case runs the committed put, the plan's, and the control, a put
;;; that commits after its hold (the prototype's private switch).
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

(load-shared-object "libc.so.6")
(define kill (foreign-procedure "kill" (int int) int))
(define getpid (foreign-procedure "getpid" () int))
(define sigint 2)

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (msd n) (make-time 'time-duration (* n 1000000) 0))

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
  (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
        ((curl-transfer-error? o)
         (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
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

;; sink-fields : String -> String
;; The sink line's bytes, pattern and want_sha fields.
(define (sink-fields line)
  (let ((words (let loop ((cs (string->list line)) (cur '()) (acc '()))
                 (cond ((null? cs) (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
                       ((char=? (car cs) #\space) (loop (cdr cs) '() (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
                       (else (loop (cdr cs) (cons (car cs) cur) acc))))))
    (apply string-append
           (map (lambda (w) (string-append w " "))
                (filter (lambda (w) (exists (lambda (p) (and (>= (string-length w) (string-length p))
                                                             (string=? (substring w 0 (string-length p)) p)))
                                            '("bytes=" "pattern=" "want_sha=")))
                        words)))))

;; one : Natural Boolean Boolean -> Void
(define (one r escaping control)
  (set-put-commits-after-hold! control)
  (let* ((tag (format "escape.~a.~a.r~a" (if escaping "escapes" "returns") (if control "control" "committed") r))
         (engine (make-curl-engine))
         (token (curl-submit engine (curl-request-with-body-stream
                                     (make-curl-request (string-append "http://" (cdr (assq 'raw faces)) "/sink?want=15&tag=" tag)
                                                        'method 'post 'proxy #f 'timeout-ms 10000)
                                     #f)))
         (asked (curl-token-room-wait token 5000))
         (paused (let loop ((i 0)) (or (stat token 'send-paused) (and (< i 1000) (begin (sleep (msd 1)) (loop (+ i 1)))))))
         (ready #f)
         (in-put #f))
    (keyboard-interrupt-handler (lambda () (when escaping (raise 'interrupted))))
    (fork-thread
     (lambda ()
       (call-with-upload-held token
         (lambda ()
           (set! ready #t)
           (let loop () (unless in-put (sleep (msd 1)) (loop)))
           (sleep (msd 100))
           (kill (getpid) sigint)
           (sleep (msd 100))))))
    (let loop () (unless ready (sleep (msd 1)) (loop)))
    (let* ((first (guard (e ((eq? e 'interrupted) 'escaped))
                    (set! in-put #t)
                    (let ((a (curl-token-put-piece! token (pattern-piece 0 5) 5000)))
                      (list 'returned a))))
           (count-after (curl-token-body-count token)))
      (keyboard-interrupt-handler (lambda () (void)))
      (set-put-commits-after-hold! #f)
      (let* ((a2 (curl-token-put-piece! token (pattern-piece 5 5) 5000))
             (a3 (curl-token-put-piece! token (pattern-piece 10 5) 5000)))
        (curl-token-end-body! token)
        (curl-token-wait token 10000)
        (let ((sink (find (lambda (line) (and (> (string-length line) 4) (string=? (substring line 0 4) "sink")))
                          (server-log tag))))
          (say "escape run=~a handler=~a put=~a asked=~a paused=~a first=~a count-after-first=~a puts-2-3=~a count-at-end=~a handed=~a ~a server: ~a"
               r (if escaping "escapes" "returns") (if control "control-commits-after-hold" "committed-in-hold")
               asked (and paused #t) first count-after (list a2 a3) (curl-token-body-count token)
               (stat token 'handed) (outcome-text (curl-token-outcome token)) (if sink (sink-fields sink) "none")))))
    (curl-engine-stop engine)
    (set-put-commits-after-hold! #f)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (control)
              (one r #f control)
              (one r #t control))
            '(#f #t)))
(curl-engine-stop log-engine)
(say "escape done")
