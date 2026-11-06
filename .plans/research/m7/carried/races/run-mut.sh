#!/bin/sh
# build/carried-races/run-mut.sh NAME...: inside the Guix container, make deps and
# make test, the suites the mutant's suites.txt names (SUITES overrides), in each
# build/carried-races/mut/NAME, natively; its log to
# build/carried-races/out/mutants/NAME.log. Prints each mutant's test lines and FAIL
# titles. From the repository's root, on the host:
#   taskset -c 0-9 scripts/guix-env sh build/carried-races/run-mut.sh NAME... < /dev/null
set -u
mkdir -p "${MUT_OUT:-build/carried-races/out/mutants}"
for name in "$@"; do
  d=build/carried-races/mut/$name
  log=${MUT_OUT:-build/carried-races/out/mutants}/$name.log
  suites=${SUITES:-$(cat "$d/suites.txt")}
  start=$(date +%s)
  make -C "$d" --no-print-directory deps test SUITES="$suites" > "$log" 2>&1
  echo "== $name ($(( $(date +%s) - start )) s): $(grep -E '^test: ran' "$log")"
  grep -E '^test: (FAIL|HUNG)' "$log" | sed 's/^/   /'
  grep -E '^FAIL' "$log" | cut -c1-200 | sed 's/^/   /'
  cp "$d/mutation.diff" "${MUT_OUT:-build/carried-races/out/mutants}/$name.diff"
done
