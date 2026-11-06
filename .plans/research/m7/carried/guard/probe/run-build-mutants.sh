#!/bin/sh
# run-build-mutants.sh VARIANT...: the new suite and test-group on each of
# build_mutants.py's copies, build-VARIANT, through run-in.sh; and, for
# a-no-compound, test-http-client and test-stream-call too. Each summary at
# ../build/mutant-VARIANT.log, each suite's log copied beside it.
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
out=$here/../build
for v in "$@"; do
  suites="test-call-checks test-group"
  [ "$v" = a-no-compound ] && suites="$suites test-http-client test-stream-call"
  mkdir -p "/home/kishu/src/chez-curl/build/carried-guard/build-$v/probe"
  cp "$here/suites.sh" "/home/kishu/src/chez-curl/build/carried-guard/build-$v/probe/"
  sh "$here/run-in.sh" "build-$v" "../build/mutant-$v.log" sh probe/suites.sh "mutant-$v" $suites
  mkdir -p "$out/mutants/$v"
  cp /home/kishu/src/chez-curl/build/carried-guard/build-"$v"/build/suite-logs/mutant-"$v"/*.log "$out/mutants/$v/"
done
