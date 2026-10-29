#!/bin/sh
# M5 slice 3's retry measurement (2026-10-28; the M5 plan, section 6.1), on
# one libcurl: probe.sps against server.mjs, with this run's PKI. Run from
# the repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/retry/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh. CURL_LIB is the libcurl chez-curl loads; CHEZ,
# scheme; NODE, node; OPENSSL, openssl.
#
# On the Mac, against Apple's libcurl, which discovery finds:
#   CHEZ=chez NODE="$(asdf which node)" sh .plans/research/m5/retry/run.sh mac
# The probe hands every request the run's CA file, which a submit refuses
# while Apple's LibreSSL is in use (ADR-0018, amended), so on macOS this sets
# CURL_SSL_BACKEND=secure-transport, as make test does, unless it is set.
# The first Mac run, 2026-10-29, had no such line, and every request was
# refused (results/mac-8.7.1-refused.log).
set -u
if [ "$(uname -s)" = Darwin ]; then
  CURL_SSL_BACKEND=${CURL_SSL_BACKEND:-secure-transport}
  export CURL_SSL_BACKEND
fi
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
d=.plans/research/m5/retry
[ -f $d/probe.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/retry.XXXXXX") || exit 1
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
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" || { echo "[$lane] make-test-pki failed"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" $d/server.mjs "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] $(cat "$tmp/ports")"
set -- $(sed 's/[a-z0-9]*=//g' "$tmp/ports")
if [ -n "${CURL_LIB:-}" ]; then
  CHEZ_CURL_LIBCURL=$CURL_LIB "${CHEZ:-scheme}" --libdirs src --program $d/probe.sps "$@" "$tmp/pki/ca.pem" < /dev/null 2>&1 | sed "s/^/[$lane] /"
else
  "${CHEZ:-scheme}" --libdirs src --program $d/probe.sps "$@" "$tmp/pki/ca.pem" < /dev/null 2>&1 | sed "s/^/[$lane] /"
fi
[ -s "$tmp/server.err" ] && sed "s/^/[$lane] server: /" "$tmp/server.err"
exit 0
