#!/bin/sh
# The curl bug report's reproduction (2026-10-31): curl's own command-line
# tool posts 4 MiB over HTTP/2 (h2c, prior knowledge) to early-3xx-server.mjs,
# which answers each STATUS after 64 KiB of the body, then reads the rest.
# Run from the repository's root, with CURL the curl to test and NODE node:
#   scripts/guix-env sh .plans/research/m6/slice3/verify/early-3xx-cli.sh < /dev/null
#   CURL=build/verify/c823/lane1/curl-current/bin/curl ... (8.23.0, in Docker)
set -u
d=.plans/research/m6/slice3/verify
curl=${CURL:-curl}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/early3xx.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
head -c 4194304 /dev/zero > "$tmp/body"
"$curl" --version | head -1
for status in 303 307 413 200; do
  mkfifo "$tmp/in.$status"
  "${NODE:-node}" $d/early-3xx-server.mjs "$status" 65536 < "$tmp/in.$status" > "$tmp/port.$status" 2> "$tmp/server.$status" &
  pid=$!
  exec 3> "$tmp/in.$status"
  n=0; until [ -s "$tmp/port.$status" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "no port"; exit 1; }; sleep 0.1; done
  port=$(cat "$tmp/port.$status")
  out=$("$curl" -sS --http2-prior-knowledge -X POST --data-binary @"$tmp/body" -m 5 -o "$tmp/resp" \
          -w 'http_code=%{http_code} size_download=%{size_download} time_total=%{time_total}' \
          "http://127.0.0.1:$port/" 2> "$tmp/err.$status")
  echo "status=$status curl_exit=$? $out stderr=$(tr '\n' ' ' < "$tmp/err.$status")"
  "$curl" -sS -v --http2-prior-knowledge -X POST --data-binary @"$tmp/body" -m 5 -o /dev/null \
    "http://127.0.0.1:$port/" 2>&1 | grep -E 'stop sending|abort upload|timed out|HTTP/2 [0-9]' | sed "s/^/  status=$status verbose: /"
  exec 3>&-
  wait "$pid"
  sed "s/^/  status=$status server: /" "$tmp/server.$status"
done
