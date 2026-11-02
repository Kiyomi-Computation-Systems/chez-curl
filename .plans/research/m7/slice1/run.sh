#!/bin/sh
# M7 slice 1's measurements (2026-11-02; the M7 plan, section 4.1), on one
# libcurl, through chez-curl's engine: version.sps's parts, against
# tests/origin.mjs --pki and standin.mjs, with this run's PKI. Run from the
# repository's root, in the Guix container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice1/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh. make-prototype.sh must have made build/m7s1/src
# first, on the host.
#
#   run.sh LANE [PART...]
#
# PART is versions, envproxy, named, twins or sharing; with none, all five,
# in that order. Each runs as its own Chez process, against the same two
# servers: named on build/m7s1/src, the prototype; every other on main's
# src/. envproxy runs with http_proxy and https_proxy naming the origin's
# http face; every other part with no proxy variable. CURL_LIB is the
# libcurl chez-curl loads; CHEZ, scheme; NODE, node; OPENSSL, openssl
# (tests/make-test-pki.sh); BOUND, the seconds GNU timeout gives each part,
# 900 by default.
#
# It prints, first, sha256 hashes of src/'s libraries and of the
# prototype's, each concatenated in sorted path order, and of the program
# and the stand-in. It unsets every proxy variable, SSL_CERT_FILE and
# SSL_CERT_DIR. Every line it prints begins [LANE]. It writes nothing outside
# its mktemp directory but stdout. Each server's stderr is printed once its
# stdin closes.
set -u
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [PART...]" >&2; exit 2; }
d=.plans/research/m7/slice1
[ -f $d/version.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
[ -d build/m7s1/src ] || { echo "run.sh: no build/m7s1/src: run make-prototype.sh on the host first" >&2; exit 2; }
lane=$1
shift
[ "$#" -gt 0 ] || set -- versions envproxy named twins sharing
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7s1.XXXXXX") || exit 1
opid=
spid=
stop_server() {
  # stop_server PID NAME: waits up to 5 s for it, its stdin closed.
  ( sleep 5; kill "$1" 2>/dev/null ) > /dev/null 2>&1 &
  watchdog=$!
  wait "$1"
  status=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  [ "$status" -eq 0 ] || echo "[$lane] $2 exited $status, not 0, after its stdin closed: 143 is the watchdog's kill, 5 s on"
  [ -s "$tmp/$2.err" ] && sed "s/^/[$lane] $2-stderr: /" "$tmp/$2.err"
}
cleanup() {
  exec 3>&- 4>&-
  [ -n "$opid" ] && stop_server "$opid" origin
  [ -n "$spid" ] && stop_server "$spid" standin
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir "$tmp/pki" "$tmp/work"
sh tests/make-test-pki.sh "$tmp/pki" > "$tmp/pki.out" 2>&1 || { echo "[$lane] make-test-pki failed"; sed "s/^/[$lane] pki: /" "$tmp/pki.out"; exit 1; }
mkfifo "$tmp/origin.in" "$tmp/standin.in"
"${NODE:-node}" tests/origin.mjs --pki "$tmp/pki" < "$tmp/origin.in" > "$tmp/origin.out" 2> "$tmp/origin.err" &
opid=$!
exec 3> "$tmp/origin.in"
"${NODE:-node}" $d/standin.mjs "$tmp/pki" < "$tmp/standin.in" > "$tmp/standin.out" 2> "$tmp/standin.err" &
spid=$!
exec 4> "$tmp/standin.in"
n=0
until [ -s "$tmp/origin.out" ] && [ -s "$tmp/standin.out" ]; do
  n=$((n+1))
  [ $n -le 200 ] || { echo "[$lane] no announcement"; cat "$tmp/origin.err" "$tmp/standin.err"; exit 1; }
  sleep 0.1
done
face() { sed "s/.*\"$1\":\"\([^\"]*\)\".*/\1/" "$2"; }
if command -v sha256sum > /dev/null 2>&1; then sum() { sha256sum "$@"; }; else sum() { shasum -a 256 "$@"; }; fi
tree() { (cd "$1" && find . -type f -name '*.sls' | LC_ALL=C sort | xargs cat) | sum | cut -d' ' -f1; }
echo "[$lane] src $(tree src) (sha256 of src/'s libraries, concatenated in sorted path order)"
echo "[$lane] prototype build/m7s1/src $(tree build/m7s1/src) (the same, for the prototype)"
echo "[$lane] program $d/version.sps $(sum $d/version.sps | cut -d' ' -f1) standin $(sum $d/standin.mjs | cut -d' ' -f1) origin $(sum tests/origin.mjs | cut -d' ' -f1)"
echo "[$lane] origin $(cat "$tmp/origin.out")"
echo "[$lane] standin $(cat "$tmp/standin.out")"
echo "[$lane] uname $(uname -sm) chez ${CHEZ:-scheme} libcurl ${CURL_LIB:-discovered} node $("${NODE:-node}" --version)"
args="tmp=$tmp/work ca=$tmp/pki/ca.pem"
for k in http https h2c h2; do args="$args $k=$(face $k "$tmp/origin.out")"; done
for k in alt1 alt1h alt2 both icy ctl closed; do args="$args $k=$(face $k "$tmp/standin.out")"; done
http_face=$(face http "$tmp/origin.out")
# GNU timeout, or Homebrew coreutils' gtimeout on macOS.
tmo=$(command -v timeout || command -v gtimeout) || { echo "[$lane] no GNU timeout"; exit 1; }
for part in "$@"; do
  libdirs=src
  envs=
  case $part in
    versions|twins|sharing) ;;
    envproxy) envs="http_proxy=http://$http_face https_proxy=http://$http_face" ;;
    named) libdirs=build/m7s1/src ;;
    *) echo "[$lane] no part $part"; continue ;;
  esac
  echo "[$lane] part $part libdirs $libdirs env ${envs:-none}"
  # shellcheck disable=SC2086
  set -- env ${CURL_LIB:+CHEZ_CURL_LIBCURL=$CURL_LIB} $envs "$tmo" "${BOUND:-900}" \
    "${CHEZ:-scheme}" --libdirs "$libdirs" --program $d/version.sps "$part" $args
  start=$(date +%s)
  { "$@" < /dev/null 2>&1; echo "$?" > "$tmp/status"; } | sed -u "s/^/[$lane] /"
  echo "[$lane] part $part exited $(cat "$tmp/status") after about $(( $(date +%s) - start )) s (124 is timeout's)"
done
exit 0
