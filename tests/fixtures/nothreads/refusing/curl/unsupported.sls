#!r6rs
;;; Fixture: a public library that imports the refusal first.
(library (curl unsupported)
  (export unsupported-fixture)
  (import (curl private require-threaded) (rnrs))
  (define unsupported-fixture "unsupported"))
