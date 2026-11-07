#!/bin/sh
# The 417 trap's runs (M8 slice 2's build), in the Guix container, from the
# trap copy's root: trap417.sps, run RUN, VARIANT, COUNT requests, under the
# memory gate's Valgrind when MODE is gate, natively when native. The
# origin's /raw/head417 log goes to logs/RUN.origin.log, the program's lines
# to logs/RUN.out, Valgrind's log to logs/RUN.valgrind.
#   sh trap-417/run.sh RUN VARIANT COUNT MODE
set -u
run=$1; variant=$2; count=$3; mode=$4
mkdir -p logs
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy
export HEAD417_LOG=$PWD/logs/$run.origin.log
: > "$HEAD417_LOG"
if [ "$mode" = gate ]; then
  supp=
  [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
  # shellcheck disable=SC2086
  timeout 900 valgrind -v --command-line-only=yes --log-file=logs/$run.valgrind --error-exitcode=9 \
    --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $supp \
    "$CHEZ" --libdirs src:tests:build/scheme-libs --program trap-417/trap417.sps "$run" "$variant" "$count" \
    > logs/$run.out 2>&1 < /dev/null
else
  timeout 900 "$CHEZ" --libdirs src:tests:build/scheme-libs --program trap-417/trap417.sps "$run" "$variant" "$count" \
    > logs/$run.out 2>&1 < /dev/null
fi
echo "exit $?" >> logs/$run.out
grep '^trap417' logs/$run.out
