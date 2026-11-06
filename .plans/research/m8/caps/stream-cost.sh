#!/bin/sh
# M8's header-caps probe, case 6 (2026-11-06): stream-cost.sps through
# today's (curl), on lane X alone, against server.mjs's h1 face. Run from the
# repository's root, pinned on the host:
#   taskset -c 12-17 scripts/guix-env sh .plans/research/m8/caps/stream-cost.sh guix-8.20.0 < /dev/null
# It runs $CHEZ (the container's) with src alone on the library path, as
# make test runs a suite with src first; ROUNDS (7) rounds; PROGRAM, the
# program, by default this directory's stream-cost.sps. Every line it prints
# begins [LANE]; it writes nothing outside its mktemp directory but stdout.
set -u
[ "$#" -eq 1 ] || { echo "usage: stream-cost.sh LANE" >&2; exit 2; }
d=.plans/research/m8/caps
[ -f $d/server.mjs ] || { echo "stream-cost.sh: run it from the repository's root" >&2; exit 2; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR
lane=$1
program=${PROGRAM:-$d/stream-cost.sps}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8c6.XXXXXX") || exit 1
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
echo "[$lane] chez ${CHEZ:-scheme} $("${CHEZ:-scheme}" --version 2>&1) libcurl ${CHEZ_CURL_LIBCURL:-unset} node $("${NODE:-node}" --version) program $program sha256 $(sha256sum "$program" | cut -c1-16) affinity=$(sed -n 's/^Cpus_allowed_list:[[:space:]]*//p' /proc/self/status 2>/dev/null)"
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" || { echo "[$lane] make-test-pki failed"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] server $(cat "$tmp/ports")"
h1=$(sed 's/.* h1=\([0-9]*\) .*/\1/' "$tmp/ports")
start=$(date +%s)
{ "${CHEZ:-scheme}" --libdirs src --program "$program" "$h1" "${ROUNDS:-7}" < /dev/null 2>&1; echo "program exit=$?"; } | sed "s/^/[$lane] /"
echo "[$lane] took about $(( $(date +%s) - start )) s"
exit 0
