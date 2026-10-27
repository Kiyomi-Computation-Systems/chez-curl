#!/bin/sh
# M4 slice 3's measurements, for one libcurl (the M4 plan, section 6.1). Run
# from the repository's root:
#
#   CURL_LIB=PATH [CURL_INCLUDE=DIR] sh .plans/research/m4/slice3/run.sh LANE [SET...]
#
# It compiles tls-env.c against CURL_INCLUDE's headers, else the compiler's
# own, linked to CURL_LIB, a libcurl.so.4, by its path; on macOS, with
# CURL_LIB unset, to the SDK's -lcurl, Apple's libcurl. It makes a PKI with
# tests/make-test-pki.sh, starts servers.mjs under NODE (default node), and
# runs each case under env -i: only what a case's steps set reaches the
# transfer. Each line gives the case, what the probe printed, and its exit
# status. SET is any of these, when, pkcs11 and proxy by default:
#
#   when     SSL_CERT_FILE and SSL_CERT_DIR, each set before curl_global_init,
#            after it, set before and unset after, empty, and at a missing
#            file; with the run CA or the other one as the CA file
#   pkcs11   CA file paths spelt as PKCS#11 URLs, in each case, and near
#            misses. Each but missing.pem exists as a file in the working
#            directory, a copy of the run CA, so 200 alone says a path was
#            read as a file: GnuTLS answers 77 for a malformed PKCS#11 URL,
#            as for a missing file
#   proxy    an https:// proxy, by http_proxy, https_proxy and all_proxy,
#            serving a leaf the run CA signed: the request's CA file and
#            verify against PROXY_CAINFO and the proxy's own verify. Each
#            case also prints what the proxy logged during it
#   maps     tests the native layer's path rule: maps.sps under CHEZ
#            (default scheme) on CURL_LIB as given and through a symlink in
#            a temporary directory. Linux only
#   backend  the Mac's: no CURL_SSL_BACKEND, then openssl, Apple's LibreSSL,
#            secure-transport, curl's name for SecureTransport, securetransport,
#            and nonesuch, two names curl 8.7.1 does not know, which fall to
#            its first backend; then no CURL_SSL_BACKEND with
#            OPENSSL_X509_TEA_DISABLE=1, which is said to turn Apple's
#            keychain fallback off. Each against PUBLIC_URL (default
#            https://example.com/), which the keychain trusts, and the local
#            origin, with no CA file, the run CA and the other CA as the CA
#            file. It reaches the network, so it runs only when named
#   chez     the same through chez-curl itself, ca-chez.sps under CHEZ
#            (default scheme), with no CURL_SSL_BACKEND. It reaches the
#            network, so it runs only when named
#
# On the Mac, with coreutils:
#   NODE="$(asdf which node)" sh .plans/research/m4/slice3/run.sh mac when pkcs11 proxy backend
#   NODE="$(asdf which node)" CHEZ=chez sh .plans/research/m4/slice3/run.sh mac backend chez
set -u
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [SET...]" >&2; exit 2; }
[ -f .plans/research/m4/slice3/tls-env.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
shift
[ "$#" -ge 1 ] || set -- when pkcs11 proxy
here=$PWD/.plans/research/m4/slice3
os=$(uname -s)
if [ -z "${CURL_LIB:-}" ] && [ "$os" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
case ${CURL_LIB:-} in ''|/*) ;; *) CURL_LIB=$PWD/$CURL_LIB ;; esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/slice3-research.XXXXXX") || exit 1
node_pid=
# The servers exit once their stdin ends. A watchdog ends them 5 s after it
# closes, and says so: slice 2's runner hung on the Mac waiting with no bound.
cleanup() {
  exec 3>&-
  if [ -n "$node_pid" ]; then
    ( sleep 5; kill "$node_pid" 2>/dev/null ) > /dev/null 2>&1 &
    watchdog=$!
    wait "$node_pid"
    node_status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    [ "$node_status" -eq 0 ] || echo "[$lane] the servers exited $node_status, not 0, after their stdin closed: 143 is the watchdog's kill, 5 s on"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" $inc -o "$tmp/probe" "$here/tls-env.c" "$CURL_LIB" "-Wl,-rpath,$(dirname "$CURL_LIB")" 2> "$tmp/cc.err"
else
  "${CC:-cc}" $inc -o "$tmp/probe" "$here/tls-env.c" -lcurl 2> "$tmp/cc.err"
fi || { cat "$tmp/cc.err"; echo "[$lane] the probe did not compile"; exit 1; }
mkdir "$tmp/pki" "$tmp/cadir" "$tmp/work"
sh tests/make-test-pki.sh "$tmp/pki" || { echo "[$lane] no PKI"; exit 1; }
ca=$tmp/pki/ca.pem other=$tmp/pki/other-ca.pem
cp "$ca" "$tmp/cadir/ca.pem"
ln -s ca.pem "$tmp/cadir/$("${OPENSSL:-openssl}" x509 -hash -noout -in "$ca").0"
# Every CA file path the pkcs11 set tries but missing.pem names a file in
# work/, a copy of the run CA, so 200 alone says a path was read as a file.
# macOS folds case in a name, so there PKCS11: and pkcs11: are one file.
kelvin=$(printf 'p\342\204\252cs11:')
longs=$(printf 'pkc\305\27711:')
# The sixteen ASCII cases of pkcs11:, p, k, c and s each lower or upper.
cases=
for p in p P; do for k in k K; do for c in c C; do for s in s S; do
  cases="$cases $p$k$c${s}11:"
done; done; done; done
mkdir "$tmp/work/x"
for path in $cases pkcs11:object=x pkcs11:ca.pem \
            pkcs11 pkcs1: pkcs111: " pkcs11:" "pkcs11 :" xpkcs11: x/pkcs11: \
            qkcs11: plcs11: pkds11: pkct11: pkcs21: pkcs12: "pkcs11;" \
            tpmkey: system: "$kelvin" "$longs"; do
  cp "$ca" "$tmp/work/$path"
done
mkfifo "$tmp/in"
: > "$tmp/log"
"${NODE:-node}" "$here/servers.mjs" "$tmp/pki" "$tmp/log" < "$tmp/in" > "$tmp/announce" &
node_pid=$!
exec 3> "$tmp/in"
tries=0
until [ -s "$tmp/announce" ]; do
  tries=$((tries + 1))
  [ "$tries" -le 100 ] || { echo "[$lane] no announcement within 10 s"; exit 1; }
  sleep 0.1
done
port() { sed "s/.*\"$1\":\\([0-9]*\\).*/\\1/" "$tmp/announce"; }
h=http://127.0.0.1:$(port origin)/x
s=https://127.0.0.1:$(port origintls)/x
p=https://127.0.0.1:$(port proxytls)
echo "[$lane] libcurl $(env -i "$tmp/probe" version), $os $(uname -m), $("${OPENSSL:-openssl}" version)"

# run_case LABEL URL STEP...: the probe, from the working directory work/.
run_case() {
  label=$1 url=$2
  shift 2
  out=$(cd "$tmp/work" && env -i "$tmp/probe" "$url" "$@" 2>&1)
  status=$?
  echo "[$lane] $label: $out; exit $status"
}

# proxy_case LABEL URL STEP...: run_case, then what the proxy logged during
# it, 0.5 s on, so a line the proxy writes as the probe exits lands here.
proxy_case() {
  before=$(wc -l < "$tmp/log")
  run_case "$@"
  sleep 0.5
  tail -n "+$((before + 1))" "$tmp/log" | sed "s|^|[$lane]   |"
}

for set in "$@"; do
  case $set in
    when)
      run_case "control, CA file the run CA" "$s" "ca-file:$ca"
      run_case "control, CA file the other CA" "$s" "ca-file:$other"
      run_case "control, no CA file" "$s"
      run_case "SSL_CERT_FILE the other CA before init, CA file the run CA" "$s" "before:SSL_CERT_FILE=$other" "ca-file:$ca"
      run_case "SSL_CERT_FILE the run CA before init, CA file the other CA" "$s" "before:SSL_CERT_FILE=$ca" "ca-file:$other"
      run_case "SSL_CERT_FILE the other CA after init, CA file the run CA" "$s" "after:SSL_CERT_FILE=$other" "ca-file:$ca"
      run_case "SSL_CERT_FILE the run CA after init, CA file the other CA" "$s" "after:SSL_CERT_FILE=$ca" "ca-file:$other"
      run_case "SSL_CERT_FILE the other CA before init, unset after, CA file the run CA" "$s" "before:SSL_CERT_FILE=$other" unset-after:SSL_CERT_FILE "ca-file:$ca"
      run_case "SSL_CERT_FILE the other CA before init, emptied after, CA file the run CA" "$s" "before:SSL_CERT_FILE=$other" "after:SSL_CERT_FILE=" "ca-file:$ca"
      run_case "SSL_CERT_FILE empty before init, CA file the run CA" "$s" "before:SSL_CERT_FILE=" "ca-file:$ca"
      run_case "SSL_CERT_FILE empty before init, CA file the other CA" "$s" "before:SSL_CERT_FILE=" "ca-file:$other"
      run_case "SSL_CERT_FILE a missing file before init, CA file the run CA" "$s" "before:SSL_CERT_FILE=$tmp/missing.pem" "ca-file:$ca"
      run_case "SSL_CERT_FILE a missing file before init, CA file the run CA, verify off" "$s" "before:SSL_CERT_FILE=$tmp/missing.pem" "ca-file:$ca" no-verify
      run_case "SSL_CERT_FILE the run CA before init, no CA file" "$s" "before:SSL_CERT_FILE=$ca"
      run_case "SSL_CERT_DIR the run CA's before init, CA file the other CA" "$s" "before:SSL_CERT_DIR=$tmp/cadir" "ca-file:$other"
      run_case "SSL_CERT_DIR the run CA's after init, CA file the other CA" "$s" "after:SSL_CERT_DIR=$tmp/cadir" "ca-file:$other"
      run_case "SSL_CERT_DIR the run CA's before init, unset after, CA file the other CA" "$s" "before:SSL_CERT_DIR=$tmp/cadir" unset-after:SSL_CERT_DIR "ca-file:$other"
      run_case "SSL_CERT_DIR empty before init, CA file the other CA" "$s" "before:SSL_CERT_DIR=" "ca-file:$other" ;;
    pkcs11)
      run_case "CA file \"missing.pem\", which does not exist" "$s" "ca-file:missing.pem"
      for path in $cases pkcs11:object=x pkcs11:ca.pem \
                  pkcs11 pkcs1: pkcs111: " pkcs11:" "pkcs11 :" xpkcs11: x/pkcs11: \
                  qkcs11: plcs11: pkds11: pkct11: pkcs21: pkcs12: "pkcs11;" \
                  tpmkey: system: ./pkcs11:; do
        run_case "CA file \"$path\"" "$s" "ca-file:$path"
      done
      run_case "CA file \"p<U+212A KELVIN SIGN>cs11:\"" "$s" "ca-file:$kelvin"
      run_case "CA file \"pkc<U+017F LATIN SMALL LETTER LONG S>11:\"" "$s" "ca-file:$longs" ;;
    proxy)
      proxy_case "http, http_proxy https://, no CA file" "$h" "before:http_proxy=$p"
      proxy_case "http, http_proxy https://, CA file the run CA" "$h" "before:http_proxy=$p" "ca-file:$ca"
      proxy_case "http, http_proxy https://, verify off" "$h" "before:http_proxy=$p" no-verify
      proxy_case "http, http_proxy https://, CA file the run CA, verify off" "$h" "before:http_proxy=$p" "ca-file:$ca" no-verify
      proxy_case "http, http_proxy https://, PROXY_CAINFO the run CA" "$h" "before:http_proxy=$p" "proxy-ca:$ca"
      proxy_case "http, http_proxy https://, the proxy's verify off" "$h" "before:http_proxy=$p" proxy-no-verify
      proxy_case "http, all_proxy https://, CA file the run CA" "$h" "before:all_proxy=$p" "ca-file:$ca"
      proxy_case "https, https_proxy https://, CA file the run CA" "$s" "before:https_proxy=$p" "ca-file:$ca"
      proxy_case "https, https_proxy https://, verify off" "$s" "before:https_proxy=$p" no-verify
      proxy_case "https, https_proxy https://, CA file and PROXY_CAINFO the run CA" "$s" "before:https_proxy=$p" "ca-file:$ca" "proxy-ca:$ca"
      proxy_case "http, http_proxy https://, SSL_CERT_FILE the run CA before init, no CA file" "$h" "before:http_proxy=$p" "before:SSL_CERT_FILE=$ca" ;;
    maps)
      if [ "$os" != Linux ]; then
        echo "[$lane] maps: Linux only"
      else
        ln -s "$CURL_LIB" "$tmp/libcurl.so.4"
        for given in "$CURL_LIB" "$tmp/libcurl.so.4"; do
          out=$("${CHEZ:-scheme}" --program "$here/maps.sps" "$given" 2>&1 < /dev/null)
          echo "[$lane] maps: $(printf '%s' "$out" | tr '\n' ' ')"
        done
      fi ;;
    backend)
      pub=${PUBLIC_URL:-https://example.com/}
      for backend in - openssl secure-transport securetransport nonesuch tea; do
        # run_case sets label and url, so the backend's own name is bl.
        case $backend in
          -) b= bl="no CURL_SSL_BACKEND" ;;
          tea) b=before:OPENSSL_X509_TEA_DISABLE=1 bl="no CURL_SSL_BACKEND, OPENSSL_X509_TEA_DISABLE=1" ;;
          *) b=before:CURL_SSL_BACKEND=$backend bl="CURL_SSL_BACKEND=$backend" ;;
        esac
        echo "[$lane] $bl: $(cd "$tmp/work" && env -i ${b:+"${b#before:}"} "$tmp/probe" version 2>&1)"
        # shellcheck disable=SC2086
        run_case "public, $bl, no CA file" "$pub" $b
        # shellcheck disable=SC2086
        run_case "public, $bl, CA file the run CA" "$pub" $b "ca-file:$ca"
        # shellcheck disable=SC2086
        run_case "local, $bl, CA file the run CA" "$s" $b "ca-file:$ca"
        # shellcheck disable=SC2086
        run_case "local, $bl, CA file the other CA" "$s" $b "ca-file:$other"
      done ;;
    chez)
      pub=${PUBLIC_URL:-https://example.com/}
      for row in "public, no CA file|$pub|-" "public, CA file the run CA|$pub|$ca" \
                 "local, CA file the run CA|$s|$ca" "local, CA file the other CA|$s|$other"; do
        rl=${row%%|*} rest=${row#*|}
        ru=${rest%%|*} rf=${rest#*|}
        out=$(env -u CURL_SSL_BACKEND "${CHEZ:-scheme}" --libdirs src:tests:build/scheme-libs \
                --program "$here/ca-chez.sps" "$ru" "$rf" 2>&1 < /dev/null | tr '\n' ' ')
        echo "[$lane] chez-curl, $rl: $out"
      done ;;
    *) echo "run.sh: no set $set" >&2; exit 2 ;;
  esac
done
echo "[$lane] done"
