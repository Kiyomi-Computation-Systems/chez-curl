;;; long-form-hold.sps: long-url-hold.sps for a form of one pair, its value
;;; CHARS a s, posted to http://127.0.0.1:9/, which refuses the connect:
;;; the checks run whole, then the submit, then the connect's refusal.
;;; For each length, one run: the call's time, and how long a
;;; SIGINT sent to this process at the checks' start (the private gate)
;;; waited for its handler. Nothing is fetched. Prints (long-form CHARS
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
  (let* ((form (list (cons "k" (make-string chars #\a))))
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
                (http-post session "http://127.0.0.1:9/" 'form form)
                '(answered)))
           (t1 (now-ns)))
      (drive-checks-gate-set! #f)
      (keyboard-interrupt-handler void)
      (write (list 'long-form chars (list 'call-ms (ms (- t1 t0)))
                   (list 'ctrl-c-ms (if (and sent handled) (ms (- handled sent)) 'none))
                   r))
      (newline)
      (flush-output-port (current-output-port)))))

(for-each measure '(1000000 16000000 32000000 64000000))
(http-session-close session)
(write (list 'counts (native-counts)))
(newline)
