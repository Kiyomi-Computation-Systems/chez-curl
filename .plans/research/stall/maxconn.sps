;;; M3 slice 3: can CURLMOPT_MAX_TOTAL_CONNECTIONS show a long reaching
;;; curl_multi_setopt, on every libcurl? Two drips of D ms to one origin, in
;;; one multi handle, with the limit at VALUE: at 1 the second waits for the
;;; first, about 2D; otherwise both run at once, about D.
;;;
;;;   maxconn.sps BYTES GAP VALUE...
;;;
;;; Prints, per VALUE, the setopt's code, the ms until both are done, and
;;; each transfer's CURLcode and ms, read as its message is. The first runs
;;; stopped the clock after one more 100 ms poll, so their "both done" read
;;; about 100 ms late; the per-transfer times did not (ADR-0001, amended
;;; 2026-10-25).
(import (chezscheme) (curl-testing) (curl private native) (curl private counters) (curl private libcurl-info))

(define args (command-line-arguments))
(define bytes (string->number (car args)))
(define gap (string->number (cadr args)))
(define tried (map string->number (cddr args)))
(define info (loaded-libcurl))

(define multi-setopt-long
  (foreign-procedure (__varargs_after 2) "curl_multi_setopt" (uptr int long) int))
(define fopen (foreign-procedure "fopen" (string string) uptr))
(define fclose (foreign-procedure "fclose" (uptr) int))
(define curlmopt-max-total-connections 13)

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))

(define (option-id name) (car (curl-easy-option name)))
(define (c-copy s)
  (let* ((bv (string->utf8 s)) (n (bytevector-length bv)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))

(define (run url value)
  (let* ((m (curl-multi-init))
         (code (multi-setopt-long m curlmopt-max-total-connections value))
         (sink (fopen "/dev/null" "w"))
         (slot (foreign-alloc 8))
         (easies (map (lambda (i)
                        (let ((h (curl-easy-init)) (p (c-copy url)))
                          (curl-easy-setopt-pointer h (option-id "URL") p)
                          (foreign-free p)
                          (curl-easy-setopt-pointer h (option-id "WRITEDATA") sink)
                          (curl-easy-setopt-long h (option-id "NOSIGNAL") 1)
                          (curl-multi-add-handle m h)
                          h))
                      '(1 2)))
         (t0 (now-ms)))
    (let loop ((done 0) (results '()))
      (if (= done 2)
          (let ((ms (round (- (now-ms) t0))))
            (for-each (lambda (h) (curl-multi-remove-handle m h) (curl-easy-cleanup h)) easies)
            (curl-multi-cleanup m)
            (fclose sink)
            (foreign-free slot)
            (printf "  value ~a: setopt ~a, both done at ~a ms, results ~a\n" value code ms (reverse results)))
          (begin
            (curl-multi-perform m slot)
            (let drain ((done done) (results results))
              (let ((msg (curl-multi-info-read m slot)))
                (cond (msg (drain (+ done 1) (cons (list (caddr msg) (round (- (now-ms) t0))) results)))
                      ;; Done: the clock stops here, before another poll.
                      ((= done 2) (loop done results))
                      (else
                       (curl-multi-poll m 100)
                       (loop done results))))))))))

(printf "libcurl ~a\n" (libcurl-info-version info))
(call-with-origin
 (lambda (o)
   (let* ((f (origin-face o 'raw))
          (url (string-append "http://" (car f) ":" (number->string (cdr f))
                              "/raw/drip?bytes=" (number->string bytes) "&gap=" (number->string gap))))
     (for-each (lambda (v) (run url v)) tried))))
(printf "counts ~a\n" (native-counts))
