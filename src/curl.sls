#!r6rs
;;; (curl): chez-curl's low-level library, the one public (curl ...) library
;;; (ADR-0007, ADR-0010).
;;;
;;; So far it reports the libcurl it loaded, and carries chez-curl's
;;; conditions. libcurl is loaded the first time a program reaches a binding
;;; of (curl private native), loaded-libcurl: in a program that imports
;;; (curl) and calls it, before the program's own body runs. A refused
;;; libcurl raises &curl-library-unavailable there, and again at every
;;; later reference: the load runs once per process (ADR-0002, ADR-0003).
;;; The report's accessors live apart, in (curl private libcurl-info), so a
;;; refusal's report can be read after the refusal.
(library (curl)
  (export
   ;; loaded-libcurl : -> Libcurl-Info
   ;; The libcurl this process loaded and accepted.
   loaded-libcurl

   ;; libcurl-info? : Any -> Boolean
   ;; libcurl-info-path : Libcurl-Info -> String
   ;; libcurl-info-source : Libcurl-Info -> Symbol
   ;; libcurl-info-version : Libcurl-Info -> String
   ;; libcurl-info-version-number : Libcurl-Info -> Natural
   ;; libcurl-info-features : Libcurl-Info -> Natural
   ;; libcurl-info-feature-names : Libcurl-Info -> (Listof (U Symbol Positive-Integer))
   ;; libcurl-info-ssl-version : Libcurl-Info -> (U String #f)
   ;; libcurl-info-host : Libcurl-Info -> (U String #f)
   ;; What it reports: the path loaded and where it came from, then
   ;; curl_version_info's version, version_num, features (as the word and
   ;; as names), ssl_version and host. See (curl private libcurl-info).
   libcurl-info? libcurl-info-path libcurl-info-source libcurl-info-version
   libcurl-info-version-number libcurl-info-features libcurl-info-feature-names
   libcurl-info-ssl-version libcurl-info-host

   ;; &curl-error: the base of every chez-curl condition, under &error.
   ;; curl-error? : Any -> Boolean
   &curl-error curl-error?

   ;; &curl-library-unavailable: libcurl was refused.
   ;; curl-library-unavailable? : Any -> Boolean
   ;; curl-library-unavailable-reason : &curl-library-unavailable -> Symbol
   ;; curl-library-unavailable-path : &curl-library-unavailable -> (U String #f)
   ;; curl-library-unavailable-source : &curl-library-unavailable -> (U Symbol #f)
   ;; curl-library-unavailable-detail : &curl-library-unavailable -> Any
   ;; curl-library-unavailable-candidates : &curl-library-unavailable
   ;;                                       -> (Listof String)
   ;; curl-library-unavailable-library : &curl-library-unavailable
   ;;                                    -> (U Libcurl-Info #f)
   ;; curl-library-unavailable-reasons : (Listof Symbol)
   ;; See (curl private conditions) for each field and reason.
   &curl-library-unavailable curl-library-unavailable?
   curl-library-unavailable-reason curl-library-unavailable-path
   curl-library-unavailable-source curl-library-unavailable-detail
   curl-library-unavailable-candidates curl-library-unavailable-library
   curl-library-unavailable-reasons

   ;; &curl-wrong-thread: an engine-owned handle used from another thread
   ;; (ADR-0012).
   ;; curl-wrong-thread? : Any -> Boolean
   ;; curl-wrong-thread-who : &curl-wrong-thread -> Symbol
   ;; curl-wrong-thread-expected : &curl-wrong-thread -> Integer
   ;; curl-wrong-thread-actual : &curl-wrong-thread -> Integer
   &curl-wrong-thread curl-wrong-thread?
   curl-wrong-thread-who curl-wrong-thread-expected curl-wrong-thread-actual)
  (import (curl private require-threaded)
          (rnrs)
          (curl private conditions)
          (curl private libcurl-info)
          (curl private native)))
