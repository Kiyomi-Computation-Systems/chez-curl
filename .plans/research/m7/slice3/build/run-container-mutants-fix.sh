#!/bin/sh
# Each NAME's mutant made and its suites run in the Guix container, one
# after another. From the repository's root, on the host.
set -u
for name in "$@"; do
  line=$(python3 build/m7s3b/mutants-fix.py make "$name")
  echo "$line"
  suites=$(echo "$line" | sed 's/.*suites: //')
  # shellcheck disable=SC2086
  sh build/m7s3b/run-mutant.sh "$name" $suites
done
echo "mutants done"
