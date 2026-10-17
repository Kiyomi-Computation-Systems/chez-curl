#!r6rs
;; A12's procedure, in a library of its own: it builds a binding of
;; curl_easy_setopt from strings, with datum->syntax, in this library's
;; context. No rule reads a procedure, and no name here is one the reader
;; looks for.
(library (curl b)
  (export built)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define (built)
    (datum->syntax #'here
                   (list (string->symbol "foreign-procedure") "curl_easy_setopt"
                         '(uptr int long) 'int))))
