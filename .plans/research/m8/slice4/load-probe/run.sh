#!/bin/sh
# run.sh: each probe program, with CHEZ_CURL_LIBCURL set to a relative path,
# which discovery refuses (invalid-override). A program whose binding loads
# libcurl fails before its body, status 255; one whose binding does not
# prints its kind, status 0. Run inside scripts/guix-env from the root.
for f in .plans/research/m8/slice4/load-probe/*.sps; do
  out=$(CHEZ_CURL_LIBCURL=relative/libcurl.so "$CHEZ" --libdirs src:build/scheme-libs --program "$f" 2>&1)
  status=$?
  name=$(basename "$f" .sps)
  first=$(printf '%s' "$out" | head -1 | cut -c1-60)
  echo "$name status=$status $first"
done
