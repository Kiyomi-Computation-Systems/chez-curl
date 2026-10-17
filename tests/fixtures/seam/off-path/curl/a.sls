#!r6rs
;; A14's shape: (curl extra), a second library in this file. Rule (h) reads
;; it as defined under the directory, but Chez looks for it at
;; curl/extra.sls, and may load it from another directory first.
(library (curl a)
  (export a)
  (import (rnrs))
  (define a 1))

(library (curl extra)
  (export extra)
  (import (rnrs))
  (define extra 1))
