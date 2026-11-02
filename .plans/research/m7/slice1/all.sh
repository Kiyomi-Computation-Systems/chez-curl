#!/bin/sh
# M7 slice 1's measurements, every lane, two runs each, one after another so
# no two runs share the machine (2026-11-02). Run on the host, from the
# repository's root, with src/ at main:
#   sh .plans/research/m7/slice1/all.sh [RUN...]
# It makes the prototype (make-prototype.sh), then, for each RUN, 1 and 2 by
# default, writes results/guix-8.20.0.log from the Guix container and
# results/docker.log from the four Docker lanes (7.85.0, both 8.5.0s,
# 8.23.0, in that order); run 2's are guix-8.20.0-2.log and docker-2.log.
set -u
d=.plans/research/m7/slice1
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
sh $d/make-prototype.sh || exit 1
mkdir -p $r
[ "$#" -gt 0 ] || set -- 1 2
for n in "$@"; do
  suffix=
  [ "$n" = 1 ] || suffix=-$n
  scripts/guix-env sh -c "CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0" < /dev/null > $r/guix-8.20.0$suffix.log 2>&1
  echo "all.sh: run $n guix-8.20.0 done $(date -u +%H:%M:%S)"
  sh $d/docker.sh all < /dev/null > $r/docker$suffix.log 2>&1
  echo "all.sh: run $n docker done $(date -u +%H:%M:%S)"
done
