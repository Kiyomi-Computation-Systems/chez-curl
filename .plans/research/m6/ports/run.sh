#!/bin/sh
# Runs the Chez custom-port probes in order and prints every line of each
# prefixed by its case's name.
#
#   sh .plans/research/m6/ports/run.sh [CASE...]   from the repository's root
#
# On the host (no CHEZ set) it re-runs itself inside the project's Guix
# container. Each case is bounded by `timeout`; a case that runs out
# prints HUNG under its own name.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ -z "${CHEZ:-}" ]; then
  root=$(CDPATH='' cd -- "$here/../../../.." && pwd)
  exec "$root/scripts/guix-env" sh -c \
    'cd .plans/research/m6/ports && sh run.sh "$@"' run.sh "$@" < /dev/null
fi

cd "$here" || exit 2

cases="I3 C1 C2 C3 I4 C4 C5 C6 C7 C8 C9 C10"
if [ $# -gt 0 ]; then cases="$*"; fi

echo "run.sh: started $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -srm), $(nproc) CPUs; CHEZ=$CHEZ"

tmp=$(mktemp "${TMPDIR:-/tmp}/ports.XXXXXX") || exit 2
trap 'rm -f "$tmp"' EXIT

for c in $cases; do
  f=$(printf '%s' "$c" | tr 'A-Z' 'a-z').sps
  bound=120
  start=$(date +%s%N)
  timeout -k 5 "$bound" "$CHEZ" --program "$f" > "$tmp" 2>&1
  status=$?
  end=$(date +%s%N)
  sed "s/^/$c: /" "$tmp"
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    echo "$c: HUNG: killed by timeout after $bound s"
  fi
  echo "$c: exit status $status, wall $(( (end - start) / 1000000 )) ms"
done
