#!/bin/sh
# Runs tests/test-origin.sps in each build/mutants-fix/NAME/, inside the
# container, JOBS at a time, from the repository's root:
#
#   scripts/guix-env sh .plans/research/m8/slice5/build/fix/run-mutants.sh [JOBS] < /dev/null
#
# Each run's log is .plans/research/m8/slice5/build/fix/mutants/NAME.log, its
# last line "exit STATUS". Then it prints, for each mutant, its exit status
# and every FAIL line its log holds.
set -u
jobs=${1:-4}
logs=.plans/research/m8/slice5/build/fix/mutants
mkdir -p "$logs"
root=$(pwd)
running=0
for dir in build/mutants-fix/*/; do
  name=$(basename "$dir")
  (
    cd "$dir" || exit 1
    timeout -s KILL 600 "$CHEZ" --libdirs src:tests:build/scheme-libs --program tests/test-origin.sps \
      > "$root/$logs/$name.log" 2>&1 3>&-
    echo "exit $?" >> "$root/$logs/$name.log"
  ) &
  running=$((running + 1))
  if [ "$running" -ge "$jobs" ]; then
    wait
    running=0
  fi
done
wait
for log in "$logs"/*.log; do
  name=$(basename "$log" .log)
  printf '== %s: %s\n' "$name" "$(tail -n 1 "$log")"
  grep '^FAIL' "$log" || echo '   (no FAIL line)'
done
