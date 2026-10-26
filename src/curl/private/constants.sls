#!r6rs
;;; (curl private constants): the libcurl constants chez-curl needs, each a
;;; Scheme definition copied from libcurl's headers (ADR-0001, decision 3).
;;; The values are curl 8.20.0's, read from the container's
;;; include/curl/. libcurl never renumbers them.
;;;
;;; CURLOPT_* ids are not here, and never will be: they come from the
;;; loaded library, by name (ADR-0001, decision 2).
(library (curl private constants)
  (export curl-version-features curl-version-ssl
          curlhe-not-built-in curlh-header curl-global-default curle-ok
          curle-bad-function-argument curle-not-built-in curlversion-tenth
          curlinfo-private curlinfo-rtsp-client-cseq curlot-types
          curlue-ok curlue-codes curlupart-url curlupart-scheme
          curlinfo-response-code curlinfo-http-version curlinfo-effective-url
          curl-error-size
          curl-http-version-1-0 curl-http-version-1-1 curl-http-version-2-0
          curl-http-version-3
          curle-unsupported-protocol curle-weird-server-reply curle-partial-file
          curle-write-error curle-out-of-memory curle-operation-timedout
          curle-got-nothing curle-recv-error curle-filesize-exceeded
          curlm-ok curlm-unknown-option curlmsg-done
          curlmopt-max-total-connections curlmopt-quick-exit)
  (import (curl private require-threaded)
          (rnrs))

  ;; curl-version-features : (Listof (Pairof Symbol Positive-Integer))
  ;; Every CURL_VERSION_* feature bit in curl/curl.h, in its order, each
  ;; named for its macro without the prefix. The features word of
  ;; curl_version_info_data holds these.
  (define curl-version-features
    '((ipv6         . #x00000001)     ; CURL_VERSION_IPV6         (1<<0)
      (kerberos4    . #x00000002)     ; CURL_VERSION_KERBEROS4    (1<<1)
      (ssl          . #x00000004)     ; CURL_VERSION_SSL          (1<<2)
      (libz         . #x00000008)     ; CURL_VERSION_LIBZ         (1<<3)
      (ntlm         . #x00000010)     ; CURL_VERSION_NTLM         (1<<4)
      (gssnegotiate . #x00000020)     ; CURL_VERSION_GSSNEGOTIATE (1<<5)
      (debug        . #x00000040)     ; CURL_VERSION_DEBUG        (1<<6)
      (asynchdns    . #x00000080)     ; CURL_VERSION_ASYNCHDNS    (1<<7)
      (spnego       . #x00000100)     ; CURL_VERSION_SPNEGO       (1<<8)
      (largefile    . #x00000200)     ; CURL_VERSION_LARGEFILE    (1<<9)
      (idn          . #x00000400)     ; CURL_VERSION_IDN          (1<<10)
      (sspi         . #x00000800)     ; CURL_VERSION_SSPI         (1<<11)
      (conv         . #x00001000)     ; CURL_VERSION_CONV         (1<<12)
      (curldebug    . #x00002000)     ; CURL_VERSION_CURLDEBUG    (1<<13)
      (tlsauth-srp  . #x00004000)     ; CURL_VERSION_TLSAUTH_SRP  (1<<14)
      (ntlm-wb      . #x00008000)     ; CURL_VERSION_NTLM_WB      (1<<15)
      (http2        . #x00010000)     ; CURL_VERSION_HTTP2        (1<<16)
      (gssapi       . #x00020000)     ; CURL_VERSION_GSSAPI       (1<<17)
      (kerberos5    . #x00040000)     ; CURL_VERSION_KERBEROS5    (1<<18)
      (unix-sockets . #x00080000)     ; CURL_VERSION_UNIX_SOCKETS (1<<19)
      (psl          . #x00100000)     ; CURL_VERSION_PSL          (1<<20)
      (https-proxy  . #x00200000)     ; CURL_VERSION_HTTPS_PROXY  (1<<21)
      (multi-ssl    . #x00400000)     ; CURL_VERSION_MULTI_SSL    (1<<22)
      (brotli       . #x00800000)     ; CURL_VERSION_BROTLI       (1<<23)
      (altsvc       . #x01000000)     ; CURL_VERSION_ALTSVC       (1<<24)
      (http3        . #x02000000)     ; CURL_VERSION_HTTP3        (1<<25)
      (zstd         . #x04000000)     ; CURL_VERSION_ZSTD         (1<<26)
      (unicode      . #x08000000)     ; CURL_VERSION_UNICODE      (1<<27)
      (hsts         . #x10000000)     ; CURL_VERSION_HSTS         (1<<28)
      (gsasl        . #x20000000)     ; CURL_VERSION_GSASL        (1<<29)
      (threadsafe   . #x40000000)))   ; CURL_VERSION_THREADSAFE   (1<<30)

  ;; curl-version-ssl : Positive-Integer
  ;; curl/curl.h: CURL_VERSION_SSL, (1<<2). Required at load (ADR-0002).
  (define curl-version-ssl #x00000004)

  ;; curlhe-not-built-in : Natural
  ;; curl/header.h: CURLHE_NOT_BUILT_IN, the eighth CURLHcode, 7. What
  ;; curl_easy_header answers in a build without the header API (ADR-0003).
  (define curlhe-not-built-in 7)

  ;; curlh-header : Positive-Integer
  ;; curl/header.h: CURLH_HEADER, (1 << 0), a plain server header. The
  ;; origin the header probe asks curl_easy_header for (ADR-0003).
  (define curlh-header 1)

  ;; curl-global-default : Natural
  ;; curl/curl.h: CURL_GLOBAL_DEFAULT, which is CURL_GLOBAL_ALL,
  ;; CURL_GLOBAL_SSL | CURL_GLOBAL_WIN32, (1<<0) | (1<<1). The flags for the
  ;; one curl_global_init (ADR-0003).
  (define curl-global-default 3)

  ;; curle-ok : Natural
  ;; curl/curl.h: CURLE_OK = 0.
  (define curle-ok 0)

  ;; curle-bad-function-argument : Positive-Integer
  ;; curl/curl.h: CURLE_BAD_FUNCTION_ARGUMENT, the CURLcode 43. What
  ;; curl_easy_setopt answers for a value its option refuses, such as a
  ;; negative MAXFILESIZE_LARGE.
  (define curle-bad-function-argument 43)

  ;; curle-not-built-in : Positive-Integer
  ;; curl/curl.h: CURLE_NOT_BUILT_IN, the CURLcode 4, there since 7.21.5.
  ;; What curl_easy_setopt answers for an option the build left out, such
  ;; as CAPATH on a TLS backend with no CA directory: a clear of it is
  ;; taken all the same (ADR-0018).
  (define curle-not-built-in 4)

  ;; curlversion-tenth : Natural
  ;; curl/curl.h: CURLVERSION_TENTH, the tenth CURLversion, 9. The age to
  ;; pass curl_version_info: it was CURLVERSION_NOW at the floor, 7.85.0
  ;; (7.77.0 added it, 7.87.0 the eleventh), so a library at the floor
  ;; fills every field it names. CURLVERSION_NOW itself moves with the
  ;; headers: it is CURLVERSION_TWELFTH in 8.20.0.
  (define curlversion-tenth 9)

  ;; curlinfo-private : Positive-Integer
  ;; curl/curl.h: CURLINFO_PRIVATE, CURLINFO_STRING + 21, 0x100000 + 21.
  ;; curl_easy_getinfo writes the pointer CURLOPT_PRIVATE set, as given.
  (define curlinfo-private 1048597)

  ;; curlinfo-rtsp-client-cseq : Positive-Integer
  ;; curl/curl.h: CURLINFO_RTSP_CLIENT_CSEQ, CURLINFO_LONG + 37,
  ;; 0x200000 + 37. curl_easy_getinfo writes the long
  ;; CURLOPT_RTSP_CLIENT_CSEQ set.
  (define curlinfo-rtsp-client-cseq 2097189)

  ;; curlot-types : (Listof (Pairof Symbol Natural))
  ;; Every curl_easytype in curl/options.h, in its order, each named for its
  ;; CURLOT_* name without the prefix: the type code of an option, as
  ;; curl_easy_option_by_name's struct curl_easyoption gives it.
  (define curlot-types
    '((long     . 0)     ; CURLOT_LONG      a long, a range of values
      (values   . 1)     ; CURLOT_VALUES    a long, a set or bitmask
      (off-t    . 2)     ; CURLOT_OFF_T     a curl_off_t
      (object   . 3)     ; CURLOT_OBJECT    a void *
      (string   . 4)     ; CURLOT_STRING    a char *, NUL-terminated
      (slist    . 5)     ; CURLOT_SLIST     a struct curl_slist *
      (cbptr    . 6)     ; CURLOT_CBPTR     a void *, handed to a callback
      (blob     . 7)     ; CURLOT_BLOB      a struct curl_blob *
      (function . 8)))   ; CURLOT_FUNCTION  a function pointer

  ;; curlue-ok : Natural
  ;; curl/urlapi.h: CURLUE_OK, the first CURLUcode, 0. What the URL API's
  ;; calls answer when they succeed.
  (define curlue-ok 0)

  ;; curlue-codes : (Listof (Pairof Symbol Natural))
  ;; Every CURLUcode in the floor's curl/urlapi.h (7.85.0), in its order,
  ;; each named for its CURLUE_* name without the prefix. A URL refusal's
  ;; reason is its code's name here (M2 plan, section 3.7). A later
  ;; libcurl's codes, CURLUE_LACKS_IDN (30) and CURLUE_TOO_LARGE (31) in
  ;; 8.20.0, are not here: the floor lane's headers lack them, and such a
  ;; code is reported by its number.
  (define curlue-codes
    '((ok                  . 0)     ; CURLUE_OK
      (bad-handle          . 1)     ; CURLUE_BAD_HANDLE
      (bad-partpointer     . 2)     ; CURLUE_BAD_PARTPOINTER
      (malformed-input     . 3)     ; CURLUE_MALFORMED_INPUT
      (bad-port-number     . 4)     ; CURLUE_BAD_PORT_NUMBER
      (unsupported-scheme  . 5)     ; CURLUE_UNSUPPORTED_SCHEME
      (urldecode           . 6)     ; CURLUE_URLDECODE
      (out-of-memory       . 7)     ; CURLUE_OUT_OF_MEMORY
      (user-not-allowed    . 8)     ; CURLUE_USER_NOT_ALLOWED
      (unknown-part        . 9)     ; CURLUE_UNKNOWN_PART
      (no-scheme           . 10)    ; CURLUE_NO_SCHEME
      (no-user             . 11)    ; CURLUE_NO_USER
      (no-password         . 12)    ; CURLUE_NO_PASSWORD
      (no-options          . 13)    ; CURLUE_NO_OPTIONS
      (no-host             . 14)    ; CURLUE_NO_HOST
      (no-port             . 15)    ; CURLUE_NO_PORT
      (no-query            . 16)    ; CURLUE_NO_QUERY
      (no-fragment         . 17)    ; CURLUE_NO_FRAGMENT
      (no-zoneid           . 18)    ; CURLUE_NO_ZONEID
      (bad-file-url        . 19)    ; CURLUE_BAD_FILE_URL
      (bad-fragment        . 20)    ; CURLUE_BAD_FRAGMENT
      (bad-hostname        . 21)    ; CURLUE_BAD_HOSTNAME
      (bad-ipv6            . 22)    ; CURLUE_BAD_IPV6
      (bad-login           . 23)    ; CURLUE_BAD_LOGIN
      (bad-password        . 24)    ; CURLUE_BAD_PASSWORD
      (bad-path            . 25)    ; CURLUE_BAD_PATH
      (bad-query           . 26)    ; CURLUE_BAD_QUERY
      (bad-scheme          . 27)    ; CURLUE_BAD_SCHEME
      (bad-slashes         . 28)    ; CURLUE_BAD_SLASHES
      (bad-user            . 29)))  ; CURLUE_BAD_USER

  ;; curlupart-url : Natural
  ;; curl/urlapi.h: CURLUPART_URL, the first CURLUPart, 0: the whole URL.
  (define curlupart-url 0)

  ;; curlupart-scheme : Positive-Integer
  ;; curl/urlapi.h: CURLUPART_SCHEME, the second CURLUPart, 1.
  (define curlupart-scheme 1)

  ;; --- the transfer (M2 plan, section 5; on an engine since M3) ---------------

  ;; curlinfo-response-code : Positive-Integer
  ;; curl/curl.h: CURLINFO_RESPONSE_CODE, CURLINFO_LONG + 2, 0x200000 + 2.
  ;; curl_easy_getinfo writes the last response's status code, a long.
  (define curlinfo-response-code 2097154)

  ;; curlinfo-http-version : Positive-Integer
  ;; curl/curl.h: CURLINFO_HTTP_VERSION, CURLINFO_LONG + 46, 0x200000 + 46.
  ;; curl_easy_getinfo writes the last response's version, a long: one of
  ;; the CURL_HTTP_VERSION_ values below, or 0.
  (define curlinfo-http-version 2097198)

  ;; curlinfo-effective-url : Positive-Integer
  ;; curl/curl.h: CURLINFO_EFFECTIVE_URL, CURLINFO_STRING + 1, 0x100000 + 1.
  ;; curl_easy_getinfo writes a char * libcurl keeps until cleanup.
  (define curlinfo-effective-url 1048577)

  ;; curl-error-size : Positive-Integer
  ;; curl/curl.h: CURL_ERROR_SIZE, 256: the bytes CURLOPT_ERRORBUFFER needs.
  (define curl-error-size 256)

  ;; curl-http-version-1-0 : Positive-Integer
  ;; curl-http-version-1-1 : Positive-Integer
  ;; curl-http-version-2-0 : Positive-Integer
  ;; curl-http-version-3 : Positive-Integer
  ;; curl/curl.h: CURL_HTTP_VERSION_1_0 1L, _1_1 2L, _2_0 3L and _3 30L:
  ;; what CURLINFO_HTTP_VERSION answers for each version.
  (define curl-http-version-1-0 1)
  (define curl-http-version-1-1 2)
  (define curl-http-version-2-0 3)
  (define curl-http-version-3 30)

  ;; The CURLcodes the transfer's tests name, each a curl/curl.h CURLcode,
  ;; all in the floor's headers. CURLE_TOO_LARGE, 100, came in 8.6.0, after
  ;; the floor, so it is no constant here; tests/known-transfer-verdicts.sexp
  ;; writes it, as every code, as a number.
  ;;
  ;; curle-unsupported-protocol : Positive-Integer   CURLE_UNSUPPORTED_PROTOCOL, 1
  ;; curle-weird-server-reply : Positive-Integer     CURLE_WEIRD_SERVER_REPLY, 8
  ;; curle-partial-file : Positive-Integer           CURLE_PARTIAL_FILE, 18
  ;; curle-write-error : Positive-Integer            CURLE_WRITE_ERROR, 23: a write
  ;;                                                 callback refused a chunk
  ;; curle-out-of-memory : Positive-Integer          CURLE_OUT_OF_MEMORY, 27
  ;; curle-operation-timedout : Positive-Integer     CURLE_OPERATION_TIMEDOUT, 28
  ;; curle-got-nothing : Positive-Integer            CURLE_GOT_NOTHING, 52
  ;; curle-recv-error : Positive-Integer             CURLE_RECV_ERROR, 56
  ;; curle-filesize-exceeded : Positive-Integer      CURLE_FILESIZE_EXCEEDED, 63
  (define curle-unsupported-protocol 1)
  (define curle-weird-server-reply 8)
  (define curle-partial-file 18)
  (define curle-write-error 23)
  (define curle-out-of-memory 27)
  (define curle-operation-timedout 28)
  (define curle-got-nothing 52)
  (define curle-recv-error 56)
  (define curle-filesize-exceeded 63)

  ;; The multi interface's (M3 plan, section 5.2), curl/multi.h.
  ;;
  ;; curlm-ok : Natural                  CURLM_OK, 0
  ;; curlm-unknown-option : Positive-Integer
  ;;                                     CURLM_UNKNOWN_OPTION, 6: curl_multi_setopt's
  ;;                                     answer to an option the libcurl lacks
  ;; curlmsg-done : Positive-Integer     CURLMSG_DONE, 1: a CURLMsg's msg for a
  ;;                                     transfer that has ended, its result in
  ;;                                     data.result
  (define curlm-ok 0)
  (define curlm-unknown-option 6)
  (define curlmsg-done 1)

  ;; The multi options chez-curl sets, curl/multi.h, each CURLOPTTYPE_LONG,
  ;; 0, plus its number. A multi option has no lookup by name, as an easy
  ;; option has (ADR-0001, decision 2), so its id is a constant.
  ;;
  ;; curlmopt-max-total-connections : Positive-Integer
  ;;                                     CURLMOPT_MAX_TOTAL_CONNECTIONS, 13, since
  ;;                                     7.30.0: tests/test-variadic.sps sets it
  ;;                                     through curl-multi-setopt-long, to watch a
  ;;                                     long arrive (ADR-0001, amended 2026-10-25)
  ;; curlmopt-quick-exit : Positive-Integer
  ;;                                     CURLMOPT_QUICK_EXIT, 21, since 8.20.0, after
  ;;                                     the floor: every engine sets it to 1 when it
  ;;                                     makes its multi handle (ADR-0019). Older
  ;;                                     headers lack it, so tests/test-constants.sps
  ;;                                     checks it where the headers have it
  (define curlmopt-max-total-connections 13)
  (define curlmopt-quick-exit 21))
