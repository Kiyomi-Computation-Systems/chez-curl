(library (curl b) (export run) (import (rnrs) (only (chezscheme) top-level-value))
  (define (run) ((top-level-value 'eval) '(let () (import (http-client target)) (hello)))))
