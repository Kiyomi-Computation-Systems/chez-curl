;; curl's answers to tests/test-url-parts' cases that vary by version (ADR-0028;
;; the M5 plan, section 4.1). tests/test-url-parts.sps holds the answer every
;; recorded libcurl agrees on for each other case. These are the cases on
;; which they do not agree: one row per libcurl version a lane runs, each with
;; that version's answer to every one of them.
;;
;; A libcurl whose version has no row fails make test, wherever it runs, and
;; test-url-parts prints the row it would need on the error port, naming this
;; file. Adding a row, or changing one, is a reviewed change: review what the
;; printed row says, paste it here, and replace its `where` with where the
;; library runs. A libcurl that answers a shared case otherwise fails too;
;; moving that case here is a reviewed change to the suite.
;;
;; The file is data: rows only, nothing else. Each is exactly
;;   (libcurl (where STRING) (version STRING) (answers (CASE ANSWER) ...))
;; A CASE is (append URL PART), curl-url-append-query of PART to URL; or
;; (parts URL), curl-url-part of URL for each of url, scheme, user, password,
;; host, port, path, query and fragment, in that order. An append's ANSWER is
;; the URL, (refused CODE), libcurl's CURLUcode, or (refused-by-chez-curl
;; REASON); a parts ANSWER is a list of nine such, each a string, the port a
;; natural, and (absent) for a part the URL lacks. A row's cases are exactly
;; test-url-parts' varying cases, each once, and each case has different
;; answers in two rows at least: one every row answers alike belongs to the
;; shared answers. `where` is a note for the reader and is not compared. Two
;; rows may not share a version.

(libcurl
 (where "The floor, curl 7.85.0 built by scripts/ci/build-curl.sh on Ubuntu 24.04 with OpenSSL 3.0.13: the library the floor lanes load. Printed by test-url-parts in Docker ubuntu:24.04 on 2026-10-27; the C probe's curl_url_get gave the same parts (.plans/research/m5/url-parts/).")
 (version "7.85.0")
 (answers
  ((append "http://h.example/p" "s=a b") (refused 26))
  ((append "http://h.example/p?a=1#frag" "s=a b") (refused 26))
  ((parts "http://:pw@h.example/") ("http://:pw@h.example/" "http" (absent) "pw" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://u:@h.example/") ("http://u@h.example/" "http" "u" (absent) "h.example" 80 "/" (absent) (absent)))
  ((parts "http://h.example/p?") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" "" (absent)))
  ((parts "http://h.example/p?#") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" "" (absent)))))

(libcurl
 (where "Ubuntu 24.04's libcurl4t64 8.5.0 (OpenSSL 3.0.13), the library CI's main and memory lanes load; its libcurl3t64-gnutls 8.5.0 printed the same row. Printed by test-url-parts in Docker ubuntu:24.04 on 2026-10-27; the C probe's curl_url_get gave the same parts.")
 (version "8.5.0")
 (answers
  ((append "http://h.example/p" "s=a b") (refused 3))
  ((append "http://h.example/p?a=1#frag" "s=a b") (refused 3))
  ((parts "http://:pw@h.example/") ("http://:pw@h.example/" "http" "" "pw" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://u:@h.example/") ("http://u:@h.example/" "http" "u" "" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://h.example/p?") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" "" (absent)))
  ((parts "http://h.example/p?#") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" "" (absent)))))

(libcurl
 (where "The pinned Guix container (scripts/guix-env, ADR-0006): the profile's curl 8.20.0 with GnuTLS 3.8.13. Printed by test-url-parts in the container on 2026-10-27; the C probe's curl_url_get gave the same parts.")
 (version "8.20.0")
 (answers
  ((append "http://h.example/p" "s=a b") (refused 3))
  ((append "http://h.example/p?a=1#frag" "s=a b") (refused 3))
  ((parts "http://:pw@h.example/") ("http://:pw@h.example/" "http" "" "pw" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://u:@h.example/") ("http://u:@h.example/" "http" "u" "" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://h.example/p?") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))
  ((parts "http://h.example/p?#") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))))

(libcurl
 (where "The current libcurl, curl 8.23.0 built by scripts/ci/build-curl.sh --current on Ubuntu 24.04 with OpenSSL 3.0.13: the library CI's current lane loads (ADR-0020, amended 2026-10-26). Printed by test-url-parts in Docker ubuntu:24.04 on 2026-10-27; 8.20.0's answers but a space's code, 26 (CURLUE_BAD_QUERY).")
 (version "8.23.0")
 (answers
  ((append "http://h.example/p" "s=a b") (refused 26))
  ((append "http://h.example/p?a=1#frag" "s=a b") (refused 26))
  ((parts "http://:pw@h.example/") ("http://:pw@h.example/" "http" "" "pw" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://u:@h.example/") ("http://u:@h.example/" "http" "u" "" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://h.example/p?") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))
  ((parts "http://h.example/p?#") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" (absent) (absent)))))

(libcurl
 (where "Apple's libcurl 8.7.1, /usr/lib/libcurl.4.dylib, on the maintainer's Mac: Apple M1, macOS 26.7.1, SecureTransport (LibreSSL/3.3.6). Printed by test-url-parts there on 2026-10-28; 8.5.0's answers, and the C probe's curl_url_get gave the same parts (.plans/research/m5/url-parts/results/mac-8.7.1.log).")
 (version "8.7.1")
 (answers
  ((append "http://h.example/p" "s=a b") (refused 3))
  ((append "http://h.example/p?a=1#frag" "s=a b") (refused 3))
  ((parts "http://:pw@h.example/") ("http://:pw@h.example/" "http" "" "pw" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://u:@h.example/") ("http://u:@h.example/" "http" "u" "" "h.example" 80 "/" (absent) (absent)))
  ((parts "http://h.example/p?") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" "" (absent)))
  ((parts "http://h.example/p?#") ("http://h.example/p" "http" (absent) (absent) "h.example" 80 "/p" "" (absent)))))
