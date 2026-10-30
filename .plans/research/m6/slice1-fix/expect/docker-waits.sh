#!/bin/sh
# waits.sps on 7.85.0, Ubuntu's 8.5.0 (OpenSSL and GnuTLS) and 8.23.0, in a
# throwaway ubuntu:24.04, the repository mounted read-only. From the root.
set -eu
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
root=$PWD
exec docker run --rm -v "$root:$root:ro" -v /gnu/store:/gnu/store:ro \
  -e NODE="$node" -e ROOT="$root" -e CI="$root/build/e1/ci" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends libcurl4t64 libcurl3t64-gnutls >/dev/null 2>&1
cd "$ROOT"
arch=$(uname -m)-linux-gnu
for lib in $CI/curl-floor/lib/libcurl.so.4 /usr/lib/$arch/libcurl.so.4 /usr/lib/$arch/libcurl-gnutls.so.4 $ROOT/build/verify/c823/lane1/curl-current/lib/libcurl.so.4; do
  t=$(mktemp -d /tmp/w.XXXXXX)
  "$NODE" .plans/research/m6/slice1-fix/expect/waits-server.mjs > "$t/p" 2> "$t/s" &
  pid=$!
  sleep 1
  echo "== $lib"
  CHEZ_CURL_LIBCURL=$lib timeout 120 "$CI/chez-threads/bin/scheme" --libdirs src:tests:build/scheme-libs \
    --program .plans/research/m6/slice1-fix/expect/waits.sps "$(cat "$t/p")" || echo "exit $?"
  kill "$pid"
done
'
