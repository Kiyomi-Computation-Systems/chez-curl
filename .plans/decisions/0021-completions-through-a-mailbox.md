# ADR-0021: Completions reach callers through a mailbox the caller drains

- **Status:** Accepted; amended 2026-10-26: after the plan's review; amended 2026-10-26:
  measured before slice 2 built on it
- **Date:** 2026-10-26
- **Scope:** chez-curl v1, `(curl)`'s asynchronous API, from M4
- **Settles:** how a completion callback runs on a caller's thread, which ADR-0012 left to M4;
  the maintainer chose on 2026-10-26
- **Related:**
  - [ADR-0012](0012-engine-thread-owns-every-handle.md), decision 4: caller code never runs on
    the engine's thread, and any completion callback the low level offers runs on a caller's;
  - [ADR-0013](0013-collect-safe-blocking-calls.md), amended 2026-10-25: every wait polls, and
    no condition variable is used;
  - brief §6.3 (M5's request group and `http-parallel`, built on this) and §8 (M4).

## Context

M3 built the engine: a submit returns a token, which any thread may await, any number of times,
and which a caller may cancel (M3 plan, §3.4 and §3.5). Await waits by polling. Each read of the
token is a short hold of the engine's mutex, and between reads the thread sleeps, from 50 µs
doubling to 10 ms, holding nothing. A wait on a condition variable deadlocked with a collection,
and was replaced (ADR-0013, amended 2026-10-25).

The brief's M4 adds completion callbacks, and ADR-0012 says where they may not run: on the
engine's thread, which owns every handle and must run no caller code. It did not say whose
thread runs them instead. Three designs were offered:

- a mailbox the caller drains;
- a delivery thread per engine;
- tokens only, with an await-any, and no callbacks in the low level.

## Decision

1. **A mailbox is a caller's object:** a queue of finished tokens, under a mutex of its own.
   `(curl)` exports its constructor.
2. **A submit may name a mailbox, and a callback.** When the token completes, the completing
   thread appends it to that mailbox, as data, under the mailbox's mutex. That thread is the
   engine's, or a caller's that cancelled a token still queued. It never calls the callback.
   Where both mutexes are held, the engine's is taken first, never the other way round.
3. **A caller's thread takes the next finished token,** waiting up to a bound it gives, and gets
   the token, or `#f` when the bound passes first. Its wait polls, as await's does, and holds
   nothing while it sleeps.
4. **Delivering runs the callback on the delivering thread.** It takes the next finished token,
   as 3 does, and calls that token's callback with the token, whose outcome await then returns at
   once. A raise from the callback leaves through the delivering call, on the caller's own
   thread. The token stays done, and the mailbox has moved past it.
5. **One mailbox may collect from any number of engines,** so "await any of these" is a take. A
   token goes to one mailbox at most; a token submitted without one is awaited, as in M3.
6. **The callback is held by the token, never by the request,** which still holds no procedure
   (the M3 plan, §3.6). The engine's thread holds the token, and never applies the callback.
7. **The test ADR-0012 asks for, its delivery half:** inside a callback, the current thread is
   the delivering thread, and never the engine's. It counts once it has been watched failing on a
   mutant that runs callbacks where the token completes.

### Rejected

- **A delivery thread per engine.** Caller code would run on a thread the caller does not own.
  One slow callback would delay every completion behind it, and a raise there would have no
  caller to reach. ADR-0012's "runs on a caller's thread" would need amending.
- **Tokens only, plus an await-any.** It drops the brief's completion callbacks, and M5 would
  build the same queue for its request group.
- **Callbacks on the engine's thread.** ADR-0012 rejected them: the brief's risk 2.

## Consequences

- **A caller that wants callbacks runs its own delivery loop,** on a thread of its choosing. M5's
  request group and `http-parallel` take from a mailbox.
- **A delivery can trail its completion by up to one polling sleep,** at most 10 ms by the wait's
  design, as await's does.
- **The engine still runs no caller code.** Its new act is one append, under a mutex no caller
  holds while waiting.
- **The mailbox's mutex is a new mutex,** held through `locked`, in a critical section, and
  never across a wait (ADR-0013, amended 2026-10-25).

## Amendment, 2026-10-26: after the plan's review

An adversarial review of the M4 plan (Opus, read-only) found two gaps in this record:

- **A take that escapes.** A take removes the token inside a critical section, and leaving one
  runs a pending interrupt at once (ADR-0012, amended 2026-10-24). So a handler that escapes
  there, or between deliver's take and its callback, leaves a token out of the mailbox that no
  caller holds, and its callback unrun. Decision 4's "the mailbox has moved past it" was
  written for a callback's raise, after the callback ran.
  - **Decided, as the plan's design: a take that escapes loses a notice, never an outcome.** The
    outcome stays on the token, which stays done, as await's does. The mailbox carries notices,
    and the token keeps the outcome: a caller whose interrupt handlers can escape keeps its
    tokens and awaits them. M5's request group keeps its tokens anyway, to cancel what it
    leaves.
  - A test plants an escaping interrupt at the take, and then awaits the token's outcome.
- **What deliver answers.** "What the callback answered" could not tell a callback answering
  `#f` from a bound that passed. Deliver answers the token it handed over, or `#f` once the
  bound passes. A token with no callback is handed over the same way, calling nothing, and
  take never runs a callback.
- **The delivery test** checks a cancel's completion from a thread other than the delivering
  one, and drives a token completed twice, a cancel while queued then a stop in the same
  batch, which must be appended once.

## Amendment, 2026-10-26: measured before slice 2 built on it

The M4 plan's §5.1 asked for two measurements before slice 2 built this record's mailbox, each
taken on a prototype of the take and the append, in the container (Guix's libcurl 8.20.0) and
in Docker `ubuntu:24.04` (8.5.0, Valgrind 3.22)
([`research/m4/slice2/`](../research/m4/slice2/)).

- **A take's delay,** from a token's completion, which a watcher thread saw within its 200 us
  pace, to the take's return: -0.2 to 9.6 ms idle, over 40 transfers on each, and 0.05 to
  8.9 ms under Valgrind, over 20; a negative is the watcher's own lag. An await, the control,
  gave 0 to 10.0 ms idle and -0.2 to 9.2 ms under Valgrind. So a delivery trails its completion
  by one polling sleep at most, as the consequences above say, Valgrind or not.
  - The first run said 0.9 to 3.2 ms, and was wrong. Each transfer paused a multiple of 10 ms,
    and a waiter's sleeps reach 10 ms on a cadence its submit sets, so the two met at one
    phase. The probe now spreads its pauses over every residue; the first run's log is kept.
- **A take that escapes.** A second thread held the mailbox's mutex, through a private seam,
  so a take blocked inside its critical section, and the runner then sent SIGINT. The
  keyboard-interrupt handler, which escaped, ran as that section ended, after the token left
  the mailbox: the take never returned it, and deliver never called its callback. The token was
  done, and await answered its 200. A control, signalled while the take slept on an empty
  mailbox, escaped before any token arrived, and the token reached the mailbox after. So the
  first amendment's contract holds as built: a take that escapes loses a notice, never an
  outcome.
  - Chez's timer cannot plant this. A timer that runs out inside a critical section runs its
    handler at a later event check, not as the section ends; a keyboard interrupt made pending
    there runs as it ends (`timer.ss` and `keyboard.ss`, there). A sweep of the timer from 1
    to 300 ticks escaped before the take at 1 to 6, after it had returned at 7 to 26, and never
    between; from 27, the take and the call after it ended before the timer ran out.
