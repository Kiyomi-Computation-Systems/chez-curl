#!r6rs
;; A known wrapper's name in a macro: its templates, patterns and literals,
;; where the macro, not the reader, decides what the name becomes. Each is
;; stray, a head with a literal entry too:
;;   - rebind's syntax-case takes its own template apart: the reader would
;;     read memcpy, and Chez binds curl_easy_setopt;
;;   - via's template hands a use to k, which via's own use names, quote
;;     or a macro that takes the use apart;
;;   - named, built and held make syntax objects: with-syntax in a
;;     syntax-case, and quasisyntax and syntax in plain procedures;
;;   - at-expand and local are transformers, by define-syntax and
;;     let-syntax, whose bodies are no template;
;;   - on-set is identifier-syntax's set! clause;
;;   - literal names the wrapper as a literal and in its pattern;
;;   - each known wrapper is defined through the other, so neither binds
;;     anything the reader can read: bind-variadic's syntax-rules template,
;;     and bind-required's transformer, a lambda whose body is no template.
(library (curl t)
  (export)
  (import (rnrs))

  (define-syntax bind-easy
    (syntax-rules ()
      ((_) (bind-required "curl_easy_init" () uptr #f))))

  (define-syntax via
    (syntax-rules ()
      ((_ k) (k (bind-variadic "curl_easy_setopt" (uptr int long) int #f)))))

  (define-syntax rebind
    (lambda (x)
      (syntax-case #'(bind-required "memcpy" (uptr int long) int #f) ()
        ((w e . rest) #'(w "curl_easy_setopt" . rest)))))

  (define-syntax named
    (lambda (x)
      (syntax-case x ()
        ((_) (with-syntax ((b #'bind-required)) #'(b "curl_easy_init" () uptr #f))))))

  (define (built) #`(bind-variadic "curl_easy_getinfo" (uptr int uptr) int #f))

  (define (held) #'(bind-variadic "curl_easy_setopt" (uptr int long) int #f))

  (define-syntax at-expand
    (lambda (x)
      (bind-required "curl_easy_init" () uptr #f)))

  (define local
    (let-syntax ((m (lambda (x) (bind-required "curl_global_init" (long) int #f))))
      0))

  (define-syntax on-set
    (identifier-syntax
      (id 0)
      ((set! id e) (bind-required "curl_easy_init" () uptr #f))))

  (define-syntax literal
    (syntax-rules (bind-required)
      ((_ bind-required) 0)))

  (define-syntax bind-variadic
    (syntax-rules ()
      ((_ entry (arg ...) result library)
       (bind-required entry (arg ...) result library))))

  (define-syntax bind-required
    (lambda (x)
      (bind-variadic "curl_easy_init" () uptr #f))))
