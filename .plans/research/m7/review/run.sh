#!/bin/sh
# Review probe, one lane: CURL_LIB a libcurl.so.4, CURL_INCLUDE its headers.
# Run from the repository's root. Writes its log under .plans/research/m7/review/results/.
set -u
d=.plans/research/m7/review
lane=$1
out=$d/results/results-$lane.log
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7review.XXXXXX") || exit 1
"${CC:-cc}" -I"$CURL_INCLUDE" -o "$tmp/probe" $d/probe.c "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err" || { cat "$tmp/cc.err"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" $d/server.mjs < "$tmp/in" > "$tmp/server.log" 2>&1 &
pid=$!
exec 3>"$tmp/in"
i=0
while ! grep -q '^port ' "$tmp/server.log" 2>/dev/null; do
  i=$((i+1)); [ $i -gt 100 ] && { echo "no port"; exit 1; }
  sleep 0.1
done
port=$(sed -n 's/^port //p' "$tmp/server.log")
"$tmp/probe" "http://127.0.0.1:$port" > "$tmp/probe.log" 2>&1
echo "probe exit=$?" >> "$tmp/probe.log"
sleep 0.5
exec 3>&-
wait $pid
{ echo "== $lane"; cat "$tmp/probe.log"; echo "-- server"; cat "$tmp/server.log"; } > "$out"
rm -rf "$tmp"
cat "$out"
