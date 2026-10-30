#!/bin/sh
# M6 slice 1 (2026-10-30): wake.c's "after" case on Guix's 8.20.0 under
# strace, which the container lacks and the host has. Run on the host, from
# the repository's root:
#   sh .plans/research/m6/slice1/wake-strace.sh
# It builds wake in the container against the container's libcurl, into
# build/m6s1/wake-guix (its rpath in /gnu/store, which the host shares),
# starts server.mjs on the host with the container's Node, and traces
# every read, write and poll of one run of the 262,144-byte gzip case. It
# prints the trace from the first write to the wakeup's eventfd on: each
# turn's write(4) (the wakeup), read(4) = 8 (libcurl draining it), and the
# poll that then waits its full 1000 ms.
set -eu
d=.plans/research/m6/slice1
[ -f $d/wake.c ] || { echo "wake-strace.sh: run it from the repository's root" >&2; exit 2; }
command -v strace > /dev/null || { echo "wake-strace.sh: no strace on this host" >&2; exit 1; }
mkdir -p build/m6s1
node=$(scripts/guix-env sh -c 'gcc -I$(dirname $CHEZ_CURL_LIBCURL)/../include -o build/m6s1/wake-guix .plans/research/m6/slice1/wake.c $CHEZ_CURL_LIBCURL -Wl,-rpath,$(dirname $CHEZ_CURL_LIBCURL) > /dev/null 2>&1 && command -v node' < /dev/null 2>/dev/null)
case $node in /gnu/store/*) ;; *) echo "wake-strace.sh: the build failed, or node is not in the store: '$node'" >&2; exit 1 ;; esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/wakestrace.XXXXXX")
trap 'exec 3>&-; rm -rf "$tmp"' EXIT
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" > /dev/null 2>&1
mkfifo "$tmp/in"
"$node" $d/server.mjs "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/err" &
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 200 ] || { echo "no ports" >&2; exit 1; }; sleep 0.1; done
http=$(sed 's/.*"http":"\([^"]*\)".*/\1/' "$tmp/ports")
env -u http_proxy -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
  strace -tt -e trace=read,write,poll,eventfd2,rt_sigaction -o "$tmp/trace" \
  build/m6s1/wake-guix "http://$http/body?n=262144&chunk=16384&pattern=zero&gzip=1" after < /dev/null
fd=$(sed -n 's/.*eventfd2(.*) = \([0-9]*\)$/\1/p' "$tmp/trace" | head -1)
echo "the wakeup's eventfd is $fd"
awk -v fd="$fd" 'index($0, "write(" fd ",") {f=1} f' "$tmp/trace" | head -60
