#!/bin/sh
# M5 slice 4's group measurement (2026-10-28; the M5 plan, section 7.1), on
# one libcurl: probe.sps against tests/origin.mjs's raw face. Run from the
# repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/group/run.sh guix-8.20.0 3' < /dev/null
# and under the memory gate's Valgrind, its options but the log file:
#   scripts/guix-env sh -c 'VALGRIND=valgrind CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/group/run.sh guix-8.20.0-valgrind 3' < /dev/null
# or in Docker by docker.sh. CURL_LIB is the libcurl chez-curl loads; CHEZ,
# scheme; NODE, node; VALGRIND, when set, runs the probe under it.
#
# On the Mac, against Apple's libcurl, which discovery finds:
#   CHEZ=chez NODE="$(asdf which node)" sh .plans/research/m5/group/run.sh mac 3
set -u
[ "$#" -eq 2 ] || { echo "usage: run.sh LANE RUNS" >&2; exit 2; }
d=.plans/research/m5/group
[ -f $d/probe.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
runs=$2
tmp=$(mktemp -d "${TMPDIR:-/tmp}/group.XXXXXX") || exit 1
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
    [ "$status" -eq 0 ] || echo "[$lane] the origin exited $status, not 0, after its stdin closed: 143 is the watchdog's kill, 5 s on"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
mkfifo "$tmp/in"
"${NODE:-node}" tests/origin.mjs < "$tmp/in" > "$tmp/ports" 2> "$tmp/origin.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/origin.err"; exit 1; }; sleep 0.1; done
raw=$(sed 's/.*"raw":"\([^"]*\)".*/\1/' "$tmp/ports")
echo "[$lane] origin $(cat "$tmp/ports")"
set -- "${CHEZ:-scheme}" --libdirs src --program $d/probe.sps "$raw" "$runs"
if [ -n "${VALGRIND:-}" ]; then
  set -- "$VALGRIND" --command-line-only=yes "--log-file=$tmp/valgrind.log" --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite \
    ${VALGRIND_SUPP:+--suppressions=$VALGRIND_SUPP} "$@"
  echo "[$lane] under $VALGRIND"
fi
if [ -n "${CURL_LIB:-}" ]; then
  CHEZ_CURL_LIBCURL=$CURL_LIB "$@" < /dev/null 2>&1 | sed "s/^/[$lane] /"
else
  "$@" < /dev/null 2>&1 | sed "s/^/[$lane] /"
fi
[ -z "${VALGRIND:-}" ] || grep -E 'ERROR SUMMARY|definitely lost' "$tmp/valgrind.log" | sed "s/^/[$lane] valgrind: /"
[ -s "$tmp/origin.err" ] && sed "s/^/[$lane] origin: /" "$tmp/origin.err"
exit 0
