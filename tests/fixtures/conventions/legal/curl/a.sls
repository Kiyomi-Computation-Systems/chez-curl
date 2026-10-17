#!r6rs
;; A legal tree: every way the reader accounts for foreign-procedure and
;; foreign-callable, and words that only look like them.
(library (curl a)
  (export bind-required on-write)
  (import (rnrs)
          (only (chezscheme) foreign-procedure foreign-callable foreign-entry?))

  (define (required-entry name library) (foreign-entry? name))

  ;; The known wrapper, as native.sls writes it.
  (define-syntax bind-required
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (begin
         (required-entry entry library)
         (foreign-procedure entry (arg ...) result)))))

  (define curl-easy-init (bind-required "curl_easy_init" () uptr #f))

  ;; Direct bindings: the conventions are what precedes the entry.
  (define curl-easy-perform (foreign-procedure __collect_safe "curl_easy_perform" (uptr) int))
  (define memcpy (foreign-procedure "memcpy" (uptr uptr size_t) uptr))

  ;; Two conventions, in the other order from the row's: compared as sets.
  (define two
    (foreign-procedure (__varargs_after 2) __collect_safe "fixture_two_conventions" (uptr int long) int))

  ;; A define-syntax that is no known wrapper, binding a string entry.
  (define-syntax bind-poll
    (syntax-rules ()
      ((_) (foreign-procedure __collect_safe "curl_multi_poll" (uptr uptr unsigned int uptr) int))))

  ;; A callable, the whole right-hand side of a define.
  (define on-write
    (foreign-callable __collect_safe (lambda (data size n user) (* size n)) (uptr size_t size_t uptr) size_t))

  ;; Neither is an occurrence: a string, and another symbol.
  (define names (list "foreign-procedure" 'foreign-procedures)))
