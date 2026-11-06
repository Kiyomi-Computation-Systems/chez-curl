#!/bin/sh
# run-suites-mutants.sh VARIANT...: the call-state users' suites, M5's and
# M6's (test-http-client, test-group, test-stream-call), on each mutant copy.
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
for v in "$@"; do
  sh "$here/run-in.sh" "$v" "suites-$v.log" sh probe/suites.sh "$v" test-http-client test-group test-stream-call
  mkdir -p "$here/../results/suites/$v"
  cp /home/kishu/src/chez-curl/build/carried-guard/"$v"/build/suite-logs/"$v"/*.log "$here/../results/suites/$v/"
done
