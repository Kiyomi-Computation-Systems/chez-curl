# Adversarial review of `fix/m7-carried` (2026-11-05)

Read-only review of the working tree against `main` at `29f4b5d`: the diff, `tests/test-call-checks.sps`
and `research/m7/carried/`. Probes ran on copies in `build/carried-review/` (`tree/`, an rsync of the
working tree; `mut-outside/` and `mut-noseam/`, one change each), in each copy's own Guix container.
Every number below comes from a log in [`results/`](results/). The large sweep logs are gzipped, so read
them with `zcat`.

## Findings

### Major

**M1. The class that call-state's section closed still happens at a redirect's step.** `drive-exchange`
runs `exchange-step` with interrupts on, and so does `drive-stream` (`drive.sls:340`, and `:933` to
`:997`). It runs between one hop's await and the next hop's submit. For a redirect, `exchange-step`'s
`follow` parses the Location and the URLs it compares (`exchange.sls:784` to `:811`). Two of those parses
sit inside `(guard (e ((curl-url-error? e) ...)))`, which declines every other raise and so rewinds into
the parse's critical wind. By reading, a group's step is safe, because `turn!` runs `step-token!` in a
section; it was not measured.

- **Reproduced** with [`probe/redirect-step.sps`](probe/redirect-step.sps). The call is `http-get` of
  `/redirect/302?to=/status/200`, swept a tick at a time from 1 to 8,000:
  - **inside an engine:** after the resume, 1,498 of 8,000 fuels raised `call-with-parsed-url`'s
    re-entry refusal (`results/redirect-step-engine-1.log.gz`);
  - **under a timer:** the handler raised `'tick` continuably and the caller's handler returned from it.
    The call should have resumed. Instead, 679 of 8,000 tick counts raised the same refusal
    (`results/redirect-step-timer-1.log.gz`).
  - **control:** the same sweeps of `/status/200`, which does not redirect, gave 0 of 8,000 for each
    (`results/redirect-step-*-control.log.gz`).
- **Not a regression.** The branch does not touch `exchange.sls` or the drive's step. But the records
  claim more than holds:
  - the ledger says "Four are fixed", with call-state's guard among them;
  - global-constraints says "never inside the URL parse's critical wind";
  - the header of `http-client.sls` says an engine's expiry fails a call only "in its await", and that
    the call then raises cancelled;
  - README.org says a streamed call's resumed reads "raise that cancel".

  None of these holds for a call that redirects. Neither brief asked where else this mechanism lives.
- **Fix.** Give `drive-exchange`'s and `drive-stream`'s steps the pattern the groups already use: each
  `exchange-step` (and `exchange-steps-past?`) runs in a `critical-section`, under a `#t` guard that
  answers as data, and the raise comes after the section ends. Measure a step's hold first. If this is
  not done in this branch, then before merging:
  - carry it in `progress.md`, citing these logs;
  - narrow the global-constraints bullet to "the checks' URL parse";
  - add the redirect step to the engine and handler paragraphs of the `http-client.sls` header.

**M2. The checks' hold grows with the caller's input, and nothing bounds it.** The ADR says "the
longest new holds are at sizes the documentation names: 0.83 s for a 16 Mi-char form value, 0.27 s for
a 7.9 MB URL". That reads as if a URL's hold stops at libcurl's 8,000,000-byte cap. It does not. A longer
URL is still copied, scanned and encoded in Scheme inside the section before libcurl refuses it as
`malformed-input`.

- **Measured** with [`probe/long-url-hold.sps`](probe/long-url-hold.sps), two runs
  (`results/long-url-hold.log`). A SIGINT sent at the checks' start waited:

  | URL length | Ctrl-C waited |
  |---|---|
  | 8 M chars | 114 to 121 ms |
  | 16 M | 232 to 235 ms |
  | 32 M | 484 to 486 ms |
  | 64 M | 871 to 891 ms |

  Every one of these URLs was refused. A form value scales the same way
  ([`probe/long-form-hold.sps`](probe/long-form-hold.sps), `results/long-form-hold.log`): 16 M chars
  0.46 s, 32 M 0.86 s, 64 M 1.63 s.
- **Before the branch,** those Scheme loops made event checks, so Ctrl-C was answered during them. The
  guard README's `results/cost-today.log` shows it: 0.02 ms for a 16 Mi-char form value, and 3.8 ms for
  a 7.9 MB URL. The primitive copies held Ctrl-C then too.
- **The hold is wider than Ctrl-C.** AGENTS.md's stall trap applies: once a collection falls due during
  the hold, every thread stops at its next event check. That includes the engine's thread, and with it
  every transfer the engine drives. The header and the ADR say only "Ctrl-C and other threads'
  collections".
- **Fix.**
  - Refuse a URL longer than 8,000,000 chars before the section. Its UTF-8 bytes are then more than
    libcurl's cap, so libcurl would refuse it anyway. This caps a URL's hold near 0.27 s.
  - In the header and the ADR, say that the other holds grow linearly with no bound, at about
    25 to 50 ms per Mi chars of form value, and that a caller who takes sizes from untrusted input should
    bound them first.
  - Say that every thread stalls once a collection falls due.

### Minor

**m1. The low level has the same trap in `curl-submit`, for a request whose proxy is a URL.** A direct
`(curl)` caller submits with interrupts on. `check-proxy-url`'s guard (`transfer.sls:3795`) takes
`&curl-url-error` alone, around `proxy-url-reading`'s critical wind. Measured with
[`probe/submit-proxy.sps`](probe/submit-proxy.sps), from 1 to 3,000 ticks:

- a timer's continuable `'tick` became `proxy-url-reading`'s re-entry refusal at 375 of 3,000
  (`results/submit-proxy-timer.log.gz`);
- inside an engine, the resumed submit raised the refusal at 579 of 3,000: 375 from `proxy-url-reading`
  and 204 from `call-with-parsed-url`, the checks' URL parse (`results/submit-proxy-engine.log.gz`).

`(curl)`'s comments say nothing about handlers or engines during a submit. The high level is safe here,
since its submits run in sections.

- **Fix:** give that guard `#t`, answer as data, and raise after it; or document it, and carry it.

**m2. test-origin-tls's new test cites a count that no kept log shows.** Its comment (`:1106`) says
"Main's origin failed this on h2 6 runs of 6". The kept logs show:

- the loop's forced variant failed 10 of 10 (`races/results/loop/stop0-main.log`);
- mutant `o0` failed the suite 1 of 1 in each of its three kept runs (`races/results/mutants/`,
  `build/carried-races/out/mutants-o0.out` and `verify/mutants/`).

- **Fix:** cite those counts.

**m3. The `stopped-before-the-request` verdict does not measure what it names.** It reads `late < 1700`.
That is how late the probe's line was read, so it counts neither the 300 ms pause oversleeping nor the
time `kill -STOP` takes to spawn and return. The ACK check (2,900 ms or more after the connect) does
catch a stop that came late. So a late stop fails the test; it never makes it pass falsely.

- **The margin, measured** by an instrumented copy ([`probe/margin-instrumentation.diff`](probe/margin-instrumentation.diff),
  `results/origin-tls-margin-*.txt`). The STOP had returned this long after the probe connected, by the
  probe's clock, against the 2,000 ms send:

  | run | STOP returned | ACK after connect |
  |---|---|---|
  | native | 342 to 349 ms | 3,005 to 3,006 ms |
  | 2 CPUs beside 3 busy loops | 350 to 390 ms | 3,006 to 3,014 ms |
  | under Valgrind, 2 CPUs | 372 to 377 ms | 3,041 to 3,047 ms |

  That leaves about 1,600 ms of room, and the suite passed 163 of 163 in all 7 runs. The flagged margin
  is ample.
- **Fix:** time the STOP's return, and assert it is under 2,000 ms in place of `late < 1700`.

**m4. test-call-checks's sweep evidence passes even if the seam is never called.** `sweep` treats a call
that completed as "after the end". With both `run-checks-gate!` calls removed (mutant `mut-noseam`,
[`probe/mut-noseam.diff`](probe/mut-noseam.diff)), all 8 sweep tests still passed:

- with no marks, no fuel can count as "inside", and the section still blocks the re-entry refusal;
- an unexpired `/status/200` call completes from fuel about 1,221 (`results/redirect-step-engine-control.log.gz`),
  so the evidence test reads `(crossed ())`.

The SIGINT and timer tests failed, 12 of them (`results/call-checks-mut-noseam.log`), so the suite as a
whole holds.

- **Fix:** the evidence should require the marks at fuel F to be `(start end)`, not `completed`.

**m5. README.org's 8.5.0 bullet says "a read waits for the timeout".** No stall measurement read the
body: `paused-held.sps` waits with `curl-token-head-wait` alone. What the logs do show is that the stall
lasted until the transfer's timeout, 4 of 600 (`guard/results/lane-*-held-long.log`).

- **Fix:** write "the transfer can wait until its timeout", or measure a read.

**m6. go's export comment (`http-client.sls:378-380`) says a handler's raise "starts no call".** That is
true only for a raise that leaves. A continuable one that the caller's handler returns from resumes `go`,
which then starts the call: test-call-checks's go `resume` rows hold `(returned 200)` and 1 transfer.

- **Fix:** "a raise that leaves starts no call; a continuable one a handler returns from resumes it".

**m7. test-group's recheck test (`:1809` to `:1819`) still says engine-block in PREPARE is "where a real
expiry can land", "in its checks".** A real expiry that runs out in the checks now lands just after
them, before go's entry. The recheck can still be reached that way, so the test is still meaningful.

- **Fix:** reword its name and comment to "in or just after its checks".

**m8. `h2EndNext`'s comment names a write the kernel holds as the one loss left.** test-origin-tls's own
comments name more:

- at `:502-506`, a stream body over 16 KiB, written one write at a time;
- at `:1538-1542`, `/mirror`'s closing empty DATA.

Both are writes chained on drains, and a client's half-close can still cut them. The fix does not change
that.

- **Fix:** add a sentence to the comment.

## The briefs

- **The guard brief scoped the question to `call-state`.** It said "the submit path is already right",
  but never asked where else a declining guard wraps a critical wind, or where else URL parses run with
  interrupts on. So the M5 §10 class went down in the records as closed, while it reproduces at a
  redirect's step (M1) and in the low level's submit (m1).
- **The guard brief asked for the cost at sizes, not as a function of size.** So no one asked what bounds
  a hold. The measured points read as maxima (M2).
- **The races brief said "fix it so it cannot race".** The fix closes the measured order. A write still
  pending past the next immediate can still be cut (m8); the agent says so for writes the kernel holds.
- **The races brief put call-state's guard out of scope**, and the guard brief left the tests to the
  races agent. Each agent ran its mutants on its own tree: the races agent on `main`'s `src/`, the guard
  agent on `main`'s tests plus its own. Neither ran on the combined tree. I found no verdict that the
  combination changes, because the files are disjoint and raise-child's compounded failure can no longer
  happen. Still, the verify README could say that the mutants were not rerun on the combined tree.
- **Neither brief asked for timing margins under the gate.** The 1,700 ms flag (m3) had to be measured
  here.
- **The Mac.** test-call-checks and the new test-origin-tls test have not run on the Mac. Its `make test`
  is due before the PR.

## Checked and found sound

1. **The critical section's contents, as code in `call-request-of`, `call-body`, `string-pairs`,
   `form-encode`, `make-curl-request`'s `checked-request`, `snapshot`, `credentials-copy`, `path-copy`,
   `curl-url-part`, `curl-url-append-query` and `curl-request-check`'s `request-checks`:**
   - **No waiting.** There is no file, network or `getenv`; the CA environment and the backend are the
     load's recorded values (`native.sls:1330` to `:1372`).
   - **No caller code.** A producer is stored, never called. The predicates are record predicates of
     sealed types. `equal?` and `member` see only libcurl's strings, so no record type's equal procedure
     runs.
   - **Mutexes:** three, the counters', `owners-lock` and memory's. Every hold of each goes through
     `locked`, with interrupts off and no wait, and none nests inside another, so their order cannot
     deadlock. Native was loaded when the session was made, so no library body runs first inside the
     section.
   - **Escapes:** the only way out is a raise, and the guard takes every raise.
   - **Unbounded allocation** is M2's point. The garbage waits for the section to end, as the guard
     README measured.
2. **What the `#t` guard takes:**
   - The checks raise no non-conditions of their own. Conditions are compounded as before.
   - Every handler is deferred: keyboard, timer, collect-request and signal handlers, and an engine's
     expiry. No handler can land inside.
   - A pending Ctrl-C runs in the section's `enable-interrupts`, after the guard. A continuable raise
     that is returned from resumes the call. A refusal is raised with `raise`, non-continuable, as
     before.
   - A Ctrl-C that escapes right after the section drops `made`, which holds no native object.
   - Rerun: mutant `mut-outside`, the guard around the section, fails the 8 SIGINT tests
     (`results/call-checks-mut-outside.log`), as the guard README says.
3. **The tests:**
   - test-call-checks passed 22 of 22, then 5 of 5 on 2 CPUs beside 3 busy loops
     (`results/call-checks-loaded-*.log`).
   - Its children hold until the signal is sent, check `quiet`, and print their counts.
   - The child-hold changes to test-http-client and test-mailbox keep what each test held, and add
     `quiet`. Their numbers (115 KiB and 87 KiB) match `races/results/children/alloc-probe-native.txt`.
   - test-group's sweeps are only tightened, and no old test asserted the old compounding.
4. **The origin's half-open change:**
   - Before the change, Node's own end came at once on the client's FIN. It now comes one immediate
     later, never earlier, so a test can only see more of an answer, not less. The routes whose answer
     waits past a client's end (`/answer?hold=`, `/answer-at`, `/refuse?at=5`) are sent their
     half-close only after the answer, as before.
   - A client that never ends, libcurl among them, is unaffected.
   - By reading: the `'end'` listener is attached as the session is made, before any read.
   - It passed on Node 20.10.0 and 24.18.0, and under the gate. Node 22 was not run.
5. **The records:**
   - I checked these against their logs, and each is backed: ADR-0025's 3,023, 881, 5,600, 647 and 20 of
     22; the header's ranges, against `cost-a.log` and `build/cost-build.log`; the 9 of 4,760 and 6 of
     800 in traps.md, AGENTS.md and progress.md, recounted from the ten `lane-*-held*.log` here; 208 ms
     (`verify/copy-hold.log`); 5 of 21, 76 of 200 and 1 of 400; and the mailbox's 9 of 20 and the
     http-client child's 1 of 10.
   - The comments in `src/` and `tests/` no longer describe the old guard, except where noted above.
   - The M5 plan §10 still says "Still open". The plans are historical, and the ledger is the live
     record.
   - CHANGELOG.md is empty, and no release is due.

## Files

- `probe/`:
  - `redirect-step.sps` (M1), `long-url-hold.sps` and `long-form-hold.sps` (M2), `submit-proxy.sps`
    (m1);
  - `margin-instrumentation.diff` (m3);
  - `mut-outside.diff` and `mut-noseam.diff` (m4, and item 2's rerun).
- `results/`: each log cited.
