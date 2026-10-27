#!/bin/sh
# The M5 plan's redirect-URL probe (2026-10-27): what CURLINFO_REDIRECT_URL
# gives, with FOLLOWLOCATION off, for each Location case server.mjs serves.
# Run from the repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/redirect-url/run.sh guix-8.20.0'
# or in Docker by docker.sh. CURL_LIB is a libcurl.so.4; CURL_INCLUDE, if
# set, the headers to compile against; NODE, node; CC, cc.
#
# On the Mac (the M5 plan, section 8), against Apple's libcurl by -lcurl:
#   NODE="$(asdf which node)" sh .plans/research/m5/redirect-url/run.sh mac
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
[ -f .plans/research/m5/redirect-url/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
lane=$1
d=.plans/research/m5/redirect-url
tmp=$(mktemp -d "${TMPDIR:-/tmp}/redirurl.XXXXXX") || exit 1
pid=
# The server exits once its stdin ends. A watchdog ends it 5 s after that
# closes, and says so: M4's runners hung on the Mac waiting with no bound.
cleanup() {
  exec 3>&-
  if [ -n "$pid" ]; then
    ( sleep 5; kill "$pid" 2>/dev/null ) > /dev/null 2>&1 &
    watchdog=$!
    wait "$pid"
    status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    [ "$status" -eq 0 ] || echo "[$lane] the server exited $status, not 0, after its stdin closed: 143 is the watchdog's kill, 5 s on"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" $inc -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
else
  "${CC:-cc}" $inc -o "$tmp/probe" "$d/probe.c" -lcurl 2>"$tmp/cc.err"
fi
[ -x "$tmp/probe" ] || { cat "$tmp/cc.err"; exit 1; }
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" < "$tmp/in" > "$tmp/port" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/port" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "no port"; exit 1; }; sleep 0.1; done
port=$(cat "$tmp/port")
base="http://127.0.0.1:$port/a/b/c"
if [ -n "${CURL_LIB:-}" ]; then
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB")"
else
  echo "[$lane] libcurl by -lcurl: $("$tmp/probe" --version 2>/dev/null || true)"
fi
echo "[$lane] base $base/NAME?q=1, port $port"
cases="rel-abs rel-path rel-dots rel-query rel-frag netpath other-host https no-path upper-scheme
ftp file javascript unknown-scheme empty blank missing padded tab space-inside utf8 latin1 ctl
del pct bad-pct userinfo frag-abs bad-ipv6 bad-port backslash two lower-name idn long-8k
long-90k long-110k s200 s201 s299 s300 s301 s303 s304 s305 s306 s307 s308 s309 s399 s400"
count=0
for c in $cases; do
  "$tmp/probe" "$base/$c?q=1" GET | sed "s/^/[$lane] $c /"
  count=$((count+1))
done
echo "[$lane] -- HEAD"
for c in rel-abs s303 s304 s307; do
  "$tmp/probe" "$base/$c?q=1" HEAD | sed "s/^/[$lane] $c /"
  count=$((count+1))
done
echo "[$lane] -- the request URL carries a fragment"
for c in rel-abs rel-frag frag-abs netpath; do
  "$tmp/probe" "$base/$c?q=1#orig" GET | sed "s/^/[$lane] $c#orig /"
  count=$((count+1))
done
echo "[$lane] -- the request URL carries credentials"
for c in rel-abs netpath other-host; do
  "$tmp/probe" "http://me:secret@127.0.0.1:$port/a/b/c/$c?q=1" GET | sed "s/^/[$lane] $c@creds /"
  count=$((count+1))
done
echo "[$lane] -- $count probes"
