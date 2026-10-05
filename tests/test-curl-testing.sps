#!r6rs
;;; The suite for (curl-testing), the helpers every suite shares (ADR-0015):
;;; the verdict behind the shared exit form, then capture-command, run-until,
;;; seeded-bytes and describe.
;;;
;;; Each expected value is one the code under test cannot produce by failing.
;;; SRFI-64 turns a raise in the actual expression into #f, so no expected
;;; value here is #f, and every check of a refusal compares what was raised
;;; against a no-raise sentinel.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize record-writer)
        ;; Chez's own current-error-port is a parameter; (rnrs)'s takes no
        ;; argument, and reads the same port.
        (prefix (only (chezscheme) current-error-port) chez:)
        (curl-testing))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; raised : (-> Any) -> Any
;; What THUNK raised: (assertion-violation WHO IRRITANTS) for an assertion
;; violation, something else for any other raise, and the symbol no-raise if
;; THUNK returned.
(define (raised thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e)
                  (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            ((message-condition? e) (list 'other-raise (condition-message e)))
            (#t (list 'other-raise e)))
    (thunk)
    'no-raise))

(test-begin "curl-testing")

;; --- suite-exit-status: the verdict behind the shared exit form -----------
;; Each runner below is a fresh null runner, which prints nothing and which
;; this suite's own runner never sees. Each base holds the outcomes the rule
;; under test must ignore, so that only that rule can produce the expected
;; verdict.

;; runner-after : (-> Any) -> Test-Runner
(define (runner-after thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r
      (test-begin "inner")
      (thunk)
      (test-end "inner"))
    r))

;; verdict : Test-Runner -> (List Integer String)
;; suite-exit-status's answer, then everything it wrote to the error port.
(define (verdict r)
  (let-values (((port contents) (open-string-output-port)))
    (let ((status (parameterize ((chez:current-error-port port))
                    (suite-exit-status r))))
      (list status (contents)))))

(test-equal "a pass beside an expected failure and a skip: exit 0, and nothing said"
  '(0 "")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256"
  '(1 "suite-exit-status: exit 1 (pass 1, fail 2, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-assert "fails" #f)
                           (test-assert "fails too" #f)))))

(test-equal "an unexpected pass beside a pass: exit 1"
  '(1 "suite-exit-status: exit 1 (pass 1, fail 0, xpass 1): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "passes unexpectedly" #t)))))

(test-equal "an expected failure and a skip, but no pass: exit 1"
  '(1 "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "no test at all: exit 1"
  '(1 "suite-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda () 'no-tests))))

(test-equal "suite-exit-status refuses what is not a runner"
  '(assertion-violation suite-exit-status ("not a runner"))
  (raised (lambda () (suite-exit-status "not a runner"))))

;; --- capture-command ------------------------------------------------------

(test-equal "capture-command: the exit status, stdout and stderr, kept apart"
  '(3 "out\n" "err\n")
  (capture-command '("sh" "-c" "echo out; echo err >&2; exit 3")))

(test-equal "capture-command: each argument arrives as one word, unchanged"
  '(0 "a b|$HOME|it's|\"q\"|back\\slash||*|;|two\nlines|" "")
  (capture-command
   (list "printf" "%s|"
         "a b" "$HOME" "it's" "\"q\"" "back\\slash" "" "*" ";" "two\nlines")))

(test-equal "capture-command: a NUL would cut the command short, so it is refused"
  (list 'assertion-violation 'capture-command (list (string #\a #\nul #\b)))
  (raised (lambda () (capture-command (list "printf" (string #\a #\nul #\b))))))

(test-equal "capture-command: every argument is a string"
  '(assertion-violation capture-command (5))
  (raised (lambda () (capture-command '("echo" 5)))))

(test-equal "capture-command: a command has at least its name"
  '(assertion-violation capture-command (()))
  (raised (lambda () (capture-command '()))))

;; --- run-until ------------------------------------------------------------

;; steps-until : Natural Natural -> (List Symbol Natural)
;; run-until's answer for a predicate that holds once N steps are taken,
;; under a cap of CAP, then the number of steps it took.
(define (steps-until n cap)
  (let* ((steps 0)
         (answer (run-until (lambda () (set! steps (+ steps 1)))
                            (lambda () (>= steps n))
                            cap)))
    (list answer steps)))

(test-equal "run-until: a predicate that already holds costs no step"
  '(satisfied 0)
  (steps-until 0 5))

(test-equal "run-until: it steps until the predicate holds, and no further"
  '(satisfied 3)
  (steps-until 3 5))

(test-equal "run-until: a predicate that first holds after the last step allowed is satisfied"
  '(satisfied 4)
  (steps-until 4 4))

(test-equal "run-until: one step short, it answers iterations-exhausted, with no step past the cap"
  '(iterations-exhausted 4)
  (steps-until 5 4))

(test-equal "run-until: the cap is a positive exact integer"
  '(assertion-violation run-until (0))
  (raised (lambda () (run-until (lambda () 'step) (lambda () #f) 0))))

(test-equal "run-until: the predicate is a procedure"
  '(assertion-violation run-until (#t))
  (raised (lambda () (run-until (lambda () 'step) #t 3))))

(test-equal "run-until: the step is a procedure"
  '(assertion-violation run-until (step))
  (raised (lambda () (run-until 'step (lambda () #f) 3))))

;; --- seeded-bytes ---------------------------------------------------------
;; The expected bytes were computed outside Chez, from the generator its
;; comment documents: x <- (1103515245 x + 12345) mod 2^31, from x = seed,
;; and each byte is bits 16 to 23 of the new x.

(test-equal "seeded-bytes: seed 1, as the documented generator computes it"
  #vu8(198 126 129 107 75 251 226 251)
  (seeded-bytes 8 1))

(test-equal "seeded-bytes: seed 2, other bytes"
  #vu8(140 33 255 114 237 215 24 217)
  (seeded-bytes 8 2))

(test-equal "seeded-bytes: as many bytes as asked for, none included"
  '(0 1000)
  (list (bytevector-length (seeded-bytes 0 1))
        (bytevector-length (seeded-bytes 1000 1))))

(test-equal "seeded-bytes: the length is a natural number"
  '(assertion-violation seeded-bytes (-1))
  (raised (lambda () (seeded-bytes -1 1))))

(test-equal "seeded-bytes: the seed is a natural number"
  '(assertion-violation seeded-bytes (1.5))
  (raised (lambda () (seeded-bytes 4 1.5))))

;; --- describe -------------------------------------------------------------

(define-record-type unprintable (fields x))
(record-writer (record-type-descriptor unprintable)
  (lambda (r port wr) (error 'unprintable "this record cannot be printed")))

(test-equal "describe: a condition, as display-condition shows it"
  "Exception in f: bad thing with irritants (1 \"two\")"
  (describe (condition (make-error)
                       (make-who-condition 'f)
                       (make-message-condition "bad thing")
                       (make-irritants-condition '(1 "two")))))

(test-equal "describe: anything else is written, so a string keeps its quotes"
  "(1 \"two\" three)"
  (describe '(1 "two" three)))

(test-equal "describe: an object whose printing raises gets a fixed text, not a raise"
  "<the raised object could not be printed>"
  (describe (make-unprintable 1)))

(test-end "curl-testing")

;; This suite tests suite-exit-status, so its exit cannot rest on it alone:
;; a suite-exit-status that ignored failures would pass this suite, and
;; make test with it. Any failure here exits 1 first.
(when (positive? (test-runner-fail-count runner))
  (exit 1))

(exit (suite-exit-status runner))
