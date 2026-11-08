#!r6rs
;;; The suite for (curl)'s two URL functions for a redirect's Location,
;;; curl-url-resolve with a bytevector reference and curl-url-with-fragment
;;; (the M5 plan, sections 3.1 and 5; ADR-0029).
;;;
;;; Its cases are M5 slice 2's measurement's (.plans/research/m5/location/),
;;; written once, in all-cases:
;;;
;;;   - (resolve BASE REFERENCE): curl-url-resolve. Each Location value the
;;;     probe's server wrote, as libcurl's header API hands it over, trimmed,
;;;     as bytes, against the probe's base for it, its port written as 40001;
;;;     then against a base with credentials and one with a fragment, as the
;;;     probe ran them; a lone CR, which 8.5.0 hands over for an empty value;
;;;     a Latin-1 host, refused as not-utf-8; é as a string, sent as
;;;     UTF-8, beside the same Latin-1 byte as bytes; and the review's eight,
;;;     a Latin-1 byte, a control byte or a space in an absolute URL, which a
;;;     reference's bytes, encoded first, make alike on every libcurl
;;;     (ADR-0029, amended);
;;;   - (fragment URL FRAGMENT): curl-url-with-fragment. The probe's three
;;;     URLs, each with its twenty fragments as a header's bytes, and as the
;;;     strings their text makes, "" and no bytes among them; and #f.
;;;
;;; curl's verdicts vary by version, so, as test-url and test-url-parts do:
;;;
;;;   - shared-answers holds the answer every recorded libcurl gives;
;;;   - tests/known-url-location-verdicts.sexp holds a row per libcurl
;;;     version, 7.85.0, 8.5.0, 8.20.0, 8.23.0 and Apple's 8.7.1, with that
;;;     version's answer to each case shared-answers leaves out. It is a file
;;;     of its own, so a libcurl not yet run fails this suite alone.
;;;
;;; The two cover the cases exactly, each once. A libcurl whose version has
;;; no row fails here, and the suite prints the row it would need on the
;;; error port (ADR-0017). Every answer is asserted whole, with the native
;;; counts after it, which must all be zero: the URL, (refused CODE) for
;;; libcurl's refusal, or (refused-by-chez-curl REASON) for chez-curl's own.
;;;
;;; Then the two references of 8,001 and 90,001 bytes, too long to write out;
;;; the refusals' conditions, field by field, a bytevector named by its
;;; bytes read as Latin-1; 0x00 and U+0000 at every place; encoded-bytes
;;; over every byte, against the whole complement of the bytes it keeps;
;;; fragment-url by tables; a reference and a fragment another thread
;;; changes; and both functions escaped at every tick.
;;;
;;; Every expected value is one the code under test cannot produce by
;;; failing: SRFI-64 makes #f of a raise in the actual expression, so none
;;; is #f.
(import (rnrs)
        (srfi :64)
        (curl-testing)
        (curl)
        (only (curl private url) fragment-url encoded-bytes)
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

;; bytes : String -> Bytevector
;; S, whose chars are all below U+0100, as one byte per char: a header's
;; Latin-1 string as its bytes.
(define (bytes s) (u8-list->bytevector (map char->integer (string->list s))))

;; A case writes a header's bytes as (bytes S), S their Latin-1 string, so
;; the tables and the rows read as text; argument makes the bytevector a
;; case's function is called with.
(define (as-bytes s) (list 'bytes s))

;; argument : Any -> Any
(define (argument x)
  (if (and (pair? x) (eq? (car x) 'bytes)) (bytes (cadr x)) x))

;; base : String -> String
;; The probe's request URL for its case NAME, its port written as 40001.
(define (base name) (string-append "http://127.0.0.1:40001/a/b/c/" name "?q=1"))

;; location-values : (Listof (List String String))
;; Each Location the probe's server wrote but the two that fail the
;; transfer and the two too long to write out, by its case's name, as
;; libcurl's header API hands it over: trimmed of the whitespace around it.
;; {PORT} is written 40001. s301 stands for the eleven statuses, each /s.
(define location-values
  '(("rel-abs" "/x/y?z=1") ("rel-path" "d/e") ("rel-dots" "../../up") ("rel-query" "?only=1")
    ("rel-frag" "#only") ("netpath" "//127.0.0.1:40001/np") ("other-host" "http://other.invalid/x")
    ("https" "https://127.0.0.1:1/s") ("no-path" "http://127.0.0.1:40001")
    ("upper-scheme" "HTTP://127.0.0.1:40001/UP") ("ftp" "ftp://127.0.0.1/f")
    ("file" "file:///etc/passwd") ("javascript" "javascript:alert(1)")
    ("unknown-scheme" "foo://bar/x") ("empty" "") ("padded" "/padded") ("tab" "/tabbed")
    ("space-inside" "/a b/c d") ("utf8" "/caf\xC3;\xA9;") ("latin1" "/caf\xE9;")
    ("ctl" "/x\x1;y") ("del" "/x\x7F;y") ("pct" "/already%20encoded") ("bad-pct" "/bad%zz")
    ("userinfo" "http://u:p@127.0.0.1:40001/creds") ("frag-abs" "/withfrag#f")
    ("bad-ipv6" "http://[::1/x") ("bad-port" "http://127.0.0.1:99999/x")
    ("backslash" "/\\evil.invalid/x") ("lower-name" "/lc") ("idn" "http://caf\xC3;\xA9;.invalid/")
    ("s301" "/s")))

(define (value-of name) (cadr (assoc name location-values)))

;; review-values : (Listof (List String String))
;; Values the slice's review added, which the probe's server never wrote:
;; a Latin-1 byte in an absolute URL's path, query, user and fragment, and
;; behind a network path and a query alone; a control byte and a space in
;; an absolute URL. Resolved raw, the first four came back as bytes that
;; are not UTF-8, refused, where a relative path's came back encoded
;; (ADR-0029, amended).
(define review-values
  '(("abs-latin1-path" "http://h.example/caf\xE9;") ("abs-latin1-query" "http://h.example/?q=caf\xE9;")
    ("abs-latin1-user" "http://caf\xE9;:p@h.example/") ("abs-latin1-frag" "http://h.example/p#caf\xE9;")
    ("net-latin1-path" "//h.example/caf\xE9;") ("rel-latin1-query" "?q=caf\xE9;")
    ("abs-ctl" "http://h.example/x\x1;y") ("abs-space" "http://h.example/a b")))

(define resolve-cases
  (append
   (map (lambda (pair) (list 'resolve (base (car pair)) (as-bytes (cadr pair)))) location-values)
   (map (lambda (name)
          (list 'resolve (string-append "http://me:secret@127.0.0.1:40001/a/b/c/" name "?q=1")
                (as-bytes (value-of name))))
        '("rel-abs" "netpath" "other-host"))
   (map (lambda (name) (list 'resolve (string-append (base name) "#orig") (as-bytes (value-of name))))
        '("rel-abs" "rel-frag" "frag-abs" "netpath"))
   (map (lambda (pair) (list 'resolve (base (car pair)) (as-bytes (cadr pair)))) review-values)
   (list (list 'resolve (base "empty") (as-bytes "\r"))
         (list 'resolve (base "latin1-host") (as-bytes "http://caf\xE9;.invalid/"))
         (list 'resolve (base "latin1") "/caf\xE9;"))))

(define fragment-bases
  '("http://h.example/a/b?q=1" "http://h.example/a/b?q=1#old" "http://h.example/a/b#old%e9"))

;; fragment-bytes : (Listof String)
;; fragment.c's twenty fragments, each as a header's Latin-1 string.
(define fragment-bytes
  '("only" "" "a b" "   " "\t" "\r" "caf\xE9;" "caf\xC3;\xA9;" "\xEF;\xBB;\xBF;bom" "%e9x" "%E9x"
    "%c3%A9" "%zz" "%" "a#b" "x\x1;y" "x\x7F;y" "\"<>`{}|^" "a?b/c:d@e!$&'()*+,;=" "a\\b"))

;; fragment-strings : (Listof String)
;; The text the same bytes make as UTF-8, as a string fragment holds it:
;; caf\xE9 is no UTF-8, so é stands for both.
(define fragment-strings
  '("only" "" "a b" "   " "\t" "\r" "caf\xE9;" "\xFEFF;bom" "%e9x" "%E9x" "%c3%A9" "%zz" "%"
    "a#b" "x\x1;y" "x\x7F;y" "\"<>`{}|^" "a?b/c:d@e!$&'()*+,;=" "a\\b"))

(define fragment-cases
  (apply append
         (map (lambda (url)
                (append (map (lambda (f) (list 'fragment url (as-bytes f))) fragment-bytes)
                        (map (lambda (f) (list 'fragment url f)) fragment-strings)
                        (list (list 'fragment url #f))))
              fragment-bases)))

(define all-cases (append resolve-cases fragment-cases))

;; shared-answers : (Listof (List Case Answer))
;; The answer every recorded libcurl gives, for each case they agree on.
(define shared-answers
  '(((resolve "http://127.0.0.1:40001/a/b/c/rel-abs?q=1" (bytes "/x/y?z=1")) "http://127.0.0.1:40001/x/y?z=1")
    ((resolve "http://127.0.0.1:40001/a/b/c/rel-path?q=1" (bytes "d/e")) "http://127.0.0.1:40001/a/b/c/d/e")
    ((resolve "http://127.0.0.1:40001/a/b/c/rel-dots?q=1" (bytes "../../up")) "http://127.0.0.1:40001/a/up")
    ((resolve "http://127.0.0.1:40001/a/b/c/rel-query?q=1" (bytes "?only=1")) "http://127.0.0.1:40001/a/b/c/rel-query?only=1")
    ((resolve "http://127.0.0.1:40001/a/b/c/netpath?q=1" (bytes "//127.0.0.1:40001/np")) "http://127.0.0.1:40001/np")
    ((resolve "http://127.0.0.1:40001/a/b/c/other-host?q=1" (bytes "http://other.invalid/x")) "http://other.invalid/x")
    ((resolve "http://127.0.0.1:40001/a/b/c/https?q=1" (bytes "https://127.0.0.1:1/s")) "https://127.0.0.1:1/s")
    ((resolve "http://127.0.0.1:40001/a/b/c/no-path?q=1" (bytes "http://127.0.0.1:40001")) "http://127.0.0.1:40001/")
    ((resolve "http://127.0.0.1:40001/a/b/c/upper-scheme?q=1" (bytes "HTTP://127.0.0.1:40001/UP")) "http://127.0.0.1:40001/UP")
    ((resolve "http://127.0.0.1:40001/a/b/c/ftp?q=1" (bytes "ftp://127.0.0.1/f")) "ftp://127.0.0.1/f")
    ((resolve "http://127.0.0.1:40001/a/b/c/file?q=1" (bytes "file:///etc/passwd")) "file:///etc/passwd")
    ((resolve "http://127.0.0.1:40001/a/b/c/unknown-scheme?q=1" (bytes "foo://bar/x")) (refused 5))
    ((resolve "http://127.0.0.1:40001/a/b/c/padded?q=1" (bytes "/padded")) "http://127.0.0.1:40001/padded")
    ((resolve "http://127.0.0.1:40001/a/b/c/tab?q=1" (bytes "/tabbed")) "http://127.0.0.1:40001/tabbed")
    ((resolve "http://127.0.0.1:40001/a/b/c/space-inside?q=1" (bytes "/a b/c d")) "http://127.0.0.1:40001/a%20b/c%20d")
    ((resolve "http://127.0.0.1:40001/a/b/c/utf8?q=1" (bytes "/caf\xC3;\xA9;")) "http://127.0.0.1:40001/caf%C3%A9")
    ((resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" (bytes "/caf\xE9;")) "http://127.0.0.1:40001/caf%E9")
    ((resolve "http://127.0.0.1:40001/a/b/c/ctl?q=1" (bytes "/x\x1;y")) "http://127.0.0.1:40001/x%01y")
    ((resolve "http://127.0.0.1:40001/a/b/c/del?q=1" (bytes "/x\x7F;y")) "http://127.0.0.1:40001/x%7Fy")
    ((resolve "http://127.0.0.1:40001/a/b/c/pct?q=1" (bytes "/already%20encoded")) "http://127.0.0.1:40001/already%20encoded")
    ((resolve "http://127.0.0.1:40001/a/b/c/bad-pct?q=1" (bytes "/bad%zz")) "http://127.0.0.1:40001/bad%zz")
    ((resolve "http://127.0.0.1:40001/a/b/c/userinfo?q=1" (bytes "http://u:p@127.0.0.1:40001/creds")) "http://u:p@127.0.0.1:40001/creds")
    ((resolve "http://127.0.0.1:40001/a/b/c/frag-abs?q=1" (bytes "/withfrag#f")) "http://127.0.0.1:40001/withfrag#f")
    ((resolve "http://127.0.0.1:40001/a/b/c/bad-port?q=1" (bytes "http://127.0.0.1:99999/x")) (refused 4))
    ((resolve "http://127.0.0.1:40001/a/b/c/backslash?q=1" (bytes "/\\evil.invalid/x")) "http://127.0.0.1:40001/\\evil.invalid/x")
    ((resolve "http://127.0.0.1:40001/a/b/c/lower-name?q=1" (bytes "/lc")) "http://127.0.0.1:40001/lc")
    ((resolve "http://127.0.0.1:40001/a/b/c/idn?q=1" (bytes "http://caf\xC3;\xA9;.invalid/")) "http://caf\xE9;.invalid/")
    ((resolve "http://127.0.0.1:40001/a/b/c/s301?q=1" (bytes "/s")) "http://127.0.0.1:40001/s")
    ((resolve "http://me:secret@127.0.0.1:40001/a/b/c/rel-abs?q=1" (bytes "/x/y?z=1")) "http://me:secret@127.0.0.1:40001/x/y?z=1")
    ((resolve "http://me:secret@127.0.0.1:40001/a/b/c/netpath?q=1" (bytes "//127.0.0.1:40001/np")) "http://127.0.0.1:40001/np")
    ((resolve "http://me:secret@127.0.0.1:40001/a/b/c/other-host?q=1" (bytes "http://other.invalid/x")) "http://other.invalid/x")
    ((resolve "http://127.0.0.1:40001/a/b/c/rel-abs?q=1#orig" (bytes "/x/y?z=1")) "http://127.0.0.1:40001/x/y?z=1")
    ((resolve "http://127.0.0.1:40001/a/b/c/frag-abs?q=1#orig" (bytes "/withfrag#f")) "http://127.0.0.1:40001/withfrag#f")
    ((resolve "http://127.0.0.1:40001/a/b/c/netpath?q=1#orig" (bytes "//127.0.0.1:40001/np")) "http://127.0.0.1:40001/np")
    ((resolve "http://127.0.0.1:40001/a/b/c/abs-latin1-path?q=1" (bytes "http://h.example/caf\xE9;")) "http://h.example/caf%E9")
    ((resolve "http://127.0.0.1:40001/a/b/c/abs-latin1-query?q=1" (bytes "http://h.example/?q=caf\xE9;")) "http://h.example/?q=caf%E9")
    ((resolve "http://127.0.0.1:40001/a/b/c/abs-latin1-user?q=1" (bytes "http://caf\xE9;:p@h.example/")) "http://caf%E9:p@h.example/")
    ((resolve "http://127.0.0.1:40001/a/b/c/abs-latin1-frag?q=1" (bytes "http://h.example/p#caf\xE9;")) "http://h.example/p#caf%E9")
    ((resolve "http://127.0.0.1:40001/a/b/c/net-latin1-path?q=1" (bytes "//h.example/caf\xE9;")) "http://h.example/caf%E9")
    ((resolve "http://127.0.0.1:40001/a/b/c/rel-latin1-query?q=1" (bytes "?q=caf\xE9;")) "http://127.0.0.1:40001/a/b/c/rel-latin1-query?q=caf%E9")
    ((resolve "http://127.0.0.1:40001/a/b/c/abs-ctl?q=1" (bytes "http://h.example/x\x1;y")) "http://h.example/x%01y")
    ((resolve "http://127.0.0.1:40001/a/b/c/abs-space?q=1" (bytes "http://h.example/a b")) "http://h.example/a%20b")
    ((resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes "\r")) "http://127.0.0.1:40001/a/b/c/%0D")
    ((resolve "http://127.0.0.1:40001/a/b/c/latin1-host?q=1" (bytes "http://caf\xE9;.invalid/")) (refused-by-chez-curl not-utf-8))
    ((fragment "http://h.example/a/b?q=1" (bytes "only")) "http://h.example/a/b?q=1#only")
    ((fragment "http://h.example/a/b?q=1" (bytes "")) "http://h.example/a/b?q=1")
    ((fragment "http://h.example/a/b?q=1" (bytes "a b")) "http://h.example/a/b?q=1#a%20b")
    ((fragment "http://h.example/a/b?q=1" (bytes "   ")) "http://h.example/a/b?q=1#%20%20%20")
    ((fragment "http://h.example/a/b?q=1" (bytes "\t")) "http://h.example/a/b?q=1#%09")
    ((fragment "http://h.example/a/b?q=1" (bytes "\r")) "http://h.example/a/b?q=1#%0D")
    ((fragment "http://h.example/a/b?q=1" (bytes "caf\xE9;")) "http://h.example/a/b?q=1#caf%E9")
    ((fragment "http://h.example/a/b?q=1" (bytes "caf\xC3;\xA9;")) "http://h.example/a/b?q=1#caf%C3%A9")
    ((fragment "http://h.example/a/b?q=1" (bytes "\xEF;\xBB;\xBF;bom")) "http://h.example/a/b?q=1#%EF%BB%BFbom")
    ((fragment "http://h.example/a/b?q=1" (bytes "%e9x")) "http://h.example/a/b?q=1#%e9x")
    ((fragment "http://h.example/a/b?q=1" (bytes "%E9x")) "http://h.example/a/b?q=1#%E9x")
    ((fragment "http://h.example/a/b?q=1" (bytes "%c3%A9")) "http://h.example/a/b?q=1#%c3%A9")
    ((fragment "http://h.example/a/b?q=1" (bytes "%zz")) "http://h.example/a/b?q=1#%zz")
    ((fragment "http://h.example/a/b?q=1" (bytes "%")) "http://h.example/a/b?q=1#%")
    ((fragment "http://h.example/a/b?q=1" (bytes "a#b")) "http://h.example/a/b?q=1#a#b")
    ((fragment "http://h.example/a/b?q=1" (bytes "x\x1;y")) "http://h.example/a/b?q=1#x%01y")
    ((fragment "http://h.example/a/b?q=1" (bytes "x\x7F;y")) "http://h.example/a/b?q=1#x%7Fy")
    ((fragment "http://h.example/a/b?q=1" (bytes "\"<>`{}|^")) "http://h.example/a/b?q=1#\"<>`{}|^")
    ((fragment "http://h.example/a/b?q=1" (bytes "a?b/c:d@e!$&'()*+,;=")) "http://h.example/a/b?q=1#a?b/c:d@e!$&'()*+,;=")
    ((fragment "http://h.example/a/b?q=1" (bytes "a\\b")) "http://h.example/a/b?q=1#a\\b")
    ((fragment "http://h.example/a/b?q=1" "only") "http://h.example/a/b?q=1#only")
    ((fragment "http://h.example/a/b?q=1" "") "http://h.example/a/b?q=1")
    ((fragment "http://h.example/a/b?q=1" "caf\xE9;") "http://h.example/a/b?q=1#caf\xE9;")
    ((fragment "http://h.example/a/b?q=1" "\xFEFF;bom") "http://h.example/a/b?q=1#\xFEFF;bom")
    ((fragment "http://h.example/a/b?q=1" "%e9x") "http://h.example/a/b?q=1#%e9x")
    ((fragment "http://h.example/a/b?q=1" "%E9x") "http://h.example/a/b?q=1#%E9x")
    ((fragment "http://h.example/a/b?q=1" "%c3%A9") "http://h.example/a/b?q=1#%c3%A9")
    ((fragment "http://h.example/a/b?q=1" "%zz") "http://h.example/a/b?q=1#%zz")
    ((fragment "http://h.example/a/b?q=1" "%") "http://h.example/a/b?q=1#%")
    ((fragment "http://h.example/a/b?q=1" "a#b") "http://h.example/a/b?q=1#a#b")
    ((fragment "http://h.example/a/b?q=1" "\"<>`{}|^") "http://h.example/a/b?q=1#\"<>`{}|^")
    ((fragment "http://h.example/a/b?q=1" "a?b/c:d@e!$&'()*+,;=") "http://h.example/a/b?q=1#a?b/c:d@e!$&'()*+,;=")
    ((fragment "http://h.example/a/b?q=1" "a\\b") "http://h.example/a/b?q=1#a\\b")
    ((fragment "http://h.example/a/b?q=1" #f) "http://h.example/a/b?q=1")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "only")) "http://h.example/a/b?q=1#only")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "")) "http://h.example/a/b?q=1")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "a b")) "http://h.example/a/b?q=1#a%20b")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "   ")) "http://h.example/a/b?q=1#%20%20%20")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "\t")) "http://h.example/a/b?q=1#%09")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "\r")) "http://h.example/a/b?q=1#%0D")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "caf\xE9;")) "http://h.example/a/b?q=1#caf%E9")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "caf\xC3;\xA9;")) "http://h.example/a/b?q=1#caf%C3%A9")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "\xEF;\xBB;\xBF;bom")) "http://h.example/a/b?q=1#%EF%BB%BFbom")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "%e9x")) "http://h.example/a/b?q=1#%e9x")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "%E9x")) "http://h.example/a/b?q=1#%E9x")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "%c3%A9")) "http://h.example/a/b?q=1#%c3%A9")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "%zz")) "http://h.example/a/b?q=1#%zz")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "%")) "http://h.example/a/b?q=1#%")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "a#b")) "http://h.example/a/b?q=1#a#b")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "x\x1;y")) "http://h.example/a/b?q=1#x%01y")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "x\x7F;y")) "http://h.example/a/b?q=1#x%7Fy")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "\"<>`{}|^")) "http://h.example/a/b?q=1#\"<>`{}|^")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "a?b/c:d@e!$&'()*+,;=")) "http://h.example/a/b?q=1#a?b/c:d@e!$&'()*+,;=")
    ((fragment "http://h.example/a/b?q=1#old" (bytes "a\\b")) "http://h.example/a/b?q=1#a\\b")
    ((fragment "http://h.example/a/b?q=1#old" "only") "http://h.example/a/b?q=1#only")
    ((fragment "http://h.example/a/b?q=1#old" "") "http://h.example/a/b?q=1")
    ((fragment "http://h.example/a/b?q=1#old" "caf\xE9;") "http://h.example/a/b?q=1#caf\xE9;")
    ((fragment "http://h.example/a/b?q=1#old" "\xFEFF;bom") "http://h.example/a/b?q=1#\xFEFF;bom")
    ((fragment "http://h.example/a/b?q=1#old" "%e9x") "http://h.example/a/b?q=1#%e9x")
    ((fragment "http://h.example/a/b?q=1#old" "%E9x") "http://h.example/a/b?q=1#%E9x")
    ((fragment "http://h.example/a/b?q=1#old" "%c3%A9") "http://h.example/a/b?q=1#%c3%A9")
    ((fragment "http://h.example/a/b?q=1#old" "%zz") "http://h.example/a/b?q=1#%zz")
    ((fragment "http://h.example/a/b?q=1#old" "%") "http://h.example/a/b?q=1#%")
    ((fragment "http://h.example/a/b?q=1#old" "a#b") "http://h.example/a/b?q=1#a#b")
    ((fragment "http://h.example/a/b?q=1#old" "\"<>`{}|^") "http://h.example/a/b?q=1#\"<>`{}|^")
    ((fragment "http://h.example/a/b?q=1#old" "a?b/c:d@e!$&'()*+,;=") "http://h.example/a/b?q=1#a?b/c:d@e!$&'()*+,;=")
    ((fragment "http://h.example/a/b?q=1#old" "a\\b") "http://h.example/a/b?q=1#a\\b")
    ((fragment "http://h.example/a/b?q=1#old" #f) "http://h.example/a/b?q=1")
    ((fragment "http://h.example/a/b#old%e9" (bytes "only")) "http://h.example/a/b#only")
    ((fragment "http://h.example/a/b#old%e9" (bytes "")) "http://h.example/a/b")
    ((fragment "http://h.example/a/b#old%e9" (bytes "a b")) "http://h.example/a/b#a%20b")
    ((fragment "http://h.example/a/b#old%e9" (bytes "   ")) "http://h.example/a/b#%20%20%20")
    ((fragment "http://h.example/a/b#old%e9" (bytes "\t")) "http://h.example/a/b#%09")
    ((fragment "http://h.example/a/b#old%e9" (bytes "\r")) "http://h.example/a/b#%0D")
    ((fragment "http://h.example/a/b#old%e9" (bytes "caf\xE9;")) "http://h.example/a/b#caf%E9")
    ((fragment "http://h.example/a/b#old%e9" (bytes "caf\xC3;\xA9;")) "http://h.example/a/b#caf%C3%A9")
    ((fragment "http://h.example/a/b#old%e9" (bytes "\xEF;\xBB;\xBF;bom")) "http://h.example/a/b#%EF%BB%BFbom")
    ((fragment "http://h.example/a/b#old%e9" (bytes "%e9x")) "http://h.example/a/b#%e9x")
    ((fragment "http://h.example/a/b#old%e9" (bytes "%E9x")) "http://h.example/a/b#%E9x")
    ((fragment "http://h.example/a/b#old%e9" (bytes "%c3%A9")) "http://h.example/a/b#%c3%A9")
    ((fragment "http://h.example/a/b#old%e9" (bytes "%zz")) "http://h.example/a/b#%zz")
    ((fragment "http://h.example/a/b#old%e9" (bytes "%")) "http://h.example/a/b#%")
    ((fragment "http://h.example/a/b#old%e9" (bytes "a#b")) "http://h.example/a/b#a#b")
    ((fragment "http://h.example/a/b#old%e9" (bytes "x\x1;y")) "http://h.example/a/b#x%01y")
    ((fragment "http://h.example/a/b#old%e9" (bytes "x\x7F;y")) "http://h.example/a/b#x%7Fy")
    ((fragment "http://h.example/a/b#old%e9" (bytes "\"<>`{}|^")) "http://h.example/a/b#\"<>`{}|^")
    ((fragment "http://h.example/a/b#old%e9" (bytes "a?b/c:d@e!$&'()*+,;=")) "http://h.example/a/b#a?b/c:d@e!$&'()*+,;=")
    ((fragment "http://h.example/a/b#old%e9" (bytes "a\\b")) "http://h.example/a/b#a\\b")
    ((fragment "http://h.example/a/b#old%e9" "only") "http://h.example/a/b#only")
    ((fragment "http://h.example/a/b#old%e9" "") "http://h.example/a/b")
    ((fragment "http://h.example/a/b#old%e9" "caf\xE9;") "http://h.example/a/b#caf\xE9;")
    ((fragment "http://h.example/a/b#old%e9" "\xFEFF;bom") "http://h.example/a/b#\xFEFF;bom")
    ((fragment "http://h.example/a/b#old%e9" "%e9x") "http://h.example/a/b#%e9x")
    ((fragment "http://h.example/a/b#old%e9" "%E9x") "http://h.example/a/b#%E9x")
    ((fragment "http://h.example/a/b#old%e9" "%c3%A9") "http://h.example/a/b#%c3%A9")
    ((fragment "http://h.example/a/b#old%e9" "%zz") "http://h.example/a/b#%zz")
    ((fragment "http://h.example/a/b#old%e9" "%") "http://h.example/a/b#%")
    ((fragment "http://h.example/a/b#old%e9" "a#b") "http://h.example/a/b#a#b")
    ((fragment "http://h.example/a/b#old%e9" "\"<>`{}|^") "http://h.example/a/b#\"<>`{}|^")
    ((fragment "http://h.example/a/b#old%e9" "a?b/c:d@e!$&'()*+,;=") "http://h.example/a/b#a?b/c:d@e!$&'()*+,;=")
    ((fragment "http://h.example/a/b#old%e9" "a\\b") "http://h.example/a/b#a\\b")
    ((fragment "http://h.example/a/b#old%e9" #f) "http://h.example/a/b")))

(define shared-cases (map car shared-answers))

;; varying-cases : (Listof Case)
;; The cases shared-answers leaves out, in all-cases' order: what each row
;; of the file answers.
(define varying-cases
  (filter (lambda (a-case) (not (member a-case shared-cases))) all-cases))

;; --- answers --------------------------------------------------------------------------

(define zero-counts
  '((block . 0) (easy . 0) (url . 0) (slist . 0) (curl-string . 0) (transfer . 0) (multi . 0) (share . 0) (mime . 0)))

;; answer : Case -> Any
;; What (curl) answers for CASE, whole: the URL, (refused CODE) for
;; libcurl's refusal, (refused-by-chez-curl REASON) for chez-curl's own, or
;; (raised TEXT) for anything else.
(define (answer a-case)
  (guard (e ((curl-url-error? e)
             (if (curl-url-error-code e)
                 (list 'refused (curl-url-error-code e))
                 (list 'refused-by-chez-curl (curl-url-error-reason e))))
            (#t (list 'raised (describe e))))
    (case (car a-case)
      ((resolve) (curl-url-resolve (cadr a-case) (argument (caddr a-case))))
      ((fragment) (curl-url-with-fragment (cadr a-case) (argument (caddr a-case))))
      (else (list 'not-a-case a-case)))))

;; answered : Case -> (List Any (Listof (Pairof Symbol Natural)))
;; CASE's answer, and the native counts once it returned.
(define (answered a-case)
  (let ((a (answer a-case)))
    (list a (native-counts))))

;; written : Any -> String
(define (written x) (call-with-string-output-port (lambda (p) (write x p))))

;; case-text : Case -> String
(define (case-text a-case)
  (case (car a-case)
    ((resolve) (string-append "resolve " (written (caddr a-case)) " against " (written (cadr a-case))))
    (else (string-append "set the fragment of " (written (cadr a-case)) " to "
                         (written (caddr a-case))))))

;; --- the rows, read under a guard ---------------------------------------------------

(define verdicts-file "tests/known-url-location-verdicts.sexp")

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

;; answer-shaped? : Any -> Boolean
;; A string, (refused CODE) or (refused-by-chez-curl REASON).
(define (answer-shaped? x)
  (or (string? x)
      (and (list? x) (= (length x) 2) (eq? (car x) 'refused)
           (integer? (cadr x)) (exact? (cadr x)))
      (and (list? x) (= (length x) 2) (eq? (car x) 'refused-by-chez-curl)
           (symbol? (cadr x)))))

;; bytes-shaped? : Any -> Boolean
;; (bytes S), S a string whose chars are all below U+0100.
(define (bytes-shaped? x)
  (and (list? x) (= (length x) 2) (eq? (car x) 'bytes) (string? (cadr x))
       (for-all (lambda (c) (< (char->integer c) 256)) (string->list (cadr x)))))

;; case-shaped? : Any -> Boolean
(define (case-shaped? x)
  (and (list? x) (= (length x) 3) (string? (cadr x))
       (or (and (eq? (car x) 'resolve) (or (string? (caddr x)) (bytes-shaped? (caddr x))))
           (and (eq? (car x) 'fragment)
                (or (string? (caddr x)) (bytes-shaped? (caddr x)) (eq? (caddr x) #f))))))

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
                       (case-shaped? (car pair)) (answer-shaped? (cadr pair)))))
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
       "test-url-location: " (if (null? matches) "no row" "more than one row") " of " verdicts-file
       " is for libcurl " version ".\n"
       "test-url-location: if it is one to support, review its answers, and add this row,\n"
       "test-url-location: with `where` saying where it runs (ADR-0029):\n\n"
       (row-text version) "\n"))
    (flush-output-port err)))

(test-begin "url-location")

;; --- the tables cover the cases ---------------------------------------------------------

(test-equal "all-cases: 50 resolutions and 120 fragments, 170 cases, each once"
  '(50 120 170 distinct)
  (list (length resolve-cases) (length fragment-cases) (length all-cases)
        (if (distinct? all-cases) 'distinct 'repeated)))

(test-equal "shared-answers: each case once, each one of all-cases, and each answer shaped"
  '(distinct () ())
  (list (if (distinct? shared-cases) 'distinct 'repeated)
        (filter (lambda (a-case) (not (member a-case all-cases))) shared-cases)
        (filter (lambda (pair) (not (answer-shaped? (cadr pair)))) shared-answers)))

(test-equal "the varying cases are the 24 shared-answers leaves out: #only, javascript:, an empty reference, a bad IPv6 host, #only again, and é as a string; then a string fragment with a space, three spaces, a tab, a CR, 0x01 or 0x7F, on each of the three URLs, refused by a code that varies. Bytes are encoded first, so no byte of a reference varies"
  (append
   '((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1" (bytes "#only"))
     (resolve "http://127.0.0.1:40001/a/b/c/javascript?q=1" (bytes "javascript:alert(1)"))
     (resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes ""))
     (resolve "http://127.0.0.1:40001/a/b/c/bad-ipv6?q=1" (bytes "http://[::1/x"))
     (resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#orig" (bytes "#only"))
     (resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" "/caf\xE9;"))
   (apply append
          (map (lambda (url)
                 (map (lambda (f) (list 'fragment url f)) '("a b" "   " "\t" "\r" "x\x1;y" "x\x7F;y")))
               fragment-bases)))
  varying-cases)

;; The decoding's control: shared answers that hold characters past ASCII,
;; where a decoding of each byte as its own character, or U+FFFD for a
;; malformed one, fails them; and a refusal as not-utf-8, which U+FFFD would
;; answer as a string.
(test-equal "shared answers hold é and U+FEFF, and a not-utf-8 refusal, so a decoding but strict UTF-8 fails them"
  '(#t #t #t)
  (let ((texts (filter string? (map cadr shared-answers))))
    (list (>= (length (filter (lambda (s) (exists (lambda (c) (char=? c #\xE9)) (string->list s))) texts))
              4)
          (>= (length (filter (lambda (s) (exists (lambda (c) (char=? c #\xFEFF)) (string->list s)))
                              texts))
              3)
          (>= (length (filter (lambda (pair) (equal? (cadr pair) '(refused-by-chez-curl not-utf-8)))
                              shared-answers))
              1))))

;; --- the file ------------------------------------------------------------------------------

(test-equal "tests/known-url-location-verdicts.sexp reads as data"
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
  '(libcurl (where "made up") (version "9.9.9")
            (answers ((fragment "http://x/" #f) "http://x/"))))

(test-equal "the matcher: a version with one row is one, with none is none, with two is several; a malformed row is never a match"
  '(one none several none)
  (list (version-verdict (list made-up-row) "9.9.9")
        (version-verdict (list made-up-row) "9.9.8")
        (version-verdict (list made-up-row made-up-row) "9.9.9")
        (version-verdict (list '(libcurl (version "9.9.9"))) "9.9.9")))

(test-equal "the shape: a row missing where, a raw bytevector for a case's bytes, bytes past U+00FF, #f for a reference, and an answer that is no URL nor refusal are refused"
  '(rejected rejected rejected rejected rejected ok)
  (map (lambda (row) (if (eq? (row-problem row) 'ok) 'ok 'rejected))
       (list '(libcurl (version "9.9.9") (answers ((fragment "http://x/" #f) "http://x/")))
             '(libcurl (where "w") (version "9.9.9") (answers ((resolve "http://x/" #vu8(47)) "http://x/")))
             '(libcurl (where "w") (version "9.9.9") (answers ((resolve "http://x/" (bytes "/\x3BB;")) "http://x/")))
             '(libcurl (where "w") (version "9.9.9") (answers ((resolve "http://x/" #f) "http://x/")))
             '(libcurl (where "w") (version "9.9.9") (answers ((fragment "http://x/" #f) 3)))
             made-up-row)))

(test-equal "the printed row reads back as a well-formed row for this version, answering exactly the varying cases"
  'ok
  (guard (e (#t (list 'raised (describe e))))
    (let ((row (read (open-string-input-port (row-text "9.9.9")))))
      (cond ((not (eq? (row-problem row) 'ok)) (row-problem row))
            ((not (same-cases? (map car (row-answers row)) varying-cases)) (row-answers row))
            (else 'ok)))))

;; --- the guard -----------------------------------------------------------------------------

(test-equal "the loaded libcurl's version has exactly one row in tests/known-url-location-verdicts.sexp"
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

;; The probe's two long Location values, a path of 8,000 and of 90,000 a's,
;; too long to write out: every libcurl measured resolved each to the path.
(test-equal "references of 8,001 and 90,001 bytes, / and a path of a's, resolve to that path on every libcurl, and the counts are back at zero"
  (list (string-append "http://127.0.0.1:40001/" (make-string 8000 #\a))
        (string-append "http://127.0.0.1:40001/" (make-string 90000 #\a))
        zero-counts)
  (let* ((short (answer (list 'resolve (base "long-8k") (list 'bytes (string-append "/" (make-string 8000 #\a))))))
         (long (answer (list 'resolve (base "long-90k") (list 'bytes (string-append "/" (make-string 90000 #\a))))))
         (counts (native-counts)))
    (list short long counts)))

;; A reference given as a string is sent as UTF-8, and as bytes, encoded
;; first: on printable ASCII the two are one, a space among it, which
;; libcurl encodes in a relative string reference as encoded-bytes does.
;; 0x01 and 0x7F are not: as a string they reach libcurl raw, which 7.85.0
;; and 8.5.0 refuse, and as bytes they are encoded and followed.
(test-equal "every Location value that is printable ASCII, 27 of them, resolves alike as a string and as bytes"
  '(27 ())
  (let ((ascii (filter (lambda (pair) (for-all (lambda (c) (<= 32 (char->integer c) 126))
                                               (string->list (cadr pair))))
                       location-values)))
    (list (length ascii)
          (filter (lambda (pair)
                    (not (equal? (answer (list 'resolve (base (car pair)) (cadr pair)))
                                 (answer (list 'resolve (base (car pair)) (list 'bytes (cadr pair)))))))
                  ascii))))

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

(test-equal "a reference libcurl refuses, given as bytes, is named by its bytes read as Latin-1, with libcurl's code; one whose host is not UTF-8, as not-utf-8, the same way"
  (list '(bad-port-number 4 "http://127.0.0.1:99999/caf\xE9;" a-message)
        '(not-utf-8 #f "http://caf\xE9;.invalid/" a-message)
        zero-counts)
  (let* ((port (refusal (lambda () (curl-url-resolve "http://h.example/a" (bytes "http://127.0.0.1:99999/caf\xE9;")))))
         (host (refusal (lambda () (curl-url-resolve "http://h.example/a" (bytes "http://caf\xE9;.invalid/")))))
         (counts (native-counts)))
    (list port host counts)))

(test-equal "a base libcurl refuses is named, for both functions, with libcurl's code"
  (list '(bad-port-number 4 "http://h.example:99999/" a-message)
        '(bad-port-number 4 "http://h.example:99999/" a-message)
        zero-counts)
  (let* ((resolved (refusal (lambda () (curl-url-resolve "http://h.example:99999/" (bytes "/x")))))
         (fragment (refusal (lambda () (curl-url-with-fragment "http://h.example:99999/" #f))))
         (counts (native-counts)))
    (list resolved fragment counts)))

(test-equal "curl-url-with-fragment: the string it writes, when libcurl refuses it, is what the refusal names: a string fragment with a space"
  (list "http://h.example/a/b?q=1#a b" 'a-code zero-counts)
  (let* ((r (refusal (lambda () (curl-url-with-fragment "http://h.example/a/b?q=1#old" "a b"))))
         (counts (native-counts)))
    (list (if (and (list? r) (= (length r) 4)) (caddr r) r)
          (if (and (list? r) (= (length r) 4) (integer? (cadr r))) 'a-code r)
          counts)))

;; 0x00 in the bytes, and U+0000 in a string, at every place a scan can
;; miss: first, inside, last, the whole, and between two bytes above 0x7F.
;; Each refused before libcurl sees it, so with no handle and no block at
;; the raise.
(for-each
 (lambda (row)
   (let ((who (car row)) (call (cadr row)) (given (caddr row)) (named (cadddr row)))
     (test-equal (string-append who " refuses " (written given)
                                " as &curl-url-error, embedded-nul, naming " (written named)
                                ", with no handle or block at the raise")
       (list (list (list 'embedded-nul #f named 'a-message) zero-counts) zero-counts)
       (let ((r (refusal-at-raise (lambda () (call given)))))
         (list r (native-counts))))))
 (append
  (apply append
         (map (lambda (s)
                (list (list "curl-url-resolve" (lambda (b) (curl-url-resolve "http://h.example/a" b))
                            (bytes s) s)
                      (list "curl-url-with-fragment" (lambda (b) (curl-url-with-fragment "http://h.example/a" b))
                            (bytes s) s)))
              '("\x0;b" "b\x0;c" "b\x0;" "\x0;" "\xE9;\x0;\xF1;")))
        (map (lambda (s)
               (list "curl-url-with-fragment" (lambda (f) (curl-url-with-fragment "http://h.example/a" f))
                     s s))
             '("\x0;b" "b\x0;c" "b\x0;" "\x0;" "\xE9;\x0;\x3BB;"))))

(test-equal "a NUL in the URL, for either function, is refused the same way, naming the URL"
  (list (list (list 'embedded-nul #f "http://a/\x0;b" 'a-message) zero-counts)
        (list (list 'embedded-nul #f "http://a/\x0;b" 'a-message) zero-counts)
        zero-counts)
  (let* ((resolved (refusal-at-raise (lambda () (curl-url-resolve "http://a/\x0;b" (bytes "/x")))))
         (fragment (refusal-at-raise (lambda () (curl-url-with-fragment "http://a/\x0;b" #f))))
         (counts (native-counts)))
    (list resolved fragment counts)))

(test-equal "what is no URL, no reference, or no fragment is an assertion violation from the function called"
  '((assertion curl-url-resolve) (assertion curl-url-resolve) (assertion curl-url-resolve)
    (assertion curl-url-with-fragment) (assertion curl-url-with-fragment)
    (assertion curl-url-with-fragment))
  (list (refusal (lambda () (curl-url-resolve 42 "/x")))
        (refusal (lambda () (curl-url-resolve "http://a/" 42)))
        (refusal (lambda () (curl-url-resolve "http://a/" #f)))
        (refusal (lambda () (curl-url-with-fragment #f #f)))
        (refusal (lambda () (curl-url-with-fragment "http://a/" 42)))
        (refusal (lambda () (curl-url-with-fragment "http://a/" '(bytes "x"))))))

;; --- the encoding, over every byte ---------------------------------------------------------
;; encoded-bytes keeps 0x21 to 0x7E, written out here, and encodes every
;; other byte (ADR-0029). Each byte alone, against the whole complement of
;; the kept set, then a run of bytes whose order a reversal would show.

(define kept-bytes
  "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")

(define (hex2 b)
  (string (string-ref "0123456789ABCDEF" (div b 16)) (string-ref "0123456789ABCDEF" (mod b 16))))

(test-equal "the kept set written out is 94 distinct chars, 0x21 to 0x7E"
  '(94 distinct)
  (list (string-length kept-bytes) (if (distinct? (string->list kept-bytes)) 'distinct 'repeated)))

(test-equal "encoded-bytes: each byte alone is itself when the kept set holds it, and % and two upper-case hex digits otherwise, 162 of them"
  '(() 162)
  (let ((encoded (filter (lambda (b) (not (memv (integer->char b) (string->list kept-bytes))))
                         (iota 256))))
    (list (filter (lambda (b)
                    (not (equal? (encoded-bytes (u8-list->bytevector (list b)))
                                 (if (memv b encoded)
                                     (string-append "%" (hex2 b))
                                     (string (integer->char b))))))
                  (iota 256))
          (length encoded))))

(test-equal "encoded-bytes: a run of bytes, kept and encoded, in order; and no bytes as no text"
  '("%00%1F%20!%#~%7F%80%E9%FF" "")
  (list (encoded-bytes #vu8(0 31 32 33 37 35 126 127 128 233 255))
        (encoded-bytes #vu8())))

;; --- the string written, by tables ---------------------------------------------------------
;; fragment-url is the string assembly, pure, so these rows reach what no
;; libcurl measured gives: a "" fragment, at the end and not. Each row is
;; WHOLE and FRAGMENT, as curl_url_get would give them, then NEW and the
;; string written.

(define fragment-rows
  '(("http://h/p" #f "x" "http://h/p#x")
    ("http://h/p#old" "old" "x" "http://h/p#x")
    ("http://h/p?q=1#old%e9" "old%e9" "n" "http://h/p?q=1#n")
    ("http://h/p#old" "old" "" "http://h/p")
    ("http://h/p" #f "" "http://h/p")
    ("http://h/p#a#b" "a#b" "c" "http://h/p#c")
    ("http://h/p" "" "x" "http://h/p#x")
    ("http://h/p#" "" "x" "http://h/p#x")
    ("http://h/p#" "" "" "http://h/p")))

(test-equal "fragment-url writes each row's string: the fragment and its # off the end, then # and the new one unless it is empty; a \"\" fragment cuts a # at the end, and nothing where there is none"
  (map (lambda (row) (list-ref row 3)) fragment-rows)
  (map (lambda (row)
         (guard (e (#t (list 'raised (describe e))))
           (apply fragment-url (list-head row 3))))
       fragment-rows))

(test-equal "fragment-url refuses a non-empty fragment that is not the URL's end, an error from curl-url-with-fragment"
  '(error curl-url-with-fragment)
  (guard (e ((and (error? e) (who-condition? e)) (list 'error (condition-who e)))
            (#t (list 'other (describe e))))
    (list 'no-raise (fragment-url "http://h/p" "zz" "x"))))

;; --- check-then-use: bytes or a string another thread changes ---------------------------------
;; Each function checks a copy of what it is given, and hands libcurl that
;; copy. Handing it the caller's bytevector or string instead lets a second
;; thread put a 0 in between: the check passes, and libcurl reads to the 0.
;; Here a thread flips one element between a and 0: each answer is the
;; input refused as embedded-nul, or the answer for it whole.

;; flipped : Natural (-> Void) (-> Void) (-> Any) Any Any -> (List (Listof Any) (Listof Symbol) Counts)
;; N calls of CALL while a thread runs SET-ZERO and SET-A in turn: the
;; answers that are neither REFUSED nor WHOLE, which of the two were seen,
;; and the counts after.
(define (flipped n set-zero set-a call refused whole)
  (let* ((stop #f)
         (yield (lambda () (sleep (make-time 'time-duration 0 0))))
         (pause (lambda () (sleep (make-time 'time-duration 1000000 0))))
         (flip (lambda ()
                 (let loop ((i 0))
                   (when (< i 100000)
                     (set-zero)
                     (set-a)
                     (loop (+ i 1))))))
         (flipper (fork-thread (lambda ()
                                 (let loop ()
                                   (unless stop
                                     (flip)
                                     (yield)
                                     (flip)
                                     (set-zero)
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
                                         (call)))))
                         (cond ((equal? a refused) 'refused)
                               ((equal? a whole) 'whole)
                               (else a)))))
                (loop (+ i 1)
                      (if (memq o '(refused whole)) odd (cons o odd))
                      (if (memq o seen) seen (cons o seen)))))))
      (lambda () (set! stop #t) (thread-join flipper)))))

(test-equal "curl-url-resolve, while another thread flips a byte of its reference to 0: 1000 answers each the bytes refused as embedded-nul, naming them, or the reference resolved whole, both seen, and nothing left"
  (list '() '(refused whole) zero-counts)
  (let ((b (bytes "/xax")))
    (flipped 1000 (lambda () (bytevector-u8-set! b 2 0)) (lambda () (bytevector-u8-set! b 2 97))
             (lambda () (curl-url-resolve "http://h.example/a" b))
             '(refused embedded-nul "/x\x0;x") "http://h.example/xax")))

(test-equal "curl-url-with-fragment, while another thread flips a byte of its fragment to 0: 1000 answers each refused or whole, both seen, and nothing left"
  (list '() '(refused whole) zero-counts)
  (let ((b (bytes "xax")))
    (flipped 1000 (lambda () (bytevector-u8-set! b 1 0)) (lambda () (bytevector-u8-set! b 1 97))
             (lambda () (curl-url-with-fragment "http://h.example/a" b))
             '(refused embedded-nul "x\x0;x") "http://h.example/a#xax")))

(test-equal "curl-url-with-fragment, while another thread flips a char of its string fragment to U+0000: 1000 answers each refused or whole, both seen, and nothing left"
  (list '() '(refused whole) zero-counts)
  (let ((s (string-copy "xax")))
    (flipped 1000 (lambda () (string-set! s 1 #\nul)) (lambda () (string-set! s 1 #\a))
             (lambda () (curl-url-with-fragment "http://h.example/a" s))
             '(refused embedded-nul "x\x0;x") "http://h.example/a#xax")))

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
   (test-equal (string-append (car row) " in an engine that runs out at every tick, each abandoned, until one completes: it completes, and no native object is left, no CURLU, no block and no string libcurl made")
     (list 'completed-after-expiries zero-counts)
     (let* ((sweep (swept (engine-sweep (cadr row) 1)))
            (counts (native-counts)))
       (list sweep counts))))
 (list (list "curl-url-resolve of bytes"
             (lambda () (curl-url-resolve "http://h.example/a/b?q=1#c" (bytes "../caf\xE9;"))))
       (list "curl-url-with-fragment of bytes"
             (lambda () (curl-url-with-fragment "http://h.example/a?b=1#c" (bytes "d \xE9;"))))))

(test-end "url-location")

(exit (suite-exit-status runner))
