#!r6rs
;;; Fixture: a public library that imports the refusal first.
(library (curl)
  (export curl-fixture)
  (import (curl private require-threaded) (rnrs))
  (define curl-fixture "curl"))
