#!r6rs
;; A syntax-violation of a library's own, which returns the form it is
;; handed instead of raising.
(library (curl v)
  (export syntax-violation)
  (import (except (rnrs) syntax-violation))

  (define (syntax-violation who message form) form))
