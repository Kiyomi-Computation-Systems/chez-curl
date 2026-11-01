#!/bin/sh
# M6 slice 3's measurements, every one, one after another, so no two timed
# runs share the machine (2026-10-31). Run on the host, from the
# repository's root, with src/ at main:
#   sh .plans/research/m6/slice3/all.sh [STEP...]
# Each step writes its logs under results/: STEP-guix-8.20.0.log, from the
# Guix container, and STEP-docker.log, from the four Docker lanes (7.85.0,
# both 8.5.0s, 8.23.0, in that order); the valgrind step writes
# drive-valgrind-docker.log (Ubuntu's 8.5.0 with OpenSSL) and
# drive-valgrind-guix-8.20.0.log, and valgrind-strict the same names with
# -strict. With no STEP, every step runs, in this order. S is the slice the
# valgrind step runs at, 10 by default; SCHED its scheduling, strict by
# default (the logs kept ran S=10 SCHED=eager). The steps before drive-f
# ran drive-v1.sps, the drive's first build, then named drive.sps (README).
set -u
d=.plans/research/m6/slice3
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
mkdir -p $r
guix() { scripts/guix-env sh -c "$1" < /dev/null; }
native() {
  # native STEP PROGRAM ARG...: Guix's 8.20.0, then the four Docker lanes.
  step=$1
  shift
  guix "CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0 $*" > $r/$step-guix-8.20.0.log 2>&1
  sh $d/docker.sh all "$@" > $r/$step-docker.log 2>&1
}
valgrind_lanes() {
  # valgrind_lanes STEP PROGRAM ARG...: Ubuntu's 8.5.0 with OpenSSL, then Guix's 8.20.0.
  step=$1
  shift
  sh $d/docker.sh ubuntu-openssl-8.5.0-valgrind "$@" > $r/$step-docker.log 2>&1
  guix "VALGRIND=valgrind CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0-valgrind $*" > $r/$step-guix-8.20.0.log 2>&1
}
step() {
  case $1 in
    asked-origin) native asked-origin asked origin 3 ;;
    asked-faces) native asked-faces asked faces 2 ;;
    drive-e) native drive-e drive-v1 cases=a,b slices=1,10,50 sched=strict runs=2 ;;
    drive-eager) native drive-eager drive-v1 cases=a,b slices=10,50 sched=eager runs=2 ;;
    drive-c) native drive-c drive-v1 cases=b-control,c,c-control,d slices=10 sched=strict runs=2 bound=20000 ;;
    drive-idle) native drive-idle drive-v1 cases=b-control slices=1,10,50 runs=2 faces=raw framings=sized control-bound=3000 ;;
    drive-hops) native drive-hops drive-v1 cases=c c-statuses=301,302,303,307,308,413,503 c-wheres=h2 slices=10 runs=2 bound=8000 ;;
    drive-hopcancel)
      native drive-hopcancel drive-v1 cases=c c-statuses=303,307 c-wheres=raw-keep,h2 slices=10 runs=2 bound=8000 hop-cancel=1 ;;
    valgrind)
      valgrind_lanes drive-valgrind drive-v1 cases=a,b,b-control,c,c-control,d slices=${S:-10} sched=${SCHED:-strict} \
        runs=1 bound=180000 control-bound=15000 ;;
    valgrind-strict)
      valgrind_lanes drive-valgrind-strict drive-v1 cases=a,b slices=10 sched=strict runs=1 bound=180000 ;;
    # drive.sps, the second build: case f, final-feeds, and the eager
    # variant's flag cleared at an empty wait (README).
    drive-f)
      native drive-f drive cases=f final-feeds=0 slices=10 runs=2 faces=raw,https
      native drive-f-final drive cases=f final-feeds=1 slices=10 runs=2 faces=raw,https ;;
    valgrind-final)
      valgrind_lanes drive-valgrind-final drive cases=a,b,b-control,c,c-control,d,f final-feeds=1 slices=10 sched=eager \
        runs=1 bound=180000 control-bound=15000 ;;
    *) echo "all.sh: no step $1" >&2; return 2 ;;
  esac
  echo "all.sh: $1 done $(date -u +%H:%M:%S)"
}
[ "$#" -gt 0 ] || set -- asked-origin asked-faces drive-e drive-eager drive-c drive-idle drive-hops drive-hopcancel valgrind \
  valgrind-strict drive-f valgrind-final
for s in "$@"; do step "$s"; done
