;;; The send side's pacing-off control, measured before the suite relies
;;; on it (the brief's item 10): the process's CPU over a 2 s pause of an
;;; HTTP/2 upload, 4,096 bytes of 8,192 put first, as the measurement's
;;; cpu.sps did, on make-curl-engine-unpaced's engine and on
;;; make-curl-engine's, RUNS times each, each on an engine of its own. The
;;; origin is tests/origin.mjs, its h2 face's /echo, which reads the body
;;; whole. One line a run.
(import (chezscheme) (curl-testing) (curl) (curl private engine) (curl private counters))
(define runs (string->number (car (command-line-arguments))))
(define (cpu-ms) (let ((t (current-time 'time-process))) (+ (* (time-second t) 1000) (/ (time-nanosecond t) 1000000.))))
(define (ms n) (make-time 'time-duration (* (mod n 1000) 1000000) (div n 1000)))
(define (stat t k) (cdr (assq k (curl-token-upload-stats t))))
(define pki (make-test-pki))
(define ca (string-append pki "/ca.pem"))
(printf "control libcurl ~a ~a~%" (libcurl-info-version (loaded-libcurl)) (libcurl-info-ssl-version (loaded-libcurl)))
(parameterize ((origin-pki pki))
  (call-with-origin
   (lambda (o)
     (let ((f (origin-face o 'h2)))
       (for-each
        (lambda (setting)
          (do ((r 1 (+ r 1))) ((> r runs))
            (let* ((own (if (eq? setting 'unpaced) (make-curl-engine-unpaced) (make-curl-engine)))
                   (t (curl-submit own (make-curl-request (string-append "https://" (car f) ":" (number->string (cdr f)) "/echo")
                                                          'method 'post 'body 'stream 'body-length 8192 'proxy #f
                                                          'ca-file ca 'timeout-ms 20000)))
                   (room (curl-token-room-wait t 20000))
                   (first (curl-token-put-piece! t (make-bytevector 4096 7) 5000)))
              (let wait ((i 0)) (unless (or (and (stat t 'paused) (not (stat t 'queued))) (> i 10000)) (sleep (ms 1)) (wait (+ i 1))))
              (collect-rendezvous)
              (let* ((c0 (cpu-ms)) (_ (sleep (ms 2000))) (c1 (cpu-ms)))
                (curl-token-put-piece! t (make-bytevector 4096 7) 5000)
                (curl-token-end-body! t)
                (curl-token-wait t 20000)
                (printf "control setting=~a run=~a room=~a cpu-ms=~a paced=~a resumes=~a outcome=~a~%"
                        setting r room (- c1 c0) (curl-engine-paced-sleeps own) (stat t 'resumes)
                        (let ((x (curl-token-outcome t))) (if (curl-response? x) (curl-response-status x) x))))
              (curl-engine-stop own))))
        '(unpaced paced))))))
(printf "control counts ~a~%" (native-counts))
