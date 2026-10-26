#!/bin/sh
# M4 slice 1's measurements, for one libcurl (the M4 plan, section 4.1). Run
# from the repository's root:
#
#   CURL_LIB=PATH [CURL_INCLUDE=DIR] sh .plans/research/m4/slice1/run.sh LANE
#
# It compiles probe.c against CURL_INCLUDE's headers, else the compiler's
# own, linked to CURL_LIB, a libcurl.so.4, by its path; starts capture.mjs,
# and the test origin with TLS material made for this run; and runs:
#
#   bodies       each method with a body of 0, 1, 1048576 and 1048577 bytes,
#                and with none, against capture.mjs, which answers Expect at
#                once on /continue and never on /silent;
#   suppression  the headers that remove, or replace, libcurl's own;
#   times        the six *_TIME_T infos, and the request and header sizes, on
#                the origin's scenarios, and the code each failing one gives.
#
# NODE is node, OPENSSL openssl, CC cc, unless set. The capture's port is
# printed as PORT, the origin's as ORIGIN.
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
[ -f .plans/research/m4/slice1/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
[ -n "${CURL_LIB:-}" ] || { echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2; exit 2; }
lane=$1
here=.plans/research/m4/slice1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/slice1-research.XXXXXX") || exit 1
pids=
cleanup() {
  exec 3>&- 4>&-
  for p in $pids; do wait "$p"; done
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
"${CC:-cc}" $inc -o "$tmp/probe" "$here/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" \
  2> "$tmp/cc.err" || { cat "$tmp/cc.err"; echo "[$lane] the probe did not compile"; exit 1; }
mkdir "$tmp/pki"
OPENSSL="${OPENSSL:-openssl}" sh tests/make-test-pki.sh "$tmp/pki" || { echo "[$lane] no PKI"; exit 1; }
mkfifo "$tmp/capture.in" "$tmp/origin.in"
"${NODE:-node}" "$here/capture.mjs" < "$tmp/capture.in" > "$tmp/capture.port" &
pids="$pids $!"
exec 3> "$tmp/capture.in"
"${NODE:-node}" tests/origin.mjs --pki "$tmp/pki" < "$tmp/origin.in" > "$tmp/origin.json" &
pids="$pids $!"
exec 4> "$tmp/origin.in"
tries=0
until [ -s "$tmp/capture.port" ] && [ -s "$tmp/origin.json" ]; do
  tries=$((tries + 1))
  [ "$tries" -le 100 ] || { echo "[$lane] no announcement within 10 s"; exit 1; }
  sleep 0.1
done
port=$(cat "$tmp/capture.port")
face() { sed "s/.*\"$1\":\"127\\.0\\.0\\.1:\\([0-9]*\\)\".*/\\1/" "$tmp/origin.json"; }
http=$(face http) raw=$(face raw) https=$(face https) rawtls=$(face raw-tls)
expired=$(face https-expired) wronghost=$(face https-wrong-host) untrusted=$(face https-untrusted)
ca=$tmp/pki/ca.pem
echo "[$lane] libcurl $("$tmp/probe" version), $(uname -s) $(uname -m)"

hide() { sed -e "s/127\\.0\\.0\\.1:$port/127.0.0.1:PORT/g" -e "s/:$http\\//:ORIGIN\\//g" \
  -e "s/:$raw\\//:ORIGIN\\//g" -e "s/:$https\\//:ORIGIN\\//g" -e "s/:$rawtls\\//:ORIGIN\\//g" \
  -e "s/^/[$lane] /"; }
body() { label=$1; shift; printf '%s: ' "$label" | hide | tr -d '\n'; "$tmp/probe" body "$port" "$@" | hide | sed "s/^\\[$lane\\] //"; }
timed() { label=$1; shift; printf '%s: ' "$label" | hide | tr -d '\n'; "$tmp/probe" time "$@" | hide | sed "s/^\\[$lane\\] //"; }

echo "[$lane] -- bodies, Expect answered at once"
for m in POST PUT PATCH DELETE; do
  for s in 0 1 1048576 1048577; do body "$m $s" continue "$m" "$s"; done
done
for m in PUT PATCH DELETE; do body "$m none" continue "$m" none; done
echo "[$lane] -- bodies, Expect never answered"
for m in POST PUT; do body "$m 1048577 silent" silent "$m" 1048577; done
echo "[$lane] -- suppression"
body "POST 1, Content-Type:" continue POST 1 "Content-Type:"
body "PUT 1, Content-Type:" continue PUT 1 "Content-Type:"
body "DELETE 1, Content-Type:" continue DELETE 1 "Content-Type:"
body "POST 0, Content-Type:" continue POST 0 "Content-Type:"
body "POST 1048577, Expect:" silent POST 1048577 "Expect:"
body "PUT 1048577, Content-Type: and Expect:" silent PUT 1048577 "Content-Type:" "Expect:"
body "POST 1, Content-Type: text/plain" continue POST 1 "Content-Type: text/plain"
body "POST 1, content-type: text/plain" continue POST 1 "content-type: text/plain"
body "POST 1, Content-Type;" continue POST 1 "Content-Type;"
body "POST 1, Expect: 100-continue" continue POST 1 "Expect: 100-continue"
body "POST 1, Expect: 100-continue, silent" silent POST 1 "Expect: 100-continue"
body "POST 1048577, Expect: 100-continue and Expect:" silent POST 1048577 "Expect: 100-continue" "Expect:"
body "POST 1, Content-Type: and Content-Type: text/plain" continue POST 1 "Content-Type:" "Content-Type: text/plain"
body "POST 1, Content-Type: text/plain and Content-Type:" continue POST 1 "Content-Type: text/plain" "Content-Type:"

echo "[$lane] -- times, in microseconds"
timed "http /status/200" "http://127.0.0.1:$http/status/200" 0 5000 -
timed "https /status/200" "https://127.0.0.1:$https/status/200" 0 5000 "$ca"
timed "raw pause-mid-body 300" "http://127.0.0.1:$raw/raw/pause-mid-body?ms=300" 0 5000 -
timed "raw-tls pause-mid-body 300" "https://127.0.0.1:$rawtls/raw/pause-mid-body?ms=300" 0 5000 "$ca"
timed "raw pause-mid-body 300, connect 100" "http://127.0.0.1:$raw/raw/pause-mid-body?ms=300" 100 0 -
timed "refused" "http://127.0.0.1:1/" 0 5000 -
timed "raw stall-before-head, timeout 300" "http://127.0.0.1:$raw/raw/stall-before-head" 0 300 -
timed "raw stall-before-head, connect 300, timeout 1500" "http://127.0.0.1:$raw/raw/stall-before-head" 300 1500 -
timed "raw stall-after-head, connect 300, timeout 1500" "http://127.0.0.1:$raw/raw/stall-after-head" 300 1500 -
timed "raw close-before-response" "http://127.0.0.1:$raw/raw/close-before-response" 0 5000 -
timed "raw short-body" "http://127.0.0.1:$raw/raw/short-body" 0 5000 -
timed "raw reset-mid-body" "http://127.0.0.1:$raw/raw/reset-mid-body" 0 5000 -
timed "TLS to raw, connect 300, timeout 3000" "https://127.0.0.1:$raw/" 300 3000 "$ca"
timed "TLS to raw, timeout 300" "https://127.0.0.1:$raw/" 0 300 "$ca"
timed "unresolvable host" "http://chez-curl-probe.invalid/" 0 10000 -
timed "expired" "https://127.0.0.1:$expired/status/200" 0 5000 "$ca"
timed "wrong host" "https://127.0.0.1:$wronghost/status/200" 0 5000 "$ca"
timed "untrusted" "https://127.0.0.1:$untrusted/status/200" 0 5000 "$ca"
timed "missing CA file" "https://127.0.0.1:$https/status/200" 0 5000 "$tmp/pki/none.pem"
printf 'http_proxy refused: ' | hide | tr -d '\n'
http_proxy=http://127.0.0.1:1 "$tmp/probe" time "http://127.0.0.1:$http/status/200" 0 5000 - | hide | sed "s/^\\[$lane\\] //"
printf 'http_proxy unresolvable: ' | hide | tr -d '\n'
http_proxy=http://chez-curl-probe.invalid:1 "$tmp/probe" time "http://127.0.0.1:$http/status/200" 0 10000 - | hide | sed "s/^\\[$lane\\] //"
echo "[$lane] done"
