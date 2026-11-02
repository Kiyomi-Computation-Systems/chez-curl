#!/bin/sh
# M7's proxy probe (2026-11-02; the M7 plan's measurements), on one libcurl:
# probe.c, built against that libcurl, against server.mjs, with this run's
# PKI. Run from the repository's root. In the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m7/proxies/run.sh guix-8.20.0' < /dev/null
# in Docker by docker.sh; on the Mac by mac.sh. CURL_LIB is a libcurl.so.4
# to link; CURL_INCLUDE, the headers to compile against, by default the
# lane's own: CURL_LIB's ../include when it holds curl/curl.h, else the
# compiler's. On macOS, with CURL_LIB unset, Apple's libcurl by -lcurl and
# the SDK's headers. NODE, node; CC, cc; OPENSSL, openssl.
#
# Every case runs the probe under env -i: its environment is EXTRA_ENV, one
# NAME=VALUE when set (the Mac's CURL_SSL_BACKEND), and the env: steps the
# case names, which the probe sets before curl_global_init and prints whole.
# CASES, when set, is a list of glob patterns, and only the cases matching
# one run. SYSSTORE=1 (docker.sh's sysstore pass, root in a throwaway
# container) adds the run CA to the system store first, by
# update-ca-certificates, and checks openssl verifies the good leaf by the
# store's file and its directory.
#
# Every line it prints begins [LANE]; it writes nothing outside its mktemp
# directory but stdout, and, with SYSSTORE=1, the system store.
set -u
set -f
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
d=.plans/research/m7/proxies
[ -f $d/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY SSL_CERT_FILE SSL_CERT_DIR
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m7proxies.XXXXXX") || exit 1
pid=
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
    [ -s "$tmp/server.err" ] && sed "s/^/[$lane] server-stderr: /" "$tmp/server.err"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=${CURL_INCLUDE:-}
if [ -z "$inc" ] && [ -n "${CURL_LIB:-}" ] && [ -f "$(dirname "$CURL_LIB")/../include/curl/curl.h" ]; then
  inc=$(dirname "$CURL_LIB")/../include
fi
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" -Wall ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
else
  "${CC:-cc}" -Wall ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" -lcurl 2>"$tmp/cc.err"
fi
cc_status=$?
[ "$cc_status" -eq 0 ] || { echo "[$lane] the compile exited $cc_status"; sed "s/^/[$lane] cc: /" "$tmp/cc.err"; exit 1; }
grep -i 'warning' "$tmp/cc.err" | sed "s/^/[$lane] cc: /"
if [ -n "${CURL_LIB:-}" ]; then
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB" 2>/dev/null || echo "$CURL_LIB"), headers ${inc:-the compiler's}"
else
  echo "[$lane] libcurl by -lcurl, headers ${inc:-the compiler's}"
fi
echo "[$lane] node $("${NODE:-node}" --version) uname $(uname -sm) EXTRA_ENV=${EXTRA_ENV:-unset} SYSSTORE=${SYSSTORE:-unset}"
env -i ${EXTRA_ENV:+"$EXTRA_ENV"} "$tmp/probe" --version 2>&1 | sed "s/^/[$lane] /"
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" || { echo "[$lane] make-test-pki failed"; exit 1; }
for x in ca:cadir other-ca:otherdir; do
  f=${x%%:*} dir=$tmp/pki/${x#*:}
  mkdir "$dir"
  cp "$tmp/pki/$f.pem" "$dir/$f.pem"
  hash=$("${OPENSSL:-openssl}" x509 -hash -noout -in "$tmp/pki/$f.pem") || { echo "[$lane] no hash for $f"; exit 1; }
  ln -s "$f.pem" "$dir/$hash.0"
done
echo "[$lane] pki: $(ls "$tmp/pki" | tr '\n' ' ')cadir: $(ls "$tmp/pki/cadir" | tr '\n' ' ')otherdir: $(ls "$tmp/pki/otherdir" | tr '\n' ' ')"
if [ "${SYSSTORE:-}" = 1 ]; then
  cp "$tmp/pki/ca.pem" /usr/local/share/ca-certificates/m7-proxies-run-ca.crt || exit 1
  update-ca-certificates > "$tmp/uca.out" 2>&1
  echo "[$lane] sysstore: update-ca-certificates exit=$? $(tr '\n' ' ' < "$tmp/uca.out")"
  echo "[$lane] sysstore: verify good.pem by the bundle: $("${OPENSSL:-openssl}" verify -CAfile /etc/ssl/certs/ca-certificates.crt "$tmp/pki/good.pem" 2>&1 | tr '\n' ' ')"
  echo "[$lane] sysstore: verify good.pem by the directory: $("${OPENSSL:-openssl}" verify -CApath /etc/ssl/certs "$tmp/pki/good.pem" 2>&1 | tr '\n' ' ')"
fi
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" "$tmp/pki" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] server $(cat "$tmp/ports")"
port() { echo " $(cat "$tmp/ports") " | sed -n "s/.* $1=\([0-9]*\) .*/\1/p"; }
CTL=$(port ctl) ORAW=$(port o-raw) OTLS=$(port o-tls) POPEN=$(port p-open) POTHER=$(port p-other)
PBASIC=$(port p-basic) PDIGEST=$(port p-digest) PBOTH=$(port p-both) P403=$(port p-403) P502=$(port p-502)
PCLOSE=$(port p-close) PPARTIAL=$(port p-partial) TPGOOD=$(port tp-good) TPEXPIRED=$(port tp-expired)
TPWRONG=$(port tp-wrong) TPUNTRUSTED=$(port tp-untrusted) REFUSED=$(port refused)
for v in "$CTL" "$ORAW" "$OTLS" "$POPEN" "$POTHER" "$PBASIC" "$PDIGEST" "$PBOTH" "$P403" "$P502" "$PCLOSE" "$PPARTIAL" "$TPGOOD" "$TPEXPIRED" "$TPWRONG" "$TPUNTRUSTED" "$REFUSED"; do
  [ -n "$v" ] || { echo "[$lane] a port is missing"; exit 1; }
done

selected() {
  [ -z "${CASES:-}" ] && return 0
  for pat in $CASES; do
    case $1 in $pat) return 0 ;; esac
  done
  return 1
}
count=0
# c NAME URL STEP...: one case; the URL gets ?case=NAME.
c() {
  name=$1 url=$2
  shift 2
  selected "$name" || return 0
  case $name in
    *noresolve*)
      if [ "$(uname -s)" = Darwin ]; then
        echo "[$lane] case $name skipped: on macOS a lookup of nonesuch.invalid leaves loopback"
        return 0
      fi ;;
  esac
  count=$((count+1))
  { env -i ${EXTRA_ENV:+"$EXTRA_ENV"} "$tmp/probe" "$CTL" "$tmp/pki" "$name" "$url?case=$name" "$@" < /dev/null 2>&1
    echo "case $name probe-exit=$?"; } | sed "s/^/[$lane] /"
}

H=http://127.0.0.1:$ORAW/x
S=https://127.0.0.1:$OTLS/x
T="ca=@ca capath=null"
po=http://127.0.0.1:$POPEN
pother=http://127.0.0.1:$POTHER
pb=127.0.0.1:$PBASIC
pd=127.0.0.1:$PDIGEST
tg=https://127.0.0.1:$TPGOOD
# u t: sets U, the origin, and X, its steps, for a transport: a, absolute
# form to the plaintext origin; c, CONNECT to the TLS origin, with the run
# CA as its CA file (chez-curl's ca-file); t, CONNECT to the plaintext
# origin by HTTPPROXYTUNNEL.
u() {
  case $1 in
    a | h) U=$H X= ;;
    c | s) U=$S X=$T ;;
    t) U=$H X=tunnel=1 ;;
  esac
}

# ---- 1. A proxy by URL, and the environment.
for o in h s; do
  u $o
  c I1-$o-none $U $X
  c I1-$o-opt $U $X proxy=$po
  c I1-$o-opt-no_proxy-host $U $X proxy=$po env:no_proxy=127.0.0.1
  c I1-$o-opt-NO_PROXY-host $U $X proxy=$po env:NO_PROXY=127.0.0.1
  c I1-$o-opt-no_proxy-star $U $X proxy=$po 'env:no_proxy=*'
  c I1-$o-opt-no_proxy-other $U $X proxy=$po env:no_proxy=example.invalid
  c I1-$o-opt-noproxy-empty $U $X proxy=$po noproxy=
  c I1-$o-opt-noproxy-empty-no_proxy-host $U $X proxy=$po noproxy= env:no_proxy=127.0.0.1
  c I1-$o-opt-noproxy-empty-NO_PROXY-host $U $X proxy=$po noproxy= env:NO_PROXY=127.0.0.1
  c I1-$o-opt-noproxy-empty-no_proxy-star $U $X proxy=$po noproxy= 'env:no_proxy=*'
  c I1-$o-opt-noproxy-null-no_proxy-host $U $X proxy=$po noproxy=null env:no_proxy=127.0.0.1
  c I1-$o-opt-noproxy-host $U $X proxy=$po noproxy=127.0.0.1
  c I1-$o-opt-env-proxy $U $X proxy=$po env:http_proxy=$pother env:https_proxy=$pother
  c I1-$o-opt-env-all_proxy $U $X proxy=$po env:all_proxy=$pother
  c I1-$o-opt-env-proxy-no_proxy-host $U $X proxy=$po env:http_proxy=$pother env:https_proxy=$pother env:no_proxy=127.0.0.1
  c I1-$o-env-proxy $U $X env:http_proxy=$pother env:https_proxy=$pother
  c I1-$o-env-proxy-noproxy-empty-no_proxy-host $U $X noproxy= env:http_proxy=$pother env:https_proxy=$pother env:no_proxy=127.0.0.1
  c I1-$o-optempty-env-proxy $U $X proxy= env:http_proxy=$pother env:https_proxy=$pother
  c I1-$o-form-noscheme $U $X proxy=127.0.0.1:$POPEN
  c I1-$o-form-HTTP $U $X proxy=HTTP://127.0.0.1:$POPEN
  c I1-$o-form-https $U $X proxy=$tg proxy-ca=@ca proxy-capath=null
  c I1-$o-form-https-plainport $U $X proxy=https://127.0.0.1:$POPEN proxy-ca=@ca proxy-capath=null
  c I1-$o-form-http-tlsport $U $X proxy=http://127.0.0.1:$TPGOOD
  c I1-$o-form-noscheme-tlsport $U $X proxy=127.0.0.1:$TPGOOD
  c I1-$o-form-foo $U $X proxy=foo://127.0.0.1:$POPEN
  c I1-$o-form-ftp $U $X proxy=ftp://127.0.0.1:$POPEN
  c I1-$o-form-noport $U $X proxy=http://127.0.0.1
  c I1-$o-form-path $U $X "proxy=http://127.0.0.1:$POPEN/a/path?q=1"
done

# ---- 2. Proxy credentials.
for t in a c; do
  u $t
  for px in basic:$PBASIC digest:$PDIGEST both:$PBOTH open:$POPEN; do
    for au in unset basic digest any; do
      A=
      [ $au = unset ] || A=proxyauth=$au
      c I2-$t-${px%%:*}-$au $U $X proxy=http://alice:s3cret@127.0.0.1:${px#*:} $A
    done
  done
  c I2-$t-src-url-pct $U $X proxy=http://al%40ice:p%3Ass%25w@$pb
  c I2-$t-src-url-utf8pct $U $X proxy=http://%C3%A9l%C3%A8ve:p%C3%A4ss@$pb
  c I2-$t-src-url-utf8raw $U $X 'proxy=http://\xc3\xa9l\xc3\xa8ve:p\xc3\xa4ss@'$pb
  c I2-$t-src-url-useronly $U $X proxy=http://alice@$pb
  c I2-$t-src-url-emptypass $U $X proxy=http://alice:@$pb
  c I2-$t-src-noscheme $U $X proxy=alice:s3cret@$pb
  c I2-$t-src-opt-plain $U $X proxy=http://$pb proxy-user=alice proxy-pass=s3cret
  c I2-$t-src-opt-raw $U $X proxy=http://$pb proxy-user=al@ice proxy-pass=p:ss%w
  c I2-$t-src-opt-pct $U $X proxy=http://$pb proxy-user=al%40ice proxy-pass=p%3Ass%25w
  c I2-$t-src-opt-utf8 $U $X proxy=http://$pb 'proxy-user=\xc3\xa9l\xc3\xa8ve' 'proxy-pass=p\xc3\xa4ss'
  c I2-$t-src-userpwd-plain $U $X proxy=http://$pb proxy-userpwd=alice:s3cret
  c I2-$t-src-userpwd-raw $U $X proxy=http://$pb proxy-userpwd=al@ice:p:ss%w
  c I2-$t-src-userpwd-pct $U $X proxy=http://$pb proxy-userpwd=al%40ice:p%3Ass%25w
  c I2-$t-src-url-wrong-opt-right $U $X proxy=http://alice:wrong@$pb proxy-user=alice proxy-pass=s3cret
  c I2-$t-src-opt-right-url-wrong $U $X proxy-user=alice proxy-pass=s3cret proxy=http://alice:wrong@$pb
  c I2-$t-src-url-right-opt-wrong $U $X proxy=http://alice:s3cret@$pb proxy-user=alice proxy-pass=wrong
  c I2-$t-src-url-wrong-userpwd-right $U $X proxy=http://alice:wrong@$pb proxy-userpwd=alice:s3cret
  c I2-$t-src-url-right-userpwd-wrong $U $X proxy=http://alice:s3cret@$pb proxy-userpwd=alice:wrong
  c I2-$t-src-user-only-opt $U $X proxy=http://$pb proxy-user=alice
  c I2-$t-dsrc-url-pct $U $X proxy=http://al%40ice:p%3Ass%25w@$pd proxyauth=digest
  c I2-$t-dsrc-url-utf8pct $U $X proxy=http://%C3%A9l%C3%A8ve:p%C3%A4ss@$pd proxyauth=digest
  c I2-$t-dsrc-opt-utf8 $U $X proxy=http://$pd 'proxy-user=\xc3\xa9l\xc3\xa8ve' 'proxy-pass=p\xc3\xa4ss' proxyauth=digest
  c I2-$t-dsrc-userpwd-raw $U $X proxy=http://$pd proxy-userpwd=al@ice:p:ss%w proxyauth=digest
  c I2-$t-wrong-basic $U $X proxy=http://alice:wrong@$pb
  c I2-$t-wrong-user-basic $U $X proxy=http://mallory:s3cret@$pb
  c I2-$t-wrong-digest $U $X proxy=http://alice:wrong@$pd proxyauth=digest
  c I2-$t-wrong-any-both $U $X proxy=http://alice:wrong@127.0.0.1:$PBOTH proxyauth=any
  c I2-$t-wrong-any-digest $U $X proxy=http://alice:wrong@$pd proxyauth=any
done

# ---- 3. A caller's headers and the proxy. The caller's Proxy-Authorization
# carries alice:s3cret, which p-basic takes; libcurl's own, where given, is
# al@ice's, which it takes too.
PA='header=Proxy-Authorization: Basic YWxpY2U6czNjcmV0'
XC='header=X-Caller: m7'
for t in a c t; do
  u $t
  c I3-$t-open-hdrs $U $X proxy=$po "$PA" "$XC"
  c I3-$t-basic-hdrs $U $X proxy=http://$pb "$PA" "$XC"
  c I3-$t-basic-hdrs-creds $U $X proxy=http://$pb proxy-userpwd=al@ice:p:ss%w "$PA" "$XC"
  c I3-$t-open-unified $U $X proxy=$po headeropt=unified "$PA" "$XC"
  c I3-$t-open-proxyheader $U $X proxy=$po 'proxyheader=X-Proxy-Only: 1' "$XC"
done

# ---- 4. An https:// proxy's TLS.
for t in a c; do
  u $t
  for lf in good:$TPGOOD expired:$TPEXPIRED wrong:$TPWRONG untrusted:$TPUNTRUSTED; do
    for v in 11 01 10 00; do
      vp=${v%?} vh=${v#?}
      [ "$vh" = 1 ] && vh=2
      c I4-$t-${lf%%:*}-v$v $U $X proxy=https://127.0.0.1:${lf#*:} proxy-ca=@ca proxy-capath=null proxy-verifypeer=$vp proxy-verifyhost=$vh
    done
  done
  for ca in ca other null default; do
    for cp in null default cadir; do
      case $ca in default) S1= ;; null) S1=proxy-ca=null ;; *) S1=proxy-ca=@$ca ;; esac
      case $cp in default) S2= ;; null) S2=proxy-capath=null ;; *) S2=proxy-capath=@$cp ;; esac
      c I4-$t-ca-$ca-capath-$cp $U $X proxy=$tg $S1 $S2
    done
  done
done
c I4-c-sep-both-set $S $T proxy=$tg proxy-ca=@ca proxy-capath=null
c I4-c-sep-origin-ca-only $S $T proxy=$tg
c I4-a-sep-origin-ca-only $H $T proxy=$tg
c I4-c-sep-origin-noverify $S verifypeer=0 verifyhost=0 proxy=$tg
c I4-c-sep-proxy-ca-only $S ca=@other capath=null proxy=$tg proxy-ca=@ca proxy-capath=null
c I4-c-sep-proxy-noverify $S ca=@other capath=null proxy=https://127.0.0.1:$TPUNTRUSTED proxy-verifypeer=0 proxy-verifyhost=0
c I4-a-env-certfile-other-proxyca-ca $H proxy=$tg proxy-ca=@ca proxy-capath=null env:SSL_CERT_FILE=@other
c I4-a-env-certfile-ca-proxyca-other $H proxy=$tg proxy-ca=@other proxy-capath=null env:SSL_CERT_FILE=@ca
c I4-a-env-certfile-ca-proxyca-default $H proxy=$tg env:SSL_CERT_FILE=@ca
c I4-a-env-certfile-ca-proxyca-null $H proxy=$tg proxy-ca=null proxy-capath=null env:SSL_CERT_FILE=@ca
c I4-a-env-certdir-cadir-proxyca-other $H proxy=$tg proxy-ca=@other proxy-capath=null env:SSL_CERT_DIR=@cadir
c I4-a-env-certdir-cadir-proxyca-null $H proxy=$tg proxy-ca=null proxy-capath=null env:SSL_CERT_DIR=@cadir
c I4-o-ca-other-capath-default $S ca=@other
c I4-o-ca-other-capath-null $S ca=@other capath=null
c I4-o-ca-default-capath-default $S
c I4-o-ca-null-capath-null $S ca=null capath=null

# ---- 5. Proxy failures.
for t in a c t; do
  u $t
  c I5-$t-refused $U $X proxy=http://127.0.0.1:$REFUSED
  c I5-$t-noresolve $U $X proxy=http://nonesuch.invalid:3128
  c I5-$t-403 $U $X proxy=http://127.0.0.1:$P403
  c I5-$t-407 $U $X proxy=http://$pb
  c I5-$t-502 $U $X proxy=http://127.0.0.1:$P502
  c I5-$t-close $U $X proxy=http://127.0.0.1:$PCLOSE
  c I5-$t-partial $U $X proxy=http://127.0.0.1:$PPARTIAL
done
c I5-c-https-refused $S $T proxy=https://127.0.0.1:$REFUSED proxy-ca=@ca proxy-capath=null

echo "[$lane] -- $count cases run"
exit 0
