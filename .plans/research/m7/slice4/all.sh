#!/bin/sh
# M7 slice 4's measurements, every lane, two runs each, one after another so
# no two runs share the machine (2026-11-03). Run on the host, from the
# repository's root, with src/ at main:
#   sh .plans/research/m7/slice4/all.sh [RUN...]
# It makes the prototype (make-prototype.sh, which checks its diff against
# prototype.diff) and builds the file watch, build/m7s4/fswatch.so, in the
# Guix container; then, for each RUN, 1 and 2 by default, writes
# results/guix-8.20.0-RUN.log from the Guix container and
# results/docker-RUN.log from the four Docker lanes (7.85.0, both 8.5.0s,
# 8.23.0, in that order). RUN valgrind instead writes
# results/valgrind-ubuntu-openssl-8.5.0.log: item 1 whole (lifetime,
# abandon-leave, abandon-free) under the memory gate's Valgrind on Ubuntu's
# 8.5.0 with OpenSSL. RUN controls writes results/controls-guix-8.20.0.log
# (controls.sh), and RUN netcheck results/netcheck-docker-default.log.
set -u
d=.plans/research/m7/slice4
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
sh $d/make-prototype.sh || exit 1
scripts/guix-env sh -c "\$CC -O1 -Wall -shared -fPIC -o build/m7s4/fswatch.so $d/fswatch.c -ldl" < /dev/null > build/m7s4/fswatch-cc.log 2>&1
[ -f build/m7s4/fswatch.so ] || { echo "all.sh: the file watch did not build: build/m7s4/fswatch-cc.log" >&2; exit 1; }
mkdir -p $r
[ "$#" -gt 0 ] || set -- 1 2
for n in "$@"; do
  case $n in
    valgrind)
      VALGRIND=1 BOUND=${BOUND:-5400} sh $d/docker.sh ubuntu-openssl-8.5.0 lifetime abandon-leave abandon-free < /dev/null > $r/valgrind-ubuntu-openssl-8.5.0.log 2>&1
      echo "all.sh: valgrind done $(date -u +%H:%M:%S)"
      continue ;;
    controls)
      scripts/guix-env sh -c "CURL_LIB=\$CHEZ_CURL_LIBCURL CHEZ=\$CHEZ sh $d/controls.sh" < /dev/null > $r/controls-guix-8.20.0.log 2>&1
      echo "all.sh: controls done $(date -u +%H:%M:%S)"
      continue ;;
    netcheck)
      sh $d/docker.sh netcheck < /dev/null > $r/netcheck-docker-default.log 2>&1
      echo "all.sh: netcheck done $(date -u +%H:%M:%S)"
      continue ;;
  esac
  scripts/guix-env sh -c "CURL_LIB=\$CHEZ_CURL_LIBCURL CHEZ=\$CHEZ sh $d/run.sh guix-8.20.0" < /dev/null > $r/guix-8.20.0-$n.log 2>&1
  echo "all.sh: run $n guix-8.20.0 done $(date -u +%H:%M:%S)"
  sh $d/docker.sh all < /dev/null > $r/docker-$n.log 2>&1
  echo "all.sh: run $n docker done $(date -u +%H:%M:%S)"
done
