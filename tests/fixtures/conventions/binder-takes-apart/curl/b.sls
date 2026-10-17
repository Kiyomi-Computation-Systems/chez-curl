#!r6rs
;; A binder whose pattern takes its library operand apart, as A5's
;; swap-entry takes apart a use: handed (bind-required "memcpy" ...) there,
;; its template would rebuild it with curl_easy_setopt. It cannot be read,
;; so none of its uses is.
(library (curl b)
  (export curl-easy-init)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result (w e . rest))
       (begin
         (w "curl_easy_setopt" . rest)
         (foreign-procedure entry (arg ...) result)))))

  (define curl-easy-init (bind-required "curl_easy_init" () uptr (begin #f))))
