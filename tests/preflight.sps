#!r6rs
;;; tests/preflight.sps: what `make build` runs. chez-curl compiles nothing
;;; (ADR-0001), so build answers the question an install raises instead:
;;; which libcurl would (curl) load here, and does chez-curl accept it?
;;;
;;; Accepted: it prints the path and its source, the version, the TLS
;;; backend, the feature names and the host, on stdout, and exits 0.
;;; Refused: it prints (reason . SYMBOL), then the path, the source, the
;;; detail, the version, TLS backend and features when the refusal came
;;; after the library said what it is, every candidate checked and a
;;; one-line remedy, on stderr, and exits 1. The reason is the contract;
;;; the rest is for the reader (ADR-0002). Anything else raised is a bug,
;;; not a refusal, and is left to Chez's default handler. The report's
;;; accessors live in (curl private libcurl-info), so reading a refusal's
;;; report never runs the load again.
;;;
;;; Like tests/refusal-probe.sps, it does not import (curl): Chez would
;;; invoke (curl)'s body, which loads libcurl, before this program's guard
;;; could catch a refusal (measured; see that file). It evaluates
;;; (loaded-libcurl) in (environment '(rnrs) '(curl)) inside the guard
;;; instead.
(import (rnrs)
        (only (chezscheme) eval environment)
        (curl private conditions))

;; say : Output-Port Any ... -> Void
;; PARTS displayed, then a newline.
(define (say port . parts)
  (for-each (lambda (part) (display part port)) parts)
  (newline port))

;; words : (Listof Any) -> String
;; Each displayed, one space between.
(define (words items)
  (call-with-string-output-port
   (lambda (p)
     (let loop ((items items) (first? #t))
       (unless (null? items)
         (unless first? (put-char p #\space))
         (display (car items) p)
         (loop (cdr items) #f))))))

(define (or-none value) (or value "none"))

(guard (e ((curl-library-unavailable? e)
           (let ((err (current-error-port))
                 (candidates (curl-library-unavailable-candidates e)))
             (say err "chez-curl: libcurl refused")
             (write (cons 'reason (curl-library-unavailable-reason e)) err)
             (newline err)
             (say err "  path:       " (or-none (curl-library-unavailable-path e)))
             (say err "  source:     " (or-none (curl-library-unavailable-source e)))
             (say err "  detail:     " (or-none (curl-library-unavailable-detail e)))
             (let ((library (curl-library-unavailable-library e)))
               (when library
                 (let ((report ((eval '(lambda (info)
                                         (list (libcurl-info-version info)
                                               (libcurl-info-ssl-version info)
                                               (libcurl-info-feature-names info)))
                                       (environment '(rnrs) '(curl)))
                                library)))
                   (say err "  version:    " (list-ref report 0))
                   (say err "  TLS:        " (or-none (list-ref report 1)))
                   (say err "  features:   " (words (list-ref report 2))))))
             (if (null? candidates)
                 (say err "  candidates: none")
                 (begin
                   (say err "  candidates:")
                   (for-each (lambda (path) (say err "    " path)) candidates)))
             (say err "  remedy:     " (if (message-condition? e)
                                            (condition-message e)
                                            "name a usable libcurl with CHEZ_CURL_LIBCURL, an absolute path"))
             (exit 1))))
  (let ((report (eval '(let ((info (loaded-libcurl)))
                         (list (libcurl-info-path info)
                               (libcurl-info-source info)
                               (libcurl-info-version info)
                               (libcurl-info-ssl-version info)
                               (libcurl-info-feature-names info)
                               (libcurl-info-host info)))
                      (environment '(rnrs) '(curl))))
        (out (current-output-port)))
    (say out "chez-curl: libcurl loaded and accepted")
    (say out "  path:     " (list-ref report 0) " (" (list-ref report 1) ")")
    (say out "  version:  " (list-ref report 2))
    (say out "  TLS:      " (or-none (list-ref report 3)))
    (say out "  features: " (words (list-ref report 4)))
    (say out "  host:     " (or-none (list-ref report 5)))
    (exit 0)))
