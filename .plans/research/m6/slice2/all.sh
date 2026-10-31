#!/bin/sh
# M6 slice 2's measurements, every one, one after another, so no two timed
# runs share the machine (2026-10-30). Run on the host, from the repository's
# root, with src/ at main:
#   sh .plans/research/m6/slice2/all.sh [STEP...]
# Each step writes its logs under results/; with no STEP, every step runs, in
# this order. CURRENT is curl 8.23.0's install directory, by default
# build/verify/c823/lane1/curl-current. Each program runs twice on each lane
# (escape three times); cpu and throughput also under the memory gate's
# Valgrind on Ubuntu's 8.5.0 with OpenSSL and on Guix's 8.20.0.
set -u
d=.plans/research/m6/slice2
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
current=${CURRENT:-build/verify/c823/lane1/curl-current}
mkdir -p $r
guix() { scripts/guix-env sh -c "$1" < /dev/null; }
docker_lanes() { sh $d/docker.sh "$current" "$@"; }
native() {
  # native PROGRAM RUNS: Guix's 8.20.0, then the four Docker lanes.
  guix "CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0 $1 $2" > $r/$1-guix-8.20.0.log 2>&1
  docker_lanes all "$1" "$2" > $r/$1-docker.log 2>&1
}
valgrind_lanes() {
  # valgrind_lanes PROGRAM RUNS: Ubuntu's 8.5.0 with OpenSSL, then Guix's 8.20.0.
  docker_lanes ubuntu-openssl-8.5.0-valgrind "$1" "$2" > $r/$1-docker-valgrind.log 2>&1
  guix "VALGRIND=valgrind CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0-valgrind $1 $2" > $r/$1-guix-8.20.0-valgrind.log 2>&1
}
step() {
  case $1 in
    build) sh $d/build.sh ;;
    check) native check 2 ;;
    answer) native answer 2 ;;
    rewind) native rewind 2 ;;
    hazards) native hazards 2 ;;
    cpu) native cpu 2; valgrind_lanes cpu 2 ;;
    offers) native offers 2 ;;
    escape) native escape 3 ;;
    throughput) native throughput 2; valgrind_lanes throughput 2 ;;
    unpaced)
      # main's own src/, not the prototype: the defect it shows is main's.
      guix "LIBDIRS=src CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0 unpaced 2" > $r/unpaced-guix-8.20.0.log 2>&1
      LIBDIRS=src docker_lanes all unpaced 2 > $r/unpaced-docker.log 2>&1 ;;
    *) echo "all.sh: no step $1" >&2; return 2 ;;
  esac
  echo "all.sh: $1 done $(date -u +%H:%M:%S)"
}
[ "$#" -gt 0 ] || set -- build check answer rewind hazards cpu offers escape throughput unpaced
for s in "$@"; do step "$s"; done
