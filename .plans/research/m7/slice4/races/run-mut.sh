#!/bin/sh
# build/m7s4r/run-mut.sh NAME...: in the Guix container, from the repository's
# root, each mutant copy's suites (its suites.txt) by make test; each
# result to build/m7s4r/mut/NAME/test.log, and a line to stdout.
for name in "$@"; do
  d=build/m7s4r/mut/$name
  start=$(date +%s)
  (cd "$d" && make --no-print-directory test SUITES="$(cat suites.txt)" > test.log 2>&1)
  rc=$?
  fails=$(grep -c '^FAIL' "$d/test.log")
  echo "$name rc=$rc fails=$fails seconds=$(( $(date +%s) - start ))"
done
