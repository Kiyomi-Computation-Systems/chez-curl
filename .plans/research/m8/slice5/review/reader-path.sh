#!/bin/sh
# A reader's path through docs/README.md's and docs/headers-and-json.md's
# own steps, in a copy of the tree with no build/: make deps, then the test
# server as docs/README.md starts it, then the page's run line, three times
# against one server, each run's stdout compared with
# examples/expected/json-api.out. Run inside the container, from the copy's
# root:
#   scripts/guix-env sh review-scripts/reader-path.sh < /dev/null
set -u
out=review-out/reader
mkdir -p "$out"
echo "== make deps (no build/ yet: $( [ -e build ] && echo present || echo absent ))"
make --no-print-directory deps; echo "deps exit $?"
ls -l build/scheme-libs | sed -n '1,20p'

fifo=$(mktemp -u "${TMPDIR:-/tmp}/origin-in.XXXXXX")
mkfifo "$fifo"
node tests/origin.mjs <"$fifo" >"$out/origin.out" 2>"$out/origin.err" &
pid=$!
exec 3>"$fifo"
i=0
while [ ! -s "$out/origin.out" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
head -n 1 "$out/origin.out"
http=$(head -n 1 "$out/origin.out" | sed -n 's/.*"http":"\([^"]*\)".*/\1/p')
echo "http face: $http"
for n in 1 2 3; do
  scheme --libdirs src:build/scheme-libs --program examples/json-api.sps "http://$http" \
    >"$out/run-$n.out" 2>"$out/run-$n.err" 3>&-
  rc=$?
  if cmp -s "$out/run-$n.out" examples/expected/json-api.out; then same=same; else same=DIFFERS; fi
  echo "run $n: exit $rc, stdout $same as examples/expected/json-api.out, stderr $(wc -c <"$out/run-$n.err") bytes"
done
# The run line as the example's head comment gives it, from another
# directory: the page says run from the root.
(cd examples && scheme --libdirs src:build/scheme-libs --program json-api.sps "http://$http" >"../$out/from-examples.out" 2>"../$out/from-examples.err" 3>&-)
echo "from examples/: exit $? ; stderr: $(head -c 300 "$out/from-examples.err")"
# A reader's own program, jsonparse's src and byte-machine's src on the
# path directly, no make deps links.
cat >"$out/own.sps" <<'EOF'
(import (rnrs) (http-client) (jsonparse easy))
(write (json-ref (bytevector->json (string->utf8 "{\"a\":[1,2]}")) "a" 1))
(newline)
EOF
scheme --libdirs src:vendor/jsonparse/src:vendor/jsonparse/vendor/byte-machine/src --program "$out/own.sps" >"$out/own.out" 2>"$out/own.err" 3>&-
echo "own program, vendor paths direct: exit $?, stdout $(cat "$out/own.out"), stderr $(head -c 300 "$out/own.err")"
exec 3>&-
wait "$pid"; echo "origin exit $?"
rm -f "$fifo"
