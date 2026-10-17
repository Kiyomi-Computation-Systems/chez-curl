#!r6rs
;; Two macros that build nothing, at a library body's top level: checked is
;; on the table, step on no row. step is named, though it holds nothing a
;; plain macro may not.
(library (curl u)
  (export)
  (import (rnrs))

  (define-syntax checked
    (syntax-rules ()
      ((_ e) e)))

  (define-syntax step
    (syntax-rules ()
      ((_ e) e))))
