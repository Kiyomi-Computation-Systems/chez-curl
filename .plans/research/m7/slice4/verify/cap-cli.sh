#!/bin/sh
# verify/cap-cli.sh: curl's own tool, given a cookie file holding one cookie
# whose value is N bytes, against cap-server.mjs. Run in the Guix container
# from the repository's root:
#   scripts/guix-env sh .plans/research/m7/slice4/verify/cap-cli.sh < /dev/null
set -u
d=.plans/research/m7/slice4/verify
tmp=$(mktemp -d "${TMPDIR:-/tmp}/capcli.XXXXXX") || exit 1
trap 'exec 3>&-; rm -rf "$tmp"' EXIT
mkfifo "$tmp/in"
node $d/cap-server.mjs < "$tmp/in" > "$tmp/out" 2>&1 &
exec 3> "$tmp/in"
until grep -q '^port=' "$tmp/out" 2>/dev/null; do :; done
port=$(sed -n 's/^port=//p' "$tmp/out")
curl --version | head -1
for n in 100 8100 8150 8170 8180 8190 8200 100000; do
  v=$(head -c "$n" /dev/zero | tr '\0' v)
  printf '127.0.0.1\tFALSE\t/\tFALSE\t0\tnm\t%s\n' "$v" > "$tmp/jar"
  curl -s -o /dev/null -b "$tmp/jar" --max-time 3 "http://127.0.0.1:$port/?n=$n"
  echo "value=$n curl-exit=$?"
done
exec 3>&-
wait
cat "$tmp/out"
