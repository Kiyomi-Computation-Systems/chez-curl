#!/bin/sh
# M5 slice 3's scoped review's probes (2026-10-28), kept and rerun on one
# libcurl, in the container, from the repository's root:
#   scripts/guix-env sh .plans/research/m5/retry-review/run.sh LABEL < /dev/null
#   - tick-storm.sps MODE N: N calls, each a get to port 1, while a timer
#     handler raises continuably, MODE fresh (a fresh object each time),
#     constant (one symbol) or prearm (the timer armed before each raise);
#   - false-storm.sps false N URL: the same, raising #f, against
#     ok-server.mjs, which answers 200;
#   - ranout-post-live.sps PORT: a post with a policy and a 3000 ms bound to
#     late-listener.mjs, which starts listening 500 ms in and never answers.
# Each storm line tallies how the calls ended, and how many raises reached
# the caller's handler or were lost.
set -u
d=.plans/research/m5/retry-review
label=$1
lib=src:tests:build/scheme-libs
for mode in fresh constant prearm; do
  echo "[$label] tick-storm $mode: $(timeout 600 $CHEZ --libdirs $lib --program $d/tick-storm.sps $mode 100 2>&1 | tail -1)"
done
port=$(( 20000 + $$ % 20000 ))
node $d/ok-server.mjs $port > /tmp/ok-server.$$ 2>&1 &
pid=$!
n=0; until grep -q listening /tmp/ok-server.$$ 2>/dev/null; do n=$((n+1)); [ $n -le 50 ] || break; sleep 0.1; done
echo "[$label] false-storm: $(timeout 600 $CHEZ --libdirs $lib --program $d/false-storm.sps false 100 "http://127.0.0.1:$port/" 2>&1 | tail -1)"
kill $pid; rm -f /tmp/ok-server.$$
port2=$(( port + 1 ))
node $d/late-listener.mjs $port2 500 > /tmp/late.$$ 2>&1 &
pid=$!
echo "[$label] ranout-post-live: $(timeout 60 $CHEZ --libdirs $lib --program $d/ranout-post-live.sps $port2 2>&1 | tail -1)"
sleep 1; kill $pid
sed "s/^/[$label] listener: /" /tmp/late.$$; rm -f /tmp/late.$$
