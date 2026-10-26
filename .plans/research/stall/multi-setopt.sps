;;; M3 slice 3: which long multi options answer curl_multi_setopt by their
;;; value? check-variadic needs one that does on every libcurl, Apple's
;;; 8.7.1 among them, to watch an unannotated binding fail on arm64.
;;;
;;; Prints, for each long CURLMOPT_ in 8.20.0's multi.h, the CURLMcode for
;;; each value, on a fresh multi handle per call.
(import (chezscheme) (only (curl private native) loaded-libcurl) (curl private libcurl-info))

(define info (loaded-libcurl))
(define multi-init (foreign-procedure "curl_multi_init" () uptr))
(define multi-cleanup (foreign-procedure "curl_multi_cleanup" (uptr) int))
(define multi-setopt-long
  (foreign-procedure (__varargs_after 2) "curl_multi_setopt" (uptr int long) int))

(define options
  '((pipelining . 3) (maxconnects . 6) (max-host-connections . 7) (max-pipeline-length . 8)
    (max-total-connections . 13) (max-concurrent-streams . 16) (network-changed . 17)
    (resolve-threads-max . 20) (quick-exit . 21)))

(define values-tried
  (list -1 0 1 2 3 4 100 (- (expt 2 31) 1) (expt 2 31) (expt 2 32) (expt 2 40)
        (- (expt 2 40)) (- (expt 2 62))))

(printf "libcurl ~a\n" (libcurl-info-version info))
(for-each
 (lambda (option)
   (printf "  ~a (~a):" (car option) (cdr option))
   (for-each (lambda (v)
               (let* ((m (multi-init)) (code (multi-setopt-long m (cdr option) v)))
                 (multi-cleanup m)
                 (printf " ~a=>~a" v code)))
             values-tried)
   (newline))
 options)
