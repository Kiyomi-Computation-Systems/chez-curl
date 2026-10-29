;;; M5 slice 4's group measurement (2026-10-28; the M5 plan, section 7.1).
;;; Through (curl) alone, as the group will run: one engine per group, as a
;;; session has, one mailbox, every token taken from it on this thread.
;;;
;;;   scheme --libdirs src --program probe.sps RAW RUNS
;;;
;;; RAW is the origin's raw face, ADDRESS:PORT. Each run makes two groups,
;;; each on an engine of its own, of 20 drips, /raw/drip?bytes=5&gap=100,
;;; each about 500 ms of gaps:
;;;   all     the 20 submitted at once;
;;;   limit2  2 submitted, then one more each time a token is taken, so at
;;;           most 2 are live.
;;; A group's time runs from its first submit to its 20th take, by the
;;; monotonic clock, read where the 20th take answers. Each line names the
;;; group, its time, the most live at once by this program's count, and its
;;; outcomes: status=N for a response, by count, and code=N for a failure,
;;; by its libcurl code, or the condition's kind.
(import (chezscheme) (curl))

(define args (command-line-arguments))
(define raw (car args))
(define runs (string->number (cadr args)))
(define url (string-append "http://" raw "/raw/drip?bytes=5&gap=100"))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (quotient (time-nanosecond t) 1000000))))

(define (outcome-label token)
  (let ((o (curl-token-outcome token)))
    (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
          ((curl-transfer-error? o) (format "code=~a" (curl-transfer-error-code o)))
          ((curl-engine-error? o) (format "engine=~a" (curl-engine-error-reason o)))
          (else "other"))))

(define (tally labels)
  (let loop ((labels (list-sort string<? labels)) (acc '()))
    (if (null? labels)
        (reverse acc)
        (let ((n (length (filter (lambda (l) (string=? l (car labels))) labels))))
          (loop (list-tail labels n) (cons (format "~a x~a" (car labels) n) acc))))))

;; group : Symbol (U Natural #f) -> Void
(define (group name limit)
  (let* ((engine (make-curl-engine))
         (mailbox (make-curl-mailbox))
         (request (make-curl-request url 'proxy #f 'timeout-ms 30000))
         (total 20)
         (start (now-ms)))
    (let loop ((submitted 0) (live 0) (taken '()) (most 0))
      (cond
       ((and (< submitted total) (or (not limit) (< live limit)))
        (curl-submit engine request mailbox)
        (loop (+ submitted 1) (+ live 1) taken (max most (+ live 1))))
       ((= (length taken) total)
        (let ((elapsed (- (now-ms) start)))
          (printf "~a ms=~a most-live=~a ~a~%" name elapsed most
                  (apply string-append
                         (map (lambda (s) (string-append s " ")) (tally (map outcome-label taken)))))))
       ((> (- (now-ms) start) 60000)
        (printf "~a gave up at 60 s, ~a taken~%" name (length taken)))
       (else
        (let ((token (curl-mailbox-take mailbox 100)))
          (if token
              (loop submitted (- live 1) (cons token taken) most)
              (loop submitted live taken most))))))
    (curl-engine-stop engine)))

(printf "libcurl ~a~%" (libcurl-info-version (loaded-libcurl)))
(do ((i 1 (+ i 1))) ((> i runs))
  (group 'all #f)
  (group 'limit2 2))
