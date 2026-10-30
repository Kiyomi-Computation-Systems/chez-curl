;; M6 plan, second review (2026-10-29): does the plan's committed put
;; (section 3.5) lose a resume, against a read callable on another thread?
;;
;; A model of the request stream with the plan's rules, as kindly as the
;; plan allows:
;;
;;   - the engine's thread (a forked thread here) calls the read callable
;;     whenever the transfer is not paused, as libcurl does. In one hold of
;;     the stream's mutex it takes the next committed piece, or, with
;;     nothing committed, sets the send bit and answers PAUSE. A resume
;;     message (a flag under the engine's mutex) makes it clear the bit and
;;     the queued flag in one hold; the read callable runs again at the next
;;     perform, as libcurl resumes a read;
;;   - the put, as section 3.5 says: inside one critical section, a stream
;;     hold that links the piece in uncommitted and decides the resume
;;     (send bit set, none queued), then the queueing hold of the engine's
;;     mutex; after the section, a plain write commits the piece, the last
;;     thing before the put returns. The commit writes a field only the
;;     putting thread writes, so no update is lost;
;;   - the producer is full-duplex: after each put it waits, polling 50 us
;;     apart, until the read callable has taken that piece, as a caller
;;     waits for a server's answer to it. A wait that sees its piece untaken
;;     for 500 ms while the bit is set and no resume is queued is a stall:
;;     nothing will resume the read. It is counted, then repaired by a
;;     forced resume, so the run goes on.
;;
;; The committed-in-hold case commits inside the put's hold instead, so the
;; read callable and the put's resume decision see one state: it should
;; never stall. It needs a put a retry can repeat safely (an offset, the
;; review's fix), which this model does not exercise.
;;
;; Run from the repository's root:
;;   scripts/guix-env sh -c '$CHEZ --program .plans/research/m6/review2/committed-put.sps' < /dev/null
(import (chezscheme))

(define (say . xs) (for-each display xs) (newline) (flush-output-port (current-output-port)))
(define (us n) (make-time 'time-duration (* n 1000) 0))
(define (now-ms) (let ([t (current-time 'time-monotonic)]) (+ (* 1000 (time-second t)) (/ (time-nanosecond t) 1e6))))

(define PIECE 16)

;; run : Symbol Natural -> Void
;; MODE: lent (the plan's commit after the section) or in-hold. N pieces.
(define (run mode n)
  (let* ([m (make-mutex)] [em (make-mutex)]
         [sentinel (cons #f '())]
         [tail sentinel]        ; the putting thread's
         [committed 0]          ; the putting thread's
         [head sentinel]        ; the engine's
         [consumed 0]           ; the engine's
         [paused #f] [flag #f]  ; under m
         [resume-queued #f]     ; under em
         [stop #f]              ; under em
         [reads 0] [pauses 0] [resumes 0] [stalls 0]
         [locked (lambda (mx thunk) (critical-section (with-mutex mx (thunk))))])
    (define (read-callable!)
      ;; #t took a piece, #f paused
      (locked m
        (lambda ()
          (set! reads (+ reads 1))
          (if (> (- committed consumed) 0)
              (let ([node (cdr head)])
                (set! head node)
                (set! consumed (+ consumed (bytevector-length (car node))))
                #t)
              (begin (set! paused #t) (set! pauses (+ pauses 1)) #f)))))
    (define (engine)
      (let loop ([held #f])
        (unless (locked em (lambda () stop))
          (if held
              (let ([r (locked em (lambda () (let ([r resume-queued]) (set! resume-queued #f) r)))])
                (if r
                    (begin (locked m (lambda () (set! paused #f) (set! flag #f)))
                           (set! resumes (+ resumes 1))
                           (loop #f))
                    (begin (sleep (us 20)) (loop #t))))
              (loop (not (read-callable!)))))))
    (define (put! piece)
      (let ([node (cons piece '())])
        (if (eq? mode 'in-hold)
            (critical-section
             (let ([q (with-mutex m
                        (set-cdr! tail node)
                        (set! tail node)
                        (set! committed (+ committed (bytevector-length piece)))
                        (let ([q (and paused (not flag))]) (when q (set! flag #t)) q))])
               (when q (with-mutex em (set! resume-queued #t)))))
            (begin
              (critical-section
               (let ([q (with-mutex m
                          (set-cdr! tail node)
                          (let ([q (and paused (not flag))]) (when q (set! flag #t)) q))])
                 (when q (with-mutex em (set! resume-queued #t)))))
              ;; the plain writes, the last thing before the put returns
              (set! tail node)
              (set! committed (+ committed (bytevector-length piece)))))))
    (let ([t0 (now-ms)])
      (fork-thread engine)
      (let loop ([i 0])
        (if (= i n)
            (begin
              (locked em (lambda () (set! stop #t)))
              (say "committed-put mode=" mode " pieces=" i " reads=" reads " pauses=" pauses
                   " resumes=" resumes " stalls=" stalls " ms=" (round (- (now-ms) t0))))
            (begin
              (put! (make-bytevector PIECE (mod i 251)))
              (let wait ([since (now-ms)])
                (unless (locked m (lambda () (>= consumed committed)))
                  (let ([stuck (locked m (lambda () (and paused (not flag))))]
                        [q (locked em (lambda () resume-queued))])
                    (if (and stuck (not q) (> (- (now-ms) since) 500))
                        (begin
                          (set! stalls (+ stalls 1))
                          (when (<= stalls 3)
                            (say "committed-put mode=" mode " stall at piece " i
                                 ": the piece unread, the bit set, no resume queued, for 500 ms"))
                          (locked m (lambda () (set! flag #t)))
                          (locked em (lambda () (set! resume-queued #t)))
                          (wait (now-ms)))
                        (begin (sleep (us 50)) (wait since))))))
              (loop (+ i 1))))))))

(run 'in-hold 50000)
(run 'lent 50000)
(say "committed-put done")
