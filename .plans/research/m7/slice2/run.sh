#!/bin/sh
# M7 slice 2's measurements (2026-11-02; the M7 plan, section 5.1), on one
# libcurl, through chez-curl's engine: auth.sps's parts against
# standin.mjs, with this run's PKI. Run from the repository's root, in the
# Guix container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice2/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh. make-prototype.sh must have made build/m7s2/src
# first, on the host.
#
#   run.sh LANE [PART...]
#
# PART is one of refusals-main, refusals, schemes, wire, streams, empty,
# bytes, bytestrace, rounds, pooled, twins, hops and origin; with none, all, in that
# order. Each runs as its own Chez process, against one stand-in:
# refusals-main (auth.sps's refusals) and origin on main's src/, every other
# on build/m7s2/src, the prototype. CURL_LIB is the libcurl chez-curl
# loads; CHEZ, scheme; NODE, node; OPENSSL, openssl (tests/make-test-pki.sh);
# PROGRAM, the program in this directory, auth.sps by default, or
# maxredirs.sps, whose one part is maxredirs, on the prototype;
# BOUND, the seconds GNU timeout gives each part, 900 by default; STANDIN,
# the stand-in to run, standin.mjs by default (wire-control.sh hands it a
# copy).
#
# VALGRIND=1 runs each part under the memory gate's Valgrind, its options
# exactly (the Makefile's test-memory, ADR-0014; GNU timeout outside it,
# never between it and Chez), Valgrind's log written to the run's
# temporary directory and its summary lines printed; SLOW, 10 by default
# then, multiplies every bound auth.sps waits.
#
# It prints, first, the stand-in's self-test, then sha256 hashes of src/'s
# libraries and of the prototype's, each concatenated in sorted path order,
# and of the program and the stand-in. It unsets every proxy variable,
# SSL_CERT_FILE and SSL_CERT_DIR. Every line it prints begins [LANE]. It
# writes nothing outside its mktemp directory but stdout. The stand-in's
# stderr is printed once its stdin closes.
set -u
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [PART...]" >&2; exit 2; }
d=.plans/research/m7/slice2
[ -f $d/auth.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
[ -d build/m7s2/src ] || { echo "run.sh: no build/m7s2/src: run make-prototype.sh on the host first" >&2; exit 2; }
lane=$1
shift
[ "$#" -gt 0 ] || set -- refusals-main refusals schemes wire streams empty bytes bytestrace rounds pooled twins hops origin
standin=${STANDIN:-$d/standin.mjs}
program=$d/${PROGRAM:-auth.sps}
[ -f "$program" ] || { echo "run.sh: no program $program" >&2; exit 2; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7s2.XXXXXX") || exit 1
spid=
cleanup() {
  exec 3>&-
  if [ -n "$spid" ]; then
    ( sleep 5; kill "$spid" 2>/dev/null ) > /dev/null 2>&1 &
    watchdog=$!
    wait "$spid"
    status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    [ "$status" -eq 0 ] || echo "[$lane] the stand-in exited $status, not 0, after its stdin closed: 143 is the watchdog's kill, 5 s on"
    [ -s "$tmp/standin.err" ] && sed "s/^/[$lane] standin-stderr: /" "$tmp/standin.err"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
{ "${NODE:-node}" "$standin" --selftest; echo "selftest exit=$?"; } 2>&1 | sed "s/^/[$lane] standin /"
mkdir "$tmp/pki" "$tmp/work"
sh tests/make-test-pki.sh "$tmp/pki" > "$tmp/pki.out" 2>&1 || { echo "[$lane] make-test-pki failed"; sed "s/^/[$lane] pki: /" "$tmp/pki.out"; exit 1; }
mkfifo "$tmp/standin.in"
"${NODE:-node}" "$standin" "$tmp/pki" < "$tmp/standin.in" > "$tmp/standin.out" 2> "$tmp/standin.err" &
spid=$!
exec 3> "$tmp/standin.in"
n=0
until [ -s "$tmp/standin.out" ]; do
  n=$((n+1))
  [ $n -le 200 ] || { echo "[$lane] no announcement"; cat "$tmp/standin.err"; exit 1; }
  sleep 0.1
done
port() { sed "s/.*\"$1\":\"\([0-9]*\)\".*/\1/" "$tmp/standin.out"; }
if command -v sha256sum > /dev/null 2>&1; then sum() { sha256sum "$@"; }; else sum() { shasum -a 256 "$@"; }; fi
tree() { (cd "$1" && find . -type f -name '*.sls' | LC_ALL=C sort | xargs cat) | sum | cut -d' ' -f1; }
echo "[$lane] src $(tree src) (sha256 of src/'s libraries, concatenated in sorted path order)"
echo "[$lane] prototype build/m7s2/src $(tree build/m7s2/src) (the same, for the prototype)"
echo "[$lane] program $program $(sum "$program" | cut -d' ' -f1) standin $standin $(sum "$standin" | cut -d' ' -f1)"
echo "[$lane] standin ports $(cat "$tmp/standin.out")"
echo "[$lane] uname $(uname -sm) chez ${CHEZ:-scheme} libcurl ${CURL_LIB:-discovered} -> $(readlink -f "${CURL_LIB:-/nonexistent}" 2>/dev/null || echo -) node $("${NODE:-node}" --version)"
slow=1
[ -n "${VALGRIND:-}" ] && slow=${SLOW:-10}
args="tmp=$tmp/work ca=$tmp/pki/ca.pem slow=$slow"
for k in http httpb https h2 ctl; do args="$args $k=$(port $k)"; done
# GNU timeout, or Homebrew coreutils' gtimeout on macOS.
tmo=$(command -v timeout || command -v gtimeout) || { echo "[$lane] no GNU timeout"; exit 1; }
for name in "$@"; do
  libdirs=build/m7s2/src
  part=$name
  case $name in
    refusals-main) libdirs=src; part=refusals ;;
    origin) libdirs=src ;;
    refusals|schemes|wire|streams|empty|bytes|bytestrace|rounds|pooled|twins|hops|maxredirs) ;;
    *) echo "[$lane] no part $name"; continue ;;
  esac
  echo "[$lane] part $name libdirs $libdirs"
  if [ -n "${VALGRIND:-}" ]; then
    vlog=$tmp/$name.valgrind
    # The gate's options, as the Makefile's test-memory hands them, with no
    # suppression: none is allowed outside a Guix environment.
    cmd="valgrind -v --command-line-only=yes --log-file=$vlog --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite"
  else
    cmd=
  fi
  start=$(date +%s)
  # shellcheck disable=SC2086
  { env ${CURL_LIB:+CHEZ_CURL_LIBCURL=$CURL_LIB} "$tmo" "${BOUND:-900}" $cmd \
      "${CHEZ:-scheme}" --libdirs "$libdirs" --program "$program" "$part" $args < /dev/null 2>&1
    echo "$?" > "$tmp/status"; } | sed -u "s/^/[$lane] /"
  echo "[$lane] part $name exited $(cat "$tmp/status") after about $(( $(date +%s) - start )) s (124 is timeout's, 9 Valgrind's)"
  if [ -n "${VALGRIND:-}" ]; then
    if [ -f "$vlog" ]; then
      grep -E "ERROR SUMMARY|definitely lost|indirectly lost|possibly lost|Command:|Valgrind-[0-9]|^==[0-9]+== Using Valgrind" "$vlog" | sed "s/^/[$lane] valgrind $name: /"
    else
      echo "[$lane] valgrind $name: no log $vlog"
    fi
  fi
done
exit 0
