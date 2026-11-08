;; inventory-check.sps: reads inventory.sexp with read, and reports its count,
;; the names in it against library-exports, and entries with no signature.
(import (chezscheme))
(define entries
  (call-with-input-file ".plans/research/m8/slice4/inventory.sexp"
    (lambda (p) (let loop ((acc '())) (let ((x (read p))) (if (eof-object? x) (reverse acc) (loop (cons x acc))))))))
(define (field e k) (let ((hit (assq k (cddr e)))) (and hit (cdr hit))))
(eval '(import (curl) (curl unsupported) (http-client)))
(define exported
  (apply append (map (lambda (lib) (map (lambda (n) (cons lib n)) (library-exports lib)))
                     '((curl) (curl unsupported) (http-client)))))
(define listed (map (lambda (e) (cons (car (field e 'library)) (cadr e))) entries))
(printf "entries ~s exports ~s\n" (length entries) (length exported))
(printf "missing ~s\n" (filter (lambda (x) (not (member x listed))) exported))
(printf "extra ~s\n" (filter (lambda (x) (not (member x exported))) listed))
(printf "no signature ~s\n" (map cadr (filter (lambda (e) (null? (car (field e 'signature)))) entries)))
(printf "kinds ~s\n" (let loop ((es entries) (acc '()))
  (if (null? es) acc
      (let* ((k (car (field (car es) 'kind))) (hit (assq k acc)))
        (if hit (begin (set-cdr! hit (+ (cdr hit) 1)) (loop (cdr es) acc))
            (loop (cdr es) (cons (cons k 1) acc)))))))
(printf "with cites ~s\n" (length (filter (lambda (e) (pair? (car (field e 'cites)))) entries)))
