#!/bin/sh
# In the Guix container, from build/m7s4-review/base: each "NAME SUITE" line
# of stdin run in mut/NAME, its log mut/NAME/logs/SUITE.log ending "exit N",
# two at a time; one line per job. Copied from the build's mut-run.sh.
set -u
xargs -P 2 -L 1 sh -c '
  name=$1; suite=$2
  dir=mut/$name
  mkdir -p "$dir/logs"
  log=$dir/logs/$(basename "$suite" .sps).log
  (cd "$dir" && timeout 900 "$CHEZ" --libdirs "src:tests:../../build/scheme-libs" --program "$suite") > "$log" 2>&1 < /dev/null
  echo "exit $?" >> "$log"
  echo "$name $suite: $(tail -n 1 "$log")"
' sh
