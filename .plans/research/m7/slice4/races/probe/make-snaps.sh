#!/bin/sh
# build/m7s4r/probe/make-snaps.sh: the probe snapshots, build/m7s4r/snap-TREE-probe,
# from build/m7s4b/snap-TREE (TREE ci, the slice at dde5146, and main, a075629),
# with test-group and test-upload replaced by their instrumented copies and
# sigprobe.c at the root. From the repository's root.
set -eu
for tree in ci main; do
  dest=build/m7s4r/snap-$tree-probe
  mkdir -p "$dest"
  rsync -a --delete --exclude /.plans/research build/m7s4b/snap-$tree/ "$dest/"
  python3 build/m7s4r/probe/gen_group_probe.py build/m7s4b/snap-$tree/tests/test-group.sps "$dest/tests/test-group.sps"
  python3 build/m7s4r/probe/gen_upload_probe.py build/m7s4b/snap-$tree/tests/test-upload.sps "$dest/tests/test-upload.sps"
  cp build/m7s4r/probe/sigprobe.c "$dest/sigprobe.c"
  echo "snapshot $dest"
done
