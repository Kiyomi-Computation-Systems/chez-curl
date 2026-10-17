;; No #!r6rs: Chez refuses datum labels in that mode. One form, labelled and
;; then referred to: the reader names it and does not walk this datum, so the
;; binding inside is not found.
(library (curl g)
  (export f g)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define f #0=(foreign-procedure "curl_easy_init" () uptr))

  (define g #0#))
