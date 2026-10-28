#!/bin/sh
# The SIGINT child, v2, against the record-after-section mutant: the drive's
# set! of its token moved out of the submit's critical section. Run on the
# host, from the repository root:
#
#   sh build/m5s1-builder/kept/run-mutant.sh
#
# It makes the mutant in a copy of the tree, build/m5s1-builder/mut/kept-record,
# and logs to witness/v2-record-after-section.log, its first line the command.
set -eu
R=$(pwd)
K=$R/build/m5s1-builder/kept
D=$R/build/m5s1-builder/mut/kept-record
rm -rf "$D"; mkdir -p "$D"
rsync -a --exclude .git --exclude build "$R/" "$D/"
python3 - "$D/src/http-client/private/drive.sls" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
old = "(critical-section\n                                  (set! token (curl-submit engine request)))"
assert t.count(old) == 1
open(p, "w").write(t.replace(old, "(set! token (critical-section (curl-submit engine request)))"))
PY
mkdir -p "$D/build/m5s1-builder/kept"
cp -r "$K/witness" "$D/build/m5s1-builder/kept/"
cmd='make deps >/dev/null 2>&1; sh build/m5s1-builder/kept/witness/child-loop.sh 24 20 build/m5s1-builder/kept/witness/escape-child-v2.sps; sh build/m5s1-builder/kept/witness/child-loop.sh 0 10 build/m5s1-builder/kept/witness/escape-child-v2.sps'
{ printf '$ (in %s, drive.sls mutated as above) scripts/guix-env sh -c %s\n' "$D" "'$cmd'"
  (cd "$D" && scripts/guix-env sh -c "$cmd" < /dev/null 2>&1)
  echo "exit $?"; } > "$K/witness/v2-record-after-section.log"
rm -rf "$D"
