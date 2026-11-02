#!/bin/sh
# M7's cookie probe: compares the kept logs (2026-11-02). Run on the host,
# from the repository's root:
#   sh .plans/research/m7/cookies/compare.sh > .plans/research/m7/cookies/results/compare.txt
# Splits results/guix-8.20.0{,-2}.log and results/docker{,-2}.log (and
# results/mac-8.7.1.log when it is there) by lane and run, takes out what
# moves on every run (ports, connection ports, temporary paths, clock
# readings, absolute expiry times, and the hex-coded queries, whose dates
# and ports move; an expiry relative to now within 2 s of a whole minute is
# printed as ~ that minute, since the clock can tick between a cookie's set
# and its read), then prints, for each lane, the diff of its two runs (a
# split), and for each lane but guix-8.20.0, the diff of its first run
# against guix-8.20.0's first run (what varies by lane). Each diff is
# preceded by its line count; "0 lines" means the normalised runs agree.
# The normalised files land in build/m7/cookies/norm/.
set -u
d=.plans/research/m7/cookies
[ -f $d/probe.c ] || { echo "compare.sh: run it from the repository's root" >&2; exit 2; }
out=build/m7/cookies/norm
rm -rf "$out"
mkdir -p "$out"
norm() {
  # $1 log, $2 lane, $3 output
  grep "^\[$2\] " "$1" | sed -E \
    -e "s/^\[$2\] //" \
    -e '/^server port=/d' \
    -e 's/url="[^"]*"/url=U/' \
    -e 's/(got req [A-Z]+ [^? ]*)[^ ]* /\1 /' \
    -e 's/:[0-9]{4,5}([/" ]|$)/:PORT\1/g' \
    -e 's/redirect_url=(http:\/\/[^:]*):[0-9]+/redirect_url=\1:PORT/' \
    -e 's/conn=[0-9]+/conn=N/' \
    -e 's/\\t1[0-9]{9}\\t/\\tT\\t/' \
    -e 's/exp_delta=(345599[6-9][0-9]|345600[0-2][0-9]|34560030)$/exp_delta=CAP(400d+30s, down to the minute)/' \
    -e 's/exp_delta=-[0-9]+$/exp_delta=NEGATIVE/' \
    -e 's/exp_delta=[0-9]{11,}$/exp_delta=HUGE/' \
    -e 's/ t=[0-9]+/ t=N/' \
    -e 's/ took-about=[0-9]+s//' \
    -e 's#/tmp/m7cookies\.[A-Za-z0-9]+#/TMP#g' \
    -e 's#/[A-Za-z0-9]{40}\.tmp#/RANDOM.tmp#' \
    -e 's#\.[0-9a-f]{8}\.tmp#.RANDOM.tmp#' \
    -e 's/(libcurl [^ ]*) -> .*/\1/' \
  | awk '
    # an expiry read a second or two after it was set: to the minute, as ~N
    match($0, /exp_delta=[0-9]+$/) {
      v = substr($0, RSTART + 10) + 0; r = int((v + 30) / 60) * 60
      if (v - r <= 2 && r - v <= 2) $0 = substr($0, 1, RSTART - 1) "exp_delta~" r
    }
    { print }' > "$3"
}
lanes_docker="floor-7.85.0 ubuntu-openssl-8.5.0 ubuntu-gnutls-8.5.0 current-8.23.0"
norm $d/results/guix-8.20.0.log guix-8.20.0 "$out/guix-8.20.0.1"
norm $d/results/guix-8.20.0-2.log guix-8.20.0 "$out/guix-8.20.0.2"
for l in $lanes_docker; do
  norm $d/results/docker.log "$l" "$out/$l.1"
  norm $d/results/docker-2.log "$l" "$out/$l.2"
done
all="guix-8.20.0 $lanes_docker"
if [ -f $d/results/mac-8.7.1.log ]; then
  norm $d/results/mac-8.7.1.log mac-8.7.1 "$out/mac-8.7.1.1"
  norm $d/results/mac-8.7.1.log mac-8.7.1-run2 "$out/mac-8.7.1.2"
  all="$all mac-8.7.1"
fi
for l in $all; do
  echo "== split check $l: run 1 ($(wc -l < "$out/$l.1" | tr -d ' ') lines) against run 2 ($(wc -l < "$out/$l.2" | tr -d ' ') lines)"
  diff "$out/$l.1" "$out/$l.2" > "$out/$l.split"
  echo "$(wc -l < "$out/$l.split" | tr -d ' ') lines"
  cat "$out/$l.split"
done
# The cookie view, for the lane checks: without the address each transfer
# reached (printed once per lane instead, as a count of each), without the
# transfers' fopen("") calls (counted per case instead), and with each run of
# jar lines sorted, since the order CURLINFO_COOKIELIST lists moves with its
# hash table, by version. Cookie headers are kept whole and in order.
view() {
  awk '
    function flush() { if (nb) { n = nb; for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (buf[j] < buf[i]) { t = buf[i]; buf[i] = buf[j]; buf[j] = t } for (i = 1; i <= n; i++) print buf[i]; nb = 0; key = "" } }
    / got remote / { flush(); split($0, a, " got remote "); split(a[2], b, " "); addr[b[1]]++; next }
    /fs fopen step=- path=""$/ { flush(); fo[$2]++; next }
    { gsub(/ primary=[^ ]*/, "") }
    /^case [^ ]+ jar@[^ ]+ line / { k = $1 " " $2 " " $3; if (k != key) flush(); key = k; buf[++nb] = $0; next }
    /^probe [^ ]+ exit=/ { flush(); print "case " $2 " fopen(\"\") during transfers: " (fo[$2] + 0); print; next }
    { flush(); print }
    END { flush(); for (x in addr) print "addresses reached: " x " " addr[x] }
  ' "$1"
}
for l in $all; do
  view "$out/$l.1" > "$out/$l.view"
done
for l in $all; do
  [ "$l" = guix-8.20.0 ] && continue
  echo "== lane check, the cookie view: guix-8.20.0 run 1 (<) against $l run 1 (>)"
  diff "$out/guix-8.20.0.view" "$out/$l.view" > "$out/$l.lane"
  echo "$(wc -l < "$out/$l.lane" | tr -d ' ') lines"
  cat "$out/$l.lane"
done
echo "== lane check, the cookie view: ubuntu-openssl-8.5.0 run 1 (<) against ubuntu-gnutls-8.5.0 run 1 (>)"
diff "$out/ubuntu-openssl-8.5.0.view" "$out/ubuntu-gnutls-8.5.0.view" > "$out/8.5.0-tls.lane"
echo "$(wc -l < "$out/8.5.0-tls.lane" | tr -d ' ') lines"
cat "$out/8.5.0-tls.lane"
