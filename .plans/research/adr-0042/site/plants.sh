#!/bin/sh
# Plants one defect per copy of the tree, under build/plants/, and requires
# the site's checks to fail on each, naming it. Run inside the container,
# from the repository root, after make check-site has passed once (so
# build/akku and build/scheme-libs exist), on a build/plants/ that does not
# exist yet:
#
#   scripts/guix-env sh .plans/research/adr-0042/site/plants.sh
#
# Prints one line per plant: "watched-fail" when the check failed and said
# what was expected, "NOT-WATCHED" otherwise, then a count. Exits 1 unless
# every plant was watched failing and the control passed.
set -u
root=$(pwd)
cmark="$root/build/akku/chez-cmark-gfm/src"
srfi="$root/build/scheme-libs"
plants="$root/build/plants"
mkdir "$plants" || { echo "plants: $plants exists; remove it first" >&2; exit 2; }

watched=0; missed=0

# copy DIR: a copy of what the site's checks read, at build/plants/DIR.
copy() {
  mkdir "$plants/$1"
  cp -R site build-site.sps tests docs examples src README.org "$plants/$1/"
}

# site_check DIR: runs tests/check-site.sps in the copy, as make check-site does.
site_check() {
  (cd "$plants/$1" && "$CHEZ" --libdirs ".:$cmark" --program tests/check-site.sps) \
    >"$plants/$1.out" 2>"$plants/$1.err"
}

# site_unit DIR: runs tests/site-unit.sps in the copy, with no chez-cmark-gfm.
site_unit() {
  (cd "$plants/$1" && "$CHEZ" --libdirs ".:tests:$srfi" --program tests/site-unit.sps) \
    >"$plants/$1.out" 2>"$plants/$1.err"
}

# expect NAME STATUS WANT: the plant's command exited STATUS; WANT must be in
# its stderr or stdout, and STATUS must not be 0.
expect() {
  if [ "$2" -ne 0 ] && grep -Fq -- "$3" "$plants/$1.err" "$plants/$1.out"; then
    echo "watched-fail $1 (exit $2): $3"; watched=$((watched + 1))
  else
    echo "NOT-WATCHED $1 (exit $2), wanted: $3"; missed=$((missed + 1))
    head -n 3 "$plants/$1.err" | sed 's/^/    /'
  fi
}

# The control: an unchanged copy passes, so a failure below is the plant's.
copy control; site_check control; c=$?
if [ "$c" -eq 0 ] && grep -Fq "all green" "$plants/control.out"; then
  echo "control passes (exit 0, all green)"
else
  echo "CONTROL FAILED (exit $c)"; missed=$((missed + 1))
fi

# P1: a docs page on disk that the nav does not name.
copy p1; printf '# New\n' >"$plants/p1/docs/new.md"; site_check p1
expect p1 $? 'missing-from-site/pages.sls=(new.md)'

# P2: a page dropped from the nav.
copy p2; sed -i '/"streams.md"/d' "$plants/p2/site/pages.sls"; site_check p2
expect p2 $? 'missing-from-site/pages.sls=(streams.md)'

# P3: a label changed in the nav alone.
copy p3; sed -i 's/"Streams")/"Streaming")/' "$plants/p3/site/pages.sls"; site_check p3
expect p3 $? "the nav is not docs/README.md's The pages list"

# P4: two pages swapped in the nav, the set and labels unchanged.
copy p4
sed -i -e 's/("streams.md" *\. "Streams")/("TMP")/' \
       -e 's/("groups.md" *\. "Groups")/("streams.md" . "Streams")/' \
       -e 's/("TMP")/("groups.md" . "Groups")/' "$plants/p4/site/pages.sls"
site_check p4
expect p4 $? "the nav is not docs/README.md's The pages list"

# P5: a link to an anchor no heading has.
copy p5; printf '\n[x](streams.md#nonesuch)\n' >>"$plants/p5/docs/groups.md"; site_check p5
expect p5 $? 'anchor resolution FAILED. danglers=((groups.md . streams.md#nonesuch))'

# P6: a link out to a repository file that does not exist.
copy p6; printf '\n[x](../examples/nonesuch.sps)\n' >>"$plants/p6/docs/groups.md"; site_check p6
expect p6 $? 'names no file in it, in groups.md'

# P7: an item in The pages with no link.
copy p7; sed -i 's/^- \[Groups\](groups.md)/- [Groups/' "$plants/p7/docs/README.md"; site_check p7
expect p7 $? "holds an item with no link"

# P8: a pure library of the site's that imports (cmark gfm): site-unit, with
# no chez-cmark-gfm on its path, fails at import.
copy p8; sed -i 's/(import (rnrs))/(import (rnrs) (cmark gfm))/' "$plants/p8/site/slug.sls"; site_unit p8
expect p8 $? '(cmark gfm)'

# P9: slugify keeps a "!", which GitHub drops: site-unit fails, and exits 1.
copy p9
sed -i 's/(or (char-alphabetic? c)/(or (char=? c #\\!) (char-alphabetic? c)/' "$plants/p9/site/slug.sls"
grep -q 'char=? c #\\!' "$plants/p9/site/slug.sls" || echo "P9: the mutation did not apply" >"$plants/p9.err"
site_unit p9
expect p9 $? 'FAIL'

# check_suites DIR SUITE...: runs tests/check-suites.sps in the copy, as make
# check-suites does.
check_suites() {
  d=$1; shift
  (cd "$plants/$d" && "$CHEZ" --libdirs "src:tests:$srfi" --program tests/check-suites.sps "$@") \
    >"$plants/$d.out" 2>"$plants/$d.err"
}

# P10: site-unit's last datum is not its exit form: check-suites names it.
copy p10; sed -i 's/^(exit (site-exit-status runner))$/(exit 0)/' "$plants/p10/tests/site-unit.sps"
check_suites p10 tests/site-unit.sps
expect p10 $? 'tests/site-unit.sps: its last datum is (exit 0), not (exit (site-exit-status runner))'

# P11: a site suite that ends with the shared form, not its own.
copy p11; sed -i 's/^(exit (site-exit-status runner))$/(exit (suite-exit-status runner))/' "$plants/p11/tests/site-render-unit.sps"
check_suites p11 tests/site-render-unit.sps
expect p11 $? 'tests/site-render-unit.sps: its last datum is (exit (suite-exit-status runner)), not (exit (site-exit-status runner))'

# P12: a test-*.sps that ends with the site form, not the shared one.
copy p12; sed -i 's/^(exit (suite-exit-status runner))$/(exit (site-exit-status runner))/' "$plants/p12/tests/test-manifest.sps"
check_suites p12 tests/test-manifest.sps
expect p12 $? 'tests/test-manifest.sps: its last datum is (exit (site-exit-status runner)), not (exit (suite-exit-status runner))'

# P13: a site suite that imports (curl-testing) fails at import, src/ being on
# no site suite's path, as on apt's Chez it would fail at the floor.
copy p13; sed -i 's/(import (rnrs) (srfi :64) (site-testing)/(import (rnrs) (srfi :64) (site-testing) (curl-testing)/' "$plants/p13/tests/site-unit.sps"
grep -q '(curl-testing)' "$plants/p13/tests/site-unit.sps" || echo "P13: the plant did not apply" >"$plants/p13.err"
site_unit p13
expect p13 $? '(curl private counters)'

# P14: a site-exit-status that ignores an unexpected pass: test-site-testing
# fails its row, and exits 1.
copy p14; sed -i 's/(and (> pass 0) (= fail 0) (= xpass 0))/(and (> pass 0) (= fail 0))/' "$plants/p14/tests/site-testing.sls"
grep -q '(and (> pass 0) (= fail 0))$' "$plants/p14/tests/site-testing.sls" || echo "P14: the plant did not apply" >"$plants/p14.err"
(cd "$plants/p14" && "$CHEZ" --libdirs "src:tests:$srfi" --program tests/test-site-testing.sps) \
  >"$plants/p14.out" 2>"$plants/p14.err"
expect p14 $? 'FAIL an unexpected pass beside a pass: exit 1'

# copy_full DIR: the whole tree but .git and build/, with the fetched
# chez-cmark-gfm, so make runs in it and fetches nothing.
copy_full() {
  mkdir "$plants/$1"
  for e in * .gitattributes; do
    [ "$e" = build ] || cp -R "$e" "$plants/$1/"
  done
  mkdir "$plants/$1/build"
  cp -R build/akku "$plants/$1/build/akku"
}

extra_suite='#!r6rs
(import (rnrs) (srfi :64) (site-testing))
(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-extra")
(test-assert "fails" #f)
(test-end "site-extra")
'

# P15: a new site suite that fails: make check-site runs every
# tests/site-*.sps, so it fails, and never reaches tests/check-site.sps.
copy_full p15
printf '%s(exit (site-exit-status runner))\n' "$extra_suite" >"$plants/p15/tests/site-extra.sps"
make --no-print-directory -C "$plants/p15" check-site >"$plants/p15.out" 2>"$plants/p15.err"
s15=$?
if grep -Fq 'all green' "$plants/p15.out"; then echo "P15: check-site.sps ran" >>"$plants/p15.err"; s15=0; fi
expect p15 $s15 'site-exit-status: exit 1 (pass 0, fail 1, xpass 0)'

# P16: the same new suite ending with (exit 0): make check-suites names it.
copy_full p16
printf '%s(exit 0)\n' "$extra_suite" >"$plants/p16/tests/site-extra.sps"
make --no-print-directory -C "$plants/p16" check-suites >"$plants/p16.out" 2>"$plants/p16.err"
expect p16 $? 'tests/site-extra.sps: its last datum is (exit 0), not (exit (site-exit-status runner))'

echo "plants: $watched watched failing, $missed not"
[ "$missed" -eq 0 ]
