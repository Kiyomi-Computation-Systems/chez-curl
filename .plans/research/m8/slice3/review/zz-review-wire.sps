#!r6rs
;; Review probe: what a few file parts send through the engine, at the
;; origin's parts route: /proc/self/status, a sysfs file, a non-ASCII path.
(import (rnrs) (only (chezscheme) system file-regular? make-time sleep current-time time-second time-nanosecond)
        (curl-testing) (curl) (http-client))

(define dir (cadr (command-line)))

(define (url o key)
  (let ((f (origin-face o 'http)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) "/parts?key=" key)))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define (send o key path timeout)
  (guard (e (#t (list 'raised (describe e))))
    (let ((e (make-curl-engine)) (start (now-ms)))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let* ((r (apply make-curl-request (url o key) 'method 'post 'proxy #f
                           'body (list 'multipart (list "f" (list 'file path)))
                           (if timeout (list 'timeout-ms timeout) '())))
                 (t (curl-submit e r)))
            (if (curl-token-wait t 8000)
                (let ((x (curl-token-outcome t)))
                  (list (- (now-ms) start) 'ms
                        (if (curl-response? x)
                            (list 'response (curl-response-status x) (utf8->string (curl-response-body x)))
                            (list 'failed (curl-transfer-error-reason x) (curl-transfer-error-code x)))))
                (list 'not-ended-in-8s))))
        (lambda () (curl-engine-stop e))))))

(define nonascii (string-append dir "/caf\xE9;-\x3BB;.bin"))
(call-with-port (open-file-output-port nonascii (file-options no-fail))
  (lambda (p) (put-bytevector p (string->utf8 "non-ascii file's bytes"))))

(display (list 'file-regular-proc (file-regular? "/proc/self/status")
               'file-regular-sys (file-regular? "/sys/kernel/mm/transparent_hugepage/enabled")))
(newline)

(call-with-origin
 (lambda (o)
   (for-each
    (lambda (row)
      (write (cons (car row) (send o (car row) (cadr row) (caddr row))))
      (newline))
    (list (list "proc" "/proc/self/status" 5000)
          (list "sys" "/sys/kernel/mm/transparent_hugepage/enabled" 5000)
          (list "nonascii" nonascii 5000)))))
