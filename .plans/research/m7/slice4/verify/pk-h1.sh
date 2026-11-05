#!/bin/sh
# verify/pk-h1.sh ORIGIN N: curl's own tool, --http2-prior-knowledge, N
# times to ORIGIN's http face, an HTTP/1.1 server, and the count of each
# exit code. ORIGIN is tests/origin.mjs, or main's copy of it, to compare
# the slice's 'data' listener on that face against none. NODE and CURL name
# the tools, node and curl by default. The origin is killed at the end:
# the Mac's Node does not exit when its FIFO stdin closes. From the
# repository's root, in the Guix container:
#   scripts/guix-env sh .plans/research/m7/slice4/verify/pk-h1.sh tests/origin.mjs 200 < /dev/null
# on the Mac:
#   NODE="$(asdf which node)" CURL=/usr/bin/curl sh .plans/research/m7/slice4/verify/pk-h1.sh tests/origin.mjs 200
set -u
origin=$1
n=$2
node=${NODE:-node}
curl=${CURL:-curl}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pkh1.XXXXXX") || exit 1
pid=
trap 'exec 3>&-; [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT
mkfifo "$tmp/in"
"$node" "$origin" < "$tmp/in" > "$tmp/out" 2> "$tmp/err" &
pid=$!
exec 3> "$tmp/in"
until [ -s "$tmp/out" ]; do :; done
port=$(sed -n 's/.*"http":"127\.0\.0\.1:\([0-9]*\)".*/\1/p' "$tmp/out")
[ -n "$port" ] || { echo "no http port in: $(cat "$tmp/out")"; exit 1; }
echo "origin $origin, node $("$node" --version), $("$curl" --version | head -1)"
i=0
: > "$tmp/codes"
while [ "$i" -lt "$n" ]; do
  "$curl" -s -o /dev/null --http2-prior-knowledge --max-time 5 "http://127.0.0.1:$port/status/200"
  echo $? >> "$tmp/codes"
  i=$((i + 1))
done
sort -n "$tmp/codes" | uniq -c | awk -v n="$n" '{print "exit " $2 ": " $1 " of " n}'
