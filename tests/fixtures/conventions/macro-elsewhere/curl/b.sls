#!r6rs
;; step, a macro the table lists in curl/a.sls, defined here instead. Its
;; definition is named, with the file its row names.
(library (curl b)
  (export)
  (import (rnrs))

  (define-syntax step
    (syntax-rules ()
      ((_ e) e))))
