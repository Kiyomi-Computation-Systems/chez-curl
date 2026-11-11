#!r6rs
;;; (curl private require-threaded): refuse a Chez that is not threaded, or is
;;; older than 10.4.0, by name (ADR-0001).
;;;
;;; chez-curl's engine uses Chez's thread system (make-mutex, fork-thread,
;;; ...; ADR-0012), which Chez builds only into threaded builds. On a
;;; --nothreads Chez a library importing those names dies at import with a
;;; bare "missing import for make-mutex". The floor is Chez 10.4.0 (ADR-0001):
;;; an older Chez dies somewhere in the first library that needs something
;;; newer, with a message that does not say why. This library raises a
;;; message naming the requirement instead. It raises from a macro, so the
;;; refusal comes while this library is being expanded: before the library
;;; importing it goes on to its next import.
;;;
;;; A pre-release comes before the release it is numbered for, and
;;; (scheme-version-number) answers that release's numbers for it, so
;;; 10.4.0-pre-release.N is below the floor and 10.5.0-pre-release.N is not.
;;; (scheme-version #t) ends "-pre-release.N" for one. It is asked only at the
;;; floor, where it matters, and a Chez that old takes the argument. The more
;;; direct (scheme-pre-release) is not imported: a Chez older than the floor
;;; may lack it, and a missing import is the bare message this library exists
;;; to replace.
;;;
;;; Hence its one condition: every other library under src/ imports it first
;;; among its imports. Chez processes a library's imports in order, and a
;;; thread primitive imported ahead of it still fails with the bare message
;;; (measured by chez-libuv on a --nothreads Chez 10.4.1). An
;;; (http-client ...) library may not import it (ADR-0007's seam), and
;;; imports (curl) first instead; (curl) imports this library first.
;;; tests/test-require-threaded.sps holds that order, and expands copies of
;;; this library in which (threaded?) answers #f and (scheme-version-number)
;;; and (scheme-version #t) answer versions on each side of the floor. It
;;; exports nothing.
(library (curl private require-threaded)
  (export)
  (import (rnrs)
          (only (chezscheme) threaded? scheme-version scheme-version-number))

  (define-syntax require-supported-chez
    (lambda (x)
      ;; minimum : (List Natural Natural Natural)
      ;; The oldest Chez chez-curl runs on: major, minor, patch.
      (define minimum '(10 4 0))

      ;; older? : (Listof Natural) (Listof Natural) -> Boolean
      ;; Whether the version HAVE is before the version WANT.
      (define (older? have want)
        (cond ((null? want) #f)
              ((< (car have) (car want)) #t)
              ((> (car have) (car want)) #f)
              (else (older? (cdr have) (cdr want)))))

      ;; dotted : (Listof Natural) -> String
      (define (dotted version)
        (let loop ((rest (cdr version)) (text (number->string (car version))))
          (if (null? rest)
              text
              (loop (cdr rest)
                    (string-append text "." (number->string (car rest)))))))

      ;; pre-release-suffix : String -> (U String #f)
      ;; The "-pre-release.N" ending the version text of a pre-release Chez,
      ;; wherever it comes in TEXT; #f for a release.
      (define (pre-release-suffix text)
        (let ((tag "-pre-release."))
          (let loop ((i 0))
            (cond ((> (+ i (string-length tag)) (string-length text)) #f)
                  ((string=? (substring text i (+ i (string-length tag))) tag)
                   (substring text i (string-length text)))
                  (else (loop (+ i 1)))))))

      (let-values (((major minor patch) (scheme-version-number)))
        (let* ((have (list major minor patch))
               ;; "-pre-release.N" when this Chez is a pre-release of the
               ;; floor itself, else #f. Asked only at the floor.
               (pre (and (equal? have minimum)
                         (pre-release-suffix (scheme-version #t)))))
          (cond
           ((not (threaded?))
            (syntax-violation
             'chez-curl
             "chez-curl needs a threaded Chez Scheme, and (threaded?) is #f in this one. Chez builds threaded unless configured with --nothreads"
             x))
           ((or (older? have minimum) pre)
            (syntax-violation
             'chez-curl
             (string-append "chez-curl needs Chez Scheme " (dotted minimum)
                            " or later, and this one is " (dotted have) (or pre ""))
             x))
           (else #'(define supported-chez-checked #t)))))))

  (require-supported-chez))
