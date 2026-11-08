#!/bin/bash
# For the survey's ten claims (docs.md section 1, at fbc6fce): which files
# slices 2 and 3 changed, and, for transfer.sls, whether the ranges each claim
# rests on are byte for byte the same at HEAD. Host only (git), read-only.
R=/home/kishu/src/chez-curl
echo "## files changed fbc6fce..HEAD among those the ten rest on"
git -C $R diff --stat fbc6fce..HEAD -- Makefile src/curl/private/require-threaded.sls src/curl/private/verify.sls \
  src/curl/private/url.sls src/curl/private/transfer.sls src/curl/private/conditions.sls \
  src/curl/private/engine.sls src/http-client/private/exchange.sls src/http-client/private/call.sls
echo "## hunks: Makefile, conditions.sls, exchange.sls"
for f in Makefile src/curl/private/conditions.sls src/http-client/private/exchange.sls; do
  echo "# $f"; git -C $R diff fbc6fce..HEAD -- $f | grep '^@@'; done
echo "## transfer.sls ranges, old (fbc6fce) against new (HEAD)"
old=$(mktemp "${TMPDIR:-/tmp}/transfer-old.XXXXXX")
git -C $R show fbc6fce:src/curl/private/transfer.sls > "$old"
cmp3() { if diff <(sed -n "$1,$2p" "$old") <(sed -n "$3,$4p" $R/src/curl/private/transfer.sls) > /dev/null
         then echo "same: old $1-$2 = new $3-$4 ($5)"; else echo "DIFFERS: old $1-$2 vs new $3-$4 ($5)"; fi; }
cmp3 486 560 550 624 "pkcs11-prefix? and the CA file's refusal, claim 3"
cmp3 1815 1822 2330 2337 "pinned-options, MAXREDIRS 30, claim 7"
cmp3 2170 2200 2685 2715 "share-settings and cookie-line-limit, claim 9"
cmp3 3110 3130 3701 3721 "upload-buffer-limit, claim 10"
echo "## the lines, old and new"
for pat in '(define (pkcs11-prefix?' "'pkcs11-url" '(define pinned-options' '"NOSIGNAL" "QUICK_EXIT" "MAXREDIRS"' \
           '(http-version "HTTP_VERSION")' '"SSL_ENABLE_ALPN" "ALTSVC" "ALTSVC_CTRL"' \
           '(define share-settings' '(define cookie-line-limit' '(define upload-buffer-limit'; do
  echo "# $pat: old $(grep -n -F -- "$pat" "$old" | head -1 | cut -d: -f1), new $(grep -n -F -- "$pat" $R/src/curl/private/transfer.sls | head -1 | cut -d: -f1)"
done
echo "# PIPEWAIT in src at HEAD:"; grep -rn PIPEWAIT $R/src | sed "s|$R/||" | cut -c1-120
echo "# OPENSSL_X509_TEA_DISABLE in src at HEAD (none expected):"; grep -rn OPENSSL_X509_TEA_DISABLE $R/src | wc -l
echo "# url.sls 320-332 old = new:"; diff <(git -C $R show fbc6fce:src/curl/private/url.sls | sed -n 320,332p) <(sed -n 320,332p $R/src/curl/private/url.sls) > /dev/null && echo same || echo DIFFERS
echo "# call.sls defaults old 101,106 / new 105,110:"; git -C $R show fbc6fce:src/http-client/private/call.sls | sed -n '101p;106p'; sed -n '105p;110p' $R/src/http-client/private/call.sls
echo "# exchange.sls redirect-statuses old/new 591:"; git -C $R show fbc6fce:src/http-client/private/exchange.sls | sed -n 591p; sed -n 591p $R/src/http-client/private/exchange.sls
echo "# engine.sls unmultiplexed-versions old/new 408:"; git -C $R show fbc6fce:src/curl/private/engine.sls | sed -n 408p; sed -n 408p $R/src/curl/private/engine.sls
echo "# Makefile 34-37 old = new:"; diff <(git -C $R show fbc6fce:Makefile | sed -n 34,37p) <(sed -n 34,37p $R/Makefile) > /dev/null && echo same || echo DIFFERS
echo "ok readme-survey-carry done"
