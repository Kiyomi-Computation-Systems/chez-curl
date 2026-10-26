;;; M3 slice 3: the resolver threads an engine leaves behind (ADR-0019,
;;; amended 2026-10-25). Written by the slice's review. Linux only: it counts
;;; /proc/self/task. run.sh's threads set runs it under the stand-in with
;;; STALL_MS 0, so every lookup answers at once.
;;;
;;;   threads.sps WITHOUT N
;;;
;;; N engines, made by make-curl-engine-without-quick-exit WITHOUT unless
;;; it is none, each running one transfer to a .stall.invalid name, then
;;; stopped; the thread count before, after each 5, and 3 s after the last.
(import (chezscheme) (curl private engine) (curl private transfer) (curl private conditions) (curl private counters))
(define without (string->symbol (car (command-line-arguments))))
(define n (string->number (cadr (command-line-arguments))))
(define (threads) (length (directory-list "/proc/self/task")))
(define (make) (if (eq? without 'none) (make-curl-engine) (make-curl-engine-without-quick-exit (list without))))
(printf "start ~a threads\n" (threads))
(do ((i 1 (+ i 1))) ((> i n))
  (let* ((e (make))
         (tok (curl-engine-submit e (make-transfer-request (format "http://q~a.stall.invalid/" i) 'get '() #f 5000 #f #f #t #f)))
         (code (guard (x ((curl-transfer-error? x) (curl-transfer-error-code x))) (curl-token-await tok) 'ok)))
    (curl-engine-stop e)
    (when (= 0 (mod i 5)) (printf "after ~a engines (last code ~a): ~a threads\n" i code (threads)))))
(sleep (make-time 'time-duration 0 3))
(printf "3 s later: ~a threads; counts ~s\n" (threads) (native-counts))
