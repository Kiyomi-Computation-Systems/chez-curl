#!/bin/sh
# test-examples' tables loosened with the code they check, and make deps,
# check-seam and the suites' library path with jsonparse missing or
# misused, in the second copy (tree2). Run inside the container from its
# root:
#   scripts/guix-env sh review-scripts/plants-examples-build.sh < /dev/null
set -u
out=review-out/plants
mkdir -p "$out" review-scripts/pristine
for f in tests/test-examples.sps examples/errors.sps tests/test-reference.sps; do
  cp "$f" "review-scripts/pristine/$(basename "$f")"
done
restore() {
  for f in tests/test-examples.sps examples/errors.sps tests/test-reference.sps; do
    cp "review-scripts/pristine/$(basename "$f")" "$f"
  done
  rm -f src/curl/private/planted.sls
}
suite() { # suite NAME LOG
  "$CHEZ" --libdirs src:tests:build/scheme-libs --program "tests/$1.sps" >"$2" 2>&1 3>&-
  rc=$?
  echo "   $1 exit $rc"
  grep '^FAIL' "$2" | head -4 | sed 's/^/   /'
}
repl() { # repl FILE OLD NEW
  OLD=$2 NEW=$3 node review-scripts/replace.js "$1" || echo "   NOT APPLIED in $1"
}

echo "== control: make deps, then test-examples"
make --no-print-directory deps >"$out/control-deps.log" 2>&1; echo "   deps exit $?"
suite test-examples "$out/control-test-examples.log"

echo "== e1: allowed-imports takes (jsonparse easy) for every example; errors.sps imports it"
repl tests/test-examples.sps "(if (member name jsonparse-examples) '((jsonparse easy)) '())" "'((jsonparse easy))"
repl examples/errors.sps "(import (rnrs) (curl) (http-client))" "(import (rnrs) (curl) (http-client) (jsonparse easy))"
suite test-examples "$out/e1-test-examples.log"
restore

echo "== e2: jsonparse-examples names errors too; errors.sps imports jsonparse, its run line src:build/scheme-libs"
repl tests/test-examples.sps "(define jsonparse-examples '(\"json-api\"))" "(define jsonparse-examples '(\"json-api\" \"errors\"))"
repl examples/errors.sps "(import (rnrs) (curl) (http-client))" "(import (rnrs) (curl) (http-client) (jsonparse easy))"
repl examples/errors.sps ";;;   scheme --libdirs src --program examples/errors.sps URL" ";;;   scheme --libdirs src:build/scheme-libs --program examples/errors.sps URL"
suite test-examples "$out/e2-test-examples.log"
suite test-docs "$out/e2-test-docs.log"
restore

echo "== e3: every child runs with build/scheme-libs, its run line unchanged; allowed-imports loosened; errors.sps imports jsonparse"
repl tests/test-examples.sps "(run-program (string-append \"examples/\" name \".sps\") (libdirs name) base" "(run-program (string-append \"examples/\" name \".sps\") \"src:build/scheme-libs\" base"
repl tests/test-examples.sps "(if (member name jsonparse-examples) '((jsonparse easy)) '())" "'((jsonparse easy))"
repl examples/errors.sps "(import (rnrs) (curl) (http-client))" "(import (rnrs) (curl) (http-client) (jsonparse easy))"
suite test-examples "$out/e3-test-examples.log"
suite test-docs "$out/e3-test-docs.log"
echo "   errors.sps as its own run line says, --libdirs src:"
"$CHEZ" --libdirs src --program examples/errors.sps http://127.0.0.1:9 >"$out/e3-reader.log" 2>&1 3>&-
echo "   exit $?: $(head -c 200 "$out/e3-reader.log")"
restore

echo "== b1: a src library imports (jsonparse easy): check-seam"
mkdir -p src/curl/private
cat >src/curl/private/planted.sls <<'EOF'
#!r6rs
(library (curl private planted)
  (export planted)
  (import (rnrs) (jsonparse easy))
  (define planted (json->bytevector 1)))
EOF
make --no-print-directory check-seam >"$out/b1-check-seam.log" 2>&1; echo "   check-seam exit $?"
grep -i -E 'jsonparse|planted' "$out/b1-check-seam.log" | head -4 | sed 's/^/   /'
restore

echo "== b2: a suite imports (jsonparse easy): check-suites, then the suite"
repl tests/test-reference.sps "(import (rnrs)" "(import (rnrs) (jsonparse easy)"
make --no-print-directory check-suites >"$out/b2-check-suites.log" 2>&1; echo "   check-suites exit $?"
suite test-reference "$out/b2-test-reference.log"
restore

echo "== b3: vendor/jsonparse empty, as a clone before its submodule update"
mv vendor/jsonparse review-jsonparse-aside && mkdir vendor/jsonparse
rm -rf build
make --no-print-directory deps >"$out/b3-deps.log" 2>&1; echo "   deps exit $?"; sed 's/^/   | /' "$out/b3-deps.log"
make --no-print-directory check-seam >"$out/b3-check-seam.log" 2>&1; echo "   check-seam exit $?"
make --no-print-directory build >"$out/b3-build.log" 2>&1; echo "   build exit $?"
make --no-print-directory check-suites >"$out/b3-check-suites.log" 2>&1; echo "   check-suites exit $? ($(tail -n 1 "$out/b3-check-suites.log"))"
make --no-print-directory test TEST_TIMEOUT=60 >"$out/b3-test.log" 2>&1; echo "   test exit $? ($(grep -c '^=== ' "$out/b3-test.log") suites started)"
echo "   a program of (curl) alone, --libdirs src:"
echo '(import (curl)) (display (libcurl-info-version (loaded-libcurl))) (newline)' | "$CHEZ" -q --libdirs src 2>&1 | sed 's/^/   | /'
rmdir vendor/jsonparse && mv review-jsonparse-aside vendor/jsonparse

echo "== b4: byte-machine empty, as a non-recursive submodule update"
mv vendor/jsonparse/vendor/byte-machine review-bm-aside && mkdir vendor/jsonparse/vendor/byte-machine
make --no-print-directory deps >"$out/b4-deps.log" 2>&1; echo "   deps exit $?"; sed 's/^/   | /' "$out/b4-deps.log"
rmdir vendor/jsonparse/vendor/byte-machine && mv review-bm-aside vendor/jsonparse/vendor/byte-machine

echo "== b5: jsonparse's src/generated gone"
mv vendor/jsonparse/src/generated review-gen-aside
make --no-print-directory deps >"$out/b5-deps.log" 2>&1; echo "   deps exit $?"; sed 's/^/   | /' "$out/b5-deps.log"
mv review-gen-aside vendor/jsonparse/src/generated

echo "== after: make deps again"
make --no-print-directory deps >"$out/after-deps.log" 2>&1; echo "   deps exit $?"
