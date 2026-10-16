#!r6rs
;;; (curl private conditions): chez-curl's condition types. Every one is a
;;; &curl-error, so a caller can catch the family or one member.
;;;
;;;   &curl-error                 the base, under &error
;;;   &curl-library-unavailable   libcurl was refused (ADR-0002, ADR-0003)
;;;   &curl-wrong-thread          an engine-owned handle used from another
;;;                               thread (ADR-0012)
;;;
;;; A raise may compound one with &who, &message and &irritants, so that
;;; the default handler prints readable text. Tests assert the reason symbol
;;; and the fields, never that text.
(library (curl private conditions)
  (export &curl-error make-curl-error curl-error?

          &curl-library-unavailable make-curl-library-unavailable
          curl-library-unavailable?
          curl-library-unavailable-reason curl-library-unavailable-path
          curl-library-unavailable-source curl-library-unavailable-detail
          curl-library-unavailable-candidates
          curl-library-unavailable-library
          curl-library-unavailable-reasons

          &curl-wrong-thread make-curl-wrong-thread curl-wrong-thread?
          curl-wrong-thread-who curl-wrong-thread-expected
          curl-wrong-thread-actual)
  (import (curl private require-threaded)
          (rnrs)
          (curl private libcurl-info))

  ;; make-curl-error : -> &curl-error
  ;; curl-error? : Any -> Boolean
  (define-condition-type &curl-error &error
    make-curl-error curl-error?)

  ;; --- &curl-library-unavailable ---------------------------------------------

  ;; curl-library-unavailable-reasons : (Listof Symbol)
  ;; Why a libcurl was refused. They are the contract: tests and CI assert
  ;; these symbols, never the message (ADR-0002, ADR-0003).
  ;;
  ;;   invalid-override  CHEZ_CURL_LIBCURL is set, but not to an absolute path
  ;;   not-found         no candidate exists
  ;;   load-failed       the loader refused the chosen path
  ;;   below-floor       the library is older than 7.85.0
  ;;   no-ssl            the library lacks CURL_VERSION_SSL
  ;;   missing-api       the options API or the header API is built out
  (define curl-library-unavailable-reasons
    '(invalid-override not-found load-failed below-floor no-ssl missing-api))

  ;; The fields:
  ;;
  ;;   reason      one of curl-library-unavailable-reasons
  ;;   path        (U String #f): the library refused, #f when none was chosen
  ;;   source      (U Symbol #f): where the path came from, one of
  ;;               (curl private discovery)'s libcurl-sources, or #f
  ;;   detail      by reason: the override's value (invalid-override), the
  ;;               loader's message (load-failed), the version string
  ;;               (below-floor, no-ssl), the API's C name (missing-api),
  ;;               #f (not-found)
  ;;   candidates  (Listof String): every path checked, in order (not-found)
  ;;   library     (U Libcurl-Info #f): what the library reported, for a
  ;;               refusal made after curl_version_info was read
  ;;               (below-floor, no-ssl, missing-api for any entry point
  ;;               but curl_version_info, and load-failed from
  ;;               curl_global_init or curl_easy_init); #f before that
  ;;               (ADR-0002, decision 4)
  (define-condition-type &curl-library-unavailable &curl-error
    unchecked-make-curl-library-unavailable curl-library-unavailable?
    (reason curl-library-unavailable-reason)
    (path curl-library-unavailable-path)
    (source curl-library-unavailable-source)
    (detail curl-library-unavailable-detail)
    (candidates curl-library-unavailable-candidates)
    (library curl-library-unavailable-library))

  ;; make-curl-library-unavailable : Symbol (U String #f) (U Symbol #f) Any
  ;;                                 (Listof String) (U Libcurl-Info #f)
  ;;                                 -> &curl-library-unavailable
  ;; Refuses a REASON that is not one of the six, and a LIBRARY that is
  ;; neither a libcurl-info nor #f, with an assertion violation, so a
  ;; misspelt reason cannot reach a caller who tests for the right one.
  (define (make-curl-library-unavailable reason path source detail candidates library)
    (unless (memq reason curl-library-unavailable-reasons)
      (assertion-violation 'make-curl-library-unavailable
                           "not a reason chez-curl refuses a libcurl for"
                           reason))
    (unless (or (not library) (libcurl-info? library))
      (assertion-violation 'make-curl-library-unavailable
                           "a refusal's library is a libcurl-info or #f"
                           library))
    (unchecked-make-curl-library-unavailable reason path source detail candidates
                                             library))

  ;; curl-library-unavailable? : Any -> Boolean
  ;; curl-library-unavailable-reason : &curl-library-unavailable -> Symbol
  ;; curl-library-unavailable-path : &curl-library-unavailable -> (U String #f)
  ;; curl-library-unavailable-source : &curl-library-unavailable -> (U Symbol #f)
  ;; curl-library-unavailable-detail : &curl-library-unavailable -> Any
  ;; curl-library-unavailable-candidates : &curl-library-unavailable
  ;;                                       -> (Listof String)
  ;; curl-library-unavailable-library : &curl-library-unavailable
  ;;                                    -> (U Libcurl-Info #f)

  ;; --- &curl-wrong-thread ----------------------------------------------------

  ;; make-curl-wrong-thread : Symbol Integer Integer -> &curl-wrong-thread
  ;; curl-wrong-thread? : Any -> Boolean
  ;; curl-wrong-thread-who : &curl-wrong-thread -> Symbol
  ;; curl-wrong-thread-expected : &curl-wrong-thread -> Integer
  ;; curl-wrong-thread-actual : &curl-wrong-thread -> Integer
  ;; An operation on an engine-owned handle ran on another thread: WHO is the
  ;; operation, EXPECTED the owner's get-thread-id, ACTUAL the caller's
  ;; (ADR-0012).
  (define-condition-type &curl-wrong-thread &curl-error
    make-curl-wrong-thread curl-wrong-thread?
    (who curl-wrong-thread-who)
    (expected curl-wrong-thread-expected)
    (actual curl-wrong-thread-actual)))
