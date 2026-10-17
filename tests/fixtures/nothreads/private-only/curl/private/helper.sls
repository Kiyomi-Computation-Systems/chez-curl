#!r6rs
;;; Fixture: a private library that does not import the refusal, so it loads
;;; anywhere. Only a check that wrongly imports private libraries sees it.
(library (curl private helper)
  (export helper-fixture)
  (import (rnrs))
  (define helper-fixture "helper"))
