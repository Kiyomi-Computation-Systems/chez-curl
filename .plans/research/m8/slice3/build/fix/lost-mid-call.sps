#!r6rs
;; M8 slice 3's fix round, item 4's probe: a file part's file removed mid-call,
;; four ways: a 307 hop, a retry with the session's timeout-ms, a retry with no
;; bound, and a group's hop. Prints how each call ended: the &curl-request-error's
;; who, field, value and reason, and whether &http-exchange is compounded with it.
(import (rnrs) (only (chezscheme) make-time sleep fork-thread display-condition)
        (curl-testing) (curl) (http-client))

(define (pause-ms ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))
(define dir (make-process-temp-directory))

(define (face-url o face path)
  (let ((f (origin-face o face))) (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

(define (ended thunk)
  (guard (e ((curl-request-error? e)
             (list 'refused (and (who-condition? e) (condition-who e)) (curl-request-error-field e)
                   (curl-request-error-value e) (curl-request-error-reason e)
                   (if (http-exchange? e) 'with-exchange 'no-exchange)))
            (#t (list 'other (if (condition? e)
                                 (call-with-string-output-port (lambda (p) (display-condition e p)))
                                 e))))
    (thunk)
    'no-raise))

(define (file name)
  (let ((p (string-append dir "/" name)))
    (call-with-port (open-file-output-port p (file-options no-fail))
      (lambda (port) (put-bytevector port (make-bytevector 10 65))))
    p))

;; removing : String (-> Any) -> Any
;; THUNK's end, PATH removed 400 ms on, from another thread, as THUNK's call waits.
(define (removing path thunk)
  (fork-thread (lambda () (pause-ms 400) (delete-file path)))
  (ended thunk))

;; delayed-307 : Origin String -> String
;; A raw face URL that answers 307, a second on, to the http face's parts route.
(define (delayed-307 o key)
  (face-url o 'raw (string-append "/raw/location?code=307&ms=1000&to=http%3A%2F%2F" (car (origin-face o 'http))
                                  "%3A" (number->string (cdr (origin-face o 'http))) "%2Fparts%3Fkey%3D" key)))

(define (show label r) (write (list label r)) (newline))

(define retry (make-http-retry 'attempts 2 'backoff-ms 1000 'jitter #f 'statuses '(503) 'methods '(post)))

(define (scenarios o)
  (let ((p (file "hop.bin")))
    (show 'hop-307
          (call-with-http-session 'proxy #f
            (lambda (s)
              (removing p (lambda () (http-post s (delayed-307 o "lost-hop") 'multipart (list (list "f" (list 'file p))))))))))
  (let ((p (file "retry-bounded.bin")))
    (show 'retry-timeout-ms
          (call-with-http-session 'proxy #f 'timeout-ms 30000 'retry retry
            (lambda (s)
              (removing p (lambda () (http-post s (face-url o 'http "/parts?key=lost-retry-1&fail=1")
                                                'multipart (list (list "f" (list 'file p))))))))))
  (let ((p (file "retry-unbounded.bin")))
    (show 'retry-no-bound
          (call-with-http-session 'proxy #f 'retry retry
            (lambda (s)
              (removing p (lambda () (http-post s (face-url o 'http "/parts?key=lost-retry-2&fail=1")
                                                'multipart (list (list "f" (list 'file p))))))))))
  (let ((p (file "group-hop.bin")))
    (show 'group-hop
          (call-with-http-session 'proxy #f
            (lambda (s)
              (removing p (lambda () (http-parallel s (list (list 'post (delayed-307 o "lost-group")
                                                                  'multipart (list (list "f" (list 'file p)))))))))))))

(call-with-origin scenarios)
