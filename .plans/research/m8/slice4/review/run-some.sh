#!/bin/sh
# Inside scripts/guix-env, from the tree's root: run-plants.sh for the plants named.
set -u
root=$PWD
libs="src:tests:$root/build/scheme-libs"
for name in "$@"; do
  d=build/m8s4-review/plants/$name
  case "$name" in
    d*) suites="tests/test-docs.sps" ;;
    r*) suites="tests/test-reference.sps" ;;
    e*) suites="tests/test-examples.sps" ;;
  esac
  for s in $suites; do
    log="$root/build/m8s4-review/logs/plant-$name-$(basename "$s" .sps).log"
    (cd "$d" && timeout --foreground 600 "$CHEZ" --libdirs "$libs" --program "$s" > "$log" 2>&1)
    rc=$?; printf "%-32s %-26s exit %s\n" "$name" "$(basename "$s")" "$rc"
  done
done
