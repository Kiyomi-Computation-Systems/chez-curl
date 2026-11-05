#!/bin/sh
# M7 slice 4's measurements (2026-11-03; the M7 plan, section 6.3), on one
# libcurl, through chez-curl's engine: jar.sps's parts against standin.mjs,
# with this run's PKI. Run from the repository's root, in the Guix
# container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice4/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh, or on the Mac by mac.sh. make-prototype.sh must
# have made build/m7s4/src first, on the host, and, for the order part on
# Linux, the file watch build/m7s4/fswatch.so (all.sh builds it).
#
#   run.sh LANE [PART...]
#
# PART is one of twins-main, lifetime, abandon-leave, abandon-free, setopt,
# order, load, readout, cost, host, h2, rounds, twins, hsts, ipv6, walk and
# lifetime-plant; with none, all but lifetime-plant, in that order.
# twins-main runs main.sps on main's src/; every other part jar.sps on the
# prototype, or on PROTO when it is set (a planted copy, for the controls).
# Each runs as its own Chez process, under env -i: its whole environment is
# CHEZ_CURL_LIBCURL=CURL_LIB, EXTRA_ENV when set (one NAME=VALUE, the Mac's
# CURL_SSL_BACKEND), and, for the order part on Linux, LD_PRELOAD the file
# watch and FSWATCH_LOG its log.
#
# CURL_LIB is the libcurl chez-curl loads; CHEZ, scheme; NODE, node;
# OPENSSL, openssl (tests/make-test-pki.sh); BOUND, the seconds GNU timeout
# gives each process, 900 by default; STANDIN, the stand-in to run,
# standin.mjs by default; FSWATCH_SO, the file watch, build/m7s4/fswatch.so
# by default.
#
# VALGRIND=1 runs each part under the memory gate's Valgrind, its options
# exactly (the Makefile's test-memory, ADR-0014; GNU timeout outside it,
# never between it and Chez), with no suppression, Valgrind's log written to
# the run's temporary directory and its summary lines printed; SLOW, 10 by
# default then, multiplies every bound jar.sps waits.
#
# It prints, first, the stand-in's self-test, the loopback's IPv6 state and
# tests/origin.mjs's announcement, then sha256 hashes of src/'s libraries
# and of the prototype's, each concatenated in sorted path order, and of
# the programs, the stand-in, the file watch's source and prototype.diff.
# Every line it prints begins [LANE]. It writes nothing outside its mktemp
# directory but stdout.
set -u
set -f
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [PART...]" >&2; exit 2; }
d=.plans/research/m7/slice4
[ -f $d/jar.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
proto=${PROTO:-build/m7s4/src}
[ -d "$proto" ] || { echo "run.sh: no $proto: run make-prototype.sh on the host first" >&2; exit 2; }
lane=$1
shift
[ "$#" -gt 0 ] || set -- twins-main lifetime abandon-leave abandon-free setopt order load readout cost host h2 rounds twins hsts ipv6 walk
standin=${STANDIN:-$d/standin.mjs}
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7s4.XXXXXX") || exit 1
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
echo "[$lane] ipv6 lo disable_ipv6=$(cat /proc/sys/net/ipv6/conf/lo/disable_ipv6 2>/dev/null || echo none) if_inet6=[$(cat /proc/net/if_inet6 2>/dev/null | tr -s ' ' | tr '\n' ';')]"
# tests/origin.mjs's announcement: it listens, prints one line, and exits as
# its stdin ends, two seconds on.
( sleep 2 ) | "${NODE:-node}" tests/origin.mjs 2>&1 | head -1 | sed "s/^/[$lane] origin.mjs announces: /"
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
ports=$(head -1 "$tmp/standin.out")
if command -v sha256sum > /dev/null 2>&1; then sum() { sha256sum "$@"; }; else sum() { shasum -a 256 "$@"; }; fi
tree() { (cd "$1" && find . -type f -name '*.sls' | LC_ALL=C sort | xargs cat) | sum | cut -d' ' -f1; }
echo "[$lane] src $(tree src) (sha256 of src/'s libraries, concatenated in sorted path order)"
echo "[$lane] prototype $proto $(tree "$proto") (the same, for the prototype)"
for f in $d/jar.sps $d/main.sps $standin $d/fswatch.c $d/prototype.diff $d/prototype.py; do
  echo "[$lane] sha256 $f $(sum "$f" | cut -d' ' -f1)"
done
echo "[$lane] standin ports $ports"
echo "[$lane] uname $(uname -sm) chez ${CHEZ:-scheme} libcurl ${CURL_LIB:-discovered} -> $(readlink -f "${CURL_LIB:-/nonexistent}" 2>/dev/null || echo -) node $("${NODE:-node}" --version) EXTRA_ENV=${EXTRA_ENV:-unset}"
slow=1
[ -n "${VALGRIND:-}" ] && slow=${SLOW:-10}
tmo=$(command -v timeout || command -v gtimeout) || { echo "[$lane] no GNU timeout"; exit 1; }
chez=$(command -v "${CHEZ:-scheme}") || { echo "[$lane] no Chez at ${CHEZ:-scheme}"; exit 1; }
vg=
if [ -n "${VALGRIND:-}" ]; then vg=$(command -v valgrind) || { echo "[$lane] no valgrind"; exit 1; }; fi
so=${FSWATCH_SO:-build/m7s4/fswatch.so}
lb=-u
sed -u q < /dev/null > /dev/null 2>&1 || lb=-l
for name in "$@"; do
  libdirs=$proto
  program=$d/jar.sps
  preload=
  watch=none
  case $name in
    twins-main) libdirs=src; program=$d/main.sps ;;
    order)
      if [ "$(uname -s)" = Linux ]; then
        if [ -f "$so" ]; then preload=$(cd "$(dirname "$so")" && pwd)/$(basename "$so"); watch=$tmp/fswatch.log; : > "$watch"
        else echo "[$lane] no file watch $so: the order part runs unwatched"; fi
      fi ;;
    lifetime|abandon-leave|abandon-free|setopt|load|readout|cost|host|h2|rounds|twins|hsts|ipv6|walk|lifetime-plant) ;;
    *) echo "[$lane] no part $name"; continue ;;
  esac
  args="lane=$lane tmp=$tmp/work ca=$tmp/pki/ca.pem slow=$slow fswatch=$watch $ports"
  echo "[$lane] part $name libdirs $libdirs program $program preload ${preload:-none}"
  if [ -n "$vg" ]; then
    vlog=$tmp/$name.valgrind
    # The gate's options, as the Makefile's test-memory hands them, with no
    # suppression: none is allowed outside a Guix environment.
    cmd="$vg -v --command-line-only=yes --log-file=$vlog --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite"
  else
    cmd=
  fi
  start=$(date +%s)
  # shellcheck disable=SC2046,SC2086
  { env -i ${CURL_LIB:+CHEZ_CURL_LIBCURL=$CURL_LIB} ${EXTRA_ENV:+"$EXTRA_ENV"} ${preload:+LD_PRELOAD=$preload} ${preload:+FSWATCH_LOG=$watch} \
      "$tmo" "${BOUND:-900}" $cmd "$chez" --libdirs "$libdirs" --program "$program" "$name" $args < /dev/null 2>&1
    echo "$?" > "$tmp/status"; } | sed $lb "s/^/[$lane] /"
  echo "[$lane] part $name exited $(cat "$tmp/status") after about $(( $(date +%s) - start )) s (124 is timeout's, 9 Valgrind's)"
  if [ -n "$preload" ]; then
    echo "[$lane] fswatch $name: $(wc -l < "$watch") calls logged, $(grep -c ' ""$' "$watch") with an empty path"
  fi
  if [ -n "$vg" ]; then
    if [ -f "$vlog" ]; then
      grep -E "ERROR SUMMARY|definitely lost|indirectly lost|possibly lost|Command:|Valgrind-[0-9]|^==[0-9]+== Using Valgrind|Invalid|uninitialised|Mismatched|by 0x|at 0x" "$vlog" | head -400 | sed "s/^/[$lane] valgrind $name: /"
    else
      echo "[$lane] valgrind $name: no log $vlog"
    fi
  fi
done
exit 0
