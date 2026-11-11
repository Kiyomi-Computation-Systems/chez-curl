#!/bin/sh
# Runs test-manifest against each plant under build/m8s6-review/plants/.
# Run from the repository root, inside scripts/guix-env. A shape plant runs the
# tree's suite; a reader plant runs its own changed copy. Each run's whole
# output is kept in its directory as run.log; one line per plant is printed:
# NAME EXIT PASSES FAILS, then each failing test's name.
set -u
base=build/m8s6-review/plants
up=../../../..
for dir in "$base"/*/; do
  name=$(basename "$dir")
  if [ -f "$dir/test-manifest.sps" ]; then
    program=test-manifest.sps
  else
    program=$up/tests/test-manifest.sps
  fi
  (cd "$dir" && $CHEZ --libdirs $up/src:$up/tests:$up/build/scheme-libs --program "$program") \
    > "$dir/run.log" 2>&1 < /dev/null
  status=$?
  passes=$(sed -n 's/^# of expected passes *//p' "$dir/run.log")
  fails=$(sed -n 's/^# of unexpected failures *//p' "$dir/run.log")
  echo "$name exit=$status passes=${passes:-0} fails=${fails:-0}"
  grep '^FAIL ' "$dir/run.log" | sed 's/^/    /'
done
echo "run-plants: done"
