# M6 slice 3's mutation log

Each mutant is a copy of a tree snapshot under `build/m6s3b/mutants/NAME/`, made by
`build/m6s3b/mutate.py`, with its `mutation.diff` (its rule on the diff's second line), its
`suites.txt` and its `how.txt`. `build/m6s3b/run-mutants.sh` ran each in the Guix container,
libcurl 8.20.0, through the copy's own `scripts/guix-env`: `make test SUITES=...`, or, for
`producer-elsewhere`, which imports `fork-thread` into the drive and so fails check-seam first,
each suite by `$CHEZ` alone. Its log is `NAME/run.log`, its verdict `NAME/results.txt`. A mutant is
killed when its run exits non-zero; each kill below was read from its log, and every one is the
test named for its rule, not another.

## Rounds

- **Round 1** (`runs/mbase1`, logs in `mutants-round1/`): 38 container mutants, 32 killed. Two
  survivors changed the build:
  - `producing-unchecked` survived because the test could not tell its refusal apart: with the
    flag off, the producer's re-entrant read put echoed bytes into the body, which then overran
    `body-length` and was refused by the same who. The test now sends that body chunked.
  - `eager-end-off` survived against an eager end-of-body call I had added. I took the call out,
    as it bent the plan's rule (the producer is called only once `room-wait` answers `#t`), and
    then `strict-alternation` was killed by the race the call had closed:
    `mutants-round1/strict-alternation/run.log`, a sized producer's eof never asked for (16 calls,
    not 17) on raw, raw-tls and h2, and a producer that gave more than its `body-length` answered
    200, never refused. So `end-at-length!` asks the producer for its end in the step whose put
    takes the length, and at the final head (ADR-0031, decision 2, which the plan's mechanism
    alone cannot hold).
- **Round 2** (`runs/mbase2`, logs in `mutants-round2/`, table `round2-table.txt`): 39 container
  mutants, 34 killed.
- **The review, then round 3** (`runs/mbase4`, logs in `mutants/`, table `round3-table.txt`): an
  Opus review (read-only) found no open blocker and four majors, each answered below; round 3 adds
  its missing mutants. 44 container mutants, 37 killed, 7 survivors, each accounted for.
  `put-reconcile-off` first ran as a mutant that did not compile (killed by check-seam's read, 2 s);
  it was remade and rerun, and survives.
- **The fix round, round 4** (`runs/r4m`, made by `round4/mutate.py`, which takes `mutate.py`'s
  table, rewrites the seven entries whose drive text the round changed, and adds 18; run by
  `round4/run-mutants.sh` in three groups, `round4/g{1,2,3}.{txt,log}`; logs in `round4/mutants/`;
  table `round4/round4-table.txt`): 62 container mutants, 56 killed, 6 survivors, each accounted
  for below; 12 lane runs of 7 lane mutants, every one killed. See "Round 4" below.
- **Round 5** (`runs/r5m`, made by `round5/mutate.py`, which takes round 4's table, rewrites the
  three entries whose text the round changed, and adds 12; run by `round5/run-mutants.sh` in three
  groups; logs in `round5/mutants/`; table `round5/round5-table.txt`): 74 container mutants, 67
  killed. `end-at-length-off` survived, so a deterministic test was added and both at-length
  mutants rerun (`round5/g-eal.log`): killed. 6 survivors, each accounted for, rerun on the final
  tree (`round5/final-survivors/`). 12 lane runs, every one killed. See "Round 5" below.

## What the review changed (between rounds 2 and 3)

- **A producer first called during `http-request`'s final read** was stepped with the state the
  head marked, so a failure there could be retried, and a second transfer submitted. The failure's
  step now marks the state from the call's own record (`final-read-unmarked`). No origin route
  fails a transfer after an early 200, once libcurl asks: it survives.
- **The port's escapes:** a held piece is put again only when `curl-token-body-count` says no
  escaped put committed it (`put-reconcile-off`); a piece the port's read takes is held before any
  other call (`take-held-late`). No high-level test can land a keyboard interrupt at a put's or a
  take's hold end, which test-upload and test-stream do at the low level: both survive.
- **The 0 ms rule had no check:** the throughput test cannot tell it under Valgrind. A seam,
  `drive-stream-waits`, counts the response side's waits by their bound, and a test requires 16 or
  more 0 ms waits for 16 puts: `strict-alternation` is now killed.
- **The cancels the producer's refusals promise** ("once its transfer is cancelled") were read only
  after the call, when the wind had cancelled anyway: the sticky tests now read the engine's live
  count inside PROC (`refuse-answer-no-cancel`, `sticky-no-cancel`, both killed). Their faults now
  fire at the producer's first call once PROC runs, not at its third, which a head slower than
  natively, under Valgrind say, would have moved.
- `produce!`'s handler forgets a raise an outer handler returned from; the tables' policy and rows
  are made under guards; a seq body's length is asserted.

## Round 3's survivors, each accounted for

- `head-check-off`, the feeding rule's head check: a head published, not yet known final, is fed.
  The check closes a window between head-wait's last look and feed!'s check, or inside feed!'s own
  room-wait; libcurl can have room after an early 303's head on 7.85.0 (the measurement's drive put
  64 KiB after one, research item 2, case c), so the window is real but narrow, and a hop's head is
  never shown to the caller, so no test can tell a producer call made in it. (My first account here,
  that no libcurl asks after a hop's head, was wrong: that holds only for a head that came before
  the first ask.)
- `resp-flag-kept`, the request side's empty wait clearing the response side's flag: the response
  side steps between every two request steps and sets its own flag afresh, so the clear changes
  nothing. The load-bearing clear is `eager-flag-kept`'s, killed by the CPU test.
- `drive-call-ignored`, the drive's own call of the producer not counted as called: at a head the
  bit says so already, since the drive calls only once libcurl has asked; it matters for a failure
  with no head after the drive called, which no deterministic origin route gives. It is then held
  only by `leg!`'s own assertion, which refuses a second transfer of a called producer's body.
- `final-fed-when-asked`: on 8.20.0 libcurl asks with the head, so the bit is always `#t`; killed on
  the 7.85.0 and 8.5.0 lanes (below).
- `final-read-unmarked`, `put-reconcile-off`, `take-held-late`: above.

## The Docker lanes' mutants

Made from `runs/mbase3` into `lane-mutants/` by `mutate-lanes.py` (mutate.py with that one
directory), run by `lane-mutants/run.sh`, `SUITES=tests/test-stream-call.sps`, each log
`lanes/lane-LANE-mutant-NAME.log`. Every one killed, by the test named for its rule:

| mutant | lane | killed by |
|---|---|---|
| `final-fed-when-asked` | floor, 7.85.0 | the held test: the 200 kept alive, never fed, 28 at its 10,000 ms bound |
| `final-fed-when-asked` | main, 8.5.0 | the same |
| `final-fed-when-asked`, round 3's copy (`mutants/`) | floor and main | the same again, on the final code (`lanes/lane-{floor,main}-mutant-final-fed-when-asked-r3.log`) |
| `row-3xx-7.85-dropped` | floor | the HTTP/2 3xx test: `(no-row-for "7.85.0" measured ((303 (text "early 303\n")) (303 "early 303\n")))` |
| `row-held-7.85-swapped` | floor | the held test: four `followed`, not `body-not-replayable` |
| `row-3xx-8.5-dropped` | main, gnutls | the HTTP/2 3xx test, printing 8.5.0's measurement |
| `row-3xx-8.23-dropped` | current | the HTTP/2 3xx test, printing `((303 (raised 28 http-timeout)) (raised 28 http-timeout))` |

## Before the last snapshot

The early lanes (`lanes/lane-*-early.log`, `runs/mbase2`, the changed suites alone) found one
version-dependent row in my own table: 7.85.0 resolves a Location of `javascript:x` as a relative
path, as test-redirect's own rows say, so the predicate's table and the "checked first" table use
`ftp://h.example/x`, no http or https on every libcurl.

## Round 3's final lanes

`runs/mbase4`, round 3's final tree: the container (`logs/container-full-final.log`) and the five Docker
lanes (`lanes/lane-{floor,main,gnutls,current,memory}-final.log`) all pass, 35 suites of 35 each;
the memory lane's check-memory-gate held its 33 cases first.

## Round 4: the fix round

Each rule the fix round added, and the mutant that holds it (`round4/round4-table.txt` has every
row; each kill below was read from its `run.log`):

| rule | mutant | killed by |
|---|---|---|
| the producer's answer held in the leg by `produce!`'s critical after thunk (M1) | `answer-slot-off` | the escape child, case A: 983,040 bytes echoed, the first wrong at 262,144 |
| the eof's removal sets the phase `ending` in its section, so `feed!` ends the body again, never calling the producer (M1) | `ending-phase-off` | case B: 18 calls, 1 after the eof, in runs 1 and 2 of 3 |
| a refusal records the call's failure, stops the leg, drops its pieces and cancels, in one section, and raises after (M1) | `refuse-order` | case C: the call returned, every later read `transfer cancelled` |
| a held piece is put again only when the body count says no escaped put committed it (M3) | `put-reconcile-off` | case D: 1,114,112 bytes echoed, the first wrong at 327,680. Round 3's survivor |
| the drive's own call counts the producer as called (M2) | `drive-call-ignored` | the cut test: `(assertion drive-stream)`, the server seeing 1 upload. Round 3's survivor |
| the check before the submit (M2) | `submit-check-off` alone survives; `call-ignored-check-off` (both) | the cut test: 3 transfers and `seen 3`, where `drive-call-ignored` alone stops at 1 |
| a failure in `http-request`'s final read is stepped from the call's own record (M2) | `final-read-unmarked` | the held cut test, on the floor and main lanes (below); 8.20.0 asks with the head, so the container cannot show it |
| one draw a transfer, the hop's step taking its head's (M4) | `hop-redraws` (the review's), `second-draw` | both draw tests |
| decision 1, a piece past the length | `long-as-assertion`, `reason-dropped` | the length test; `reason-dropped` the reasons test too |
| decision 4, a ran-out response whose body is #f | `ran-out-body-off` | the seam test through drive-stream, and the core's table |
| the port's close from another thread | `port-close-thread-unchecked` | the close test |
| a streamed call inside a critical section | `stream-interrupts-unchecked` | the critical-section test |
| `/raw/cut` and arm's mode cut | `cut-after-optional`, `cut-after-ignored`, `cut-writes`, `cut-uncounted`, `arm-after-loosened`, `arm-cut-ignored` | test-origin's cut and arm tests, each the one for its rule |

`refuse-answer-no-cancel`, `sticky-answer-off` and `end-at-length-off` are now also killed by the
escape child.

### Round 4's survivors, each accounted for

- `head-check-off` survives in the container, and is killed on 7.85.0 and 8.5.0 (below), by the held
  test's control half: the early 200, published before libcurl's first ask, saw its producer first
  called before the drive read the head, `(before-the-head 1)`, not after it. So round 3's account,
  that no test can tell, is superseded over HTTP/1.1 on those versions. Over HTTP/2 on 7.85.0 and
  8.5.0 it is unmeasured: no test there publishes a head before libcurl's first ask. Where it
  matters, its effect is over-refusal: a producer called in the window counts as called, so a 307
  or 308 that could have resent an unasked body meets `body-not-replayable`, and a retry is refused.
  No body is ever sent twice.
- `final-fed-when-asked` and `final-read-unmarked`: killed on the floor and main lanes (below).
- `resp-flag-kept`: equivalent, as round 3 says.
- `submit-check-off`: equivalent alone. The core never asks a second transfer of a called
  producer's body; `call-ignored-check-off` shows what the check stops.
- `take-held-late`: unreachable as compiled. It moves `resp-waited!` between
  `curl-token-next-piece`'s return and the piece's hold. The low level removes the piece as the last
  thing before it returns, after its section, so no section ends in that window, and no SIGINT plant
  can reach it: the plant needs a section that ends there. And cp0 inlines `resp-waited!` into two
  record writes (`$object-set!`) and two `bytevector?` checks (`round4/inline-take-held-late.txt`,
  read!'s code from its interrupts refusal on, printed by `round4/inline-dump.ss` through
  `expand/optimize-output`). The window is straight-line code, with no call and no loop header, so
  no event check: no keyboard interrupt, timer or collect request can run there. The tree's read!
  (`round4/inline-tree.txt`) differs only in the order. Nothing here turns cp0 off: the round's
  review found no lane that sets an optimize or debug level. A build that did would make
  `resp-waited!` a call, and the window reachable. The tree's own window, between that return and
  its hold, rests on the same compiler behaviour: no event check falls in it either.

### Round 4's lane mutants

Copies in `round4/lane-mutants/`, run by `round4/lane-run.sh`, `SUITES=tests/test-stream-call.sps`,
each log `lanes/lane-LANE-r4-mutant-NAME.log`. Every run killed:

| mutant | lanes | killed by |
|---|---|---|
| `final-fed-when-asked` | floor, main | the held test's control half and the held cut test, each final head never fed: 28 at its bound, 10,000 and 20,000 ms |
| `final-read-unmarked` | floor, main | the held cut test: `(assertion drive-stream)`, not the transfer's failure |
| `head-check-off` | floor, main | the held test's control half: `(before-the-head 1)` |
| `row-3xx-7.85-dropped` | floor | the HTTP/2 3xx test, printing 7.85.0's row |
| `row-held-7.85-swapped` | floor | the held test: four `followed`, not `body-not-replayable` |
| `row-3xx-8.5-dropped` | main, gnutls | the HTTP/2 3xx test, printing 8.5.0's row |
| `row-3xx-8.23-dropped` | current | the HTTP/2 3xx test, printing 8.23.0's row |

### The escape child's plant

Case A's plant first held its mutex with interrupts on. On 8.5.0, 1 run in 48 hung
(`lanes/adhoc-main-escape-main3.log`): the plant's thread, holding the mutex and sleeping, joined
a collection, while the main thread, blocked on that mutex inside the after thunk's critical
section, stayed active. That is AGENTS.md's deadlock trap. The plant now holds through
`critical-section`, as the low level's seams do, and 24 runs on 8.5.0 passed after
(`lanes/adhoc-main-escape-main4.log`, 576 cases, each run exit 0, every count zero).

### Round 4's final lanes

`runs/r4final`, the fix round's final tree, the same as `runs/r4m`, which the mutants were made from.
The container (`round4/container-final.log`) ran check-seam, check-suites, check-floors, then make test:
35 suites of 35. Four Docker lanes (`round4/lanes-final.out`, `lanes/lane-{floor,main,gnutls,current}-r4final.log`)
passed, 35 of 35 each, main's check-variadic too. So did the memory lane (`round4/lane-memory-final.out`,
`lanes/lane-memory-r4final.log`): check-memory-gate held its 33 cases, then 35 suites of 35 under Valgrind.

## Round 5: the scoped review of round 4

| rule | mutant | killed by |
|---|---|---|
| the seam records a call's token only while armed (the major) | `last-token-unarmed` | the seam's test: unarmed, 67,041,992 bytes retained after a 64 MiB body's call (`round5/retain-red.log`, the red step) |
| the armed record goes as its call ends | `last-token-kept` | the same test, armed: the token still held after the call |
| a producer never entered neither records nor cancels (case E) | `before-cancel` | the escape child, case E: `transfer cancelled` under PROC, 3 of 3 before the fix (`round5/escape-E-red.log`) |
| nothing of a piece past the length is put | `long-partial-put` | the long-piece test: the token's puts 2,000, not 1,500 |
| the long piece's irritants, as the low level orders them | `long-irritants-swapped` | the long-piece test (red on the tree before the swap, `round5/long-red.log`) |
| the eof's removal sets the phase `ending` | `ending-phase-off` | case B, now 20 of 20 (`round5/m-ending-B20.log`; the tree, 20 of 20 clean, `round5/tree-B20.log`) |
| the end asked at once once the length is taken, room or none | `end-at-length-off`, `end-at-length-off-strict` | the new at-length test: asked on room, the drive waited out the 10 s bound, one call (`round5/g-eal.log`) |
| `/raw/sunk` and answer-at's `hold`, `/raw/release` | `sunk-unrecorded`, `sunk-query-loosened`, `release-query-loosened`, `hold-ignored`, `hold-key-loosened`, `release-wakes-none`, `release-not-kept` | test-origin's sunk, release and hold tests, each the one for its rule |

`refuse-answer-no-cancel` is now also killed by the long-piece test: the caller's handler, where
the raise is made, saw a transfer still live.

### Case B made deterministic

B's answer now holds its last byte (`hold=KEY`) until the planting thread releases it by
`/raw/release`, which it does only once the response side has waited twice more after the escape,
so a read after the escape has fed by then. Before, that read often found the transfer done:
`ending-phase-off` showed in 14 runs of 20 (the review's `build/m6s3s/m-ending-B20.log`). Now 20 of
20. B no longer kills `end-at-length-off` by its old race (the transfer done before the eof was
asked), which is why that mutant first survived round 5; the at-length test now holds the rule.

### The escape child's plants

Case E first hung 1 iteration in 8 (`round5/escape-loop.log`, and the suite's run in
`round5/long-red.log`, exit 137 at the child's 120 s bound). The holder waited inside its critical
section for the main thread to go on, and a collection between deadlocked them: main stopped at the
collection's rendezvous, which waited for the holder (AGENTS.md's trap). E's window, from its
arming at the fifth piece to the next call's before thunk, is long. B, C and D had the same window,
microseconds wide. Now A and E, whose gates run inside the drive's own sections, send SIGINT to
themselves there, with no second thread. B, C and D keep a holder for the low level's sections,
but it waits on nothing the main thread does: main waits for the hold, with interrupts on, then
blocks. 20 iterations, 600 cases, all as expected, none hung (`round5/escape-loop2.log`).

### Round 5's survivors

`resp-flag-kept`, `submit-check-off` and `take-held-late` (unreachable as compiled), as round 4
says; `final-fed-when-asked`, `final-read-unmarked` and `head-check-off`, killed on the floor and
main lanes (`lanes/lane-{floor,main}-r5-mutant-*.log`), each by the same test as in round 4. All six
were rerun on the final tree (`round5/final-survivors/`, `round5/survivors-final.log`).

### Round 5's final runs

`runs/r5final`, the final tree. The container (`round5/container-final.log`) ran check-seam,
check-suites, check-floors, then make test: 35 suites of 35. Four Docker lanes
(`round5/lanes-final.out`, `lanes/lane-{floor,main,gnutls,current}-r5final.log`) passed, 35 of 35
each, main's check-variadic too. So did the memory lane (`round5/lane-memory-final.out`,
`lanes/lane-memory-r5final.log`): check-memory-gate held its 33 cases, then 35 of 35 under Valgrind.

## What is kept

Each mutant's `mutation.diff`, `run.log`, `results.txt`, `suites.txt` and `how.txt`; the tree copies
themselves were removed once the logs were read, rounds 4 and 5's alike. `runs/mbase4` is round
3's final tree's snapshot, `runs/r4final` round 4's, `runs/r5final` round 5's.
