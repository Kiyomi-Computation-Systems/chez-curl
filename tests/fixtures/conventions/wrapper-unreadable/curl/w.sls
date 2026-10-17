#!r6rs
;; Known wrappers the reader cannot read. The suite names each of these as a
;; known wrapper for this tree alone.
(library (curl w)
  (export)
  (import (rnrs) (only (chezscheme) foreign-procedure))

  ;; syntax-case, not syntax-rules
  (define-syntax w-syntax-case
    (lambda (x)
      (syntax-case x ()
        ((_ e) #'(foreign-procedure e () int)))))

  ;; two clauses
  (define-syntax w-two-clauses
    (syntax-rules ()
      ((_ e) (foreign-procedure e () long))
      ((_) #f)))

  ;; no foreign-procedure in the template
  (define-syntax w-no-binding
    (syntax-rules ()
      ((_ e) (list e))))

  ;; two foreign-procedure forms in the template
  (define-syntax w-two-bindings
    (syntax-rules ()
      ((_ e) (list (foreign-procedure e () short) (foreign-procedure e () double)))))

  ;; the entry nested in the pattern
  (define-syntax w-nested-entry
    (syntax-rules ()
      ((_ (e) result) (foreign-procedure e () result))))

  ;; an ellipsis before the entry, so its place in a use is unknown
  (define-syntax w-ellipsis-first
    (syntax-rules ()
      ((_ arg ... e) (foreign-procedure e (arg ...) int))))

  ;; the entry is no pattern variable
  (define-syntax w-entry-literal
    (syntax-rules ()
      ((_) (foreign-procedure "curl_easy_init" () uptr))))

  ;; a foreign-procedure form too short to read
  (define-syntax w-malformed
    (syntax-rules ()
      ((_ e) (foreign-procedure e))))

  ;; the entry is a literal, which a use must spell e, not a pattern variable
  (define-syntax w-literal-entry
    (syntax-rules (e)
      ((_ e) (foreign-procedure e () int))))

  ;; a parameter list that mixes a type and a pattern variable
  (define-syntax w-mixed-parameters
    (syntax-rules ()
      ((_ e arg ...) (foreign-procedure e (uptr arg ...) int))))

  ;; a parameter list with no pattern variable, that is no list of types
  (define-syntax w-literal-parameters
    (syntax-rules ()
      ((_ e) (foreign-procedure e ("u8*") int))))

  ;; the result a pattern variable nested in the pattern, so its place in a
  ;; use is unknown
  (define-syntax w-nested-result
    (syntax-rules ()
      ((_ e (r)) (foreign-procedure e () r))))

  ;; a result that holds a pattern variable, and is not one
  (define-syntax w-pointer-result
    (syntax-rules ()
      ((_ e r) (foreign-procedure e () (* r))))))
