#!/bin/sh
# The engine test's measurements, for .plans/research/m5/http-client/engine/.
# Run on the host, from the repository root: sh build/m5s1-builder/kept/run-engine.sh
set -u
K=build/m5s1-builder/kept
log() {
  name=$1; shift
  { printf '$ scripts/guix-env'
    for a in "$@"; do case $a in *' '*) printf " '%s'" "$a" ;; *) printf ' %s' "$a" ;; esac; done
    printf '\n'
    scripts/guix-env "$@" < /dev/null 2>&1
    echo "exit $?"; } > "$K/$name"
}
log engine/ticks.log sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program build/m5s1-builder/kept/engine/ticks.sps'
log engine/slices-loaded.log sh -c 'pids=; i=0; while [ $i -lt 24 ]; do ( while :; do :; done ) & pids="$pids $!"; i=$((i + 1)); done; $CHEZ --libdirs src:tests:build/scheme-libs --program build/m5s1-builder/kept/engine/slices.sps; for p in $pids; do kill $p; done'
log engine/slices-idle.log sh -c '$CHEZ --libdirs src:tests:build/scheme-libs --program build/m5s1-builder/kept/engine/slices.sps'
