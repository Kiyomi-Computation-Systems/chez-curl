#!/bin/sh
# build/m7s4r/mut-summary.sh NAME...: each mutant's rule, its make test status
# and the tests that failed, from build/m7s4r/mut/NAME/test.log.
for name in "$@"; do
  d=/home/kishu/src/chez-curl/build/m7s4r/mut/$name
  echo "== $name: $(python3 /home/kishu/src/chez-curl/build/m7s4r/mut.py list $name | cut -d'|' -f2 | sed 's/^ *//;s/ *$//')"
  grep -E '^test: (pass|FAIL|HUNG)' "$d/test.log" | sed 's/^/  /'
  grep -E '^FAIL' "$d/test.log" | cut -c6-150 | sed 's/^/  FAIL /'
done
