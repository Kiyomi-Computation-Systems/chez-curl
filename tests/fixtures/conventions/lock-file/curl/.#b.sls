#!r6rs
;; A regular file named .#...: no lock file, so it is read.
(library (curl b)
  (export)
  (import (rnrs))
  (define b 'foreign-callable))
