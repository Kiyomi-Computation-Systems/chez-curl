#!r6rs
;;; Fixture: an (http-client) library imports (curl) first, which carries the
;;; refusal.
(library (http-client)
  (export client-fixture)
  (import (curl) (rnrs))
  (define client-fixture curl-fixture))
