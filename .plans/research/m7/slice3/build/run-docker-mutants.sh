#!/bin/sh
# Each NAME:LANE's mutant made, then test-proxy run on that Docker lane by
# lanes.sh, one after another. From the repository's root, on the host.
set -u
for pair in "$@"; do
  name=${pair%%:*}; lane=${pair#*:}
  python3 build/m7s3b/mutants.py make "$name"
  SNAP=/src/build/m7s3b/mut/$name SUITES=tests/test-proxy.sps TAG=mut-$name sh build/m7s3b/lanes.sh $lane 2>&1 | grep -E '^lane |FAIL' | cut -c1-300
done
echo "docker mutants done"
