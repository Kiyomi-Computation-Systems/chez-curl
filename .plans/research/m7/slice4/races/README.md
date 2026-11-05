# M7 slice 4: the two races CI's memory job hit on PR #45 (2026-11-05)

CI's memory job failed all three attempts at `dde5146`: test-group's raise-child (attempts 1
and 3) and test-upload's `h2-answer` body-asked cell (attempts 2 and 3)
([`../verify/results/ci-memory-dde5146*.log`](../verify/results/)). This directory measures
both on this slice's tree (`build/m7s4b/snap-ci`, `dde5146`) and main's (`build/m7s4b/snap-main`,
`a075629`), and fixes the tests.

## How it was measured

- **The lane:** [`race-gate.sh`](race-gate.sh), a copy of `../verify/memory-race.sh`'s
  container: Docker `ubuntu:24.04`, Ubuntu's 8.5.0 with OpenSSL, Valgrind 3.22, spike E1's
  threaded Chez, Node 20.10.0, pinned to two CPUs; each round runs every tree in turn on a fresh
  copy, `MODE=gate` (make test-memory) or `MODE=native` (make test). Its header gives the command.
- **The probe:** [`probe/`](probe/). `make-snaps.sh` makes `build/m7s4r/snap-{ci,main}-probe`,
  each tree with instrumented copies of its two suites (`gen_group_probe.py`,
  `gen_upload_probe.py`); the tests themselves are unchanged. Every SIGINT child of test-group
  loads `sigprobe.c`, which wraps Chez's SIGINT handler and records which thread took each signal
  and whether it was in a blocking call; the child notes its ready line, its hold's start and end
  (and the main thread's system call at the end, 202 a futex), its Ctrl-C handler with the frame
  names of its continuation, its collections, and around the call the signal is meant for. The
  interrupt script reports when it saw ready and sent the SIGINT. test-upload's body-asked rows
  print the bit, whether and when libcurl first asked (`asked-at`), and when the head was
  published (`head-at`). `analyze.py` tabulates either.
- **Planted collections:** `make_sweep.py` makes a program that runs one child many times, with
  `GROUP_TRIP` (collect-trip-bytes at ready) or `GROUP_TRIP_DELTA` (the trip D bytes past what
  generation 0 holds at ready) and `GROUP_PROBE_SLEEP` (the script's sleep before its kill);
  `delta_table.py` tabulates it.

## test-group: a collection requested inside the hold

**Measured, under the gate:** [`results/gate-{A,B,C,D}.out`](results/), CPUs 0,1 and 3,6
(P-cores) and 8,9 and 10,11 (E-cores), 5 rounds each: **0 of 20 runs failed on either tree.**
All 400 SIGINTs (10 children, 20 runs, 2 trees) reached the main thread, each while it was in
a blocking call; each handler ran where its test means, as the section ends
([`results/gate-analysis.txt`](results/gate-analysis.txt)). The script sent the SIGINT 504 to
558 ms after ready; the holds ended at least 443 ms after it (lost-child's 1 s hold), 1.44 s
after for the 2 s holds and 2.44 s for the 3 s ones. **Natively** in the same lane
([`results/native-{A,B}.out`](results/)): the same, 0 of 20 on each tree.

**The hypothesis was wrong.** A SIGINT the holder takes is dropped (`c/schsig.c`), so its
handler would never run; CI's run shows it ran, after the release, and its raise left
compounded. A late SIGINT does not give that either: sent 3.5 s after ready, past every hold,
raise-child passed, its handler run in the group's join, whose waits no guard surrounds
([`results/late-sigint-3.5s-unfixed-ci-guix.log`](results/late-sigint-3.5s-unfixed-ci-guix.log));
and swept across the release, 2.90 to 3.05 s, no placement compounded
([`results/sigint-across-release-raise-ci-guix.log`](results/sigint-across-release-raise-ci-guix.log),
both in [`results/late-and-across-analysis.txt`](results/late-and-across-analysis.txt)).

**The cause, reproduced:** a collection requested while the holder sleeps in
`call-with-engine-held`'s critical section waits for the hold to end, and so does every thread
that reaches an event check meanwhile. A main thread that met one after ready and before its
`go` blocked stalled there; the SIGINT arrived while it waited; at the release the collection
ran, then the handler, wherever the main thread had stopped. When that was inside `go`'s
checks, `call-state`'s guard (`src/http-client.sls`, compounding every condition with
`&http-exchange`, on main too) read the handler's planted `&curl-error` as the call's, and what
left the group was compounded: CI's `(raise #f #t after-release (0 0 0))`, exactly.
- With the trip at 1 KiB from ready, on this slice's tree: 3 of 5 runs, the handler in
  `call-request-of` ([`results/trip-1k-raise-ci-guix-first.log`](results/trip-1k-raise-ci-guix-first.log));
  2 of 3 with the collect-request handler's run noted, on the main thread, 0.1 ms after the hold
  ended ([`results/trip-1k-raise-ci-guix.log`](results/trip-1k-raise-ci-guix.log)).
- With the trip D bytes past ready, D 0 to 96 KiB by 4 KiB: main's tree failed at D 0 to 16 KiB,
  5 of 25, the handler in `set-url-flagged!`/`call-request-of`; this slice's tree 0 of 25
  ([`results/trip-delta-raise-{main,ci}-guix.log`](results/), [`results/trip-tables.txt`](results/trip-tables.txt)).
  Where a trip stalls the main thread moves with each tree's allocation, not with its code.
- submit-child, so stalled, **passed**: its handler escaped from `go`'s checks, nothing
  submitted, and the engine held nothing, as the test expects
  ([`results/trip-1k-submit-ci-guix.log`](results/trip-1k-submit-ci-guix.log), 4 of 4).
- turn-child, sections-child, admissions-child and resume-child ask for a collection with
  `collect-rendezvous` before their holders start; submit-child, raise-child and lost-child did
  not.

**Did this slice move it:** the race is the tests', on main too (planted trips fail main's tree
as readily). Whether a run meets it depends on where generation 0 stands as the window opens,
which the trees' allocation sets: this slice changed it, so CI's environment, never reproduced
here, may have moved into the window. No local run met it unplanted, on either tree.

**The fix** (`tests/test-group.sps`, by [`fix_group.py`](fix_group.py); `child-hold` holds its
comment): every SIGINT child splices in `child-hold`, and
- holds its mutex until the suite has sent its SIGINT: `interrupt-script` makes the file
  `GROUP_CHILD_SENT` names once its kill has returned, and the holder polls for it, 20 s at most;
  so no release precedes the signal however late the script runs;
- asks for a collection by `collect-rendezvous` before its holder starts (submit-child,
  raise-child and lost-child now, as the other four did), which leaves the 8 MiB trip far off;
- reports `quiet` when `(collections)` read as the hold starts equals the one read as the
  handler starts, and each test expects it: a stall shows as `(collected N M)`.

What each test still shows is what it showed: the handler's place is each child's own check,
now with no timing margin and no silent stall.

## test-upload: HTTP/2's answer before libcurl's first ask

**Measured, under the gate:** `h2-answer`'s bit read `#f` in **4 of 20 runs on this slice's
tree and 5 of 20 on main's** (8 of 20 on the P-cores, 1 of 20 on the E-cores). In all 9, libcurl
never asked for the body (`asked #f`, no read callable call), and the head came at its usual time,
32.6 to 34.2 ms after the submit; where it asked, the ask came about 2.5 ms before the head
([`results/gate-analysis.txt`](results/gate-analysis.txt)). Natively, 0 of 20 on each tree.
**This slice did not move it.** The hypothesis holds: the answer, written as the headers arrive,
was read before libcurl's first upload attempt, and 8.5.0, its response whole, never asked.

**A loop of the row, 20 times a run, at its place in the suite** (`probe/gen_upload_loop.py`,
`build/m7s4r/snap-uloop-*`), on CPUs 8,9 and 10,11, 3 runs each
([`results/uloop-{G,H}.out`](results/)): the unfixed row, this slice's tree, read `#f` 15 times
of 120, never asked each time, and **once hung**, asked and paused, no head before the
transfer's 20 s timeout, `(no-head not-done)`.

**A held answer hangs 8.5.0.** The first fix held the server's answer until the row saw the read
callable asked, then released it, the body left paused: its loop hung 5 times of 120
(`uloop-fix`, same logs), and 2 of 40 with the origin logging
([`results/uloop-fixp-I.out`](results/uloop-fixp-I.out)): each time the origin answered within
1 ms of the release, and the client's stream ended 20 s later, cancelled
([`results/hold-hang-origin-log-fixp-I-2.log`](results/hold-hang-origin-log-fixp-I-2.log),
keys `asked-h2-answer-1` and `-4`). Read in 8.5.0's source (`build/m7s4r/src/curl-8.5.0`,
the release tarball, sha256 `42ab8db9...0eeb`): `drain_stream` (`lib/http2.c:211`) sets a
transfer's `dselect_bits` to IN and OUT while its stream's upload is open, at the server's
SETTINGS among other frames (`:1239`); `Curl_readwrite` returns early, leaving them, while
`select_bits_paused` (`lib/transfer.c:1019`) finds OUT with the send paused, though IN is not:
so a transfer paused for sending reads nothing more until it is resumed.

**The fix:** `tests/origin.mjs`'s HTTP/2 `/answer` takes `hold=KEY`, answering once
`/raw/release?key=KEY` names it (test-origin-tls holds the route, its refusals and the hold).
The `h2-answer` row's server holds its answer; the row waits for the read callable's ask, ends
the body empty, waits for the read callable to answer the end, then releases the answer. So the
ask comes first by construction, nothing is put, and no answer lands while the send is paused.
Its loop under the gate, CPUs 8,9, 10,11, 12,13 and 14,15, 3 runs each, the origin logging
([`results/uloop-fix2-{K,L,M,N}.out`](results/), origin logs under `build/m7s4r/out/uloop-fix2-*`):
**240 of 240 bits `#t`**, the read callable answering the end each time, and the origin's answer
after the client's end every time; 12 of 12 runs passed.

## Checks of the fixes

- **Mutants** ([`mut.py`](mut.py), on copies of the fixed tree, natively in the Guix
  container; [`results/mutants-summary.txt`](results/mutants-summary.txt), each one's log and
  diff under `results/mutants/`): the copy passes test-group, test-upload and test-origin-tls.
  M5 slice 4's mutants of the rules the SIGINT children guard each fail their children's tests
  with `quiet` intact: `r4-guard-outside-section` (raise-child), `r4-record-outside-section`
  (submit-child, raise-child, resume P1 and P3), `f1-guard-outside-due` (turn-child raise),
  `turn-no-sections` (submit, raise, both turns, two resumes), `f6-one-section` (sections-child),
  `g7-admissions-one-section` (admissions-child), `r5-no-take-out` and `r7-no-look` (lost-child),
  `g1-parallel-no-closed` (resume P1), `z-parallel-last-unfinished` (P1, P3),
  `z3-go-closed-after-admit` (G). Planted: a 1 KiB trip as each hold starts fails 9 of the 10
  child tests on `(collected 77 78)` or the like, submit-child and turn-child's escape among them,
  which passed so stalled before; the SIGINT sent 3.5 s after ready passes every child
  (`control-late-sigint`), and fails five with each hold a fixed 1 s (`plant-late-fixed-hold`).
  The body-asked bit read from bytes handed fails `h2-answer`, `#f`; the origin answering a held
  `/answer` at once fails test-origin-tls's hold test on h2c and h2, and never answering it fails
  that test and `h2-answer`, `(no-head not-done)`.
- **Natively in the container,** Guix's 8.20.0: `make test`, 40 of 40
  ([`results/make-test-final-guix-8.20.0.log`](results/make-test-final-guix-8.20.0.log)).
- **The four Docker lanes,** floor, openssl, gnutls and current, test-group, test-upload,
  test-origin-tls and test-origin on the final tree: all pass ([`results/lanes/`](results/lanes/),
  [`results/lanes-final.out`](results/lanes-final.out)).
- **Under the gate,** CPUs 0,1 and 3,6, 5 rounds each, the final tree (`build/m7s4r/snap-final2`):
  test-group and test-upload **10 of 10**; test-origin-tls 4 of 10, every failure an unchanged
  `/refuse` test (`at=3` 5 times, `at=0` twice, `at=0` main's floor failure,
  `../verify/results/ci-main-floor-a075629.log`), its new hold test passing every run
  ([`results/finalgate-{P,Q}.out`](results/)). No control of the unfixed tree on these CPUs was
  run, so that race's rate there before these changes is unmeasured.

## Files

- [`race-gate.sh`](race-gate.sh): the lane. [`probe/`](probe/): the probes and their tables.
- [`fix_group.py`](fix_group.py): the test-group fix, applied once to `tests/test-group.sps`.
- [`mut.py`](mut.py), [`run-mut.sh`](run-mut.sh): the mutants and their runner.
- `results/`: every log cited, and each run's suite logs under `build/m7s4r/out/LABEL/`.
