#!/bin/sh
# quick-start as a reader runs it: CHEZSCHEMELIBDIRS in place of --libdirs,
# and no CHEZ_CURL_LIBCURL (discovery). Run inside scripts/guix-env.
set -u
out=build/m8s4-review/reader-env
mkdir -p "$out"
fifo="$out/origin-stdin"; rm -f "$fifo"; mkfifo "$fifo"
node tests/origin.mjs < "$fifo" > "$out/origin.json" 2> "$out/origin.err" &
opid=$!
exec 7> "$fifo"
i=0; while [ ! -s "$out/origin.json" ] && [ $i -lt 100 ]; do i=$((i+1)); sleep 0.1; done
base="http://$(sed -n 's/.*"http":"\([^"]*\)".*/\1/p' "$out/origin.json")"
echo "--- CHEZSCHEMELIBDIRS=$PWD/src, CHEZ_CURL_LIBCURL unset"
env -u CHEZ_CURL_LIBCURL CHEZSCHEMELIBDIRS="$PWD/src" scheme --program examples/quick-start.sps "$base" < /dev/null; echo "exit $?"
echo "--- the load check, CHEZ_CURL_LIBCURL unset"
echo '(import (curl)) (display (libcurl-info-version (loaded-libcurl))) (newline) (display (libcurl-info-source (loaded-libcurl))) (newline) (display (libcurl-info-path (loaded-libcurl)))' | env -u CHEZ_CURL_LIBCURL scheme -q --libdirs src; echo; echo "exit $?"
echo "--- the low-level fragments (low-level.md URLs)"
cat > "$out/urls.ss" <<'EOS'
(import (chezscheme) (curl))
(for-each (lambda (thunk) (guard (e (#t (display "RAISED ") (display (condition-message e)) (newline))) (write (thunk)) (newline)))
 (list (lambda () (curl-url-part "https://u@example.com:8443/a?b#c" 'port))
       (lambda () (curl-url-part "https://example.com/a" 'port))
       (lambda () (curl-url-append-query "https://example.com/s?q=1" "page=2"))
       (lambda () (curl-url-resolve "http://example.com/a/b/c" "../d?x=2"))
       (lambda () (curl-url-with-fragment "http://example.com/a" "top"))
       (lambda () (curl-url-part "http://example.com/a%zz" 'url))
       (lambda () (curl-url-part "http:/example.com/x" 'url))
       (lambda () (curl-url-part "HTTP://Example.COM:80/x" 'url))
       (lambda () (curl-url-append-query "https://example.com/s?q=1&" "page=2"))
       (lambda () (curl-url-append-query "https://example.com/s?" "page=2"))
       (lambda () (curl-url-append-query "https://example.com/s#f" "page=2"))
       (lambda () (curl-url-resolve "http://example.com/a" (bytevector 47 32 127 128 255)))
       (lambda () (curl-url-with-fragment "http://example.com/a#x" #f))
       (lambda () (curl-url-with-fragment "http://example.com/a#x" ""))
       (lambda () (curl-url-part "http://[fe80::1%25eth0]/" 'host))
       (lambda () (curl-url-part "http://[fe80::1%25eth0]/" 'zoneid))))
EOS
scheme -q --libdirs src --script "$out/urls.ss" < /dev/null; echo "exit $?"
exec 7>&-; wait $opid
