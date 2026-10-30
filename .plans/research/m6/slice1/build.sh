#!/bin/sh
# M6 slice 1's prototype (2026-10-30): build/m6s1/src, made afresh from the
# working tree's src/ and proto.patch, by GNU patch on the host (the Guix
# container has diffutils but no patch). Run on the host, from the
# repository's root, with src/ at main (46c1f3c when the logs were made):
#   sh .plans/research/m6/slice1/build.sh
# It writes build/m6s1/patch.sha256, the patch's sum, and
# build/m6s1/src.sha256, every file's, which run.sh checks before it runs.
set -eu
d=.plans/research/m6/slice1
[ -f $d/proto.patch ] || { echo "build.sh: run it from the repository's root" >&2; exit 2; }
rm -rf build/m6s1/src
mkdir -p build/m6s1
cp -R src build/m6s1/src
patch -s -p2 -d build/m6s1/src < $d/proto.patch
(cd build/m6s1/src && find . -type f | LC_ALL=C sort | xargs sha256sum) > build/m6s1/src.sha256
sha256sum $d/proto.patch | cut -d' ' -f1 > build/m6s1/patch.sha256
echo "build.sh: build/m6s1/src from src/ and proto.patch $(cat build/m6s1/patch.sha256), $(patch --version | head -1)"
