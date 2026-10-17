#!r6rs
;; A case clause's datum list is data: Chez compares the key with it, and
;; answers data for (foreign-procedure "curl_easy_init" () uptr), binding
;; nothing. So the occurrences there are stray, never a binding or a use.
;; A clause's body is code, so the binding in h's is read.
(library (curl c)
  (export f g h)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define (f x)
    (case x
      ((foreign-procedure "curl_easy_init" () uptr) 'data)
      (else 'other)))

  (define (g x)
    (case x
      ((bind-required "curl_easy_init" () uptr #f) 'data)
      (else 'other)))

  (define (h x)
    (case x
      ((1 2) (foreign-procedure "curl_global_init" (long) int))
      (else #f))))
