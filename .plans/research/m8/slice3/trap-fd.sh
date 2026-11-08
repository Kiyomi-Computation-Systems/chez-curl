#!/bin/sh
# The trap run-probe.sh met (results/trap-fd-{1,2}.log): a server whose stdin
# is a FIFO this script holds open on fd 3 ends when the script closes fd 3,
# unless a child started after the exec inherited fd 3. Two cats stand in for
# the origin and the stand-in. Prints, for each case, whether A had ended
# 1 s after fd 3 closed, while B still ran.
set -u
tmp=$(mktemp -d "${TMPDIR:-/tmp}/trapfd.XXXXXX") || exit 1
for how in inherited closed; do
  rm -f "$tmp/a" "$tmp/b"; mkfifo "$tmp/a" "$tmp/b"
  cat "$tmp/a" > /dev/null & a=$!
  exec 3> "$tmp/a"
  if [ "$how" = inherited ]; then cat "$tmp/b" > /dev/null & b=$!; else cat "$tmp/b" > /dev/null 3>&- & b=$!; fi
  exec 4> "$tmp/b"
  exec 3>&-
  sleep 1
  if kill -0 "$a" 2>/dev/null; then echo "$how: A still runs 1 s after fd 3 closed"; else echo "$how: A ended when fd 3 closed"; fi
  exec 4>&-
  wait "$a" "$b"
  echo "$how: A and B ended once fd 4 closed too"
done
rm -f "$tmp/a" "$tmp/b"; rmdir "$tmp"
