#!/bin/sh
# build/m7s3b/run-mutant.sh NAME SUITE...: in the Guix container, each SUITE
# on the mutant copy build/m7s3b/mut/NAME, its log under that copy's
# build/m7s3b-logs/. Prints each suite's verdict and its FAIL lines. From
# the repository's root, on the host.
set -eu
name=$1; shift
dir=build/m7s3b/mut/$name
root=$PWD
mkdir -p "$dir/logs"
for suite in "$@"; do
  log=$dir/logs/$(basename "$suite" .sps).log
  scripts/guix-env sh -c "(cd $dir && timeout 900 \$CHEZ --libdirs src:tests:$root/build/scheme-libs --program $suite) > $log 2>&1; echo \"exit \$?\" >> $log" < /dev/null
  verdict=$(tail -1 "$log")
  echo "mutant $name $suite: $verdict"
  grep -E '^FAIL ' "$log" | cut -c1-300 | sed 's/^/    /' || true
done
