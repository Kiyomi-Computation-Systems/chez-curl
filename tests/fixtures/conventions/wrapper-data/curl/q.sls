#!r6rs
;; A known wrapper's name in data: a quoted symbol, a quoted use, a use under
;; an unquote in a quasiquote, and a vector literal holding a use. Each is
;; stray.
(library (curl q)
  (export q)
  (import (rnrs))

  (define (q)
    (list 'bind-required
          '(bind-variadic "curl_easy_setopt" (uptr int long) int #f)
          `(,(bind-required "curl_easy_init" () uptr #f))
          #(bind-variadic "curl_easy_getinfo" (uptr int uptr) int #f))))
