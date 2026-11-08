#!/bin/sh
# quick-start and errors given the base URL with a trailing slash.
set -u
out=build/m8s4-review/reader-slash; mkdir -p "$out"
fifo="$out/origin-stdin"; rm -f "$fifo"; mkfifo "$fifo"
node tests/origin.mjs < "$fifo" > "$out/origin.json" 2> "$out/origin.err" &
opid=$!; exec 7> "$fifo"
i=0; while [ ! -s "$out/origin.json" ] && [ $i -lt 100 ]; do i=$((i+1)); sleep 0.1; done
base="http://$(sed -n 's/.*"http":"\([^"]*\)".*/\1/p' "$out/origin.json")/"
for n in quick-start group; do echo "--- $n $base"; scheme --libdirs src --program examples/$n.sps "$base" < /dev/null; echo "exit $?"; done
exec 7>&-; wait $opid
