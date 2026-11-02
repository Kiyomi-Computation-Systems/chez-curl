#!/bin/sh
# Run in the Guix container from the repository's root.
d=.plans/research/m7/slice2/verify
head -c 65536 /dev/zero > ${TMPDIR:-/tmp}/c417-body
curl --version | head -1
for mode in keep close; do
  node $d/c417-server.mjs $mode > ${TMPDIR:-/tmp}/c417-server-$mode.out &
  pid=$!
  until grep -q '^port' ${TMPDIR:-/tmp}/c417-server-$mode.out 2>/dev/null; do sleep 0.1; done
  port=$(sed -n 's/^port //p' ${TMPDIR:-/tmp}/c417-server-$mode.out)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'Expect: 100-continue' --data-binary @${TMPDIR:-/tmp}/c417-body http://127.0.0.1:$port/)
  echo "mode=$mode curl-exit=$? status=$code requests=$(grep -c '^requests' ${TMPDIR:-/tmp}/c417-server-$mode.out)"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
done
