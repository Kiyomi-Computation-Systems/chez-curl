#!/bin/sh
# M6 slice 1 (2026-10-30): wake.c, built against one libcurl, against
# server.mjs. Run from the repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/wake.sh guix-8.20.0' < /dev/null
# or in Docker by docker-wake.sh. CURL_LIB is the libcurl.so.4 to link;
# CURL_INCLUDE its headers, by default CURL_LIB's ../include when it holds
# curl/curl.h, else the compiler's; CC, cc; NODE, node; OPENSSL, openssl.
# Each case runs wake on the http face's /body of 262,144 bytes, 16 KiB a
# write: zeros, gzip-encoded, for the paused cases; i mod 251 written 50 ms
# apart for plain; under a bound of 120 s. Every line it prints begins
# [LANE].
set -u
[ "$#" -eq 1 ] || { echo "usage: wake.sh LANE" >&2; exit 2; }
d=.plans/research/m6/slice1
[ -f $d/wake.c ] || { echo "wake.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
tmp=$(mktemp -d "${TMPDIR:-/tmp}/wake.XXXXXX") || exit 1
pid=
cleanup() {
  exec 3>&-
  [ -n "$pid" ] && wait "$pid"
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=${CURL_INCLUDE:-}
if [ -z "$inc" ] && [ -f "$(dirname "$CURL_LIB")/../include/curl/curl.h" ]; then inc=$(dirname "$CURL_LIB")/../include; fi
"${CC:-cc}" ${inc:+-I"$inc"} -o "$tmp/wake" $d/wake.c "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2> "$tmp/cc.err" \
  || { echo "[$lane] the compile failed"; sed "s/^/[$lane] cc: /" "$tmp/cc.err"; exit 1; }
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" > /dev/null 2>&1 || { echo "[$lane] make-test-pki failed"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" $d/server.mjs "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 200 ] || { echo "[$lane] no ports"; exit 1; }; sleep 0.1; done
http=$(sed 's/.*"http":"\([^"]*\)".*/\1/' "$tmp/ports")
echo "[$lane] libcurl $CURL_LIB headers ${inc:-the compiler's}; server $(cat "$tmp/ports")"
for spec in "none pattern=zero&gzip=1" "before-poll pattern=zero&gzip=1" "after pattern=zero&gzip=1" \
            "pause pattern=zero&gzip=1" "plain gap=50"; do
  set -- $spec
  q=$(printf '%s' "$2" | sed 's/&/\\\&/g')
  timeout 120 "$tmp/wake" "http://$http/body?n=262144&chunk=16384&$2" "$1" < /dev/null 2>&1 | sed "s/^/[$lane] query=$q /"
done
[ -s "$tmp/server.err" ] && sed "s/^/[$lane] server-stderr: /" "$tmp/server.err"
exit 0
