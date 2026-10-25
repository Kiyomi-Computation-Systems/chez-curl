;;; Spike E1: two threads make the first reference to (curl private native)
;;; together (ADR-0002, amended). Chez locks no library's loading or
;;; invocation, so the second may find it pending and raise "cyclic
;;; dependency". Each reference is eval'd inside a guard: a guard cannot
;;; catch a raise from an imported library's body.
;;;
;;;   load-race.sps MODE
;;;
;;; MODE is import or invoke:
;;;   import  each thread evals the reference in an environment it makes
;;;           itself, so each loads the library and then invokes it;
;;;   invoke  the main thread makes the environment first, which loads the
;;;           library without invoking it, and both threads eval the
;;;           reference in it: the first reference a program that imports
;;;           the library makes, as an engine's thread would.
;;;
;;; Prints one line: what each thread's reference answered.
(import (chezscheme))

(define mode (string->symbol (car (command-line-arguments))))
(define shared (and (eq? mode 'invoke) (environment '(chezscheme) '(curl private native))))
(define mx (make-mutex))
(define cv (make-condition))
(define go #f)
(define results '())
(define (attempt who)
  (with-mutex mx (let w () (unless go (condition-wait cv mx) (w))))
  (let ((r (guard (e (#t (if (message-condition? e) (condition-message e) e)))
             (eval '(begin (loaded-libcurl) 'loaded)
                   (or shared (environment '(chezscheme) '(curl private native)))))))
    (with-mutex mx (set! results (cons (cons who r) results)) (condition-broadcast cv))))
(fork-thread (lambda () (attempt 'forked)))
(sleep (make-time 'time-duration 50000000 0))
(with-mutex mx (set! go #t) (condition-broadcast cv))
(attempt 'main)
(with-mutex mx (let w () (unless (= 2 (length results)) (condition-wait cv mx) (w))))
(printf "load-race ~a: ~s\n" mode
        (list-sort (lambda (a b) (string<? (symbol->string (car a)) (symbol->string (car b))))
                   results))
