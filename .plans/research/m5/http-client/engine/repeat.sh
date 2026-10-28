#!/bin/sh
# Runs tests/test-http-client.sps N times, LOAD busy loops beside it, and
# prints one line per run: its exit status and its FAIL lines.
n=$1; load=$2
pids=
i=0
while [ "$i" -lt "$load" ]; do ( while :; do :; done ) & pids="$pids $!"; i=$((i + 1)); done
i=0
while [ "$i" -lt "$n" ]; do
  out=$(timeout 600 $CHEZ --libdirs src:tests:build/scheme-libs --program tests/test-http-client.sps 2>&1 < /dev/null)
  status=$?
  printf 'run %s status %s %s\n' "$i" "$status" "$(printf '%s\n' "$out" | grep -E '^FAIL|expected passes|unexpected' | tr '\n' '|')"
  i=$((i + 1))
done
for p in $pids; do kill "$p"; done
