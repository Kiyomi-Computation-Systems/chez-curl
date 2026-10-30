#!/bin/sh
# M6 slice 1's review: expect417.sps on the floor, 7.85.0, and Ubuntu's 8.5.0,
# in a throwaway ubuntu:24.04, the tree TREE mounted read-only. Run on the
# host, from the repository's root:
#
#   TREE=build/m6s1-review/tree sh .plans/research/m6/slice1-review/docker-417.sh
#
# TREE must hold probes/expect417.sps and probes/expect417-server.mjs, copies
# of this directory's, and build/scheme-libs (make deps). Chez is spike E1's
# threaded build, node the Guix store's, as build/m6s1/lanes.sh runs them.
set -eu
node=$(scripts/guix-env sh -c 'command -v node' < /dev/null)
root=$PWD
exec docker run --rm -v "$root:$root:ro" -v /gnu/store:/gnu/store:ro \
  -e NODE="$node" -e TREE="$root/${TREE:?}" -e CI="$root/build/e1/ci" ubuntu:24.04 sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends libcurl4t64 >/dev/null 2>&1
cd "$TREE"
for lane in floor main; do
  case $lane in
    floor) lib=$CI/curl-floor/lib/libcurl.so.4 ;;
    main) lib=$(ls /usr/lib/*-linux-gnu/libcurl.so.4) ;;
  esac
  t=$(mktemp -d /tmp/e417.XXXXXX)
  "$NODE" probes/expect417-server.mjs once > "$t/p" 2> "$t/s" &
  pid=$!
  sleep 1
  echo "== $lane $lib"
  CHEZ_CURL_LIBCURL=$lib timeout 60 "$CI/chez-threads/bin/scheme" --libdirs src:tests:build/scheme-libs \
    --program probes/expect417.sps "$(cat "$t/p")" || echo "exit $?"
  sed "s/^/server: /" "$t/s"
  kill "$pid"
done
'
