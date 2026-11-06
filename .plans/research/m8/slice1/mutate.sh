#!/bin/sh
# Watches make check-memory-gate's shard cases (n, o) fail: each mutation
# is made in a copy of the tree, and the copy's check runs in its own Guix
# container. Run on the host, from anywhere: sh mutate.sh [NAME ...].
# Writes results/<name>.log, each copy's whole output, and prints each
# mutation's exit status and FAILED lines. A mutation the check passes is
# printed "PASSED (a defect)".
set -u
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../../../.." && pwd)
mkdir -p "$root/build/m8slice1"
copies=$(mktemp -d "$root/build/m8slice1/mutants.XXXXXX") || exit 2
results=$here/results
mkdir -p "$copies" "$results"

all="neither both missing new-suite two-on-one deleted misspelt no-gate continue job-if block run-ignores no-refusal no-origin gate-if shard-flags no-list-origin no-run-origin"
[ $# -gt 0 ] || set -- $all

# mutate NAME DIR: makes the mutation NAME in the copy DIR.
mutate() {
  mk=$2/Makefile ci=$2/.github/workflows/ci.yml
  case $1 in
    neither)     sed -i '/^  tests\/test-native\.sps \\$/d' "$mk" ;;
    both)        sed -i 's/^MEMORY_SUITES_2 := \\$/&\n  tests\/test-auth.sps \\/' "$mk" ;;
    missing)     sed -i 's/^MEMORY_SUITES_1 := \\$/&\n  tests\/test-nope.sps \\/' "$mk" ;;
    new-suite)   cp "$2/tests/test-manifest.sps" "$2/tests/test-zzz-new.sps" ;;
    two-on-one)  sed -i 's/^        run: make test-memory MEMORY_SHARD=2$/        run: make test-memory MEMORY_SHARD=1/' "$ci" ;;
    deleted)     awk '/^  memory-2:$/ { stop = 1 } !stop { print }' "$ci" >"$ci.new" && mv "$ci.new" "$ci" ;;
    misspelt)    sed -i 's/MEMORY_SHARD=2$/MEMORY_SHRAD=2/' "$ci" ;;
    no-gate)     awk '/^        run: make check-memory-gate$/ && ++n == 2 { print "        run: true"; next } { print }' "$ci" >"$ci.new" && mv "$ci.new" "$ci" ;;
    continue)    sed -i 's/^        run: make test-memory MEMORY_SHARD=1$/        continue-on-error: true\n&/' "$ci" ;;
    job-if)      sed -i 's/^    name: memory-2 .*/&\n    if: false/' "$ci" ;;
    block)       sed -i 's/^        run: make test-memory MEMORY_SHARD=2$/        run: |\n          make test-memory MEMORY_SHARD=2/' "$ci" ;;
    run-ignores) sed -i 's/^MEMORY_RUN = .*/MEMORY_RUN = $(MEMORY_SUITES)/' "$mk" ;;
    no-refusal)  sed -i "s/^	  ''|1|2) ;; \\\\\$/	  *) ;; \\\\/" "$mk" ;;
    no-origin)   sed -i "s/\[ '\$(origin MEMORY_SUITES)' != file \]/false/" "$mk" ;;
    gate-if)     awk '/^        run: make check-memory-gate$/ && ++n == 1 { print "        if: false" } { print }' "$ci" >"$ci.new" && mv "$ci.new" "$ci" ;;
    shard-flags) sed -i 's/--error-exitcode=9 --leak-check=full/--error-exitcode=9 $(if $(MEMORY_SHARD),,--leak-check=full)/' "$mk" ;;
    no-list-origin) sed -i '/^	$(if $(filter 1 2,$(MEMORY_SHARD)),$(if $(filter-out file,$(origin $(MEMORY_RUN_NAME)))/d' "$mk" ;;
    no-run-origin) sed -i '/^	$(foreach v,MEMORY_RUN MEMORY_RUN_NAME,/d' "$mk" ;;
    *) echo "mutate.sh: no mutation $1" >&2; return 2 ;;
  esac
}

for name in "$@"; do
  dir=$copies/$name
  mkdir -p "$dir"
  ( cd "$root" && tar cf - --exclude=./build --exclude=./.git --exclude=./.plans/research . ) | ( cd "$dir" && tar xf - )
  mutate "$name" "$dir" || continue
  if [ "$name" != new-suite ] && cmp -s "$root/Makefile" "$dir/Makefile" &&
      cmp -s "$root/.github/workflows/ci.yml" "$dir/.github/workflows/ci.yml"; then
    echo "$name: the mutation changed nothing"
    continue
  fi
  { echo "mutation: $name"; diff "$root/Makefile" "$dir/Makefile"; diff "$root/.github/workflows/ci.yml" "$dir/.github/workflows/ci.yml"; echo "---"; } >"$results/$name.log"
  ( "$dir/scripts/guix-env" make check-memory-gate </dev/null >>"$results/$name.log" 2>&1
    echo "exit $?" >>"$results/$name.log" ) &
done
wait
for name in "$@"; do
  log=$results/$name.log
  [ -f "$log" ] || continue
  status=$(tail -n 1 "$log")
  if [ "$status" = "exit 0" ]; then
    echo "$name: PASSED (a defect)"
  else
    echo "$name: $status"
    grep '^check-memory-gate: FAILED' "$log" | sed 's/^/  /'
  fi
done
