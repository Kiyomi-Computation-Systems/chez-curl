#!/bin/sh
# M5 slice 1's URL-parts probe (2026-10-27): probe.c's two tables, append
# and parts, on one libcurl. Run from the repository's root, in the
# container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/url-parts/run.sh guix-8.20.0'
# or in Docker by docker.sh. CURL_LIB is a libcurl.so.4; CURL_INCLUDE, if
# set, the headers to compile against; CC, cc.
#
# On the Mac, against Apple's libcurl by -lcurl:
#   sh .plans/research/m5/url-parts/run.sh mac
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
[ -f .plans/research/m5/url-parts/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/urlparts.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" $inc -o "$tmp/probe" .plans/research/m5/url-parts/probe.c "$CURL_LIB" \
    -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB")"
else
  "${CC:-cc}" $inc -o "$tmp/probe" .plans/research/m5/url-parts/probe.c -lcurl 2>"$tmp/cc.err"
  echo "[$lane] libcurl by -lcurl"
fi
[ -x "$tmp/probe" ] || { cat "$tmp/cc.err"; exit 1; }
"$tmp/probe" | sed "s/^/[$lane] /"
