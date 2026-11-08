#!/bin/sh
# Runs each example as docs/README.md and docs/quickstart.md tell a reader to:
# `node tests/origin.mjs` in one place, then
# `scheme --libdirs src --program examples/NAME.sps http://127.0.0.1:PORT`,
# from the repository's root. Each example is run ROUNDS times against ONE
# origin (a reader runs them by hand, more than once), and each run's stdout
# compared with examples/expected/NAME.out. Run inside scripts/guix-env.
set -u
ROUNDS=${ROUNDS:-3}
out=build/m8s4-review/reader
mkdir -p "$out"
fifo="$out/origin-stdin"
rm -f "$fifo"
mkfifo "$fifo"
node tests/origin.mjs < "$fifo" > "$out/origin.json" 2> "$out/origin.err" &
opid=$!
exec 7> "$fifo"
i=0
while [ ! -s "$out/origin.json" ] && [ $i -lt 100 ]; do i=$((i+1)); sleep 0.1; done
http=$(sed -n 's/.*"http":"\([^"]*\)".*/\1/p' "$out/origin.json")
echo "origin http face: $http"
base="http://$http"
for round in $(seq 1 "$ROUNDS"); do
  for f in examples/*.sps; do
    name=$(basename "$f" .sps)
    scheme --libdirs src --program "$f" "$base" > "$out/$name.$round.out" 2> "$out/$name.$round.err" < /dev/null
    rc=$?
    if cmp -s "$out/$name.$round.out" "examples/expected/$name.out"; then same=same; else same=DIFFERS; fi
    printf 'round %s %-20s exit %s stdout %s stderr-bytes %s\n' "$round" "$name" "$rc" "$same" "$(wc -c < "$out/$name.$round.err")"
    if [ "$same" = DIFFERS ]; then diff "examples/expected/$name.out" "$out/$name.$round.out" | sed 's/^/    /'; fi
  done
done
exec 7>&-
wait $opid
echo "origin exit $?"
