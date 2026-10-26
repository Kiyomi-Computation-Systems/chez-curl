#!r6rs
;;; A child of tests/test-engine.sps, run under tests/stall-getaddrinfo.c, a
;;; stand-in getaddrinfo that stalls each name ending .stall.invalid for
;;; STALL_MS, which the suite sets well above 1000 ms, and logs to STALL_LOG
;;; as each lookup starts and as it answers (ADR-0019; M3 plan, section 6.2).
;;;
;;;   engine-stall.sps WITHOUT URL
;;;
;;; WITHOUT is none, transfer or multi: the QUICK_EXIT setting each engine
;;; here leaves out, through make-curl-engine-without-quick-exit. URL is a
;;; drip of about 1 s that answers abcdefghij. Three scenarios, each on an
;;; engine of its own, stopped after, each stop judged too:
;;;
;;;   cancel   cancel.stall.invalid, submitted with URL beside it, and
;;;            cancelled the moment the log shows its lookup stalling; then
;;;            URL awaited;
;;;   timeout  timeout.stall.invalid, with a 500 ms timeout, awaited;
;;;   stop     stop.stall.invalid; the engine stopped the moment the log
;;;            shows its lookup stalling.
;;;
;;; A cancel or a stop sent before the lookup starts would find the token
;;; queued, and no lookup would ever stall: so each waits for the log.
;;;
;;; Each event is judged against the stand-in's log, so the two share no
;;; clock, read as it starts and right after it returns: stalled, when the
;;; stand-in answered meanwhile, so the event waited for the lookup; else
;;; prompt, within its bound of its cause: 1000 ms for the cancel and each
;;; stop; 2000 ms past the timeout's due time, whose 28 waits on libcurl's
;;; timer and the engine's poll, at most 1000 ms; 2000 ms from its submit
;;; for URL; else (slow MS). So a stop after a cancel that waited for the
;;; lookup is prompt: the lookup was over before it started. A lookup the
;;; log never shows starting, within 5 s, is (no-stall NAME). Prints, a
;;; datum each:
;;;
;;;   (settings MULTI COUNT)     the cancel engine's CURLMOPT_QUICK_EXIT,
;;;                              set, unknown or off, and how many of the
;;;                              four transfers here set QUICK_EXIT
;;;   (cancel VERDICT OUTCOME)
;;;   (other VERDICT OUTCOME)    URL's, beside the cancel
;;;   (cancel-stop VERDICT)      the cancel engine's stop, after both
;;;   (timeout VERDICT OUTCOME)
;;;   (timeout-stop VERDICT)     the timeout engine's stop, after it
;;;   (stop VERDICT OUTCOME)
;;;   (stalled NAME ...)         the names the stand-in stalled, sorted
;;;   (counts COUNTS)            the native counts, every engine stopped
;;;
;;; Each await is curl-token-await's, and each stop curl-engine-stop's: the
;;; suite bounds this whole child, at 60 s.
(import (rnrs)
        (only (chezscheme) sleep make-time current-time time-second time-nanosecond getenv
              command-line-arguments)
        (curl private engine)
        (curl private transfer)
        (curl private conditions)
        (curl private counters))

(define args (command-line-arguments))
(define without (string->symbol (car args)))
(define url (cadr args))
(define log-path (getenv "STALL_LOG"))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define (pause-ms ms)
  (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

;; make-engine : -> Engine
(define (make-engine)
  (if (eq? without 'none)
      (make-curl-engine)
      (make-curl-engine-without-quick-exit (list without))))

;; request : String Natural -> Request
(define (request target timeout-ms)
  (make-transfer-request target 'get '() #f timeout-ms #f #f #t #f))

;; outcome : (-> Response) -> Outcome
;; What THUNK answers, whole: (response STATUS BODY), the body as Latin-1;
;; (transfer-error REASON CODE RECORDED); (raised TEXT) for anything else.
(define (outcome thunk)
  (guard (e ((curl-transfer-error? e)
             (list 'transfer-error (curl-transfer-error-reason e) (curl-transfer-error-code e)
                   (curl-transfer-error-recorded e)))
            (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
    (let ((r (thunk)))
      (list 'response (transfer-response-status r)
            (list->string (map integer->char (bytevector->u8-list (transfer-response-body r))))))))

;; log-text : -> String
(define (log-text)
  (or (guard (e (#t #f)) (call-with-input-file log-path get-string-all)) ""))

;; holds? : String String -> Boolean
;; Whether TEXT holds LINE as one of its lines.
(define (holds? text line)
  (let ((n (string-length text)) (m (string-length line)))
    (let scan ((start 0))
      (cond ((> (+ start m) n) #f)
            ((and (string=? (substring text start (+ start m)) line)
                  (or (= start 0) (char=? (string-ref text (- start 1)) #\newline))
                  (or (= (+ start m) n) (char=? (string-ref text (+ start m)) #\newline)))
             #t)
            (else (scan (+ start 1)))))))

;; answered? : String -> Boolean
(define (answered? name) (holds? (log-text) (string-append "answered " name)))

;; started-within : String Natural -> Boolean
;; Whether the log shows NAME's lookup starting, polled every 10 ms for MS.
(define (started-within name ms)
  (let ((deadline (+ (now-ms) ms)))
    (let wait ()
      (cond ((holds? (log-text) (string-append "stalling " name)) #t)
            ((> (now-ms) deadline) #f)
            (else (pause-ms 10) (wait))))))

;; verdict : Boolean Boolean Integer Natural -> Verdict
;; An event that took MS of its BOUND, judged by whether the stand-in had
;; answered as it started, BEFORE, and right after it returned, AFTER.
(define (verdict before after ms bound)
  (cond ((and after (not before)) 'stalled)
        ((< ms bound) 'prompt)
        (else (list 'slow ms))))

;; stopped-verdict : Engine String -> Verdict
;; ENGINE's stop, judged against NAME's lookup, within 1000 ms.
(define (stopped-verdict engine name)
  (let* ((before (answered? name))
         (t0 (now-ms))
         (done (curl-engine-stop engine))
         (after (answered? name)))
    (verdict before after (- (now-ms) t0) 1000)))

;; cancel: the stalled transfer cancelled, URL beside it.
(define cancel-engine (make-engine))
(define multi-setting (curl-engine-quick-exit cancel-engine))
(define quick-exits-before (quick-exits-set))
(define cancel-name "cancel.stall.invalid")
(define cancelled (curl-engine-submit cancel-engine (request (string-append "http://" cancel-name "/") 60000)))
(define other-start (now-ms))
(define other (curl-engine-submit cancel-engine (request url 20000)))
(define cancel-lines
  (if (started-within cancel-name 5000)
      (begin
        (let* ((before (answered? cancel-name))
               (t0 (now-ms))
               (sent (curl-token-cancel cancelled))
               (o (outcome (lambda () (curl-token-await cancelled))))
               (state (answered? cancel-name))
               (ms (- (now-ms) t0))
               (other-o (outcome (lambda () (curl-token-await other))))
               (other-state (answered? cancel-name))
               (other-ms (- (now-ms) other-start)))
          (list (list 'cancel (verdict before state ms 1000) o)
                (list 'other (verdict before other-state other-ms 2000) other-o))))
      (list (list 'cancel (list 'no-stall cancel-name)) (list 'other (list 'no-stall cancel-name)))))
(define cancel-stop-line (list 'cancel-stop (stopped-verdict cancel-engine cancel-name)))

;; timeout: 500 ms, awaited.
(define timeout-engine (make-engine))
(define timeout-name "timeout.stall.invalid")
(define timeout-line
  (let* ((t0 (now-ms))
         (token (curl-engine-submit timeout-engine (request (string-append "http://" timeout-name "/") 500)))
         (o (outcome (lambda () (curl-token-await token))))
         (state (answered? timeout-name))
         (ms (- (now-ms) t0 500)))
    (if (holds? (log-text) (string-append "stalling " timeout-name))
        (list 'timeout (verdict #f state ms 2000) o)
        (list 'timeout (list 'no-stall timeout-name) o))))
(define timeout-stop-line (list 'timeout-stop (stopped-verdict timeout-engine timeout-name)))

;; stop: the engine stopped while the lookup stalls.
(define stop-engine (make-engine))
(define stop-name "stop.stall.invalid")
(define stopped (curl-engine-submit stop-engine (request (string-append "http://" stop-name "/") 60000)))
(define stop-line
  (if (started-within stop-name 5000)
      (begin
        (let ((v (stopped-verdict stop-engine stop-name)))
          (list 'stop v (outcome (lambda () (curl-token-await stopped))))))
      (begin
        (curl-engine-stop stop-engine)
        (list 'stop (list 'no-stall stop-name)))))

;; stalled-names : -> (Listof String)
;; Each name a "stalling NAME" line of the log names, once, sorted.
(define (stalled-names)
  (let loop ((lines (log-lines (log-text))) (found '()))
    (cond ((null? lines) (list-sort string<? found))
          ((and (> (string-length (car lines)) 9) (string=? (substring (car lines) 0 9) "stalling "))
           (let ((name (substring (car lines) 9 (string-length (car lines)))))
             (loop (cdr lines) (if (member name found) found (cons name found)))))
          (else (loop (cdr lines) found)))))

;; log-lines : String -> (Listof String)
(define (log-lines text)
  (let loop ((i 0) (start 0) (found '()))
    (cond ((= i (string-length text))
           (reverse (if (> i start) (cons (substring text start i) found) found)))
          ((char=? (string-ref text i) #\newline) (loop (+ i 1) (+ i 1) (cons (substring text start i) found)))
          (else (loop (+ i 1) start found)))))

(for-each (lambda (datum) (write datum) (newline))
          (append (list (list 'settings multi-setting (- (quick-exits-set) quick-exits-before)))
                  cancel-lines
                  (list cancel-stop-line timeout-line timeout-stop-line stop-line
                        (cons 'stalled (stalled-names))
                        (list 'counts (native-counts)))))
