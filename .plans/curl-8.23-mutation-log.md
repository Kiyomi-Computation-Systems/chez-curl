# curl 8.23.0 mutation log (the `current` lane moves to 8.23.0)

The slice of [ADR-0020](decisions/0020-a-ci-lane-on-the-current-libcurl.md), amended
2026-10-26. Each mutant was applied to its own copy of the tree, and its suite ran from there:
in the Guix container (`guix`, curl 8.20.0 with GnuTLS) or in Docker `ubuntu:24.04` under the
floor's Chez (`8.23.0`, the vanilla build). A mutant passes only if its suite exits 0 on it.
The driver and every log are in `build/verify/c823/` (`mut.py`, `mut/NAME/LANE-SUITE.log`).

## The hang

The three planted a failing shared transfer, `/raw/close-before-response`, so that 8.20.0
shows what 8.23.0 did.

| Mutant | Change | Lane | Failed |
|---|---|---|---|
| `shared-fails` | the shared transfer fails | guix | the two-thread check, by name: each thread `(on-thread (transfer-error perform-failed 52 #f))` |
| `shared-fails-unguarded` | that, and the threads' `guard` dropped | guix | the same check, by name, after its 45 s bound: `unanswered-within-45-s` |
| `shared-fails-unguarded-unbounded` | that, and the bound dropped too, as the suite was | guix | nothing: the suite hung, killed at 200 s, exit 124. The defect, reproduced on 8.20.0 |

## Engines of their own

| Mutant | Change | Lane | Failed |
|---|---|---|---|
| `eight-on-suite-engine` | the eight drips on the suite's engine | 8.23.0 | the next raw transfer on it: "a cancel of a live drip" answered `(transfer-error perform-failed 55 #f)`, not cancelled |
| `pair-on-suite-engine` | the two-thread check on the suite's engine | 8.23.0 | **nothing.** With the eight drips on an engine of their own, the suite's engine pools at most one dead connection, which a retry survives. Its own engine guards against a later check that leaves more |
| `eight-thread-is-suites` | the eight drips' chunks checked against the suite's engine's thread | guix | the eight drips' check: the chunks ran on their own engine's thread |

## The reuse pin

| Mutant | Change | Lane | Failed |
|---|---|---|---|
| `reuse-five` | five drips, not eight | 8.23.0 | the reuse check: five dead connections, and the sixth try connects afresh, so it answered |
| `reuse-823-answers` | 8.23.0's row says it answers | 8.23.0 | the reuse check |
| `reuse-820-refuses` | 8.20.0's row says 55 | guix | the reuse check |
| `reuse-823-dropped` | 8.23.0's row removed | 8.23.0 | the row for this libcurl, and the reuse check; the suite printed the row |

## The text, a version row's answer

| Mutant | Change | Lane | Failed |
|---|---|---|---|
| `text-823-old` | 8.23.0's text "Nul byte in header" | 8.23.0 | the varying text, and "each varying case has different answers in two rows at least" |
| `text-measured-kept` | the shared texts keep "Nul byte in header" | guix | the nul-in-header texts check, which then names the text, not any text |
| `fits-any` | either kind of case takes either answer | guix | the shape test |
| `fits-get-only` | every case takes a get's answer | guix | 21 checks: each varying case, the row checks, the shape test, the printed row |
| `case-answer-ignores-kind` | an `error-text` case answered as a get | guix | the varying text |

## The other rows and the pin

| Mutant | Change | Lane | Failed |
|---|---|---|---|
| `url-823-old` | 8.23.0's two spaces refused with 3, as 8.20.0's | 8.23.0 | those two cases |
| `minus-one-823-zero` | 8.23.0's `minus-one-rows` at 0 | 8.23.0 | -1 through `curl-multi-setopt-long` |
| `drift-823-features` | 8.23.0's features 8.20.0's word | 8.23.0 | the drift row |
| `current-curl-stale` | `test-check-floors`' `current-curl` left at 8.20.0 | guix | the four `--current` download rows |
| `script-current-820` | `build-curl.sh` back at 8.20.0, which has no sum now | guix | the same four: "no sha256 is pinned for curl 8.20.0" |

## After the slice's review

The review (ADR-0020, amended 2026-10-26, "After the slice's review") ran two mutants that
passed or hung, and showed the reuse pin needed its drips to overlap. Then, against the fixes,
the same way (`build/verify/c823/mut-3.out`); the reuse mutants above were rerun on the
changed check.

| Mutant | Change | Lane | Failed |
|---|---|---|---|
| `reuse-five` | five drips | 8.23.0 | the reuse check |
| `reuse-823-answers` | 8.23.0's row says it answers | 8.23.0 | the reuse check |
| `reuse-820-refuses` | 8.20.0's row says 55 | guix | the reuse check |
| `reuse-823-dropped` | 8.23.0's row removed | 8.23.0 | the row for this libcurl, and the reuse check |
| `reuse-823-no-buffer` | 8.23.0's row holds 55 with no text | 8.23.0 | the reuse check: the buffer is compared |
| `reuse-outcome-drops-buffer` | `reuse-outcome` puts `#f` for the buffer | 8.23.0 | the reuse check |
| `reuse-sequential` | the eight drips submitted one after another, each awaited | 8.23.0, guix | the reuse check on both: not live together |
| `reuse-overlap-unchecked` | that, and the overlap assertion dropped | guix | **nothing**, the control: before 8.23.0 the ninth answers however the drips ran, so only the assertion holds their overlap there |
| `review-textshape` | the review's: an `error-text` answer of any length | guix | the shape test, which now rejects `(error-text "t" "u")` and `(error-text)`. It passed before the fix |
| `review-capture-raise` | the review's: a raise in a capture thread outside its capture's `guard` | guix | the capture check, by name: thread 1 answers `(raised-on-thread "planted-outside-the-guard")`. It hung before the fix, killed at 240 s |
| `capture-thread-hangs` | a capture thread that never ends | guix | the capture check, by name, after its 120 s bound: `unanswered-within-120-s` |

The two `test-curl-testing` mutants also failed eight checks that are not theirs: run outside
`make` from a copy, seven of the suite's children exit 255 having found their scratch
directory elsewhere, and one cannot find `(srfi :64)`. The unmutated copy, run the same way,
fails the same eight and no other (`mut/control/guix-test-curl-testing.log`).

Before any of these, the unchanged suites ran on 8.23.0 and failed as ADR-0020 recorded, and
`test-engine`, with its first fix, failed the two-thread check by name, 55 on both threads,
instead of hanging (`build/verify/c823/logs/main-8.23.0-test-engine-2.log`).
