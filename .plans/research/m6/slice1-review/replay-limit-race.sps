#!r6rs
;;; test-stream's "a body limit crossed in a replay" with its race made
;;; deterministic (M6 slice 1's review). The test takes one piece, whose look
;;; queues the resume, then waits for the token to be done, looking no more.
;;; It passes only when the take's removal lands before the engine's replay:
;;; a replay that comes first finds the piece still counted, pauses again,
;;; and no look follows to resume it. Here the gate seam holds the take
;;; between its look and its removal until the engine has resumed, as a
;;; descheduled taker would be held. Prints:
;;;
;;;   (window PAUSED-AGAIN RESUMES)   the engine's resume ran inside the window
;;;   (done-within-3s BOOLEAN)        the test's own wait would see #f too
;;;   (after-one-more-look OUTCOME)   a further look resumes it: body-limit
;;;
;;; Run from a tree's root, in the container:
;;;   scripts/guix-env sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m6/slice1-review/replay-limit-race.sps' < /dev/null
(import (chezscheme) (curl) (curl private engine) (curl-testing))

(define (show d) (write d) (newline) (flush-output-port (current-output-port)))
(define (stat t k) (cdr (assq k (curl-token-stream-stats t))))
(define (wait-for thunk ms)
  (let loop ((i 0))
    (or (thunk) (and (< i ms) (begin (sleep (make-time 'time-duration 1000000 0)) (loop (+ i 1)))))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'raw))
          (url (string-append "http://" (car f) ":" (number->string (cdr f))
                              "/raw/pattern?key=race&bytes=3000&chunk=1000&gap=300&framing=chunked"))
          (engine (make-curl-engine))
          (t (curl-submit engine (make-curl-request url 'proxy #f 'timeout-ms 60000
                                                    'stream-buffer 1 'body-limit 1999)))
          (paused (wait-for (lambda () (and (stat t 'paused) (not (stat t 'queued)))) 20000))
          (resumes (stat t 'resumes)))
     (curl-token-plant! t 'gate)
     (fork-thread (lambda () (curl-token-next-piece t 5000)))
     (wait-for (lambda () (eq? (curl-token-gate t) 'waiting)) 10000)
     (let ((resumed (wait-for (lambda () (and (> (stat t 'resumes) resumes) (stat t 'paused))) 10000)))
       (show (list 'window (and paused resumed #t) (stat t 'resumes)))
       (curl-token-open-gate! t)
       (show (list 'done-within-3s (curl-token-wait t 3000)))
       (curl-token-next-piece t 5000)
       (curl-token-wait t 10000)
       (let ((o (curl-token-outcome t)))
         (show (list 'after-one-more-look
                     (if (curl-transfer-error? o)
                         (list (curl-transfer-error-reason o) (curl-transfer-error-code o))
                         o))))
       (curl-engine-stop engine)))))
