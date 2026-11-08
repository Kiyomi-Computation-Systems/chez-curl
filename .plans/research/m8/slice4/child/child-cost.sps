#!r6rs
;;; child-cost.sps: what one child Chez costs, as a docs suite would spawn
;;; it (M8 slice 4's measurement). Under (curl-testing)'s origin, it runs
;;; child-probe.sps five times plain, and five times through
;;; example-runner.sps, each by capture-command, and prints each run's wall
;;; time in ms, its exit status, and what it wrote; then whether this
;;; process has Valgrind mapped. Run from the repository root:
;;;   $CHEZ --libdirs src:tests:build/scheme-libs --program .plans/research/m8/slice4/child/child-cost.sps
(import (rnrs) (only (chezscheme) getenv library-directories current-time time-second time-nanosecond)
        (curl-testing))

(define dir ".plans/research/m8/slice4/child/")

(define (library-path)
  (let loop ((dirs (map car (library-directories))) (text ""))
    (cond ((null? dirs) text)
          ((string=? text "") (loop (cdr dirs) (car dirs)))
          (else (loop (cdr dirs) (string-append text ":" (car dirs)))))))

(define (ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

(define (under-valgrind?)
  (let ((text (guard (e (#t ""))
                (call-with-port (open-file-input-port "/proc/self/maps" (file-options)
                                                      (buffer-mode block) (native-transcoder))
                  get-string-all))))
    (let loop ((i 0))
      (cond ((> (+ i 9) (string-length text)) #f)
            ((string=? (substring text i (+ i 9)) "vgpreload") #t)
            (else (loop (+ i 1)))))))

(define (run argv)
  (let* ((start (ms)) (r (capture-command argv)) (end (ms)))
    (list (- end start) r)))

(call-with-origin
 (lambda (o)
   (let* ((face (origin-face o 'http))
          (url (string-append "http://" (car face) ":" (number->string (cdr face))))
          (chez (getenv "CHEZ")))
     (let loop ((i 0))
       (when (< i 5)
         (write (cons 'plain (run (list chez "--libdirs" (library-path) "--program"
                                        (string-append dir "child-probe.sps") url))))
         (newline)
         (loop (+ i 1))))
     (let loop ((i 0))
       (when (< i 5)
         (write (cons 'runner (run (list chez "--libdirs" (library-path) "--program"
                                         (string-append dir "example-runner.sps")
                                         (string-append dir "child-probe.sps") url))))
         (newline)
         (loop (+ i 1)))))))
(write (list 'parent-valgrind (under-valgrind?))) (newline)
