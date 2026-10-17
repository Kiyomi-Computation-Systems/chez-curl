#!r6rs
;; (curl x) imports (curl y), defined beside it, and (curl private extra),
;; which no library in this tree defines: Chez would load that one from
;; another directory on its library path, as tests/ is for the suites.
(library (curl x)
  (export x)
  (import (rnrs) (curl y) (prefix (curl private extra) e:))
  (define x 1))
