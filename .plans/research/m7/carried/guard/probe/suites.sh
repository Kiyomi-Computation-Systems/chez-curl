#!/bin/sh
# suites.sh TAG SUITE...: inside the container, from a copy's root: each
# tests/SUITE.sps under timeout, its whole log under build/suite-logs/TAG/,
# then one line per suite: exit status, SRFI-64's expected passes and
# unexpected failures, and each failing test's name.
set -u
tag=$1; shift
out=build/suite-logs/$tag
mkdir -p "$out"
for suite in "$@"; do
  log=$out/$suite.log
  timeout --foreground 900 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "tests/$suite.sps" >"$log" 2>&1
  rc=$?
  pass=$(sed -n 's/^# of expected passes *//p' "$log" | tail -1)
  fail=$(sed -n 's/^# of unexpected failures *//p' "$log" | tail -1)
  echo "suite $suite exit $rc pass ${pass:-0} fail ${fail:-0}"
  grep '^FAIL' "$log" | cut -c1-300 | sed 's/^/  /'
done
