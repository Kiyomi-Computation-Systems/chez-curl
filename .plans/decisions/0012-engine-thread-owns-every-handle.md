# ADR-0012: One engine thread owns every transfer handle, and caller code never runs on it

- **Status:** Accepted; amended 2026-10-24: stopping an engine (the M3 plan); amended
  2026-10-26: completions reach callers through a mailbox (the M4 plan); amended 2026-10-26:
  the engine's thread and SIGINT (M4 slice 2); amended 2026-10-29: resuming a paused transfer,
  and pacing a poll that spins (the M6 plan); amended 2026-10-30: a look at the queue before
  the poll (M6 slice 1)
- **Date:** 2026-10-04
- **Scope:** chez-curl v1, from M3 (the engine)
- **Settles:** the brief's §2 items 1 to 3 and the caller-code rule of its §5. The brief
  said each of these "becomes a decision record at M0".
- **Related:**
  - brief §2, §5, §6.3 and §9 risk 2;
  - chez-libuv ADR-0019 (per-loop affinity, enforced);
  - [ADR-0008](0008-curl-url-only.md) (handing over a `CURLU`);
  - [ADR-0009](0009-typed-escape-hatch.md) (escape-hatch options are applied on the engine);
  - [ADR-0013](0013-collect-safe-blocking-calls.md) (`__collect_safe`).

## Context

libcurl's threading rule (`docs/libcurl/libcurl-thread.md`): "You must **never** share
the same handle in multiple threads. You can pass the handles around among threads, but
you must never use a single handle from more than one thread at any given time."

Its documentation says three more things about how its calls behave:

- `curl_multi_poll` "blocks until activity is detected".
- `curl_multi_wakeup` "can be called from any thread and it wakes up a sleeping
  `curl_multi_poll`".
- `curl_multi_perform` "performs transfers … in a non-blocking fashion".

The brief settled the design:

- **§2 item 1:** one dedicated Chez thread owns the multi handle, waits in
  `curl_multi_poll`, and is not chez-libuv.
- **§2 item 2:** every libcurl handle is owned by that thread, and a call from elsewhere
  raises a named condition, mirroring chez-libuv's ADR-0019.
- **§2 item 3:** concurrency does not cost threads.
- **§5:** libcurl's write callback runs on the engine thread, so caller code there is a real
  hazard. The brief's §9 calls it "the worst bug this design can have", which needs "a test
  that asserts thread identity … not just a comment".

chez-libuv enforces its version of the rule at one central site, raising `&uv-wrong-thread`
with who, expected and actual.

Chez 10.4.0 gives each thread an id through `get-thread-id`: 0 for the main thread and 1 for
the first forked one, measured here.

## Decision

1. **An engine is one dedicated Chez thread holding one multi handle.** It owns every
   transfer handle it uses: the easy handles, share handles, mime handles and string lists
   a transfer uses. It creates them, configures them, adds them, removes them and frees
   them, all on its own thread. A high-level session owns one engine (brief §6.2).
2. **Callers never touch a transfer handle.** Submitting a request, cancelling one,
   resuming a paused transfer and stopping the engine are all messages. Each is queued
   under the engine's mutex, then `curl_multi_wakeup` wakes the poll. That wakeup is the
   only libcurl call a caller's thread makes on an engine's handle. A `CURLU` reaches the
   engine by the handover in ADR-0008.
3. **The rule is enforced, not documented.** Every operation on an engine-owned handle goes
   through one central check that compares `get-thread-id` with the engine's thread. A
   mismatch raises `&curl-wrong-thread`, carrying who, expected and actual. Calls that
   touch no handle are exempt: `curl_version_info`, `curl_easy_option_by_name` and
   `curl_easy_strerror`.
4. **Caller code never runs on the engine thread.**
   - **libcurl callbacks are the binding's own trampolines.** They copy bytes between
     libcurl's buffers and bounded buffers, signal, and return. They never call a procedure
     a caller supplied.
   - **A full buffer pauses its transfer** (`CURL_WRITEFUNC_PAUSE`). The consumer resumes
     it by message, and the engine calls `curl_easy_pause` itself.
   - **Completions reach callers through a mutex,** as data. No condition variable is used:
     every wait polls (ADR-0013, amended 2026-10-25), and from M4 a mailbox the caller drains
     carries them (ADR-0021). Any completion callback the low level offers (M4) runs on a
     caller's thread.
   - **A test enforces this.** It asserts, inside a body consumer and inside completion
     delivery, that the current thread is not the engine's. Like every check here, it
     counts only after it has been watched failing.
5. **Concurrency costs no threads.** Many requests share one engine. The high level never
   starts a thread per request, so `http-parallel` submits N requests and blocks one caller.

Before M3 there is no engine. M2's single blocking request owns its easy handle on the
calling thread (brief §8). From M3 on, only engines own transfer handles.

### Rejected

- **A thread per request.** Concurrency would cost threads (brief §2 item 3).
- **Caller threads using handles under a lock.** libcurl allows a handle to move between
  threads, but never to be used by two at once. A lock would queue every caller behind the
  transfer and spread each handle's lifetime across threads.
- **chez-libuv's loop as the engine.** It needs `uv_poll` bindings that chez-libuv lacks,
  and it brings another library's affinity rules (brief §2 item 1).
- **Completion callbacks on the engine thread.** They would run caller code there, which is
  the brief's risk 2.

## Consequences

- **Every transfer handle lives and dies on one thread.** A stopping engine frees all of
  its handles before its thread exits.
- **Cancel, resume and stop are messages.** None of them touches a handle from the
  caller's thread.
- **A caller pays only its own thread to wait,** however many requests are in flight.
- **The central check costs one thread-id comparison** per handle operation.

## Amendment, 2026-10-24: stopping an engine (the M3 plan)

The maintainer chose on 2026-10-24 what a stop does with transfers still in flight.

- **Stop is a message, like the others.** On its own thread, the engine cancels every live
  transfer, and each completes as `stopped`. Then it takes apart and frees every handle it
  holds, cleans up the multi handle, and its thread exits.
- **The caller's stop returns once that thread has exited.** A later stop returns at once. A
  submit after stop raises a named refusal, before anything is queued.
- **A drain is the caller's to ask for:** await what is in flight, then stop. That is policy,
  M5's session's, and the low level has none.
- **Rejected:**
  - draining in stop itself, since a transfer with no timeout could hold stop forever;
  - a mode argument choosing between the two, which puts policy in the low level.

**Measured for the M3 plan, on Chez 10.4.0's source and in the container:**

- **Chez delivers Ctrl-C to the main thread alone.** `c/schsig.c`'s SIGINT handler acts only
  in the main thread's context. In any other thread it drops the signal ("disable keyboard
  interrupts in subordinate threads"). The engine's thread is always a forked one, so a
  keyboard interrupt never runs there.
- **A caller waiting in `condition-wait` does not answer Ctrl-C until the wait ends,** even
  with timed waits of 100 ms in a loop. Chez notices a pending event only when its event
  counter, 1000 ticks, runs out. But leaving a critical section runs `$event` at once:
  `enable-interrupts` does it as its count returns to 0. A loop of timed waits, each inside
  its own `critical-section`, answered Ctrl-C at 1,100 ms, against 3,000 ms without, 2 runs
  of 2. The M3 plan builds the caller's wait that way (§3.4).

## Amendment, 2026-10-26: completions reach callers through a mailbox (the M4 plan)

Decision 4 said that any completion callback the low level offers runs on a caller's thread,
and left which one to M4. The maintainer chose on 2026-10-26: a submit may name a mailbox, the
engine's thread appends the finished token to it as data, and a caller's thread takes it and runs
its callback ([ADR-0021](0021-completions-through-a-mailbox.md)). The engine still runs no caller
code. The test decision 4 asks for gains its delivery half: inside a callback, the thread is the
delivering one, never the engine's.

The plan's review found decision 4 still naming "a Chez condition variable", which ADR-0013's
2026-10-25 amendment replaced with polling waits. The line now says so.

## Amendment, 2026-10-26: the engine's thread and SIGINT (M4 slice 2)

M3 carried a question: Chez drops a SIGINT the kernel hands any thread but the main one, so
could Ctrl-C be lost to the engine's thread, now that the engine is public? Spike E1 saw every
process-directed SIGINT reach the main thread, 32 of 32, and left whether the engine's thread
should block SIGINT to M4, to measure on the Mac too, and to the maintainer.

**Measured on Linux** ([`research/m4/slice2/`](../research/m4/slice2/)), in the container (Guix's
libcurl 8.20.0) and in Docker `ubuntu:24.04` (8.5.0). A program made an engine, submitted a 9 s
transfer, and waited; the runner sent it SIGINT 20 times, 300 ms apart. Each one the main thread
took ran the keyboard-interrupt handler once, and one handed to any other thread would run it
never. The handler ran 20 times in every case, on both:

- the main thread waiting in a take, beside the engine's thread in `curl_multi_poll`;
- the main thread busy, never sleeping;
- the main thread in a take during a 9 s stalled lookup, `tests/stall-getaddrinfo.c`
  preloaded, with libcurl's resolver threads alive: 4 threads in all on 8.20.0, 3 on 8.5.0;
- the main thread in a take under Valgrind, Guix's 3.27.0 and Ubuntu's 3.22.0, the signals
  1 s apart, while a 30 s transfer was live.

So 160 of 160 reached the main thread, and 120 of 120 again in a second run of the first three
cases. Not for want of another taker: that run read each thread's masks from
`/proc/self/task/*/status`, on both, and no thread, the resolver threads among them, blocked any
signal; each ignored SIGPIPE alone. Linux's own rule explains it: the
kernel offers a signal sent to a process to its main thread first, unless that thread blocks it
or already has a signal pending while not running (`complete_signal`, `kernel/signal.c`).

**Decided by the maintainer, 2026-10-26: the engine's thread leaves its signal mask alone.**
Blocking SIGINT there would change nothing on Linux, and costs a libc binding whose `sigset_t`
differs by platform. The Mac runs `run.sh mac sigint` on slice 2's PR before it merges. A
SIGINT lost there reopens the question.

**The Mac, 2026-10-26,** on the maintainer's M1 (Darwin arm64, Homebrew's Chez 10.4.1, Node
20.10.0; `results/mac.log`): the handler ran 20 times of 20 with the main thread in a take, and
20 of 20 with it busy, so 40 of 40 reached the main thread there too, and the decision stands.
The stalled lookup's case is Linux's alone, with no `LD_PRELOAD` on macOS, and the masks were
not read, with no `/proc`. The runner then hung after its last line, in an unbounded wait for
the origin to exit once its stdin, a FIFO, was closed; why the origin did not exit there is
unmeasured. That wait now has a bound.

## Amendment, 2026-10-29: resuming a paused transfer, and pacing a poll that spins (the M6 plan)

M6 streams bodies (ADR-0030), so decision 4's pause and resume are built. The M6 plan measured
them first ([research](../research/m6/pause/)), through a C probe whose loop steps as the engine
does, on 7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, Guix's 8.20.0 and 8.23.0, two
runs each:

- **`curl_easy_pause` hands the bytes it held to the write callback before it returns,** on
  all five: so the callbacks run on the engine's thread, inside that call, as inside a perform.
  It answers 43 for a transfer that is done, removed, or never added, and 0 for one not paused.
- **A refusal inside that replay is lost on 7.85.0 and 8.5.0:** `curl_easy_pause` answers 23,
  and the transfer then ends 0 without the chunk it refused, 16,307 to 16,384 bytes. 8.20.0 and
  8.23.0 end it with 23.
- **On Ubuntu's 8.5.0, both builds, a paused transfer makes the poll spin:** `curl_multi_poll`
  returned at once 6.2 to 7.0 million times in a 3 s pause, every return under 1 ms, the
  probe's CPU 2,998 to 3,000 ms, over plaintext, TLS and HTTP/2. 7.85.0, 8.20.0 and 8.23.0
  polled 3 to 5 times, at 0.1 to 0.2 ms of CPU. curl fixed it in 8.6.0 (#12632), read in its
  source by the plan.

Decided by the maintainer, 2026-10-29, the recommended option, and settled with it by the
plan:

1. **Resume is the fourth message,** as decision 2 said, and names its token, never a handle.
   The engine carries it out after the cancels and before the perform, for a token still live,
   as a cancel is; one for a token taken out since is passed over, since its easy handle is
   freed in the turn its transfer ends. It clears both directions' pause bits and calls
   `curl_easy_pause` with `CURLPAUSE_CONT`, since the call takes the new state, not a change:
   `CURLPAUSE_SEND_CONT` and `CURLPAUSE_CONT` are both 0; a callable that still cannot go on
   pauses again inside the call (after the plan's second review). Any answer but 0, a 43 among
   them,
   fails the transfer, with the code, and takes it out; a reason a callable recorded inside the
   call wins over it (after the plan's review).
2. **The engine paces a poll that spins:** when a poll returns in under 1 ms while a transfer is
   paused, in a turn that took no message and in which no callable moved a byte, the engine
   sleeps 1 ms before its next poll. A message that arrives then waits at most that millisecond
   more. Chez's sleep, with interrupts on, deactivates the thread, so other threads' collections
   go on. M6's first slice measures the CPU and the delay on every lane, under the memory gate's
   Valgrind too, and a test holds the CPU and the delay under bounds on 8.5.0.

**Rejected:** leaving the loop as it is, and documenting that a paused stream costs a core on
8.5.0; and refusing streams on a libcurl that carries the bug, which is Ubuntu 24.04's own.

## Amendment, 2026-10-30: a look at the queue before the poll (M6 slice 1)

Decision 2 woke the poll by `curl_multi_wakeup`, and libcurl's documentation says it "wakes up a
sleeping `curl_multi_poll`". M6 slice 1 measured, before it built
([research](../research/m6/slice1/)):

- **On Guix's 8.20.0 with GnuTLS, the container's libcurl, `curl_multi_perform` reads back a
  wakeup made before it in the turn,** so the poll after it waits for libcurl's own events, up
  to its 1000 ms bound. A C loop that steps as the engine does, with no Chez, woke its poll once
  a turn:
  - made inside `curl_easy_pause`, or between that call and the perform, 14 of 14 polls lasted
    100 ms or more, the longest 1005.0 to 1005.1 ms, in each of three runs;
  - made before every perform with no pause, 15 of 18 polls waited for the next bytes, up to
    50.8 ms, in each;
  - made after the perform, the control, 15 of 15 ended at once, in each.

  Marks written around each libcurl call place the eventfd's `read` inside
  `curl_multi_perform`, under `strace`.
- **7.85.0, Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, 8.23.0, and upstream's 8.20.0 built
  with OpenSSL keep the wakeup** in every case.
- **The prototype streamed through it badly:** a drain of 1 MiB took 1,021 to 10,139 ms, with
  1 to 10 polls of 100 ms or more, each up to 1,005 ms, that began with a message queued; and
  one run made 588 resumes, then failed with 28 at its bound. A submit, a cancel or a stop made while the engine's
  thread is in its perform is exposed the same way, and has been since M3.

Decided by the maintainer, 2026-10-30, the recommended option: **after the read, and before the
poll, the engine looks at its queue under its mutex, and when a message is queued it skips the
poll and begins its next turn.** A message queued before the look is seen by it. One queued
after the look makes its wakeup after the perform, which every libcurl measured keeps, so the
poll ends at once. A turn that skipped its poll took a message at its next start, so it never
paces. The wakeup stays, as the poll's way to end for a message queued after the look.

**Rejected:** a poll capped at about 10 ms, which bounds the loss but wakes every engine about
100 times a second on every libcurl; and documenting a delay of up to 1 s on Guix's 8.20.0,
which the slice's tests of a resume's delay would then need rows for.
