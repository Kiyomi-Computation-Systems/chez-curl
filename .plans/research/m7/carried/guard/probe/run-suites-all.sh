#!/bin/sh
# run-suites-all.sh VARIANT...: the high level's suites, M5's and M7's, on
# each copy, through run-in.sh; each summary in results/suites-VARIANT.log,
# each suite's whole log copied to results/suites/VARIANT/.
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
suites="test-http-client test-group test-stream-call test-retry test-redirect test-auth test-proxy test-cookies test-printed test-version"
for v in "$@"; do
  sh "$here/run-in.sh" "$v" "suites-$v.log" sh probe/suites.sh "$v" $suites
  mkdir -p "$here/../results/suites/$v"
  cp /home/kishu/src/chez-curl/build/carried-guard/"$v"/build/suite-logs/"$v"/*.log "$here/../results/suites/$v/"
done
