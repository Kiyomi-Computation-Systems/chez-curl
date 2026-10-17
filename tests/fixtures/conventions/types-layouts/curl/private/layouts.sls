#!r6rs
;; This tree's (curl private layouts): the ftypes a (* NAME) or (& NAME)
;; type may name. Only a (define-ftype NAME TYPE) in its library body
;; defines one; not-an-ftype is a variable.
(library (curl private layouts)
  (export fixture-struct not-an-ftype)
  (import (rnrs) (only (chezscheme) define-ftype))

  (define-ftype fixture-struct
    (struct
      (age int)
      (version uptr)))

  (define not-an-ftype 0))
