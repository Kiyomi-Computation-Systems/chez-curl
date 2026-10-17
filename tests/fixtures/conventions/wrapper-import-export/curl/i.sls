#!r6rs
;; Imports that name a known wrapper: only, rename, except, prefix, for,
;; (only (chezscheme) ...), which accounts for foreign-procedure alone, and
;; an import as a body form. Each is stray. A rename puts the name at a
;; head, where code would read a use.
(library (curl i)
  (export)
  (import (rnrs)
          (only (curl e) bind-required)
          (rename (curl e) (bind-required b) (bind-v bind-variadic))
          (except (curl e) bind-required)
          (prefix (only (curl e) bind-required) e:)
          (for (only (curl e) bind-variadic) run)
          (only (chezscheme) foreign-procedure bind-variadic import))

  (import (rename (curl e) (bind-required c))))
