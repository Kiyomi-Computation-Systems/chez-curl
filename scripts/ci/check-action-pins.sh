#!/bin/sh
# scripts/ci/check-action-pins.sh DIR
#
# Fails unless every line of every file under DIR (CI passes
# .github/workflows) that holds a `uses` key is exactly this, with its action
# at a full commit SHA, 40 hex digits, and the release tag that SHA was
# resolved from in a comment after it:
#
#   uses: actions/checkout@<40 hex digits> # v7.0.1
#
# with any indent, and an optional `- ` before it. Nothing else passes: the
# line holds nothing but the key, the action, the SHA and the comment.
#
# A line "holds a uses key" in any spelling of one, so a pinned step cannot
# hide in another: the key bare, in single or double quotes, with white space
# before its colon, as a step's first key or a later one, a job's, or inside a
# flow mapping or sequence ({uses: ...}, [{uses: ...}], after a comma). Every
# such line must be the form above, so a flow mapping, a quoted key, a space
# before the colon, a quoted value and a value on the next line all fail,
# whether or not the SHA is there. A line that is only a comment is skipped.
# The check reads text, not YAML: a `uses` in the middle of a string on a line
# counts, and fails too. That is the price of failing closed.
#
# A tag or a branch can be moved to other code after it was reviewed; a
# commit cannot. To bump a pin, resolve the tag on a machine with git:
#
#   git ls-remote https://github.com/OWNER/REPO refs/tags/TAG 'refs/tags/TAG^{}'
#
# and take the commit the ^{} line names, or the one line's commit when the
# tag is not annotated. This script reads text only: it does not check that
# the comment's tag names that commit, which needs the network.
#
# It fails closed, because a check that finds nothing to check passes
# vacuously: on a DIR that is not a directory or holds no file, on a file it
# cannot read, and when no file under DIR has a line with a uses key at all. A
# local action (./path) or a docker:// image fails too: none is used, and one
# would need a rule of its own.
#
# It prints one line on a pass, naming how many lines it checked, or each line
# at fault, as FILE:LINE:TEXT, on stderr. It exits 0 or 1, or 2 on a usage
# error.
set -eu

usage() {
  echo "usage: check-action-pins.sh DIR" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
dir=$1

fail() {
  printf 'check-action-pins: %s\n' "$*" >&2
  exit 1
}

# Bytes, not characters: a file that is not valid in the locale's encoding is
# still read, line by line, and never skipped as binary.
LC_ALL=C
export LC_ALL

[ -d "$dir" ] || fail "$dir is not a directory"

# A uses key in any spelling: bare or in quotes, white space allowed before its
# colon, at the start of the line or after white space, a brace, a bracket or a
# comma.
quote="[\"']?"
uses_key="(^|[][{,[:space:]])${quote}uses${quote}[[:space:]]*:"
# A line that is only a comment.
comment='^[0-9]+:[[:space:]]*#'
# The one form allowed, after the line number grep -n puts first.
canonical='^[0-9]+:[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*[[:space:]]*$'

work=$(mktemp -d "${TMPDIR:-/tmp}/check-action-pins.XXXXXX")
trap 'rm -rf "$work"' EXIT

find "$dir" ! -type d | sort >"$work/files"
[ -s "$work/files" ] || fail "$dir holds no file"

# grep answers 0 when it selects a line, 1 when it selects none, and 2 when it
# fails: keep says what it selected, and stops the script on a 2.
keep() {
  rc=0
  grep -a -E "$@" || rc=$?
  [ "$rc" -le 1 ] || fail "grep failed on a line it gathered"
}

: >"$work/at-fault"
count=0
while IFS= read -r file; do
  rc=0
  grep -a -n -E "$uses_key" -- "$file" >"$work/hits" || rc=$?
  # grep answers 1 for a file with no match, and 2 when it cannot read it.
  [ "$rc" -le 1 ] || fail "$file cannot be read"
  keep -v "$comment" <"$work/hits" >"$work/lines"
  count=$((count + $(grep -c '' "$work/lines" || true)))
  keep -v "$canonical" <"$work/lines" >"$work/off"
  while IFS= read -r line; do
    printf '%s:%s\n' "$file" "$line" >>"$work/at-fault"
  done <"$work/off"
done <"$work/files"

[ "$count" -ne 0 ] || fail "no file under $dir has a line with a uses key, so nothing was checked"

if [ -s "$work/at-fault" ]; then
  while IFS= read -r line; do
    printf 'check-action-pins: %s\n' "$line" >&2
  done <"$work/at-fault"
  fail "$(grep -c '' "$work/at-fault") of $count lines with a uses key are not \"uses: OWNER/REPO@<40 hex digits> # vTAG\", after an optional \"- \""
fi
printf 'check-action-pins: all %s lines with a uses key under %s name a full commit SHA, with its tag in a comment\n' "$count" "$dir"
