#!r6rs
;;; (curl private url): URLs parsed, resolved and checked by libcurl's own
;;; URL API (ADR-0008; M2 plan, section 4.4).
;;;
;;; Every CURLU handle here is made and freed within one call, under
;;; dynamic-wind, on the calling thread: nothing native outlives the call
;;; that made it (M2 plan, section 3.1), and re-entering a finished call
;;; through a continuation raises. Each string curl_url_get hands back is
;;; copied, then freed with curl_free. Each string handed to libcurl is a
;;; counted, NUL-terminated UTF-8 copy, freed as soon as curl_url_set
;;; returns: libcurl "does not have to keep content around after a
;;; successful call" (curl_url_set(3), 7.85.0).
;;;
;;; Every refusal raises &curl-url-error (curl private conditions): with
;;; libcurl's CURLUcode and its name, or with one of chez-curl's own
;;; reasons, scheme-not-http or embedded-nul, and no code. A string holding
;;; U+0000 is refused before libcurl sees it: C reads a string to its first
;;; NUL, so "http://a/\x0;b" would reach libcurl as http://a/.
;;;
;;; curl's verdicts vary by version (ADR-0008, amended 2026-10-19):
;;; tests/test-url.sps holds the shared answers, and
;;; tests/known-url-verdicts.sexp a row per libcurl for the rest.
(library (curl private url)
  (export url-normalize url-resolve call-with-parsed-url require-http-scheme)
  (import (curl private require-threaded)
          (rnrs)
          (curl private conditions)
          (curl private constants)
          (curl private native))

  ;; refuse : String (U Symbol #f) (U Integer #f) (U String #f) -> Nothing
  (define (refuse input reason code message)
    (raise (condition (make-curl-url-error input reason code message)
                      (make-who-condition 'chez-curl)
                      (make-message-condition
                       (or message "libcurl's URL API refused a URL"))
                      (make-irritants-condition (list input)))))

  ;; refuse-code : String Integer -> Nothing
  ;; libcurl's refusal of INPUT with CODE.
  (define (refuse-code input code)
    (refuse input (curl-url-code-reason code) code (curl-url-strerror code)))

  ;; holds-nul? : String -> Boolean
  (define (holds-nul? s)
    (let loop ((i 0))
      (and (< i (string-length s))
           (or (char=? (string-ref s i) #\nul) (loop (+ i 1))))))

  ;; checked-input : Symbol Any -> String
  ;; INPUT, a string without U+0000: an assertion violation from WHO for
  ;; what is no string, and embedded-nul for one that holds it.
  (define (checked-input who input)
    (unless (string? input)
      (assertion-violation who "a URL is a string" input))
    (when (holds-nul? input)
      (refuse input 'embedded-nul #f
              "a URL holds U+0000, which libcurl would read as its end"))
    input)

  ;; set-url! : Positive-Integer String -> Void
  ;; curl_url_set of the whole URL on HANDLE: INPUT parsed, or resolved
  ;; against what HANDLE holds; raises its refusal.
  (define (set-url! handle input)
    (let ((code (call-with-c-string input
                  (lambda (address) (curl-url-set handle curlupart-url address 0)))))
      (unless (eqv? code curlue-ok)
        (refuse-code input code))))

  ;; get-part : Positive-Integer Natural String -> String
  ;; PART of HANDLE, as curl_url_get writes it, copied and then freed with
  ;; curl_free; INPUT names the refusal, if any.
  (define (get-part handle part input)
    (let-values (((code address) (curl-url-get handle part 0)))
      (unless (eqv? code curlue-ok)
        (refuse-code input code))
      (dynamic-wind
        (lambda () #f)
        (lambda () (utf8->string (c-string->bytevector address)))
        (lambda () (curl-free address)))))

  ;; call-with-parsed-url : String (Positive-Integer -> Any) -> Any
  ;; PROC's answer, PROC given a CURLU handle that holds STRING, parsed by
  ;; curl_url_set with no flags. The handle is freed once PROC returns,
  ;; raises or escapes. STRING's refusal raises &curl-url-error before PROC
  ;; runs. Re-entering PROC through a continuation, once the handle is
  ;; freed, raises an assertion violation.
  (define (call-with-parsed-url string proc)
    (checked-input 'call-with-parsed-url string)
    (unless (procedure? proc)
      (assertion-violation 'call-with-parsed-url "not a procedure" proc))
    (let ((handle #f) (freed #f))
      (dynamic-wind
        (lambda ()
          (when freed
            (assertion-violation 'call-with-parsed-url
                                 "re-entered after its handle was freed" string))
          (let ((made (curl-url)))
            (when (eqv? made 0)
              (error 'call-with-parsed-url "curl_url returned NULL: no memory for a handle"))
            (set! handle made)))
        (lambda ()
          (set-url! handle string)
          (proc handle))
        (lambda ()
          (set! freed #t)
          (curl-url-cleanup handle)))))

  ;; url-normalize : String -> String
  ;; What curl_url_get gives back for STRING, parsed: libcurl's own form of
  ;; it, dot segments removed. Its scheme is not checked here:
  ;; require-http-scheme does that.
  (define (url-normalize string)
    (call-with-parsed-url string
      (lambda (handle) (get-part handle curlupart-url string))))

  ;; url-resolve : String String -> String
  ;; REFERENCE resolved against BASE, by curl_url_set on BASE's handle
  ;; (ADR-0008, decision 4), as curl_url_get gives it back. A refusal of
  ;; either raises, naming the string refused.
  (define (url-resolve base reference)
    (checked-input 'url-resolve reference)
    (call-with-parsed-url base
      (lambda (handle)
        (set-url! handle reference)
        (get-part handle curlupart-url reference))))

  ;; require-http-scheme : Positive-Integer -> Void
  ;; Returns when the parsed HANDLE's scheme, as curl_url_get gives it, is
  ;; http or https. Otherwise raises &curl-url-error, reason
  ;; scheme-not-http, with the URL HANDLE holds as its input (ADR-0008,
  ;; decision 2). libcurl writes a scheme in lower case.
  (define (require-http-scheme handle)
    (let ((url (get-part handle curlupart-url "a parsed handle")))
      (unless (member (get-part handle curlupart-scheme url) '("http" "https"))
        (refuse url 'scheme-not-http #f "chez-curl fetches only http and https URLs")))))
