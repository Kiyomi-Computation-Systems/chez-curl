#!/bin/sh
# M4 slice 1's options table, for one libcurl. Run from the repository's root:
#
#   CURL_LIB=PATH [CURL_INCLUDE=DIR] sh .plans/research/m4/slice1/options.sh LANE
#
# It compiles options.c as run.sh compiles probe.c, and prints each option the
# library names, prefixed with LANE. On macOS, with CURL_LIB unset, it links
# the SDK's -lcurl, Apple's libcurl (added for M4 slice 4):
#   sh .plans/research/m4/slice1/options.sh mac
set -u
[ "$#" -eq 1 ] || { echo "usage: options.sh LANE" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "options.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/slice1-options.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" $inc -o "$tmp/options" .plans/research/m4/slice1/options.c "$CURL_LIB" \
    -Wl,-rpath,"$(dirname "$CURL_LIB")" 2> "$tmp/cc.err"
else
  "${CC:-cc}" $inc -o "$tmp/options" .plans/research/m4/slice1/options.c -lcurl 2> "$tmp/cc.err"
fi || { cat "$tmp/cc.err"; exit 1; }
"$tmp/options" | sed "s/^/[$1] /"
