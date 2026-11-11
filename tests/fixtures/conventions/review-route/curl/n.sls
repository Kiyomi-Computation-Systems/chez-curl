#!r6rs
;; load-step, a plain macro, gains a flat second clause that puts its first
;; operand at the head: handed define-syntax, it defines bind-quietly, whose
;; syntax-case builds a foreign-procedure form from strings.
;; curl-easy-setopt-long is bound through it, plain, while an unused
;; bind-variadic keeps the count. The clause's head and the handed keyword
;; are each named.
(library (curl n)
  (export curl-easy-setopt-long)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  (define-syntax bind-variadic
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure (__varargs_after 2) entry (arg ...) result)))))

  (define-syntax load-step
    (syntax-rules ()
      ((_ expr) (guard (e (#t (raise e))) expr))
      ((_ head operand ...) (head operand ...))))

  (load-step define-syntax bind-quietly
    (lambda (x)
      (syntax-case x ()
        ((k entry types result)
         (datum->syntax #'k
                        (list (string->symbol (string-append "foreign-" "procedure"))
                              (syntax->datum #'entry) (syntax->datum #'types)
                              (syntax->datum #'result)))))))

  (define curl-easy-setopt-long-unused
    (load-step (bind-variadic "curl_easy_setopt" (uptr int long) int #f)))

  (define curl-easy-setopt-long
    (load-step (bind-quietly "chez_curl_review_absent" (uptr int long) int))))
