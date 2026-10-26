;; The libcurls the suites have been recorded against (ADR-0017). Each row is
;; one library that curl_version_info has answered for, and tests/test-drift.sps
;; passes only when the libcurl a run loads equals exactly one row on its
;; version, version-num, features, ssl-version and host. `where` is a note for
;; the reader and is not compared, nor is the path the library loaded from.
;;
;; A libcurl with no row fails make test, wherever it runs: a new OS package, a
;; macOS update, a bumped Guix pin, or a different build of the floor. Adding a
;; row, or changing one, is a reviewed change. To add one, run
;; `make test`: test-drift prints the loaded library's row on the error
;; port, naming this file. Review what changed, paste the row here, and
;; replace its `where` with where the library runs and the package versions.
;; Bumping the Guix pin (channels.scm) updates the container's row in the same
;; change.
;;
;; The file is data: rows only, nothing else. Each is exactly
;;   (libcurl (where STRING) (version STRING) (version-num NATURAL)
;;            (features NATURAL) (ssl-version STRING) (host STRING))
;; with those six fields in that order. features is the whole word, so a
;; libcurl built with another library (brotli, zstd, a different IDN) differs.
;; Two rows may not be equal on the five compared fields.

(libcurl
 (where "The pinned Guix container (scripts/guix-env, ADR-0006): the profile's curl 8.20.0 with GnuTLS 3.8.13. Measured in the container on 2026-10-18 with tests/libcurl-oracle.c.")
 (version "8.20.0")
 (version-num 529408)
 (features 1430210445)
 (ssl-version "GnuTLS/3.8.13")
 (host "x86_64-unknown-linux-gnu"))

(libcurl
 (where "Ubuntu 24.04's libcurl4t64 8.5.0-2ubuntu10.16 with libssl3t64 3.0.13-0ubuntu3.16, the library CI's main and memory lanes load. Measured in Docker ubuntu:24.04 (24.04.5) on 2026-10-18 with tests/libcurl-oracle.c, against /usr/lib/x86_64-linux-gnu/libcurl.so.4.")
 (version "8.5.0")
 (version-num 525568)
 (features 1438599069)
 (ssl-version "OpenSSL/3.0.13")
 (host "x86_64-pc-linux-gnu"))

(libcurl
 (where "Ubuntu 24.04's libcurl3t64-gnutls 8.5.0-2ubuntu10.16 with libgnutls30t64 3.8.3-1.1ubuntu3.6, the library CI's GnuTLS lane loads through CHEZ_CURL_LIBCURL, against libcurl4-openssl-dev's headers. Printed by test-drift in Docker ubuntu:24.04 on 2026-10-24, against /usr/lib/x86_64-linux-gnu/libcurl-gnutls.so.4.")
 (version "8.5.0")
 (version-num 525568)
 (features 1438599069)
 (ssl-version "GnuTLS/3.8.3")
 (host "x86_64-pc-linux-gnu"))

(libcurl
 (where "The floor, curl 7.85.0 built by scripts/ci/build-curl.sh on Ubuntu 24.04 with OpenSSL 3.0.13 (libssl-dev 3.0.13-0ubuntu3.16), zlib1g-dev 1:1.3.dfsg-3.1ubuntu2.2 and libnghttp2-dev 1.59.0-1ubuntu0.4: the library the floor lanes load. Measured in Docker ubuntu:24.04 on 2026-10-18 with tests/libcurl-oracle.c, with only packaging/debian-prereqs.txt installed, and again with ten more -dev packages installed: the same five fields.")
 (version "7.85.0")
 (version-num 480512)
 (features 1361691293)
 (ssl-version "OpenSSL/3.0.13")
 (host "x86_64-pc-linux-gnu"))

(libcurl
 (where "Curl 8.20.0 built by scripts/ci/build-curl.sh --current on Ubuntu 24.04 with OpenSSL 3.0.13 (libssl3t64 3.0.13-0ubuntu3.16): the library CI's current lane loaded until 8.23.0 took its place, the same day (ADR-0020, amended 2026-10-26). Printed by test-drift in Docker ubuntu:24.04 on 2026-10-26, against that build's lib/libcurl.so.4.")
 (version "8.20.0")
 (version-num 529408)
 (features 1361658509)
 (ssl-version "OpenSSL/3.0.13")
 (host "x86_64-pc-linux-gnu"))

(libcurl
 (where "The current libcurl, curl 8.23.0 built by scripts/ci/build-curl.sh --current on Ubuntu 24.04 with OpenSSL 3.0.13 (libssl3t64 3.0.13-0ubuntu3.16): the library CI's current lane loads (ADR-0020, amended 2026-10-26). Its features are 8.20.0's less TLSAUTH_SRP, which 8.23.0 dropped. Printed by test-drift in Docker ubuntu:24.04 on 2026-10-26, against that build's lib/libcurl.so.4.")
 (version "8.23.0")
 (version-num 530176)
 (features 1361642125)
 (ssl-version "OpenSSL/3.0.13")
 (host "x86_64-pc-linux-gnu"))

(libcurl
 (where "Apple's libcurl 8.7.1, /usr/lib/libcurl.4.dylib, on the maintainer's Mac: Apple M1, macOS 26.7.1, loaded by Homebrew's Chez as tarm64osx. Its host names x86_64, though the process is arm64 (ADR-0001, amended 2026-10-23). Printed by test-drift there on 2026-10-23.")
 (version "8.7.1")
 (version-num 526081)
 (features 1364132765)
 (ssl-version "SecureTransport (LibreSSL/3.3.6)")
 (host "x86_64-apple-darwin25.0"))
