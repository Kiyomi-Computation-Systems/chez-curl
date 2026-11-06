;;; step-hold.sps [CASE ...]: what a redirect's step costs, at the inputs
;;; the loaded libcurl accepts, on the code before the fix, where
;;; drive-exchange and drive-stream run exchange-step with interrupts on:
;;; the time of exchange-step itself, which the fix runs in a critical
;;; section, so its time is how long that section would hold Ctrl-C and
;;; other threads' collections.
;;;
;;; Against probe/step-server.mjs, a stand-in that answers a 302 whose
;;; Location is N bytes, with H more headers, to a target of any length:
;;; for each case, one transfer by the low level, its response read whole
;;; by libcurl, or its refusal, its class and code; then a call's state,
;;; made by make-exchange for that request and put in flight by
;;; exchange-submission, stepped with that response by exchange-step, 3
;;; times, and by exchange-steps-past?, 3 times. Cases: loc-N, a Location of
;;; N bytes; hdr-H, H headers beside a short Location; url-L, a requested
;;; URL of about L chars beside a short Location; and both, the longest URL
;;; with the longest Location and 5,000 headers. Prints
;;;   (step LIBCURL CASE URL-CHARS (transfer MS OUTCOME) (step ANSWER MIN MAX)
;;;    (past ANSWER MIN MAX))
;;; times in ms. Run from a copy's root, NODE set.
(import (chezscheme) (curl)
        (only (http-client private exchange) make-exchange exchange-submission exchange-step
              exchange-steps-past?)
        (curl private counters))

(define version (libcurl-info-version (loaded-libcurl)))
(define (now-ns)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))
(define (ms ns) (/ (round (/ ns 10000.0)) 100.0))

(define node (or (getenv "NODE") "node"))
(define server-ports
  (call-with-values
    (lambda () (open-process-ports (string-append node " probe/step-server.mjs") 'line (native-transcoder)))
    list))
(define to-server (car server-ports))
(define from-server (cadr server-ports))
(define port (cadr (read from-server)))

(define all-cases
  '((loc-1000 1000 0 0) (loc-50000 50000 0 0) (loc-100000 100000 0 0) (loc-102000 102000 0 0)
    (loc-102400 102400 0 0) (loc-200000 200000 0 0) (loc-1048576 1048576 0 0)
    (hdr-1000 10 1000 0) (hdr-5000 10 5000 0) (hdr-20000 10 20000 0) (hdr-50000 10 50000 0)
    (hdr-100000 10 100000 0)
    (url-1000000 10 0 1000000) (url-4000000 10 0 4000000) (url-7999900 10 0 7999900)
    (both 100000 5000 7999900)))

(define cases
  (if (null? (command-line-arguments))
      all-cases
      (filter (lambda (c) (member (symbol->string (car c)) (command-line-arguments))) all-cases)))

(define (class-of c)
  (cond ((not (condition? c)) (list 'non-condition c))
        ((curl-transfer-error? c) (list (curl-transfer-error-reason c) (curl-transfer-error-code c)))
        ((curl-url-error? c) (list 'url (curl-url-error-reason c)))
        (else (list 'other (if (message-condition? c) (condition-message c) #f)))))

(define engine (make-curl-engine))

(define (timed-3 thunk)
  (let loop ((i 0) (times '()) (answer #f))
    (if (= i 3)
        (list answer (ms (apply min times)) (ms (apply max times)))
        (let* ((t0 (now-ns))
               (a (guard (e (#t (list 'raised (class-of e)))) (thunk)))
               (t1 (now-ns)))
          (loop (+ i 1) (cons (- t1 t0) times) a)))))

(define (answer-of step)
  (cond ((and (pair? step) (eq? (car step) 'raised)) step)
        ((pair? step) (car step))
        (else step)))

;; url-for : Natural Natural Natural -> String
(define (url-for n h pad)
  (string-append "http://127.0.0.1:" (number->string port) "/r?n=" (number->string n)
                 "&h=" (number->string h)
                 (if (> pad 0) (string-append "&p=" (make-string pad #\b)) "")))

;; accepted? : Natural Natural Natural -> Boolean
;; Whether the loaded libcurl's transfer of url-for's URL answers a
;; response, the 302, rather than a refusal; each try printed, (try N H
;; PAD RESULT MS).
(define (accepted? n h pad)
  (let* ((t0 (now-ns))
         (r (guard (e (#t (list #f (class-of e))))
              (curl-token-await (curl-submit engine (make-curl-request (url-for n h pad) 'timeout-ms 120000 'proxy #f)))
              (list #t))))
    (write (list 'try n h pad r (ms (- (now-ns) t0))))
    (newline)
    (flush-output-port (current-output-port))
    (car r)))

;; largest : (Natural -> Boolean) Natural Natural -> (U Natural #f)
;; The largest X from LO to HI that OK? takes, by bisection, OK? taking
;; every X below one it takes; #f when it takes not even LO.
(define (largest ok? lo hi)
  (cond ((not (ok? lo)) #f)
        ((ok? hi) hi)
        (else (let loop ((lo lo) (hi hi))
                (if (= (+ lo 1) hi) lo
                    (let ((mid (div (+ lo hi) 2)))
                      (if (ok? mid) (loop mid hi) (loop lo mid))))))))

(define bisect? (or (equal? (getenv "STEP_BISECT") "1") (null? (command-line-arguments))))
(define maxima
  (if bisect?
      (let* ((n (largest (lambda (n) (accepted? n 0 0)) 1000 1048576))
             (h (largest (lambda (h) (accepted? 10 h 0)) 10 100000))
             (pad (largest (lambda (pad) (accepted? 10 0 pad)) 1000 7999900)))
        (write (list 'maxima version 'location n 'headers h 'url-pad pad))
        (newline)
        (list n h pad))
      #f))

(define run-cases
  (if maxima
      (let ((n (car maxima)) (h (cadr maxima)) (pad (caddr maxima)))
        (list (list 'max-location n 0 0) (list 'max-headers 10 h 0) (list 'max-url 10 0 pad)
              (list 'max-location-and-headers n h 0) (list 'max-all n h (- pad 64))))
      cases))

(for-each
 (lambda (c)
   (let* ((name (car c)) (n (cadr c)) (h (caddr c)) (pad (cadddr c))
          (url (string-append "http://127.0.0.1:" (number->string port) "/r?n=" (number->string n)
                              "&h=" (number->string h)
                              (if (> pad 0) (string-append "&p=" (make-string pad #\b)) "")))
          (request (make-curl-request url 'timeout-ms 120000 'proxy #f))
          (t0 (now-ns))
          (outcome (guard (e (#t (list 'failed e)))
                     (list 'response (curl-token-await (curl-submit engine request)))))
          (t1 (now-ns)))
     (write
      (if (eq? (car outcome) 'failed)
          (list 'step version name (string-length url)
                (list 'transfer (ms (- t1 t0)) (list 'refused (class-of (cadr outcome)))))
          (let* ((r (cadr outcome))
                 (state0 (make-exchange 'get url request #f (now-ns) 20 #f))
                 (submission (exchange-submission state0 (now-ns)))
                 (state (cadr submission))
                 (utc (time-second (current-time 'time-utc)))
                 (step (timed-3 (lambda () (answer-of (exchange-step state (list 'response r) (now-ns) utc 0.5)))))
                 (past (timed-3 (lambda () (exchange-steps-past? state r (now-ns) utc 0.5)))))
            (list 'step version name (string-length url)
                  (list 'transfer (ms (- t1 t0))
                        (list (curl-response-status r) (length (curl-response-headers r))))
                  (cons 'step step) (cons 'past past)))))
     (newline)
     (flush-output-port (current-output-port))))
 run-cases)
(curl-engine-stop engine)
(close-port to-server)
(write (list 'counts (native-counts)))
(newline)
