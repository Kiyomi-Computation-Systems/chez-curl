#!/bin/sh
# `make check-dev`: holds make dev to what it promises, by running it as a
# person would, through make, with forms piped in for its REPL. Each case
# runs in a fresh copy of the tree with no build/, as a fresh clone has, so
# make dev must run make deps itself. Two cases:
#
#   repl     make dev runs make build first, so its output must hold
#            build's "libcurl loaded and accepted" report once, then the
#            REPL's banner once, then exactly one line "check-dev: ok
#            version VERSION" and one "check-dev: ok path PATH (SOURCE)".
#            The piped forms print them only once (curl), (curl-testing)
#            and (srfi :64) have all imported, which takes the suites' whole
#            library path and make deps' links, and (curl) has loaded
#            libcurl. VERSION, PATH and SOURCE, read through (curl), must
#            equal what build's report names. A REPL that fails an import
#            prints the error, reads on, and exits 0 at the end of its
#            input, so the lines are the evidence, and the exit status only
#            has to be 0.
#   refused  with CHEZ_CURL_LIBCURL naming no file, make dev must fail
#            with build's refusal, and no REPL may start: neither the
#            banner nor a line may appear.
#
# A copy is the working tree without .git, build/ and .claude/ (Claude
# Code's local state, which can hold whole worktrees), with the chez-srfi
# checkout. Nothing in it runs git. Each case runs under timeout, so a REPL
# that never reads the end of its input cannot hang the check. make
# check-dev passes MAKE and TIMEOUT, the tools it found. Run directly, the
# script takes make and timeout from PATH.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

# The inner make starts afresh: nothing of an outer make's flags or
# command-line variables reaches it.
unset MAKEFLAGS MFLAGS MAKELEVEL

make=${MAKE:-make}
timeout=${TIMEOUT:-timeout}
limit=120
missing=/nonexistent/chez-curl-check-dev/libcurl.so.4
status=0

# mktemp's one line is the name. A template under TMPDIR, since a bare
# mktemp -d ignores it on macOS, where TMPDIR ends in a slash.
scratch=${TMPDIR:-/tmp}
scratch=${scratch%/}
tmp=$(mktemp -d "$scratch/check-dev.XXXXXX") || {
  echo "check-dev: mktemp failed" >&2
  exit 2
}
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# fresh-copy DIR: the working tree, copied to DIR, with no build/.
fresh_copy() {
  mkdir "$1" || return 1
  for entry in "$root"/* "$root"/.[!.]* "$root"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    case "$entry" in "$root/.git" | "$root/build" | "$root/.claude") continue ;; esac
    cp -a "$entry" "$1/" || return 1
  done
}

# fail CASE MESSAGE OUTPUT: names the case and the problem, then shows
# what make dev printed.
fail() {
  echo "check-dev: $1: $2" >&2
  printf '%s\n' "$3" | sed 's/^/  | /' >&2
  status=1
}

# The REPL prints a prompt before each form, so the lines start with a
# newline of their own.
forms='(import (curl) (curl-testing) (srfi :64))
(begin
  (newline)
  (when (and (procedure? loaded-libcurl) (procedure? suite-exit-status)
             (procedure? test-runner-simple))
    (let ((info (loaded-libcurl)))
      (display "check-dev: ok version ")
      (display (libcurl-info-version info))
      (newline)
      (display "check-dev: ok path ")
      (display (libcurl-info-path info))
      (display " (")
      (display (libcurl-info-source info))
      (display ")")
      (newline))))
'

# ---- repl ----
fresh_copy "$tmp/repl" || { echo "check-dev: could not copy the tree" >&2; exit 2; }
out=$(cd "$tmp/repl" && printf '%s' "$forms" | "$timeout" --foreground "$limit" "$make" --no-print-directory dev 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  fail repl "make dev exited $rc, not 0" "$out"
else
  # Prints ok, or the first problem it finds.
  verdict=$(printf '%s\n' "$out" | awk '
    $0 == "chez-curl: libcurl loaded and accepted" { n_report++; if (!report) report = NR }
    index($0, "Chez Scheme Version ") == 1 { n_banner++; if (!banner) banner = NR }
    index($0, "  version:  ") == 1 { n_version++; version = substr($0, 13) }
    index($0, "  path:     ") == 1 { n_path++; path = substr($0, 13) }
    index($0, "check-dev: ok version ") == 1 { n_got_version++; at_version = NR; got_version = substr($0, 23) }
    index($0, "check-dev: ok path ") == 1 { n_got_path++; at_path = NR; got_path = substr($0, 20) }
    END {
      if (n_report != 1) print "build'\''s report appears " n_report + 0 " times, not once"
      else if (n_banner != 1) print "the REPL'\''s banner appears " n_banner + 0 " times, not once"
      else if (n_version != 1) print "build'\''s version line appears " n_version + 0 " times, not once"
      else if (n_path != 1) print "build'\''s path line appears " n_path + 0 " times, not once"
      else if (n_got_version != 1) print "the line \"check-dev: ok version VERSION\" appears " n_got_version + 0 " times, not once"
      else if (n_got_path != 1) print "the line \"check-dev: ok path PATH (SOURCE)\" appears " n_got_path + 0 " times, not once"
      else if (!(report < banner && banner < at_version && banner < at_path)) print "build'\''s report, the banner and the lines are out of order"
      else if (got_version != version) print "the REPL loaded libcurl " got_version ", but build named " version
      else if (got_path != path) print "the REPL loaded " got_path ", but build named " path
      else print "ok"
    }')
  awk_rc=$?
  if [ "$awk_rc" -ne 0 ]; then
    fail repl "the output check exited $awk_rc" "$out"
  elif [ "$verdict" != ok ]; then
    fail repl "$verdict" "$out"
  fi
fi

# ---- refused ----
fresh_copy "$tmp/refused" || { echo "check-dev: could not copy the tree" >&2; exit 2; }
out=$(cd "$tmp/refused" && printf '%s' "$forms" | CHEZ_CURL_LIBCURL=$missing "$timeout" --foreground "$limit" "$make" --no-print-directory dev 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  fail refused "make dev passed with CHEZ_CURL_LIBCURL naming no file" "$out"
elif [ "$rc" -eq 124 ]; then
  fail refused "make dev hung with CHEZ_CURL_LIBCURL naming no file" "$out"
elif ! printf '%s\n' "$out" | grep -qxF 'chez-curl: libcurl refused'; then
  fail refused "make dev did not fail with build's refusal" "$out"
elif printf '%s\n' "$out" | grep -qE '^(Chez Scheme Version |check-dev: ok )'; then
  fail refused "a REPL started after build refused libcurl" "$out"
fi

if [ "$status" -eq 0 ]; then
  echo "check-dev: ok: in a fresh copy, make dev runs deps and build, then a REPL with the suites' library path and build's libcurl; a refused libcurl stops it"
fi
exit "$status"
