#!r6rs
;; Plain macros that would build a binding: one holds a foreign-procedure
;; form, one a foreign-callable, one a known wrapper's use. Each is named,
;; beside whatever the walk finds in it.
(library (curl p)
  (export)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define-syntax bind-poll
    (syntax-rules ()
      ((_) (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned int uptr) int))))

  (define-syntax on-callable
    (syntax-rules ()
      ((_) (list (foreign-callable (lambda (n) n) (int) int)))))

  (define-syntax via-wrapper
    (syntax-rules ()
      ((_) (bind-required "curl_easy_init" () uptr #f)))))
