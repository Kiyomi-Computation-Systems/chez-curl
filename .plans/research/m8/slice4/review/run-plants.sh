#!/bin/sh
# Inside scripts/guix-env, from the tree's root: runs each plant's suites in
# its own copy, from the copy's root, as make test runs a suite.
set -u
root=$PWD
libs="src:tests:$root/build/scheme-libs"
for d in build/m8s4-review/plants/*/; do
  name=$(basename "$d")
  case "$name" in
    d*) suites="tests/test-docs.sps" ;;
    r*) suites="tests/test-reference.sps" ;;
    e*) suites="tests/test-examples.sps" ;;
    control) suites="tests/test-docs.sps tests/test-reference.sps tests/test-examples.sps" ;;
  esac
  for s in $suites; do
    log="$root/build/m8s4-review/logs/plant-$name-$(basename "$s" .sps).log"
    (cd "$d" && timeout --foreground 600 "$CHEZ" --libdirs "$libs" --program "$s" > "$log" 2>&1)
    rc=$?
    printf '%-32s %-26s exit %s\n' "$name" "$(basename "$s")" "$rc"
  done
done
