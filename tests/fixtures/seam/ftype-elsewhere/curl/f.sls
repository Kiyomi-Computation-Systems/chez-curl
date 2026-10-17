#!r6rs
;;; Fixture for tests/test-check-seam.sps: a library that is not listed
;;; imports define-ftype, to bind a C entry point as a function ftype. format
;;; beside it is allowed everywhere, and is not named.
(library (curl f)
  (export f)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) format define-ftype ftype-ref make-ftype-pointer))
  (define-ftype perform (function (uptr) int))
  (define (f easy)
    ((ftype-ref perform () (make-ftype-pointer perform "curl_easy_perform")) easy)))
