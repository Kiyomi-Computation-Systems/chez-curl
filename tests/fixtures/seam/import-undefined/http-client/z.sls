#!r6rs
;; (http-client z) imports (curl), defined in this tree, and (http-client
;; w), which no library in it defines.
(library (http-client z)
  (export z)
  (import (rnrs) (curl) (http-client w))
  (define z 1))
