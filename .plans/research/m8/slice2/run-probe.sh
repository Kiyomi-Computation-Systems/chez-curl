#!/bin/sh
# M8 slice 2's probes on one lane, from a tree's root (the probe's tree for
# engine-probe.sps; main's and the prototype's for cost.sps), against the caps
# stand-in, research/m8/caps/server.mjs, which lanes.sh copies into the tree's
# m8s2/ beside the programs:
#   sh m8s2/run-probe.sh LANE PROGRAM [ARG...]
# PROGRAM is m8s2/engine-probe.sps, given LANE CTL H1 H1TLS H2 PROXY CA and
# ARG, or m8s2/cost.sps, given LANE H1 and ARG. CHEZ runs it, with src alone
# on the library path, as the caps probe's case 6 did; CHEZ_CURL_LIBCURL is the
# lane's libcurl. SERVER, the stand-in, m8s2/server.mjs by default:
# m8s2/server-limits.mjs is the variant whose h2 limits H2_LIMITS names.
# VALGRIND=FILE runs CHEZ under Valgrind with the memory
# gate's options (ADR-0014; the Makefile's test-memory): -v
# --command-line-only=yes --log-file=FILE --error-exitcode=9 --leak-check=full
# --show-leak-kinds=definite --errors-for-leak-kinds=definite, and in a Guix
# environment the gate's one suppression. The stand-in runs natively.
#
# It unsets the proxy variables, SSL_CERT_FILE and SSL_CERT_DIR. Every line it
# prints begins [LANE]; it writes nothing outside its mktemp directory but
# stdout, and Valgrind's log.
set -u
[ "$#" -ge 2 ] || { echo "usage: run-probe.sh LANE PROGRAM [ARG...]" >&2; exit 2; }
[ -f m8s2/server.mjs ] || { echo "run-probe.sh: no m8s2/server.mjs: run it from a tree's root" >&2; exit 2; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR
lane=$1; program=$2; shift 2
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8s2.XXXXXX") || exit 1
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
echo "[$lane] tree $(pwd) chez ${CHEZ:-scheme} $("${CHEZ:-scheme}" --version 2>&1) libcurl ${CHEZ_CURL_LIBCURL:-unset} node $("${NODE:-node}" --version) program $program sha256 $(sha256sum "$program" | cut -c1-16) transfer.sls sha256 $(sha256sum src/curl/private/transfer.sls | cut -c1-16) affinity=$(sed -n 's/^Cpus_allowed_list:[[:space:]]*//p' /proc/self/status 2>/dev/null) valgrind=${VALGRIND:-unset}"
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" > "$tmp/pki.out" 2>&1 || { echo "[$lane] make-test-pki failed"; cat "$tmp/pki.out"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" "${SERVER:-m8s2/server.mjs}" "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] server $(cat "$tmp/ports")"
port() { sed "s/.*$1=\([0-9]*\).*/\1/" "$tmp/ports"; }
case $program in
  *engine-probe.sps) set -- "$lane" "$(port ctl)" "$(port h1)" "$(port h1tls)" "$(port h2)" "$(port proxy)" "$tmp/pki/ca.pem" "$@" ;;
  *) set -- "$lane" "$(port h1)" "$@" ;;
esac
start=$(date +%s)
if [ -n "${VALGRIND:-}" ]; then
  supp=
  [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
  # shellcheck disable=SC2086
  { valgrind -v --command-line-only=yes "--log-file=$VALGRIND" --error-exitcode=9 --leak-check=full --show-leak-kinds=definite \
      --errors-for-leak-kinds=definite $supp "${CHEZ:-scheme}" --libdirs src --program "$program" "$@" < /dev/null 2>&1; echo "program exit=$?"; } | sed "s/^/[$lane] /"
  echo "[$lane] valgrind $(valgrind --version) log $VALGRIND: $(grep 'ERROR SUMMARY' "$VALGRIND" | tail -1)"
else
  { "${CHEZ:-scheme}" --libdirs src --program "$program" "$@" < /dev/null 2>&1; echo "program exit=$?"; } | sed "s/^/[$lane] /"
fi
echo "[$lane] took about $(( $(date +%s) - start )) s"
exit 0
