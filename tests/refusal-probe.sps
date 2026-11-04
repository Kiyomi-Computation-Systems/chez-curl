#!r6rs
;;; tests/refusal-probe.sps: loads libcurl as (curl) does, in a process of
;;; its own, and prints what happened as data, one datum per line, for
;;; tests/test-library-loading.sps to read. It is not a suite: its name lies
;;; outside the tests/test-*.sps glob, so make test never runs it directly.
;;;
;;;   refusal-probe.sps [--then-override PATH] [--marker NAME] [--backend yes]
;;;
;;; It references loaded-libcurl three times, each inside its guard. The
;;; first reference prints what happened:
;;;
;;;   loaded:   (loaded . PATH) (source . SYMBOL) (version . STRING)
;;;             (version-num . N) (features . N) (ssl-version . STRING-OR-#F)
;;;             (host . STRING-OR-#F), what tests/libcurl-oracle.c prints,
;;;             after the path and source; then (protocols . LIST), (curl
;;;             private native)'s loaded-protocols, what the oracle prints
;;;             with protocols; and the exit status is 0
;;;   refused:  (reason . SYMBOL) (path . P) (source . S) (detail . D)
;;;             (candidates . LIST) (library . L), and the exit status is
;;;             1. L is #f, or the report read before the refusal: its
;;;             path, source and the five fields, as a list
;;;   anything else raised: (raised . TEXT), and the exit status is 2
;;;
;;; With --then-override, CHEZ_CURL_LIBCURL is set to PATH after the first
;;; reference, and (then-override . VALUE) shows what getenv then reads.
;;; The two later references print one line, (again . (A B)).
;;; Each is `same` when the reference returned or raised the very object
;;; the first one did (eq?), else (loaded PATH), (refused REASON) or
;;; (raised TEXT). A load that ran once answers `same` twice; a load that
;;; ran again answers a fresh object.
;;;
;;; Then (counts . ALIST): (curl private counters)' native-counts, read once
;;; the three references are done. The counters gate counts per process, and
;;; a suite's suite-exit-status reads only its own, so this process reports
;;; its counts, and tests/test-library-loading.sps requires every one zero,
;;; refusals included: a native object a refused load left behind shows here
;;; and nowhere else.
;;;
;;; With --backend, (backend . NAME-OR-#F) follows the counts: (curl private
;;; native)'s loaded-tls-backend, the TLS backend in use as libcurl named it
;;; after curl_global_init; then (features-after . WORD), its
;;; loaded-features, the features word libcurl then reported.
;;;
;;; With --marker, (marker . present) or (marker . absent) follows: whether
;;; this process has the entry point NAME, as foreign-entry? answers.
;;; Last comes (calls . LOG) when the most recently loaded library has the
;;; entry point decoy_calls, as tests/decoy-libcurl.c does: its call log.
;;;
;;; Why eval, and no import of (curl). Measured on Chez 10.4.0 (the
;;; mutation log's native-layer part): Chez invokes the libraries a program
;;; imports before the program's body starts, so a guard in the body never
;;; sees a raise from an imported library's body, and the program dies in
;;; Chez's default handler with exit 255. (curl)'s body loads libcurl. So
;;; this program evaluates (loaded-libcurl) in (environment '(rnrs) '(curl))
;;; inside the guard, and the load runs within it. (curl private conditions)
;;; loads nothing, so importing it is safe.
(import (rnrs)
        (only (chezscheme) eval environment foreign-entry? foreign-procedure
              display-condition putenv getenv)
        (curl private conditions)
        (curl private counters))

;; show : Symbol Any -> Void
;; One datum, (KEY . VALUE), on a line of its own.
(define (show key value)
  (write (cons key value))
  (newline))

;; text : Any -> String
(define (text obj)
  (call-with-string-output-port
   (lambda (p) (if (condition? obj) (display-condition obj p) (write obj p)))))

;; option : String -> (U String #f)
;; The argument after NAME on the command line, or #f.
(define (option name)
  (let loop ((args (cdr (command-line))))
    (cond ((or (null? args) (null? (cdr args))) #f)
          ((string=? (car args) name) (cadr args))
          (else (loop (cdr args))))))

;; reference : -> (Pairof Symbol Any)
;; One reference to loaded-libcurl: (loaded . INFO), (refused . CONDITION)
;; or (raised . OBJECT).
(define (reference)
  (guard (e ((curl-library-unavailable? e) (cons 'refused e))
            (#t (cons 'raised e)))
    (cons 'loaded (eval '(loaded-libcurl) (environment '(rnrs) '(curl))))))

;; info-fields : Libcurl-Info -> (List String Symbol String Natural Natural
;;                                    (U String #f) (U String #f))
;; Read through (curl)'s own accessors.
(define (info-fields info)
  ((eval '(lambda (info)
            (list (libcurl-info-path info)
                  (libcurl-info-source info)
                  (libcurl-info-version info)
                  (libcurl-info-version-number info)
                  (libcurl-info-features info)
                  (libcurl-info-ssl-version info)
                  (libcurl-info-host info)))
         (environment '(rnrs) '(curl)))
   info))

;; later : (Pairof Symbol Any) (Pairof Symbol Any) -> Any
;; What a later reference did, against the first.
(define (later first answer)
  (cond ((eq? (cdr answer) (cdr first)) 'same)
        ((eq? (car answer) 'loaded) (list 'loaded (car (info-fields (cdr answer)))))
        ((eq? (car answer) 'refused)
         (list 'refused (curl-library-unavailable-reason (cdr answer))))
        (else (list 'raised (text (cdr answer))))))

(define first (reference))

(define status
  (case (car first)
    ((loaded)
     (let ((fields (info-fields (cdr first))))
       (show 'loaded (list-ref fields 0))
       (show 'source (list-ref fields 1))
       (show 'version (list-ref fields 2))
       (show 'version-num (list-ref fields 3))
       (show 'features (list-ref fields 4))
       (show 'ssl-version (list-ref fields 5))
       (show 'host (list-ref fields 6))
       (show 'protocols (eval '(loaded-protocols) (environment '(curl private native))))
       0))
    ((refused)
     (let ((e (cdr first)))
       (show 'reason (curl-library-unavailable-reason e))
       (show 'path (curl-library-unavailable-path e))
       (show 'source (curl-library-unavailable-source e))
       (show 'detail (curl-library-unavailable-detail e))
       (show 'candidates (curl-library-unavailable-candidates e))
       (show 'library (let ((library (curl-library-unavailable-library e)))
                        (and library (info-fields library))))
       1))
    (else
     (show 'raised (text (cdr first)))
     2)))

(let ((path (option "--then-override")))
  (when path
    (putenv "CHEZ_CURL_LIBCURL" path)
    (show 'then-override (getenv "CHEZ_CURL_LIBCURL"))))

(let* ((second (reference))
       (third (reference)))
  (show 'again (list (later first second) (later first third))))

(show 'counts (native-counts))

(when (option "--backend")
  (show 'backend (guard (e (#t (list 'raised (text e))))
                   (eval '(loaded-tls-backend) (environment '(curl private native)))))
  (show 'features-after (guard (e (#t (list 'raised (text e))))
                          (eval '(loaded-features) (environment '(curl private native))))))

(let ((marker (option "--marker")))
  (when marker
    (show 'marker (if (foreign-entry? marker) 'present 'absent))))

(when (foreign-entry? "decoy_calls")
  (show 'calls ((foreign-procedure "decoy_calls" () string))))

(exit status)
