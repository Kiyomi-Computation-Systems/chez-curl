#!r6rs
;;; The suite for (site-testing): site-exit-status, the verdict the docs
;;; site's suites exit through, and site-exit-form, the datum check-suites
;;; holds them to. Each runner a row reads is a fresh null runner, which
;;; prints nothing and which this suite's own runner never sees. Each base
;;; holds the outcomes the rule under test must ignore, so that only that
;;; rule can produce the expected verdict.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) parameterize)
        ;; Chez's own current-error-port is a parameter; (rnrs)'s takes no
        ;; argument, and reads the same port.
        (prefix (only (chezscheme) current-error-port) chez:)
        (site-testing)
        (curl-testing))

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

;; runner-after : (-> Any) -> Test-Runner
(define (runner-after thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r
      (test-begin "inner")
      (thunk)
      (test-end "inner"))
    r))

;; verdict : Test-Runner -> (List Integer String)
;; site-exit-status's answer, then everything it wrote to the error port.
(define (verdict r)
  (let-values (((port contents) (open-string-output-port)))
    (let ((status (parameterize ((chez:current-error-port port))
                    (site-exit-status r))))
      (list status (contents)))))

;; refusal : (-> Any) -> Any
;; What THUNK raised, as (assertion-violation WHO IRRITANTS) for an assertion
;; violation and (other-raise ...) for any other raise, or no-raise.
(define (refusal thunk)
  (guard (e ((and (assertion-violation? e) (who-condition? e) (irritants-condition? e))
             (list 'assertion-violation (condition-who e) (condition-irritants e)))
            (#t (list 'other-raise e)))
    (thunk)
    'no-raise))

(test-begin "site-testing")

(test-equal "a pass beside an expected failure and a skip: exit 0, and nothing said"
  '(0 "")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "two failures beside a pass: exit 1, not a count, since exit statuses wrap at 256"
  '(1 "site-exit-status: exit 1 (pass 1, fail 2, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-assert "fails" #f)
                           (test-assert "fails too" #f)))))

(test-equal "an unexpected pass beside a pass: exit 1"
  '(1 "site-exit-status: exit 1 (pass 1, fail 0, xpass 1): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-assert "passes" #t)
                           (test-expect-fail 1)
                           (test-assert "passes unexpectedly" #t)))))

(test-equal "an expected failure and a skip, but no pass: exit 1"
  '(1 "site-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda ()
                           (test-expect-fail 1)
                           (test-assert "fails, as expected" #f)
                           (test-skip 1)
                           (test-assert "skipped" #t)))))

(test-equal "no test at all: exit 1"
  '(1 "site-exit-status: exit 1 (pass 0, fail 0, xpass 0): a suite needs a pass, and no fail or xpass\n")
  (verdict (runner-after (lambda () 'no-tests))))

(test-equal "site-exit-status refuses what is not a runner"
  '(assertion-violation site-exit-status ("not a runner"))
  (refusal (lambda () (site-exit-status "not a runner"))))

;; The expected form is built, not quoted: check-suites reads a quoted exit
;; form as an early exit.
(test-equal "a site suite ends with (exit (site-exit-status runner)), not the shared form"
  (list (list 'exit (list 'site-exit-status 'runner)) #f)
  (list site-exit-form (equal? site-exit-form suite-exit-form)))

(test-end "site-testing")

;; This suite tests a verdict, so its exit cannot rest on that verdict: it
;; exits through the shared form, and any failure here exits 1 first.
(when (positive? (test-runner-fail-count runner))
  (exit 1))

(exit (suite-exit-status runner))
