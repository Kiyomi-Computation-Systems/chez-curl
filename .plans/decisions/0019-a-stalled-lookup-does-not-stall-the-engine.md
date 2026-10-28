# ADR-0019: A stalled name lookup does not stall the engine

- **Status:** Accepted; amended 2026-10-25, the stand-in measured, and the Mac's probe (M3 slice 3); amended 2026-10-25, what slice 3 built; amended 2026-10-25, after the slice's review; amended 2026-10-26, a CI lane on 8.20.0; amended 2026-10-26, the lane on 8.23.0; amended 2026-10-26, the Mac's probe; amended 2026-10-28: a second late 28, about 1 s past a call's bound
- **Date:** 2026-10-24
- **Scope:** M3's engine and every transfer it runs (the [M3 plan](../2026-10-24-m3-plan.md))
- **Settles:** what the engine does about libcurl's resolver thread, which blocks teardown
  while a lookup runs. The maintainer chose on 2026-10-24.
- **Related:** [ADR-0003](0003-libcurl-floor-7-85.md), whose rule makes anything newer than the
  floor optional, one feature at a time · [ADR-0009](0009-typed-escape-hatch.md), owned
  options · [ADR-0012](0012-engine-thread-owns-every-handle.md), the engine ·
  [ADR-0013](0013-collect-safe-blocking-calls.md), calls that can block · the M3 plan, §2

## Context

The M3 plan measured this before planning, on 2026-10-24, through Chez probes under
`build/verify/m3/measure/` (not kept; spike E1 commits its own). Each ran in Docker
`ubuntu:24.04`, where `/etc/resolv.conf` named `127.0.0.1`, and `nc -lku 127.0.0.1 53` read
every query and answered none. The libcurls were:
- the floor's 7.85.0 and Ubuntu's 8.5.0, with OpenSSL and with GnuTLS, under the CI stand-in's
  Chez 10.4.0;
- Guix's 8.20.0 under Guix's Chez 10.4.0, from `/gnu/store` mounted read-only.

Each probe ran one easy handle for `http://slow-name.example.com/` in one multi handle, with
`NOSIGNAL` 1. Every case ran twice, and the runs agreed within 25 ms.

- **Taking a resolving transfer apart blocks until the lookup ends.** Driven 300 ms, then
  removed and cleaned up, with `TIMEOUT_MS` at 60 s, in ms:

  | libcurl | `remove_handle` | `easy_cleanup` | `multi_cleanup` |
  |---|---|---|---|
  | 7.85.0 | 9,729–9,733 | 0 | 0 |
  | 8.5.0, OpenSSL | 9,724–9,744 | 0 | 0 |
  | 8.5.0, GnuTLS | 9,741–9,744 | 0 | 0 |
  | 8.5.0, either, with `QUICK_EXIT` 1 | 0 | 0 | 0 |
  | 8.20.0, with or without `QUICK_EXIT` | 0 | 0 | 9,749 |
  | 8.20.0 with `CURLMOPT_QUICK_EXIT` 1 | 0 | 0 | 0 |

  9.7 s is glibc's resolver giving up: two tries of 5 s, less the 300 ms already spent.
  The floor has no `QUICK_EXIT` (7.87.0), and `curl_easy_option_by_name` does not find it.
  8.20.0 joins its resolver threads when the multi handle is cleaned up. Its
  `CURLMOPT_QUICK_EXIT`, option 21 in its `multi.h`, stops that. 8.5.0 answers it
  `CURLM_UNKNOWN_OPTION`, 6.
- **A transfer's own timeout blocks inside `curl_multi_perform`.** With `TIMEOUT_MS` at 1000,
  driven to its end:

  | libcurl | code 28 at | longest single `curl_multi_perform` |
  |---|---|---|
  | 7.85.0 | 10,046–10,051 ms | 9,046–9,051 ms |
  | 8.5.0, either | 10,027–10,051 ms | 9,026–9,051 ms |
  | 8.5.0, either, with `QUICK_EXIT` 1 | 1,001–1,002 ms | 0 ms |
  | 8.20.0, with or without `QUICK_EXIT` | 1,000–1,001 ms | 0 ms |

  8.20.0's `multi_cleanup` then blocked 9,050–9,051 ms.

  On an engine, that one call holds the thread: every other transfer on it stops for 9 s.
  A plain binding would also stall every other thread's collection for longer than that.
  The plan measured it: a collection waits about 500 of the engine's loops (§2).
- **libcurl documents the trade.** `CURLOPT_QUICK_EXIT(3)`, 8.20.0: "1L meaning that when
  recovering from a timeout, libcurl should skip lengthy cleanups that are intended to avoid
  all kinds of leaks (threads etc.), as the caller program is about to call exit() anyway.
  This allows for a swift termination after a DNS timeout for example, by canceling and/or
  forgetting about a resolver thread, at the expense of a possible (though short-lived) leak
  of associated resources." `CURLMOPT_QUICK_EXIT(3)` says the same of a multi handle, "do not
  join threads when cleaning up this multi handle", and was added in 8.20.0.
- **Every recorded libcurl resolves on a thread.** Each row of `tests/known-libcurls.sexp` has
  the `AsynchDNS` bit. A libcurl without it resolves inside `curl_multi_perform` itself. A new
  row is a reviewed change (ADR-0017), so such a libcurl is seen before it is admitted.
- **The container cannot show any of it.** It has no `/etc/resolv.conf` and no network, so
  the same lookup fails at once: code 6, `CURLE_COULDNT_RESOLVE_HOST`, in 1 ms. Binding
  port 53 there, to stand in a server that never answers, is refused, `EACCES`.

## Decision

1. **Every engine transfer sets `QUICK_EXIT` to 1 when the loaded libcurl knows it.** It is
   looked up by name, as every option is, and set with the pins, before the request's own
   settings. Any answer but `CURLE_OK` is `setopt-failed`. On the floor, which lacks it, the
   transfer runs without it.
2. **Every engine's multi handle sets `CURLMOPT_QUICK_EXIT` to 1, on the engine thread, when
   it is made.** It goes through `curl_multi_setopt`, bound once for a long through
   `bind-variadic` (ADR-0001). `CURLM_UNKNOWN_OPTION` is accepted: that libcurl predates it.
   Any other answer but `CURLM_OK` refuses the engine before its thread runs a transfer.
   This applies decision 1 to the multi handle. It was measured after the maintainer chose
   "QUICK_EXIT where known", which it follows.
3. **The calls measured blocking are `__collect_safe`,** through `bind-blocking`:
   `curl_multi_perform`, `curl_multi_remove_handle` and `curl_multi_cleanup`, with
   `curl_multi_poll`. That is ADR-0013's decision 1, which binds whatever can block. It
   overturns ADR-0013's provisional decision 3 for `curl_multi_perform`. Spike E1 reruns the
   measurement and amends ADR-0013 (amended 2026-10-24).
4. **`QUICK_EXIT` is an owned option** (ADR-0009, amended 2026-10-24). The test seam refuses
   it, so no request can turn it off. No hatch reaches a multi option.
5. **A test shows a stalled lookup returning promptly,** on Linux. The container cannot
   stall a lookup, so a stand-in `getaddrinfo`, compiled at test time and loaded with
   `LD_PRELOAD` into a child Chez, stalls one name. The M3 plan, §6, says what it holds.

### Rejected

- **Raising the floor to 7.87.0, so that `QUICK_EXIT` is always there.** Every 7.85.0 row
  would be measured again (drift, URL verdicts, transfer verdicts), and CI's floor curl
  rebuilt. It would not reach 8.20.0's stall, which is the multi handle's.
- **Accepting the stall,** with the calls `__collect_safe` so that collections go on. A
  cancel, a timeout or a stop during a slow lookup would still hold every transfer on the
  engine for up to 10 s.

## Consequences

- **A detached resolver thread outlives its transfer** until its lookup ends, and then frees
  what it holds, as libcurl documents. That is unmeasured under Valgrind. No suite stalls a
  lookup under the memory gate.
- **The floor keeps the stall.** On 7.85.0 and 7.86.x, a cancel or a timeout during a stalled
  lookup holds the engine for up to glibc's resolver timeout, 10 s by default. M8's
  documentation says so.
- **`curl_multi_setopt` is a new variadic binding,** so `make check-variadic` must run on the
  Mac before M3 is done (ADR-0001).
- **`CURLMOPT_QUICK_EXIT` is a constant newer than the floor.** `test-constants` compiles
  against headers no newer than the library, and the floor's headers lack it. So M3 checks
  it only where the headers have it, under `LIBCURL_VERSION_NUM` (M3 plan, §6).
- **Apple's libcurl is unmeasured.** Its 8.7.1 has `QUICK_EXIT` but not the multi option, and
  macOS has no `LD_PRELOAD`. Whether the stand-in reaches Apple's resolver is the Mac run's
  to show.

## Amendment, 2026-10-25: the stand-in, measured, and the Mac (M3 slice 3)

- **A stand-in `getaddrinfo` under `LD_PRELOAD` stalls libcurl's resolver as a silent DNS
  server did.** It stalls one name for a set time, then answers `EAI_NONAME`, and hands every
  other name to the real `getaddrinfo`, found by `dlsym(RTLD_NEXT, ...)`. It logs each lookup
  it stalls. Spike E1's `lookup.sps` ran under it, each of its nine cases four times per
  stall, with stalls of 10,000 and 3,000 ms: twice from scratch copies, then twice from the
  committed programs, `.plans/research/stall/` with its `results/`:
  - in the container, on 8.20.0;
  - in Docker `ubuntu:24.04`, on the floor's 7.85.0 and Ubuntu's 8.5.0 with OpenSSL and with
    GnuTLS, under the floor's Chez.

  Each case gave the shape of E1's tables, in ms:

  | libcurl | blocks without its option | at a 10,000 ms stall | at 3,000 | with the option |
  |---|---|---|---|---|
  | 7.85.0 | `remove_handle` on teardown | 9,667–9,698 | 2,655–2,700 | none to set |
  | 7.85.0 | one `perform` on timeout; 28 at the stall's end | 9,001–9,002 | 1,999–2,002 | none to set |
  | 8.5.0, both | `remove_handle` on teardown | 9,692–9,694 | 2,692–2,695 | `QUICK_EXIT`: 0 |
  | 8.5.0, both | one `perform` on timeout; 28 at the stall's end | 8,999–9,001 | 2,000–2,001 | `QUICK_EXIT`: 0, and 28 at 999–1,003 |
  | 8.20.0 | `multi_cleanup` after a teardown | 9,698–9,703 | 2,699 | `CURLMOPT_QUICK_EXIT`: 0 |
  | 8.20.0 | `multi_cleanup` after a timeout | 8,999–9,010 | 1,998–2,001 | `CURLMOPT_QUICK_EXIT`: 0 |

  Each wait is the stall less the time already spent: 300 ms of driving, or the 1,000 ms
  timeout. So it is the stand-in that holds them. On 8.20.0, `curl_easy_cleanup` after
  `curl_easy_perform` waited 8,996–9,002 and 1,995–1,999 ms, and none with `QUICK_EXIT`, as E1
  found. With no stand-in, the same lookup failed at once on every lane, code 6 within 43 ms.
  The stand-in saw two lookups per transfer on 8.20.0, and one on the others.
- **The maintainer chose on 2026-10-25: the stall checks run on Linux alone.** macOS has no
  `LD_PRELOAD`. A stand-in there needs `DYLD_INSERT_LIBRARIES` and an `__interpose` section,
  and whether that reaches the resolver Apple's 8.7.1 uses is unmeasured. So on macOS
  `test-engine` prints that the stall checks did not run, and holds no test there. The
  stand-in's source carries a macOS half, and a probe for the Mac's M3 run shows whether it
  stalls Apple's lookups. Its answer is recorded here, and decides whether a later change
  runs the checks on macOS. Rejected: running the checks on macOS now, which would fail the
  Mac's `make test` if interposition cannot reach the resolver; and no probe, leaving the Mac
  unmeasured.

## Amendment, 2026-10-25: what slice 3 built

- **Decisions 1 and 2, as built.** `pinned-settings` adds `QUICK_EXIT` at 1 to the pins when
  the engine asks for it and `curl_easy_option_by_name` finds it, and `set-pinned-options!`
  sets the list, first, as data. The engine's thread sets `CURLMOPT_QUICK_EXIT` to 1 right
  after `curl_multi_init`. `multi-quick-exit-verdict` judges the answer: `CURLM_OK` is set,
  `CURLM_UNKNOWN_OPTION` unknown, and any other refuses the engine before its first turn.
  `curl-engine-quick-exit` reads which, privately.
- **The test seam:** `make-curl-engine-without-quick-exit` takes a list of `transfer` and
  `multi`, the settings its engine leaves out. It is private, as `make-faulty-curl-engine`
  is (ADR-0009, amended 2026-10-25).
- **The test** (decision 5) is `test-engine`'s, on Linux. It compiles
  `tests/stall-getaddrinfo.c` with `$CC`, and runs `tests/engine-stall.sps` under it, preloaded,
  with each lookup of a name ending `.stall.invalid` stalled 3,000 ms:
  - three scenarios, each on an engine of its own: a cancel, sent the moment the stand-in logs
    the lookup stalling, beside a 1 s drip that must answer whole; a 500 ms timeout; and a
    stop, sent the moment the lookup stalls;
  - each event is judged against the stand-in's log, so the two share no clock: prompt, done
    before the stand-in answered, and within 1,000 ms of its cause, or 2,000 ms for the
    timeout and the drip; stalled, done once the stand-in had answered; anything else fails;
  - the child also reports the cancel engine's `CURLMOPT_QUICK_EXIT` and how many of its four
    transfers set `QUICK_EXIT`, counted once libcurl took it, so a switch is held by what
    the engine did, not what the child asked;
  - `stall-verdicts` holds each libcurl's verdicts, by version, written out in the suite.
    7.85.0 stalls each event, the recorded limit, and runs with both settings alone. 8.5.0
    is prompt, and stalls each event without `QUICK_EXIT`, its control. 8.20.0 is prompt,
    and its stop stalls without `CURLMOPT_QUICK_EXIT`, its control. A libcurl with no row
    fails by name, and the suite prints the row it measured;
  - `linux?`, from Chez's machine type, decides whether the checks run, and must agree with
    `uname -s`, so they cannot quietly not run on Linux.
- **The memory gate does not reach the child.** `make test-memory` runs `test-engine` under
  Valgrind, which does not follow its children, so the child runs natively, and no lookup
  stalls under the gate, as this record's consequences say.
- **Found:** once, among about 80 runs of the child, a 500 ms timeout's code 28 came 1,014 ms after
  it fell due, while two agents ran heavy suites on the machine. That run's log was overwritten
  when the sweep reran its mutant, so only this record keeps it. 240 more, 40 at a time on fresh
  engines and on one, came within 12 ms (`results/container-2.log`), and the slice's review's 80
  under three times the load within 22 ms. 1,014 ms is about the engine's 1,000 ms poll, so
  the timeout's bound is 2,000 ms, still short of the stand-in's answer, about 2,500 ms after
  it fell due. The cause is not known.

## Amendment, 2026-10-25: after the slice's review

A read-only Opus review of the slice found these, each shown by a mutant it ran or a probe;
I reproduced each before acting on it.

- **No test held decision 2's refusal.** Every libcurl answers `CURLMOPT_QUICK_EXIT` with
  `CURLM_OK` or `CURLM_UNKNOWN_OPTION`, and the decoy libcurl makes no multi handle, so a
  mutant that took any other answer as unknown passed. A private constructor,
  `make-curl-engine-answering-quick-exit`, now takes a given code for libcurl's answer, after
  making the call. `test-engine` requires 1 and 10 to refuse the engine, as `failed`,
  carrying the code, with the counts unchanged, and 0 and 6 to run it, set and unknown.
- **Two stops were not judged.** The child stopped its cancel's and its timeout's engines
  without timing them, so 8.20.0's wait in `curl_multi_cleanup` after either, a row of this
  record's first table, was checked by nothing. Each stop is now an event, and each event is
  judged by whether the stand-in had answered as it started and as it returned: stalled when
  the answer came during it. So a stop after a cancel that waited for the lookup is prompt.
  The rows gained both stops: stalled on 8.20.0 without `CURLMOPT_QUICK_EXIT`, prompt
  elsewhere. Without the start's reading, those stops are stalled on the floor and on 8.5.0
  without `QUICK_EXIT`, which only those lanes show: a mutant passed in the container and
  failed in Docker on both.
- **8.20.0 leaves resolver threads behind after every stop, stall or none.** With
  `CURLMOPT_QUICK_EXIT`, each stopped engine left two threads, whose lookups had answered at
  once: 41 in all after 20 engines, 1 again within 3 s, and 2,002 ms after a stop by the
  review's measure. Without it, there was 1 throughout (`results/container-threads.log`).
  The review ran it under Valgrind, and the stall child held open 6 s so that left threads
  woke after their multi handle's cleanup: no errors, nothing lost, in both. A program that makes many engines
  briefly holds two threads for each. M8's documentation says so.
- **No CI lane loads 8.20.0 or later.** CI's lanes load Ubuntu's 8.5.0 and the floor's 7.85.0.
  So `CURLMOPT_QUICK_EXIT`'s value and number, its constant's check, the `multi` control and
  the refusal of an engine whose libcurl knows the option are shown only in the Guix
  container, which runs 8.20.0. On 8.5.0 a mutant that sets the option to 0 passes, and on
  the floor every mutant that keeps transfers working passes. A CI lane that builds a current
  curl, as the floor lane builds 7.85.0, would close it; that is the maintainer's to decide.
- **The Mac probe could not tell its failures apart.** The stand-in now logs `loaded PID` as
  it loads, and the probe has a `control` set: which preload variable reached Chez, and
  `gai-control.c`, an ordinary program's own `getaddrinfo` call on the stalled name, which must
  take the stall. A call from Chez proves nothing: Chez finds an entry through libcurl's own
  dependencies, which skip `LD_PRELOAD` on Linux, so a call from Chez under the stand-in
  answered at once. The probe also refuses to run with a proxy variable set. Whether dyld
  applies the interposition to a call from the shared cache is still the Mac's to show.
- **Small things:** the stand-in's path goes through `LD_PRELOAD`, which splits on spaces and
  colons, so a `TMPDIR` holding either fails every stall check by name. The record's context
  reads the `AsynchDNS` bit as "resolves on a thread", but a c-ares build sets it too.

## Amendment, 2026-10-26: a CI lane on 8.20.0

The maintainer asked for the lane this record's review found missing. CI's `current` job
builds vanilla 8.20.0 with OpenSSL and runs every suite against it
([ADR-0020](0020-a-ci-lane-on-the-current-libcurl.md)), so `CURLMOPT_QUICK_EXIT`'s setting
and its `set` verdict, its constant's check, and 8.20.0's row of `stall-verdicts`, the
`multi` control among them, run in CI, once CI runs.

## Amendment, 2026-10-26: the lane on 8.23.0

The `current` lane builds curl's newest release, 8.23.0, in place of 8.20.0 (ADR-0020,
amended 2026-10-26). Measured in Docker: 8.23.0's stall verdicts are 8.20.0's, row for row,
its `multi` control among them, so `stall-verdicts` gains an 8.23.0 row equal to 8.20.0's, and
`CURLMOPT_QUICK_EXIT` still runs in CI. 8.20.0's row runs in the Guix container.

## Amendment, 2026-10-26: the Mac's probe

The maintainer ran the probe this record's 2026-10-25 amendment asked for, on their M1:
Homebrew's Chez 10.4.1 on Darwin arm64, and Apple's libcurl 8.7.1. Its output is
kept as `research/stall/results/mac-control.log` and `mac.log`.

- **The stand-in reaches Apple's resolver.** Through `DYLD_INSERT_LIBRARIES` and its
  `__interpose` section it loaded into Homebrew's Chez and into `gai-control`, whose
  `getaddrinfo` call took the 3,005 ms stall. On every stalled `lookup` line it loaded once
  and stalled once; with no stand-in, every lookup failed at once, code 6.
- **Apple's 8.7.1 stalls as 8.5.0 does.** A 10,000 ms stall blocked `curl_multi_remove_handle`
  9,677–9,678 ms, `curl_multi_perform` 9,001–9,003 ms inside a timeout that answered 28 at
  10,007 ms, and `curl_easy_perform` 10,006–10,007 ms; a 3,000 ms stall, 2,676–2,681,
  2,001 and 3,004–3,006 ms. With `QUICK_EXIT` set, none waited: the teardown at once, each
  timeout at 1,002–1,007 ms. `CURLMOPT_QUICK_EXIT` is unknown to it, 6, and changes nothing.
  Two runs of each.
- **So the engine's setting protects the Mac,** as on 8.5.0: each transfer's `QUICK_EXIT`.
- **What this decides is the maintainer's:** the checks could now run on macOS, as the
  2026-10-25 amendment left open. `test-engine` would compile the stand-in as a dynamic
  library and preload it with `DYLD_INSERT_LIBRARIES`, and 8.7.1's row would be 8.5.0's.
  The probe handed the variable to Chez through `env`, as `test-engine`'s child does; System
  Integrity Protection strips it from a protected binary's own start, such as `sh`'s, so the
  child's path in `test-engine` itself is to be measured. Until decided, they run on Linux
  alone.

## Amendment, 2026-10-28: a second late 28, about 1 s past a call's bound

M5 slice 3's review probe `ranout-post-live.sps` makes a `post` with a retry policy and a
3000 ms bound, its retry stalled at a listener that never answers, so the call ends at the
bound's 28. On 8.20.0 in the container, one run raised after 4014 ms
([`research/m5/retry-review/results/after-round-2-guix-8.20.0.log`](../research/m5/retry-review/results/after-round-2-guix-8.20.0.log)),
right after four timer storms in the same script; three kept reruns raised after 3008, 3008 and
3014 ms ([`late-reruns-guix-8.20.0.log`](../research/m5/retry-review/results/late-reruns-guix-8.20.0.log)).
So a 28 came about 1 s late once more, as the 1,014 ms of 2026-10-25 did, and its cause is still
open (the M5 plan, §10).
