# M8 slice 6, the release: verification

- `ci-chain.log`: CI's main chain in the Guix container, `check-memory-gate`, and
  `test-manifest` under the gate, on the first reader, before the review.
- `review-plants-summary.txt`, `make-plants.py`, `run-plants.sh`: the review's plants
  (Opus, read-only) on that reader: seven changelog shapes passed that should fail (a
  release at `###`, indented, appended below, given twice, numbered down, a bad date, a
  fenced heading), and five reader mutants survived (two date places, `char-numeric?` in a
  version, the oldest heading unchecked, the greatest version taken).
- `review-shape-plants-on-v2.txt`: the review's shape plants on the rewritten reader: every
  one fails but the two controls and a BOM, which Chez's decoder drops.
- `reader-mutants-v2.txt`: my sixteen mutants of the rewritten reader, the count of tests
  each failed. `n15-max-version` passes, and is equivalent: with the order held, the first
  release is the greatest.
- `ci-chain-2.log`: `make test` on the final tree, and `test-manifest` and `test-docs` under
  the gate.

My seven mutants of the first reader (the last heading taken, malformed headings skipped,
no `[Unreleased]` check, a leading zero, `char-numeric?`, a date's prefix, no date) each
failed the suite, and the real-file check failed on a manifest bumped alone, a changelog
bumped alone, and a newer release in the changelog alone.
