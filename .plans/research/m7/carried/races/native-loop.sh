#!/bin/sh
# build/carried-races/native-loop.sh TREE N LABEL: make test, N times, on TREE (a
# snapshot under build/carried-races), the suites SUITES names
# (tests/test-origin-tls.sps by default), inside the Guix container. Each run's
# make output goes to build/carried-races/out/LABEL/N.make.out, and with RACE=1
# the instrumented origin's and probe's log to N.race.log. Prints each run's
# test lines and FAIL lines. From the repository's root, on the host:
#   taskset -c 0-9 scripts/guix-env sh build/carried-races/native-loop.sh TREE N LABEL < /dev/null
set -eu
tree=$1 n=$2 label=$3
suites=${SUITES:-tests/test-origin-tls.sps}
out=build/carried-races/out/$label
mkdir -p "$out"
echo "native-loop: tree $tree, $n runs, suites $suites, out $out, node $(node --version), libcurl $CHEZ_CURL_LIBCURL"
make -C "$tree" --no-print-directory deps >/dev/null
i=1
while [ "$i" -le "$n" ]; do
  log=$PWD/$out/$i.race.log
  rm -f "$log"
  start=$(date +%s)
  if [ "${RACE:-1}" = 1 ]; then
    env RACE_LOG="$log" MAILBOX_PROBE_LOG="$PWD/$out/$i.window.log" make -C "$tree" --no-print-directory test SUITES="$suites" >"$out/$i.make.out" 2>&1 || true
  else
    make -C "$tree" --no-print-directory test SUITES="$suites" >"$out/$i.make.out" 2>&1 || true
  fi
  echo "=== run $i, $(( $(date +%s) - start )) s"
  grep -E '^test: (pass|FAIL|HUNG|ran)' "$out/$i.make.out" || tail -5 "$out/$i.make.out"
  grep -E '^FAIL|^  (expected|actual):' "$out/$i.make.out" | cut -c1-400 || true
  i=$((i + 1))
done
echo "native-loop: done"
