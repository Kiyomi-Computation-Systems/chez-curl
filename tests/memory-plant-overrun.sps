#!r6rs
;;; tests/memory-plant-overrun.sps: a PLANTED heap overrun. Not a suite.
;;;
;;; `make check-memory-gate` runs it through `make test-memory` and requires
;;; the gate to FAIL on it, with Valgrind's own report of the write in the
;;; log (ADR-0014). A gate nobody has watched fail checks nothing: one that
;;; hands Valgrind timeout instead of Chez stays green on every run.
;;;
;;; It writes one byte just past the end of a 23-byte foreign block, then
;;; frees the block. malloc rounds 23 up to a 24-byte chunk, so a plain run
;;; overwrites nothing that is in use, and exits 0: check-memory-gate requires
;;; that first, so a red gate can only mean Valgrind saw the write. The size
;;; is a sentinel: nothing else in a run overruns a block of 23 bytes.
;;;
;;; It is not named tests/test-*.sps, so neither make test nor make
;;; test-memory runs it unasked.
(import (rnrs)
        (only (chezscheme) foreign-alloc foreign-set! foreign-free))

(define size 23)

(let ((block (foreign-alloc size)))
  (foreign-set! 'unsigned-8 block size 1)
  (foreign-free block))

(display "memory-plant-overrun: planted a one-byte write just past a 23-byte foreign block")
(newline)
(exit 0)
