#!/bin/sh
# `make check-clean`: holds make clean to removing build/ and nothing else.
# It runs in a copy of the tree, so the real build/ is left alone:
#
#   1. make deps fills the copy's build/ with its links. The script adds
#      what other targets leave there: a memory log, a nested scratch
#      directory and a hidden file. It also adds three links out of
#      build/: to a directory and a file outside the copy, and to the
#      copy's vendor/;
#   2. it lists every path outside build/, the copy's and those the links
#      name: each file with its checksum, each link with its target;
#   3. make clean must exit 0 and leave no build/;
#   4. the listing must be unchanged: nothing outside build/ removed or
#      altered, and no link followed;
#   5. make clean again, with no build/, must exit 0;
#   6. make deps must then work, and link SRFI-64 again.
#
# The copy is the working tree without .git, build/ and .claude/ (Claude
# Code's local state, which can hold whole worktrees), with the chez-srfi
# checkout. Nothing in it runs git.
# make check-clean passes MAKE. Run directly, the script takes make from
# PATH.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

# The copy's make starts afresh: nothing of an outer make's flags or
# command-line variables reaches it.
unset MAKEFLAGS MFLAGS MAKELEVEL
# Sort file names byte by byte, the same on every platform.
LC_ALL=C
export LC_ALL

make=${MAKE:-make}

# mktemp's one line is the name. A template under TMPDIR, since a bare
# mktemp -d ignores it on macOS, where TMPDIR ends in a slash.
scratch=${TMPDIR:-/tmp}
scratch=${scratch%/}
tmp=$(mktemp -d "$scratch/check-clean.XXXXXX") || {
  echo "check-clean: mktemp failed" >&2
  exit 2
}
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

status=0

# fail MESSAGE [LOG]: names the problem, then shows LOG's lines.
fail() {
  echo "check-clean: $1" >&2
  if [ "$#" -ge 2 ]; then
    sed 's/^/  | /' "$2" >&2
  fi
  status=1
}

copy=$tmp/tree
mkdir "$copy"
for entry in "$root"/* "$root"/.[!.]* "$root"/..?*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  case "$entry" in "$root/.git" | "$root/build" | "$root/.claude") continue ;; esac
  cp -a "$entry" "$copy/" || { echo "check-clean: could not copy $entry" >&2; exit 2; }
done

# listing DIR: every path under DIR but DIR/build, sorted, with its kind,
# and a file's checksum or a link's target.
listing() {
  (
    cd "$1" || exit 1
    find . -path ./build -prune -o -print | sort | while IFS= read -r p; do
      if [ -L "$p" ]; then
        printf 'link %s -> %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then
        printf 'dir %s\n' "$p"
      elif [ -f "$p" ]; then
        printf 'file %s %s\n' "$p" "$(cksum <"$p")"
      else
        printf 'other %s\n' "$p"
      fi
    done
  )
}

# 1. Fill build/.
if ! (cd "$copy" && "$make" --no-print-directory deps) >"$tmp/deps-before.log" 2>&1; then
  fail "make deps failed in the copy, before make clean" "$tmp/deps-before.log"
  exit 1
fi
if [ ! -L "$copy/build/scheme-libs/srfi/:64.sls" ]; then
  fail "make deps linked no build/scheme-libs/srfi/:64.sls in the copy" "$tmp/deps-before.log"
  exit 1
fi
outside=$tmp/outside
mkdir -p "$outside/dir" "$copy/build/memory" "$copy/build/scratch/deep"
echo outside >"$outside/dir/file"
echo log >"$copy/build/memory/test-plant.sps.log"
echo deep >"$copy/build/scratch/deep/file"
echo hidden >"$copy/build/.hidden"
ln -s "$outside/dir" "$copy/build/to-outside-dir"
ln -s "$outside/dir/file" "$copy/build/to-outside-file"
ln -s ../vendor "$copy/build/to-vendor"

# 2. What must survive.
listing "$copy" >"$tmp/copy-before" && listing "$outside" >"$tmp/outside-before" || {
  echo "check-clean: could not list the copy" >&2
  exit 2
}

# 3. make clean.
if ! (cd "$copy" && "$make" --no-print-directory clean) >"$tmp/clean.log" 2>&1; then
  fail "make clean failed" "$tmp/clean.log"
elif [ -e "$copy/build" ] || [ -L "$copy/build" ]; then
  fail "make clean left build/ in place" "$tmp/clean.log"
fi

# 4. Nothing else changed.
listing "$copy" >"$tmp/copy-after" && listing "$outside" >"$tmp/outside-after" || {
  echo "check-clean: could not list the copy after make clean" >&2
  exit 2
}
if ! diff "$tmp/copy-before" "$tmp/copy-after" >"$tmp/copy.diff"; then
  fail "make clean changed the tree outside build/" "$tmp/copy.diff"
fi
if ! diff "$tmp/outside-before" "$tmp/outside-after" >"$tmp/outside.diff"; then
  fail "make clean followed a link out of build/" "$tmp/outside.diff"
fi

# 5. Again, with no build/.
if ! (cd "$copy" && "$make" --no-print-directory clean) >"$tmp/clean-again.log" 2>&1; then
  fail "make clean failed with no build/" "$tmp/clean-again.log"
fi

# 6. deps after clean.
if ! (cd "$copy" && "$make" --no-print-directory deps) >"$tmp/deps-after.log" 2>&1; then
  fail "make deps failed after make clean" "$tmp/deps-after.log"
elif [ ! -L "$copy/build/scheme-libs/srfi/:64.sls" ]; then
  fail "make deps linked no build/scheme-libs/srfi/:64.sls after make clean" "$tmp/deps-after.log"
fi

if [ "$status" -eq 0 ]; then
  echo "check-clean: ok: make clean removes build/, follows no link out of it, changes nothing else, passes again, and make deps works after it"
fi
exit "$status"
