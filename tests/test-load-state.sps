#!r6rs
;;; The suite for (curl private load-state): the load's first failure, kept
;;; for the life of the process, and load-step, which records it.
;;;
;;; The state is the process's own, so the tests run in order and build on
;;; each other: nothing recorded, then a first failure, then later ones that
;;; must not replace it.
;;;
;;; Each expected value is one the code under test cannot produce by
;;; failing, and none is #f: SRFI-64 makes #f of a raise in the actual
;;; expression.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) eval environment interaction-environment)
        (curl-testing)
        (curl private load-state))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; caught : (-> Any) -> Any
;; What THUNK raised, or the symbol no-raise.
(define (caught thunk)
  (guard (e (#t e))
    (thunk)
    'no-raise))

(define (recorded) (if (load-failure) 'recorded 'none))

;; made-serious : Any -> Any
;; For a condition as-serious made of something else: whether it is
;; serious and an error, its who, and its irritants.
(define (made-serious c)
  (if (condition? c)
      (list (serious-condition? c) (error? c)
            (and (who-condition? c) (condition-who c))
            (and (irritants-condition? c) (condition-irritants c)))
      (list 'not-a-condition c)))

(test-begin "load-state")

(test-equal "nothing is recorded at first"
  'none
  (recorded))

(test-equal "load-step answers its expression's value, and records nothing"
  '(42 none)
  (let ((value (load-step (+ 40 2))))
    (list value (recorded))))

;; --- as-serious --------------------------------------------------------------------

(test-equal "as-serious answers a serious condition itself"
  '(same same same same)
  (map (lambda (c) (if (eq? (as-serious c) c) 'same 'different))
       (list (make-serious-condition) (make-error) (make-assertion-violation)
             (condition (make-error) (make-message-condition "refused")))))

(test-equal "as-serious makes a symbol or a number an error from chez-curl, carrying it"
  '((#t #t chez-curl (boom)) (#t #t chez-curl (42)))
  (map (lambda (obj) (made-serious (as-serious obj))) '(boom 42)))

(test-equal "as-serious makes a warning or a bare message an error, carrying it"
  '(carried carried)
  (map (lambda (c)
         (let ((made (as-serious c)))
           (if (and (serious-condition? made) (irritants-condition? made)
                    (equal? (condition-irritants made) (list c)))
               'carried
               (made-serious made))))
       (list (make-warning) (make-message-condition "not serious"))))

;; --- recording -------------------------------------------------------------------

;; first : Any
;; What load-step raised for a symbol: the load's first failure from here on.
(define first (caught (lambda () (load-step (raise 'boom)))))

(test-equal "load-step raises a symbol made serious, carrying it"
  '(#t #t chez-curl (boom))
  (made-serious first))

(test-equal "load-step records what it raised"
  'recorded-what-was-raised
  (if (eq? (load-failure) first) 'recorded-what-was-raised (recorded)))

(test-equal "a later load-step raises its own serious condition, unchanged, and the first stays recorded"
  '(raised-itself first-kept)
  (let* ((later (make-error))
         (raised (caught (lambda () (load-step (raise later))))))
    (list (if (eq? raised later) 'raised-itself 'raised-something-else)
          (if (eq? (load-failure) first) 'first-kept 'replaced))))

(test-equal "record-load-failure! keeps the first failure"
  'first-kept
  (begin
    (record-load-failure! (make-error))
    (if (eq? (load-failure) first) 'first-kept 'replaced)))

(test-equal "record-load-failure! refuses a condition that is not serious"
  'refused
  (let ((raised (caught (lambda () (record-load-failure! (make-warning))))))
    (if (and (assertion-violation? raised) (who-condition? raised)
             (eq? (condition-who raised) 'record-load-failure!))
        'refused
        (if (condition? raised) (describe raised) raised))))

;; --- a library body that raises -----------------------------------------------------
;; Chez runs a library body that raised a serious condition again at the
;; next reference, and wedges one that raised anything else: every later
;; reference raises "cyclic dependency involving invocation of library".
;; Each library below is defined here with eval, and referenced twice.

(define (string-prefix? prefix s)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; reference : (Listof Symbol) -> Any
;; What a reference to the library NAME's export v did.
(define (reference name)
  (guard (e ((and (message-condition? e)
                  (string-prefix? "cyclic dependency" (condition-message e)))
             'wedged)
            ((and (serious-condition? e) (irritants-condition? e)
                  (equal? (condition-irritants e) '(boom)))
             'raised-serious)
            ((symbol? e) (list 'raised e))
            (#t (list 'other (describe e))))
    (eval 'v (environment name))
    'no-raise))

;; twice : (Listof Symbol) Any -> (List Any Any)
;; Defines the library NAME, whose one definition is v, as BODY, then
;; references it twice.
(define (twice name body)
  (eval `(library ,name
           (export v)
           (import (rnrs) (curl private load-state))
           (define v ,body))
        (interaction-environment))
  (let* ((one (reference name))
         (two (reference name)))
    (list one two)))

(test-equal "Chez wedges a library whose body raised a symbol (the reason for load-step)"
  '((raised boom) wedged)
  (twice '(load-state-fixture bare) '(raise 'boom)))

(test-equal "through load-step, the same raise is serious, so the body runs again, never wedged"
  '(raised-serious raised-serious)
  (twice '(load-state-fixture stepped) '(load-step (raise 'boom))))

(test-end "load-state")

(exit (suite-exit-status runner))
