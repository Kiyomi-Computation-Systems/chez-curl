;;; M3 slice 3: which libcurl calls block while a name lookup stalls
;;; (ADR-0019, amended 2026-10-25). Spike E1's lookup.sps, run under the
;;; stand-in getaddrinfo, tests/stall-getaddrinfo.c, which stalls every
;;; lookup of slow-name.example.com. Native's setopt now checks each
;;; handle's owning thread (M3 slice 2), so this program binds its own. One
;;; easy handle for http://slow-name.example.com/, with NOSIGNAL 1, and
;;; every libcurl call timed.
;;;
;;;   lookup.sps SCENARIO [quick] [mquick]
;;;
;;; SCENARIO is teardown, timeout or easy:
;;;   teardown  in one multi handle, TIMEOUT_MS 60000; driven 300 ms, with
;;;             one curl_multi_wakeup along the way, then removed and
;;;             cleaned up;
;;;   timeout   the same, with TIMEOUT_MS 1000, driven until
;;;             curl_multi_info_read reports it done, or 30 s pass;
;;;   easy      no multi handle of ours: curl_easy_perform, bound
;;;             __collect_safe, with TIMEOUT_MS 1000, then curl_easy_cleanup,
;;;             as M2's blocking path did.
;;; quick sets CURLOPT_QUICK_EXIT 1 when the libcurl knows it (7.87.0), and
;;; mquick sets CURLMOPT_QUICK_EXIT, option 21, to 1 (8.20.0) on the multi
;;; handle. Each prints the code its setopt answered: unknown, for an option
;;; libcurl lacks.
;;;
;;; Prints one line: the transfer's state at the end of the drive, or its
;;; CURLcode and when it arrived, then the longest single call of each
;;; entry point, in ms.
(import (chezscheme)
        (except (curl private native) curl-easy-setopt-long curl-easy-setopt-pointer)
        (curl private libcurl-info))

(define args (command-line-arguments))
(define scenario (string->symbol (car args)))
(define quick? (and (member "quick" args) #t))
(define mquick? (and (member "mquick" args) #t))
(define info (loaded-libcurl))

(define easy-init (foreign-procedure "curl_easy_init" () uptr))
(define easy-cleanup (foreign-procedure "curl_easy_cleanup" (uptr) void))
(define easy-perform (foreign-procedure __collect_safe "curl_easy_perform" (uptr) int))
(define multi-init (foreign-procedure "curl_multi_init" () uptr))
(define multi-cleanup (foreign-procedure "curl_multi_cleanup" (uptr) int))
(define multi-add (foreign-procedure "curl_multi_add_handle" (uptr uptr) int))
(define multi-remove (foreign-procedure "curl_multi_remove_handle" (uptr uptr) int))
(define multi-perform (foreign-procedure "curl_multi_perform" (uptr uptr) int))
(define multi-wakeup (foreign-procedure "curl_multi_wakeup" (uptr) int))
(define multi-setopt-long
  (foreign-procedure (__varargs_after 2) "curl_multi_setopt" (uptr int long) int))
(define poll
  (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned-int int uptr) int))
(define info-read (foreign-procedure "curl_multi_info_read" (uptr uptr) uptr))
(define curl-easy-setopt-long
  (foreign-procedure (__varargs_after 2) "curl_easy_setopt" (uptr int long) int))
(define curl-easy-setopt-pointer
  (foreign-procedure (__varargs_after 2) "curl_easy_setopt" (uptr int uptr) int))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6))))

(define longest (make-eq-hashtable))
(define-syntax timed
  (syntax-rules ()
    ((_ name e)
     (let* ((t0 (now-ms)) (v e))
       (hashtable-update! longest 'name (lambda (old) (max old (- (now-ms) t0))) 0)
       v))))

(define (option-id name) (let ((o (curl-easy-option name))) (and o (car o))))
(define (c-copy s)
  (let* ((bv (string->utf8 s)) (n (bytevector-length bv)) (p (foreign-alloc (+ n 1))))
    (do ((i 0 (+ i 1))) ((= i n)) (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bv i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))

(define curlmopt-quick-exit 21)
(define curlm-unknown-option 6)

;; easy-handle : Natural -> (Values Natural (U #f Integer 'unknown))
;; A fresh easy handle for the slow name, with TIMEOUT-MS, and the code its
;; QUICK_EXIT setopt answered when quick was asked.
(define (easy-handle timeout-ms)
  (let ((h (easy-init)))
    (let ((p (c-copy "http://slow-name.example.com/")))
      (curl-easy-setopt-pointer h (option-id "URL") p)
      (foreign-free p))
    (curl-easy-setopt-long h (option-id "NOSIGNAL") 1)
    (curl-easy-setopt-long h (option-id "TIMEOUT_MS") timeout-ms)
    (values h
            (and quick?
                 (let ((id (option-id "QUICK_EXIT")))
                   (if id (curl-easy-setopt-long h id 1) 'unknown))))))

;; through-multi : -> (Values Outcome Quick-Code Mquick-Code)
;; teardown or timeout, through a multi handle of our own.
(define (through-multi)
  (let ((m (timed multi_init (multi-init)))
        (running (foreign-alloc 8))
        (numfds (foreign-alloc 8)))
    (let-values (((h quick-code) (easy-handle (if (eq? scenario 'timeout) 1000 60000))))
      (let* ((mquick-code
              (and mquick?
                   (let ((code (multi-setopt-long m curlmopt-quick-exit 1)))
                     (if (= code curlm-unknown-option) 'unknown code))))
             (t-start (begin (timed multi_add_handle (multi-add m h)) (now-ms)))
             (elapsed (lambda () (- (now-ms) t-start)))
             (outcome
              (let loop ((woken #f))
                (timed multi_perform (multi-perform m running))
                (let ((msg (timed multi_info_read (info-read m numfds))))
                  (cond
                    ((not (zero? msg)) (list 'code (foreign-ref 'int msg 16) (round (elapsed))))
                    ((and (eq? scenario 'teardown) (>= (elapsed) 300))
                     (list 'running (foreign-ref 'int running 0)))
                    ((> (elapsed) 30000) (list 'gave-up (round (elapsed))))
                    (else
                     (unless woken (timed multi_wakeup (multi-wakeup m)))
                     (timed multi_poll (poll m 0 0 (if (eq? scenario 'teardown) 50 100) numfds))
                     (loop #t)))))))
        (timed multi_remove_handle (multi-remove m h))
        (timed easy_cleanup (easy-cleanup h))
        (timed multi_cleanup (multi-cleanup m))
        (foreign-free running)
        (foreign-free numfds)
        (values outcome quick-code mquick-code)))))

;; through-easy-perform : -> (Values Outcome Quick-Code #f)
;; easy: curl_easy_perform runs the transfer in a multi handle of its own.
(define (through-easy-perform)
  (let-values (((h quick-code) (easy-handle 1000)))
    (let* ((t-start (now-ms))
           (code (timed easy_perform (easy-perform h)))
           (outcome (list 'code code (round (- (now-ms) t-start)))))
      (timed easy_cleanup (easy-cleanup h))
      (values outcome quick-code #f))))

(define-values (outcome quick-code mquick-code)
  (if (eq? scenario 'easy) (through-easy-perform) (through-multi)))

(printf "lookup ~a, libcurl ~a~a~a: ~s; longest ~s\n"
        scenario (libcurl-info-version info)
        (if quick? (format ", QUICK_EXIT ~a" quick-code) "")
        (if (and mquick? (not (eq? scenario 'easy))) (format ", CURLMOPT_QUICK_EXIT ~a" mquick-code) "")
        outcome
        (list-sort (lambda (a b) (string<? (symbol->string (car a)) (symbol->string (car b))))
                   (map (lambda (k) (cons k (round (hashtable-ref longest k 0))))
                        (vector->list (hashtable-keys longest)))))
