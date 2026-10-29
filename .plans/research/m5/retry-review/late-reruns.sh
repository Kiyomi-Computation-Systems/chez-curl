#!/bin/sh
# Reruns ranout-post-live.sps three times against late-listener.mjs, in the
# container, from the repository root, to time the bound's 28 (2026-10-28):
#   scripts/guix-env sh .plans/research/m5/retry-review/late-reruns.sh < /dev/null
d=.plans/research/m5/retry-review
for i in 1 2 3; do
port=$(( 21000 + $$ % 10000 + i ))
node $d/late-listener.mjs $port 500 > /dev/null 2>&1 &
pid=$!
$CHEZ --libdirs src:tests:build/scheme-libs --program $d/ranout-post-live.sps $port 2>&1 | tail -1
kill $pid
done
