#!/bin/sh
# scripts/ci/floor.sh NAME
#
# Prints one floor, NAME being chez, libcurl or node, as packaging/floors.sexp
# at the repository root writes it (ADR-0016): one line, "10.4.0". The root is
# two directories above this script.
#
# CI states no floor anywhere. This is how a step, or a script, gets one:
# scripts/ci/build-chez.sh and build-curl.sh call it for the version they
# build, and the floor lane and scripts/ci/expect-missing-api.sh for the
# version they require. It reads nothing else, no argument and no environment
# variable, so nothing a workflow says, an env key or a matrix value, can
# change what it prints.
#
# It fails closed, because a wrong floor is worse than none: it prints a floor
# only when the file is one list of (key "version") entries and holds exactly
# one entry for NAME, whose version is well-formed. That is chez and libcurl:
# three naturals, major.minor.patch; node: one natural or more; each natural
# ASCII digits with no leading zero. The file is read as text, not evaluated.
# A ; comment is dropped before anything is read. A # outside a comment is
# refused: it is a datum comment or a block comment, which Scheme's reader
# skips and this script would not. `make check-floors` holds the whole file to
# its rules, in Scheme; this script holds only what it must to be right about
# NAME. The other floors' versions are not its concern.
#
# It prints the floor on stdout and exits 0, or says what is wrong on stderr
# and exits 1, or 2 on a usage error.
set -eu

usage() {
  echo "usage: floor.sh chez|libcurl|node" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
name=$1
case $name in
  chez | libcurl)
    shape=three
    what="three dot-separated naturals, major.minor.patch"
    ;;
  node)
    shape=any
    what="dot-separated naturals"
    ;;
  *) usage ;;
esac

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
file=$root/packaging/floors.sexp
shown=packaging/floors.sexp

fail() {
  printf 'floor.sh: %s: %s\n' "$shown" "$*" >&2
  exit 1
}

[ -f "$file" ] && [ -r "$file" ] || fail "it cannot be read"

# The text without its ; comments, and with each run of white space a single
# space, so one entry is one piece of text wherever it was broken.
text=$(sed 's/;.*$//' "$file") || fail "it cannot be read"
case $text in
  *'#'*) fail "it holds a # outside a ; comment, which this script does not read" ;;
esac
text=$(printf '%s\n' "$text" | tr -s '[:space:]' ' ')

# One list of entries, each a lower-case key and a string, and nothing else.
if ! printf '%s\n' "$text" | grep -q -E '^ *\( *(\( *[a-z]+ +"[^"]*" *\) *)+\) *$'; then
  fail "it is not one list of (key \"version\") entries"
fi

entries=$(printf '%s\n' "$text" | grep -o -E "\\( *$name +\"[^\"]*\" *\\)" || true)
[ -n "$entries" ] || fail "it holds no $name entry"
case $entries in
  *'
'*) fail "it holds more than one $name entry" ;;
esac

version=$(printf '%s\n' "$entries" | sed -e 's/^[^"]*"//' -e 's/".*$//')
nat='(0|[1-9][0-9]*)'
case $shape in
  three) form="^$nat\\.$nat\\.$nat\$" ;;
  *) form="^$nat(\\.$nat)*\$" ;;
esac
if ! printf '%s\n' "$version" | grep -q -E "$form"; then
  fail "the $name version \"$version\" is not $what"
fi
printf '%s\n' "$version"
