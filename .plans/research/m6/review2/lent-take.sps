;; M6 plan, second review (2026-10-29): does the plan's lent take (section
;; 3.5) lose a resume, against a write callable on another thread?
;;
;; A model of the response stream with the plan's rules, built as kindly
;; as the plan allows, so only its order of operations is on trial:
;;
;;   - the engine's thread (a forked thread here) offers chunks one after
;;     another, as libcurl does. The write callable, in one hold of the
;;     stream's mutex, takes the chunk when the buffer is empty or holds
;;     less than LIMIT with it added; otherwise it sets the paused bit and
;;     answers PAUSE, keeping the chunk. A resume message (a flag under the
;;     engine's mutex) makes it clear the bit and the queued flag in one
;;     hold, then offer the kept chunk again, as curl_easy_pause replays;
;;   - the consumer takes as section 3.5 says: inside one critical section,
;;     a stream hold that copies the first piece and leaves it in place,
;;     and decides the resume there, counting the buffer as it will be once
;;     the piece is removed (paused bit set, no resume queued, and at or
;;     below half of LIMIT); then the queueing hold of the engine's mutex.
;;     After the section, plain writes remove the piece, the last thing
;;     before the take returns. The removal writes only consumer-owned
;;     fields (the queue's head and a taken count), so no update is lost:
;;     the engine counts the buffer as appended - taken.
;;   - the consumer waits for a piece by polling, 50 us apart, as the
;;     engine's waits do. A wait that sees no piece for 500 ms while the
;;     bit is set and no resume is queued is a stall: nothing will ever
;;     resume the stream. It is counted, then repaired by a forced resume,
;;     so the run goes on.
;;
;; The fixed case is the lent take, and every look of the consumer's wait
;; that finds no piece also re-arms the resume, level-triggered: holding
;; the engine's mutex then the stream's (the plan's lock order), it queues
;; one when the bit is set, none is queued, and the buffer is at or below
;; half. It should never stall; rearms counts the looks that queued a
;; resume no take had, each a stall the lent take would have had.
;;
;; The shared case is the lent take with one byte count both threads write,
;; the write callable inside its hold and the take's removal by its plain
;; write after: drift is that count minus the bytes the queue holds, read
;; once the run ends, when both threads are quiet. It should be 0.
;;
;; The control removes the piece inside the take's hold (which the plan
;; rejects because a Ctrl-C at the section's end then loses it): it should
;; never stall. The planted case gates the engine's offer into the window
;; between the take's section and its removal, to show the interleaving
;; by itself.
;;
;; Run from the repository's root:
;;   scripts/guix-env sh -c '$CHEZ --program .plans/research/m6/review2/lent-take.sps' < /dev/null
(import (chezscheme))

(define (say . xs) (for-each display xs) (newline) (flush-output-port (current-output-port)))
(define (us n) (make-time 'time-duration (* n 1000) 0))
(define (now-ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (/ (time-nanosecond t) 1e6))))

(define CHUNK 16)
(define LIMIT 16)

;; run : Symbol Natural -> Void
;; MODE: lent (the plan), control (removal inside the hold), planted (lent,
;; with the engine's offer gated into the window), fixed (lent, and each
;; look of the wait re-arms the resume). N pieces.
(define (run mode n)
  (let* ([m (make-mutex)]          ; the stream's mutex
         [em (make-mutex)]         ; the engine's mutex
         [sentinel (cons #f '())]
         [head sentinel]           ; consumer-owned
         [taken 0]                 ; consumer-owned
         [tail sentinel]           ; engine-owned
         [appended 0]              ; engine-owned
         [paused #f]               ; under m
         [flag #f]                 ; under m
         [resume-queued #f]        ; under em
         [offers 0] [pauses 0] [resumes 0]
         [stalls 0] [rearms 0]
         [count 0]                 ; shared mode: written by both threads
         [done #f]
         [gate-open #f] [in-window #f]   ; planted only
         [locked (lambda (mx thunk) (critical-section (with-mutex mx (thunk))))])
    (define (offer! chunk)
      ;; the write callable: #t taken, #f paused
      (locked m
        (lambda ()
          (set! offers (+ offers 1))
          (let ([buffered (if (eq? mode 'shared) count (- appended taken))])
            (if (or (= buffered 0) (< (+ buffered (bytevector-length chunk)) LIMIT))
                (let ([node (cons chunk '())])
                  (set-cdr! tail node)
                  (set! tail node)
                  (set! appended (+ appended (bytevector-length chunk)))
                  (set! count (+ count (bytevector-length chunk)))
                  #t)
                (begin (set! paused #t) (set! pauses (+ pauses 1)) #f))))))
    (define (engine)
      (let loop ([i 0] [pending (make-bytevector CHUNK 0)] [held #f] [free #t])
        (cond
          [(= i n) (locked em (lambda () (set! done #t)))]
          [held
           ;; paused: wait for a resume message, as the engine's poll does
           (let ([r (locked em (lambda () (let ([r resume-queued]) (set! resume-queued #f) r)))])
             (if r
                 (begin
                   (locked m (lambda () (set! paused #f) (set! flag #f)))
                   (set! resumes (+ resumes 1))
                   (loop i pending #f #t))
                 (begin (sleep (us 20)) (loop i pending #t #f))))]
          [else
           (when (and (eq? mode 'planted) (not free))
             ;; offer only while the consumer sits in its window; the
             ;; first offer and a resume's replay go at once
             (let wait () (unless (locked em (lambda () in-window)) (sleep (us 5)) (wait))))
           (let ([ok (offer! pending)])
             (when (and (eq? mode 'planted) (not free)) (locked em (lambda () (set! gate-open #t))))
             (if ok
                 (loop (+ i 1) (make-bytevector CHUNK (mod (+ i 1) 251)) #f #f)
                 (loop i pending #t #f)))])))
    (define (take!)
      ;; one look: the piece, or #f
      (if (eq? mode 'control)
          (critical-section
           (let ([r (with-mutex m
                      (let ([first (cdr head)])
                        (and (pair? first)
                             (let* ([p (car first)]
                                    [after (- appended taken (bytevector-length p))]
                                    [q (and paused (not flag) (<= after (div LIMIT 2)))])
                               (when q (set! flag #t))
                               (set! head first)
                               (set! taken (+ taken (bytevector-length p)))
                               (cons p q)))))])
             (when (and r (cdr r)) (with-mutex em (set! resume-queued #t)))
             (and r (car r))))
          (let ([r (critical-section
                    (let ([r (with-mutex m
                               (let ([first (cdr head)])
                                 (and (pair? first)
                                      (let* ([p (car first)]
                                             [after (- appended taken (bytevector-length p))]
                                             [q (and paused (not flag) (<= after (div LIMIT 2)))])
                                        (when q (set! flag #t))
                                        (list first p q)))))])
                      (when (and r (caddr r)) (with-mutex em (set! resume-queued #t)))
                      r))])
            (when (and r (eq? mode 'planted))
              ;; the window: let the engine offer, then go on
              (locked em (lambda () (set! gate-open #f) (set! in-window #t)))
              (let wait () (unless (locked em (lambda () (or gate-open done))) (sleep (us 5)) (wait)))
              (locked em (lambda () (set! in-window #f))))
            (and r
                 (begin
                   ;; the plain writes, the last thing before the take returns
                   (set! head (car r))
                   (set! taken (+ taken (bytevector-length (cadr r))))
                   (set! count (- count (bytevector-length (cadr r))))
                   (cadr r))))))
    (let ([t0 (now-ms)])
      (fork-thread engine)
      (let loop ([got 0] [bytes 0])
        (if (and (= got n))
            (say "lent-take mode=" mode " pieces=" got " bytes=" bytes " offers=" offers
                 " pauses=" pauses " resumes=" resumes " stalls=" stalls " rearms=" rearms
                 (if (eq? mode 'shared) (format " drift=~a" (- count (- appended taken))) "")
                 " ms=" (round (- (now-ms) t0)))
            (let wait ([since (now-ms)])
              (let ([p (take!)])
                (if p
                    (loop (+ got 1) (+ bytes (bytevector-length p)))
                    (let ([_ (when (eq? mode 'fixed)
                               (critical-section
                                (with-mutex em
                                  (with-mutex m
                                    (when (and paused (not flag) (<= (- appended taken) (div LIMIT 2)))
                                      (set! flag #t)
                                      (set! rearms (+ rearms 1))
                                      (set! resume-queued #t))))))]
                          [stuck (locked m (lambda () (and paused (not flag))))]
                          [q (locked em (lambda () resume-queued))])
                      (if (and stuck (not q) (> (- (now-ms) since) 500))
                          (begin
                            (set! stalls (+ stalls 1))
                            (when (<= stalls 3)
                              (say "lent-take mode=" mode " stall at piece " got
                                   ": no piece, the bit set, no resume queued, for 500 ms"))
                            ;; repair, so the run goes on
                            (locked m (lambda () (set! flag #t)))
                            (locked em (lambda () (set! resume-queued #t)))
                            (wait (now-ms)))
                          (begin (sleep (us 50)) (wait since))))))))))))

(run 'planted 5)
(run (quote control) 50000)
(run (quote lent) 50000)
(run (quote fixed) 50000)
(run (quote shared) 50000)
(say "lent-take done")
