#!r6rs
;;; tests/memory-plant-leak.sps: a PLANTED definite leak. Not a suite.
;;;
;;; `make check-memory-gate` runs it through `make test-memory` and requires
;;; the gate to FAIL on it, with Valgrind's own loss record in the log
;;; (ADR-0014). It also runs it with the container's suppression on, so the
;;; suppression is seen not to hide a leak of chez-curl's own.
;;;
;;; It allocates a 777-byte foreign block and drops its address: no live
;;; value holds it, so Valgrind counts it definitely lost. A Chez fixnum
;;; holds an address shifted, never as the raw pointer, so the dropped
;;; integer does not keep the block reachable. A plain run exits 0:
;;; check-memory-gate requires that first, so a red gate can only mean
;;; Valgrind saw the leak. The size is a sentinel: nothing else in a run
;;; loses a block of 777 bytes.
;;;
;;; It is not named tests/test-*.sps, so neither make test nor make
;;; test-memory runs it unasked.
(import (rnrs)
        (only (chezscheme) foreign-alloc))

(foreign-alloc 777)

(display "memory-plant-leak: planted a 777-byte foreign block that nothing frees or holds")
(newline)
(exit 0)
