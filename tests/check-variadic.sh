#!/bin/sh
# `make check-variadic`: proves that a variadic binding without
# (__varargs_after 2) fails, in a copy of the tree (ADR-0001, decision 1).
# It mutates src/curl/private/native.sls five ways, each from the unchanged
# file: the convention removed from bind-variadic's template, which every
# use loses at once, and then each of the four uses alone bound through
# bind-required. The steps, in order, each named ok or FAILED:
#
#   copy     the copy holds src/, tests/ and .plans/decisions/, all the two
#            suites read; SRFI-64 comes from the tree's own build/scheme-libs
#   machine  Chez's (machine-type), which decides the ABI: arm64osx and
#            tarm64osx are Apple arm64. Not uname: a Chez under Rosetta is
#            ta6osx, and runs x86-64's ABI
#   control  the unchanged copy passes test-collect-safe and test-variadic,
#            so a failure below is the mutation's doing
#
# For the template, then for each use (long, pointer, off-t, getinfo):
#
#   mutant   the text the mutation replaces stands in the unchanged
#            native.sls exactly once; after it, that text stands nowhere,
#            the lines holding its replacement are one more, and that one
#            line alone has changed
#   static   test-collect-safe fails on the mutant, on every platform. Its
#            only failing tests are the two that read the variadic
#            bindings, and its violations are exactly the mutated
#            bindings': for the template, a mismatch for each of the four
#            uses of bind-variadic, curl_easy_setopt three times and
#            curl_easy_getinfo once; for a use, a mismatch and a
#            wrong-binder for that one, and the scan places bind-required
#            where that use stands
#   arm64    on Apple arm64 only, test-variadic runs on the mutant:
#              - the template: it must fail. It may name a test, or die:
#                getinfo may write through a garbage pointer. Either
#                passes, and the step says which;
#              - a setopt use: it must fail by name, exiting 1, and its
#                failing tests must include one through that binding.
#                getinfo stays annotated, so nothing writes through a
#                garbage pointer: a crash, or no named test, fails;
#              - getinfo: it must fail, by name or by dying, and the step
#                says which
#   other    on any other machine type, test-variadic runs on the mutant
#            and its result is reported, never failed: x86-64 and Linux
#            arm64 pass variadic arguments as they pass named ones, so a
#            binding without the convention works there
#
# Every step needs positive evidence: a run's exit status, and the lines
# it must print, never an empty output. The script exits 0 only when every
# step is ok, and prints a last line saying so.
#
# POSIX sh, for macOS too: no sed -i, exact-text replacement by awk's index,
# changed lines counted by awk, and mktemp given a template under $TMPDIR,
# which BSD mktemp needs (AGENTS.md). `make check-variadic` passes CHEZ, TIMEOUT and TEST_TIMEOUT,
# the ones make test uses. Run directly, it takes scheme and timeout from
# PATH, and 300 seconds a suite.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

CHEZ=${CHEZ:-scheme}
TIMEOUT=${TIMEOUT:-timeout}
TEST_TIMEOUT=${TEST_TIMEOUT:-300}
LC_ALL=C
export LC_ALL

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'check-variadic: ok %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'check-variadic: FAILED %s\n' "$1" >&2; }
# stop: the steps after this one cannot run.
stop() {
  bad "$1"
  printf 'check-variadic: stopped after %d ok, %d FAILED\n' "$pass" "$fail" >&2
  exit 1
}

# The scratch directory: mktemp's one line, whole, absolute and a
# directory, never its first word (AGENTS.md).
base=${TMPDIR:-/tmp}
base=${base%/}
tmp=$(mktemp -d "$base/check-variadic.XXXXXX") || stop "copy: mktemp -d failed under $base"
case $tmp in
  *'
'*) stop "copy: mktemp answered more than one line" ;;
  /*) ;;
  *) stop "copy: mktemp answered '$tmp', not an absolute path" ;;
esac
[ -d "$tmp" ] || stop "copy: mktemp answered '$tmp', which is not a directory"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- copy ----
srfi=$root/build/scheme-libs
copy=$tmp/tree
native=$copy/src/curl/private/native.sls
# The unchanged native.sls, kept: each mutation starts from it.
original=$tmp/native.orig
[ -d "$srfi/srfi" ] || stop "copy: $srfi/srfi is missing; run make deps"
if mkdir "$copy" "$copy/.plans" &&
   cp -RP "$root/src" "$root/tests" "$copy/" &&
   cp -RP "$root/.plans/decisions" "$copy/.plans/" &&
   cp "$native" "$original"; then
  ok "copy: src/, tests/ and .plans/decisions/ copied to $copy"
else
  stop "copy: could not copy src/, tests/ and .plans/decisions/ to $copy"
fi

# run SUITE: SUITE in the copy, as make test runs it, under timeout. Its
# output goes to $tmp/out, and its exit status to $status.
run() {
  ( cd "$copy" &&
      "$TIMEOUT" --foreground "$TEST_TIMEOUT" "$CHEZ" --libdirs "src:tests:$srfi" --program "$1" ) \
    >"$tmp/out" 2>&1
  status=$?
}

# show: the last run's whole output, indented.
show() { sed 's/^/  | /' "$tmp/out" >&2; }

# named: the tests the last run named as failing, one a line.
named() { grep '^FAIL ' "$tmp/out"; }

# actual_of TEST: the actual value the runner printed for the failing TEST,
# whole: it prints a failing test's expected value, then its actual one.
actual_of() {
  awk -v name="FAIL $1" '$0 == name { at = NR + 2 } NR == at { print; exit }' "$tmp/out"
}

# count TEXT FILE: the lines of FILE that hold TEXT, a fixed string.
count() { grep -c -F -- "$1" "$2"; }

# differ A B: how many lines of A and B differ, place by place, with the
# longer file's extra lines. awk, not diff: BusyBox's diff prints unified
# output by default, and its sh runs its own diff whatever PATH says.
differ() {
  awk 'NR == FNR { a[FNR] = $0; n = FNR; next }
       { m = FNR; if (!(FNR in a) || a[FNR] != $0) c++ }
       END { if (n > m) c += n - m; print c + 0 }' "$1" "$2"
}

# ---- machine ----
printf '(display (machine-type))\n(newline)\n' >"$tmp/machine.ss"
machine=$("$TIMEOUT" "$TEST_TIMEOUT" "$CHEZ" --script "$tmp/machine.ss" 2>"$tmp/out")
status=$?
case $machine in
  '' | *[!a-z0-9]*) machine= ;;
esac
if [ "$status" -ne 0 ] || [ -z "$machine" ]; then
  show
  stop "machine: $CHEZ --script printing (machine-type) exited $status, printing no machine type"
fi
case $machine in
  arm64osx | tarm64osx) apple_arm64=1 ;;
  *) apple_arm64=0 ;;
esac
ok "machine: Chez's machine type is $machine"

collect=tests/test-collect-safe.sps
variadic=tests/test-variadic.sps

# ---- control ----
for suite in "$collect" "$variadic"; do
  run "$suite"
  if [ "$status" -eq 0 ]; then
    ok "control: $suite passes on the unchanged copy"
  else
    show
    stop "control: $suite exited $status on the unchanged copy, so nothing below would say anything about the mutation"
  fi
done

# mutate LABEL FROM TO: the copy's native.sls made the unchanged one with
# its one line holding FROM changed to hold TO there. FROM must stand in
# the unchanged file exactly once; TO, after the change, once more than
# before; and the change touches one line alone.
mutate() {
  label=$1 from=$2 to=$3
  found=$(count "$from" "$original")
  before=$(count "$to" "$original")
  [ "$found" = 1 ] || stop "$label mutant: the unchanged native.sls holds $from $found times, not once"
  awk -v from="$from" -v to="$to" '{
    i = index($0, from)
    if (i > 0) $0 = substr($0, 1, i - 1) to substr($0, i + length(from))
    print
  }' "$original" >"$tmp/native.sls" || stop "$label mutant: awk failed on the unchanged native.sls"
  cp "$tmp/native.sls" "$native" || stop "$label mutant: could not write the copy's native.sls"
  changed=$(differ "$original" "$native")
  left=$(count "$from" "$native")
  now=$(count "$to" "$native")
  if [ "$changed" = 1 ] && [ "$left" = 0 ] && [ "$now" = $((before + 1)) ]; then
    ok "$label mutant: $from is now $to, and no other line changed"
  else
    stop "$label mutant: the mutation changed $changed lines, left $from $left times and took $to from $before to $now lines; it must change one line, leave none and add one"
  fi
}

# static LABEL WANT_VIA WANT_VIOLATIONS: test-collect-safe on the mutant
# fails, naming exactly the two tests that read the variadic bindings,
# with WANT_VIA the actual line of the first and WANT_VIOLATIONS the
# second's, each whole. SAYS is what the ok line says it named.
via_test='the scan of src/ finds curl_easy_setopt bound three times, once per value type, and curl_easy_getinfo once, each through bind-variadic with (__varargs_after 2)'
table_test='src/ holds to the table: no violation'
want_named="FAIL $via_test
FAIL $table_test"
static() {
  label=$1 want_via=$2 want_violations=$3 says=$4
  run "$collect"
  got_named=$(named)
  got_via=$(actual_of "$via_test")
  got_violations=$(actual_of "$table_test")
  problems=
  [ "$status" -ne 0 ] || problems="${problems}  it exited 0
"
  [ "$status" -ne 124 ] || problems="${problems}  it hung: no exit within ${TEST_TIMEOUT}s
"
  [ "$got_named" = "$want_named" ] || problems="${problems}  the tests it named differ:
$(printf '%s\n' "$want_named" | sed 's/^/    wanted: /')
$(printf '%s\n' "$got_named" | sed 's/^/    got:    /')
"
  [ "$got_via" = "$want_via" ] || problems="${problems}  the bindings it found differ:
    wanted: $want_via
    got:    $got_via
"
  [ "$got_violations" = "$want_violations" ] || problems="${problems}  its violations differ:
    wanted: $want_violations
    got:    $got_violations
"
  if [ -z "$problems" ]; then
    ok "$label static: $collect fails on the mutant (exit $status), naming $says"
  else
    bad "$label static: $collect must fail on the mutant, naming $says"
    printf '%s' "$problems" >&2
    show
  fi
}

# how: what the last run of test-variadic did, in words.
how() {
  if [ -n "$got_named" ]; then
    printf 'naming %s failing tests' "$(printf '%s\n' "$got_named" | grep -c '')"
    if [ "$status" -eq 255 ]; then
      printf ', then dying by an uncaught raise (exit 255)'
    elif [ "$status" -gt 128 ]; then
      printf ', then dying by signal %s' "$((status - 128))"
    fi
  elif [ "$status" -eq 124 ]; then
    printf 'hanging: no exit within %ss' "$TEST_TIMEOUT"
  elif [ "$status" -eq 255 ]; then
    printf 'dying by an uncaught raise (exit 255), naming no test'
  elif [ "$status" -gt 128 ]; then
    printf 'dying by signal %s, naming no test' "$((status - 128))"
  else
    printf 'naming no test'
  fi
}

# list: the last run's failing tests, indented, on stdout.
list() { [ -z "$got_named" ] || printf '%s\n' "$got_named" | sed 's/^/  /'; }

# other LABEL: test-variadic on the mutant, off Apple arm64: reported.
other() {
  if [ "$status" -eq 0 ]; then
    ok "$1 other: on $machine, $variadic passes on the mutant (exit 0), as expected: this ABI passes variadic arguments as it passes named ones, so only Apple arm64 (arm64osx, tarm64osx) can show the mutation"
  else
    ok "$1 other: on $machine, $variadic fails on the mutant (exit $status), $(how): this ABI showed the mutation too"
    list
  fi
}

# fails LABEL: on Apple arm64, test-variadic fails on the mutant, by name
# or by dying, and the step says which.
fails() {
  label=$1
  if [ "$status" -ne 0 ] && [ "$status" -ne 124 ] && { [ -n "$got_named" ] || [ "$status" -gt 128 ]; }; then
    ok "$label arm64: on $machine, $variadic fails on the mutant (exit $status), $(how)"
    list
  else
    bad "$label arm64: on $machine, $variadic must fail on the mutant, by a named test or by dying; it exited $status, $(how)"
    show
  fi
}

# fails_by_name LABEL BINDING: on Apple arm64, test-variadic fails on the
# mutant by name, exiting 1, and a failing test runs through BINDING.
fails_by_name() {
  label=$1 binding=$2
  own=$(printf '%s\n' "$got_named" | grep -c -F -- " through $binding ")
  if [ "$status" -eq 1 ] && [ "$own" -gt 0 ]; then
    ok "$label arm64: on $machine, $variadic fails on the mutant by name (exit 1), $(how), $own of them through $binding"
    list
  else
    bad "$label arm64: on $machine, $variadic must fail on the mutant by name, exiting 1, with a failing test through $binding; it exited $status, $(how), $own of them through $binding"
    show
  fi
}

file='"src/curl/private/native.sls"'
setopt='"curl_easy_setopt"'
getinfo='"curl_easy_getinfo"'
annotated='(((__varargs_after 2)) bind-variadic)'
plain='(() bind-required)'

# ---- the template ----
mutate template '(foreign-procedure (__varargs_after 2) entry (arg ...) result)' \
  '(foreign-procedure entry (arg ...) result)'
mismatch="(mismatch $setopt ((__varargs_after 2)) () $file)"
static template \
  "  actual:   (($setopt ((() bind-variadic) (() bind-variadic) (() bind-variadic))) ($getinfo ((() bind-variadic))))" \
  "  actual:   ($mismatch $mismatch $mismatch (mismatch $getinfo ((__varargs_after 2)) () $file))" \
  "curl_easy_setopt three times and curl_easy_getinfo once as mismatches"
run "$variadic"
got_named=$(named)
if [ "$apple_arm64" -eq 1 ]; then
  fails template
else
  other template
fi

# ---- each use alone ----
# use LABEL KEY TYPES BINDING VIA: the use of bind-variadic binding KEY
# with TYPES, which defines BINDING, bound through bind-required instead.
# VIA is where the scan of src/ then finds bind-required.
use() {
  label=$1 key=$2 types=$3 binding=$4 via=$5
  mutate "$label" "(bind-variadic \"$key\" $types int info)" "(bind-required \"$key\" $types int info)"
  static "$label" "  actual:   $via" \
    "  actual:   ((mismatch \"$key\" ((__varargs_after 2)) () $file) (wrong-binder \"$key\" bind-variadic bind-required $file))" \
    "$binding alone: a mismatch and a wrong-binder for $key"
  run "$variadic"
  got_named=$(named)
  if [ "$apple_arm64" -eq 0 ]; then
    other "$label"
  elif [ "$label" = getinfo ]; then
    fails "$label"
  else
    fails_by_name "$label" "$binding"
  fi
}

use long curl_easy_setopt '(uptr int long)' curl-easy-setopt-long \
  "(($setopt ($plain $annotated $annotated)) ($getinfo ($annotated)))"
use pointer curl_easy_setopt '(uptr int uptr)' curl-easy-setopt-pointer \
  "(($setopt ($annotated $plain $annotated)) ($getinfo ($annotated)))"
use off-t curl_easy_setopt '(uptr int integer-64)' curl-easy-setopt-off-t \
  "(($setopt ($annotated $annotated $plain)) ($getinfo ($annotated)))"
use getinfo curl_easy_getinfo '(uptr int uptr)' curl-easy-getinfo \
  "(($setopt ($annotated $annotated $annotated)) ($getinfo ($plain)))"

if [ "$fail" -eq 0 ]; then
  printf 'check-variadic: all %d steps ok, on %s\n' "$pass" "$machine"
fi
[ "$fail" -eq 0 ]
