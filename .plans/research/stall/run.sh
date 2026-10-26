#!/bin/sh
# M3 slice 3's measurements (ADR-0019 and ADR-0001, both amended
# 2026-10-25), for one lane: one Chez and one libcurl. Run from the
# repository's root:
#
#   sh .plans/research/stall/run.sh LANE SET...
#
# SET is one of:
#   control       under the stand-in, with a 3,000 ms stall: control.sps,
#                 which preload variable reached Chez; then gai-control.c,
#                 an ordinary program's getaddrinfo call on the stalled
#                 name, which must take the stall; then the stand-in's log,
#                 whose "loaded PID" lines say where it loaded
#   lookup        lookup.sps under the stand-in getaddrinfo,
#                 tests/stall-getaddrinfo.c, which stalls every lookup of
#                 slow-name.example.com: each of E1's nine cases twice with
#                 a 10,000 ms stall and twice with 3,000 ms, then once with
#                 no stand-in, the control. Each line ends with how many
#                 times the stand-in loaded and how many lookups it
#                 stalled. On Linux the stand-in loads with LD_PRELOAD; on
#                 macOS with DYLD_INSERT_LIBRARIES, through its __interpose
#                 section: the Mac's probe
#   timeout-late  timeout-late.sps under the stand-in, 3,000 ms: 40 timeouts
#                 of 500 ms on fresh engines and 40 on one engine, three
#                 times each; how late each 28 came
#   threads       threads.sps, Linux only: 20 engines with both settings, and
#                 20 without CURLMOPT_QUICK_EXIT, each lookup answered at once;
#                 how many threads the process holds
#   multi-setopt  multi-setopt.sps: what each long multi option answers
#                 for each value
#   maxconn       maxconn.sps twice: two 1 s drips at
#                 MAX_TOTAL_CONNECTIONS 1, 2, 0, -1 and 2^40; needs NODE
#   maxconn-valgrind
#                 the same, twice, under Valgrind (VALGRIND, default
#                 valgrind), its report in a file of its own
#
# On the Mac, the probe ADR-0019's 2026-10-25 amendment asks for:
#
#   CHEZ="$(command -v chez)" NODE="$(asdf which node)" \
#     sh .plans/research/stall/run.sh mac lookup multi-setopt maxconn
#
#   CHEZ="$(command -v chez)" NODE="$(asdf which node)" \
#     sh .plans/research/stall/run.sh mac control
#
# first. Then the lines tell its failures apart: "loaded 0" is a stand-in
# that never reached Chez; loaded, with gai-control's call stalled but
# "stalled 0" on lookup's lines, is an interposition that does not reach
# Apple's libcurl, or a libcurl that does not resolve through getaddrinfo;
# loaded, with neither stalled, is an interposition that did not apply at
# all. It refuses to run with a proxy variable set: libcurl would look up
# the proxy, not the name.
#
# The results/draft-*.log files came first, from scratch copies of these
# programs and a draft stand-in that matched one name exactly, as
# STALL_NAME; the others from these programs as committed.
#
# The environment gives CHEZ, the scheme binary; CHEZ_CURL_LIBCURL, when
# the libcurl is not the one discovery finds (ADR-0002); CC, the C
# compiler (default cc); NODE, for maxconn (default node). Each program
# runs under GNU timeout (gtimeout on macOS), and one that fails prints its
# exit status: 124 for one that ran out of time.
set -u
[ "$#" -ge 2 ] || { echo "usage: run.sh LANE SET..." >&2; exit 2; }
[ -f .plans/research/stall/lookup.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
shift
here=.plans/research/stall
for v in http_proxy https_proxy HTTPS_PROXY all_proxy ALL_PROXY; do
  eval "set_=\${$v+x}"
  [ -z "$set_" ] || { echo "run.sh: $v is set: libcurl would look up the proxy, not the stalled name; unset it" >&2; exit 2; }
done
libdirs=src:tests:build/scheme-libs
t=$(command -v timeout || command -v gtimeout) || { echo "run.sh: no timeout, nor gtimeout" >&2; exit 2; }
echo "[$lane] chez $("$CHEZ" --version 2>&1), $(uname -s) $(uname -m)"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/stall-research.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
case $(uname -s) in
  Darwin)
    so=$tmp/stall-getaddrinfo.dylib
    "${CC:-cc}" -dynamiclib -o "$so" tests/stall-getaddrinfo.c || { echo "[$lane] the stand-in did not compile"; exit 1; }
    preload=DYLD_INSERT_LIBRARIES ;;
  *)
    so=$tmp/stall-getaddrinfo.so
    "${CC:-cc}" -shared -fPIC -o "$so" tests/stall-getaddrinfo.c -ldl || { echo "[$lane] the stand-in did not compile"; exit 1; }
    preload=LD_PRELOAD ;;
esac

# lookup-case LABEL MS PRELOAD? CASE...
lookup_case() {
  label=$1 ms=$2 with=$3
  shift 3
  log=$tmp/log
  rm -f "$log"
  if [ "$with" = yes ]; then
    line=$("$t" 60 env "$preload=$so" STALL_SUFFIX=slow-name.example.com STALL_MS="$ms" STALL_LOG="$log" \
           "$CHEZ" --libdirs "$libdirs" --program "$here/lookup.sps" "$@" 2>&1)
  else
    line=$("$t" 60 "$CHEZ" --libdirs "$libdirs" --program "$here/lookup.sps" "$@" 2>&1)
  fi
  status=$?
  stalls=0 loads=0
  if [ -f "$log" ]; then
    stalls=$(grep -c '^stalling' "$log")
    loads=$(grep -c '^loaded' "$log")
  fi
  echo "[$lane, $label] $line; exit $status; stand-in loaded $loads, stalled $stalls"
}

cases="teardown|teardown quick|teardown mquick|teardown quick mquick|timeout|timeout quick|timeout quick mquick|easy|easy quick"
for set in "$@"; do
  case $set in
    control)
      log=$tmp/log
      rm -f "$log"
      "$t" 60 env "$preload=$so" STALL_SUFFIX=slow-name.example.com STALL_MS=3000 STALL_LOG="$log" \
        "$CHEZ" --libdirs "$libdirs" --program "$here/control.sps" 2>&1 | sed "s|^|[$lane] |"
      "${CC:-cc}" -o "$tmp/gai-control" "$here/gai-control.c" || { echo "[$lane] gai-control did not compile"; exit 1; }
      "$t" 60 env "$preload=$so" STALL_SUFFIX=slow-name.example.com STALL_MS=3000 STALL_LOG="$log" \
        "$tmp/gai-control" slow-name.example.com 2>&1 | sed "s|^|[$lane] |"
      echo "[$lane] the stand-in's log:"
      if [ -f "$log" ]; then sed "s|^|[$lane]   |" "$log"; else echo "[$lane]   (none)"; fi ;;
    lookup)
      for ms in 10000 3000; do
        for run in 1 2; do
          IFS='|'
          for c in $cases; do
            IFS=' '
            # shellcheck disable=SC2086
            lookup_case "stall $ms, run $run" "$ms" yes $c
            IFS='|'
          done
          IFS=' '
        done
      done
      IFS='|'
      for c in $cases; do
        IFS=' '
        # shellcheck disable=SC2086
        lookup_case "no stand-in" 0 no $c
        IFS='|'
      done
      IFS=' ' ;;
    timeout-late)
      for run in 1 2 3; do
        for mode in fresh shared; do
          "$t" 300 env "$preload=$so" STALL_SUFFIX=.stall.invalid STALL_MS=3000 STALL_LOG="$tmp/late.log" \
            "$CHEZ" --libdirs "$libdirs" --program "$here/timeout-late.sps" "$mode" 40 2>&1 | sed "s|^|[$lane, run $run] |"
        done
      done ;;
    threads)
      for w in none multi; do
        "$t" 120 env "$preload=$so" STALL_SUFFIX=.stall.invalid STALL_MS=0 STALL_LOG="$tmp/threads.log" \
          "$CHEZ" --libdirs "$libdirs" --program "$here/threads.sps" "$w" 20 2>&1 | sed "s|^|[$lane, $w] |"
      done ;;
    multi-setopt)
      "$t" 60 "$CHEZ" --libdirs "$libdirs" --program "$here/multi-setopt.sps" 2>&1 | sed "s|^|[$lane] |" ;;
    maxconn)
      for run in 1 2; do
        "$t" 120 "$CHEZ" --libdirs "$libdirs" --program "$here/maxconn.sps" 10 100 1 2 0 -1 1099511627776 2>&1 \
          | sed "s|^|[$lane, run $run] |"
      done ;;
    maxconn-valgrind)
      for run in 1 2; do
        "$t" 600 "${VALGRIND:-valgrind}" --quiet --command-line-only=yes --log-file="$tmp/valgrind.log" \
          "$CHEZ" --libdirs "$libdirs" --program "$here/maxconn.sps" 10 100 1 2 0 -1 1099511627776 2>&1 \
          | sed "s|^|[$lane, valgrind, run $run] |"
        echo "[$lane, valgrind, run $run] Valgrind wrote $(wc -c < "$tmp/valgrind.log") bytes of report"
      done ;;
    *)
      echo "run.sh: no set $set" >&2
      exit 2 ;;
  esac
done
