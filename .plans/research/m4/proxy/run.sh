#!/bin/sh
# The M4 plan's proxy measurement, for one libcurl. Run from the
# repository's root:
#
#   CURL_LIB=PATH [CURL_INCLUDE=DIR] sh .plans/research/m4/proxy/run.sh LANE
#
# It compiles proxy-env.c against CURL_INCLUDE's headers, else the
# compiler's own, linked to CURL_LIB, a libcurl.so.4, by its path; starts
# proxies.mjs under NODE (default node); and runs each case below under
# env -i, so only the variables a case names reach the transfer. Each line
# gives the case, what the probe printed, its exit status, and how many
# requests the proxy logged during it.
#
# The origin answers 200 "origin" and the proxy 299 "proxy", and 403 to a
# CONNECT. The https cases ask the plaintext origin for TLS, so a direct
# one fails its handshake, 35, and one through the proxy fails its CONNECT,
# 56, with the proxy's log line.
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
[ -f .plans/research/m4/proxy/proxy-env.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
[ -n "${CURL_LIB:-}" ] || { echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2; exit 2; }
lane=$1
here=.plans/research/m4/proxy
tmp=$(mktemp -d "${TMPDIR:-/tmp}/proxy-research.XXXXXX") || exit 1
node_pid=
cleanup() {
  exec 3>&-
  [ -z "$node_pid" ] || wait "$node_pid"
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
"${CC:-cc}" $inc -o "$tmp/probe" "$here/proxy-env.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" \
  || { echo "[$lane] the probe did not compile"; exit 1; }
mkfifo "$tmp/in"
: > "$tmp/log"
"${NODE:-node}" "$here/proxies.mjs" "$tmp/log" < "$tmp/in" > "$tmp/announce" &
node_pid=$!
exec 3> "$tmp/in"
tries=0
until [ -s "$tmp/announce" ]; do
  tries=$((tries + 1))
  [ "$tries" -le 100 ] || { echo "[$lane] no announcement within 10 s"; exit 1; }
  sleep 0.1
done
origin=$(sed 's/.*"origin":\([0-9]*\).*/\1/' "$tmp/announce")
proxy=$(sed 's/.*"proxy":\([0-9]*\).*/\1/' "$tmp/announce")
p=http://127.0.0.1:$proxy
h=http://127.0.0.1:$origin/x
s=https://127.0.0.1:$origin/x
echo "[$lane] libcurl $(env -i "$tmp/probe" version), $(uname -s) $(uname -m)"

# run_case LABEL URL FLAG VAR=VALUE...: FLAG is - for none.
run_case() {
  label=$1 url=$2 flag=$3
  shift 3
  before=$(wc -l < "$tmp/log")
  if [ "$flag" = - ]; then
    out=$(env -i "$@" "$tmp/probe" "$url" 2>&1)
  else
    out=$(env -i "$@" "$tmp/probe" "$url" "$flag" 2>&1)
  fi
  status=$?
  after=$(wc -l < "$tmp/log")
  echo "[$lane] $label: $out; exit $status; proxy got $((after - before))"
}

run_case "http, no variable" "$h" -
run_case "http, http_proxy" "$h" - "http_proxy=$p"
run_case "http, HTTP_PROXY alone" "$h" - "HTTP_PROXY=$p"
run_case "http, all_proxy" "$h" - "all_proxy=$p"
run_case "http, ALL_PROXY" "$h" - "ALL_PROXY=$p"
run_case "http, http_proxy and no_proxy" "$h" - "http_proxy=$p" no_proxy=127.0.0.1
run_case "http, http_proxy and NO_PROXY" "$h" - "http_proxy=$p" NO_PROXY=127.0.0.1
run_case "http, http_proxy, PROXY \"\"" "$h" proxy-empty "http_proxy=$p"
run_case "http, all_proxy, PROXY \"\"" "$h" proxy-empty "all_proxy=$p"
run_case "http, http_proxy, NOPROXY \"*\"" "$h" noproxy-star "http_proxy=$p"
run_case "https, no variable" "$s" -
run_case "https, https_proxy" "$s" - "https_proxy=$p"
run_case "https, HTTPS_PROXY" "$s" - "HTTPS_PROXY=$p"
run_case "https, https_proxy, PROXY \"\"" "$s" proxy-empty "https_proxy=$p"
run_case "https, https_proxy, NOPROXY \"*\"" "$s" noproxy-star "https_proxy=$p"
echo "[$lane] the proxy's log:"
sed "s|^|[$lane]   |" "$tmp/log"
