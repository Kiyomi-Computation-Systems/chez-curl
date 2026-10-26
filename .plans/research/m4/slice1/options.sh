#!/bin/sh
# M4 slice 1's options table, for one libcurl. Run from the repository's root:
#
#   CURL_LIB=PATH [CURL_INCLUDE=DIR] sh .plans/research/m4/slice1/options.sh LANE
#
# It compiles options.c as run.sh compiles probe.c, and prints each option the
# library names, prefixed with LANE.
set -u
[ "$#" -eq 1 ] || { echo "usage: options.sh LANE" >&2; exit 2; }
[ -n "${CURL_LIB:-}" ] || { echo "options.sh: set CURL_LIB to a libcurl.so.4" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/slice1-options.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
"${CC:-cc}" $inc -o "$tmp/options" .plans/research/m4/slice1/options.c "$CURL_LIB" \
  -Wl,-rpath,"$(dirname "$CURL_LIB")" 2> "$tmp/cc.err" || { cat "$tmp/cc.err"; exit 1; }
"$tmp/options" | sed "s/^/[$1] /"
