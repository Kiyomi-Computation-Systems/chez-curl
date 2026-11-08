#!r6rs
;; Review probe: the printed outcome of a transfer whose file part is removed
;; once the origin holds the head (after the engine's check): does the
;; printed condition hold the path?
(import (rnrs) (curl-testing) (curl) (curl unsupported)
        (only (chezscheme) mkdir display-condition make-time sleep current-time time-second time-nanosecond))

(define dir (cadr (command-line)))
(define secret "S3CRETDIR")

(define (face-url o face path)
  (let ((f (origin-face o face)))
    (string-append "http://" (car f) ":" (number->string (cdr f)) path)))

(define (pause-ms ms) (sleep (make-time 'time-duration (* (mod ms 1000) 1000000) (div ms 1000))))

(define (seen o key)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f)
      (lambda ()
        (let* ((r (curl-token-await (curl-submit e (make-curl-request (face-url o 'http (string-append "/seen?key=" key))
                                                                      'proxy #f 'timeout-ms 10000))))
               (text (utf8->string (curl-response-body r))))
          (string->number (substring text 5 (- (string-length text) 1)))))
      (lambda () (curl-engine-stop e)))))

(define (release o key)
  (let ((e (make-curl-engine)))
    (dynamic-wind (lambda () #f)
      (lambda () (curl-response-status (curl-token-await (curl-submit e (make-curl-request (face-url o 'raw (string-append "/raw/release?key=" key)) 'proxy #f 'timeout-ms 10000)))))
      (lambda () (curl-engine-stop e)))))

(call-with-origin
 (lambda (o)
   (let* ((sub (string-append dir "/" secret))
          (p (string-append sub "/" secret ".bin"))
          (key "zz-errbuf"))
     (guard (e (#t #f)) (mkdir sub))
     (call-with-port (open-file-output-port p (file-options no-fail))
       (lambda (port) (put-bytevector port (make-bytevector 3000 65))))
     (let* ((request (curl-request-with-options
                      (make-curl-request (face-url o 'http (string-append "/parts?key=" key "&hold=1"))
                                         'method 'post 'proxy #f 'headers '(("Expect" . "100-continue"))
                                         'timeout-ms 20000
                                         'body (list 'multipart (list "f" (list 'file p))))
                      '(("EXPECT_100_TIMEOUT_MS" . 60000))))
            (e (make-curl-engine)))
       (dynamic-wind (lambda () #f)
         (lambda ()
           (let ((t (curl-submit e request)))
             (let loop ((n 0)) (unless (or (> n 500) (eqv? (seen o key) 1)) (pause-ms 20) (loop (+ n 1))))
             (delete-file p)
             (release o key)
             (curl-token-wait t 20000)
             (let* ((x (curl-token-outcome t))
                    (text (call-with-string-output-port (lambda (port) (display-condition x port)))))
               (write (list 'reason (and (curl-transfer-error? x) (curl-transfer-error-reason x))
                            'code (and (curl-transfer-error? x) (curl-transfer-error-code x))
                            'printed-holds-secret (let loop ((i 0))
                                                    (and (<= (+ i (string-length secret)) (string-length text))
                                                         (or (string=? (substring text i (+ i (string-length secret))) secret)
                                                             (loop (+ i 1)))))
                            'text text))
               (newline))))
         (lambda () (curl-engine-stop e)))))))
