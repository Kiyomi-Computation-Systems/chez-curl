#!/bin/sh
# M4 slice 2's measurements, for one lane (the M4 plan, section 5.1). Run from
# the repository's root, once make deps has run:
#
#   sh .plans/research/m4/slice2/run.sh LANE [SET...]
#
# CHEZ is the scheme binary, NODE node, unless set; CHEZ_CURL_LIBCURL as
# discovery reads it (ADR-0002). SET is any of these, all by default:
#
#   escape     escape.sps: timer, take and then deliver, K from 1 to 300;
#              then held and unheld, take and then deliver, each with one
#              SIGINT 500 ms after ready
#   delay      delay.sps, take and then await, 40 transfers each
#   sigint     sigint.sps, take and then busy, 20 SIGINTs 300 ms apart while
#              a 9 s transfer is live; on Linux, take again during a 9 s
#              stalled lookup, its resolver thread live, through
#              tests/stall-getaddrinfo.c, built with CC (default cc)
#   vg-delay   delay under Valgrind, take and then await, 20 transfers each
#   vg-sigint  sigint's take, under Valgrind, its signals 1 s apart
#
# Valgrind (VALGRIND, default valgrind) runs with the memory gate's options,
# and in a Guix environment its one suppression (ADR-0014); each run prints
# its ERROR SUMMARY line.
#
# On the Mac, with Homebrew's Chez and coreutils:
#   make deps && CHEZ=chez NODE="$(asdf which node)" sh .plans/research/m4/slice2/run.sh mac sigint
set -u
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [SET...]" >&2; exit 2; }
[ -f .plans/research/m4/slice2/sigint.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
shift
[ "$#" -ge 1 ] || set -- escape delay sigint vg-delay vg-sigint
here=.plans/research/m4/slice2
libdirs=src:tests:build/scheme-libs
chez=${CHEZ:-scheme}
t=$(command -v timeout || command -v gtimeout) || { echo "run.sh: no timeout" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/slice2-research.XXXXXX") || exit 1
origin_pid=
cleanup() {
  exec 3>&-
  [ -z "$origin_pid" ] || wait "$origin_pid"
  rm -rf "$tmp"
}
trap cleanup EXIT
mkfifo "$tmp/origin.in"
"${NODE:-node}" tests/origin.mjs < "$tmp/origin.in" > "$tmp/origin.json" &
origin_pid=$!
exec 3> "$tmp/origin.in"
tries=0
until [ -s "$tmp/origin.json" ]; do
  tries=$((tries + 1))
  [ "$tries" -le 100 ] || { echo "[$lane] the origin never announced itself"; exit 1; }
  sleep 0.1
done
face() { sed "s/.*\"$1\":\"127\\.0\\.0\\.1:\\([0-9]*\\)\".*/\\1/" "$tmp/origin.json"; }
http=$(face http) raw=$(face raw)
echo "[$lane] $(uname -s) $(uname -m), chez $("$chez" --version 2>&1), node $("${NODE:-node}" --version)"

vg=
if [ -n "${GUIX_ENVIRONMENT:-}" ]; then supp=--suppressions=tests/guix-glibc-locpath.supp; else supp=; fi
valgrind_on() {
  vg="${VALGRIND:-valgrind} -v --command-line-only=yes --log-file=$tmp/vg.%p --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $supp"
}
valgrind_report() {
  for f in "$tmp"/vg.*; do
    [ -f "$f" ] || continue
    printf '[%s]   valgrind: %s\n' "$lane" "$(sed -n 's/^==[0-9]*== ERROR SUMMARY: //p' "$f" | tail -n 1)"
    rm -f "$f"
  done
}

# one SECONDS LABEL PROGRAM ARG...
one() {
  secs=$1 label=$2 prog=$3
  shift 3
  # shellcheck disable=SC2086
  out=$("$t" -s KILL "$secs" $vg "$chez" --libdirs "$libdirs" --program "$here/$prog" "$@" 2>&1 < /dev/null)
  status=$?
  printf '%s\n' "$out" | sed "s|^|[$lane] $label: |"
  [ "$status" -eq 0 ] || echo "[$lane] $label: exit $status, its limit $secs s"
}

# signalled LABEL SIGNALS SPACING PROGRAM ARG... [-- ENV=VALUE...]
# Runs PROGRAM, waits up to 60 s for its (ready PID) line, then sends SIGINT
# to PID SIGNALS times, SPACING seconds apart, the first SPACING after ready.
signalled() {
  label=$1 n=$2 spacing=$3 prog=$4
  shift 4
  pargs=
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do pargs="$pargs $1"; shift; done
  [ "$#" -eq 0 ] || shift
  out=$tmp/signalled.out
  : > "$out"
  # PARGS is split on spaces, and never globbed: a URL holds a ?.
  set -f
  # shellcheck disable=SC2086
  env "$@" "$t" -s KILL 300 $vg "$chez" --libdirs "$libdirs" --program "$here/$prog" $pargs \
    > "$out" 2>&1 < /dev/null &
  waiter=$!
  set +f
  tries=0
  until grep -q '^(ready ' "$out" || [ "$tries" -ge 1200 ]; do sleep 0.05; tries=$((tries + 1)); done
  pid=$(sed -n 's/^(ready \([0-9]*\))$/\1/p' "$out")
  if [ -z "$pid" ]; then
    kill "$waiter"
    wait "$waiter"
    sed "s|^|[$lane] $label: |" "$out"
    echo "[$lane] $label: never ready"
    return
  fi
  i=0
  while [ "$i" -lt "$n" ]; do
    sleep "$spacing"
    kill -INT "$pid"
    i=$((i + 1))
  done
  wait "$waiter"
  status=$?
  grep -v '^(ready ' "$out" | sed "s|^|[$lane] $label ($n sent): |"
  [ "$status" -eq 0 ] || echo "[$lane] $label: exit $status"
}

for set in "$@"; do
  case $set in
    escape)
      for w in take deliver; do
        one 600 "escape timer $w" escape.sps timer "$w" "http://127.0.0.1:$http/status/200" 1 300
        signalled "escape held $w" 1 0.5 escape.sps held "$w" "http://127.0.0.1:$http/status/200"
        signalled "escape unheld $w" 1 0.5 escape.sps unheld "$w" "http://127.0.0.1:$raw/raw/pause-mid-body?ms=2000"
      done ;;
    delay)
      one 300 "delay take" delay.sps take "$raw" 40
      one 300 "delay await" delay.sps await "$raw" 40 ;;
    sigint)
      signalled "sigint take" 20 0.3 sigint.sps take "http://127.0.0.1:$raw/raw/pause-mid-body?ms=9000"
      signalled "sigint busy" 20 0.3 sigint.sps busy "http://127.0.0.1:$raw/raw/pause-mid-body?ms=9000"
      if [ "$(uname -s)" = Linux ]; then
        "${CC:-cc}" -shared -fPIC -o "$tmp/stall.so" tests/stall-getaddrinfo.c -ldl 2> "$tmp/cc.err" \
          || { cat "$tmp/cc.err"; echo "[$lane] the stand-in did not compile"; }
        signalled "sigint take, lookup stalled" 20 0.3 sigint.sps take "http://stall.chez-curl.invalid:$http/status/200" \
          -- LD_PRELOAD="$tmp/stall.so" STALL_SUFFIX=.invalid STALL_MS=9000 STALL_LOG="$tmp/stall.log"
        printf '[%s]   stall log: %s\n' "$lane" "$(tr '\n' ';' < "$tmp/stall.log" | sed 's/loaded [0-9]*;//g')"
      fi ;;
    vg-delay)
      valgrind_on
      one 900 "valgrind delay take" delay.sps take "$raw" 20
      valgrind_report
      one 900 "valgrind delay await" delay.sps await "$raw" 20
      valgrind_report
      vg= ;;
    vg-sigint)
      valgrind_on
      signalled "valgrind sigint take" 20 1 sigint.sps take "http://127.0.0.1:$raw/raw/pause-mid-body?ms=30000"
      valgrind_report
      vg= ;;
    *) echo "run.sh: no set $set" >&2; exit 2 ;;
  esac
done
echo "[$lane] done"
