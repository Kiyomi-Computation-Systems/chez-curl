#!r6rs
;;; Fixture: a public library that does not import the refusal first, so it
;;; loads on any Chez. This is the fault in this tree.
(library (curl unsupported)
  (export unsupported-fixture)
  (import (rnrs))
  (define unsupported-fixture "unsupported"))
