#!r6rs
;;; M5 slice 2's review asked (2026-10-28): what if a Location's bytes were
;;; encoded by ADR-0029's rule, encoded-bytes, before curl-url-resolve,
;;; as curl-url-with-fragment encodes a fragment's?
;;;
;;;   scheme --libdirs src --program encoded.sps
;;;
;;; Prints, for each Location value: NAME, then raw=, curl-url-resolve of
;;; the bytes as they are, and enc=, of the bytes encoded first: each byte
;;; at or below 0x20, 0x7F and each above 0x7F as upper-case %XX, every
;;; other kept. An answer is the URL, written, or (refused CODE), or
;;; (refused-by-chez-curl REASON). The values are the location probe's, as
;;; test-url-location holds them, then absolute and network-path ones that
;;; hold the same bytes.
;;;
;;; The results in results/encoded-*.log came from the tree before the
;;; maintainer's choice: curl-url-resolve then sent a bytevector's bytes as
;;; they were. It now encodes them itself (ADR-0029, amended), so raw= and
;;; enc= now give one answer; encoded-bytes was then named
;;; fragment-encoded.
(import (rnrs)
        (curl)
        (only (curl private url) encoded-bytes))

(define (bytes s) (u8-list->bytevector (map char->integer (string->list s))))

(define (base name) (string-append "http://127.0.0.1:40001/a/b/c/" name "?q=1"))

(define values-to-try
  '(("rel-abs" "/x/y?z=1") ("rel-path" "d/e") ("rel-dots" "../../up") ("rel-query" "?only=1")
    ("netpath" "//127.0.0.1:40001/np") ("other-host" "http://other.invalid/x")
    ("https" "https://127.0.0.1:1/s") ("no-path" "http://127.0.0.1:40001")
    ("upper-scheme" "HTTP://127.0.0.1:40001/UP") ("ftp" "ftp://127.0.0.1/f")
    ("file" "file:///etc/passwd") ("javascript" "javascript:alert(1)")
    ("unknown-scheme" "foo://bar/x") ("padded" "/padded") ("tab" "/tabbed")
    ("space-inside" "/a b/c d") ("utf8" "/caf\xC3;\xA9;") ("latin1" "/caf\xE9;")
    ("ctl" "/x\x1;y") ("del" "/x\x7F;y") ("pct" "/already%20encoded") ("bad-pct" "/bad%zz")
    ("userinfo" "http://u:p@127.0.0.1:40001/creds") ("frag-abs" "/withfrag#f")
    ("bad-ipv6" "http://[::1/x") ("bad-port" "http://127.0.0.1:99999/x")
    ("backslash" "/\\evil.invalid/x") ("idn" "http://caf\xC3;\xA9;.invalid/")
    ("latin1-host" "http://caf\xE9;.invalid/")
    ("abs-latin1-path" "http://h.example/caf\xE9;") ("abs-latin1-query" "http://h.example/?q=caf\xE9;")
    ("abs-utf8-path" "http://h.example/caf\xC3;\xA9;") ("net-latin1-path" "//h.example/caf\xE9;")
    ("rel-latin1-query" "?q=caf\xE9;") ("abs-ctl" "http://h.example/x\x1;y")
    ("abs-del" "http://h.example/x\x7F;y") ("abs-space" "http://h.example/a b")
    ("abs-tab-inside" "http://h.example/a\tb") ("rel-tab-inside" "/a\tb")
    ("abs-latin1-frag" "http://h.example/p#caf\xE9;") ("rel-latin1-frag" "/p#caf\xE9;")
    ("space-host" "http://exa mple.com/") ("abs-pct-lower" "http://h.example/%e9")
    ("rel-pct-lower" "/%e9") ("abs-latin1-user" "http://caf\xE9;:p@h.example/")))

(define (answer thunk)
  (guard (e ((curl-url-error? e)
             (if (curl-url-error-code e)
                 (list 'refused (curl-url-error-code e))
                 (list 'refused-by-chez-curl (curl-url-error-reason e))))
            (#t (list 'raised (condition-message e))))
    (thunk)))

(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

(put-string (current-output-port)
            (string-append "libcurl " (libcurl-info-version (loaded-libcurl)) "\n"))
(for-each
 (lambda (pair)
   (let* ((b (bytes (cadr pair)))
          (raw (answer (lambda () (curl-url-resolve (base (car pair)) b))))
          (enc (answer (lambda () (curl-url-resolve (base (car pair)) (encoded-bytes b))))))
     (put-string (current-output-port)
                 (string-append (car pair) " raw=" (written raw) " enc=" (written enc) "\n"))))
 values-to-try)
(put-string (current-output-port)
            (string-append "-- " (number->string (length values-to-try)) " values\n"))
