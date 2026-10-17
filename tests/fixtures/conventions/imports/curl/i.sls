#!r6rs
;; Only an (only (chezscheme) name ...) import accounts for the names: an
;; export, another import set, and an only nested in a prefix do not.
(library (curl i)
  (export foreign-procedure)
  (import (rnrs)
          (only (chezscheme) foreign-procedure foreign-callable)
          (except (chezscheme) foreign-callable)
          (only (scheme) foreign-procedure)
          (prefix (only (chezscheme) foreign-procedure) c:)))
