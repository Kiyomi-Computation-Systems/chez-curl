;;; Development toolchain for chez-curl (ADR-0006).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and runs
;;; this manifest in a container with no network. Plain
;;; `guix shell -m manifest.scm` also loads this file, but against whatever
;;; Guix you have pulled.

(specifications->manifest
 '(;; Threaded Chez, and libcurl bound with no C shim (ADR-0001). "curl"
   ;; brings libcurl.so.4 and its headers (ADR-0003); gcc-toolchain compiles
   ;; the test-time program that checks constants against those headers.
   "chez-scheme" "curl" "gcc-toolchain"
   ;; The test origin, and its TLS material made fresh each run (ADR-0005).
   "node" "openssl"
   ;; The memory gate (ADR-0014).
   "valgrind"
   ;; `make site` renders docs/ through chez-cmark-gfm, which loads this C
   ;; library by the absolute paths scripts/guix-env-enter exports (ADR-0042).
   "cmark-gfm"
   ;; What the Makefile and scripts shell out to; tar and xz unpack the
   ;; archive scripts/fetch-akku-lock holds chez-cmark-gfm's tree to, and
   ;; build the ones tests/fetch-akku-lock.sh makes. The container has
   ;; nothing else.
   "bash" "coreutils" "make" "grep" "sed" "gawk" "findutils" "diffutils"
   "tar" "xz"))
