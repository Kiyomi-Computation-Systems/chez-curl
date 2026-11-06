;;; long-url-hold.sps: how long a call's checks hold a Ctrl-C for a URL past
;;; libcurl's 8,000,000-byte cap, which libcurl refuses, so the size is the
;;; caller's alone. For each length, an http-get of http://127.0.0.1:9/ and
;;; that many a's, one run: the call's time to its refusal, and how long a
;;; SIGINT sent to this process at the checks' start (the private gate)
;;; waited for its handler. Nothing is fetched. Prints (long-url CHARS
;;; (call-ms MS) (ctrl-c-ms MS) (refused REASON)).
(import (chezscheme) (curl) (http-client) (only (http-client private drive) drive-checks-gate-set!)
        (curl private counters))

(define (now-ns)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))
(define (ms ns) (/ (round (/ ns 10000.0)) 100.0))

(load-shared-object "libc.so.6")
(define kill (foreign-procedure "kill" (int int) int))

(define session (make-http-session 'timeout-ms 5000))

(define (measure chars)
  (let* ((url (string-append "http://127.0.0.1:9/" (make-string chars #\a)))
         (sent #f)
         (handled #f))
    (collect-rendezvous)
    (keyboard-interrupt-handler (lambda () (unless handled (set! handled (now-ns)))))
    (drive-checks-gate-set! (lambda (where)
                              (when (and (eq? where 'start) (not sent))
                                (set! sent (now-ns))
                                (kill (get-process-id) 2))))
    (let* ((t0 (now-ns))
           (r (guard (e (#t (if (condition? e)
                                (list 'refused (cond ((curl-url-error? e) (curl-url-error-reason e))
                                                     ((message-condition? e) (condition-message e))
                                                     (else 'condition)))
                                (list 'raised e))))
                (http-get session url)
                '(answered)))
           (t1 (now-ns)))
      (drive-checks-gate-set! #f)
      (keyboard-interrupt-handler void)
      (write (list 'long-url chars (list 'call-ms (ms (- t1 t0)))
                   (list 'ctrl-c-ms (if (and sent handled) (ms (- handled sent)) 'none))
                   r))
      (newline)
      (flush-output-port (current-output-port)))))

(for-each measure '(1000000 8000000 16000000 32000000 64000000))
(http-session-close session)
(write (list 'counts (native-counts)))
(newline)
