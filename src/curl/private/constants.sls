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
          curle-bad-function-argument curlversion-tenth
          curlinfo-private curlinfo-rtsp-client-cseq curlot-types)
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
      (function . 8))))  ; CURLOT_FUNCTION  a function pointer
