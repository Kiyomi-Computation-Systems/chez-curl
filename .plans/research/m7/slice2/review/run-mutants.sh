#!/bin/sh
# Inside the Guix container, from the repository's root:
#   scripts/guix-env sh build/m7s2-review/run-mutants.sh NAME... < /dev/null
set -u
mkdir -p build/m7s2-review/logs
for name in "$@"; do
  log=build/m7s2-review/logs/mutant-$name${TAG:+.$TAG}.log
  make -C build/m7s2-review/mut/$name test SUITES="${MUT_SUITES:-tests/test-auth.sps}" > $log 2>&1 < /dev/null
  echo "mutant $name exit $?: $(grep -E '^test: (pass|FAIL|HUNG)' $log | tr '\n' ' ')"
  grep '^FAIL' $log | cut -c1-200
done
