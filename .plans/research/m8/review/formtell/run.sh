#!/bin/sh
# The M8 plan's review (2026-11-06): probe.c on one libcurl. Run from the
# repository's root. CURL_LIB is a libcurl.so.4 to link; CURL_INCLUDE its
# headers, by default CURL_LIB's ../include when it holds curl/curl.h. Every
# line it prints begins [LANE]. Scratch goes to a mktemp directory, removed.
#   lane X: scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m8/review/formtell/run.sh guix-8.20.0' < /dev/null
#   the Docker lanes: sh .plans/research/m8/review/formtell/docker.sh
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
d=.plans/research/m8/review/formtell
[ -f $d/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
[ -n "${CURL_LIB:-}" ] || { echo "run.sh: set CURL_LIB" >&2; exit 2; }
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8ft.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
inc=${CURL_INCLUDE:-}
if [ -z "$inc" ] && [ -f "$(dirname "$CURL_LIB")/../include/curl/curl.h" ]; then
  inc=$(dirname "$CURL_LIB")/../include
fi
# shellcheck disable=SC2086
"${CC:-cc}" ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
st=$?
[ "$st" -eq 0 ] || { echo "[$lane] the compile exited $st"; sed "s/^/[$lane] cc: /" "$tmp/cc.err"; exit 1; }
echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB"), headers ${inc:-the compiler's}"
"$tmp/probe" < /dev/null 2>&1 | sed "s/^/[$lane] /"
echo "[$lane] probe exit=$?"
