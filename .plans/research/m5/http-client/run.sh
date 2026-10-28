#!/bin/sh
# M5 slice 1's kept measurements, for .plans/research/m5/http-client/. Run
# on the host, from the repository root:
#
#   sh build/m5s1-builder/kept/run.sh
#
# Each log's first line is the command that made it, run in the container.
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
log timing/native.log sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do $CHEZ --libdirs src:tests:build/scheme-libs --program build/m5s1-builder/kept/timing/timing.sps; done'
log timing/valgrind.log sh -c 'for i in 1 2 3; do valgrind -q --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite --suppressions=tests/guix-glibc-locpath.supp $CHEZ --libdirs src:tests:build/scheme-libs --program build/m5s1-builder/kept/timing/timing.sps; done'
log witness/v1-loaded.log sh build/m5s1-builder/kept/witness/child-loop.sh 24 40 build/m5s1-builder/kept/witness/escape-child-v1.sps
log witness/v2-loaded.log sh build/m5s1-builder/kept/witness/child-loop.sh 24 40 build/m5s1-builder/kept/witness/escape-child-v2.sps
log witness/v2-idle.log sh build/m5s1-builder/kept/witness/child-loop.sh 0 40 build/m5s1-builder/kept/witness/escape-child-v2.sps
