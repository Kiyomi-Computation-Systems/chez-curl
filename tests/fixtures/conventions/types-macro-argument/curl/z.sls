#!r6rs
;; A macro that is no known wrapper, whose foreign-procedure form has a
;; string entry, so the reader takes it as a direct binding. Its first
;; parameter type is the pattern variable buffer, and the use supplies u8*:
;; Chez binds memcpy with a u8* parameter. A reader that took any symbol for
;; a type let it through; buffer is on no allowlist, so the binding is
;; unreadable.
(library (curl z)
  (export copy-in)
  (import (rnrs) (only (chezscheme) foreign-procedure load-shared-object))
  (define-syntax bind-memcpy
    (syntax-rules ()
      ((_ buffer) (foreign-procedure "memcpy" (buffer uptr size_t) uptr))))
  (define libc (load-shared-object "libc.so.6"))
  (define copy-in (bind-memcpy u8*)))
