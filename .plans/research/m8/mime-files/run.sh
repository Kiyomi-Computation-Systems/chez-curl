#!/bin/sh
# M8's mime-files probe (2026-11-06; probe 2 of the M8 plan's measurements),
# on one libcurl: probe.c, built against that libcurl, against server.mjs.
# Run from the repository's root. Lane X, in the container, pinned from the
# host:
#   taskset -c 6-11 scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL VALGRIND=valgrind sh .plans/research/m8/mime-files/run.sh guix-8.20.0' < /dev/null
# the Docker lanes by docker.sh, the builds without mime by nomime.sh, and
# the Mac by mac.sh.
#
# CURL_LIB is a libcurl.so.4 to link; CURL_INCLUDE, the headers to compile
# against, by default the lane's own: CURL_LIB's ../include when it holds
# curl/curl.h, else the compiler's. NODE, node; CC, cc; CASES, the cases to
# run, by default every case probe --list names, one process each, each in a
# fresh directory of its own under the run's mktemp directory.
#
# VALGRIND, when set, names a valgrind: after the native cases, the lifetime
# and handle cases (VG_CASES, by default every L- and M- case, and
# R-when; none skips the pass) run again under it, each in a process of its own, with the memory
# gate's options (ADR-0014; Makefile, test-memory): -v --command-line-only=yes
# --log-file --error-exitcode=9 --leak-check=full --show-leak-kinds=definite
# --errors-for-leak-kinds=definite, and in a Guix environment the gate's one
# suppression, tests/guix-glibc-locpath.supp. timeout wraps valgrind, never
# the probe. PROBE_PLAIN=1 there: libcurl allocates by malloc itself. Every
# line of each Valgrind log is printed but its -v "--PID--" lines, of which
# the used_suppression ones are kept, and its banner about vgdb and gdb, and
# its notes on conflicting redirections, which every run prints alike.
#
# On the Mac, against Apple's libcurl by -lcurl and the SDK's headers, with
# CURL_LIB unset; CURL_SSL_BACKEND=secure-transport unless set, as make test
# does (no case here uses TLS). The file watch is Linux's alone.
#
# It unsets the proxy variables, SSL_CERT_FILE, SSL_CERT_DIR and VALGRIND_OPTS.
# Every line it prints begins [LANE]; it writes nothing outside its mktemp
# directory but stdout.
set -u
if [ "$(uname -s)" = Darwin ]; then
  CURL_SSL_BACKEND=${CURL_SSL_BACKEND:-secure-transport}
  export CURL_SSL_BACKEND
fi
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
d=.plans/research/m8/mime-files
[ -f $d/probe.c ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR VALGRIND_OPTS
lane=$1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/m8mf.XXXXXX") || exit 1
pid=
# The server exits once its stdin ends. A watchdog ends it 5 s after that
# closes, and says so.
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
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=${CURL_INCLUDE:-}
if [ -z "$inc" ] && [ -n "${CURL_LIB:-}" ] && [ -f "$(dirname "$CURL_LIB")/../include/curl/curl.h" ]; then
  inc=$(dirname "$CURL_LIB")/../include
fi
ldl=
[ "$(uname -s)" = Linux ] && ldl=-ldl
# shellcheck disable=SC2086
if [ -n "${CURL_LIB:-}" ]; then
  "${CC:-cc}" ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" $ldl 2>"$tmp/cc.err"
else
  "${CC:-cc}" ${inc:+-I"$inc"} -o "$tmp/probe" "$d/probe.c" -lcurl 2>"$tmp/cc.err"
fi
cc_status=$?
[ "$cc_status" -eq 0 ] || { echo "[$lane] the compile exited $cc_status"; sed "s/^/[$lane] cc: /" "$tmp/cc.err"; exit 1; }
if [ -n "${CURL_LIB:-}" ]; then
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB" 2>/dev/null || echo "$CURL_LIB"), headers ${inc:-the compiler's}"
else
  echo "[$lane] libcurl by -lcurl, headers ${inc:-the compiler's}"
fi
echo "[$lane] node $("${NODE:-node}" --version) uname $(uname -sm) uid=$(id -u) CURL_SSL_BACKEND=${CURL_SSL_BACKEND:-unset} cpus=$( (grep Cpus_allowed_list /proc/self/status 2>/dev/null || echo '-') | tr -d '\t' )"
"$tmp/probe" --version 2>&1 | sed "s/^/[$lane] /"
cases=${CASES:-$("$tmp/probe" --list)}
mkfifo "$tmp/in"
"${NODE:-node}" "$d/server.mjs" < "$tmp/in" > "$tmp/ports" 2> "$tmp/server.err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/ports" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$lane] no ports"; cat "$tmp/server.err"; exit 1; }; sleep 0.1; done
echo "[$lane] server $(cat "$tmp/ports")"
set -- $(sed 's/[a-z0-9]*=//g' "$tmp/ports")
count=0
for c in $cases; do
  start=$(date +%s)
  mkdir "$tmp/c-$c"
  { "$tmp/probe" "$c" "$1" "$2" "$3" "$tmp/c-$c" < /dev/null 2>&1; echo "probe $c exit=$?"; } | sed "s/^/[$lane] /"
  echo "[$lane] probe $c took about $(( $(date +%s) - start )) s"
  count=$((count+1))
done
echo "[$lane] -- $count cases run"
[ "${VG_CASES:-}" = none ] && VALGRIND=
if [ -n "${VALGRIND:-}" ]; then
  supp=
  [ -n "${GUIX_ENVIRONMENT:-}" ] && supp=--suppressions=tests/guix-glibc-locpath.supp
  vgcases=${VG_CASES:-$("$tmp/probe" --list | grep -e '^L-' -e '^M-' -e '^R-when$')}
  echo "[$lane] valgrind $("$VALGRIND" --version) ${supp:-no suppression}"
  vcount=0
  for c in $vgcases; do
    start=$(date +%s)
    mkdir "$tmp/v-$c"
    # shellcheck disable=SC2086
    PROBE_PLAIN=1 PROBE_ALARM=280 timeout 300 "$VALGRIND" -v --command-line-only=yes --log-file="$tmp/v-$c.vg" --error-exitcode=9 \
      --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $supp \
      "$tmp/probe" "$c" "$1" "$2" "$3" "$tmp/v-$c" < /dev/null > "$tmp/v-$c.out" 2>&1
    st=$?
    sed "s/^/[$lane] vg $c out: /" "$tmp/v-$c.out" | grep -v ' dbg '
    grep -v -e '^--' -e 'gdbserver' -e 'vgdb' -e 'TO CONTROL THIS' -e 'TO DEBUG THIS' -e "don't want to do" -e 'strange experiment' \
      -e '/path/to/gdb' -e 'and then give GDB' -e 'pid is optional' -e 'redirection' "$tmp/v-$c.vg" | sed "s/^/[$lane] vg $c valgrind: /"
    grep -e 'used_suppression' "$tmp/v-$c.vg" | sed "s/^/[$lane] vg $c valgrind: /"
    echo "[$lane] vg $c exit=$st took about $(( $(date +%s) - start )) s"
    vcount=$((vcount+1))
  done
  echo "[$lane] -- $vcount cases run under valgrind"
fi
exit 0
