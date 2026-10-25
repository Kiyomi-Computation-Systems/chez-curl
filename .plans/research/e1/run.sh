#!/bin/sh
# Spike E1's runner for one lane: one Chez and one libcurl. It runs from the
# repository's root, runs each set twice, and prints every program's line
# under the lane's name and the run's number.
#
#   run.sh LANE SET...
#
# SET is one of:
#   collect       collect.sps: no engine, a __collect_safe poll, and plain
#                 polls of 1 and 3 ms, then plain 1 ms polls spending 9, 99
#                 and 999 more ticks a loop
#   collect-long  collect.sps: plain polls of 10 and 300 ms; the second is
#                 killed at 60 s
#   collect-once  collect.sps once: single collections beside a plain and a
#                 __collect_safe poll of 1 ms
#   wake          wake.sps
#   deliver       deliver.sps, 3 runs of each pairing of callable and
#                 perform, the control (a plain callable inside a
#                 __collect_safe perform, which CSUG rules out) last
#   lookup        lookup.sps, teardown and timeout, with and without the
#                 two QUICK_EXIT options, then easy, with and without QUICK_EXIT
#   interrupt     interrupt.sps, each case with SIGINT to the main thread,
#                 then sectioned with SIGINT to the other thread, which
#                 waits in sleep, in condition-wait, then in curl_multi_poll
#   load-race     load-race.sps, import and then invoke, 10 times each
#   system        system.sps, plain and inside a critical section
#
# The environment gives CHEZ, the scheme binary; CHEZ_CURL_LIBCURL, the
# libcurl it loads (ADR-0002); and NODE, the node deliver's test origin
# runs on (default node). Each program runs under timeout, and one that
# fails prints its exit status: 124 for one that ran out of time.
set -u
[ "$#" -ge 2 ] || { echo "usage: run.sh LANE SET..." >&2; exit 2; }
lane=$1
shift
e1=.plans/research/e1
libdirs=src:tests:build/scheme-libs
echo "[$lane] chez $("$CHEZ" --version 2>&1)"

# one RUN SECONDS PROGRAM ARG...
one() {
  run=$1 secs=$2 prog=$3
  shift 3
  out=$(timeout "$secs" "$CHEZ" --libdirs "$libdirs" --program "$e1/$prog" "$@" 2>&1)
  status=$?
  [ -z "$out" ] || printf '%s\n' "$out" | sed "s|^|[$lane, run $run] |"
  [ "$status" -eq 0 ] || echo "[$lane, run $run] $prog $*: exit $status, its limit ${secs} s"
}

# interrupt RUN CASE TARGET OTHER
# Starts interrupt.sps, waits up to 10 s for its ready line, then 1 s more,
# sends SIGINT to the main thread or to the other one, and prints its line.
interrupt() {
  run=$1 case=$2 target=$3 other=$4
  out=$(mktemp "${TMPDIR:-/tmp}/e1-interrupt.XXXXXX")
  "$CHEZ" --libdirs "$libdirs" --program "$e1/interrupt.sps" "$case" "$target" "$other" >"$out" 2>&1 &
  pid=$!
  tries=0
  until grep -q '^ready' "$out" || [ "$tries" -ge 200 ]; do sleep 0.05; tries=$((tries + 1)); done
  sleep 1
  threads=$(ls "/proc/$pid/task" | wc -l)
  if [ "$target" = main ]; then
    tid=$pid
  else
    tid=$(ls "/proc/$pid/task" | grep -vx "$pid" | head -n 1)
  fi
  kill -INT "$tid"
  wait "$pid"
  status=$?
  grep -v '^ready' "$out" | sed "s|^|[$lane, run $run] ($threads threads) |"
  [ "$status" -eq 0 ] || echo "[$lane, run $run] interrupt.sps $case $target $other: exit $status"
  rm -f "$out"
}

for run in 1 2; do
  for set in "$@"; do
    case $set in
      collect)
        for c in "none 300 0" "safe 300 0" "safe 1 0" "plain 1 0" "plain 3 0" \
                 "plain 1 9" "plain 1 99" "plain 1 999"; do
          # shellcheck disable=SC2086
          one "$run" 120 collect.sps $c
        done ;;
      collect-long)
        one "$run" 180 collect.sps plain 10 0
        one "$run" 60 collect.sps plain 300 0 ;;
      collect-once)
        one "$run" 60 collect.sps plain 1 0 once
        one "$run" 60 collect.sps safe 1 0 once ;;
      wake)
        one "$run" 60 wake.sps ;;
      deliver)
        for c in "safe plain" "plain plain" "safe safe" "plain safe"; do
          # shellcheck disable=SC2086
          one "$run" 120 deliver.sps $c 3
        done ;;
      lookup)
        for c in "teardown" "teardown quick" "teardown mquick" "teardown quick mquick" \
                 "timeout" "timeout quick" "timeout quick mquick" "easy" "easy quick"; do
          # shellcheck disable=SC2086
          one "$run" 60 lookup.sps $c
        done ;;
      interrupt)
        for c in wait timed sectioned poll; do interrupt "$run" "$c" main sleep; done
        for o in sleep wait poll; do interrupt "$run" sectioned other "$o"; done ;;
      load-race)
        for m in import invoke; do
          i=0
          while [ "$i" -lt 10 ]; do one "$run" 60 load-race.sps "$m"; i=$((i + 1)); done
        done ;;
      system)
        one "$run" 60 system.sps plain
        one "$run" 60 system.sps section ;;
      *)
        echo "run.sh: no set $set" >&2
        exit 2 ;;
    esac
  done
done
