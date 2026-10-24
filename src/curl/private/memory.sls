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
;;; Each block's malloc, its entry in the table and its count happen in one
;;; critical section, and so do its removal, free and count down: an
;;; interrupt that escapes, an engine's expiry say, cannot fall between them
;;; and leave a block no table and no count sees, nor leave the table's
;;; mutex held (M2 fix round 2).
;;;
;;; It never loads libcurl.
(library (curl private memory)
  (export foreign-block free-foreign-block!)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) critical-section foreign-alloc foreign-free make-mutex with-mutex)
          (curl private counters))

  ;; The live blocks, by address, each with its size, and the mutex every
  ;; read and write holds.
  (define live (make-eqv-hashtable))
  (define lock (make-mutex))

  ;; locked : Mutex (-> Any) -> Any
  ;; THUNK's value, run holding LOCK, in a critical section. Chez's
  ;; with-mutex is a dynamic-wind whose before thunk takes the mutex, so an
  ;; interrupt that escapes, an engine's expiry say, between the take and
  ;; the wind would leave it held, with no after thunk to release it, and
  ;; block every other thread. Every mutex here is held through locked.
  (define (locked lock thunk)
    (critical-section (with-mutex lock (thunk))))

  ;; foreign-block : Positive-Integer -> Positive-Integer
  ;; A fresh block of SIZE bytes, uninitialised, counted: its address. An
  ;; assertion violation for a SIZE that is not a positive exact integer,
  ;; and an error when foreign-alloc answers 0.
  (define (foreign-block size)
    (unless (and (integer? size) (exact? size) (positive? size))
      (assertion-violation 'foreign-block "a block's size is a positive exact integer" size))
    (critical-section
     (let ((address (foreign-alloc size)))
       (when (eqv? address 0)
         (error 'foreign-block "foreign-alloc answered 0: no memory for a block" size))
       (locked lock (lambda () (hashtable-set! live address size)))
       (count-up! 'block)
       address)))

  ;; free-foreign-block! : Positive-Integer -> Void
  ;; Frees the live block at ADDRESS, and counts it down. An address that
  ;; is not a live block raises an assertion violation, and nothing is
  ;; freed.
  (define (free-foreign-block! address)
    (critical-section
     (let ((was-live (locked lock
                       (lambda ()
                         (and (hashtable-contains? live address)
                              (begin (hashtable-delete! live address) #t))))))
       (unless was-live
         (assertion-violation 'free-foreign-block! "not a live block" address))
       (foreign-free address)
       (count-down! 'block)))))
