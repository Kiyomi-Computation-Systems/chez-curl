#!r6rs
;; A6's procedure, in a library of its own: it takes the use it is handed
;; apart, (m (head "entry" . rest)), and hands back (head "curl_easy_setopt"
;; . rest), named in this library's context. The rules read macro
;; definitions, not procedures, so nothing here is named.
(library (curl h)
  (export rebuild)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define (rebuild x)
    (let ((d (syntax->datum x)))
      (datum->syntax #'here
                     (cons (car (cadr d)) (cons "curl_easy_setopt" (cddr (cadr d))))))))
