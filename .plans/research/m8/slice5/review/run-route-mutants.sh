#!/bin/sh
# Runs test-origin in each review-mutants/NAME/, and test-examples too in
# the mutants the example's own requests reach, JOBS at a time, inside the
# container, from the copy's root; then a control of both in the copy:
#   scripts/guix-env sh review-scripts/run-route-mutants.sh [JOBS] < /dev/null
set -u
jobs=${1:-3}
logs=review-out/route-mutants
mkdir -p "$logs"
root=$(pwd)
run() { # run DIR SUITE LOG
  ( cd "$1" && timeout -s KILL 900 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "tests/$2.sps" \
      >"$3" 2>&1 3>&- ; echo "exit $?" >>"$3" )
}
running=0
for dir in review-mutants/*/ control; do
  name=$(basename "$dir")
  if [ "$name" = control ]; then d=$root; else d=$root/$dir; fi
  (
    run "$d" test-origin "$root/$logs/$name.test-origin.log"
    case $name in
      control|r01-*|r02-*|r03-*|r05-*) run "$d" test-examples "$root/$logs/$name.test-examples.log" ;;
    esac
  ) &
  running=$((running + 1))
  if [ "$running" -ge "$jobs" ]; then wait; running=0; fi
done
wait
for log in "$logs"/*.log; do
  printf '== %s: %s\n' "$(basename "$log" .log)" "$(tail -n 1 "$log")"
  grep '^FAIL' "$log" | head -6 || true
done
