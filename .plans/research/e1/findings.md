# Spike E1: what blocks, where callbacks run, and what a plain wait costs

- **Date:** 2026-10-24
- **Decides:** [ADR-0013](../../decisions/0013-collect-safe-blocking-calls.md), accepted with
  amendments (2026-10-24). Its decision 5 asked four questions; each has a section below.
- **Scope:** M3 slice 1 (the [M3 plan](../../2026-10-24-m3-plan.md), §4.1). E1 binds nothing in
  `src/`. Its programs bind libcurl themselves, plain and `__collect_safe` side by side.
- **Status of each claim:** every row ran at least twice on each lane it names, and the runs
  agreed as the ranges show. Results: `results/`.

## How it ran

The programs are in this directory. Each prints one line per measurement, naming its
libcurl's version.

| Program | Measures |
|---|---|
| `collect.sps` | a worker's collections beside an idle engine thread in `curl_multi_poll`, plain or `__collect_safe` |
| `lookup.sps` | every multi call's longest single run while a name lookup stalls |
| `deliver.sps` | where a write callback fires, and whether every byte arrives, while another thread collects |
| `wake.sps` | `curl_multi_wakeup` from another thread |
| `interrupt.sps` | when a waiting main thread answers SIGINT |
| `load-race.sps` | two threads' first references to `(curl private native)` at once |
| `system.sps` | whether Chez's `system` holds other threads' collections (for the harness) |

`run.sh LANE SET...` runs a lane's sets twice. `docker.sh` runs the Docker lanes, through
`in-docker.sh`, from the repository's root:

```sh
scripts/guix-env sh .plans/research/e1/run.sh container collect collect-long wake deliver lookup interrupt load-race collect-once system
sh .plans/research/e1/docker.sh
sh .plans/research/e1/docker.sh lookup interrupt load-race collect-once
```

The results came in parts, each from the same programs, except where a section says the
second runs extended them.

The lanes:

| Lane | Chez | libcurl |
|---|---|---|
| `container` | Guix's 10.4.0 | Guix's 8.20.0, GnuTLS |
| `floor` | the floor's 10.4.0, built by `scripts/ci/build-chez.sh` | 7.85.0, OpenSSL 3.0.13, built by `scripts/ci/build-curl.sh` |
| `ubuntu-openssl` | the floor's | Ubuntu 24.04's `libcurl4t64` 8.5.0 |
| `ubuntu-gnutls` | the floor's | Ubuntu 24.04's `libcurl3t64-gnutls` 8.5.0 |
| `guix-store` | Guix's, from the store | Guix's 8.20.0, from the store |

The four Docker lanes ran in `ubuntu:24.04`, image
`sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac`. There
`/etc/resolv.conf` named `127.0.0.1`, and `nc -lku 127.0.0.1 53` read every query and answered
none. `getent hosts slow-name.example.com` then failed after 20,103 and 20,104 ms, once each
time Docker started. The container cannot stall a lookup: it has no `/etc/resolv.conf`, so
the lookup fails at once. So `guix-store` runs only `lookup`.

Ubuntu's packages were `libcurl4t64` and `libcurl3t64-gnutls` 8.5.0-2ubuntu10.16, with
`libssl3t64` 3.0.13-0ubuntu3.16 and `libgnutls30t64` 3.8.3-1.1ubuntu3.6, the versions
`tests/known-libcurls.sexp` records. The test origin ran on the container's Node, from the
store.

Docker was started twice. In the first, `results/docker.log`, `deliver` found no
`(srfi :64)`: `make deps` links `vendor/` by its absolute path, and Docker mounted the
repository only at `/src`. `docker.sh` now mounts it at its own path too, and the second ran
`deliver` alone, `results/docker-deliver.log`. The container's run is `results/container.log`,
and its `system` set `results/container-system.log`. `results/container-trial.log` came first,
with the same programs, except that its `interrupt` lines print times as floats. The first
Docker start printed no package versions; it used the same image the same day.

A read-only review then found claims the runs did not support, and cases they missed. So
`lookup`, `interrupt`, `load-race` and a new `collect-once` set ran again, twice more on each
lane, with the programs extended: `results/container-2.log` and `results/docker-2.log`. Those
runs also print each lane's Chez, 10.4.0 on every lane. Where a section below draws on them,
it says so.

## 1. What a plain wait costs

A worker on the main thread made 60 lists of 100,000 elements, 11 collections, while an engine
thread waited in `curl_multi_poll`, idle, then spun a loop of TICKS turns, and polled again.
Each row is the range over the four Linux lanes, two runs each, unless it names a lane:

| Engine | Ticks | Worker | Polls per collection |
|---|---|---|---|
| none | | 13.4–16.0 ms | |
| `__collect_safe` poll, 300 ms | 0 | 14.1–19.1 ms | 0 |
| `__collect_safe` poll, 1 ms | 0 | 14.5–16.8 ms | 0.8–0.9 |
| plain poll, 1 ms | 0 | 5,349–5,360 ms | 459 |
| plain poll, 3 ms | 0 | 15,848–15,923 ms | 470 |
| plain poll, 1 ms | 9 | 1,034–1,041 ms | 87.3–87.8 |
| plain poll, 1 ms | 99 | 123–130 ms | 9.2–9.5 |
| plain poll, 1 ms | 999 | 23.5–28.1 ms | 1.0–1.1 |
| plain poll, 10 ms, `container` | 0 | 54,395–54,428 ms | 491 |
| plain poll, 300 ms, `container` | 0 | killed at 60 s, 2 runs of 2 | |

Polls per collection counts the polls that returned while the worker ran.

- **Each of the worker's collections waited 459 to 491 polls,** whatever each poll's length.
  So the worker's time grew with the poll's: 5.4 s beside a plain poll of 1 ms, 15.9 s beside
  one of 3 ms, 54.4 s beside one of 10 ms. Beside one of 300 ms, 11 collections of about 470
  polls would take about 26 minutes; those runs were killed at 60 s.
- **A collection waits for the engine thread's next event check, which comes once every 1,000
  ticks: here, every 500 polls.** `collect.sps once` (the second runs) asked for one
  collection at a time, after sleeps of 37 to 586 ms. On every lane, both runs:

  | Sleep, ms | 37 | 98 | 159 | 220 | 281 | 342 | 403 | 464 | 525 | 586 |
  |---|---|---|---|---|---|---|---|---|---|---|
  | Polls the collection waited, plain poll of 1 ms | 465–466 | 407–408 | 349–350 | 291–292 | 234–235 | 176–177 | 118–119 | 60–61 | 51–54 | 444–446 |
  | The same, `__collect_safe` poll | 0 | 0 | 0 | 0 | 0 | 0 | 0–1 | 0 | 0–1 | 0 |

  The first eight fit one sum: the polls the sleep covered, at about 1.07 ms each, and the
  wait add up to about 500, as if the collection before restarted the engine's timer. The
  last two do not fit it simply, and E1 did not explain them. Either way a lone collection
  waited anywhere from 51 to 466 polls here, by when it was asked, and collections close
  together, as the worker's are, wait nearly the whole period.
- **The ticks rows show the counter at work.** Each turn of the spin costs one tick, and the
  loop's own turn about 2 (500 polls a 1,000 ticks, above). A collection waited 459 polls
  with no spin, about 87.5 with 9 more ticks a poll, 9.4 with 99, and 1 with 999. At 2 ticks
  a turn, that is 918, 960–966 and 929–960 ticks a collection. The 999 row is one check a
  turn, so it says only that one poll is the least. Chez's source says why:
  - a thread that wants a collection sets every thread's `something-pending` flag, and
    nothing more (`S_fire_collector`, `c/schsig.c`);
  - a thread reads that flag only when its timer runs out (`s/library.ss`, the event
    handler), and the timer holds `default-timer-ticks`, 1000 (`s/cmacros.ss`);
  - the collection runs once one thread is left active (`$collect-rendezvous`, `s/7.ss`).
    A `__collect_safe` call deactivates its thread for the call, so a collection need not
    wait for it.
- **A `__collect_safe` poll costs nothing measurable.** Beside one, the worker took what it
  took with no engine thread at all.
- **E5c's 10 s, against these minutes, fits the ticks rows.** chez-http-server's E5c measured
  10,272 ms beside a plain `uv_run` with a 300 ms timer (ADR-0013's context). Its loop ran a
  Scheme timer callback each turn, so each turn spent more ticks than this one's. How many is
  unmeasured.

## 2. Which libcurl calls block

`lookup.sps` timed every multi call while one transfer resolved `slow-name.example.com`, in
two scenarios: `teardown` drove it 300 ms and took it apart; `timeout` set `TIMEOUT_MS` to
1000 and drove it to its end. `quick` set `CURLOPT_QUICK_EXIT` 1, and `mquick` set
`CURLMOPT_QUICK_EXIT`, option 21, to 1. A longest call is rounded to whole ms, and a blank
cell is 0 ms.

The second runs added `easy`: `curl_easy_perform`, bound `__collect_safe`, with `TIMEOUT_MS`
1000, then `curl_easy_cleanup`, as M2's blocking path does. Each range is over 4 runs, two in
each Docker start, except `easy`'s, which ran in the second only.

**Teardown,** in ms:

| Lane | Options | `remove_handle` | `multi_cleanup` |
|---|---|---|---|
| `floor` | none, `quick`, `mquick` or both | 9,699–9,750 | |
| `ubuntu-openssl` | none, or `mquick` | 9,732–9,744 | |
| `ubuntu-openssl` | `quick`, or `quick` and `mquick` | | |
| `ubuntu-gnutls` | none, or `mquick` | 9,721–9,744 | |
| `ubuntu-gnutls` | `quick`, or `quick` and `mquick` | | |
| `guix-store` | none, or `quick` | | 9,748–9,749 |
| `guix-store` | `mquick`, or both | | |

**Timeout,** in ms:

| Lane | Options | code 28 at | longest `perform` | `multi_cleanup` |
|---|---|---|---|---|
| `floor` | none, `quick`, or both | 10,026–10,051 | 9,026–9,051 | |
| `ubuntu-openssl` | none | 10,036–10,051 | 9,035–9,050 | |
| `ubuntu-openssl` | `quick`, or both | 1,000–1,001 | | |
| `ubuntu-gnutls` | none | 10,042–10,051 | 9,042–9,050 | |
| `ubuntu-gnutls` | `quick`, or both | 1,001 | | |
| `guix-store` | none, or `quick` | 1,000–1,003 | | 9,048–9,051 |
| `guix-store` | both | 1,000–1,001 | | |

**`easy`, through `curl_easy_perform`,** in ms:

| Lane | Options | code 28 at, all of it in `curl_easy_perform` | `curl_easy_cleanup` |
|---|---|---|---|
| `floor` | none, or `quick` | 10,018–10,051 | |
| `ubuntu-openssl` | none | 10,013–10,029 | |
| `ubuntu-openssl` | `quick` | 1,002 | |
| `ubuntu-gnutls` | none | 10,047–10,049 | |
| `ubuntu-gnutls` | `quick` | 1,001–1,003 | |
| `guix-store` | none | 1,005 | 9,045–9,046 |
| `guix-store` | `quick` | 1,005 | |

In the container, every case failed at once: code 6, `CURLE_COULDNT_RESOLVE_HOST`, at 1 ms,
with no call above 1 ms.

- **Three calls can block.** Each returned 9 to 10 s after the transfer began.
  `getent hosts` took 20 s for the same name there, so this fits glibc's resolver giving up
  on one query, by its defaults two tries of 5 s; E1 did not show that directly:
  - `curl_multi_remove_handle`, taking a resolving transfer apart, on 7.85.0 and 8.5.0;
  - one `curl_multi_perform`, at the transfer's own timeout, on the same libcurls;
  - `curl_multi_cleanup` on 8.20.0, in both scenarios.
- **`QUICK_EXIT` removes the first two on 8.5.0, and `CURLMOPT_QUICK_EXIT` the third on
  8.20.0.** 7.85.0 knows neither: `curl_easy_option_by_name` finds no `QUICK_EXIT`, and
  `curl_multi_setopt` answers 6, `CURLM_UNKNOWN_OPTION`. 8.5.0 also answers 6 to the multi
  option.
- **No other call took a millisecond,** stalled or not: `curl_multi_init`,
  `curl_multi_add_handle`, `curl_multi_wakeup`, `curl_multi_info_read`, and
  `curl_easy_cleanup` of a handle removed from our multi handle. `curl_multi_poll` waited no
  longer than it was asked. `deliver.sps` timed the same calls on ordinary transfers, and
  none but `curl_multi_perform` and `curl_multi_poll` reached 0.5 ms (§4).
- **`curl_easy_cleanup` after `curl_easy_perform` can block,** on 8.20.0: 9,045–9,046 ms,
  2 runs of 2, without `QUICK_EXIT`, and none with it. That is the shape of 8.20.0's
  `curl_multi_cleanup` above, for the multi handle `curl_easy_perform` runs the transfer in;
  E1 did not read libcurl's source to confirm it. On the other lanes the wait was inside
  `curl_easy_perform` itself.
- **So where the wait falls depends on the path.** ADR-0013's decision 1 asked about
  `curl_easy_cleanup`, since `CURLOPT_QUICK_EXIT(3)` describes a lengthy cleanup. Through a
  multi handle of ours, the wait is in the removal on 7.85.0 and 8.5.0, and in the multi
  handle's cleanup on 8.20.0, never in `curl_easy_cleanup`. Through `curl_easy_perform`, it is
  in `curl_easy_cleanup` on 8.20.0. M2's blocking path binds that call plain, inside a
  critical section, and sets no `QUICK_EXIT`, so during a stalled lookup on 8.20.0 it can
  hold every other thread's collections for about 9 s. Slice 2 deletes that path (M3 plan,
  §5.4); the engine's path removes every handle first.

## 3. Which call each callback fires from

`deliver.sps` ran four transfers on one multi handle on an engine thread, against the test
origin: two drips, of 200 bytes 5 ms apart and 150 bytes 7 ms apart, a 200 and an echo. A
second thread collected about once a millisecond. The engine marked where it was before each
call, and the write callable counted where it fired and on which thread.

- **Every write callback fired inside `curl_multi_perform`,** on the engine's thread: 352 of
  352 in each of the 74 runs that finished, on every lane, none inside `curl_multi_poll` and
  none elsewhere.
- **So a callback inherits perform's declaration** (ADR-0013's decision 2). On the engine,
  perform is `__collect_safe`, so the write callable is too.

## 4. One callable for a `__collect_safe` call and a plain one

- **Chez's source says it is safe.** A `__collect_safe` callable's entry calls
  `S_activate_thread`, which answers how to undo what it did, and its exit undoes exactly
  that (`c/thread.c`, and `s/x86_64.ss` and `s/arm64.ss` alike). Called from an active
  thread, as from a plain call, it does nothing either way.
- **The runs agree.** Each pairing below ran 3 times per invocation, twice per lane, while the
  other thread made 1,002–1,043 collections a run:

  | Write callable | `curl_multi_perform` | Runs | Every byte, every code 0, every status 200 |
  |---|---|---|---|
  | `__collect_safe` | plain | 24 | yes |
  | plain | plain | 24 | yes |
  | `__collect_safe` | `__collect_safe` | 24 | yes |
  | plain | `__collect_safe` | 2, then a crash | crashed in 8 invocations of 8 |

- **The control shows the runs can fail.** CSUG rules out a plain callable inside a
  `__collect_safe` call, since the thread runs Scheme while deactivated. That pairing crashed
  Chez with "nonrecoverable invalid memory reference", exit 134, in 8 invocations of 8, two
  on each lane. One, on `ubuntu-openssl`, finished 2 runs before it crashed.
- **The calls took no time worth a declaration.** The longest single call of each, in ms:
  `curl_multi_init`, `curl_multi_add_handle`, `curl_multi_info_read`,
  `curl_multi_remove_handle` and `curl_easy_cleanup` at most 0.2, and `curl_multi_cleanup`
  0.3. `curl_multi_perform` took at most 0.7 plain. When it was `__collect_safe` it took up
  to 6.4 in the container and 9.1 on `floor` and `ubuntu-gnutls`; why is unmeasured.
  `curl_multi_poll` waited up to 9.5, about the drips' gaps.

## Also recorded

### Wakeups

`curl_multi_wakeup` is the one call a caller's thread makes on an engine's handle (M3 plan,
§3.1). On every lane, both runs:
- a wakeup reached a waiting `__collect_safe` poll in 0.015 to 0.208 ms, over 20 wakeups a
  run;
- one sent while no poll ran made the next poll of 5,000 ms return at once, in 0 ms;
- two sent together made the next poll return at once, and the one after that wait its whole
  300 ms (301–302 ms): they coalesced into one.

So "queue under the mutex, then wake" loses no message, whenever the wakeup lands.

### Ctrl-C

`interrupt.sps` waited about 3 s on its main thread for a second thread, which signalled once
its own 3 s wait ended, and the runner sent SIGINT about 1 s in, by process id or to the second
thread's id in `/proc`. Every row ran on every lane, in both sets of runs (16 runs), except
the second thread's `condition-wait` and `curl_multi_poll`, added in the second (8 runs):

| The main thread waited in | SIGINT to | The second thread waited in | Main's wait ended at | The second's ended at | The handler ran at |
|---|---|---|---|---|---|
| `condition-wait`, no timeout | the process | `sleep` | 3,000–3,001 ms | 3,000 ms | 3,000–3,001 ms |
| `condition-wait`, 100 ms, in a loop | the process | `sleep` | 3,000–3,001 ms | 3,000 ms | 3,000–3,001 ms |
| the same, each wait in its own `critical-section` | the process | `sleep` | 3,000 ms | 3,000 ms | 1,100–1,101 ms |
| a `__collect_safe` `curl_multi_poll` of 3 s | the process | `sleep` | 1,012–1,026 ms | 3,000 ms | the same as the wait |
| the sectioned waits | the second thread | `sleep` | 1,011–1,032 ms | the same | never |
| the sectioned waits | the second thread | `condition-wait`, 3 s | 3,000 ms | 3,000 ms | never |
| the sectioned waits | the second thread | a `__collect_safe` `curl_multi_poll` of 3 s | 1,015–1,059 ms | the same | never |

The first runs did not print the second thread's time; their rows agree with the rest.

- **A waiting thread answers Ctrl-C only at its next event check,** and leaving a critical
  section makes one at once. So the engine's await waits in timed waits, each inside its own
  critical section (M3 plan, §3.4).
- **A SIGINT sent to the process reached the main thread every time,** 32 of 32 on
  Linux. Which thread takes a process's signal is the kernel's choice; E1 did not read
  Linux's, and macOS is unmeasured.
- **A SIGINT sent to another thread is lost.** Chez acts on SIGINT only in the main thread's
  context (`handle_signal`, `c/schsig.c`), so the handler never ran.
- **It ended the second thread's `sleep` and `curl_multi_poll` early, and not its
  `condition-wait`.** On Linux, Chez installs its SIGINT handler without `SA_RESTART`
  (`c/schsig.c`; its `siginterrupt` call is for BSDI alone), so a system call the signal
  interrupts returns. Chez's `sleep` calls `nanosleep` once and drops what was left
  (`s_nanosleep`, `c/prim5.c`). A thread in `condition-wait` went on waiting. So a SIGINT the
  kernel hands an engine's thread is lost, and ends its poll early, which costs it a turn of
  its loop.

### `system` and the harness

`capture-command` runs every command through Chez's `system`, which deactivates its thread
for the call, unless interrupts are disabled (`s_system`, `c/prim5.c`). A worker's allocation
beside a second thread running `sleep 1` through it took 20.4–20.9 ms. With the call inside
a `critical-section`, it took 921.5–922.9 ms, the rest of the sleep. So `capture-command` may
run beside other threads, but never inside a critical section.

### The load race

Two threads made their first reference to `(curl private native)` together, each through
`eval` inside a guard. Chez locks neither the loading of a library nor its invocation, and
marks each pending while it runs (`s/syntax.ss`). There are two races:

- **`import`:** each thread made its own environment, so each first loaded the library and
  then invoked it. 158 of 160 races raised in one thread: "cyclic dependency involving import
  of library", 157 times, from the load (`s/syntax.ss`'s import paths), and once "involving
  invocation". In the other 2, both threads loaded. Either thread could lose: the forked one
  132 times, the main one 26. The trial, `results/container-trial.log`, raised "invocation"
  once in its 20 races too.
- **`invoke`,** in the second runs: the main thread made the environment first, which loads
  the library without invoking it, and both threads then made the first reference in it, as a
  program that imports the library does. 80 of 80 raised "cyclic dependency involving
  invocation of library": in the forked thread 78 times, in the main one 2.

The engine's case is `invoke`'s: a program imports `(curl)`, and its engine's thread makes the
first reference. So an engine loads libcurl on the caller's thread before it forks (ADR-0002,
amended 2026-10-24).

## Not measured

- macOS, and Linux on arm64. The Mac runs `make test` and `make check-variadic` before M3 is
  done (M3 plan, §7).
- Anything under Valgrind.
- TLS transfers, a slow connect rather than a slow lookup, and every callback but the write
  callback, the only one chez-curl sets.
- `curl_multi_strerror`, which E1 never called: it reads a table, and is plain under
  ADR-0013's decision 3.
- Whether two threads' `capture-command` calls run their commands at once on macOS. glibc's
  `system` lets them; Apple's may take a lock. `test-curl-testing` requires only that the
  calls overlap.

## For slice 2

- **The rows exist before the bindings.** `tests/foreign-conventions.sls` now requires
  `__collect_safe` of `curl_multi_perform`, `curl_multi_remove_handle` and
  `curl_multi_cleanup`, and plain of the four other multi calls E1 timed. Slice 2 adds each
  blocking row's `(bound-by bind-blocking)`, `curl_multi_poll`'s too (M3 plan, §3.9).
- **`curl_easy_cleanup` is plain once its handle is removed,** so the engine always removes a
  handle before it cleans it up.
- **A SIGINT the kernel hands the engine's thread is lost.** Every process-directed SIGINT
  here reached the main thread. Whether the engine's thread should block SIGINT, so that no
  kernel can choose it, is slice 2's to measure, on the Mac too, and the maintainer's to
  decide: Chez has no call for a thread's signal mask.
- **A `__collect_safe` perform's longest call, 9.1 ms against 0.7 plain,** is unexplained.
  Slice 2 measures a transfer's time beside the thread check's cost (M3 plan, §5.1).
- **The collection bound must ask for collections back to back** (M3 plan, §3.2). A lone
  collection beside a plain poll waited 51 to 466 polls (§1), by when it was asked, so a check
  that timed one could pass by luck. The worker's 11, close together, each waited nearly all.
- **glibc's `system` ignores SIGINT in the whole process while its command runs**
  (`system(3)`). So while any thread is inside `capture-command`, Ctrl-C reaches no thread.
  A test of Ctrl-C runs in a child that captures nothing while it waits for the signal.
- **M2's `curl_easy_cleanup` can block until slice 2 deletes its path** (§2): about 9 s on
  8.20.0, plain, in a critical section, during a stalled lookup. The maintainer chose on
  2026-10-25 to leave it until then (ADR-0013, amended).
