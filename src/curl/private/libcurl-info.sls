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
    (fields path source version version-number features feature-names
            ssl-version host)
    (sealed #t)
    (opaque #t)))
