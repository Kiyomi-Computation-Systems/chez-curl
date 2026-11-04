#!/bin/sh
# M7 slice 3's measurements (2026-11-02; the M7 plan, section 6.1), on one
# libcurl, through chez-curl's engine: proxy.sps's parts against
# standin.mjs, with this run's PKI. Run from the repository's root, in the
# Guix container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/slice3/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh, or on the Mac by mac.sh. make-prototype.sh must
# have made build/m7s3/src first, on the host.
#
#   run.sh LANE [PART...]
#
# PART is one of refusals-main, urlparse, refusals, named, userinfo, ports,
# pooled, refused, tls, tlsenv, stall, twins, pk, hl, sent and wire; with
# none, all, in that order. refusals-main (proxy.sps's refusals) and
# urlparse run on main's src/, every other part on build/m7s3/src, the
# prototype. Each runs as its own Chez process, under env -i: its whole
# environment is CHEZ_CURL_LIBCURL=CURL_LIB, EXTRA_ENV when set (one
# NAME=VALUE, the Mac's CURL_SSL_BACKEND), and the variables of the
# environment it runs in. named runs once in each of item 1's environments,
# tlsenv once in each of item 5's; every other part in none. The program
# prints that environment as its first line.
#
# CURL_LIB is the libcurl chez-curl loads; CHEZ, scheme; NODE, node;
# OPENSSL, openssl (tests/make-test-pki.sh); BOUND, the seconds GNU timeout
# gives each process, 900 by default; STANDIN, the stand-in to run,
# standin.mjs by default (wire-control.sh hands it a copy); LOW_PORTS=1
# starts the stand-in with --low-ports (root alone: docker.sh sets it).
#
# VALGRIND=1 runs each part under the memory gate's Valgrind, its options
# exactly (the Makefile's test-memory, ADR-0014; GNU timeout outside it,
# never between it and Chez), with no suppression, Valgrind's log written to
# the run's temporary directory and its summary lines printed; SLOW, 10 by
# default then, multiplies every bound proxy.sps waits.
#
# It prints, first, the stand-in's self-test, then sha256 hashes of src/'s
# libraries and of the prototype's, each concatenated in sorted path order,
# and of the program and the stand-in. Every line it prints begins [LANE].
# It writes nothing outside its mktemp directory but stdout. The stand-in's
# stderr is printed once its stdin closes.
set -u
set -f
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [PART...]" >&2; exit 2; }
d=.plans/research/m7/slice3
[ -f $d/proxy.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
[ -d build/m7s3/src ] || { echo "run.sh: no build/m7s3/src: run make-prototype.sh on the host first" >&2; exit 2; }
lane=$1
shift
[ "$#" -gt 0 ] || set -- refusals-main urlparse refusals named userinfo ports pooled refused tls tlsenv stall twins pk hl sent wire
standin=${STANDIN:-$d/standin.mjs}
program=$d/proxy.sps
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7s3.XXXXXX") || exit 1
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
mkdir "$tmp/pki/cadir"
cp "$tmp/pki/ca.pem" "$tmp/pki/cadir/ca.pem"
hash=$("${OPENSSL:-openssl}" x509 -hash -noout -in "$tmp/pki/ca.pem") || { echo "[$lane] no hash for the run CA"; exit 1; }
ln -s ca.pem "$tmp/pki/cadir/$hash.0"
echo "[$lane] pki: $(ls "$tmp/pki" | tr '\n' ' ')cadir: $(ls "$tmp/pki/cadir" | tr '\n' ' ')"
mkfifo "$tmp/standin.in"
"${NODE:-node}" "$standin" "$tmp/pki" ${LOW_PORTS:+--low-ports} < "$tmp/standin.in" > "$tmp/standin.out" 2> "$tmp/standin.err" &
spid=$!
exec 3> "$tmp/standin.in"
n=0
until [ -s "$tmp/standin.out" ]; do
  n=$((n+1))
  [ $n -le 200 ] || { echo "[$lane] no announcement"; cat "$tmp/standin.err"; exit 1; }
  sleep 0.1
done
ports=$(head -1 "$tmp/standin.out")
port() { echo " $ports " | sed -n "s/.* $1=\([0-9]*\) .*/\1/p"; }
if command -v sha256sum > /dev/null 2>&1; then sum() { sha256sum "$@"; }; else sum() { shasum -a 256 "$@"; }; fi
tree() { (cd "$1" && find . -type f -name '*.sls' | LC_ALL=C sort | xargs cat) | sum | cut -d' ' -f1; }
echo "[$lane] src $(tree src) (sha256 of src/'s libraries, concatenated in sorted path order)"
echo "[$lane] prototype build/m7s3/src $(tree build/m7s3/src) (the same, for the prototype)"
echo "[$lane] program $program $(sum "$program" | cut -d' ' -f1) standin $standin $(sum "$standin" | cut -d' ' -f1)"
echo "[$lane] standin ports $ports"
echo "[$lane] uname $(uname -sm) chez ${CHEZ:-scheme} libcurl ${CURL_LIB:-discovered} -> $(readlink -f "${CURL_LIB:-/nonexistent}" 2>/dev/null || echo -) node $("${NODE:-node}" --version) EXTRA_ENV=${EXTRA_ENV:-unset} LOW_PORTS=${LOW_PORTS:-unset}"
slow=1
[ -n "${VALGRIND:-}" ] && slow=${SLOW:-10}
args="tmp=$tmp/work ca=$tmp/pki/ca.pem other=$tmp/pki/other-ca.pem cadir=$tmp/pki/cadir slow=$slow $ports"
# GNU timeout, or Homebrew coreutils' gtimeout on macOS.
tmo=$(command -v timeout || command -v gtimeout) || { echo "[$lane] no GNU timeout"; exit 1; }
chez=$(command -v "${CHEZ:-scheme}") || { echo "[$lane] no Chez at ${CHEZ:-scheme}"; exit 1; }
vg=
if [ -n "${VALGRIND:-}" ]; then vg=$(command -v valgrind) || { echo "[$lane] no valgrind"; exit 1; }; fi
pother=$(port p-other)
# sed's line buffering: -u for GNU sed, -l for macOS's.
lb=-u
sed -u q < /dev/null > /dev/null 2>&1 || lb=-l
# envargs ENV: the variables of the environment ENV, NAME=VALUE each, for
# env -i.
envargs() {
  case $1 in
    none) ;;
    no_proxy-host) echo "no_proxy=127.0.0.1" ;;
    NO_PROXY-host) echo "NO_PROXY=127.0.0.1" ;;
    no_proxy-star) echo "no_proxy=*" ;;
    proxy-vars) echo "http_proxy=http://127.0.0.1:$pother https_proxy=http://127.0.0.1:$pother" ;;
    all_proxy) echo "all_proxy=http://127.0.0.1:$pother" ;;
    proxy-vars-no_proxy-host) echo "http_proxy=http://127.0.0.1:$pother https_proxy=http://127.0.0.1:$pother no_proxy=127.0.0.1" ;;
    certfile-ca) echo "SSL_CERT_FILE=$tmp/pki/ca.pem" ;;
    certfile-other) echo "SSL_CERT_FILE=$tmp/pki/other-ca.pem" ;;
    certdir-cadir) echo "SSL_CERT_DIR=$tmp/pki/cadir" ;;
    *) echo "BAD_ENVIRONMENT=$1" ;;
  esac
}
for name in "$@"; do
  libdirs=build/m7s3/src
  part=$name
  envs=none
  case $name in
    refusals-main) libdirs=src; part=refusals ;;
    urlparse) libdirs=src ;;
    named) envs="none no_proxy-host NO_PROXY-host no_proxy-star proxy-vars all_proxy proxy-vars-no_proxy-host" ;;
    tlsenv) envs="certfile-ca certfile-other certdir-cadir" ;;
    refusals|userinfo|ports|pooled|refused|tls|stall|twins|pk|hl|sent|wire|setopts) ;;
    *) echo "[$lane] no part $name"; continue ;;
  esac
  for e in $envs; do
    echo "[$lane] part $name env $e libdirs $libdirs"
    if [ -n "$vg" ]; then
      vlog=$tmp/$name-$e.valgrind
      # The gate's options, as the Makefile's test-memory hands them, with no
      # suppression: none is allowed outside a Guix environment.
      cmd="$vg -v --command-line-only=yes --log-file=$vlog --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite"
    else
      cmd=
    fi
    start=$(date +%s)
    # shellcheck disable=SC2046,SC2086
    { env -i ${CURL_LIB:+CHEZ_CURL_LIBCURL=$CURL_LIB} ${EXTRA_ENV:+"$EXTRA_ENV"} $(envargs "$e") \
        "$tmo" "${BOUND:-900}" $cmd "$chez" --libdirs "$libdirs" --program "$program" "$part" $args env=$e < /dev/null 2>&1
      echo "$?" > "$tmp/status"; } | sed $lb "s/^/[$lane] /"
    echo "[$lane] part $name env $e exited $(cat "$tmp/status") after about $(( $(date +%s) - start )) s (124 is timeout's, 9 Valgrind's)"
    if [ -n "$vg" ]; then
      if [ -f "$vlog" ]; then
        grep -E "ERROR SUMMARY|definitely lost|indirectly lost|possibly lost|Command:|Valgrind-[0-9]|^==[0-9]+== Using Valgrind" "$vlog" | sed "s/^/[$lane] valgrind $name $e: /"
      else
        echo "[$lane] valgrind $name $e: no log $vlog"
      fi
    fi
  done
done
exit 0
