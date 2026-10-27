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
  (export curl-version-info-data curl-easyoption curl-header curl-msg curl-blob)
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
      (gsasl-version uptr)))

  ;; curl-easyoption : Ftype
  ;; struct curl_easyoption, curl/options.h, every field: what
  ;; curl_easy_option_by_name answers a pointer to. id is a CURLoption and
  ;; type a curl_easytype, both enums of int's size; type is read as
  ;; unsigned, since its codes are natural numbers (constants.sls's
  ;; curlot-types). name is the option's name without CURLOPT_. The suite
  ;; checks each field here, not the struct's size, so a field left off
  ;; the end would pass it; native reads options one at a time, by
  ;; pointer, and never steps from one to the next.
  (define-ftype curl-easyoption
    (struct
      (name uptr)
      (id int)
      (type unsigned-int)
      (flags unsigned-int)))

  ;; curl-header : Ftype
  ;; struct curl_header, curl/header.h (7.83.0), every field: what
  ;; curl_easy_nextheader answers a pointer to. name and value are C
  ;; strings libcurl keeps until the handle is reused or cleaned up; amount
  ;; is how many headers share the name, and index this one's place among
  ;; them; origin holds CURLH_ bits; anchor is libcurl's own. The suite
  ;; checks every field and the struct's size.
  (define-ftype curl-header
    (struct
      (name uptr)
      (value uptr)
      (amount size_t)
      (index size_t)
      (origin unsigned-int)
      (anchor uptr)))

  ;; curl-msg : Ftype
  ;; struct CURLMsg, curl/multi.h, every field: what curl_multi_info_read
  ;; answers a pointer to. msg is a CURLMSG, an enum of int's size;
  ;; easy-handle the transfer's easy handle. data is a union of a void *
  ;; and a CURLcode, result: a transfer that ended, msg CURLMSG_DONE, has
  ;; its CURLcode there, so the field is laid out as that member alone, an
  ;; int at the union's offset, and named for it, data.result, which the
  ;; suite reads as the C member's name. The union is a pointer's size, so
  ;; the struct's size, which the suite checks, is the trailing padding's
  ;; too.
  (define-ftype curl-msg
    (struct
      (msg int)
      (easy-handle uptr)
      (data.result int)))

  ;; curl-blob : Ftype
  ;; struct curl_blob, curl/easy.h (7.71.0), every field: what a blob
  ;; option's setopt takes the address of. data is the bytes' address, len
  ;; their count, and flags CURL_BLOB_COPY or CURL_BLOB_NOCOPY; native fills
  ;; one for each blob the hatch sets (ADR-0009, decision 4). The suite
  ;; checks every field and the struct's size.
  (define-ftype curl-blob
    (struct
      (data uptr)
      (len size_t)
      (flags unsigned-int))))
