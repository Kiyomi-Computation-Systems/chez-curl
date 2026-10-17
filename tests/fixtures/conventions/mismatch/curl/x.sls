#!r6rs
;; Bindings whose conventions differ from their rows: a direct
;; foreign-procedure with a convention its row lacks, and a callable without
;; the one its row requires.
(library (curl x)
  (export curl-easy-init on-write)
  (import (rnrs) (only (chezscheme) foreign-procedure foreign-callable))

  (define curl-easy-init (foreign-procedure __collect_safe "curl_easy_init" () uptr))

  (define on-write
    (foreign-callable (lambda (data size n user) (* size n)) (uptr size_t size_t uptr) size_t)))
