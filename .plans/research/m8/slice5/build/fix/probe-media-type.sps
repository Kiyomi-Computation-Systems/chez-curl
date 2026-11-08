#!r6rs
;;; probe-media-type.sps: examples/json-api.sps's media-type, read from the
;;; example's own text and evaluated, on Content-Type values the route never
;;; sends. Run from the repository's root:
;;;   $CHEZ --libdirs src --program .plans/research/m8/slice5/build/fix/probe-media-type.sps
(import (rnrs) (rnrs eval))

(define definition
  (call-with-input-file "examples/json-api.sps"
    (lambda (port)
      (let loop ()
        (let ((d (read port)))
          (cond ((eof-object? d) (error 'probe "no media-type in the example"))
                ((and (pair? d) (eq? (car d) 'define) (pair? (cadr d)) (eq? (caadr d) 'media-type)) d)
                (else (loop))))))))

;; The definition as a lambda: R6RS's eval takes no definition.
(define media-type
  (eval (cons 'lambda (cons (cdadr definition) (cddr definition))) (environment '(rnrs))))

(for-each
 (lambda (v) (write (list v (media-type v))) (newline))
 '("application/json" "application/json; charset=utf-8" " Application/JSON\t;charset=UTF-8"
   "APPLICATION/JSON" "application/json-seq" "text/html" "" ";" "application/ json"))
