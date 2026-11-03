#!r6rs
;;; (curl private libcurl-info): what a loaded libcurl reports about itself
;;; (ADR-0002, decision 4). (curl private native) builds one when it has
;;; read curl_version_info. loaded-libcurl answers it, and every refusal
;;; made after that read carries it, as &curl-library-unavailable's library.
;;;
;;; It is a library of its own because a refusal's report must be readable
;;; after the refusal. Reading an accessor runs the library that defines
;;; it, and native's body raises its refusal again at every reference. This
;;; library's body defines a record type only, so it cannot raise.
(library (curl private libcurl-info)
  (export make-libcurl-info libcurl-info?
          libcurl-info-path libcurl-info-source libcurl-info-version
          libcurl-info-version-number libcurl-info-features
          libcurl-info-feature-names libcurl-info-ssl-version libcurl-info-host)
  (import (curl private require-threaded)
          (rnrs))

  ;; make-libcurl-info : String Symbol String Natural Natural
  ;;                     (Listof (U Symbol Positive-Integer)) (U String #f)
  ;;                     (U String #f) -> Libcurl-Info
  ;; libcurl-info? : Any -> Boolean
  ;; libcurl-info-path : Libcurl-Info -> String
  ;;   the path loaded, absolute
  ;; libcurl-info-source : Libcurl-Info -> Symbol
  ;;   where the path came from: one of (curl private discovery)'s
  ;;   libcurl-sources
  ;; libcurl-info-version : Libcurl-Info -> String
  ;;   curl_version_info_data's version, "8.20.0"; a NULL one is refused
  ;; libcurl-info-version-number : Libcurl-Info -> Natural
  ;;   its version_num, #xMMmmpp
  ;; libcurl-info-features : Libcurl-Info -> Natural
  ;;   its features word, CURL_VERSION_* bits
  ;; libcurl-info-feature-names : Libcurl-Info -> (Listof (U Symbol Positive-Integer))
  ;;   that word as names: (curl private verify)'s feature-names
  ;; libcurl-info-ssl-version : Libcurl-Info -> (U String #f)
  ;;   its ssl_version, the TLS backend, "GnuTLS/3.8.13"; #f when NULL
  ;; libcurl-info-host : Libcurl-Info -> (U String #f)
  ;;   its host, "x86_64-unknown-linux-gnu"; #f when NULL
  ;; Opaque, so that record-rtd on a report raises. Its type, once read, builds
  ;; a report holding any path, version and features, which libcurl-info?
  ;; and the accessors then take for a genuine one.
  (define-record-type libcurl-info
    (fields (immutable path unchecked-libcurl-info-path)
            (immutable source unchecked-libcurl-info-source)
            (immutable version unchecked-libcurl-info-version)
            (immutable version-number unchecked-libcurl-info-version-number)
            (immutable features unchecked-libcurl-info-features)
            (immutable feature-names unchecked-libcurl-info-feature-names)
            (immutable ssl-version unchecked-libcurl-info-ssl-version)
            (immutable host unchecked-libcurl-info-host))
    (sealed #t)
    (opaque #t))

  ;; shown : Any -> Any
  ;; X as an accessor's refusal names it: (curl private conditions)'
  ;; shown-value's rule, which this library cannot import, since that one
  ;; imports this: a symbol, a number, a boolean, a char, (), or a proper
  ;; list of them, as itself; anything else (kind K), never the value.
  ;; tests/test-printed.sps holds the two alike. Pure.
  (define (shown x)
    (define (atom? y) (or (symbol? y) (number? y) (boolean? y) (char? y) (null? y)))
    (cond ((or (atom? x) (and (list? x) (for-all atom? x))) x)
          ((string? x) '(kind string))
          ((pair? x) '(kind list))
          ((bytevector? x) '(kind bytevector))
          ((vector? x) '(kind vector))
          ((procedure? x) '(kind procedure))
          (else '(kind other))))

  ;; checked : Symbol (Any -> Any) -> (Any -> Any)
  ;; ACCESSOR for WHO, called on a report alone; anything else an assertion
  ;; violation from WHO naming it by shown, never the value: Chez's own check
  ;; printed what it refused (ADR-0036, amended 2026-11-03). A procedure is
  ;; all this makes, so the body still cannot raise.
  (define (checked who accessor)
    (lambda (x)
      (unless (libcurl-info? x)
        (assertion-violation who "not a libcurl-info" (shown x)))
      (accessor x)))

  (define libcurl-info-path (checked 'libcurl-info-path unchecked-libcurl-info-path))
  (define libcurl-info-source (checked 'libcurl-info-source unchecked-libcurl-info-source))
  (define libcurl-info-version (checked 'libcurl-info-version unchecked-libcurl-info-version))
  (define libcurl-info-version-number
    (checked 'libcurl-info-version-number unchecked-libcurl-info-version-number))
  (define libcurl-info-features (checked 'libcurl-info-features unchecked-libcurl-info-features))
  (define libcurl-info-feature-names
    (checked 'libcurl-info-feature-names unchecked-libcurl-info-feature-names))
  (define libcurl-info-ssl-version (checked 'libcurl-info-ssl-version unchecked-libcurl-info-ssl-version))
  (define libcurl-info-host (checked 'libcurl-info-host unchecked-libcurl-info-host)))
