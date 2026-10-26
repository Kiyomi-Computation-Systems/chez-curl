# Mailbox mutation log (M4 slice 2)

Each mutant was applied to a copy of the tree, one at a time, by `build/m4s2/mut.sh`, a scratch
script, and `test-mailbox` ran there in the container (Chez 10.4.0, libcurl 8.20.0). A mutant
passes only if the suite exits 0 on it. The first sweep printed one line for each of its 23
mutants, and `done`. After the fixes below and the slice's review, the final suite ran the 23
again, with the review's two, and printed 25 lines and `done`: each row here failed it, as
named, and `no-read-after-deadline` alone survived, under "Not killed". The cancel's append,
there too, was not run.

| Mutant | Change | Failed |
|---|---|---|
| `append-every-call` | a token appended at every completion, not only its change to done | a token cancelled while queued, then stopped, reaches the mailbox once; an engine failure's tokens, each once |
| `callback-at-completion` | the callback called where the token completes, beside the append, and never by a delivery | first, the deliveries: the callback's raise ran on the suite's engine's thread and failed it, and the suite died before the delivery test. That check moved to an engine of its own, and the delivery block under a guard; then, by name, the hundred callbacks' threads, the canceller's thread, the live cancel's, and the escapes' unrun callbacks |
| `lifo` | the mailbox's back list used unreversed, newest first | oldest first: three transfers, taken in the order they ended |
| `deliver-answers-callback` | a delivery answers what the callback answered | a callback answering `#f` is no timeout; the hundred delivered once; each cancel's delivery |
| `take-calls-callback` | a take calls the token's callback | a take never calls a callback; the hundred callbacks each ran once |
| `deliver-catches-raise` | a callback's raise caught inside the delivery | a callback's raise leaves through the delivery |
| `deliver-puts-back` | a callback's raise puts the token back in the mailbox | the same: the mailbox has moved past it |
| `deliver-calls-none` | a delivery calls the callback whether it has one or not | a delivery of a token with none calls nothing |
| `take-peeks` | a take leaves the token in the mailbox | a take answers it, then `#f`; and every check that drains |
| `no-bound-check` | any bound taken | the take's, the delivery's and the token wait's refusals |
| `negative-bound` | a negative bound taken | the same, by -1 |
| `no-interrupts-check` | a wait inside a critical section not refused | a take, a delivery and a token's wait, each inside `critical-section` |
| `unclamped-sleep` | a wait's last sleep runs its whole pause past the bound | first, nothing: the check took three takes bounded at 23 ms, and a take's reads come at about 13.2, 23.3 and 33.5 ms, so the read at 23.3 came after the bound either way. Measured, then bounded at 15 ms: the fastest of three at 15.1 ms, the mutant's at 23.3 |
| `bound-in-us` | a bound read as microseconds | a token's wait at its bound; a take's bound of 300 ms |
| `callback-without-mailbox` | a callback without a mailbox taken | `curl-submit`'s refusals |
| `mailbox-unchecked` | a mailbox that is no mailbox taken | `curl-submit`'s refusals; and later checks, once the engine failed appending to it |
| `callback-unchecked` | a callback that is no procedure taken | `curl-submit`'s refusals |
| `token-wait-unbounded` | a token's wait ignores its bound | its `#f` at the bound |
| `append-engine-thread-only` | only the engine's thread appends | a token cancelled while queued, on its own thread, reaches the mailbox; and once, stopped after |
| `append-skips-engine-error` | an engine failure's tokens not appended | an engine failure's tokens reach the mailbox |
| `append-skips-stopped` | a stop's tokens not appended | a stop's tokens reach the mailbox |
| `append-skips-setup-failure` | a set-up failure's token not appended | a set-up failure's token reaches the mailbox |
| `take-restores-on-escape` | a take that escapes after taking its token puts it back | both escapes: the token was back in the mailbox, `before`, not `lost` |

The last is the escape test's control: the plant reaches the place between the take's removal
and its return, or a take that restores its token would pass it.

## After the slice's review

The review (Opus, read-only) found every wait in the suite timed only where it ran out, and ran
a mutant in a copy of its own that passed all 24 checks. The check it asked for was written,
and the final sweep ran:

| Mutant | Change | Failed |
|---|---|---|
| `oversleep` | after one empty read, a bounded wait sleeps out its whole bound | a take, a delivery and a token's wait, each bounded at 5000 ms, return once a 300 ms transfer ends |
| `callback-at-completion`, again | as above | by name: the hundred callbacks' threads, the queued cancel's, on its own thread, and the live cancel's |

## Not killed, by design

- **`no-read-after-deadline`:** a wait answers `#f` once its last sleep ends past its bound,
  without the read after. It misses only a token that completes during that last sleep, and
  the next take hands that token over. A check needs a completion inside the sleep, a window
  of a few ms whose place moves with every sleep's overshoot, under Valgrind most of all; the
  suite holds the sleep's end to the bound instead (`unclamped-sleep`).
- **A cancel's append moved after its critical section,** in `curl-token-cancel`: an interrupt
  handler that escapes as the engine's section ends would then leave a cancelled token in no
  mailbox. Not run, as no check can plant it. The review's plant, the mailbox held while a
  queued token is cancelled, cannot tell the two apart: the mutant's own append blocks in a
  critical section of its own, and the handler runs after it. The plant that can, the
  engine's mutex held while the cancel waits for it, races the engine's thread for that mutex
  as the hold ends, and whichever takes it decides who completes the token. The append stays
  inside `complete-locked!`, the one place a token becomes done.
