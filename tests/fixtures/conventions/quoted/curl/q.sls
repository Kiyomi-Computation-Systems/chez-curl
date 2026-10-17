#!r6rs
;; Quoted occurrences: data, not bindings. Each is named.
(library (curl q)
  (export q)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define (q)
    (list 'foreign-procedure
          '(foreign-procedure "curl_easy_init" () uptr)
          `(,(foreign-procedure "curl_global_init" (long) int))
          #'foreign-callable
          #(foreign-callable (foreign-procedure "curl_easy_perform" (uptr) int)))))
