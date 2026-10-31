#!r6rs
;;; Review probe (M6 slice 2, read-only review): two puts made while the
;;; engine is held, inside one pause of the send. The plan (section 3.3)
;;; says a put queues a resume "when the transfer is paused for sending,
;;; once". Prints the upload's pauses and resumes, and the token's outcome.
(import (rnrs)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond)
        (curl-testing)
        (curl)
        (curl private engine))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))
(define (pause-ms ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))
(define (wait-for thunk ms)
  (let ((deadline (+ (now-ms) ms)))
    (let loop () (or (thunk) (and (< (now-ms) deadline) (begin (pause-ms 1) (loop)))))))
(define (ustat t key) (cdr (assq key (curl-token-upload-stats t))))
(define (send-paused? t) (and (ustat t 'paused) (not (ustat t 'queued))))

(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'http))
          (url (string-append "http://" (car f) ":" (number->string (cdr f)) "/sink?key=once-probe"))
          (engine (make-curl-engine))
          (t (curl-submit engine (make-curl-request url 'method 'post 'proxy #f 'timeout-ms 20000
                                                    'body 'stream))))
     (curl-token-room-wait t 20000)
     (let ((paused (wait-for (lambda () (send-paused? t)) 10000)))
       (call-with-engine-held engine
         (lambda ()
           (curl-token-put-piece! t (make-bytevector 1 0) 0)
           (curl-token-put-piece! t (make-bytevector 1 1) 0)))
       (wait-for (lambda () (= (ustat t 'handed) 2)) 10000)
       (wait-for (lambda () (send-paused? t)) 10000)
       (let ((pauses (ustat t 'pauses)) (resumes (ustat t 'resumes)))
         (curl-token-end-body! t)
         (curl-token-wait t 20000)
         (write (list 'once-probe 'paused-first paused 'pauses-before-end pauses
                      'resumes-before-end resumes 'status
                      (let ((r (curl-token-outcome t))) (if (curl-response? r) (curl-response-status r) r))))
         (newline)))
     (curl-engine-stop engine))))
