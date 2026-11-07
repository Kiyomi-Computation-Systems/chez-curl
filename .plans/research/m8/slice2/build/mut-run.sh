#!/bin/sh
# .plans/research/m8/slice2/build/mut-run.sh [JOBS]: in the Guix container,
# from the repository's root, each line "NAME SUITE" of JOBS
# (build/m8s2/mut/jobs by default) run in the mutant copy build/m8s2/mut/NAME,
# its log under that copy's logs/, its last line "exit N". Two at a time.
# Prints one line per job.
set -u
jobs=${1:-build/m8s2/mut/jobs}
root=$PWD
export root
xargs -P 2 -L 1 sh -c '
  name=$1; suite=$2
  dir=$root/build/m8s2/mut/$name
  mkdir -p "$dir/logs"
  log=$dir/logs/$(basename "$suite" .sps).log
  (cd "$dir" && timeout 1500 "$CHEZ" --libdirs "src:tests:$root/build/scheme-libs" --program "$suite") > "$log" 2>&1 < /dev/null
  echo "exit $?" >> "$log"
  echo "$name $suite: $(tail -n 1 "$log")"
' sh < "$jobs"
