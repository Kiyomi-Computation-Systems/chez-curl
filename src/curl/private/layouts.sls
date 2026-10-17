#!r6rs
;;; (curl private layouts): the C structs Scheme reads, each a define-ftype
;;; written from libcurl's headers (ADR-0001, decision 4). C's padding and
;;; alignment apply, as in a C struct.
;;;
;;; tests/test-constants.sps reads this file as data and checks every
;;; field of every define-ftype here against the headers: its offset with
;;; offsetof, its size with sizeof, and its kind (integer, floating or
;;; other) with _Generic. Each define-ftype needs a row in that suite's
;;; layout-rows, naming its C type, and must be a struct of fields whose
;;; types are in the suite's field-kinds. Anything else fails there by name.
;;;
;;; This is the only library check-seam lets import define-ftype: a
;;; function ftype would bind C without foreign-procedure (ADR-0007).
;;;
;;; It never loads libcurl. (curl private native) does, and reads these
;;; through ftype pointers.
(library (curl private layouts)
  (export curl-version-info-data)
  (import (curl private require-threaded)
          (rnrs)
          (only (chezscheme) define-ftype))

  ;; curl-version-info-data : Ftype
  ;; curl_version_info_data, curl/curl.h, through the last field
  ;; CURLVERSION_TENTH fills, gsasl_version: the age native asks for at the
  ;; floor (constants.sls). It stops there on purpose, so its size is not
  ;; the struct's, and only its fields are checked.
  ;; features is an int in C. It is read as unsigned, the same size: a bit
  ;; 31 in a later libcurl would make an int negative, and feature-names
  ;; takes a natural number.
  (define-ftype curl-version-info-data
    (struct
      (age int)
      (version uptr)
      (version-num unsigned-int)
      (host uptr)
      (features unsigned-int)
      (ssl-version uptr)
      (ssl-version-num long)
      (libz-version uptr)
      (protocols uptr)
      (ares uptr)
      (ares-num int)
      (libidn uptr)
      (iconv-ver-num int)
      (libssh-version uptr)
      (brotli-ver-num unsigned-int)
      (brotli-version uptr)
      (nghttp2-ver-num unsigned-int)
      (nghttp2-version uptr)
      (quic-version uptr)
      (cainfo uptr)
      (capath uptr)
      (zstd-ver-num unsigned-int)
      (zstd-version uptr)
      (hyper-version uptr)
      (gsasl-version uptr))))
