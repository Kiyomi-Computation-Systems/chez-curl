#!/bin/sh
# The timing probe, 3 runs, natively and under the memory gate's Valgrind
# options, each log kept here. From the repository's root, in the container:
#   scripts/guix-env sh .plans/research/m5/group/timing/run.sh < /dev/null
d=.plans/research/m5/group/timing
"$CHEZ" --libdirs src:tests:build/scheme-libs --program $d/probe.sps 3 > $d/native.log 2>&1 < /dev/null
echo "native: exit $?"
valgrind --command-line-only=yes --log-file=$d/valgrind.vglog --error-exitcode=9 --leak-check=full \
  --show-leak-kinds=definite --errors-for-leak-kinds=definite \
  ${GUIX_ENVIRONMENT:+--suppressions=tests/guix-glibc-locpath.supp} \
  "$CHEZ" --libdirs src:tests:build/scheme-libs --program $d/probe.sps 3 > $d/valgrind.log 2>&1 < /dev/null
echo "valgrind: exit $?"
