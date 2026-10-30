#!/bin/sh
# M6 slice 1's measurements (2026-10-30; the M6 plan, section 4.1), on one
# libcurl: PROGRAM.sps, run on the prototype in build/m6s1/src, against
# server.mjs with this run's PKI. Run from the repository's root, after
# build.sh has made the prototype on the host, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 check' < /dev/null
# under the memory gate's Valgrind, its options exactly, and in the
# container its one suppression:
#   scripts/guix-env sh -c 'VALGRIND=valgrind CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0-valgrind paced 2' < /dev/null
# or in Docker by docker.sh.
#
#   run.sh LANE PROGRAM [ARG...]
#
# PROGRAM is check, paced, replay, head, escape or throughput; each ARG goes
# to it after the faces and the CA file. CURL_LIB is the libcurl chez-curl
# loads; CHEZ, scheme; NODE, node; OPENSSL, openssl (tests/make-test-pki.sh);
# VALGRIND, when set, runs the program under it with the gate's options, its
# log file in this run's directory, and prints Valgrind's evidence from that
# file alone. CHILD_PROXY=1 hands the program, and it alone, https_proxy at
# the server's proxy face, through env.
#
# It checks the prototype first: build/m6s1/src must hold exactly what
# build.sh made from src/ and proto.patch, by the sums build.sh wrote. It
# unsets every proxy variable, SSL_CERT_FILE and SSL_CERT_DIR. Every line it
# prints begins [LANE]; it writes nothing outside its mktemp directory but
# stdout.
set -u
[ "$#" -ge 2 ] || { echo "usage: run.sh LANE PROGRAM [ARG...]" >&2; exit 2; }
d=.plans/research/m6/slice1
[ -f $d/proto.patch ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
program=$2
shift 2
[ -f "$d/$program.sps" ] || { echo "run.sh: no program $d/$program.sps" >&2; exit 2; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
want=$(sha256sum $d/proto.patch | cut -d' ' -f1)
have=$(cat build/m6s1/patch.sha256 2>/dev/null)
if [ "$want" != "$have" ]; then
  echo "[$lane] build/m6s1/src was not made from this proto.patch ($want, made from '${have:-nothing}'): run build.sh on the host"
  exit 1
fi
if ! (cd build/m6s1/src && sha256sum -c --quiet ../src.sha256) > /dev/null 2>&1; then
  echo "[$lane] build/m6s1/src differs from what build.sh made: run build.sh on the host"
  exit 1
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m6s1.XXXXXX") || exit 1
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
echo "[$lane] prototype build/m6s1/src from proto.patch $want"
echo "[$lane] server $(cat "$tmp/ports")"
echo "[$lane] uname $(uname -sm) chez ${CHEZ:-scheme} libcurl ${CURL_LIB:-discovered}"
proxy=$(face proxy)
set -- "${CHEZ:-scheme}" --libdirs build/m6s1/src --program "$d/$program.sps" \
  "$(face http)" "$(face raw)" "$(face https)" "$(face h2)" "$proxy" "$tmp/pki/ca.pem" "$@"
if [ -n "${VALGRIND:-}" ]; then
  supp=
  [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
  set -- "$VALGRIND" -v --command-line-only=yes "--log-file=$tmp/valgrind.log" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $supp "$@"
  echo "[$lane] under $VALGRIND $(valgrind --version 2>/dev/null)"
fi
if [ "${CHILD_PROXY:-}" = 1 ]; then
  set -- env "https_proxy=http://$proxy" "$@"
  echo "[$lane] the program's own environment: https_proxy=http://$proxy"
fi
if [ -n "${CURL_LIB:-}" ]; then
  set -- env "CHEZ_CURL_LIBCURL=$CURL_LIB" "$@"
fi
start=$(date +%s)
{ "$@" < /dev/null 2>&1; echo "$?" > "$tmp/status"; } | sed -u "s/^/[$lane] /"
status=$(cat "$tmp/status")
echo "[$lane] $program exited $status after about $(( $(date +%s) - start )) s"
if [ -n "${VALGRIND:-}" ]; then
  if [ -f "$tmp/valgrind.log" ]; then
    grep -E '^==[0-9]+== (Command:|ERROR SUMMARY|   definitely lost|.*used_suppression)|^--[0-9]+-- +used_suppression' "$tmp/valgrind.log" | sed "s/^/[$lane] valgrind: /"
  else
    echo "[$lane] valgrind: no log file"
  fi
fi
exit 0
