#!/bin/sh
# A snapshot of the working tree for the Docker lanes, into build/m7s3b/SNAP
# (snap by default): every file but build/, .git and .plans/research.
set -eu
dest=build/m7s3b/${1:-snap}
mkdir -p "$dest"
rsync -a --delete --exclude /build --exclude /.git --exclude /.plans/research ./ "$dest/"
echo "snapshot $dest"
