;;; M6 slice 1, item 3 (2026-10-30): curl_easy_pause's longest replay, and
;;; whether the plain binding holds collections up (the M6 plan, 3.4, 4.1).
;;;
;;;   scheme --libdirs build/m6s1/src --program replay.sps HTTP RAW HTTPS H2 PROXY CA RUNS [N [SIZES]]
;;;
;;; The body: /body?n=N&pattern=zero&gzip=1 on the http face, N bytes of
;;; zeros, 64 MiB by default, gzip-encoded at level 9 (about 64 KiB on the
;;; wire for 64 MiB, written 16 KiB a write), under the hatch's
;;; ACCEPT_ENCODING "gzip", so one wire chunk decodes to megabytes. Each
;;; run, at each stream-buffer of SIZES, a comma list, by default 1, 65536,
;;; 1048576 and 16777216, three transfers, each on an engine of its own:
;;;
;;;   alone        the plain binding, no collector: each resume's time inside
;;;                curl_easy_pause, and the bytes the replay appended there;
;;;   plain        the plain binding, beside a collector;
;;;   collect-safe the __collect_safe twin, beside a collector: the contrast.
;;;
;;; Each waits for the write callable to pause the stream, holds it paused
;;; 1 s, then drains it, checking every byte is 0 and the total. A collector
;;; thread, from the pause on, calls (collect-rendezvous) back to back, 100
;;; us apart, timing each: the control is every collection asked for and
;;; done inside the 1 s hold, while no call is under way; "in a call" is
;;; every one asked for while a curl_easy_pause call ran. For each: how
;;; many, and the median and the longest wait, and for those in a call the
;;; longest time a collection ended after its call returned.
(import (chezscheme)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private native)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define faces (map cons '(http raw https h2 proxy) (list-head args 5)))
(define runs (string->number (list-ref args 6)))
(define n (if (> (length args) 7) (string->number (list-ref args 7)) 67108864))
(define sizes (if (> (length args) 8)
                  (map string->number
                       (let split ((s (list-ref args 8)) (acc '()))
                         (let ((i (let find ((i 0)) (cond ((= i (string-length s)) #f)
                                                          ((char=? (string-ref s i) #\,) i)
                                                          (else (find (+ i 1)))))))
                           (if i (split (substring s (+ i 1) (string-length s)) (cons (substring s 0 i) acc))
                               (reverse (cons s acc))))))
                  '(1 65536 1048576 16777216)))

(define (say fmt . xs) (apply printf fmt xs) (newline) (flush-output-port (current-output-port)))
(define (ns-of t) (+ (* (time-second t) 1000000000) (time-nanosecond t)))
(define (now-ns) (ns-of (current-time 'time-monotonic)))
(define (ms x) (/ (round (/ x 1000)) 1000.0))
(define (sleep-ns n) (when (> n 0) (sleep (make-time 'time-duration (mod n 1000000000) (div n 1000000000)))))

(define (request)
  (make-curl-request (string-append "http://" (cdr (assq 'http faces))
                                    (format "/body?n=~a&pattern=zero&gzip=1&chunk=16384" n))
                     'proxy #f 'timeout-ms 300000))

(define (stat token key) (cdr (assq key (curl-token-stream-stats token))))
(define (resume-events engine token)
  (filter (lambda (e) (and (eq? (car e) 'resume) (eq? (cadr e) token)))
          (cdr (assq 'events (curl-engine-probe engine)))))

(define (wait-for thunk ms)
  (let ((deadline (+ (now-ns) (* ms 1000000))))
    (let loop ()
      (or (thunk)
          (and (< (now-ns) deadline) (begin (sleep-ns 1000000) (loop)))))))

;; The collector: a thread that asks for collections, 100 us apart, until
;; told to stop, keeping each (ASKED . DONE).
(define (start-collector)
  (let ((state (vector #t '() #f)))
    (fork-thread
     (lambda ()
       (let loop ((acc '()))
         (if (vector-ref state 0)
             (let* ((c0 (now-ns)) (_ (collect-rendezvous)) (c1 (now-ns)))
               (sleep-ns 100000)
               (loop (cons (cons c0 c1) acc)))
             (begin (vector-set! state 1 acc) (vector-set! state 2 #t))))))
    state))
(define (stop-collector state)
  (vector-set! state 0 #f)
  (wait-for (lambda () (vector-ref state 2)) 30000)
  (reverse (vector-ref state 1)))

(define (median xs)
  (if (null? xs) #f (list-ref (list-sort < xs) (div (length xs) 2))))
(define (maximum xs) (if (null? xs) #f (apply max xs)))

(define (all-zero? piece)
  (let ((k (bytevector-length piece)))
    (let loop ((i 0)) (or (= i k) (and (fx= (bytevector-u8-ref piece i) 0) (loop (fx+ i 1)))))))

(define (outcome-text token)
  (let ((o (curl-token-outcome token)))
    (cond ((curl-response? o) (format "status=~a" (curl-response-status o)))
          ((curl-transfer-error? o)
           (format "failed reason=~a code=~a" (curl-transfer-error-reason o) (curl-transfer-error-code o)))
          (else (format "other ~s" o)))))

;; one : Natural Natural Symbol -> Void
(define (one r size mode)
  (set-engine-pause-binding! (if (eq? mode 'collect-safe) 'collect-safe 'plain))
  (let* ((engine (make-curl-engine))
         (token (curl-submit engine (curl-request-with-stream-buffer
                                     (curl-request-with-options (request) '(("ACCEPT_ENCODING" . "gzip")))
                                     size)))
         (label (format "replay run=~a stream-buffer=~a mode=~a" r size mode)))
    (if (not (wait-for (lambda () (stat token 'recv-paused)) 30000))
        (say "~a never paused: ~s ~a" label (curl-token-stream-stats token) (outcome-text token))
        (let* ((collector (and (not (eq? mode 'alone)) (start-collector)))
               (hold-start (now-ns)))
          (sleep-ns 1000000000)
          (let ((drain-start (now-ns)))
            (let drain ((at 0) (zero #t))
              (let ((piece (curl-token-next-piece token 120000)))
                (if (bytevector? piece)
                    (drain (+ at (bytevector-length piece)) (and zero (all-zero? piece)))
                    (let* ((collects (if collector (stop-collector collector) '()))
                           (events (resume-events engine token))
                           (calls (map (lambda (e) (list (list-ref e 4) (list-ref e 5) (list-ref e 7) (list-ref e 8)))
                                       events))
                           (longest (fold-left (lambda (best c) (if (or (not best) (> (- (cadr c) (car c)) (- (cadr best) (car best)))) c best))
                                               #f calls))
                           (control (filter (lambda (c) (and (>= (car c) hold-start) (<= (cdr c) drain-start))) collects))
                           (in-call (filter (lambda (c) (exists (lambda (k) (and (>= (car c) (car k)) (< (car c) (cadr k)))) calls))
                                            collects))
                           (past (map (lambda (c)
                                        (let ((k (find (lambda (k) (and (>= (car c) (car k)) (< (car c) (cadr k)))) calls)))
                                          (- (cdr c) (cadr k))))
                                      in-call))
                           (codes (fold-left (lambda (acc c) (if (memv (list-ref c 2) acc) acc (cons (list-ref c 2) acc)))
                                             '() (map (lambda (e) (list (list-ref e 4) (list-ref e 5) (list-ref e 6))) events))))
                      (curl-token-wait token 5000)
                      (say "~a bytes=~a whole=~a zeros=~a end=~a drain-ms=~a resumes=~a codes=~a pauses=~a queued-polls=~a queued-poll-max-ms=~a queued-polls-100ms=~a longest-call-ms=~a longest-call-appended=~a median-call-ms=~a ~a"
                           label at (= at n) zero (if (eof-object? piece) "eof" piece) (ms (- (now-ns) drain-start))
                           (length calls) codes
                           (stat token 'pauses)
                           (cdr (assq 'queued-polls (curl-engine-probe engine)))
                           (ms (cdr (assq 'queued-poll-max-ns (curl-engine-probe engine))))
                           (cdr (assq 'queued-polls-100ms (curl-engine-probe engine)))
                           (and longest (ms (- (cadr longest) (car longest))))
                           (and longest (- (cadddr longest) (caddr longest)))
                           (let ((m (median (map (lambda (c) (- (cadr c) (car c))) calls)))) (and m (ms m)))
                           (outcome-text token))
                      (when collector
                        (say "~a collects control n=~a median-ms=~a max-ms=~a; in-call n=~a median-ms=~a max-ms=~a max-past-call-end-ms=~a; all n=~a max-ms=~a"
                             label (length control)
                             (let ((m (median (map (lambda (c) (- (cdr c) (car c))) control)))) (and m (ms m)))
                             (let ((m (maximum (map (lambda (c) (- (cdr c) (car c))) control)))) (and m (ms m)))
                             (length in-call)
                             (let ((m (median (map (lambda (c) (- (cdr c) (car c))) in-call)))) (and m (ms m)))
                             (let ((m (maximum (map (lambda (c) (- (cdr c) (car c))) in-call)))) (and m (ms m)))
                             (let ((m (maximum past))) (and m (ms m)))
                             (length collects)
                             (let ((m (maximum (map (lambda (c) (- (cdr c) (car c))) collects)))) (and m (ms m))))))))))))
    (curl-engine-stop engine)))

(say "libcurl ~a ~a" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(do ((r 1 (+ r 1))) ((> r runs))
  (for-each (lambda (size)
              (for-each (lambda (mode) (one r size mode)) '(alone plain collect-safe)))
            sizes))
(set-engine-pause-binding! 'plain)
(say "replay done")
