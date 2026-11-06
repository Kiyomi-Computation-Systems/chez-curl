# M7's carried races: test-origin-tls's `/refuse`, and three suites' SIGINT children (2026-11-05)

Two races carried past M7 (`.plans/progress.md`): test-origin-tls's `/refuse` tests, which lost
their `RST_STREAM` on CI's floor job at `a075629` and under the memory gate; and the SIGINT
children of test-http-client, test-mailbox and test-engine, which hold across a SIGINT without
the `collect-rendezvous` PR #45 gave test-group's ([slice 4's races](../../slice4/races/)). The
control tree is `main` at `29f4b5d` (`git archive`, `build/carried-races/snap-main`); the fixed
tree is this branch's `tests/` (`build/carried-races/snap-fix`). Every run was pinned to CPUs 0
to 9.

## How it was measured

- **The gate:** [`race-gate.sh`](race-gate.sh), slice 4's lane: Docker `ubuntu:24.04`, Ubuntu's
  8.5.0 with OpenSSL, Valgrind 3.22, spike E1's threaded Chez, Node 20.10.0, two CPUs, `make
  test-memory`. Three lanes at once, on CPUs 0,1 and 3,6 (P-cores) and 8,9 (E-cores).
- **Natively:** [`native-loop.sh`](native-loop.sh), `make test` N times in the Guix container
  (Guix's 8.20.0 with GnuTLS, Node 24.18.0), `taskset -c 0-9`.
- **The probe of the race:** [`probe/gen_refuse_probe.py`](probe/gen_refuse_probe.py) makes
  instrumented copies of `tests/origin.mjs` and `tests/wire-probe.mjs`, which log to `RACE_LOG`
  by the wall clock: per HTTP/2 session the client's end (Node's `'end'`), this side's finish
  and close, with the bytes each handle had been handed; per refusal the route's call and the
  stream's close; per probe its send, its half-close, each chunk and its end. Nothing else
  changes, so the tests run as they are. [`probe/analyze_refuse.py`](probe/analyze_refuse.py)
  joins them by the client's port, one row per refusal;
  [`probe/extract_sessions.py`](probe/extract_sessions.py) prints a session's events.
- **The loop:** [`probe/refuse-loop.mjs`](probe/refuse-loop.mjs) runs the real origin and the
  real probe on the three `/refuse` shapes test-origin-tls sends, N rounds, outside the suite:
  idle; on two CPUs beside three busy loops; with Node's native trace (`NODE_DEBUG_NATIVE`); or
  with the origin stopped across the request (`ATS=stop0`).
- **The children:** [`sigint/gen_children.py`](sigint/gen_children.py) makes measurement copies
  of the four SIGINT children (main's), which plant a collection by the environment:
  `CHILD_TRIP`, a 1 KiB `collect-trip-bytes` just before the ready line, as slice 4's
  `GROUP_TRIP`; or `CHILD_TRIP_AFTER`, the control, the same trip set by the holder once its
  hold has ended. Each prints `(collections)` at the hold, the handler and the release, and its
  handler's frames. [`sigint/child-loop.sps`](sigint/child-loop.sps) runs one N times under the
  suites' interrupt script; [`sigint/tabulate.py`](sigint/tabulate.py) reads each run as its
  suite does. [`probe/gen_window_probe.py`](probe/gen_window_probe.py) times the mailbox child
  from its ready line to its call of the take.
- **Mutants:** [`mut.py`](mut.py) and [`run-mut.sh`](run-mut.sh), natively in the container.

## The `/refuse` race

### Counts

Each cell: refusals that lost their `RST_STREAM`, of refusals made. Main's tree, then the fixed
one. The suite's rows from the instrumented copies, the loop's from the real files.

| where | h2 at=0 | h2 at=3 | h2 at=5 | h2c, each |
|---|---|---|---|---|
| gate, main, 21 runs (7 a lane) | 3 / 21 | 4 / 21 | 0 / 21 | 0 / 21 |
| gate, fixed, 21 runs | 0 / 21 | 0 / 21 | 0 / 21 | 0 / 21 |
| Guix, main, 20 runs | 0 / 20 | 0 / 20 | 0 / 20 | 0 / 20 |
| Guix, fixed, 20 runs | 0 / 20 | 0 / 20 | 0 / 20 | 0 / 20 |
| loop, idle, main | 1 / 200 | 0 / 200 | 0 / 200 | 0 / 200 |
| loop, idle, fixed | 0 / 200 | 0 / 200 | 0 / 200 | 0 / 200 |
| loop, 2 CPUs and 3 busy loops, main | 37 / 100 | 39 / 100 | 0 / 100 | 0 / 100 |
| loop, the same, fixed | 0 / 100 | 0 / 100 | 0 / 100 | 0 / 100 |
| loop, origin stopped across the request, main | 10 / 10 | | | 0 / 10 |
| loop, the same, fixed | 0 / 10 | | | 0 / 10 |

Main under the gate failed 5 runs of 21: 2 of 7 on CPUs 0,1, 3 of 7 on 3,6, none on the E-cores
([`results/gate-main-{A,B,C}.out`](results/), [`results/gate-main-analysis.txt`](results/gate-main-analysis.txt)).
Natively in the suite it never failed in 20 runs ([`results/native-main-analysis.txt`](results/native-main-analysis.txt));
the loop's idle rate, 1 of 200, fits a race CI met once. The loop's counts:
[`results/loop/loop-summary.txt`](results/loop/loop-summary.txt), every miss's row in
[`results/loop/main-miss-rows.txt`](results/loop/main-miss-rows.txt).

### The cause: the origin drops it, not the probe

**Every refusal that lost its `RST_STREAM` had the client's end read before the stream's close,
and the frame was never written.** In the suite's 7 misses under the gate, each session read:
the refusal, with nghttp2's outbound queue holding 2 frames; then the client's end, the
session's socket handed 18 bytes, the server's SETTINGS and the ACK; then this side's finish;
then the stream's close, after the socket had ended ([`results/gate-main-missing-sessions.txt`](results/gate-main-missing-sessions.txt)).
Every refusal that kept it closed first, with 31 bytes handed by the client's end: the 13 of
the frame more. The probe read each connection to the origin's FIN: it never stopped early,
and never half-closed before its request had gone, which TCP orders ahead of its FIN.

**Node's native trace shows where it went** ([`results/loop/native-trace-sessions.txt`](results/loop/native-trace-sessions.txt),
two sessions whole in [`results/loop/native-trace-main-pair.txt`](results/loop/native-trace-main-pair.txt)
and [`-node20-pair.txt`](results/loop/native-trace-main-node20-pair.txt)): on Node 24.18.0, 5
misses of 10, and on Node 20.10.0, 6 of 10, each the same.

1. The request and the client's close_notify came in one read. TLSWrap's `ClearOut` decrypts
   the HEADERS, which the session takes at once, then reads the close_notify, and in the same
   call reports the end (`SSL_ERROR_ZERO_RETURN`, `EmitRead(UV_EOF)`).
2. The route refuses as the HEADERS are taken, `stream.close(REFUSED_STREAM)`. Node's
   `Http2Stream::SubmitRstStream` first writes what is pending, the SETTINGS and the ACK of the
   client's, so the frame cannot jump them; then queues the `RST_STREAM` in nghttp2.
3. TLSWrap's write of those 18 bytes finished at once, but TLSWrap reports a finished write
   only at the next immediate (`EncOut`: "Simulate asynchronous finishing, TLS cannot handle
   this at the moment"). Until then the session's write is in progress, so the `RST_STREAM`
   waits.
4. The end, step 1's, reaches the TLS socket, which ends its side at once: Node's servers are
   not half-open, so `'end'` ends the writable side (`DoShutdown`: `SSL_shutdown`, then the TCP
   shutdown).
5. At the immediate the write completes, and the session serializes the `RST_STREAM` (the
   stream's close comes here) and hands it to TLS: `Writing 13 bytes, written = -1 ... Got SSL
   error (1), returning UV_EPROTO`. The frame never left.

Every session that kept the frame read its close_notify in a later read, after the immediate.
**h2c never raced**: a TCP write completes at once, so the `RST_STREAM` follows the ACK in the
same read, and libuv reads a FIN in a read of its own, after the data. **`at=5` never raced**:
it refuses 300 ms after the session's first writes, with nothing pending, so the frame goes in
the read that refuses. Source read: Node 20.10.0's `src/crypto/crypto_tls.cc` (`EncOut`,
`DoShutdown`, `ClearOut`), `src/node_http2.cc` (`SubmitRstStream`, `SendPendingData`,
`ConsumeHTTP2Data`), `src/env.cc` (`RunAndClearNativeImmediates`), fetched to
`build/carried-races/node-src/`.

### The fix

`tests/origin.mjs`: both HTTP/2 servers are half-open (`allowHalfOpen: true`), and each
session's socket, at its client's end, ends at the next immediate (`h2EndNext`). Node runs its
native immediates first, in that check phase, and drains whatever they queue, so TLSWrap's
completion, then the session's write of the `RST_STREAM`, come before it. The face
documentation says so. A write the kernel holds, to a client that has stopped reading, can
still be in progress then; no suite makes one. A first version also waited for nghttp2's
outbound queue to empty and for each refusal's close, rechecked at each immediate: rebuilt
([`make_v1.py`](make_v1.py)), test-origin-tls passed it with either wait removed, or both, so
neither was held, and it was not kept ([`results/v1-waits/`](results/v1-waits/)).

**test-origin-tls holds it by a new test,** on both faces: the probe sends the preface, then,
2000 ms on, the SETTINGS and HEADERS of `POST /refuse?at=0` and its half-close, while the origin
is stopped (SIGSTOP to its pid) from 300 ms after the probe connected to 3000 ms after, so the
request and the client's end come in one read. It expects the `RST_STREAM` then eof, the stop
begun before the request went (the probe's line read under 1700 ms after its spawn, its clock
less), and the answer after the stop (the ACK 2900 ms or more after connected). Main's origin
failed it on h2 10 runs of 10 in the loop, and in the suite (`o0`, below); h2c passed either
way. The fixed tree's runs under the gate met the unforced race too, and kept the frame: on h2,
`at=0` 2 times of 21 and `at=3` once read the client's end first, as main's misses did, and the
`RST_STREAM` still came, written before this side's finish ([`results/gate-fix-end-first-sessions.txt`](results/gate-fix-end-first-sessions.txt),
with the 21 forced ones). No route's answer changed, so test-origin is as it was.

## The SIGINT children

### Can the stall reach them

Main's children, natively, 10 runs each with a 1 KiB trip planted at ready, 10 with the control
(the trip set after the hold), 5 with none ([`results/children/main-native-table.txt`](results/children/main-native-table.txt),
the runs in `main-plant-1k-native*.log`):

| child | planted | control | none |
|---|---|---|---|
| test-http-client escape-child | 10 pass, a collection in each hold | 10 pass, quiet | 5 pass |
| test-http-client raise-child | 1 fail, `(raise #f #t ...)`, 9 pass, a collection in each | 10 pass | 5 pass |
| test-mailbox, take | 5 fail: `before` 2, `returned` 3; 5 pass, 2 with a collection | 10 pass | 5 pass |
| test-mailbox, deliver | 4 fail: `before` 3, `returned` 1; 6 pass | 10 pass | 5 pass |
| test-engine's interrupt child | 10 pass, handler 506 to 555 ms | 10 pass, 508 to 558 | 5 pass |

- **test-http-client, yes.** Both children hold the engine's mutex for a fixed 3 s inside
  `call-with-engine-held`'s critical section. A collection asked for after ready waited for
  the hold, and stalled the main thread with it, before its submit blocked; its handler ran
  after the release where it had stopped. raise-child's ran in the call's request building
  (`call-request-of` among its frames) and its raise was compounded: CI's test-group failure,
  here. escape-child passed every time: its line, `(escape escaped after-release cancelled)`,
  cannot show where the handler ran.
- **test-mailbox, yes, and it is M5's `escape before`.** The child holds the mailbox's mutex
  for 1 s. Stalled before the take, the handler ran there: `before`. Stalled before its ready
  line, the take returned the token before the signal came: `returned`.
- **test-engine, no.** Its child holds nothing: the main thread awaits with sleeps outside every
  critical section, the engine waits in `__collect_safe` polls. With the trip planted, 17 to 21
  collections ran during each await, and the handler came as early as without.

### The fixes

As test-group's `child-hold`, with a datum of the same kind (M7 slice 4's races):

- **test-http-client:** `child-hold`, its own copy, spliced into both children: each child
  `collect-rendezvous`es before its holder starts, the holder holds until the suite's
  interrupt script has sent the SIGINT (the file `HTTP_CLIENT_CHILD_SENT` names, made once its
  kill has returned), and each line carries `quiet`, the hold's `(collections)` equal to the
  handler's. The tests expect `(escape escaped after-release quiet cancelled)` and `(raise #t #f
  after-release quiet cancelled)`.
- **test-mailbox:** `tests/mailbox-escape.sps` the same, by `MAILBOX_CHILD_SENT`; the suite's
  interrupt script makes the file; the test expects `(escape lost quiet #f #t (response 200))`.
- **test-engine:** unchanged.

What each still shows: the handler's place, now with no timing margin at the release and no
silent stall. The signal always comes before the release, so `after-release` means the handler
ran as the section that waited on the mutex ended, and `before-release` that the signal came
before it blocked; `quiet` means no collection ran between the hold's start and the handler.
The rendezvous leaves the next collection 8 MiB of allocation away, where the window allocates
about 115 KiB (test-http-client) and 87 KiB (test-mailbox), each from rendezvous to handler
([`results/children/alloc-probe-native.txt`](results/children/alloc-probe-native.txt)).

### The deliver-escape child's timing

Its precondition: the take has blocked inside its critical section when the SIGINT comes, about
500 ms after its ready line is read. **Measured, it held with that margin:** from the ready line
to the call of the take or the delivery, 0.025 to 0.071 ms natively in 40 runs, 0.032 to 0.050
ms beside 24 busy loops in 40, and 0.046 to 0.079 ms under the gate in 42
([`results/native-fix-window.txt`](results/native-fix-window.txt),
[`results/children/window-loaded.log`](results/children/window-loaded.log),
[`results/gate-fix-window.txt`](results/gate-fix-window.txt)). What failed it was the stall, a
1 s hold away; with the rendezvous no collection is due there. Should the precondition fail, the
child reads `before`, never `lost`: a failure, never a pass. So no more is done.

### Mutants

Each a copy of the final tree with one change, natively in the Guix container, CPUs 8,9
([`results/mutants-summary.txt`](results/mutants-summary.txt), with each failing test's actual
value; each one's log and diff under [`results/mutants/`](results/mutants/)). The baseline
passes all five suites.

- **The route,** test-origin-tls: `o1`, no `RST_STREAM`, the stream left open; `o2`, the wrong
  code, `INTERNAL_ERROR`; `o3`, the wrong stream, an `RST_STREAM` `REFUSED_STREAM` on a stream
  it pushed, 2, the request's left open. Each fails every `/refuse` test on both faces, the new
  one among them, and nothing else.
- **The end,** test-origin-tls: `o0`, main's origin whole; `o4`, the end at once, half-open
  kept; `o5`, Node's own end, the servers not half-open; `o6`, the end at the next tick, before
  the immediates. Each fails the new test on h2, reading the SETTINGS and the ACK, then eof,
  with both its evidence data as expected, and nothing else: natively the unforced tests do not
  meet the race.
- **The drive's critical section,** test-http-client: `h1`, the token recorded after the
  submit's section, and `h3`, the submit in no section of its own, leave the transfer live,
  `still-live`, in both children (`h3`'s raise compounded too); `h2`, the refusal guard around
  the section, compounds the raise, `(raise #f #t ...)`.
- **The take's order,** test-mailbox: `m1`, the take looks inside its section and takes the
  token out after it, reads `before` for take and deliver; `m2`, the delivery's callback run
  inside the take's section, reads the callback called, `#t`.
- **The fixes' own data:** `f1`, a collection planted in the http-client children's holds,
  fails both on `(collected 77 79)` and `(collected 77 78)`, where escape-child's line would
  otherwise pass; `f2` and `f2b`, one planted in the mailbox child, 64 KiB allocated after the
  trip, at its ready line or as its hold starts, fail on `returned (collected 57 #f)`: the main
  thread stopped short of its ready line, and the hold ran to its 20 s bound. `f4`, the
  mailbox's hold back to a fixed 1 s and the SIGINT 3.5 s after ready, fails, `returned`; `f5`
  and `f6`, the SIGINT 3.5 s after ready with the holds until sent, pass, as they must.
- **Two survive, and say what the tests cannot see.** `f2a`, the bare 1 KiB trip at the mailbox
  child's ready line, passed: just after the rendezvous the main thread allocates too little
  for the trip to fire before it blocks, so the plant never landed (a planting trap, below).
  `f3`, the http-client children's holds back to a fixed 1 s and the SIGINT 3.5 s after ready,
  passed: their handlers ran in the await, and their lines read as at the submit's section.
  Their verdicts mean the section's end only because the signal comes before the release,
  which the hold until sent now guarantees.

## Checks of the fixes

- **Under the gate, two CPUs:** test-origin-tls, test-origin, test-http-client, test-engine and
  test-mailbox, on the fixed tree uninstrumented, 4 rounds on each of CPUs 0,1, 3,6 and 8,9:
  **12 of 12 runs passed every suite** ([`results/finalgate-{A,B,C}.out`](results/)). The
  instrumented fixed tree, test-origin-tls and test-mailbox, 21 of 21 (above).
- **Natively in the container,** Guix's 8.20.0: `make test`, **40 of 40**
  ([`results/make-test-native-fix.log`](results/make-test-native-fix.log)); the five suites, the
  mutants' baseline ([`results/mutants/baseline.log`](results/mutants/baseline.log)); and the
  instrumented two 20 times, every run passing.
- **The four Docker lanes,** floor 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, 8.23.0,
  `make test` whole on the fixed tree, CPUs 0-4 and 5-9: **40 of 40 on each**
  ([`results/lanes/`](results/lanes/)). A first run, on a snapshot that left out `.plans/`,
  failed test-collect-safe's citation checks on every lane, as it must: it reads
  `.plans/decisions/`. The rerun has main's.

## For the records

- **A trap, reproduced:** Node's HTTP/2 over TLS loses an `RST_STREAM` it queued behind a write
  in progress when the client's close_notify comes in the request's read (above; the new test,
  and `o0`, `o4` to `o6`).
- **A trap, reproduced:** a planted collection lands only where allocation crosses the trip:
  `f2a` passed with a bare 1 KiB trip set just after the rendezvous, `f2` failed with 64 KiB
  allocated after it.
- **The stall's trap, met by two more suites:** test-http-client's children (raise-child
  compounded, escape-child passing stalled) and test-mailbox's (M5's `escape before`); and a
  child whose line reads the same wherever its handler ran needs the signal before the
  release (`f3`).
- **Comments:** the suites' own, in `tests/`: `child-hold` in test-http-client,
  `tests/mailbox-escape.sps`'s header, the new test's in test-origin-tls, and the HTTP/2 faces'
  in `tests/origin.mjs`.

## Files

- [`race-gate.sh`](race-gate.sh), [`native-loop.sh`](native-loop.sh), [`lanes.sh`](lanes.sh)
  and [`lanes-in-docker.sh`](lanes-in-docker.sh) (the four Docker lanes, `build/m7s4b`'s copy,
  pinned): the lanes, run from `build/carried-races/`.
- [`probe/`](probe/), [`sigint/`](sigint/): the probes, the loop, and their tables.
- [`fix_http_client.py`](fix_http_client.py), [`fix_mailbox.py`](fix_mailbox.py): the
  children's fixes, applied once.
- [`mut.py`](mut.py), [`run-mut.sh`](run-mut.sh): the mutants and their runner;
  [`make_v1.py`](make_v1.py): the fix's first version, rebuilt, and its waits removed.
- `results/`: every log cited. Each run's suite logs and whole race logs are under
  `build/carried-races/out/LABEL/`.
