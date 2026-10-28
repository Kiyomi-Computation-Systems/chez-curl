#!/bin/sh
# M5 slice 2's measurements (2026-10-28; the M5 plan, section 5.1), on one
# libcurl:
#   - fragment.c: what curl_url_set makes of a fragment from a header's bytes;
#   - localhost.c: whether localhost, and ::ffff:127.0.0.1, reach a server
#     on 127.0.0.1;
#   - the Location cases of ../redirect-url/, each through the C probe there
#     and through probe.sps, chez-curl's engine and its header reading, then
#     compared, case by case: status, the first Location's bytes, how many,
#     and its resolution, r0, must agree byte for byte.
# Run from the repository's root, in the container:
#   scripts/guix-env sh -c 'CURL_LIB=$CHEZ_CURL_LIBCURL sh .plans/research/m5/location/run.sh guix-8.20.0' < /dev/null
# or in Docker by docker.sh. CURL_LIB is a libcurl.so.4, which chez-curl
# loads too; CURL_INCLUDE, if set, the headers to compile against; CHEZ,
# scheme; NODE, node; CC, cc.
#
# On the Mac, against Apple's libcurl by -lcurl, which discovery finds:
#   CHEZ=chez NODE="$(asdf which node)" sh .plans/research/m5/location/run.sh mac
set -u
[ "$#" -eq 1 ] || { echo "usage: run.sh LANE" >&2; exit 2; }
[ -f .plans/research/m5/location/probe.sps ] || { echo "run.sh: run it from the repository's root" >&2; exit 2; }
if [ -z "${CURL_LIB:-}" ] && [ "$(uname -s)" != Darwin ]; then
  echo "run.sh: set CURL_LIB to a libcurl.so.4" >&2
  exit 2
fi
lane=$1
d=.plans/research/m5/location
r=.plans/research/m5/redirect-url
tmp=$(mktemp -d "${TMPDIR:-/tmp}/location.XXXXXX") || exit 1
pid=
# The server exits once its stdin ends; a watchdog ends it 5 s after that.
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
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
inc=
[ -z "${CURL_INCLUDE:-}" ] || inc="-I$CURL_INCLUDE"
for p in "$r/probe.c:redirect" "$d/fragment.c:fragment" "$d/localhost.c:localhost"; do
  src=${p%%:*}
  out=$tmp/${p##*:}
  # shellcheck disable=SC2086
  if [ -n "${CURL_LIB:-}" ]; then
    "${CC:-cc}" $inc -o "$out" "$src" "$CURL_LIB" -Wl,-rpath,"$(dirname "$CURL_LIB")" 2>"$tmp/cc.err"
  else
    "${CC:-cc}" $inc -o "$out" "$src" -lcurl 2>"$tmp/cc.err"
  fi
  [ -x "$out" ] || { cat "$tmp/cc.err"; exit 1; }
done
if [ -n "${CURL_LIB:-}" ]; then
  echo "[$lane] libcurl $CURL_LIB -> $(readlink -f "$CURL_LIB")"
else
  echo "[$lane] libcurl by -lcurl: $("$tmp/fragment" --version 2>/dev/null || true)"
fi

echo "[$lane] -- fragment"
"$tmp/fragment" | sed "s/^/[$lane] /"

mkfifo "$tmp/in"
"${NODE:-node}" "$r/server.mjs" < "$tmp/in" > "$tmp/port" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/port" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "no port"; exit 1; }; sleep 0.1; done
port=$(cat "$tmp/port")

echo "[$lane] -- localhost, port $port"
"$tmp/localhost" "http://127.0.0.1:$port/x" "http://localhost:$port/x" \
  "http://[::ffff:127.0.0.1]:$port/x" | sed "s/^/[$lane] /"

base="http://127.0.0.1:$port/a/b/c"
cases="rel-abs rel-path rel-dots rel-query rel-frag netpath other-host https no-path upper-scheme
ftp file javascript unknown-scheme empty blank missing padded tab space-inside utf8 latin1 ctl
del pct bad-pct userinfo frag-abs bad-ipv6 bad-port backslash two lower-name idn long-8k
long-90k long-110k s200 s201 s299 s300 s301 s303 s304 s305 s306 s307 s308 s309 s399 s400"
{
  for c in $cases; do echo "$c GET $base/$c?q=1"; done
  for c in rel-abs s303 s304 s307; do echo "$c.head HEAD $base/$c?q=1"; done
  for c in rel-abs rel-frag frag-abs netpath; do echo "$c#orig GET $base/$c?q=1#orig"; done
  for c in rel-abs netpath other-host; do echo "$c@creds GET http://me:secret@127.0.0.1:$port/a/b/c/$c?q=1"; done
  echo "localhost GET http://localhost:$port/a/b/c/rel-abs?q=1"
  echo "mapped GET http://[::ffff:127.0.0.1]:$port/a/b/c/rel-abs?q=1"
} > "$tmp/cases"
echo "[$lane] -- $(wc -l < "$tmp/cases" | tr -d ' ') cases, base $base"

echo "[$lane] -- C"
while read -r label method url; do
  "$tmp/redirect" "$url" "$method" < /dev/null | sed "s/^/[$lane] C $label /"
done < "$tmp/cases" > "$tmp/c.out"
cat "$tmp/c.out"

echo "[$lane] -- Scheme"
if [ -n "${CURL_LIB:-}" ]; then
  CHEZ_CURL_LIBCURL=$CURL_LIB "${CHEZ:-scheme}" --libdirs src --program "$d/probe.sps" "$tmp/cases" \
    < /dev/null > "$tmp/s.raw" 2>&1
else
  "${CHEZ:-scheme}" --libdirs src --program "$d/probe.sps" "$tmp/cases" < /dev/null > "$tmp/s.raw" 2>&1
fi
echo "[$lane] probe.sps exited $?"
sed "s/^/[$lane] S /" "$tmp/s.raw" > "$tmp/s.out"
cat "$tmp/s.out"

echo "[$lane] -- compare"
cat "$tmp/c.out" "$tmp/s.out" | awk -v lane="$lane" '
function load(line, arr,   n, parts, i, k) {
  for (k in arr) delete arr[k]
  gsub(/\(len /, "(len_", line)
  n = split(line, parts, " ")
  for (i = 1; i <= n; i++) {
    k = index(parts[i], "=")
    if (k) arr[substr(parts[i], 1, k - 1)] = substr(parts[i], k + 1)
  }
}
$2 == "C" { c[$3] = $0; order[++n] = $3 }
$2 == "S" && $3 != "libcurl" && $3 != "--" { s[$3] = $0; ns++ }
END {
  agree = 0; differ = 0
  for (i = 1; i <= n; i++) {
    l = order[i]
    if (!(l in s)) { print "[" lane "] compare " l ": no Scheme line"; differ++; continue }
    load(c[l], C); load(s[l], S)
    if (C["location"] ~ /^hc/) C["location"] = "none"
    verdict = ""
    if (C["rc"] != "0" || S["rc"] != "0") {
      if (C["rc"] != S["rc"]) verdict = " rc"
    } else {
      if (C["status"] != S["status"]) verdict = verdict " status"
      if (C["location"] != S["location"]) verdict = verdict " location"
      if (C["amount"] != S["amount"]) verdict = verdict " amount"
      if (C["r0"] != S["r0"]) verdict = verdict " r0"
    }
    if (verdict == "") agree++
    else { differ++; print "[" lane "] compare " l " differs:" verdict; print "  " c[l]; print "  " s[l] }
  }
  print "[" lane "] compare: " agree " agree, " differ " differ, of " n " C lines and " ns " Scheme lines"
}'
