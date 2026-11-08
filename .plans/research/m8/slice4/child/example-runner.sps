#!r6rs
;;; example-runner.sps: a prototype of the wrapper a docs suite could run an
;;; example under, so that the example imports public libraries alone and
;;; the wrapper prints the native counts (AGENTS.md's counters rule).
;;;   example-runner.sps EXAMPLE ARG ...
;;; It loads EXAMPLE as a top-level program in this process, with
;;; (command-line) as (EXAMPLE ARG ...), then writes (counts ALIST) on
;;; stderr: (curl private counters)' native-counts once the program's body
;;; has returned. The example's stdout is its own.
(import (chezscheme) (curl private counters))

(define args (command-line-arguments))
(parameterize ((command-line args))
  (load-program (car args)))
(let ((err (current-error-port)))
  (write (list 'counts (native-counts)) err)
  (newline err)
  (flush-output-port err))
