# The carried items' hand-backs, checked

My checks of the two agents' work on `fix/m7-carried`, 2026-11-05: the races agent's
([`../races/`](../races/)) and the guard agent's, measurement then build
([`../guard/`](../guard/)). The guard's reruns are in [`../guard/verify/`](../guard/verify/).

## The guard: measurement

- **The guard's rewind, in pure Chez,** rerun: the same four lines as its log
  (`../guard/results/guard-rewind.log`).
- **The SIGINT matrix,** on today's copy and on option (a)'s, rerun
  ([`sigint-today-rerun.log`](../guard/verify/sigint-today-rerun.log),
  [`sigint-a-rerun.log`](../guard/verify/sigint-a-rerun.log)): each matches its log line for
  line, timings aside. On (a): 8 rows `(raised (the-planted-condition))`, 16 `(returned 200)`,
  8 `(raised (non-condition #f))`.
- **Q2's stalls,** counted from its logs by `no-head`: 15 rows, every one 8.5.0's, 9 native of
  4,760 and 6 under Valgrind of 800, as its README tables them.
- **Its mutants,** tallied from its suite logs: the three new ones pass test-http-client,
  test-group and test-stream-call, 220 tests; `a-no-compound` fails 13.
- **A large copy holds a Ctrl-C** ([`copy-hold.sps`](../guard/verify/copy-hold.sps),
  [`copy-hold.log`](../guard/verify/copy-hold.log)), my own probe, two runs: a Ctrl-C raised
  just before a 256 MiB `bytevector-copy` ran 206 to 208 ms later, `string-copy` 228 ms,
  `string->utf8` 142 ms; the 4 KiB-piece control 0.0 ms. A first version timed a collector's
  gaps, and its pieces control showed 205 ms too: a collection just after a copy moves the new
  object, so the Ctrl-C's wait is the measure.

## The guard: build

- **The patch** (`build/carried-guard/build.patch`) dry-ran clean on the tree, then applied.
- **On its copy:** test-call-checks 22 of 22 and test-group 65 of 65; on `build-today`, the old
  `call-state` with the seam kept, test-call-checks failed 20 of 22 and test-group 2
  ([`suites-build-rerun.log`](../guard/verify/suites-build-rerun.log),
  [`suites-build-today-rerun.log`](../guard/verify/suites-build-today-rerun.log)).
- **Its memory gate:** 5 rounds of 5, each of the four suites passing
  (`../guard/build/lane-openssl-memory-*.log`).

## The races

- **The tree's changes** are the five files the agent named in `tests/`, nothing else of
  `src/`, the Makefile, `scripts/` or the records.
- **Mutants rerun** ([`mutants/`](mutants/), through its `run-mut.sh`): `o0-main-origin`,
  `main`'s origin under the new test, fails it on h2; `f1-plant-trip-http-client` and
  `f2-plant-trip-mailbox` fail their suites; `f2a-plant-bare-trip-mailbox`, a 1 KiB trip with
  nothing allocated after it, passes, as the agent found.

## Both together

- **`make test` in the Guix container**, both agents' changes and the patch applied: 41 of 41
  ([`make-test-guix-8.20.0.log`](make-test-guix-8.20.0.log)).

## The review's fix round

- **`make test` in the Guix container** on the fixed tree: 41 of 41
  ([`make-test-guix-8.20.0-fix.log`](make-test-guix-8.20.0-fix.log)). After it I added one
  comment to `(http-client)`'s header, on a group's next hop; check-seam, check-suites,
  test-call-checks and test-group passed after it.
- **The review's probes on the fixed tree** ([`review-probes-fixed-rerun.log`](review-probes-fixed-rerun.log)):
  a 302 swept 1,300 to 2,300 ticks, in an engine and under a timer, no re-entry refusal; a long
  URL's Ctrl-C 0.03 ms at 8 M to 64 M chars, where it was 117 to 860 ms
  ([`long-url-hold-rerun.log`](long-url-hold-rerun.log)). Before the round, on the combined
  tree, 1,380 to 1,700 ticks gave 42 and 104 re-entry refusals
  ([`redirect-step-rerun.log`](redirect-step-rerun.log)).
- **Mutants rerun:** `step-pre` 10 failures and `cap-off-by-one` 2, as the builder counted;
  `submit-pre` 5, one more than its 4: go's step sweep's evidence read `(#t #t #f)`, no expiry
  found after a step, its property held (`mutant-*-rerun.log`). On the tree, test-call-checks
  passed 3 of 3 run at once in three copies (`call-checks-parallel-*.log`).
- **A group's next hop:** the tally copy, its handler slowed 100 ms, 10 runs an entry: go and
  `http-parallel` started 2 every time, `http-request` and `call-with-response-port` 1
  ([`group-next-hop-tally.log`](group-next-hop-tally.log)).

## PR #47's memory failure: test-unsupported's flip test

- **CI at `473b1b4`** ([`ci/ci-memory-473b1b4.log`](ci/ci-memory-473b1b4.log)): test-unsupported's
  list's-string flip test read `(refused)`, only refusals of 300, where `(refused whole)` is held;
  Valgrind 0 errors. The other seven jobs passed.
- **Under the gate,** `race-gate.sh` (`../../slice4/races/`), five `--rm` containers at two
  pinned CPUs each, four rounds: `main`'s tree failed 6 of 20, the branch's 5 of 20, the
  list's-string test every time ([`flip/gate-unsupported-*.out`](flip/)). So not the branch's.
  test-transfer-tls's CA-file flip test, the same shape, four containers more: 16 of 16 on each
  tree ([`flip/gate-transfer-tls-*.out`](flip/)), left as it is.
- **The fix:** test-unsupported's `race` loop sleeps 1 ms after a refusal, as test-transfer's flip
  tests do: 20 of 20 under the gate ([`flip/gate-unsupported-fix-*.out`](flip/)), and natively in
  the container. Under a mutant that lets CR through the hatch's `text-fault`
  ([`flip/mutant-cr-not-line-break.diff`](flip/mutant-cr-not-line-break.diff)), both flip tests
  fail, beside the two position tests ([`flip/mutant-cr-not-line-break.log`](flip/mutant-cr-not-line-break.log)).
