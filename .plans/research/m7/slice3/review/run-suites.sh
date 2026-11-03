#!/bin/sh
# M7 slice 3's review: runs suites on copies of the tree in the Guix
# container, each log under the copy's logs/. From the repository's root,
# on the host:
#
#   sh .plans/research/m7/slice3/review/run-suites.sh COPY SUITE...
#
# COPY is a directory under build/m7s3-review/ (tree, or a mutant's copy,
# mut-NAME). Prints each suite's exit status and its FAIL lines.
set -eu
copy=$1; shift
dir=build/m7s3-review/$copy
root=$PWD
mkdir -p "$dir/logs"
for suite in "$@"; do
  log=$dir/logs/$(basename "$suite" .sps).log
  scripts/guix-env sh -c "(cd $dir && timeout 900 \$CHEZ --libdirs src:tests:$root/build/scheme-libs --program $suite) > $log 2>&1; echo \"exit \$?\" >> $log" < /dev/null
  echo "$copy $suite: $(tail -1 "$log")"
  grep -E '^FAIL ' "$log" | cut -c1-400 | sed 's/^/    /' || true
done
