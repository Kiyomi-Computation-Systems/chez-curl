#!/bin/sh
# M4 slice 4's measurements, for one libcurl (the M4 plan, section 7.1). Run
# from the repository's root:
#
#   CURL_LIB=PATH [CURL_INCLUDE=DIR] [VALGRIND=PATH] sh .plans/research/m4/slice4/run.sh LANE [SET...]
#
# It compiles hatch.c against CURL_INCLUDE's headers, else the compiler's
# own, linked to CURL_LIB, a libcurl.so.4, by its path; on macOS, with
# CURL_LIB unset, to the SDK's -lcurl, Apple's libcurl. It makes a PKI with
# tests/make-test-pki.sh, starts servers.mjs under NODE (default node), and
# runs each case under env -i, CURL_SSL_BACKEND alone passed through when
# it is set, for the Mac's MultiSSL libcurl. With VALGRIND set, each case runs under that
# Valgrind with the memory gate's options (the Makefile's test-memory), its
# suppression in a Guix environment, and the line gives the exit status, the
# ERROR SUMMARY, and the first error and definite leak its log names. SET is
# any of these, blob and list by default:
#
#   blob   the blob options the hatch takes, each against the TLS origin with
#          the run CA as the CA file: ISSUERCERT_BLOB at the run CA, the right
#          issuer, and at the other CA, a wrong one; SSLCERT_BLOB at the good
#          leaf with SSLKEY_BLOB at its key, at the leaf alone, and at bytes
#          that are no certificate. Each passed with CURL_BLOB_COPY and freed
#          as soon as setopt returns; the right issuer and the leaf with its
#          key again with CURL_BLOB_NOCOPY, the control
#   list   the string lists: RESOLVE and CONNECT_TO, each sending a name that
#          does not resolve to capture; HTTP200ALIASES at "ICY 200 OK"
#          against icy. Each freed after curl_easy_cleanup; RESOLVE and
#          HTTP200ALIASES again freed as soon as setopt returns, a control,
#          and RESOLVE never freed, another
#   candidates
#          what the options ADR-0009's last amendment left unreviewed do, each
#          plainly, under env -i with only the variables a case names, its
#          stdin a file or /dev/null; each line gives what the servers logged
#          during the case: COOKIEFILE at "-"; RESUME_FROM beside a body;
#          COOKIEJAR at "-"; UNIX_SOCKET_PATH and CONNECT_TO beside
#          http_proxy; PROXYHEADER and HEADEROPT through a proxy; CONNECT_ONLY;
#          TIMECONDITION, TRANSFER_ENCODING, DOH_URL, NETRC and VERBOSE
#   review what the slice's twin review claimed from curl's source alone:
#          TRANSFERTEXT beside CRLF on a body holding LF; USERPWD, USERNAME,
#          PASSWORD and NETRC against a URL's own credentials; HSTS turning
#          http:// to https://; ABSTRACT_UNIX_SOCKET beside http_proxy (Linux
#          alone); DOH_URL's lookups through https_proxy with PROXY "", the
#          request's proxy #f; a file option at /dev/stdin; SSLENGINE and
#          SSLENGINE_DEFAULT's answers; NOPROGRESS 0
#   chez   RESOLVE through chez-curl's own hatch, resolve-chez.sps under CHEZ
#          (default scheme), CURL_LIB as CHEZ_CURL_LIBCURL: whether one
#          request's entry reaches a later request on the same engine
#
# On the Mac, with coreutils, Apple's libcurl with each backend:
#   NODE="$(asdf which node)" sh .plans/research/m4/slice4/run.sh mac blob list candidates
#   CURL_SSL_BACKEND=secure-transport NODE="$(asdf which node)" sh .plans/research/m4/slice4/run.sh mac-st blob list candidates
set -u
[ "$#" -ge 1 ] || { echo "usage: run.sh LANE [SET...]" >&2; exit 2; }
[ -f .plans/research/m4/slice4/hatch.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
lane=$1
shift
[ "$#" -ge 1 ] || set -- blob list
here=$PWD/.plans/research/m4/slice4
os=$(uname -s)
if [ -z "${CURL_LIB:-}" ] && [ "$os" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
case ${CURL_LIB:-} in ''|/*) ;; *) CURL_LIB=$PWD/$CURL_LIB ;; esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/slice4-research.XXXXXX") || exit 1
node_pid=
# The servers exit once their stdin ends. A watchdog ends them 5 s after it
# closes, and says so: the Mac's Node has not exited on its own (slice 3).
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
  "${CC:-cc}" -g $inc -o "$tmp/probe" "$here/hatch.c" "$CURL_LIB" "-Wl,-rpath,$(dirname "$CURL_LIB")" 2> "$tmp/cc.err"
else
  "${CC:-cc}" -g $inc -o "$tmp/probe" "$here/hatch.c" -lcurl 2> "$tmp/cc.err"
fi || { cat "$tmp/cc.err"; echo "[$lane] the probe did not compile"; exit 1; }
mkdir "$tmp/pki"
sh tests/make-test-pki.sh "$tmp/pki" > /dev/null || { echo "[$lane] no PKI"; exit 1; }
ca=$tmp/pki/ca.pem other=$tmp/pki/other-ca.pem leaf=$tmp/pki/good.pem key=$tmp/pki/good.key
printf 'no certificate here\n' > "$tmp/garbage.pem"
vg=
if [ -n "${VALGRIND:-}" ]; then
  vg=$(command -v "$VALGRIND") || { echo "[$lane] no Valgrind at $VALGRIND"; exit 1; }
  supp=
  [ -z "${GUIX_ENVIRONMENT:-}" ] || supp=--suppressions=$PWD/tests/guix-glibc-locpath.supp
fi
mkfifo "$tmp/in"
: > "$tmp/log"
abstract=
[ "$os" != Linux ] || abstract=chez-curl-slice4-$$
# shellcheck disable=SC2086
"${NODE:-node}" "$here/servers.mjs" "$tmp/pki" "$tmp/log" "$tmp/capture.sock" $abstract < "$tmp/in" > "$tmp/announce" &
node_pid=$!
exec 3> "$tmp/in"
tries=0
until [ -s "$tmp/announce" ]; do
  tries=$((tries + 1))
  [ "$tries" -le 100 ] || { echo "[$lane] no announcement within 10 s"; exit 1; }
  sleep 0.1
done
port() { sed "s/.*\"$1\":\\([0-9]*\\).*/\\1/" "$tmp/announce"; }
cport=$(port capture) iport=$(port icy) tport=$(port tls)
s=https://127.0.0.1:$tport/x
# keep: CURL_SSL_BACKEND=VALUE when the runner has it set, else nothing.
keep=${CURL_SSL_BACKEND:+CURL_SSL_BACKEND=$CURL_SSL_BACKEND}
echo "[$lane] libcurl $(env -i $keep "$tmp/probe" version), $os $(uname -m)${keep:+, $keep}${vg:+, $("$vg" --version)}"

# run_case LABEL URL STEP...: the probe, its output on one line, and its
# exit status; under Valgrind, what its log says.
n=0
run_case() {
  label=$1 url=$2
  shift 2
  n=$((n + 1))
  if [ -n "$vg" ]; then
    vlog=$tmp/case-$n.valgrind
    # shellcheck disable=SC2086
    env -i $keep "$vg" -v --command-line-only=yes "--log-file=$vlog" --error-exitcode=9 \
      --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $supp \
      "$tmp/probe" "$url" "$@" > "$tmp/out" 2>&1
    status=$?
    summary=$(grep -m1 'ERROR SUMMARY' "$vlog" | sed 's/^==[0-9]*== //')
    first=$(grep -m1 -E 'Invalid (read|write)|uninitialised|definitely lost in' "$vlog" | sed 's/^==[0-9]*== //')
    echo "[$lane] $label: $(tr '\n' ' ' < "$tmp/out")| valgrind exit $status, $summary${first:+ | first: $first}"
  else
    env -i $keep "$tmp/probe" "$url" "$@" > "$tmp/out" 2>&1
    status=$?
    echo "[$lane] $label: $(tr '\n' ' ' < "$tmp/out")| exit $status"
  fi
}

# env_case LABEL ENV STDIN URL STEP...: the probe, plainly, under env -i
# with ENV, NAME=VALUE pairs split at spaces, or - for none, its stdin
# STDIN; then what the servers logged during it, 0.5 s on.
env_case() {
  label=$1 envs=$2 input=$3 url=$4
  shift 4
  [ "$envs" != - ] || envs=
  before=$(wc -l < "$tmp/log")
  # shellcheck disable=SC2086
  (cd "$tmp" && env -i $keep $envs "$tmp/probe" "$url" "$@" < "$input" > "$tmp/out" 2>&1)
  status=$?
  sleep 0.5
  echo "[$lane] $label: $(tr '\n' ' ' < "$tmp/out")| exit $status"
  tail -n "+$((before + 1))" "$tmp/log" | sed "s|^|[$lane]   |"
}

for set in "$@"; do
  case $set in
    blob)
      run_case "control, no blob" "$s" "ca:$ca"
      run_case "ISSUERCERT_BLOB the run CA, copied" "$s" "ca:$ca" "blob:ISSUERCERT_BLOB=$ca"
      run_case "ISSUERCERT_BLOB the other CA, copied" "$s" "ca:$ca" "blob:ISSUERCERT_BLOB=$other"
      run_case "ISSUERCERT_BLOB the run CA, not copied, freed after setopt" "$s" "ca:$ca" "blob-nocopy:ISSUERCERT_BLOB=$ca"
      run_case "SSLCERT_BLOB the leaf, SSLKEY_BLOB its key, copied" "$s" "ca:$ca" "blob:SSLCERT_BLOB=$leaf" "blob:SSLKEY_BLOB=$key"
      run_case "SSLCERT_BLOB the leaf alone, copied" "$s" "ca:$ca" "blob:SSLCERT_BLOB=$leaf"
      run_case "SSLCERT_BLOB no certificate, copied" "$s" "ca:$ca" "blob:SSLCERT_BLOB=$tmp/garbage.pem"
      run_case "SSLCERT_BLOB the leaf, SSLKEY_BLOB its key, not copied, freed after setopt" "$s" "ca:$ca" "blob-nocopy:SSLCERT_BLOB=$leaf" "blob-nocopy:SSLKEY_BLOB=$key" ;;
    list)
      run_case "control, hatch.test unresolved" "http://hatch.test:$cport/x"
      run_case "RESOLVE hatch.test to 127.0.0.1" "http://hatch.test:$cport/x" "list:RESOLVE=hatch.test:$cport:127.0.0.1"
      run_case "RESOLVE hatch.test to 127.0.0.1, freed after setopt" "http://hatch.test:$cport/x" "list-early:RESOLVE=hatch.test:$cport:127.0.0.1"
      run_case "RESOLVE hatch.test to 127.0.0.1, never freed" "http://hatch.test:$cport/x" "list-leak:RESOLVE=hatch.test:$cport:127.0.0.1"
      run_case "CONNECT_TO any host to capture" "http://hatch.test:1/x" "list:CONNECT_TO=::127.0.0.1:$cport"
      run_case "control, icy without an alias" "http://127.0.0.1:$iport/x"
      run_case "HTTP200ALIASES ICY 200 OK" "http://127.0.0.1:$iport/x" "list:HTTP200ALIASES=ICY 200 OK"
      run_case "HTTP200ALIASES ICY 200 OK, freed after setopt" "http://127.0.0.1:$iport/x" "list-early:HTTP200ALIASES=ICY 200 OK" ;;
    candidates)
      h=http://127.0.0.1:$cport/x u=http://hatch.test:1/x p=http_proxy=http://127.0.0.1:$cport
      printf '127.0.0.1\tFALSE\t/\tFALSE\t0\tfrom\tstdin\n' > "$tmp/cookies.txt"
      printf 'STDIN-BYTES' > "$tmp/stdin.txt"
      mkdir "$tmp/home"
      printf 'machine 127.0.0.1 login netrc-user password netrc-pass\n' > "$tmp/home/.netrc"
      env_case "COOKIEFILE -, stdin a cookie file" - "$tmp/cookies.txt" "$h" "str:COOKIEFILE=-"
      env_case "COOKIEFILE -, stdin empty" - /dev/null "$h" "str:COOKIEFILE=-"
      env_case "COOKIEFILE the cookie file, stdin empty" - /dev/null "$h" "str:COOKIEFILE=$tmp/cookies.txt"
      env_case "POST, body 8, stdin bytes" - "$tmp/stdin.txt" "$h" body:8
      env_case "POST, body 8, RESUME_FROM 3, stdin bytes" - "$tmp/stdin.txt" "$h" body:8 long:RESUME_FROM=3
      env_case "PUT, body 8, RESUME_FROM 3, stdin bytes" - "$tmp/stdin.txt" "$h" method:PUT body:8 long:RESUME_FROM=3
      env_case "POST, body 8, RESUME_FROM_LARGE 3, stdin bytes" - "$tmp/stdin.txt" "$h" body:8 off:RESUME_FROM_LARGE=3
      env_case "GET, RESUME_FROM 3, stdin bytes" - "$tmp/stdin.txt" "$h" long:RESUME_FROM=3
      env_case "COOKIEJAR -, COOKIELIST a cookie" - /dev/null "$h" "str:COOKIELIST=Set-Cookie: jar=out; domain=127.0.0.1; path=/" "str:COOKIEJAR=-"
      env_case "control, http_proxy capture" "$p" /dev/null "$u"
      env_case "UNIX_SOCKET_PATH capture's socket" - /dev/null "$u" "str:UNIX_SOCKET_PATH=$tmp/capture.sock"
      env_case "UNIX_SOCKET_PATH capture's socket, http_proxy capture" "$p" /dev/null "$u" "str:UNIX_SOCKET_PATH=$tmp/capture.sock"
      env_case "CONNECT_TO icy, http_proxy capture" "$p" /dev/null "$u" "list:CONNECT_TO=::127.0.0.1:$iport"
      env_case "RESOLVE hatch.test to 127.0.0.1, http_proxy capture" "$p" /dev/null "$u" "list:RESOLVE=hatch.test:1:127.0.0.1"
      env_case "PROXYHEADER X-P, no proxy" - /dev/null "$h" "list:PROXYHEADER=X-P: 1"
      env_case "PROXYHEADER X-P, http_proxy capture" "$p" /dev/null "$u" "list:PROXYHEADER=X-P: 1"
      env_case "POST, body 3, PROXYHEADER Content-Length 5, http_proxy capture" "$p" /dev/null "$u" body:3 "list:PROXYHEADER=Content-Length: 5"
      env_case "PROXYHEADER Host elsewhere, http_proxy capture" "$p" /dev/null "$u" "list:PROXYHEADER=Host: elsewhere"
      env_case "PROXYHEADER Transfer-Encoding chunked, POST body 3, http_proxy capture" "$p" /dev/null "$u" body:3 "list:PROXYHEADER=Transfer-Encoding: chunked"
      env_case "https, HTTPHEADER X-Secret, HEADEROPT 1, https_proxy capture" "https_proxy=http://127.0.0.1:$cport" /dev/null "$s" "ca:$ca" "list:HTTPHEADER=X-Secret: s" long:HEADEROPT=1
      env_case "https, HTTPHEADER X-Secret, HEADEROPT 0, https_proxy capture" "https_proxy=http://127.0.0.1:$cport" /dev/null "$s" "ca:$ca" "list:HTTPHEADER=X-Secret: s" long:HEADEROPT=0
      env_case "CONNECT_ONLY 1" - /dev/null "$h" long:CONNECT_ONLY=1
      env_case "TIMECONDITION 1, TIMEVALUE 0" - /dev/null "$h" long:TIMECONDITION=1 long:TIMEVALUE=0
      env_case "TRANSFER_ENCODING 1" - /dev/null "$h" long:TRANSFER_ENCODING=1
      env_case "DOH_URL the TLS origin, CA file the run CA" - /dev/null "http://hatch.test:$cport/x" "ca:$ca" "str:DOH_URL=https://127.0.0.1:$tport/dns-query"
      env_case "NETRC 1, HOME with a .netrc" "HOME=$tmp/home" /dev/null "$h" long:NETRC=1
      env_case "NETRC 1, no HOME" - /dev/null "$h" long:NETRC=1
      env_case "VERBOSE 1" - /dev/null "$h" long:VERBOSE=1 ;;
    review)
      h=http://127.0.0.1:$cport/x u=http://hatch.test:1/x p=http_proxy=http://127.0.0.1:$cport
      lf=$(printf 'a\nb\nX')
      lf=${lf%X}
      env_case "POST a LF b LF" - /dev/null "$h" "text:$lf"
      env_case "POST a LF b LF, CRLF 1" - /dev/null "$h" "text:$lf" long:CRLF=1
      env_case "POST a LF b LF, TRANSFERTEXT 1" - /dev/null "$h" "text:$lf" long:TRANSFERTEXT=1
      creds=http://alice:secret@127.0.0.1:$cport/x
      env_case "the URL's credentials alice:secret" - /dev/null "$creds"
      env_case "the URL's credentials, USERPWD mallory:x" - /dev/null "$creds" "str:USERPWD=mallory:x"
      env_case "the URL's credentials, USERNAME mallory" - /dev/null "$creds" "str:USERNAME=mallory"
      env_case "the URL's credentials, PASSWORD x" - /dev/null "$creds" "str:PASSWORD=x"
      printf 'machine 127.0.0.1 login netrc-user password netrc-pass\n' > "$tmp/netrc"
      env_case "the URL's credentials, NETRC 2, NETRC_FILE a file" - /dev/null "$creds" long:NETRC=2 "str:NETRC_FILE=$tmp/netrc"
      env_case "the URL's credentials, NETRC 1, NETRC_FILE a file" - /dev/null "$creds" long:NETRC=1 "str:NETRC_FILE=$tmp/netrc"
      env_case "the URL's credentials, NETRC_FILE alone" - /dev/null "$creds" "str:NETRC_FILE=$tmp/netrc"
      printf 'localhost "20991231 00:00:00"\n' > "$tmp/hsts.txt"
      printf 'example.invalid "20991231 00:00:00"\n' > "$tmp/hsts-other.txt"
      env_case "http://localhost, HSTS naming localhost" - /dev/null "http://localhost:$cport/x" "str:HSTS=$tmp/hsts.txt"
      env_case "http://localhost, HSTS naming another host" - /dev/null "http://localhost:$cport/x" "str:HSTS=$tmp/hsts-other.txt"
      if [ -n "$abstract" ]; then
        env_case "ABSTRACT_UNIX_SOCKET capture's, http_proxy capture" "$p" /dev/null "$u" "str:ABSTRACT_UNIX_SOCKET=$abstract"
      fi
      env_case "DOH_URL the TLS origin, PROXY empty, https_proxy capture" "https_proxy=http://127.0.0.1:$cport" /dev/null "http://hatch.test:$cport/x" "ca:$ca" "str:PROXY=" "str:DOH_URL=https://127.0.0.1:$tport/dns-query"
      env_case "control, PROXY empty, https_proxy capture, no DOH_URL" "https_proxy=http://127.0.0.1:$cport" /dev/null "http://hatch.test:$cport/x" "ca:$ca" "str:PROXY="
      env_case "SSLCERT /dev/stdin, stdin the leaf, CA file the run CA" - "$leaf" "$s" "ca:$ca" "str:SSLCERT=/dev/stdin"
      env_case "control, SSLCERT the leaf's file, stdin the leaf" - "$leaf" "$s" "ca:$ca" "str:SSLCERT=$leaf"
      env_case "SSLENGINE rdrand, SSLENGINE_DEFAULT 1" - /dev/null "$h" "str:SSLENGINE=rdrand" long:SSLENGINE_DEFAULT=1
      env_case "NOPROGRESS 0" - /dev/null "$h" long:NOPROGRESS=0 ;;
    chez)
      out=$(env ${CURL_LIB:+CHEZ_CURL_LIBCURL=$CURL_LIB} "${CHEZ:-scheme}" --libdirs src \
              --program "$here/resolve-chez.sps" "$cport" 2>&1 < /dev/null | tr '\n' ' ')
      echo "[$lane] chez-curl, RESOLVE across one engine: $out"
      tail -n 5 "$tmp/log" | sed "s|^|[$lane]   |" ;;
    *) echo "run.sh: no set $set" >&2; exit 2 ;;
  esac
done
echo "[$lane] done"
