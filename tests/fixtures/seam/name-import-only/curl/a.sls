(library (curl a) (export run) (import (rnrs) (only (chezscheme) import-only))
  (define (run) (let () (import-only (http-client target)) (hello))))
