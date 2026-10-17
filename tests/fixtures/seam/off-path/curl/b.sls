#!r6rs
;; (curl c), the one library in a file named for another.
(library (curl c)
  (export c)
  (import (rnrs))
  (define c 1))
