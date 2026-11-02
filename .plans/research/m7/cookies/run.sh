#!/bin/sh
# M7's cookie probe (2026-11-02; the M7 plan's measurements), on one
# libcurl: probe.c, built against that libcurl, against server.mjs. Run from
# the repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/cookies/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh, or on the Mac by mac.sh. CURL_LIB is a
# libcurl.so.4 to link, unset on macOS (-lcurl); CURL_INCLUDE, the headers
# to compile against, by default the lane's own: CURL_LIB's ../include when
# it holds curl/curl.h, else the compiler's. NODE, node; CC, cc; CASES, the
# cases to run, by default every one probe --list names.
#
# Each case runs in an empty working directory, its stdin a pipe holding one
# known line, its stdout and stderr each to a file of their own, its log to
# a third (PROBE_LOG): after it, this prints the log, then one line with the
# exit status, the bytes libcurl or the probe left on stdout and stderr (and
# those bytes, escaped, when there are any), and the entries in the working
# directory and in FLUSH_DIR (F-flush-control's scratch directory).
#
# It unsets the proxy variables. Every line it prints begins [LANE]; it
# writes nothing outside its mktemp directory but stdout.
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
d=.plans/research/m7/cookies
[ -f $d/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7cookies.XXXXXX") || exit 1
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
inc=${CURL_INCLUDE:-}
if [ -z "$inc" ] && [ -n "${CURL_LIB:-}" ] && [ -f "$(dirname "$CURL_LIB")/../include/curl/curl.h" ]; then
  inc=$(dirname "$CURL_LIB")/../include
fi
extra=
[ "$(uname -s)" = Linux ] && extra=-ldl
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" $extra 2>"$tmp/cc.err"
else
  "${CC:-cc}" ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" -lcurl $extra 2>"$tmp/cc.err"
fi
cc_status=$?
[ "$cc_status" -eq 0 ] || { echo "[$lane] the compile exited $cc_status"; sed "s/^/[$lane] cc: /" "$tmp/cc.err"; exit 1; }
if [ -n "${CURL_LIB:-}" ]; then
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB" 2>/dev/null || echo "$CURL_LIB"), headers ${inc:-the compiler's}"
else
  echo "[$lane] libcurl by -lcurl, headers ${inc:-the compiler's}"
fi
echo "[$lane] node $("${NODE:-node}" --version) uname $(uname -srm)"
[ -f /etc/os-release ] && echo "[$lane] os $(. /etc/os-release; echo "${PRETTY_NAME:-?}")"
[ "$(uname -s)" = Darwin ] && echo "[$lane] os $(sw_vers -productName) $(sw_vers -productVersion)"
"$tmp/probe" --version 2>&1 | sed "s/^/[$lane] /"
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no port"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] server $(cat "$tmp/ports")"
port=$(sed 's/^port=\([0-9]*\).*/\1/' "$tmp/ports")
cases=${CASES:-$("$tmp/probe" --list)}
count=0
for c in $cases; do
  rm -rf "$tmp/cwd" "$tmp/flush"
  mkdir "$tmp/cwd" "$tmp/flush"
  : > "$tmp/log"
  start=$(date +%s)
  ( cd "$tmp/cwd" && printf 'SENTINEL-STDIN-0123456789\n' | FLUSH_DIR="$tmp/flush" PROBE_LOG="$tmp/log" "$tmp/probe" "$c" "$port" > "$tmp/out" 2> "$tmp/err" )
  status=$?
  sed "s/^/[$lane] /" "$tmp/log"
  ob=$(wc -c < "$tmp/out" | tr -d ' ')
  eb=$(wc -c < "$tmp/err" | tr -d ' ')
  cw=$(ls -A "$tmp/cwd" | tr '\n' ' ')
  fl=$(ls -A "$tmp/flush" | tr '\n' ' ')
  echo "[$lane] probe $c exit=$status stdout-bytes=$ob stderr-bytes=$eb cwd-entries=[${cw% }] flush-dir-entries=[${fl% }] took-about=$(( $(date +%s) - start ))s"
  [ "$ob" -gt 0 ] && od -c "$tmp/out" | sed "s/^/[$lane] probe $c stdout: /"
  [ "$eb" -gt 0 ] && od -c "$tmp/err" | sed "s/^/[$lane] probe $c stderr: /"
  count=$((count+1))
done
echo "[$lane] -- $count cases run"
exit 0
