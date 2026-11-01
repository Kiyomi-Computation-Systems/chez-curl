;; The transfer's verdicts that vary by version (M2 plan, sections 5.1.1 and
;; 5.3). tests/test-transfer.sps holds the answer every recorded
;; libcurl agrees on for each other scenario. These are the scenarios on
;; which they do not agree: one row per libcurl version a lane runs, each
;; with that version's answer to every one of them.
;;
;; A libcurl whose version has no row fails make test, wherever it runs, and
;; test-transfer prints the row it would need on the error port, naming this
;; file. Adding a row, or changing one, is a reviewed change: review what the
;; printed row says, paste it here, and replace its `where` with where the
;; library runs. A libcurl that answers a shared scenario otherwise fails
;; too; moving that scenario here is a reviewed change to the suite.
;;
;; The file is data: rows only, nothing else. Each is exactly
;;   (libcurl (where STRING) (version STRING) (answers (CASE ANSWER) ...))
;; A CASE is (get FACE PATH), a GET of PATH on the origin's FACE, http or
;; raw, submitted to an engine and awaited, with no body limit; or
;; (error-text FACE PATH), the same GET, which raises a &curl-transfer-error,
;; and whose ANSWER is (error-text TEXT), its error buffer's text: a text
;; that varies by version (ADR-0020, amended 2026-10-26). A get's ANSWER is (refused REASON
;; CODE), the &curl-transfer-error's reason and CURLcode, a number; or
;; (response STATUS VERSION HEADERS BODY): the status, the HTTP version's
;; symbol, every header as (NAME VALUE), in libcurl's order, and the body
;; read as Latin-1. HEADERS may instead be (numbered PREFIX COUNT VALUE):
;; COUNT headers, PREFIX1 to PREFIXCOUNT, each VALUE, in that order. A row's
;; cases are exactly test-transfer's varying cases, each once, and each case
;; has different answers in two rows at least: one every row answers alike
;; belongs to the shared answers. `where` is a note for the reader and is
;; not compared. Two rows may not share a version.

(libcurl
 (where "The floor, curl 7.85.0 built by scripts/ci/build-curl.sh on Ubuntu 24.04 with OpenSSL 3.0.13: the library the floor lanes load. Measured through C in Docker ubuntu:24.04, Node 20.10.0, on 2026-10-23 (M2 plan, section 5.1.1). many-headers at 50,000, 100,000's answer: measured in Docker on 2026-11-01, 7,280 to 7,637 ms of CPU (build/cifix).")
 (version "7.85.0")
 (answers
  ((get raw "/raw/big-header?bytes=102400") (refused perform-failed 27))
  ((get raw "/raw/big-header?bytes=1048576") (refused perform-failed 27))
  ((get raw "/raw/many-headers?count=50000") (response 200 http/1.1 (numbered "X-H-" 50000 "v") ""))
  ((get raw "/raw/bad-status-code") (refused perform-failed 1))
  ((get raw "/raw/conflicting-content-length")
   (response 200 http/1.1 (("Content-Length" "5") ("Content-Length" "6")) "hello\n"))
  ((error-text raw "/raw/nul-in-header") (error-text "Nul byte in header"))))

(libcurl
 (where "Ubuntu 24.04's libcurl4t64 8.5.0 (OpenSSL 3.0.13), the library CI's main and memory lanes load; its libcurl3t64-gnutls 8.5.0 gave the same answers. Measured through C in Docker ubuntu:24.04, Node 20.10.0, on 2026-10-23 (M2 plan, section 5.1.1). many-headers at 50,000, 100,000's answer, on both: measured in Docker on 2026-11-01 (build/cifix).")
 (version "8.5.0")
 (answers
  ((get raw "/raw/big-header?bytes=102400") (refused perform-failed 27))
  ((get raw "/raw/big-header?bytes=1048576") (refused perform-failed 27))
  ((get raw "/raw/many-headers?count=50000") (refused perform-failed 56))
  ((get raw "/raw/bad-status-code") (refused perform-failed 1))
  ((get raw "/raw/conflicting-content-length")
   (response 200 http/1.1 (("Content-Length" "5") ("Content-Length" "6")) "hello\n"))
  ((error-text raw "/raw/nul-in-header") (error-text "Nul byte in header"))))

(libcurl
 (where "Apple's libcurl 8.7.1, /usr/lib/libcurl.4.dylib with SecureTransport (LibreSSL/3.3.6), on the maintainer's M1: macOS 26.7.1, Homebrew's Chez as tarm64osx, Node 20.10.0 through asdf. Printed by test-transfer there on 2026-10-24, whose shared answers all passed. many-headers at 50,000 is not yet measured there: its cell is 100,000's until the Mac's next test-transfer. 8.7.1's lib/http.h caps a response's headers at 300 KiB, and 50,000 are about 690 KB.")
 (version "8.7.1")
 (answers
  ((get raw "/raw/big-header?bytes=102400") (refused perform-failed 100))
  ((get raw "/raw/big-header?bytes=1048576") (refused perform-failed 100))
  ((get raw "/raw/many-headers?count=50000") (refused perform-failed 56))
  ((get raw "/raw/bad-status-code") (refused perform-failed 1))
  ((get raw "/raw/conflicting-content-length")
   (response 200 http/1.1 (("Content-Length" "5") ("Content-Length" "6")) "hello\n"))
  ((error-text raw "/raw/nul-in-header") (error-text "Nul byte in header"))))

(libcurl
 (where "The pinned Guix container (scripts/guix-env, ADR-0006): the profile's curl 8.20.0 with GnuTLS 3.8.13. Measured through C in the container, Node 24.18.0, on 2026-10-23 (M2 plan, section 5.1.1). many-headers at 50,000, 100,000's answer: measured in the container on 2026-11-01 (build/cifix).")
 (version "8.20.0")
 (answers
  ((get raw "/raw/big-header?bytes=102400") (refused perform-failed 100))
  ((get raw "/raw/big-header?bytes=1048576") (refused perform-failed 100))
  ((get raw "/raw/many-headers?count=50000") (refused perform-failed 100))
  ((get raw "/raw/bad-status-code") (response 200 http/1.1 (("Content-Length" "6")) "hello\n"))
  ((get raw "/raw/conflicting-content-length") (refused perform-failed 8))
  ((error-text raw "/raw/nul-in-header") (error-text "Nul byte in header"))))

(libcurl
 (where "The current libcurl, curl 8.23.0 built by scripts/ci/build-curl.sh --current on Ubuntu 24.04 with OpenSSL 3.0.13: the library CI's current lane loads (ADR-0020, amended 2026-10-26). Printed by test-transfer in Docker ubuntu:24.04, Node 24.18.0, on 2026-10-26: 8.20.0's answers, and nul-in-header's text capitalised. many-headers at 50,000, 100,000's answer: measured in Docker on 2026-11-01 (build/cifix).")
 (version "8.23.0")
 (answers
  ((get raw "/raw/big-header?bytes=102400") (refused perform-failed 100))
  ((get raw "/raw/big-header?bytes=1048576") (refused perform-failed 100))
  ((get raw "/raw/many-headers?count=50000") (refused perform-failed 100))
  ((get raw "/raw/bad-status-code") (response 200 http/1.1 (("Content-Length" "6")) "hello\n"))
  ((get raw "/raw/conflicting-content-length") (refused perform-failed 8))
  ((error-text raw "/raw/nul-in-header") (error-text "NUL byte in header"))))
