#!/bin/sh
# M6 slice 3's measurements (2026-10-31; the M6 plan, section 6.1), on one
# libcurl: PROGRAM.sps, run on main's own src/, against server.mjs with this
# run's PKI. Run from the repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice3/run.sh guix-8.20.0 drive ARG...' < /dev/null
# under the memory gate's Valgrind, its options exactly, and in the
# container its one suppression:
#   scripts/guix-env sh -c 'VALGRIND=valgrind CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice3/run.sh guix-8.20.0-valgrind drive ARG...' < /dev/null
# or in Docker by docker.sh.
#
#   run.sh LANE PROGRAM [ARG...]
#
# PROGRAM gets the faces http, raw, https, h2 and closed, each HOST:PORT,
# then the CA file, then each ARG. CURL_LIB is the libcurl chez-curl loads;
# CHEZ, scheme; NODE, node; OPENSSL, openssl (tests/make-test-pki.sh);
# BOUND, the seconds GNU timeout gives the program, 3600 by default, and
# timeout wraps Valgrind, never sitting between it and Chez; VALGRIND, when
# set, runs the program under it with the gate's options, its log file in
# this run's directory, and prints Valgrind's evidence from that file
# alone. LIBDIRS, by default src:tests:build/scheme-libs, is the library
# path: main's own src/, and tests/ for (curl-testing), whose origin
# asked.sps runs.
#
# It prints a hash of src/'s libraries on its first lines, so a log says
# what it ran on. It unsets every proxy variable, SSL_CERT_FILE and
# SSL_CERT_DIR. Every line it prints begins [LANE]; it writes nothing
# outside its mktemp directory but stdout. The server's stderr, its
# unfetched tags and its counts, is printed as server-stderr lines once its
# stdin closes.
set -u
[ "$#" -ge 2 ] || { echo "usage: run.sh LANE PROGRAM [ARG...]" >&2; exit 2; }
d=.plans/research/m6/slice3
[ -f $d/server.mjs ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
program=$2
shift 2
[ -f "$d/$program.sps" ] || { echo "run.sh: no program $d/$program.sps" >&2; exit 2; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m6s3.XXXXXX") || exit 1
pid=
cleanup() {
  exec 3>&-
  if [ -n "$pid" ]; then
    ( sleep 5; kill "$pid" 2>/dev/null ) > /dev/null 2>&1 &
    watchdog=$!
    wait "$pid"
    status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    [ "$status" -eq 0 ] || echo "[$lane] the server exited $status, not 0, after its stdin closed: 143 is the watchdog's kill, 5 s on"
    [ -s "$tmp/server.err" ] && sed "s/^/[$lane] server-stderr: /" "$tmp/server.err"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" > "$tmp/pki.out" 2>&1 || { echo "[$lane] make-test-pki failed"; sed "s/^/[$lane] pki: /" "$tmp/pki.out"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" $d/server.mjs "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 200 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
face() { sed "s/.*\"$1\":\"\([^\"]*\)\".*/\1/" "$tmp/ports"; }
libdirs=${LIBDIRS:-src:tests:build/scheme-libs}
if command -v sha256sum > /dev/null 2>&1; then sum() { sha256sum "$@"; }; else sum() { shasum -a 256 "$@"; }; fi
echo "[$lane] src $(find src -type f -name '*.sls' | LC_ALL=C sort | xargs cat | sum | cut -d' ' -f1) (sha256 of src/'s libraries, concatenated in sorted path order)"
echo "[$lane] program $d/$program.sps $(sum "$d/$program.sps" | cut -d' ' -f1)"
echo "[$lane] libdirs $libdirs"
echo "[$lane] server $(cat "$tmp/ports")"
echo "[$lane] uname $(uname -sm) chez ${CHEZ:-scheme} libcurl ${CURL_LIB:-discovered} node $("${NODE:-node}" --version)"
set -- "${CHEZ:-scheme}" --libdirs "$libdirs" --program "$d/$program.sps" \
  "$(face http)" "$(face raw)" "$(face https)" "$(face h2)" "$(face closed)" "$tmp/pki/ca.pem" "$@"
if [ -n "${VALGRIND:-}" ]; then
  supp=
  [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
  set -- "$VALGRIND" -v --command-line-only=yes "--log-file=$tmp/valgrind.log" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $supp "$@"
  echo "[$lane] under $VALGRIND $(valgrind --version 2>/dev/null)"
fi
if [ -n "${CURL_LIB:-}" ]; then
  set -- env "CHEZ_CURL_LIBCURL=$CURL_LIB" "$@"
fi
# GNU timeout, or Homebrew coreutils' gtimeout on macOS.
tmo=$(command -v timeout || command -v gtimeout) || { echo "[$lane] no GNU timeout"; exit 1; }
set -- "$tmo" "${BOUND:-3600}" "$@"
start=$(date +%s)
{ "$@" < /dev/null 2>&1; echo "$?" > "$tmp/status"; } | sed -u "s/^/[$lane] /"
status=$(cat "$tmp/status")
echo "[$lane] $program exited $status after about $(( $(date +%s) - start )) s (124 is timeout's)"
if [ -n "${VALGRIND:-}" ]; then
  if [ -f "$tmp/valgrind.log" ]; then
    grep -E '^==[0-9]+== (Command:|ERROR SUMMARY|   definitely lost|.*used_suppression)|^--[0-9]+-- +used_suppression' "$tmp/valgrind.log" | sed "s/^/[$lane] valgrind: /"
  else
    echo "[$lane] valgrind: no log file"
  fi
fi
exit 0
