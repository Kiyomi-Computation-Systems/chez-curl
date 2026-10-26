#!/bin/sh
# The M4 plan review's redirect probe (2026-10-26), kept for ADR-0023 and the
# plan. Run from the repository root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m4/redirect/run.sh guix-8.20.0'
# or in Docker by docker.sh. CURL_LIB is a libcurl.so.4; CURL_INCLUDE, if
# set, the headers to compile against; NODE, node; CC, cc.
set -u
lane=$1
d=.plans/research/m4/redirect
tmp=$(mktemp -d "${TMPDIR:-/tmp}/redir.XXXXXX") || exit 1
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
"${CC:-cc}" $inc -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
[ -x "$tmp/probe" ] || { cat "$tmp/cc.err"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" < "$tmp/in" > "$tmp/port" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/port" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "no port"; exit 1; }; sleep 0.1; done
port=$(cat "$tmp/port")
echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB")"
for code in 301 302 303 307 308; do
  for m in POST PUT PATCH DELETE; do "$tmp/probe" "$port" "$m" "$code" hello | sed "s/^/[$lane] /"; done
  "$tmp/probe" "$port" DELETE "$code" nobody | sed "s/^/[$lane] /"
done
echo "[$lane] -- empty bodies, no redirect: /r200 is the echo itself"
for m in POST PUT; do
  "$tmp/probe" "$port" "$m" 200 empty | sed "s/^/[$lane] /"
  "$tmp/probe" "$port" "$m" 200 empty null | sed "s/^/[$lane] /"
  "$tmp/probe" "$port" "$m" 200 nobody | sed "s/^/[$lane] /"
done
exec 3>&-
wait "$pid"
rm -rf "$tmp"
