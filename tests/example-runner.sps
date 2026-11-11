#!r6rs
;;; tests/example-runner.sps: runs one example as tests/test-examples.sps
;;; needs it run, so that the example imports public libraries alone and the
;;; native counts are still read.
;;;
;;;   example-runner.sps EXAMPLE ARG ...
;;;
;;; It loads EXAMPLE as a top-level program in this process, by Chez's
;;; load-program, with (command-line) as (EXAMPLE ARG ...), as the example
;;; would have it run alone. Once the example's body has returned, it writes
;;; one line on stderr, (counts ALIST), (curl private counters)' native
;;; counts, and nothing else. The example's stdout is its own. An example
;;; that raises, or calls exit, leaves before that line, so its suite sees
;;; no counts.
(import (chezscheme) (curl private counters))

(define arguments (command-line-arguments))

(when (null? arguments)
  (assertion-violation 'example-runner "an example's path is required"))

(parameterize ((command-line arguments))
  (load-program (car arguments)))

(let ((err (current-error-port)))
  (write (list 'counts (native-counts)) err)
  (newline err)
  (flush-output-port err))
