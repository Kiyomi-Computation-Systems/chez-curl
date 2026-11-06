#!/bin/sh
# run-in.sh VARIANT LOG CMD...: copies this directory's probes into
# build/carried-guard/VARIANT/probe/, then runs CMD there, from that copy's
# root, inside the Guix container (scripts/guix-env), on CPUs 10 to 17
# alone, after make deps; stdout and stderr into LOG, a path under
# results/. Nothing else is written.
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
variant=$1; log=$2; shift 2
copy=/home/kishu/src/chez-curl/build/carried-guard/$variant
[ -d "$copy/src" ] || { echo "run-in: no copy $copy" >&2; exit 2; }
mkdir -p "$copy/probe"
cp "$here"/*.sps "$here"/*.mjs "$here"/suites.sh "$copy/probe/"
mkdir -p "$(dirname -- "$here/../results/$log")"
rc=0
(cd "$copy" && taskset -c 10-17 scripts/guix-env sh -c 'make --no-print-directory deps >/dev/null && "$@"' sh "$@" </dev/null) \
  >"$here/../results/$log" 2>&1 || rc=$?
echo "run-in: $variant $* -> results/$log (exit $rc)"
