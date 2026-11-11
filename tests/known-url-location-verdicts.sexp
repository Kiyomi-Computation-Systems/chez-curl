;; curl's answers to tests/test-url-location's cases that vary by version
;; (ADR-0029). tests/test-url-location.sps holds the answer every recorded
;; libcurl agrees on for each other case. These are the cases on which they do
;; not agree: one row per libcurl version a lane runs, each with that version's
;; answer to every one of them.
;;
;; A libcurl whose version has no row fails make test, wherever it runs, and
;; test-url-location prints the row it would need on the error port, naming
;; this file. Adding a row, or changing one, is a reviewed change: review what
;; the printed row says, paste it here, and replace its `where` with where the
;; library runs. A libcurl that answers a shared case otherwise fails too;
;; moving that case here is a reviewed change to the suite.
;;
;; The file is data: rows only, nothing else. Each is exactly
;;   (libcurl (where STRING) (version STRING) (answers (CASE ANSWER) ...))
;; A CASE is (resolve BASE REFERENCE), curl-url-resolve of REFERENCE, a
;; string or a bytevector, against BASE; or (fragment URL FRAGMENT),
;; curl-url-with-fragment of URL with FRAGMENT, a string, a bytevector or #f.
;; An ANSWER is the URL, (refused CODE), libcurl's CURLUcode, or
;; (refused-by-chez-curl REASON). A row's cases are exactly
;; test-url-location's varying cases, each once, and each case has different
;; answers in two rows at least: one every row answers alike belongs to the
;; shared answers. `where` is a note for the reader and is not compared. Two
;; rows may not share a version.

(libcurl
 (where "The floor, curl 7.85.0 built by scripts/ci/build-curl.sh on Ubuntu 24.04 with OpenSSL 3.0.13: the library the floor lanes load. Printed by test-url-location in Docker ubuntu:24.04 on 2026-10-28.")
 (version "7.85.0")
 (answers
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/javascript?q=1" (bytes "javascript:alert(1)")) "http://127.0.0.1:40001/a/b/c/javascript:alert(1)")
  ((resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes "")) "http://127.0.0.1:40001/a/b/c/")
  ((resolve "http://127.0.0.1:40001/a/b/c/bad-ipv6?q=1" (bytes "http://[::1/x")) (refused 4))
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#orig" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" "/caf\xE9;") "http://127.0.0.1:40001/caf%c3%a9")
  ((fragment "http://h.example/a/b?q=1" "a b") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "   ") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "\t") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "\r") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "x\x1;y") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "x\x7F;y") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "a b") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "   ") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "\t") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "\r") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "x\x1;y") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "x\x7F;y") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "a b") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "   ") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "\t") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "\r") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "x\x1;y") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "x\x7F;y") (refused 20))))

(libcurl
 (where "Ubuntu 24.04's libcurl4t64 8.5.0 (OpenSSL 3.0.13), the library CI's main and memory lanes load; its libcurl3t64-gnutls 8.5.0 printed the same row. Printed by test-url-location in Docker ubuntu:24.04 on 2026-10-28.")
 (version "8.5.0")
 (answers
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/javascript?q=1" (bytes "javascript:alert(1)")) (refused 5))
  ((resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes "")) (refused 3))
  ((resolve "http://127.0.0.1:40001/a/b/c/bad-ipv6?q=1" (bytes "http://[::1/x")) (refused 22))
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#orig" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" "/caf\xE9;") "http://127.0.0.1:40001/caf%c3%a9")
  ((fragment "http://h.example/a/b?q=1" "a b") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "   ") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "\t") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "\r") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "x\x7F;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "a b") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "   ") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "\t") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "\r") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "x\x7F;y") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "a b") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "   ") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "\t") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "\r") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "x\x7F;y") (refused 3))))

(libcurl
 (where "The pinned Guix container (scripts/guix-env, ADR-0006): the profile's curl 8.20.0 with GnuTLS 3.8.13. Printed by test-url-location in the container on 2026-10-28.")
 (version "8.20.0")
 (answers
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/javascript?q=1" (bytes "javascript:alert(1)")) (refused 5))
  ((resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes "")) "http://127.0.0.1:40001/a/b/c/empty?q=1")
  ((resolve "http://127.0.0.1:40001/a/b/c/bad-ipv6?q=1" (bytes "http://[::1/x")) (refused 22))
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#orig" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" "/caf\xE9;") "http://127.0.0.1:40001/caf%C3%A9")
  ((fragment "http://h.example/a/b?q=1" "a b") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "   ") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "\t") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "\r") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "x\x7F;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "a b") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "   ") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "\t") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "\r") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "x\x7F;y") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "a b") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "   ") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "\t") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "\r") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "x\x7F;y") (refused 3))))

(libcurl
 (where "curl 8.23.0, built from source by scripts/ci/build-curl.sh --current on Ubuntu 24.04: the library CI's current lane loads. Printed by test-url-location in Docker ubuntu:24.04 on 2026-10-28.")
 (version "8.23.0")
 (answers
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/javascript?q=1" (bytes "javascript:alert(1)")) (refused 5))
  ((resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes "")) "http://127.0.0.1:40001/a/b/c/empty?q=1")
  ((resolve "http://127.0.0.1:40001/a/b/c/bad-ipv6?q=1" (bytes "http://[::1/x")) (refused 22))
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#orig" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" "/caf\xE9;") "http://127.0.0.1:40001/caf%C3%A9")
  ((fragment "http://h.example/a/b?q=1" "a b") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "   ") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "\t") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "\r") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "x\x1;y") (refused 20))
  ((fragment "http://h.example/a/b?q=1" "x\x7F;y") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "a b") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "   ") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "\t") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "\r") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "x\x1;y") (refused 20))
  ((fragment "http://h.example/a/b?q=1#old" "x\x7F;y") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "a b") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "   ") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "\t") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "\r") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "x\x1;y") (refused 20))
  ((fragment "http://h.example/a/b#old%e9" "x\x7F;y") (refused 20))))

(libcurl
 (where "Apple's libcurl 8.7.1, /usr/lib/libcurl.4.dylib, on the maintainer's Mac: Apple M1, macOS 26.7.1, SecureTransport (LibreSSL/3.3.6). Printed by test-url-location there on 2026-10-29, on feat/m5-slice-4; 8.5.0's answers, case for case (.plans/research/m5/location/results/mac-8.7.1.log).")
 (version "8.7.1")
 (answers
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/javascript?q=1" (bytes "javascript:alert(1)")) (refused 5))
  ((resolve "http://127.0.0.1:40001/a/b/c/empty?q=1" (bytes "")) (refused 3))
  ((resolve "http://127.0.0.1:40001/a/b/c/bad-ipv6?q=1" (bytes "http://[::1/x")) (refused 22))
  ((resolve "http://127.0.0.1:40001/a/b/c/rel-frag?q=1#orig" (bytes "#only")) "http://127.0.0.1:40001/a/b/c/#only")
  ((resolve "http://127.0.0.1:40001/a/b/c/latin1?q=1" "/caf\xE9;") "http://127.0.0.1:40001/caf%c3%a9")
  ((fragment "http://h.example/a/b?q=1" "a b") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "   ") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "\t") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "\r") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1" "x\x7F;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "a b") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "   ") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "\t") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "\r") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b?q=1#old" "x\x7F;y") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "a b") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "   ") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "\t") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "\r") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "x\x1;y") (refused 3))
  ((fragment "http://h.example/a/b#old%e9" "x\x7F;y") (refused 3))))
