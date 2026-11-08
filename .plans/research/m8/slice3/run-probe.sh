#!/bin/sh
# M8 slice 3's probe on one lane, from the probe tree's root, where lanes.sh
# (or the session, for the Guix lane) has copied this directory's programs
# into m8s3/, beside the mime-files stand-in as m8s3/server-files.mjs:
#   sh m8s3/run-probe.sh LANE [GROUP...]
# It makes the run's PKI, starts the tree's own test origin, the
# prototype's (tests/origin.mjs --pki), and the mime-files stand-in, then
# runs m8s3/engine-probe.sps with their ports, a CA file and a scratch
# directory, src alone on the library path. CHEZ runs it and
# CHEZ_CURL_LIBCURL names the lane's libcurl. NOFILES=1 starts no stand-in
# (its ports 0), for the builds without mime. VALGRIND=FILE runs CHEZ under
# Valgrind with the memory gate's options (ADR-0014; the Makefile's
# test-memory): -v --command-line-only=yes --log-file=FILE
# --error-exitcode=9 --leak-check=full --show-leak-kinds=definite
# --errors-for-leak-kinds=definite, and in a Guix environment the gate's one
# suppression, and sets M8S3_SLOW, which the memory group's cancel and
# timeout read. The servers run natively.
#
# It unsets the proxy variables, SSL_CERT_FILE and SSL_CERT_DIR. Every line
# it prints begins [LANE]; it writes nothing outside its mktemp directory
# but stdout, and Valgrind's log.
set -u
[ "$#" -ge 1 ] || { echo "usage: run-probe.sh LANE [GROUP...]" >&2; exit 2; }
[ -f m8s3/engine-probe.sps ] || { echo "run-probe.sh: no m8s3/engine-probe.sps: run it from the probe tree's root" >&2; exit 2; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR
lane=$1; shift
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8s3.XXXXXX") || exit 1
opid=; fpid=
stop() {
  # $1 the pid, $2 the fd holding its stdin, $3 its name
  if [ -n "$1" ]; then
    eval "exec $2>&-"
    ( sleep 5; kill "$1" 2>/dev/null ) > /dev/null 2>&1 &
    watchdog=$!
    wait "$1"
    status=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    [ "$status" -eq 0 ] || echo "[$lane] $3 exited $status, not 0, after its stdin closed: 143 is the watchdog's kill, 5 s on"
  fi
}
cleanup() {
  stop "$opid" 3 origin
  stop "$fpid" 4 stand-in
  [ -s "$tmp/origin.err" ] && sed "s/^/[$lane] origin-stderr: /" "$tmp/origin.err"
  [ -s "$tmp/files.err" ] && sed "s/^/[$lane] stand-in-stderr: /" "$tmp/files.err"
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
echo "[$lane] tree $(pwd) chez ${CHEZ:-scheme} $("${CHEZ:-scheme}" --version 2>&1) libcurl ${CHEZ_CURL_LIBCURL:-unset} node $("${NODE:-node}" --version) probe sha256 $(sha256sum m8s3/engine-probe.sps | cut -c1-16) transfer.sls sha256 $(sha256sum src/curl/private/transfer.sls | cut -c1-16) origin.mjs sha256 $(sha256sum tests/origin.mjs | cut -c1-16) affinity=$(sed -n 's/^Cpus_allowed_list:[[:space:]]*//p' /proc/self/status 2>/dev/null) uid=$(id -u) valgrind=${VALGRIND:-unset}"
mkdir "$tmp/pki" "$tmp/files"
sh tests/make-test-pki.sh "$tmp/pki" > "$tmp/pki.out" 2>&1 || { echo "[$lane] make-test-pki failed"; cat "$tmp/pki.out"; exit 1; }
mkfifo "$tmp/oin" "$tmp/fin"
"${NODE:-node}" tests/origin.mjs --pki "$tmp/pki" < "$tmp/oin" > "$tmp/oports" 2> "$tmp/origin.err" &
opid=$!
exec 3> "$tmp/oin"
if [ -z "${NOFILES:-}" ]; then
  # fd 3, the origin's stdin, is closed in the stand-in, so the origin's
  # stdin ends when this script closes it
  "${NODE:-node}" m8s3/server-files.mjs < "$tmp/fin" > "$tmp/fports" 2> "$tmp/files.err" 3>&- &
  fpid=$!
  exec 4> "$tmp/fin"
else
  # no reader: an open of the FIFO would wait for one
  exec 4> /dev/null
fi
n=0
until [ -s "$tmp/oports" ] && { [ -n "${NOFILES:-}" ] || [ -s "$tmp/fports" ]; }; do
  n=$((n+1)); [ $n -le 150 ] || { echo "[$lane] no ports"; cat "$tmp/origin.err" "$tmp/files.err" 2>/dev/null; exit 1; }; sleep 0.1
done
echo "[$lane] origin $(cat "$tmp/oports")"
face() { sed "s/.*\"$1\":\"127\.0\.0\.1:\([0-9]*\)\".*/\1/" "$tmp/oports"; }
if [ -z "${NOFILES:-}" ]; then
  echo "[$lane] stand-in $(cat "$tmp/fports")"
  fport() { sed "s/.*$1=\([0-9]*\).*/\1/" "$tmp/fports"; }
  set -- "$lane" "$(face http)" "$(face h2c)" "$(face h2)" "$(face raw)" "$tmp/pki/ca.pem" "$(fport raw)" "$(fport h2c)" "$(fport ctl)" "$tmp/files" "$@"
else
  set -- "$lane" "$(face http)" "$(face h2c)" "$(face h2)" "$(face raw)" "$tmp/pki/ca.pem" 0 0 0 "$tmp/files" "$@"
fi
start=$(date +%s)
if [ -n "${VALGRIND:-}" ]; then
  # the memory group's cancel and timeout wait longer under Valgrind
  export M8S3_SLOW=1
  supp=
  [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
  # shellcheck disable=SC2086
  { valgrind -v --command-line-only=yes "--log-file=$VALGRIND" --error-exitcode=9 --leak-check=full --show-leak-kinds=definite \
      --errors-for-leak-kinds=definite $supp "${CHEZ:-scheme}" --libdirs src --program m8s3/engine-probe.sps "$@" < /dev/null 2>&1 3>&- 4>&-; echo "program exit=$?"; } | sed -u "s/^/[$lane] /"
  echo "[$lane] valgrind $(valgrind --version) log $VALGRIND: $(grep 'ERROR SUMMARY' "$VALGRIND" | tail -1)"
else
  { "${CHEZ:-scheme}" --libdirs src --program m8s3/engine-probe.sps "$@" < /dev/null 2>&1 3>&- 4>&-; echo "program exit=$?"; } | sed -u "s/^/[$lane] /"
fi
echo "[$lane] took about $(( $(date +%s) - start )) s"
exit 0
