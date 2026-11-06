#!/bin/sh
# M8's header-caps probe (2026-11-06; the M8 plan's measurements, ADR-0038
# decision 2), on one libcurl: probe.c, built against that libcurl, against
# server.mjs, with this run's PKI. Run from the repository's root, in the
# container, pinned on the host:
#   taskset -c 12-17 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/caps/run.sh guix-8.20.0' < /dev/null
# in Docker by docker.sh, or on the Mac by mac.sh. CURL_LIB is a
# libcurl.so.4 to link; CURL_INCLUDE, the headers to compile against, by
# default the lane's own: CURL_LIB's ../include when it holds curl/curl.h,
# else the compiler's. NODE, node; CC, cc; OPENSSL, openssl
# (tests/make-test-pki.sh); CASES, the cases to run, by default
# "count bytes toward walk"; PROBE_MODES, WALK_NS and WALK_ROUNDS are
# passed to the probe (probe.c's header).
#
# PROBE_VALGRIND=FILE runs the walk case alone, under Valgrind with the
# memory gate's options (ADR-0014; the Makefile's test-memory): -v
# --command-line-only=yes --log-file=FILE --error-exitcode=9
# --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite,
# and in a Guix environment --suppressions=tests/guix-glibc-locpath.supp;
# WALK_NS "1000 5000" and WALK_ROUNDS 3 unless set. The server runs
# natively. FILE is where Valgrind writes its log.
#
# On the Mac, against Apple's libcurl by -lcurl and the SDK's headers, with
# CURL_LIB unset. The probe hands every TLS transfer the run's CA file, which
# Apple's LibreSSL undoes by its keychain fallback, so on macOS this sets
# CURL_SSL_BACKEND=secure-transport, as make test does, unless it is set.
#
# It unsets the proxy variables and SSL_CERT_FILE and SSL_CERT_DIR (Guix's
# 8.20.0 writes those over CAINFO and CAPATH). Every line it prints begins
# [LANE]; it writes nothing outside its mktemp directory but stdout, and
# Valgrind's log.
set -u
if [ "$(uname -s)" = Darwin ]; then
  CURL_SSL_BACKEND=${CURL_SSL_BACKEND:-secure-transport}
  export CURL_SSL_BACKEND
fi
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
d=.plans/research/m8/caps
[ -f $d/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR
lane=$1
cases=${CASES:-"count bytes toward walk"}
vg=${PROBE_VALGRIND:-}
if [ -n "$vg" ]; then
  cases=walk
  WALK_NS=${WALK_NS:-"1000 5000"}
  WALK_ROUNDS=${WALK_ROUNDS:-3}
fi
export PROBE_MODES="${PROBE_MODES:-}" WALK_NS="${WALK_NS:-}" WALK_ROUNDS="${WALK_ROUNDS:-}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8caps.XXXXXX") || exit 1
pid=
# The server exits once its stdin ends. A watchdog ends it 5 s after that
# closes, and says so.
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
inc=${CURL_INCLUDE:-}
if [ -z "$inc" ] && [ -n "${CURL_LIB:-}" ] && [ -f "$(dirname "$CURL_LIB")/../include/curl/curl.h" ]; then
  inc=$(dirname "$CURL_LIB")/../include
fi
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" -O2 ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
else
  "${CC:-cc}" -O2 ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" -lcurl 2>"$tmp/cc.err"
fi
cc_status=$?
[ "$cc_status" -eq 0 ] || { echo "[$lane] the compile exited $cc_status"; sed "s/^/[$lane] cc: /" "$tmp/cc.err"; exit 1; }
if [ -n "${CURL_LIB:-}" ]; then
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB" 2>/dev/null || echo "$CURL_LIB"), headers ${inc:-the compiler's}"
else
  echo "[$lane] libcurl by -lcurl, headers ${inc:-the compiler's}"
fi
echo "[$lane] node $("${NODE:-node}" --version) uname $(uname -sm) CURL_SSL_BACKEND=${CURL_SSL_BACKEND:-unset} cpus=$(nproc 2>/dev/null || sysctl -n hw.ncpu) affinity=$(sed -n 's/^Cpus_allowed_list:[[:space:]]*//p' /proc/self/status 2>/dev/null)"
echo "[$lane] cases=$cases PROBE_MODES=${PROBE_MODES:-default} WALK_NS=${WALK_NS:-default} WALK_ROUNDS=${WALK_ROUNDS:-default} PROBE_VALGRIND=${vg:-unset}"
"$tmp/probe" --version 2>&1 | sed "s/^/[$lane] /"
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" || { echo "[$lane] make-test-pki failed"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] server $(cat "$tmp/ports")"
set -- $(sed 's/[a-z0-9]*=//g' "$tmp/ports")
count=0
for c in $cases; do
  start=$(date +%s)
  if [ -n "$vg" ]; then
    supp=
    [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
    # shellcheck disable=SC2086
    { valgrind -v --command-line-only=yes "--log-file=$vg" --error-exitcode=9 --leak-check=full --show-leak-kinds=definite \
        --errors-for-leak-kinds=definite $supp "$tmp/probe" "$c" "$1" "$2" "$3" "$4" "$5" "$tmp/pki/ca.pem" < /dev/null 2>&1; echo "probe $c exit=$?"; } | sed "s/^/[$lane] /"
    echo "[$lane] valgrind $(valgrind --version) log $vg: $(grep -c . "$vg") lines; $(grep 'ERROR SUMMARY' "$vg" | tail -1)"
  else
    { "$tmp/probe" "$c" "$1" "$2" "$3" "$4" "$5" "$tmp/pki/ca.pem" < /dev/null 2>&1; echo "probe $c exit=$?"; } | sed "s/^/[$lane] /"
  fi
  echo "[$lane] probe $c took about $(( $(date +%s) - start )) s"
  count=$((count+1))
done
echo "[$lane] -- $count cases run"
exit 0
