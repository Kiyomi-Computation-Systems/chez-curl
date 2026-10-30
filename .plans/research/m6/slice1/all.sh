#!/bin/sh
# M6 slice 1's measurements, every one, one after another, so no two timed
# runs share the machine (2026-10-30). Run on the host, from the repository's
# root, with src/ at main:
#   sh .plans/research/m6/slice1/all.sh [STEP...]
# Each step writes its log under results/; with no STEP, every step runs, in
# this order. CURRENT is curl 8.23.0's install directory, by default
# build/verify/c823/lane1/curl-current.
set -u
d=.plans/research/m6/slice1
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
current=${CURRENT:-build/verify/c823/lane1/curl-current}
mkdir -p $r
guix() { scripts/guix-env sh -c "$1" < /dev/null; }
docker_lanes() { sh $d/docker.sh "$current" "$@"; }
step() {
  case $1 in
    build) sh $d/build.sh ;;
    check)
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 check' > $r/check-guix-8.20.0.log 2>&1
      docker_lanes all,ubuntu-openssl-8.5.0-valgrind check > $r/check-docker.log 2>&1 ;;
    paced)
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 paced 3' > $r/paced-guix-8.20.0.log 2>&1
      docker_lanes all paced 3 > $r/paced-docker.log 2>&1
      docker_lanes ubuntu-openssl-8.5.0-valgrind paced 3 > $r/paced-docker-valgrind.log 2>&1
      guix 'VALGRIND=valgrind CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0-valgrind paced 3' > $r/paced-guix-8.20.0-valgrind.log 2>&1 ;;
    replay)
      # Guix's 8.20.0 loses a wakeup made inside curl_easy_pause (wake.c),
      # so its full replay stalls: the bounded run is the evidence.
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 replay 1 1048576 1,65536' > $r/replay-guix-8.20.0-bounded.log 2>&1
      docker_lanes all replay 2 > $r/replay-docker.log 2>&1 ;;
    head)
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 head direct; CHILD_PROXY=1 CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 head connect' > $r/head-guix-8.20.0.log 2>&1
      docker_lanes all head direct > $r/head-docker.log 2>&1
      CHILD_PROXY=1 docker_lanes all head connect > $r/head-connect-docker.log 2>&1 ;;
    escape)
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 escape 3' > $r/escape-guix-8.20.0.log 2>&1
      docker_lanes all escape 3 > $r/escape-docker.log 2>&1 ;;
    throughput)
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0 throughput 3' > $r/throughput-guix-8.20.0.log 2>&1
      docker_lanes all throughput 3 > $r/throughput-docker.log 2>&1
      docker_lanes ubuntu-openssl-8.5.0-valgrind throughput 2 > $r/throughput-docker-valgrind.log 2>&1
      guix 'VALGRIND=valgrind CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/run.sh guix-8.20.0-valgrind throughput 2' > $r/throughput-guix-8.20.0-valgrind.log 2>&1 ;;
    wake)
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/slice1/wake.sh guix-8.20.0' > $r/wake-guix-8.20.0.log 2>&1
      docker_lanes all wake > $r/wake-docker.log 2>&1
      docker_lanes vanilla-8.20.0 wake > $r/wake-docker-vanilla-8.20.0.log 2>&1
      mkdir -p $r/stall
      sh $d/wake-strace.sh > $r/stall/wake-guix-8.20.0-strace.txt 2>&1 ;;
    nomux)
      guix 'PAUSE_NO_MULTIPLEX=1 CASES="D-hold-mux W-h2-error" CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/pause/run.sh guix-8.20.0' > $r/nomux-guix-8.20.0.log 2>&1
      PAUSE_NO_MULTIPLEX=1 CASES="D-hold-mux W-h2-error" sh .plans/research/m6/pause/docker.sh "$current" > $r/nomux-docker.log 2>&1 ;;
    regress)
      # Item 7's switch unset: every case of the pause probe, as before; and
      # R-reset-mid, whose post cases split by timing, 3 times with main's
      # probe.c and server.mjs (by git show, read-only) beside 3 with ours.
      guix 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/pause/run.sh guix-8.20.0' > $r/pause-unset-guix-8.20.0.log 2>&1
      rm -rf build/m6s1/pause-orig
      mkdir -p build/m6s1/pause-orig
      git show main:.plans/research/m6/pause/probe.c > build/m6s1/pause-orig/probe.c
      git show main:.plans/research/m6/pause/server.mjs > build/m6s1/pause-orig/server.mjs
      sed 's|^d=.plans/research/m6/pause$|d=build/m6s1/pause-orig|' .plans/research/m6/pause/run.sh > build/m6s1/pause-orig/run.sh
      guix 'for i in 1 2 3; do CASES=R-reset-mid CURL_LIB=$CHEZ_CURL_LIBCURL sh build/m6s1/pause-orig/run.sh main-files; CASES=R-reset-mid CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m6/pause/run.sh switch-unset; done' > $r/pause-reset-mid-guix-8.20.0.log 2>&1 ;;
    *) echo "all.sh: no step $1" >&2; return 2 ;;
  esac
  echo "all.sh: $1 done $(date -u +%H:%M:%S)"
}
[ "$#" -gt 0 ] || set -- build check paced replay head escape throughput wake nomux regress
for s in "$@"; do step "$s"; done
