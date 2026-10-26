#!r6rs
;; A legal tree: every way the reader accounts for foreign-procedure,
;; foreign-callable and a known wrapper, and words that only look like them.
(library (curl a)
  (export curl-easy-init curl-global-init curl-easy-cleanup on-write)
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

  ;; Its uses, in its own file: a library may not export it. A let's
  ;; initial value is code.
  (define curl-easy-init (bind-required "curl_easy_init" () uptr #f))

  (define curl-global-init
    (let ((bound (bind-required "curl_global_init" (long) int #f))) bound))

  ;; Plain macros, as load-state.sls and require-threaded.sls write them: a
  ;; syntax-rules whose pattern is identifiers only, and a transformer that
  ;; takes nothing apart. A use handed whole to the first is code.
  (define-syntax step
    (syntax-rules ()
      ((_ expr) (guard (e (#t (raise e))) expr))))

  (define-syntax checked
    (lambda (x)
      (if (string? "ok")
          #'(define checked-ok #t)
          (syntax-violation 'checked "refused" x))))

  (define curl-easy-cleanup (step (bind-required "curl_easy_cleanup" (uptr) void #f)))

  ;; Direct bindings: the conventions are what precedes the entry.
  (define fixture-blocking (foreign-procedure __collect_safe "fixture_blocking" (uptr) int))
  (define memcpy (foreign-procedure "memcpy" (uptr uptr size_t) uptr))

  ;; Two conventions, in the other order from the row's: compared as sets.
  (define two
    (foreign-procedure (__varargs_after 2) __collect_safe "fixture_two_conventions" (uptr int long) int))

  ;; A define-syntax that is no known wrapper, binding a string entry: the
  ;; fixture's table lists it as any, which only a fixture may. Its entry is
  ;; a fixture row's: the real table holds each blocking multi call to
  ;; bind-blocking.
  (define-syntax bind-poll
    (syntax-rules ()
      ((_) (foreign-procedure __collect_safe "fixture_polled" (uptr uptr unsigned int uptr) int))))

  ;; A callable, the whole right-hand side of a define.
  (define on-write
    (foreign-callable __collect_safe (lambda (data size n user) (* size n)) (uptr size_t size_t uptr) size_t))

  ;; None is an occurrence: strings, and other symbols.
  (define names (list "foreign-procedure" 'foreign-procedures "bind-required" 'bind-variadics)))
