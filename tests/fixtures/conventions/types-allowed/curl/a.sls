#!r6rs
;; Every immediate and address type Chez 10.4.0 documents (CSUG 10.4.0
;; section 4.2), written out here from that list: each a parameter of a
;; foreign procedure and of a callable, with void their result. Each is
;; read, and none is a crossing.
(library (curl a)
  (export every on-every)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define every
    (foreign-procedure "fixture_immediate"
      (integer-8 unsigned-8 integer-16 unsigned-16 integer-32 unsigned-32
       integer-64 unsigned-64 double-float single-float double float
       short unsigned-short int unsigned unsigned-int long unsigned-long
       long-long unsigned-long-long ptrdiff_t size_t ssize_t iptr uptr void*
       fixnum boolean stdbool char wchar_t wchar)
      void))

  (define on-every
    (foreign-callable (lambda args (if #f #f))
      (integer-8 unsigned-8 integer-16 unsigned-16 integer-32 unsigned-32
       integer-64 unsigned-64 double-float single-float double float
       short unsigned-short int unsigned unsigned-int long unsigned-long
       long-long unsigned-long-long ptrdiff_t size_t ssize_t iptr uptr void*
       fixnum boolean stdbool char wchar_t wchar)
      void)))
