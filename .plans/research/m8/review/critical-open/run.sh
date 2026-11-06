#!/bin/sh
# The M8 plan's review (2026-11-06): probe.sps's three cases, each in a
# process of its own, RUNS times (default 3), in the Guix container. Run from
# the repository's root:
#   scripts/guix-env sh .plans/research/m8/review/critical-open/run.sh < /dev/null
# For inside and outside, a FIFO in the run's mktemp directory, whose writer,
# a background sh, opens it 2 s after the program starts. CHEZ is the
# container's scheme.
set -u
d=.plans/research/m8/review/critical-open
[ -f $d/probe.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
CHEZ=${CHEZ:-scheme}
RUNS=${RUNS:-3}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8co.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
echo "chez $("$CHEZ" --version 2>&1) threaded=$(echo '(display (threaded?))' | "$CHEZ" -q)"
printf 'x\n' > "$tmp/regular"
k=1
while [ "$k" -le "$RUNS" ]; do
  for c in inside outside regular; do
    if [ "$c" = regular ]; then
      p=$tmp/regular
    else
      p=$tmp/fifo-$c-$k
      mkfifo "$p"
      ( sleep 3; exec 3>"$p"; printf 'x\n' >&3; exec 3>&- ) &
      writer=$!
    fi
    "$CHEZ" --program $d/probe.sps "$c" "$p" < /dev/null 2>&1 | sed "s/^/run $k /"
    [ "$c" = regular ] || wait "$writer"
  done
  k=$((k+1))
done
