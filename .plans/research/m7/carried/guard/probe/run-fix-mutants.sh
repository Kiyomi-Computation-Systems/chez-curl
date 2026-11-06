#!/bin/sh
# run-fix-mutants.sh NAME...: test-call-checks on each fix_mutants.py copy,
# fixmut-NAME, test-origin-tls for stop-late and test-transfer for
# flip-no-cr, through run-in.sh; each
# summary at ../fix/mutant-NAME.log, each suite's whole log copied beside it.
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
out=$here/../fix
for v in "$@"; do
  suites=test-call-checks
  [ "$v" = stop-late ] && suites=test-origin-tls
  [ "$v" = flip-no-cr ] && suites=test-transfer
  sh "$here/run-in.sh" "fixmut-$v" "../fix/mutant-$v.log" sh probe/suites.sh "fixmut-$v" $suites
  mkdir -p "$out/mutants/$v"
  cp /home/kishu/src/chez-curl/build/carried-guard/fixmut-"$v"/build/suite-logs/fixmut-"$v"/*.log "$out/mutants/$v/"
done
