(library (curl d) (export run) (import (rnrs) (only (chezscheme) $primitive))
  (define (run) (($primitive eval) '(let () (import (http-client target)) (hello)))))
