#!r6rs
;;; (curl private memory): counted foreign blocks (M2 plan, sections 3.2 and
;;; 4.2). The only library check-seam lets import foreign-alloc and
;;; foreign-free (ADR-0007).
;;;
;;; A block is malloc'd memory, where Valgrind sees an overrun or a leak.
;;; Each one is counted as a block in (curl private counters) while it
;;; lives, and kept in a table of live blocks, behind a mutex, so that
;;; freeing an address that is not a live block, twice or never allocated
;;; here, raises before anything reaches free.
;;;
;;; It never loads libcurl.
(library (curl private memory)
  (export foreign-block free-foreign-block!)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) foreign-alloc foreign-free make-mutex with-mutex)
          (curl private counters))

  ;; The live blocks, by address, each with its size, and the mutex every
  ;; read and write holds.
  (define live (make-eqv-hashtable))
  (define lock (make-mutex))

  ;; foreign-block : Positive-Integer -> Positive-Integer
  ;; A fresh block of SIZE bytes, uninitialised, counted: its address. An
  ;; assertion violation for a SIZE that is not a positive exact integer,
  ;; and an error when foreign-alloc answers 0.
  (define (foreign-block size)
    (unless (and (integer? size) (exact? size) (positive? size))
      (assertion-violation 'foreign-block "a block's size is a positive exact integer" size))
    (let ((address (foreign-alloc size)))
      (when (eqv? address 0)
        (error 'foreign-block "foreign-alloc answered 0: no memory for a block" size))
      (with-mutex lock
        (hashtable-set! live address size))
      (count-up! 'block)
      address))

  ;; free-foreign-block! : Positive-Integer -> Void
  ;; Frees the live block at ADDRESS, and counts it down. An address that
  ;; is not a live block raises an assertion violation, and nothing is
  ;; freed.
  (define (free-foreign-block! address)
    (let ((was-live (with-mutex lock
                      (and (hashtable-contains? live address)
                           (begin (hashtable-delete! live address) #t)))))
      (unless was-live
        (assertion-violation 'free-foreign-block! "not a live block" address))
      (foreign-free address)
      (count-down! 'block))))
