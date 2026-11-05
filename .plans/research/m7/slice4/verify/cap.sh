#!/bin/sh
# verify/cap.sh LANE: builds cap.c against CURL_LIB's libcurl (CURL_INC its
# headers, if set), then runs it against cap-server.mjs. From the
# repository's root; in the Guix container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice4/verify/cap.sh guix-8.20.0' < /dev/null
set -u
d=.plans/research/m7/slice4/verify
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cap.XXXXXX") || exit 1
trap 'exec 3>&-; rm -rf "$tmp"' EXIT
inc=${CURL_INC:+-I$CURL_INC}
${CC:-cc} $inc -o "$tmp/cap" $d/cap.c "$CURL_LIB" || { echo "[$lane] compile failed"; exit 1; }
mkfifo "$tmp/in"
${NODE:-node} $d/cap-server.mjs < "$tmp/in" > "$tmp/out" 2>&1 &
exec 3> "$tmp/in"
until grep -q '^port=' "$tmp/out" 2>/dev/null; do :; done
port=$(sed -n 's/^port=//p' "$tmp/out")
LD_LIBRARY_PATH=$(dirname "$CURL_LIB") "$tmp/cap" "$port" 100 8100 8150 8170 8180 8190 8200 100000 | sed "s/^/[$lane] /"
exec 3>&-
wait
sed "s/^/[$lane] server /" "$tmp/out"
