#!/bin/sh
# M7 slice 3's measurements, every lane, two runs each, one after another so
# no two runs share the machine (2026-11-02). Run on the host, from the
# repository's root, with src/ at main:
#   sh .plans/research/m7/slice3/all.sh [RUN...]
# It makes the prototype (make-prototype.sh), then, for each RUN, 1 and 2 by
# default, writes results/guix-8.20.0-RUN.log from the Guix container and
# results/docker-RUN.log from the four Docker lanes (7.85.0, both 8.5.0s,
# 8.23.0, in that order). RUN valgrind instead writes
# results/valgrind-ubuntu-openssl-8.5.0.log: items 3, 4 and 5 (pooled,
# refused, tls, stall) under the memory gate's Valgrind on Ubuntu's 8.5.0
# with OpenSSL. RUN controls writes results/selftest-control.log and
# results/wire-control-guix-8.20.0.log.
set -u
d=.plans/research/m7/slice3
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
sh $d/make-prototype.sh || exit 1
mkdir -p $r
[ "$#" -gt 0 ] || set -- 1 2
for n in "$@"; do
  case $n in
    valgrind)
      VALGRIND=1 sh $d/docker.sh ubuntu-openssl-8.5.0 pooled refused tls stall < /dev/null > $r/valgrind-ubuntu-openssl-8.5.0.log 2>&1
      echo "all.sh: valgrind done $(date -u +%H:%M:%S)"
      continue ;;
    controls)
      scripts/guix-env sh $d/selftest-control.sh < /dev/null > $r/selftest-control.log 2>&1
      scripts/guix-env sh -c "CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/wire-control.sh" < /dev/null > $r/wire-control-guix-8.20.0.log 2>&1
      echo "all.sh: controls done $(date -u +%H:%M:%S)"
      continue ;;
  esac
  scripts/guix-env sh -c "CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0" < /dev/null > $r/guix-8.20.0-$n.log 2>&1
  echo "all.sh: run $n guix-8.20.0 done $(date -u +%H:%M:%S)"
  sh $d/docker.sh all < /dev/null > $r/docker-$n.log 2>&1
  echo "all.sh: run $n docker done $(date -u +%H:%M:%S)"
done
