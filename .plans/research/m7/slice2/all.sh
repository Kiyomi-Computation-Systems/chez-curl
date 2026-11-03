#!/bin/sh
# M7 slice 2's measurements, every lane, two runs each, one after another so
# no two runs share the machine (2026-11-02). Run on the host, from the
# repository's root, with src/ at main:
#   sh .plans/research/m7/slice2/all.sh [RUN...]
# It makes the prototype (make-prototype.sh), then, for each RUN, 1 and 2 by
# default, writes results/guix-8.20.0-RUN.log from the Guix container and
# results/docker-RUN.log from the four Docker lanes (7.85.0, both 8.5.0s,
# 8.23.0, in that order). RUN valgrind instead writes
# results/valgrind-ubuntu-openssl-8.5.0.log: items 1, 2 and 6 under the
# memory gate's Valgrind on Ubuntu's 8.5.0 with OpenSSL. RUN maxredirs-N
# runs maxredirs.sps's one part on every lane, into
# results/maxredirs-guix-8.20.0-N.log and results/maxredirs-docker-N.log;
# when every RUN is one of these, an existing prototype is kept, not remade.
set -u
d=.plans/research/m7/slice2
r=$d/results
[ -f $d/run.sh ] || { echo "all.sh: run it from the repository's root" >&2; exit 2; }
only_mr=yes
for n in "$@"; do case $n in maxredirs-*) ;; *) only_mr= ;; esac; done
[ "$#" -gt 0 ] || only_mr=
if [ -n "$only_mr" ] && [ -d build/m7s2/src ]; then echo "all.sh: keeping build/m7s2/src"; else sh $d/make-prototype.sh || exit 1; fi
mkdir -p $r
[ "$#" -gt 0 ] || set -- 1 2
for n in "$@"; do
  case $n in
    maxredirs-*)
      k=${n#maxredirs-}
      scripts/guix-env sh -c "PROGRAM=maxredirs.sps CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0 maxredirs" < /dev/null > $r/maxredirs-guix-8.20.0-$k.log 2>&1
      echo "all.sh: $n guix-8.20.0 done $(date -u +%H:%M:%S)"
      PROGRAM=maxredirs.sps sh $d/docker.sh all maxredirs < /dev/null > $r/maxredirs-docker-$k.log 2>&1
      echo "all.sh: $n docker done $(date -u +%H:%M:%S)"
      continue ;;
  esac
  if [ "$n" = valgrind ]; then
    VALGRIND=1 sh $d/docker.sh ubuntu-openssl-8.5.0 schemes streams pooled < /dev/null > $r/valgrind-ubuntu-openssl-8.5.0.log 2>&1
    echo "all.sh: valgrind done $(date -u +%H:%M:%S)"
    continue
  fi
  scripts/guix-env sh -c "CURL_LIB=\$CHEZ_CURL_LIBCURL sh $d/run.sh guix-8.20.0" < /dev/null > $r/guix-8.20.0-$n.log 2>&1
  echo "all.sh: run $n guix-8.20.0 done $(date -u +%H:%M:%S)"
  sh $d/docker.sh all < /dev/null > $r/docker-$n.log 2>&1
  echo "all.sh: run $n docker done $(date -u +%H:%M:%S)"
done
