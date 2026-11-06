#!/bin/sh
# run-probes.sh VARIANT...: on each copy, through run-in.sh, the Q1 probes:
# the SIGINT matrix, the timer matrix, the engine sweep a tick at a time
# from 1 to 1400 at each entry, and the refusals; each into
# results/PROBE-VARIANT.log.
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
for v in "$@"; do
  sh "$here/run-in.sh" "$v" "sigint-$v.log" sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program probe/sigint-probe.sps'
  sh "$here/run-in.sh" "$v" "timer-$v.log" sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program probe/timer-probe.sps'
  sh "$here/run-in.sh" "$v" "engine-fine-$v.log" sh -c 'for e in request port go parallel; do $CHEZ --libdirs src:tests:build/scheme-libs --program probe/engine-sweep.sps $e 1 1400 1; done'
  sh "$here/run-in.sh" "$v" "refusal-$v.log" sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program probe/refusal-probe.sps'
done
