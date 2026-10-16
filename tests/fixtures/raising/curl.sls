#!r6rs
;;; tests/fixtures/raising/curl.sls: a stand-in (curl) whose loaded-libcurl
;;; raises a plain error, not a refusal, for tests/test-library-loading.sps
;;; only. Run with --libdirs tests/fixtures/raising:src, it shadows src/'s
;;; (curl), so the probe and the preflight meet a raise that is a bug and
;;; must report it as one: never as a refusal.
;;;
;;; It exports every name (curl) does, so that a program which references
;;; one expands, and the raise comes from calling loaded-libcurl itself.
;;; The conditions are src/'s own; every other procedure raises.
(library (curl)
  (export
   loaded-libcurl
   libcurl-info? libcurl-info-path libcurl-info-source libcurl-info-version
   libcurl-info-version-number libcurl-info-features libcurl-info-feature-names
   libcurl-info-ssl-version libcurl-info-host
   &curl-error curl-error?
   &curl-library-unavailable curl-library-unavailable?
   curl-library-unavailable-reason curl-library-unavailable-path
   curl-library-unavailable-source curl-library-unavailable-detail
   curl-library-unavailable-candidates curl-library-unavailable-library
   curl-library-unavailable-reasons
   &curl-wrong-thread curl-wrong-thread?
   curl-wrong-thread-who curl-wrong-thread-expected curl-wrong-thread-actual)
  (import (rnrs)
          (curl private conditions))

  ;; loaded-libcurl : -> Nothing
  (define (loaded-libcurl)
    (error 'loaded-libcurl "the raising fixture raises a plain error, not a refusal"))

  (define (unreachable who)
    (lambda (info)
      (error who "the raising fixture never returns a libcurl-info" info)))

  (define libcurl-info? (unreachable 'libcurl-info?))
  (define libcurl-info-path (unreachable 'libcurl-info-path))
  (define libcurl-info-source (unreachable 'libcurl-info-source))
  (define libcurl-info-version (unreachable 'libcurl-info-version))
  (define libcurl-info-version-number (unreachable 'libcurl-info-version-number))
  (define libcurl-info-features (unreachable 'libcurl-info-features))
  (define libcurl-info-feature-names (unreachable 'libcurl-info-feature-names))
  (define libcurl-info-ssl-version (unreachable 'libcurl-info-ssl-version))
  (define libcurl-info-host (unreachable 'libcurl-info-host)))
