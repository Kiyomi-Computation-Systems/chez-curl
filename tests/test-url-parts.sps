#!r6rs
;;; The suite for (curl)'s two URL functions, curl-url-part and
;;; curl-url-append-query, and for the rule every URL function keeps: an
;;; answer whose bytes are not UTF-8 is refused as not-utf-8, never decoded
;;; with U+FFFD (the M5 plan, sections 3.1 and 4.1; ADR-0028).
;;;
;;; Its cases are M5 slice 1's measurement's (.plans/research/m5/url-parts/),
;;; through C on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's
;;; 8.20.0 and 8.23.0, written once, in all-cases:
;;;
;;;   - (append URL PART): curl-url-append-query, eight URLs with and without
;;;     a query, an empty one, one ending in &, and a fragment, each with
;;;     eight parts: what the form encoding makes, %XX in upper case, + & and
;;;     =; a bare name; an empty part; raw UTF-8; the query's other
;;;     characters; and a #, which is refused; then every byte encoded in
;;;     upper case and in lower case, behind every character the encoding
;;;     keeps, URLs whose other parts a parse could change, and a space,
;;;     which libcurl refuses;
;;;   - (parts URL): curl-url-part, each of its nine parts of 41 URLs: each
;;;     part present and absent, ports named, defaulted and odd, é raw and
;;;     as %E9 in each part, a host's %XX, which libcurl decodes, U+FEFF at
;;;     a part's start, which Chez's decoder drops, and two other schemes.
;;;
;;; curl's verdicts vary by version, so, as test-url does:
;;;
;;;   - shared-answers holds the answer every recorded libcurl gives;
;;;   - tests/known-url-part-verdicts.sexp holds a row per libcurl version,
;;;     7.85.0, 8.5.0, 8.20.0, 8.23.0 and Apple's 8.7.1, with that version's
;;;     answer to each case shared-answers leaves out.
;;;
;;; The two cover the cases exactly, each once. A libcurl whose version has
;;; no row fails here, and the suite prints the row it would need on the
;;; error port (ADR-0017). Every answer is asserted whole, with the native
;;; counts after it, which must all be zero. An append's answer is the URL,
;;; or the refusal; a parts answer is the nine parts in order, each a
;;; string, a natural for the port, (absent), or the refusal.
;;;
;;; Then the refusals' conditions, field by field; not-utf-8 through
;;; url-normalize, url-resolve, the scheme check and a submit; a NUL in a
;;; part at every position; a part another thread changes; and both
;;; functions escaped at every tick.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f, and an absent part is (absent).
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (curl)
        (only (curl private url) url-normalize url-resolve call-with-parsed-url
              require-http-scheme appended-url)
        (curl private counters)
        (rnrs mutable-strings)
        (only (chezscheme) fork-thread thread-join sleep make-time make-engine iota list-head))

;; SRFI-64 sets no exit status. This suite's last line turns the runner's
;; counts into one.
(define runner (test-runner-simple))
(test-runner-current runner)

;; The simple runner names a failing test but not its values. Print both.
(let ((simple-end (test-runner-on-test-end runner)))
  (test-runner-on-test-end! runner
    (lambda (r)
      (simple-end r)
      (when (memq (test-result-kind r) '(fail xpass))
        (display "  expected: ")
        (write (test-result-ref r 'expected-value))
        (newline)
        (display "  actual:   ")
        (write (test-result-ref r 'actual-value))
        (newline)))))

;; --- the cases ----------------------------------------------------------------------

;; kept-set : String
;; Every character the form encoding keeps as itself, and +, its space.
(define kept-set "*-._0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+")

;; every-byte : (Natural -> String) -> String
;; %XX for each byte, 0 to 255, in order, HEX writing each pair of digits.
(define (every-byte hex)
  (apply string-append
         (map (lambda (b) (string-append "%" (if (< b 16) "0" "") (hex (number->string b 16))))
              (iota 256))))

;; encoder-part : String
;; A part as the form encoding writes one: every kept character, then every
;; byte in upper-case hex. ADR-0028 sends it as written, on every libcurl.
(define encoder-part (string-append "k=" kept-set (every-byte string-upcase)))

;; lower-part : String
;; Every byte in lower-case hex, which a part set by curl_url_set turns
;; upper on 8.23.0.
(define lower-part (string-append "k=" (every-byte string-downcase)))

(define append-bases
  '("http://h.example/p" "http://h.example/p?a=1" "http://h.example/p?" "http://h.example/p?a=1&"
    "http://h.example/p#frag" "http://h.example/p?a=1#frag" "http://h.example/p?#frag"
    "http://h.example"))

(define append-parts
  '("b=2" "n=a%20b+c&m=%3D%26%2B" "x" "" "e=%C3%A9" "u=\xE9;" "q=?/:@!$'()*,;" "h=#x"))

;; append-cases : (Listof Case)
;; Each base with each part, then 14 more.
(define append-cases
  (append
   (apply append
          (map (lambda (base) (map (lambda (part) (list 'append base part)) append-parts))
               append-bases))
   `((append "http://h.example/p?a=1" ,encoder-part)
     (append "http://h.example/p?a=1" ,lower-part)
     (append "https://u:pw@H.Example:8443/p/q?a=1#frag" "b=2")
     (append "http://[::1]:8080/p" "b=2")
     (append "http://h.example:080/./a/../b?a=1" "b=2")
     (append "http://h.example/p\xE9;?q=\xE9;#f\xE9;" "b=2")
     (append "http://h.example/p#\xFEFF;f" "b=2")
     (append "http://h.example/p?a=1#f#g" "b=2")
     (append "http://h.example/p" "#x")
     (append "http://h.example/p" "x#")
     (append "http://h.example:99999/" "b=2")
     (append "http://caf%E9.example/" "b=2")
     (append "http://h.example/p" "s=a b")
     (append "http://h.example/p?a=1#frag" "s=a b"))))

(define parts-urls
  '("http://h.example/p" "https://u:pw@H.Example:8443/p/q?a=1&b=2#frag" "HTTP://h.example/p"
    "http://h.example" "http://h.example:80/p" "https://h.example/" "http://h.example:080/"
    "http://h.example:0/" "http://h.example:65535/" "http://[::1]:8080/p" "http://u@h.example/"
    "http://:pw@h.example/" "http://u:@h.example/" "http://h.example/p?" "http://h.example/p#"
    "http://h.example/p?#" "http://h.example/p%3D%3d?x=%3D&y=%3d#f%3D%3d"
    "http://us\xE9;r:pw@h.example/" "http://u:p\xE9;ss@h.example/" "http://caf\xE9;.example/"
    "http://h.example/p\xE9;" "http://h.example/p?q=\xE9;" "http://h.example/p#f\xE9;"
    "http://us%E9r:pw@h.example/" "http://u:p%E9ss@h.example/" "http://caf%E9.example/"
    "http://h.example/p%E9" "http://h.example/p?q=%E9" "http://h.example/p#f%E9"
    "http://caf%e9.example/" "http://caf%C3%A9.example/" "http://caf%C3.example/"
    "http://%41.example/" "http://a%00b.example/" "http://a%2Fb.example/" "http://a%2Eb.example/"
    "http://h.example/p?\xFEFF;x" "http://h.example/p#\xFEFF;\xFEFF;y" "file:///etc/passwd"
    "ftp://u@f.example/x" "http://h.example:99999/"))

(define parts-cases (map (lambda (url) (list 'parts url)) parts-urls))

;; part-names : (Listof Symbol)
;; The parts a parts case reads, in its answer's order.
(define part-names '(url scheme user password host port path query fragment))

;; all-cases : (Listof Case)
(define all-cases (append append-cases parts-cases))

;; shared-answers : (Listof (List Case Answer))
;; The cases every recorded libcurl answers alike: 7.85.0, 8.5.0 (OpenSSL
;; and GnuTLS), 8.20.0 and 8.23.0, through this suite, on 2026-10-27. The
;; parts answers agree with the C probe's curl_url_get on each.
(define shared-answers
  `(
    ((append "http://h.example/p" "b=2") "http://h.example/p?b=2")
    ((append "http://h.example/p" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?n=a%20b+c&m=%3D%26%2B")
    ((append "http://h.example/p" "x") "http://h.example/p?x")
    ((append "http://h.example/p" "") "http://h.example/p")
    ((append "http://h.example/p" "e=%C3%A9") "http://h.example/p?e=%C3%A9")
    ((append "http://h.example/p" "u=\xE9;") "http://h.example/p?u=\xE9;")
    ((append "http://h.example/p" "q=?/:@!$'()*,;") "http://h.example/p?q=?/:@!$'()*,;")
    ((append "http://h.example/p" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p?a=1" "b=2") "http://h.example/p?a=1&b=2")
    ((append "http://h.example/p?a=1" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?a=1&n=a%20b+c&m=%3D%26%2B")
    ((append "http://h.example/p?a=1" "x") "http://h.example/p?a=1&x")
    ((append "http://h.example/p?a=1" "") "http://h.example/p?a=1&")
    ((append "http://h.example/p?a=1" "e=%C3%A9") "http://h.example/p?a=1&e=%C3%A9")
    ((append "http://h.example/p?a=1" "u=\xE9;") "http://h.example/p?a=1&u=\xE9;")
    ((append "http://h.example/p?a=1" "q=?/:@!$'()*,;") "http://h.example/p?a=1&q=?/:@!$'()*,;")
    ((append "http://h.example/p?a=1" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p?" "b=2") "http://h.example/p?b=2")
    ((append "http://h.example/p?" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?n=a%20b+c&m=%3D%26%2B")
    ((append "http://h.example/p?" "x") "http://h.example/p?x")
    ((append "http://h.example/p?" "") "http://h.example/p")
    ((append "http://h.example/p?" "e=%C3%A9") "http://h.example/p?e=%C3%A9")
    ((append "http://h.example/p?" "u=\xE9;") "http://h.example/p?u=\xE9;")
    ((append "http://h.example/p?" "q=?/:@!$'()*,;") "http://h.example/p?q=?/:@!$'()*,;")
    ((append "http://h.example/p?" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p?a=1&" "b=2") "http://h.example/p?a=1&b=2")
    ((append "http://h.example/p?a=1&" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?a=1&n=a%20b+c&m=%3D%26%2B")
    ((append "http://h.example/p?a=1&" "x") "http://h.example/p?a=1&x")
    ((append "http://h.example/p?a=1&" "") "http://h.example/p?a=1&")
    ((append "http://h.example/p?a=1&" "e=%C3%A9") "http://h.example/p?a=1&e=%C3%A9")
    ((append "http://h.example/p?a=1&" "u=\xE9;") "http://h.example/p?a=1&u=\xE9;")
    ((append "http://h.example/p?a=1&" "q=?/:@!$'()*,;") "http://h.example/p?a=1&q=?/:@!$'()*,;")
    ((append "http://h.example/p?a=1&" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p#frag" "b=2") "http://h.example/p?b=2#frag")
    ((append "http://h.example/p#frag" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?n=a%20b+c&m=%3D%26%2B#frag")
    ((append "http://h.example/p#frag" "x") "http://h.example/p?x#frag")
    ((append "http://h.example/p#frag" "") "http://h.example/p#frag")
    ((append "http://h.example/p#frag" "e=%C3%A9") "http://h.example/p?e=%C3%A9#frag")
    ((append "http://h.example/p#frag" "u=\xE9;") "http://h.example/p?u=\xE9;#frag")
    ((append "http://h.example/p#frag" "q=?/:@!$'()*,;") "http://h.example/p?q=?/:@!$'()*,;#frag")
    ((append "http://h.example/p#frag" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p?a=1#frag" "b=2") "http://h.example/p?a=1&b=2#frag")
    ((append "http://h.example/p?a=1#frag" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?a=1&n=a%20b+c&m=%3D%26%2B#frag")
    ((append "http://h.example/p?a=1#frag" "x") "http://h.example/p?a=1&x#frag")
    ((append "http://h.example/p?a=1#frag" "") "http://h.example/p?a=1&#frag")
    ((append "http://h.example/p?a=1#frag" "e=%C3%A9") "http://h.example/p?a=1&e=%C3%A9#frag")
    ((append "http://h.example/p?a=1#frag" "u=\xE9;") "http://h.example/p?a=1&u=\xE9;#frag")
    ((append "http://h.example/p?a=1#frag" "q=?/:@!$'()*,;") "http://h.example/p?a=1&q=?/:@!$'()*,;#frag")
    ((append "http://h.example/p?a=1#frag" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p?#frag" "b=2") "http://h.example/p?b=2#frag")
    ((append "http://h.example/p?#frag" "n=a%20b+c&m=%3D%26%2B") "http://h.example/p?n=a%20b+c&m=%3D%26%2B#frag")
    ((append "http://h.example/p?#frag" "x") "http://h.example/p?x#frag")
    ((append "http://h.example/p?#frag" "") "http://h.example/p#frag")
    ((append "http://h.example/p?#frag" "e=%C3%A9") "http://h.example/p?e=%C3%A9#frag")
    ((append "http://h.example/p?#frag" "u=\xE9;") "http://h.example/p?u=\xE9;#frag")
    ((append "http://h.example/p?#frag" "q=?/:@!$'()*,;") "http://h.example/p?q=?/:@!$'()*,;#frag")
    ((append "http://h.example/p?#frag" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example" "b=2") "http://h.example/?b=2")
    ((append "http://h.example" "n=a%20b+c&m=%3D%26%2B") "http://h.example/?n=a%20b+c&m=%3D%26%2B")
    ((append "http://h.example" "x") "http://h.example/?x")
    ((append "http://h.example" "") "http://h.example/")
    ((append "http://h.example" "e=%C3%A9") "http://h.example/?e=%C3%A9")
    ((append "http://h.example" "u=\xE9;") "http://h.example/?u=\xE9;")
    ((append "http://h.example" "q=?/:@!$'()*,;") "http://h.example/?q=?/:@!$'()*,;")
    ((append "http://h.example" "h=#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p?a=1" ,encoder-part) ,(string-append "http://h.example/p?a=1&" encoder-part))
    ((append "http://h.example/p?a=1" ,lower-part) ,(string-append "http://h.example/p?a=1&" lower-part))
    ((append "https://u:pw@H.Example:8443/p/q?a=1#frag" "b=2") "https://u:pw@H.Example:8443/p/q?a=1&b=2#frag")
    ((append "http://[::1]:8080/p" "b=2") "http://[::1]:8080/p?b=2")
    ((append "http://h.example:080/./a/../b?a=1" "b=2") "http://h.example:80/b?a=1&b=2")
    ((append "http://h.example/p\xE9;?q=\xE9;#f\xE9;" "b=2") "http://h.example/p\xE9;?q=\xE9;&b=2#f\xE9;")
    ((append "http://h.example/p#\xFEFF;f" "b=2") "http://h.example/p?b=2#\xFEFF;f")
    ((append "http://h.example/p?a=1#f#g" "b=2") "http://h.example/p?a=1&b=2#f#g")
    ((append "http://h.example/p" "#x") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example/p" "x#") (refused-by-chez-curl query-not-kept))
    ((append "http://h.example:99999/" "b=2") (refused 4))
    ((append "http://caf%E9.example/" "b=2") (refused-by-chez-curl not-utf-8))
    ((parts "http://h.example/p") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))
    ((parts "https://u:pw@H.Example:8443/p/q?a=1&b=2#frag") ("https://u:pw@H.Example:8443/p/q?a=1&b=2#frag" "https" "u" "pw" "H.Example" 8443 "/p/q" "a=1&b=2" "frag"))
    ((parts "HTTP://h.example/p") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))
    ((parts "http://h.example") ("http://h.example/" "http" (absent) (absent) "h.example" 80 "/" (absent) (absent)))
    ((parts "http://h.example:80/p") ("http://h.example:80/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))
    ((parts "https://h.example/") ("https://h.example/" "https" (absent) (absent) "h.example" 443 "/" (absent) (absent)))
    ((parts "http://h.example:080/") ("http://h.example:80/" "http" (absent) (absent) "h.example" 80 "/" (absent) (absent)))
    ((parts "http://h.example:0/") ("http://h.example:0/" "http" (absent) (absent) "h.example" 0 "/" (absent) (absent)))
    ((parts "http://h.example:65535/") ("http://h.example:65535/" "http" (absent) (absent) "h.example" 65535 "/" (absent) (absent)))
    ((parts "http://[::1]:8080/p") ("http://[::1]:8080/p" "http" (absent) (absent) "[::1]" 8080 "/p" (absent) (absent)))
    ((parts "http://u@h.example/") ("http://u@h.example/" "http" "u" (absent) "h.example" 80 "/" (absent) (absent)))
    ((parts "http://h.example/p#") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))
    ((parts "http://h.example/p%3D%3d?x=%3D&y=%3d#f%3D%3d") ("http://h.example/p%3D%3d?x=%3D&y=%3d#f%3D%3d" "http" (absent) (absent) "h.example" 80 "/p%3D%3d" "x=%3D&y=%3d" "f%3D%3d"))
    ((parts "http://us\xE9;r:pw@h.example/") ("http://us\xE9;r:pw@h.example/" "http" "us\xE9;r" "pw" "h.example" 80 "/" (absent) (absent)))
    ((parts "http://u:p\xE9;ss@h.example/") ("http://u:p\xE9;ss@h.example/" "http" "u" "p\xE9;ss" "h.example" 80 "/" (absent) (absent)))
    ((parts "http://caf\xE9;.example/") ("http://caf\xE9;.example/" "http" (absent) (absent) "caf\xE9;.example" 80 "/" (absent) (absent)))
    ((parts "http://h.example/p\xE9;") ("http://h.example/p\xE9;" "http" (absent) (absent) "h.example" 80 "/p\xE9;" (absent) (absent)))
    ((parts "http://h.example/p?q=\xE9;") ("http://h.example/p?q=\xE9;" "http" (absent) (absent) "h.example" 80 "/p" "q=\xE9;" (absent)))
    ((parts "http://h.example/p#f\xE9;") ("http://h.example/p#f\xE9;" "http" (absent) (absent) "h.example" 80 "/p" (absent) "f\xE9;"))
    ((parts "http://us%E9r:pw@h.example/") ("http://us%E9r:pw@h.example/" "http" "us%E9r" "pw" "h.example" 80 "/" (absent) (absent)))
    ((parts "http://u:p%E9ss@h.example/") ("http://u:p%E9ss@h.example/" "http" "u" "p%E9ss" "h.example" 80 "/" (absent) (absent)))
    ((parts "http://caf%E9.example/") ((refused-by-chez-curl not-utf-8) "http" (absent) (absent) (refused-by-chez-curl not-utf-8) 80 "/" (absent) (absent)))
    ((parts "http://h.example/p%E9") ("http://h.example/p%E9" "http" (absent) (absent) "h.example" 80 "/p%E9" (absent) (absent)))
    ((parts "http://h.example/p?q=%E9") ("http://h.example/p?q=%E9" "http" (absent) (absent) "h.example" 80 "/p" "q=%E9" (absent)))
    ((parts "http://h.example/p#f%E9") ("http://h.example/p#f%E9" "http" (absent) (absent) "h.example" 80 "/p" (absent) "f%E9"))
    ((parts "http://caf%e9.example/") ((refused-by-chez-curl not-utf-8) "http" (absent) (absent) (refused-by-chez-curl not-utf-8) 80 "/" (absent) (absent)))
    ((parts "http://caf%C3%A9.example/") ("http://caf\xE9;.example/" "http" (absent) (absent) "caf\xE9;.example" 80 "/" (absent) (absent)))
    ((parts "http://caf%C3.example/") ((refused-by-chez-curl not-utf-8) "http" (absent) (absent) (refused-by-chez-curl not-utf-8) 80 "/" (absent) (absent)))
    ((parts "http://%41.example/") ("http://A.example/" "http" (absent) (absent) "A.example" 80 "/" (absent) (absent)))
    ((parts "http://a%00b.example/") ((refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21)))
    ((parts "http://a%2Fb.example/") ((refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21) (refused 21)))
    ((parts "http://a%2Eb.example/") ("http://a.b.example/" "http" (absent) (absent) "a.b.example" 80 "/" (absent) (absent)))
    ((parts "http://h.example/p?\xFEFF;x") ("http://h.example/p?\xFEFF;x" "http" (absent) (absent) "h.example" 80 "/p" "\xFEFF;x" (absent)))
    ((parts "http://h.example/p#\xFEFF;\xFEFF;y") ("http://h.example/p#\xFEFF;\xFEFF;y" "http" (absent) (absent) "h.example" 80 "/p" (absent) "\xFEFF;\xFEFF;y"))
    ((parts "file:///etc/passwd") ("file:///etc/passwd" "file" (absent) (absent) (absent) 0 "/etc/passwd" (absent) (absent)))
    ((parts "ftp://u@f.example/x") ("ftp://u@f.example/x" "ftp" "u" (absent) "f.example" 21 "/x" (absent) (absent)))
    ((parts "http://h.example:99999/") ((refused 4) (refused 4) (refused 4) (refused 4) (refused 4) (refused 4) (refused 4) (refused 4) (refused 4)))
    ))

;; shared-cases : (Listof Case)
(define shared-cases (map car shared-answers))

;; varying-cases : (Listof Case)
;; The cases shared-answers leaves out, in all-cases' order: what each row
;; of the file answers.
(define varying-cases
  (filter (lambda (a-case) (not (member a-case shared-cases))) all-cases))

;; --- answers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0)))

;; one-answer : (-> Any) -> Any
;; THUNK's answer: a string, a natural, (absent) for #f, (refused CODE) for
;; libcurl's refusal, (refused-by-chez-curl REASON) for chez-curl's own, or
;; (raised TEXT) for anything else.
(define (one-answer thunk)
  (guard (e ((curl-url-error? e)
             (if (curl-url-error-code e)
                 (list 'refused (curl-url-error-code e))
                 (list 'refused-by-chez-curl (curl-url-error-reason e))))
            (#t (list 'raised (describe e))))
    (let ((value (thunk)))
      (if value value '(absent)))))

;; answer : Case -> Any
;; What (curl) answers for CASE, whole: an append's one answer, or a parts
;; case's nine, in part-names' order.
(define (answer a-case)
  (case (car a-case)
    ((append) (one-answer (lambda () (curl-url-append-query (cadr a-case) (caddr a-case)))))
    ((parts) (map (lambda (part) (one-answer (lambda () (curl-url-part (cadr a-case) part))))
                  part-names))
    (else (list 'not-a-case a-case))))

;; answered : Case -> (List Any (Listof (Pairof Symbol Natural)))
;; CASE's answer, and the native counts once it returned.
(define (answered a-case)
  (let ((a (answer a-case)))
    (list a (native-counts))))

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; case-text : Case -> String
;; CASE, its long encoder parts named, for a test's name.
(define (case-text a-case)
  (let ((text (lambda (s)
                (cond ((equal? s encoder-part) "the encoder's every character and byte")
                      ((equal? s lower-part) "every byte in lower case")
                      (else (written s))))))
    (case (car a-case)
      ((append) (string-append "append " (text (caddr a-case)) " to " (text (cadr a-case))))
      (else (string-append "the parts of " (text (cadr a-case)))))))

;; --- the rows, read under a guard ---------------------------------------------------

(define verdicts-file "tests/known-url-part-verdicts.sexp")

;; read-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
;; Every datum of the file at PATH, as test-url reads its file: strict
;; UTF-8, and nothing after an end-of-file mark.
(define (read-data path)
  (guard (e (#t (list 'unreadable (describe e))))
    (call-with-port
     (open-file-input-port path (file-options) (buffer-mode block)
                           (make-transcoder (utf-8-codec) (native-eol-style)
                                            (error-handling-mode raise)))
     (lambda (port)
       (let loop ((found '()))
         (let ((datum (read port)))
           (cond ((not (eof-object? datum)) (loop (cons datum found)))
                 ((port-eof? port) (list 'data (reverse found)))
                 (else (list 'unreadable "text after an end-of-file mark")))))))))

(define file-result (read-data verdicts-file))

(define rows (if (eq? (car file-result) 'data) (cadr file-result) '()))

;; one-shaped? : Any -> Boolean
;; A string, a natural, (absent), (refused CODE) or
;; (refused-by-chez-curl REASON).
(define (one-shaped? x)
  (or (string? x)
      (and (integer? x) (exact? x) (>= x 0))
      (equal? x '(absent))
      (and (list? x) (= (length x) 2) (eq? (car x) 'refused)
           (integer? (cadr x)) (exact? (cadr x)))
      (and (list? x) (= (length x) 2) (eq? (car x) 'refused-by-chez-curl)
           (symbol? (cadr x)))))

;; case-shaped? : Any -> Boolean
(define (case-shaped? x)
  (and (list? x)
       (or (and (= (length x) 3) (eq? (car x) 'append) (string? (cadr x)) (string? (caddr x)))
           (and (= (length x) 2) (eq? (car x) 'parts) (string? (cadr x))))))

;; answer-shaped? : Case Any -> Boolean
;; X answers CASE: one answer for an append, nine for parts.
(define (answer-shaped? a-case x)
  (if (eq? (car a-case) 'append)
      (one-shaped? x)
      (and (list? x) (= (length x) (length part-names)) (for-all one-shaped? x))))

;; row-problem : Any -> (U 'ok (Listof Any))
;; ok when ROW is (libcurl (where S) (version S) (answers (CASE ANSWER) ...)),
;; each CASE and ANSWER well formed; else what is wrong. Total.
(define (row-problem row)
  (cond
    ((not (and (list? row) (= (length row) 4) (eq? (car row) 'libcurl)))
     (list 'not-a-row-of-three-fields row))
    ((not (and (list? (cadr row)) (= (length (cadr row)) 2) (eq? (car (cadr row)) 'where)
               (string? (cadr (cadr row)))))
     (list 'where-is (cadr row)))
    ((not (and (list? (caddr row)) (= (length (caddr row)) 2) (eq? (car (caddr row)) 'version)
               (string? (cadr (caddr row)))))
     (list 'version-is (caddr row)))
    ((not (and (list? (cadddr row)) (pair? (cadddr row)) (eq? (car (cadddr row)) 'answers)))
     (list 'answers-is (cadddr row)))
    ((find (lambda (pair)
             (not (and (list? pair) (= (length pair) 2)
                       (case-shaped? (car pair)) (answer-shaped? (car pair) (cadr pair)))))
           (cdr (cadddr row)))
     => (lambda (pair) (list 'not-a-case-and-an-answer pair)))
    (else 'ok)))

;; row-version : Row -> String
(define (row-version row) (cadr (caddr row)))

;; row-answers : Row -> (Listof (List Case Answer))
(define (row-answers row) (cdr (cadddr row)))

;; rows-for-version : (Listof Any) String -> (Listof Row)
;; The well-formed rows of ROWS whose version is VERSION, in order.
(define (rows-for-version rows version)
  (filter (lambda (row) (and (eq? (row-problem row) 'ok) (string=? (row-version row) version)))
          rows))

;; version-verdict : (Listof Any) String -> (U 'one 'none 'several)
;; Whether ROWS hold exactly one row for VERSION.
(define (version-verdict rows version)
  (let ((n (length (rows-for-version rows version))))
    (cond ((= n 1) 'one) ((= n 0) 'none) (else 'several))))

;; distinct? : (Listof Any) -> Boolean
(define (distinct? xs)
  (or (null? xs) (and (not (member (car xs) (cdr xs))) (distinct? (cdr xs)))))

;; same-cases? : (Listof Case) (Listof Case) -> Boolean
;; Whether A and B hold the same cases, each once.
(define (same-cases? a b)
  (and (distinct? a) (distinct? b) (= (length a) (length b))
       (for-all (lambda (a-case) (member a-case b)) a)
       #t))

;; --- the loaded libcurl, and its row -------------------------------------------------

(define version
  (guard (e (#t (list 'no-version (describe e))))
    (libcurl-info-version (loaded-libcurl))))

(define matches (if (string? version) (rows-for-version rows version) '()))

(define the-row (and (= (length matches) 1) (car matches)))

;; row-text : String -> String
;; The row this libcurl would need: each varying case with what it answers
;; here, ready to paste, its where to be replaced.
(define (row-text version)
  (string-append
   "(libcurl\n"
   " (where \"TODO: say where this libcurl runs\")\n"
   " (version " (written version) ")\n"
   " (answers"
   (apply string-append
          (map (lambda (a-case) (string-append "\n  (" (written a-case) " " (written (answer a-case)) ")"))
               varying-cases))
   "))\n"))

;; No row: say so on the error port, with the row to add.
(when (and (string? version) (not the-row))
  (let ((err (current-error-port)))
    (put-string err
      (string-append
       "test-url-parts: " (if (null? matches) "no row" "more than one row") " of " verdicts-file
       " is for libcurl " version ".\n"
       "test-url-parts: if it is one to support, review its answers, and add this row,\n"
       "test-url-parts: with `where` saying where it runs (ADR-0028):\n\n"
       (row-text version) "\n"))
    (flush-output-port err)))

(test-begin "url-parts")

;; --- the tables cover the cases ---------------------------------------------------------

(test-equal "all-cases: 78 appends and 41 URLs read by part, 119 cases, each once"
  '(78 41 119 distinct)
  (list (length append-cases) (length parts-cases) (length all-cases)
        (if (distinct? all-cases) 'distinct 'repeated)))

(test-equal "shared-answers: each case once, each one of all-cases, and each answer shaped for its case"
  '(distinct () ())
  (list (if (distinct? shared-cases) 'distinct 'repeated)
        (filter (lambda (a-case) (not (member a-case all-cases))) shared-cases)
        (filter (lambda (pair) (not (answer-shaped? (car pair) (cadr pair)))) shared-answers)))

(test-equal "the varying cases are the 6 shared-answers leaves out: a space appended, refused by a code that varies, then an empty user, an empty password, and an empty query, alone and before an empty fragment"
  '((append "http://h.example/p" "s=a b")
    (append "http://h.example/p?a=1#frag" "s=a b")
    (parts "http://:pw@h.example/")
    (parts "http://u:@h.example/")
    (parts "http://h.example/p?")
    (parts "http://h.example/p?#"))
  varying-cases)

;; The decoding's control: shared answers that hold characters past ASCII,
;; where a decoding of each byte as its own character, or U+FFFD for a
;; malformed one, fails them; and refusals as not-utf-8, which U+FFFD would
;; answer as a string.
(test-equal "shared answers hold characters past ASCII, é and U+FEFF among them, and not-utf-8 refusals, so a decoding but strict UTF-8 fails them"
  '(#t #t #t)
  (let ((texts (apply append
                      (map (lambda (pair)
                             (let ((a (cadr pair)))
                               (filter string? (if (eq? (car (car pair)) 'parts) a (list a)))))
                           shared-answers)))
        (refusals (apply append
                         (map (lambda (pair)
                                (let ((a (cadr pair)))
                                  (filter (lambda (x) (equal? x '(refused-by-chez-curl not-utf-8)))
                                          (if (eq? (car (car pair)) 'parts) a (list a)))))
                              shared-answers))))
    (list (>= (length (filter (lambda (s) (exists (lambda (c) (char=? c #\xE9)) (string->list s)))
                              texts))
              10)
          (>= (length (filter (lambda (s) (exists (lambda (c) (char=? c #\xFEFF)) (string->list s)))
                              texts))
              4)
          (>= (length refusals) 6))))

;; --- the file ------------------------------------------------------------------------------

(test-equal "tests/known-url-part-verdicts.sexp reads as data"
  'read
  (if (eq? (car file-result) 'data) 'read file-result))

(test-equal "it holds rows for 7.85.0, 8.5.0 and 8.23.0, the libcurls the lanes run, 8.20.0, the container's, and 8.7.1, Apple's"
  '("7.85.0" "8.5.0" "8.20.0" "8.23.0" "8.7.1")
  (map (lambda (row) (if (eq? (row-problem row) 'ok) (row-version row) row)) rows))

(let loop ((i 1) (rest rows))
  (unless (null? rest)
    (let ((row (car rest)))
      (test-equal (string-append "row " (number->string i)
                                 " is (libcurl (where S) (version S) (answers (CASE ANSWER) ...))")
        'ok
        (row-problem row))
      (test-equal (string-append "row " (number->string i)
                                 " answers exactly the varying cases, each once")
        'exactly
        (if (and (eq? (row-problem row) 'ok)
                 (same-cases? (map car (row-answers row)) varying-cases))
            'exactly
            (if (eq? (row-problem row) 'ok) (map car (row-answers row)) row))))
    (loop (+ i 1) (cdr rest))))

(test-equal "each varying case has different answers in two rows at least: one all rows answer alike is a shared answer"
  '()
  (filter (lambda (a-case)
            (let ((answers (map (lambda (row) (let ((p (assoc a-case (row-answers row)))) (and p (cadr p))))
                                (filter (lambda (row) (eq? (row-problem row) 'ok)) rows))))
              (< (length (fold-left (lambda (seen a) (if (member a seen) seen (cons a seen))) '() answers)) 2)))
          varying-cases))

(test-equal "no two rows share a version"
  'distinct
  (let ((versions (map (lambda (row) (if (eq? (row-problem row) 'ok) (row-version row) row)) rows)))
    (if (distinct? versions) 'distinct versions)))

;; --- the matcher, on made-up rows ---------------------------------------------------------

(define made-up-row
  `(libcurl (where "made up") (version "9.9.9")
            (answers ((parts "http://x/") ("http://x/" "http" (absent) (absent) "x" 80 "/" (absent) (absent))))))

(test-equal "the matcher: a version with one row is one, with none is none, with two is several; a malformed row is never a match"
  '(one none several none)
  (list (version-verdict (list made-up-row) "9.9.9")
        (version-verdict (list made-up-row) "9.9.8")
        (version-verdict (list made-up-row made-up-row) "9.9.9")
        (version-verdict (list '(libcurl (version "9.9.9"))) "9.9.9")))

(test-equal "the shape: a row missing where, a parts answer of eight, an append answered by a list of parts, and a port that is no natural are refused"
  '(rejected rejected rejected rejected ok)
  (map (lambda (row) (if (eq? (row-problem row) 'ok) 'ok 'rejected))
       (list '(libcurl (version "9.9.9") (answers ((parts "http://x/") ("http://x/" "http" (absent) (absent) "x" 80 "/" (absent) (absent)))))
             '(libcurl (where "w") (version "9.9.9") (answers ((parts "http://x/") ("http://x/" "http" (absent) (absent) "x" 80 "/" (absent)))))
             '(libcurl (where "w") (version "9.9.9") (answers ((append "http://x/" "a") ("http://x/?a" "http" (absent) (absent) "x" 80 "/" "a" (absent)))))
             '(libcurl (where "w") (version "9.9.9") (answers ((parts "http://x/") ("http://x/" "http" (absent) (absent) "x" -80 "/" (absent) (absent)))))
             made-up-row)))

(test-equal "the printed row reads back as a well-formed row for this version, answering exactly the varying cases"
  'ok
  (guard (e (#t (list 'raised (describe e))))
    (let ((row (read (open-string-input-port (row-text "9.9.9")))))
      (cond ((not (eq? (row-problem row) 'ok)) (row-problem row))
            ((not (same-cases? (map car (row-answers row)) varying-cases)) (row-answers row))
            (else 'ok)))))

;; --- the guard -----------------------------------------------------------------------------

(test-equal "the loaded libcurl's version has exactly one row in tests/known-url-part-verdicts.sexp"
  (list version)
  (map row-version matches))

;; --- every case, answered whole, the counts back at zero -------------------------------------

(for-each
 (lambda (pair)
   (test-equal (string-append "every libcurl: " (case-text (car pair))
                              " is the shared answer, and the counts are back at zero")
     (list (cadr pair) zero-counts)
     (answered (car pair))))
 shared-answers)

(for-each
 (lambda (a-case)
   (test-equal (string-append "libcurl " (if (string? version) version "?") ": " (case-text a-case)
                              " is its row's answer, and the counts are back at zero")
     (list (if the-row
               (let ((pair (assoc a-case (row-answers the-row))))
                 (if pair (cadr pair) (list 'no-answer-in-its-row a-case)))
               (list 'no-row version))
           zero-counts)
     (answered a-case)))
 varying-cases)

;; --- the refusals' conditions ------------------------------------------------------------------

;; refusal : (-> Any) -> Any
;; What THUNK raised, as a &curl-url-error's fields, its message's type for
;; the message; (assertion WHO) for an assertion violation; (other TEXT)
;; for any other raise, or (no-raise VALUE).
(define (refusal thunk)
  (guard (e ((curl-url-error? e)
             (list (curl-url-error-reason e) (curl-url-error-code e) (curl-url-error-input e)
                   (let ((m (curl-url-error-message e)))
                     (if (and (string? m) (> (string-length m) 0)) 'a-message m))))
            ((and (assertion-violation? e) (who-condition? e))
             (list 'assertion (condition-who e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (thunk))))

;; refusal-at-raise : (-> Any) -> (List Any (Listof (Pairof Symbol Natural)))
;; refusal's answer for THUNK, and the native counts at the moment of the
;; raise, read by a handler that runs before any dynamic-wind's after thunk,
;; then raises on.
(define (refusal-at-raise thunk)
  (let* ((seen 'no-raise)
         (r (refusal (lambda ()
                       (with-exception-handler
                         (lambda (c) (set! seen (native-counts)) (raise c))
                         thunk)))))
    (list r seen)))

(test-equal "a part libcurl gives back as bytes that are not UTF-8: curl-url-part refuses the host, and the URL, as not-utf-8, with no code, naming the URL; its path it answers"
  (list '(not-utf-8 #f "http://caf%E9.example/" a-message)
        '(not-utf-8 #f "http://caf%E9.example/" a-message)
        '(no-raise "/")
        zero-counts)
  (let* ((host (refusal (lambda () (curl-url-part "http://caf%E9.example/" 'host))))
         (url (refusal (lambda () (curl-url-part "http://caf%E9.example/" 'url))))
         (path (refusal (lambda () (curl-url-part "http://caf%E9.example/" 'path))))
         (counts (native-counts)))
    (list host url path counts)))

(test-equal "the same rule holds for every URL function: url-normalize names the URL, url-resolve the reference that made the host, and the scheme check, which a submit runs, the URL"
  (list '(not-utf-8 #f "http://caf%E9.example/" a-message)
        '(not-utf-8 #f "//caf%E9.example/x" a-message)
        '(not-utf-8 #f "http://caf%C3.example/" a-message)
        zero-counts)
  (let* ((normalized (refusal (lambda () (url-normalize "http://caf%E9.example/"))))
         (resolved (refusal (lambda () (url-resolve "http://h.example/a" "//caf%E9.example/x"))))
         (checked (refusal (lambda ()
                             (call-with-parsed-url "http://caf%C3.example/"
                               (lambda (handle)
                                 (require-http-scheme handle "http://caf%C3.example/"))))))
         (counts (native-counts)))
    (list normalized resolved checked counts)))

(test-equal "a submit of a URL whose host decodes to bytes that are not UTF-8 is refused on the caller's thread, as not-utf-8, and nothing is left once the engine stops"
  (list '(not-utf-8 #f "http://caf%E9.example/" a-message) zero-counts)
  (guard (e (#t (list 'raised (describe e))))
    (let ((engine (make-curl-engine)))
      (let ((r (refusal (lambda () (curl-submit engine (make-curl-request "http://caf%E9.example/"))))))
        (curl-engine-stop engine)
        (list r (native-counts))))))

(test-equal "curl-url-append-query: a URL libcurl refuses is named, with libcurl's code; one whose host is not UTF-8, as not-utf-8"
  (list '(bad-port-number 4 "http://h.example:99999/" a-message)
        '(not-utf-8 #f "http://caf%E9.example/" a-message)
        zero-counts)
  (let* ((port (refusal (lambda () (curl-url-append-query "http://h.example:99999/" "b=2"))))
         (host (refusal (lambda () (curl-url-append-query "http://caf%E9.example/" "b=2"))))
         (counts (native-counts)))
    (list port host counts)))

(test-equal "curl-url-append-query: the string it writes, when libcurl refuses it, is what the refusal names: a space in a part"
  (list "http://h.example/p?a=1&s=a b#frag" 'a-code zero-counts)
  (let* ((r (refusal (lambda () (curl-url-append-query "http://h.example/p?a=1#frag" "s=a b"))))
         (counts (native-counts)))
    (list (if (and (list? r) (= (length r) 4)) (caddr r) r)
          (if (and (list? r) (= (length r) 4) (integer? (cadr r))) 'a-code r)
          counts)))

(test-equal "curl-url-append-query: a part holding #, first, inside or last, is refused as query-not-kept, with no code, naming the part"
  (list '(query-not-kept #f "#a" a-message)
        '(query-not-kept #f "a#b" a-message)
        '(query-not-kept #f "a#" a-message)
        zero-counts)
  (let* ((first (refusal (lambda () (curl-url-append-query "http://h.example/p?q=1" "#a"))))
         (inside (refusal (lambda () (curl-url-append-query "http://h.example/p?q=1" "a#b"))))
         (last (refusal (lambda () (curl-url-append-query "http://h.example/p?q=1#f" "a#"))))
         (counts (native-counts)))
    (list first inside last counts)))

;; A NUL in the part, at every place a scan can miss: first, inside, last,
;; the whole part, and between é and λ. Each refused before libcurl sees
;; it, so with no handle and no block at the raise.
(for-each
 (lambda (part)
   (test-equal (string-append "curl-url-append-query refuses the part " (written part)
                              " as &curl-url-error, embedded-nul, naming the part, with no handle or block at the raise")
     (list (list (list 'embedded-nul #f part 'a-message) zero-counts) zero-counts)
     (let ((r (refusal-at-raise (lambda () (curl-url-append-query "http://h.example/" part)))))
       (list r (native-counts)))))
 '("\x0;b" "b\x0;c" "b\x0;" "\x0;" "\xE9;\x0;\x3BB;"))

(test-equal "a NUL in the URL, for either function, is refused the same way, naming the URL"
  (list (list (list 'embedded-nul #f "http://a/\x0;b" 'a-message) zero-counts)
        (list (list 'embedded-nul #f "http://a/\x0;b" 'a-message) zero-counts)
        zero-counts)
  (let* ((part (refusal-at-raise (lambda () (curl-url-part "http://a/\x0;b" 'host))))
         (appended (refusal-at-raise (lambda () (curl-url-append-query "http://a/\x0;b" "b=2"))))
         (counts (native-counts)))
    (list part appended counts)))

(test-equal "what is no URL, no part's name, or no query part is an assertion violation from the function called"
  '((assertion curl-url-part) (assertion curl-url-part) (assertion curl-url-part)
    (assertion curl-url-append-query) (assertion curl-url-append-query))
  (list (refusal (lambda () (curl-url-part 42 'host)))
        (refusal (lambda () (curl-url-part "http://a/" 'zoneid)))
        (refusal (lambda () (curl-url-part "http://a/" "host")))
        (refusal (lambda () (curl-url-append-query #f "b=2")))
        (refusal (lambda () (curl-url-append-query "http://a/" 42)))))

;; --- the string written, by tables ---------------------------------------------------------
;; appended-url is the append's string assembly, pure, so these rows reach
;; what no libcurl measured gives: a ? kept for an empty query, a "" query
;; or fragment, and a "" fragment the URL lacks (ADR-0028). Each row is
;; WHOLE, QUERY, FRAGMENT and PART, as curl_url_get would give the first
;; three, then the string written and the query it must read back.

(define appended-rows
  '(("http://h/p" #f #f "b=2" ("http://h/p?b=2" "b=2"))
    ("http://h/p?a=1" "a=1" #f "b=2" ("http://h/p?a=1&b=2" "a=1&b=2"))
    ("http://h/p?a=1&" "a=1&" #f "b=2" ("http://h/p?a=1&b=2" "a=1&b=2"))
    ("http://h/p?a=1" "a=1" #f "" ("http://h/p?a=1&" "a=1&"))
    ("http://h/p" "" #f "b=2" ("http://h/p?b=2" "b=2"))
    ("http://h/p?" "" #f "b=2" ("http://h/p?b=2" "b=2"))
    ("http://h/p?" #f #f "b=2" ("http://h/p?b=2" "b=2"))
    ("http://h/p#f" #f "f" "b=2" ("http://h/p?b=2#f" "b=2"))
    ("http://h/p?a=1#f" "a=1" "f" "b=2" ("http://h/p?a=1&b=2#f" "a=1&b=2"))
    ("http://h/p?#f" "" "f" "b=2" ("http://h/p?b=2#f" "b=2"))
    ("http://h/p#a#b" #f "a#b" "x" ("http://h/p?x#a#b" "x"))
    ("http://h/p" #f "" "b=2" ("http://h/p?b=2" "b=2"))
    ("http://h/p#" #f "" "b=2" ("http://h/p?b=2#" "b=2"))))

(test-equal "appended-url writes each row's string and query: ? or & by the query, none after a trailing &, the fragment kept at the end; a ? kept for an empty query is dropped, and a \"\" fragment the URL lacks adds no #"
  (map (lambda (row) (list-ref row 4)) appended-rows)
  (map (lambda (row)
         (guard (e (#t (list 'raised (describe e))))
           (apply appended-url (list-head row 4))))
       appended-rows))

(test-equal "appended-url refuses a non-empty fragment that is not the URL's end, an error from curl-url-append-query"
  '(error curl-url-append-query)
  (guard (e ((and (error? e) (who-condition? e)) (list 'error (condition-who e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (appended-url "http://h/p" #f "zz" "b=2"))))

;; --- check-then-use: a part another thread changes -----------------------------------------
;; curl-url-append-query checks a copy of its part, and writes that copy
;; into the URL. Writing the caller's string instead lets a second thread
;; put a NUL in between: the check of the part passes, and the URL written
;; holds the NUL, refused then as the URL, not the part. Here a thread flips
;; one char of the part between a and U+0000: each answer is the part
;; refused as embedded-nul, naming the part, or the URL with the part
;; whole.

;; flipped-append : Natural -> (List (Listof Any) (Listof Symbol) Counts)
;; N appends of b=xax to http://h.example/p, its a flipped: the answers that
;; are neither, which of the two were seen, and the counts after.
(define (flipped-append n)
  (let* ((s (string-copy "b=xax"))
         (stop #f)
         (yield (lambda () (sleep (make-time 'time-duration 0 0))))
         (pause (lambda () (sleep (make-time 'time-duration 1000000 0))))
         (flip (lambda ()
                 (let loop ((i 0))
                   (when (< i 100000)
                     (string-set! s 3 #\nul)
                     (string-set! s 3 #\a)
                     (loop (+ i 1))))))
         (flipper (fork-thread (lambda ()
                                 (let loop ()
                                   (unless stop
                                     (flip)
                                     (yield)
                                     (flip)
                                     (string-set! s 3 #\nul)
                                     (yield)
                                     (loop)))))))
    (dynamic-wind
      (lambda () #f)
      (lambda ()
        (let loop ((i 0) (odd '()) (seen '()))
          (if (= i n)
              (list (reverse odd) (filter (lambda (k) (memq k seen)) '(refused whole)) (native-counts))
              ;; A sleep of a millisecond before every tenth, as test-url's
              ;; flip test: under Valgrind a sleep of no time could hand this
              ;; thread the lock straight back, and starve the flipper.
              (let ((o (let ((a (begin (when (= (mod i 10) 0) (pause))
                                       (guard (e ((curl-url-error? e)
                                                  (list 'refused (curl-url-error-reason e)
                                                        (curl-url-error-input e)))
                                                 (#t (list 'raised (describe e))))
                                         (curl-url-append-query "http://h.example/p" s)))))
                         (cond ((equal? a '(refused embedded-nul "b=x\x0;x")) 'refused)
                               ((equal? a "http://h.example/p?b=xax") 'whole)
                               (else a)))))
                (loop (+ i 1)
                      (if (memq o '(refused whole)) odd (cons o odd))
                      (if (memq o seen) seen (cons o seen)))))))
      (lambda () (set! stop #t) (thread-join flipper)))))

(test-equal "curl-url-append-query, while another thread flips a char of its part to U+0000: 1000 answers each the part refused as embedded-nul, naming the part, or the URL with the part whole, both seen, and nothing left"
  (list '() '(refused whole) zero-counts)
  (flipped-append 1000))

;; --- asynchronous escapes: an engine's fuel running out anywhere ------------------------

;; engine-sweep : (-> Any) Natural -> (List Symbol Natural)
;; (completed EXPIRED), EXPIRED the engines that ran out first; or
;; (never-completed EXPIRED) past 100000 fuel.
(define (engine-sweep thunk step)
  (let loop ((fuel 1) (expired 0))
    (cond ((> fuel 100000) (list 'never-completed expired))
          (((make-engine thunk) fuel (lambda (ticks v) #t) (lambda (e) #f)) (list 'completed expired))
          (else (loop (+ fuel step) (+ expired 1))))))

;; swept : (List Symbol Natural) -> Any
;; completed-after-expiries when the sweep completed after more than ten
;; engines ran out, its positive evidence; else the sweep itself.
(define (swept result)
  (if (and (eq? (car result) 'completed) (> (cadr result) 10)) 'completed-after-expiries result))

(for-each
 (lambda (row)
   (test-equal (string-append (car row) " in an engine that runs out at every tick, each abandoned, until one completes: it completes, and no native object is left, no CURLU and no string libcurl made")
     (list 'completed-after-expiries zero-counts)
     (let* ((sweep (swept (engine-sweep (cadr row) 1)))
            (counts (native-counts)))
       (list sweep counts))))
 (list (list "curl-url-part" (lambda () (curl-url-part "http://u:p@h.example:8080/a?b#c" 'port)))
       (list "curl-url-append-query"
             (lambda () (curl-url-append-query "http://h.example/a?b=1#c" "d=%2B")))))

(test-end "url-parts")

(exit (suite-exit-status runner))
