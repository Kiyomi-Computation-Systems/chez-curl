#!/bin/sh
# M8 slice 2's review fixes: the odd-header probe on one libcurl, from a
# tree's root holding src/ and odd/: CHEZ runs odd/odd.sps with src alone on
# the library path, CHEZ_CURL_LIBCURL the libcurl, NODE the stand-in's Node.
#   sh odd/odd.sh LABEL
set -u
label=${1:-lane}
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE SSL_CERT_DIR
tmp=$(mktemp -d "${TMPDIR:-/tmp}/odd.XXXXXX") || exit 1
mkfifo "$tmp/in"
"${NODE:-node}" odd/oddserver.mjs < "$tmp/in" > "$tmp/port" 2> "$tmp/err" &
pid=$!
exec 3> "$tmp/in"
n=0
until [ -s "$tmp/port" ]; do n=$((n+1)); [ $n -le 100 ] || { echo "[$label] no port"; cat "$tmp/err"; exit 1; }; sleep 0.1; done
echo "[$label] chez $("${CHEZ:-scheme}" --version 2>&1) libcurl ${CHEZ_CURL_LIBCURL:-unset} node $("${NODE:-node}" --version) transfer.sls sha256 $(sha256sum src/curl/private/transfer.sls | cut -c1-16)"
{ "${CHEZ:-scheme}" --libdirs src --program odd/odd.sps "$(cat "$tmp/port")" < /dev/null 2>&1; echo "program exit=$?"; } | sed "s/^/[$label] /"
exec 3>&-
wait "$pid"
echo "[$label] server exit=$?"
[ -s "$tmp/err" ] && sed "s/^/[$label] server-stderr: /" "$tmp/err"
rm -f "$tmp/in" "$tmp/port" "$tmp/err"
rmdir "$tmp"
