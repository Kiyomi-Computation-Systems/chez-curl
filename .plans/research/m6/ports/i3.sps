;; Item 3: the buffer-size defaults, and when each is read.
(import (chezscheme))

(define (say fmt . args)
  (apply printf fmt args)
  (newline)
  (flush-output-port (current-output-port)))

(say "scheme-version ~a machine-type ~s threaded? ~s optimize-level ~s"
     (scheme-version) (machine-type) (threaded?) (optimize-level))
(say "file-buffer-size default ~s" (file-buffer-size))
(say "custom-port-buffer-size default ~s" (custom-port-buffer-size))
(say "transcoded-port-buffer-size default ~s" (transcoded-port-buffer-size))

;; Each is a thread parameter: what does a forked thread see after the
;; parent changes it?
(let* ([m (make-mutex)]
       [answer #f]
       [set-answer! (lambda (x) (with-mutex m (set! answer x)))]
       [get-answer (lambda () (with-mutex m answer))])
  (parameterize ([file-buffer-size 333] [custom-port-buffer-size 77])
    (fork-thread
      (lambda ()
        (set-answer!
          (guard (c [#t (list 'raised (condition-message c))])
            (list (file-buffer-size) (custom-port-buffer-size)))))))
  (let loop ([i 0])
    (cond
      [(get-answer) => (lambda (a) (say "forked under parameterize 333/77 sees ~s" a))]
      [(fx= i 200) (say "forked thread: no answer within 2 s")]
      [else (sleep (make-time 'time-duration 10000000 0)) (loop (fx+ i 1))])))

(say "I3 done")
