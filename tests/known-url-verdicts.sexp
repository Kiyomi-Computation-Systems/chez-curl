;; curl's URL verdicts that vary by version (ADR-0008, amended 2026-10-19).
;; tests/test-url.sps holds the answer every recorded libcurl agrees on for
;; each other case. These are the cases on which they do not agree: one row
;; per libcurl version a lane runs, each with that version's answer to every
;; one of them.
;;
;; A libcurl whose version has no row fails make test, wherever it runs, and
;; test-url prints the row it would need on the error port, naming this file.
;; Adding a row, or changing one, is a reviewed change: review what the
;; printed row says, paste it here, and replace its `where` with where the
;; library runs. A libcurl that answers a shared case otherwise fails too;
;; moving that case here is a reviewed change to the suite.
;;
;; The file is data: rows only, nothing else. Each is exactly
;;   (libcurl (where STRING) (version STRING) (answers (CASE ANSWER) ...))
;; A CASE is (normalize URL), curl_url_set of URL on a fresh handle, then
;; curl_url_get; or (resolve BASE REFERENCE), BASE set, then REFERENCE, then
;; curl_url_get. An ANSWER is the URL curl_url_get gives back, or
;; (refused CODE), the CURLUcode of the curl_url_set that refused. A row's
;; cases are exactly test-url's varying cases, each once. `where` is a note
;; for the reader and is not compared. Two rows may not share a version.

(libcurl
 (where "The floor, curl 7.85.0 built by scripts/ci/build-curl.sh on Ubuntu 24.04 with OpenSSL 3.0.13: the library the floor lanes load. Measured through C in Docker ubuntu:24.04 on 2026-10-19 (ADR-0008, amended 2026-10-19); the last three, on 2026-10-23.")
 (version "7.85.0")
 (answers
  ((resolve "http://example.com/a/b/c?q=1" "#frag") "http://example.com/a/b/#frag")
  ((normalize "http://example.com/a b") (refused 25))
  ((normalize "http://exa mple.com/") (refused 21))
  ((resolve "http://a/b/c/d;p?q" "#s") "http://a/b/c/#s")
  ((resolve "http://a/b/c/d;p?q" "") "http://a/b/c/")
  ((resolve "http://a/b/c/d;p?q" "g:h") "http://a/b/c/g:h")
  ((resolve "http://a/b/c/d;p?q" "http:g") "http://a/b/c/http:g")
  ((resolve "http://example.com/a/b/c?q=1" "\xE9;") "http://example.com/a/b/%c3%a9")
  ((resolve "http://example.com/a/b/c?q=1" "?q=\x3BB;") "http://example.com/a/b/c?q=%ce%bb")
  ((resolve "http://example.com/a/b/c?q=1" "?q=\x1F600;") "http://example.com/a/b/c?q=%f0%9f%98%80")))

(libcurl
 (where "Ubuntu 24.04's libcurl4t64 8.5.0 (OpenSSL 3.0.13), the library CI's main and memory lanes load; its libcurl3t64-gnutls 8.5.0 gave the same answers. Measured through C in Docker ubuntu:24.04 on 2026-10-19 (ADR-0008, amended 2026-10-19); the last three, on 2026-10-23.")
 (version "8.5.0")
 (answers
  ((resolve "http://example.com/a/b/c?q=1" "#frag") "http://example.com/a/b/#frag")
  ((normalize "http://example.com/a b") (refused 3))
  ((normalize "http://exa mple.com/") (refused 3))
  ((resolve "http://a/b/c/d;p?q" "#s") "http://a/b/c/#s")
  ((resolve "http://a/b/c/d;p?q" "") (refused 3))
  ((resolve "http://a/b/c/d;p?q" "g:h") (refused 5))
  ((resolve "http://a/b/c/d;p?q" "http:g") (refused 28))
  ((resolve "http://example.com/a/b/c?q=1" "\xE9;") "http://example.com/a/b/%c3%a9")
  ((resolve "http://example.com/a/b/c?q=1" "?q=\x3BB;") "http://example.com/a/b/c?q=%ce%bb")
  ((resolve "http://example.com/a/b/c?q=1" "?q=\x1F600;") "http://example.com/a/b/c?q=%f0%9f%98%80")))

(libcurl
 (where "The pinned Guix container (scripts/guix-env, ADR-0006): the profile's curl 8.20.0 with GnuTLS 3.8.13. Measured through C in the container on 2026-10-19 (ADR-0008, amended 2026-10-19); the last three, on 2026-10-23.")
 (version "8.20.0")
 (answers
  ((resolve "http://example.com/a/b/c?q=1" "#frag") "http://example.com/a/b/c?q=1#frag")
  ((normalize "http://example.com/a b") (refused 3))
  ((normalize "http://exa mple.com/") (refused 3))
  ((resolve "http://a/b/c/d;p?q" "#s") "http://a/b/c/d;p?q#s")
  ((resolve "http://a/b/c/d;p?q" "") "http://a/b/c/d;p?q")
  ((resolve "http://a/b/c/d;p?q" "g:h") (refused 5))
  ((resolve "http://a/b/c/d;p?q" "http:g") (refused 28))
  ((resolve "http://example.com/a/b/c?q=1" "\xE9;") "http://example.com/a/b/%C3%A9")
  ((resolve "http://example.com/a/b/c?q=1" "?q=\x3BB;") "http://example.com/a/b/c?q=%CE%BB")
  ((resolve "http://example.com/a/b/c?q=1" "?q=\x1F600;") "http://example.com/a/b/c?q=%F0%9F%98%80")))
