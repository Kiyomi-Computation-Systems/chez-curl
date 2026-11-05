#!/bin/sh
# build/m7s4b/run-suites.sh TAG SUITE...: in the container, from the
# repository's root, each SUITE under timeout, its log under
# build/m7s4b/logs/TAG/, and one verdict line each.
set -u
tag=$1; shift
out=build/m7s4b/logs/$tag
mkdir -p "$out"
for suite in "$@"; do
  name=$(basename "$suite" .sps)
  timeout --foreground 900 "$CHEZ" --libdirs src:tests:build/scheme-libs --program "$suite" > "$out/$name.log" 2>&1
  rc=$?
  echo "$name exit $rc"
done
