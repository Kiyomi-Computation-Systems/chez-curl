#!/bin/sh
# `make check-test-fails`: proves that `make test` fails on a bad suite, by
# planting one in a copy of the tree (ADR-0015). One case per plant:
#
#   fails        a suite with a failing test   make test names it FAIL
#   no-tests     a suite that runs no test     make test names it FAIL
#   hangs        a suite that never ends       make test names it HUNG
#   exit-line    a suite that ends with the    check-suites names it, and
#                siblings' exit line           no suite runs
#   early-exit   a suite with a failing test   check-suites names it, and
#                that exits 0 before its       no suite runs
#                verdict
#   nested-exit  the same, with the exit 0     check-suites names it, and
#                inside a when                 no suite runs
#   empty        an empty file (Chez fails     check-suites names it, and
#                it, exit 255, unexplained)    no suite runs
#   seam         a (curl ...) library that     check-seam names the import,
#                imports (http-client ...)     and no suite runs
#   floors       README's Chez line says       check-floors names the line,
#                10.3.0, not the floor         and no suite runs
#   no-suites    every suite deleted           make test refuses to pass
#
# The copy holds no real suite, so no slow one can run into the 5 s
# TEST_TIMEOUT. The plant is tests/test-0-plant.sps. After it sorts
# tests/test-1-after.sps, a suite that passes: in the first three cases its
# pass line shows that make test runs the suites after a failure. Each plant
# but no-tests has a passing test of its own, so only the planted fault can
# fail it.
#
# A case requires a non-zero exit, and compares the lines starting
# "check-suites: " or "test: " as a whole: check-suites' verdict, the plant's
# outcome, the after-suite's pass line, and the count. The seam case also
# compares the lines starting "check-seam: ", and the floors case those
# starting "check-floors: ".
#
# The copy is the working tree without .git and build/, and with the
# chez-srfi checkout, so make deps works there and nothing is fetched.
# Nothing in the copy runs git. make deps relinks build/ in the copy. Its
# src/ is the script's own, two libraries with legal imports, whatever the
# tree holds, so check-seam passes in every case but seam. README.org and
# packaging/floors.sexp are the tree's own, and agree, so check-floors passes
# in every case but floors.
#
# `make check-test-fails` passes MAKE and TIMEOUT, the tools it found. Run
# directly, the script takes make and timeout from PATH.
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

# The copy's make starts afresh: nothing of an outer make's flags or
# command-line variables reaches it.
unset MAKEFLAGS MFLAGS MAKELEVEL
# Sort file names byte by byte, as make's $(sort) does.
LC_ALL=C
export LC_ALL

# Every case runs make test with this TEST_TIMEOUT, in seconds, so the
# hanging plant is killed soon. The two suites in the copy finish at once.
suite_timeout=5
# The plant and the after-suite each run for at most suite_timeout seconds.
# A make test that runs much longer has lost its per-suite timeout.
make_timeout=$(( 2 * suite_timeout + 60 ))

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

copy=$tmp/tree
mkdir "$copy"
for entry in "$root"/* "$root"/.[!.]* "$root"/..?*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  case "$entry" in "$root/.git" | "$root/build") continue ;; esac
  cp -a "$entry" "$copy/" || { echo "check-test-fails: could not copy $entry" >&2; exit 2; }
done
# No real suite: the plant and the after-suite are the only two.
rm -f "$copy"/tests/test-*.sps
# No real library: one on each side of the seam, each import legal, so that
# check-seam passes until a case plants a bad one.
rm -rf "$copy/src"
mkdir "$copy/src"
cat >"$copy/src/curl.sls" <<'EOF'
#!r6rs
;;; Written by tests/check-test-fails.sh: a legal (curl) library.
(library (curl)
  (export curl-version)
  (import (rnrs))
  (define curl-version "fixture"))
EOF
cat >"$copy/src/http-client.sls" <<'EOF'
#!r6rs
;;; Written by tests/check-test-fails.sh: a legal (http-client) library.
(library (http-client)
  (export client-version)
  (import (rnrs) (curl))
  (define client-version curl-version))
EOF

# ---- the plants ----
plant_dir=$tmp/plants
mkdir "$plant_dir"

cat >"$plant_dir/fails" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite with a failing test.
(import (rnrs) (srfi :64) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "plant-fails")
(test-assert "passes, so only the failure below can fail this suite" #t)
(test-equal "the planted failure" 1 2)
(test-end "plant-fails")
(exit (suite-exit-status runner))
EOF

cat >"$plant_dir/no-tests" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite that runs no test.
(import (rnrs) (srfi :64) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "plant-no-tests")
(test-end "plant-no-tests")
(exit (suite-exit-status runner))
EOF

cat >"$plant_dir/hangs" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite that never ends.
(import (rnrs) (srfi :64) (only (chezscheme) sleep make-time) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "plant-hangs")
(test-assert "passes, so only the hang below can fail this suite" #t)
(sleep (make-time 'time-duration 0 3600))
(test-end "plant-hangs")
(exit (suite-exit-status runner))
EOF

cat >"$plant_dir/exit-line" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite that ends with the
;;; siblings' exit line, which lets a suite that ran no test pass.
(import (rnrs) (srfi :64) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "plant-exit-line")
(test-assert "passes, so only check-suites can fail this suite" #t)
(test-end "plant-exit-line")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
EOF

cat >"$plant_dir/early-exit" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite with a failing test that
;;; exits 0 before its verdict. The shared exit form after it never runs.
(import (rnrs) (srfi :64) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "plant-early-exit")
(test-assert "passes, so only the failure below can fail this suite" #t)
(test-equal "the planted failure" 1 2)
(test-end "plant-early-exit")
(exit 0)
(exit (suite-exit-status runner))
EOF

cat >"$plant_dir/nested-exit" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite with a failing test whose
;;; exit 0, inside a when, comes before the shared exit form.
(import (rnrs) (srfi :64) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "plant-nested-exit")
(test-assert "passes, so only the failure below can fail this suite" #t)
(test-equal "the planted failure" 1 2)
(test-end "plant-nested-exit")
(when (positive? (test-runner-fail-count runner))
  (exit 0))
(exit (suite-exit-status runner))
EOF

cat >"$plant_dir/seam" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a (curl ...) library that imports
;;; an (http-client ...) library, which ADR-0007's seam forbids.
(library (curl planted)
  (export planted)
  (import (rnrs) (http-client session))
  (define planted 1))
EOF

cat >"$plant_dir/after" <<'EOF'
#!r6rs
;;; Planted by tests/check-test-fails.sh: a suite that passes, sorted after
;;; the plant, so its pass line shows that make test went on after a failure.
(import (rnrs) (srfi :64) (curl-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "after")
(test-assert "passes" #t)
(test-end "after")
(exit (suite-exit-status runner))
EOF

plant=tests/test-0-plant.sps
after=tests/test-1-after.sps
cp "$plant_dir/after" "$copy/$after"

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'check-test-fails: ok %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'check-test-fails: FAILED %s\n' "$1" >&2; }

checked() {
  printf 'check-suites: every suite ends with (exit (suite-exit-status runner)) (%d checked)\n' "$1"
}

# expected PLANT-LINE FAILED HUNG: the lines a run must print with a plant
# that check-suites accepts. The after-suite passes.
expected() {
  checked 2
  printf '%s\n' "$1"
  printf 'test: pass %s\n' "$after"
  printf 'test: ran 2, passed 1, failed %d, hung %d\n' "$2" "$3"
}

# run_case NAME WANTED [LINES]: runs make test in the copy, then requires a
# non-zero exit and exactly the WANTED lines: those matching the egrep pattern
# LINES, by default the check-suites and test lines. On a failure it prints
# make test's whole output.
run_case() {
  name=$1 wanted=$2 lines=${3:-'^(check-suites|test): '}
  ( cd "$copy" &&
      "${TIMEOUT:-timeout}" "$make_timeout" "${MAKE:-make}" --no-print-directory test \
        TEST_TIMEOUT="$suite_timeout" ) \
    >"$tmp/out" 2>&1
  status=$?
  got=$(grep -E "$lines" "$tmp/out")
  wrong=0
  if [ "$status" -eq 124 ]; then
    bad "$name: make test did not finish within ${make_timeout}s, so no per-suite timeout is stopping its suites"
    wrong=1
  elif [ "$status" -eq 0 ]; then
    bad "$name: make test exited 0"
    wrong=1
  fi
  if [ "$got" != "$wanted" ]; then
    bad "$name: make test's lines differ"
    printf '%s\n' "$wanted" | sed 's/^/  wanted: /' >&2
    printf '%s\n' "$got" | sed 's/^/  got:    /' >&2
    wrong=1
  fi
  if [ "$wrong" -eq 0 ]; then
    ok "$name"
  else
    sed 's/^/  | /' "$tmp/out" >&2
  fi
}

cp "$plant_dir/fails" "$copy/$plant"
run_case "fails: a failing suite is named FAIL, and the suites after it run" \
  "$(expected "test: FAIL $plant (exit 1)" 1 0)"

cp "$plant_dir/no-tests" "$copy/$plant"
run_case "no-tests: a suite that runs no test is named FAIL, and the suites after it run" \
  "$(expected "test: FAIL $plant (exit 1)" 1 0)"

cp "$plant_dir/hangs" "$copy/$plant"
run_case "hangs: a suite that never ends is named HUNG, and the suites after it run" \
  "$(expected "test: HUNG $plant (no exit within ${suite_timeout}s)" 0 1)"

cp "$plant_dir/exit-line" "$copy/$plant"
run_case "exit-line: check-suites names a suite without the shared exit form, and no suite runs" \
  "check-suites: $plant: its last datum is (exit (if (zero? (test-runner-fail-count runner)) 0 1)), not (exit (suite-exit-status runner))"

cp "$plant_dir/early-exit" "$copy/$plant"
run_case "early-exit: check-suites names a suite that exits before its verdict, and no suite runs" \
  "check-suites: $plant: (exit 0) before the last datum would end the suite before its verdict; only (exit 1) may exit early"

cp "$plant_dir/nested-exit" "$copy/$plant"
run_case "nested-exit: check-suites names an exit inside a form before the verdict, and no suite runs" \
  "check-suites: $plant: (exit 0) before the last datum would end the suite before its verdict; only (exit 1) may exit early"

: >"$copy/$plant"
run_case "empty: check-suites names a suite with no datum, and no suite runs" \
  "check-suites: $plant: it holds no datum, so it cannot end with (exit (suite-exit-status runner))"

# The plant is gone, so only the after-suite is left to check.
rm -f "$copy/$plant"
mkdir "$copy/src/curl"
cp "$plant_dir/seam" "$copy/src/curl/planted.sls"
run_case "seam: check-seam names a (curl ...) library that imports (http-client ...), and no suite runs" \
  "$(checked 1
     echo 'check-seam: src/curl/planted.sls: (curl planted) imports (http-client session), but no (curl ...) library may import an (http-client ...) library'
     echo 'check-seam: FAILED (problems: 1)')" \
  '^(check-suites|check-seam|test): '
rm -rf "$copy/src/curl"

# The floors case: the copy's README states an older Chez than the floors
# file does. The file's floor is read from the file, so this script is no
# fourth place that writes it. check-floors passes before and after: the
# README is restored.
chez_floor=$(sed -n 's/^ *((chez "\([0-9.]*\)").*$/\1/p' "$root/packaging/floors.sexp")
case "$chez_floor" in
  "" | *[!0-9.]*) bad "floors: could not read the Chez floor from packaging/floors.sexp"; chez_floor=0.0.0 ;;
esac
sed 's/^- Chez Scheme .* or later, built with threads$/- Chez Scheme 10.3.0 or later, built with threads/' \
  "$root/README.org" >"$copy/README.org"
if cmp -s "$root/README.org" "$copy/README.org"; then
  bad "floors: the plant did not change README.org, so it plants nothing"
fi
run_case "floors: check-floors names a README that states another Chez floor, and no suite runs" \
  "$(checked 1
     echo "check-floors: README.org: list line 1 under \"** Requirements\" is \"- Chez Scheme 10.3.0 or later, built with threads\", but packaging/floors.sexp gives \"- Chez Scheme $chez_floor or later, built with threads\""
     echo 'check-floors: FAILED (problems: 1)')" \
  '^(check-suites|check-floors|test): '
cp "$root/README.org" "$copy/README.org"

rm -f "$copy"/tests/test-*.sps
run_case "no-suites: make test refuses to pass with no suite to run" \
  "$(checked 0; echo 'test: no suites: nothing matches tests/test-*.sps')"

if [ "$fail" -eq 0 ]; then
  printf 'check-test-fails: make test failed, as it must, in all %d cases\n' "$pass"
fi
[ "$fail" -eq 0 ]
