;;; verify/copy-hold.sps: does a large primitive copy, with no critical
;;; section, hold off a Ctrl-C? One thread, no collector: SIGINT raised on
;;; the main thread, by raise(3) (glibc's, so Linux alone), just before the
;;; work; the keyboard handler notes when it runs. The work: bytevector-copy of 256 MiB, string-copy of
;;; 64 Mi chars, string->utf8 of the same; and a control, the same 256 MiB
;;; copied in 4 KiB pieces, 65,536 calls of bytevector-copy!, which run out
;;; Chez's 1,000-tick event counter many times over, into a bytevector made
;;; before the clock starts. Prints (CASE (work-ms MS) (handler-after-ms MS)),
;;; the second the time from the raise to the handler.
(import (chezscheme))

(load-shared-object "libc.so.6")
(define raise-signal (foreign-procedure "raise" (int) int))
(define sigint 2)

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000.) (/ (time-nanosecond t) 1000000.))))

(define size (* 256 1024 1024))
(define source (make-bytevector size 7))
(define text (make-string (* 64 1024 1024) #\a))
(define out (make-bytevector size))

(define (measure label work)
  (collect)
  (let ((ran #f))
    (keyboard-interrupt-handler (lambda () (set! ran (now-ms))))
    (let* ((start (now-ms)))
      (raise-signal sigint)
      (work)
      (let ((end (now-ms)))
        ;; the handler runs by the next event check after the work
        (let loop ((i 0)) (unless (or ran (= i 100000000)) (loop (+ i 1))))
        (printf "(~a (work-ms ~,1f) (handler-after-ms ~a))\n" label (- end start)
                (if ran (format "~,1f" (- ran start)) "never"))))))

(measure 'bytevector-copy (lambda () (bytevector-copy source)))
(measure 'string-copy (lambda () (string-copy text)))
(measure 'string->utf8 (lambda () (string->utf8 text)))
(measure 'pieces-control
         (lambda ()
           (let ((piece 4096))
             (do ((i 0 (+ i piece))) ((= i size))
               (bytevector-copy! source i out i piece)))))
