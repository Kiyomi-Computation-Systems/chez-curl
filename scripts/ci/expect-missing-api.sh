#!/bin/sh
# scripts/ci/expect-missing-api.sh ENTRY-POINT
#
# For the floor-disabled-api lanes of .github/workflows/ci.yml (ADR-0003),
# run from the repository root. Runs `make build`, which must refuse the
# libcurl CHEZ_CURL_LIBCURL names, a libcurl at its floor built with one API
# disabled, as missing-api, naming ENTRY-POINT: the C function whose
# probe finds that API missing, curl_easy_option_by_name for the options API
# and curl_easy_header for the header API.
#
# It fails unless make build exits non-zero and prints, once, the line that
# opens tests/preflight.sps's refusal, followed by exactly these whole lines,
# in this order:
#
#   chez-curl: libcurl refused
#   (reason . missing-api)
#     path:       $CHEZ_CURL_LIBCURL
#     source:     override
#     detail:     ENTRY-POINT
#     version:    the libcurl floor
#
# The libcurl floor is the one packaging/floors.sexp holds (ADR-0016), read by
# scripts/ci/floor.sh, which fails closed. It is read from the file, not from
# the environment or an argument: nothing a workflow says can change the
# version this requires.
#
# The detail line is what tells the two lanes apart: each library is refused
# as missing-api, by a different probe. The lines preflight prints after
# these are not compared: TLS and features name what the runner's packages
# let curl build in, and the remedy restates the detail in prose.
#
# It prints make build's output whole, then its verdict. It exits 0 or 1, or
# 2 on a usage error.
set -eu

usage() {
  echo "usage: expect-missing-api.sh ENTRY-POINT, with CHEZ_CURL_LIBCURL set" >&2
  exit 2
}

[ "$#" -eq 1 ] && [ -n "$1" ] || usage
[ -n "${CHEZ_CURL_LIBCURL:-}" ] || usage
entry=$1

fail() {
  echo "::error::expect-missing-api: $*"
  exit 1
}

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
floor=$(sh "$here/floor.sh" libcurl) || fail "no libcurl floor to require"

work=$(mktemp -d "${TMPDIR:-/tmp}/expect-missing-api.XXXXXX")
trap 'rm -rf "$work"' EXIT

status=0
make build >"$work/build.log" 2>&1 || status=$?
cat "$work/build.log"
[ "$status" -ne 0 ] || fail "make build accepted $CHEZ_CURL_LIBCURL, which it must refuse as missing-api, naming $entry"

heading='chez-curl: libcurl refused'
printf '%s\n' \
  "$heading" \
  '(reason . missing-api)' \
  "  path:       $CHEZ_CURL_LIBCURL" \
  '  source:     override' \
  "  detail:     $entry" \
  "  version:    $floor" >"$work/expected"

count=$(grep -c -x -F -- "$heading" "$work/build.log" || true)
[ "$count" = 1 ] || fail "make build exited $status, and printed the line '$heading' ${count:-no} times, but must print it once"

start=$(grep -n -x -F -- "$heading" "$work/build.log" | cut -d: -f1)
lines=$(grep -c '' "$work/expected")
sed -n "${start},$((start + lines - 1))p" "$work/build.log" >"$work/found"
if ! diff -u "$work/expected" "$work/found" >"$work/diff"; then
  cat "$work/diff"
  fail "make build exited $status, but did not refuse $CHEZ_CURL_LIBCURL at $floor as missing-api, naming $entry: the diff above runs from what must be printed to what was"
fi
echo "expect-missing-api: make build exited $status, refusing $CHEZ_CURL_LIBCURL at $floor as missing-api, naming $entry"
