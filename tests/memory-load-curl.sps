#!r6rs
;;; tests/memory-load-curl.sps: loads libcurl through (curl), and says which.
;;; Not a suite.
;;;
;;; `make check-memory-gate` runs it under Valgrind in the Guix container to
;;; hold the one suppression, tests/guix-glibc-locpath.supp, honest (ADR-0014):
;;; with the suppression Valgrind must report the entry used, and without it the
;;; run must fail on the block Guix's glibc loses.
;;; The line it prints shows that libcurl was loaded: (curl)'s body runs only
;;; when one of its bindings is referenced, so this calls loaded-libcurl.
;;;
;;; It is not named tests/test-*.sps, so neither make test nor make
;;; test-memory runs it unasked.
(import (rnrs) (curl))

(let ((info (loaded-libcurl)))
  (display "memory-load-curl: loaded libcurl ")
  (display (libcurl-info-version info))
  (display " from ")
  (display (libcurl-info-path info))
  (newline))
(exit 0)
