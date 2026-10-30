#!/bin/sh
# M6 slice 1 (2026-10-30): which libcurl call reads a lost wakeup back, on
# Guix's 8.20.0. wake-marked.c is wake.c with a mark written to stderr
# around each call of the turn, so strace places each read of the wakeup's
# eventfd between two marks. Run on the host, which has strace, from the
# repository's root:
#   sh .plans/research/m6/slice1/wake-marked.sh
# It builds wake-marked in the container against the container's libcurl,
# into build/m6s1/ (its rpath in /gnu/store, which the host shares), starts
# server.mjs on the host with the container's Node, and traces the after
# case, a wakeup made between curl_easy_pause and curl_multi_perform, and
# the before-poll control, a wakeup made between the perform and the poll.
# For each it prints the wakeup's fd, then the marks, the wakeup's writes
# and reads, and the polls, from its first wakeup on.
set -eu
d=.plans/research/m6/slice1
[ -f $d/wake-marked.c ] || { echo "wake-marked.sh: run it from the repository's root" >&2; exit 2; }
command -v strace > /dev/null || { echo "wake-marked.sh: no strace on this host" >&2; exit 1; }
mkdir -p build/m6s1
node=$(scripts/guix-env sh -c 'gcc -I$(dirname $CHEZ_CURL_LIBCURL)/../include -o build/m6s1/wake-marked .plans/research/m6/slice1/wake-marked.c $CHEZ_CURL_LIBCURL -Wl,-rpath,$(dirname $CHEZ_CURL_LIBCURL) > /dev/null 2>&1 && command -v node' < /dev/null 2>/dev/null)
case $node in /gnu/store/*) ;; *) echo "wake-marked.sh: the build failed, or node is not in the store: '$node'" >&2; exit 1 ;; esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/wakemarked.XXXXXX")
trap 'exec 3>&-; rm -rf "$tmp"' EXIT
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" > /dev/null 2>&1
mkfifo "$tmp/in"
"$node" $d/server.mjs "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/err" &
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 200 ] || { echo "no ports" >&2; exit 1; }; sleep 0.1; done
http=$(sed 's/.*"http":"\([^"]*\)".*/\1/' "$tmp/ports")
for where in after before-poll; do
  env -u http_proxy -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    strace -tt -e trace=read,write,poll,eventfd2 -o "$tmp/trace" \
    build/m6s1/wake-marked "http://$http/body?n=262144&chunk=16384&pattern=zero&gzip=1" "$where" \
    < /dev/null 2> /dev/null
  fd=$(sed -n 's/.*eventfd2(.*) = \([0-9]*\)$/\1/p' "$tmp/trace" | head -1)
  echo "== where=$where, the wakeup's eventfd is $fd"
  grep -E "write\(2, \"M-|write\($fd, \"|read\($fd, (\"\\\\1|0x)|poll\(" "$tmp/trace" \
    | sed -E 's/write\(2, "(M-[a-z-]+).*/\1/' \
    | awk -v fd="$fd" 'index($0, "write(" fd ", \"\\1") {f=1} f' | head -24
done
