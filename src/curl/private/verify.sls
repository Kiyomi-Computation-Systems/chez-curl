#!r6rs
;;; (curl private verify): what a loaded libcurl must offer (ADR-0002,
;;; ADR-0003).
;;;
;;; Pure: the native layer reads curl_version_info and runs the two probes,
;;; and hands their answers here, so tests/test-verify.sps can make every
;;; decision on synthetic inputs. Both checks come after curl_version_info
;;; is read, so each takes the library's report too, and every refusal
;;; carries it (ADR-0002, decision 4). In load order:
;;;
;;;   1. check-version: version_num at least the floor, 7.85.0, else
;;;      below-floor; then CURL_VERSION_SSL set, else no-ssl.
;;;   2. check-apis: curl_easy_option_by_name("URL") found something, and
;;;      curl_easy_header on a fresh handle did not answer
;;;      CURLHE_NOT_BUILT_IN, else missing-api naming the API.
(library (curl private verify)
  (export libcurl-floor check-version check-apis feature-names)
  (import (curl private require-threaded)
          (rnrs)
          (curl private conditions)
          (curl private constants))

  ;; libcurl-floor : Natural
  ;; The oldest libcurl chez-curl loads, 7.85.0, as curl_version_info's
  ;; version_num encodes it: #xMMmmpp (ADR-0003).
  (define libcurl-floor #x075500)

  ;; check-version : String Natural Natural String Symbol Libcurl-Info -> #t
  ;; #t when VERSION-NUM is at least the floor and FEATURES has
  ;; CURL_VERSION_SSL. Otherwise raises &curl-library-unavailable, carrying
  ;; PATH, SOURCE, VERSION-STRING and LIBRARY: below-floor when the library
  ;; is too old, whatever its features, and else no-ssl.
  (define (check-version version-string version-num features path source library)
    (cond
      ((< version-num libcurl-floor)
       (refuse 'below-floor path source library version-string
               (string-append "libcurl " version-string " is older than chez-curl's floor, "
                              (version->string libcurl-floor)
                              "; name a newer one with CHEZ_CURL_LIBCURL")))
      ((zero? (bitwise-and features curl-version-ssl))
       (refuse 'no-ssl path source library version-string
               (string-append "libcurl " version-string
                              " was built without SSL; name another with CHEZ_CURL_LIBCURL")))
      (else #t)))

  ;; check-apis : Boolean Integer String Symbol Libcurl-Info -> #t
  ;; #t when OPTION-FOUND?, whether curl_easy_option_by_name("URL") answered
  ;; non-NULL, is #t, and HEADER-CODE, what curl_easy_header answered on a
  ;; fresh handle, is not CURLHE_NOT_BUILT_IN. Otherwise raises
  ;; &curl-library-unavailable, reason missing-api, carrying PATH, SOURCE,
  ;; LIBRARY and the C name of the missing API, the options API's first.
  ;; OPTION-FOUND? must be a boolean: a NULL pointer passed as 0 would be
  ;; true.
  (define (check-apis option-found? header-code path source library)
    (unless (boolean? option-found?)
      (assertion-violation 'check-apis
                           "the option probe's answer is not a boolean"
                           option-found?))
    (cond
      ((not option-found?)
       (refuse 'missing-api path source library "curl_easy_option_by_name"
               "libcurl was built without its options API (--disable-get-easy-options); name another with CHEZ_CURL_LIBCURL"))
      ((= header-code curlhe-not-built-in)
       (refuse 'missing-api path source library "curl_easy_header"
               "libcurl was built without its header API (--disable-headers-api); name another with CHEZ_CURL_LIBCURL"))
      (else #t)))

  ;; feature-names : Natural -> (Listof (U Symbol Positive-Integer))
  ;; The name of each CURL_VERSION_* bit set in FEATURES, in curl.h's
  ;; order, then each set bit the table does not know, as its value (a
  ;; power of two), lowest first.
  (define (feature-names features)
    (append
     (map car (filter (lambda (entry) (not (zero? (bitwise-and features (cdr entry)))))
                      curl-version-features))
     (unknown-bits (bitwise-and features (bitwise-not known-bits)))))

  (define known-bits
    (fold-left bitwise-ior 0 (map cdr curl-version-features)))

  ;; unknown-bits : Natural -> (Listof Positive-Integer)
  ;; Each bit set in BITS, as its value, lowest first.
  (define (unknown-bits bits)
    (let loop ((bits bits) (bit 1) (found '()))
      (cond ((zero? bits) (reverse found))
            ((zero? (bitwise-and bits bit)) (loop bits (* bit 2) found))
            (else (loop (- bits bit) (* bit 2) (cons bit found))))))

  ;; version->string : Natural -> String
  ;; #xMMmmpp as M.m.p.
  (define (version->string num)
    (string-append (number->string (bitwise-arithmetic-shift-right num 16)) "."
                   (number->string (bitwise-and (bitwise-arithmetic-shift-right num 8) #xff)) "."
                   (number->string (bitwise-and num #xff))))

  ;; refuse : Symbol String Symbol Libcurl-Info String String -> Nothing
  (define (refuse reason path source library detail message)
    (raise (condition (make-curl-library-unavailable reason path source detail '()
                                                     library)
                      (make-who-condition 'chez-curl)
                      (make-message-condition message)
                      (make-irritants-condition (list path))))))
