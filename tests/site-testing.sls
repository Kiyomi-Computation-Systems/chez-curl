#!r6rs
;;; The verdict the docs site's suites exit through, tests/site-unit.sps and
;;; tests/site-render-unit.sps. They run on apt's Chez in CI and the Pages
;;; workflow, below chez-curl's floor, so they import nothing under src/:
;;; (curl-testing)'s suite-exit-status reads (curl private counters), which
;;; refuses that Chez. Nothing the site's suites test makes a native object,
;;; so there are no counts to read: this is the shared verdict's rule for the
;;; runner alone. check-suites holds each site suite to site-exit-form, and
;;; tests/test-site-testing.sps holds the verdict.
(library (site-testing)
  (export site-exit-form site-exit-status)
  (import (rnrs) (srfi :64))

  ;; site-exit-form : Datum
  ;; The last datum of every tests/site-*.sps. `runner` is the suite's own
  ;; binding for the runner it makes current.
  (define site-exit-form '(exit (site-exit-status runner)))

  ;; site-exit-status : Test-Runner -> (U 0 1)
  ;; 0 when RUNNER saw a pass, and no failure and no unexpected pass.
  ;; Otherwise 1, after a line on the error port naming the runner's counts.
  ;; Expected failures and skips count neither way. The answer is 0 or 1,
  ;; never a count: exit statuses wrap at 256.
  (define (site-exit-status runner)
    (unless (test-runner? runner)
      (assertion-violation 'site-exit-status "not a SRFI-64 test runner" runner))
    (let ((pass (test-runner-pass-count runner))
          (fail (test-runner-fail-count runner))
          (xpass (test-runner-xpass-count runner)))
      (if (and (> pass 0) (= fail 0) (= xpass 0))
          0
          (let ((err (current-error-port)))
            ;; The runner's own summary, on stdout, comes first.
            (flush-output-port (current-output-port))
            (put-string err
              (string-append "site-exit-status: exit 1 (pass " (number->string pass)
                             ", fail " (number->string fail)
                             ", xpass " (number->string xpass)
                             "): a suite needs a pass, and no fail or xpass\n"))
            (flush-output-port err)
            1)))))
