# Engine mutation log (M3 slice 2)

Each mutant was applied to a fresh copy of `src/`, and `tests/test-engine.sps` ran against it in
the container (Chez 10.4.0, libcurl 8.20.0), or `tests/test-native.sps` where a row says so.
The sweeps' drivers were scratch scripts; each row gives the change and the checks that failed.
A mutant passes only if its suite exits 0 on it.

There were two sweeps. The first ran on the engine as first built, whose waits held the
engine's mutex through a critical `dynamic-wind`. The slice's adversarial review then found
that design deadlocks, and eight checks that could not fail. The second sweep ran on the
engine as it stands, whose waits poll (ADR-0013, amended 2026-10-25, after the slice's
review).

## The first sweep, on the first engine

| Mutant | Change | Failed |
|---|---|---|
| `poll-plain` | `curl_multi_poll` through `bind-required`, plain | the collection bound beside an idle engine: the child was killed at 60 s |
| `wait-sectioned` | `wait-until`'s wait inside `critical-section` around `with-mutex` (the plan's §3.4 as first written) | the collection bound beside a caller awaiting a 1 s drip |
| `wait-plain` | `wait-until`'s wait in `with-mutex` alone, no critical section | Ctrl-C while a caller awaits a 2 s drip: the handler ran when the drip ended |
| `no-owner-raise` | native's `check-owner` never raises `&curl-wrong-thread` | the engine's multi handle used from the main thread |
| `cancel-queued-as-message` | a cancel of a queued token sent as a message, as a live one's | a queued cancel: one transfer started |
| `stop-sets-up-batch` | a stop sets up the submits in its batch, then stops them | a stop with transfers queued and live: the queued ones started |
| `stop-leaves-live` | a stop takes no live transfer out | the stop's two checks: the engine failed on its table check |
| `submit-after-stop-queued` | a submit to a stopped engine queued, not refused | after a stop: the submit was not refused |
| `url-checked-late` | `prepare-transfer` does not parse the URL at submit | the URL refusals at submit, and the CA file's after them |
| `one-at-a-time` | the loop takes no message while a transfer is live | the eight drips' overlap, a live cancel, two faults and a stop |
| `log-thread-zero` | the chunk log records thread 0 | every chunk on the engine's thread, twice |
| `fault-never` | a planted fault never raises | each of the seven fault checks |
| `cancel-without-take-out` | a live cancel completes the token, and leaves the transfer in | nine checks: the live cancel, the race, the faults and the stop |
| `fail-skips-batch` | a failed engine does not complete the turn's batch | first: a hang, killed at 400 s, naming no test. Now the take and setup faults, by name |
| `no-broadcast` | a completion wakes no waiter | first: nothing. Now twenty awaits in a row within 1000 ms |
| `stop-at-failing` | a stop returns while the engine is still failing | first: nothing. Now the stop beside thirty live transfers, 3 runs of 3 |
| `slot-kept` | a stop frees the multi handle, and keeps the slot | five checks: after a stop, the children's counts, and the suite's last check |

## What the sweep changed

- **Three mutants passed, or hung, the first time.** The suite then gained:
  - `awaited-within`, a bounded await, in every fault and stop check, so a token never
    completed fails a named check instead of hanging the suite;
  - twenty awaits in a row within 1000 ms: a wait that woke only at its 100 ms timeout took
    about 2 s;
  - a fault beside thirty live transfers, whose counts are read the moment stop returns: one
    transfer's cleanup was too quick for a stop that returned early to see.
- **The engine had one bug the suite found before the sweep:** a failed engine marked itself
  failed before its cleanup, so a stop returned while the engine's thread was still freeing.
  The engine is now failing until its cleanup ends, and failed after.
- **The plan's load check was dropped.** It passed with `make-curl-engine`'s early reference
  removed, 20 runs of 20: a top-level program runs the load before its first line (ADR-0002,
  amended 2026-10-25).
- **The count race the conversion found.** native's `curl-multi-perform` and
  `curl-multi-info-read` made and freed a counted block for their slot on every call, so a
  read of the counts as an await returned found it 6 times in 100. The engine now holds one
  slot from start to stop (ADR-0014, amended 2026-10-25), and the transfer suites read the
  counts directly, with no settling: test-transfer, test-transfer-tls and test-engine passed
  5 runs of 5 each.
- **Stability:** the unmutated suite passed 5 runs of 5, about 7 s each, and under the gate's
  Valgrind.

## The transfer suites' conversion

The agent that converted `test-transfer` and `test-transfer-tls` ran 23 mutants against copies
of `src/`, each failing a named check. Among them:
- the pins set after the URL;
- `set-tls-options!` skipped;
- the header list freed before the easy handle, and the easy handle made before the header
  list;
- the chunk log's length or thread wrong;
- the URL left unchecked at submit, and the checks reordered;
- the planted fault dropped, or checked after the limit;
- `write-body` left unlocked: 96 of 195 checks, with libcurl's "invalid memory reference";
- the plan holding the caller's strings;
- an engine that takes one transfer at a time, or keeps its multi handle at stop;
- `locked` without its critical section, in transfer and in the engine.

I regenerated four from the current `src/` and reran them: `pins-after-url`,
`free-slist-first`, `skip-tls` and `no-url-check-at-submit` each failed the checks it reported.

## What the review found

The slice's read-only adversarial review, on Opus, found:

- **The wound wait deadlocks the process.** Four caller threads, each submitting and awaiting
  in a loop, hung within 1 s, 3 runs of 3, which I reproduced. An awaiter holding the engine's
  mutex with interrupts on joined a collection, while another thread blocked on that mutex
  with interrupts off stayed active. No check had two threads awaiting while collections ran.
  The maintainer chose polling waits.
- **Eight mutants that passed every check:**
  - `fail-skips-queue`: the queued case's test planted its fault after the token was set up;
  - `complete-not-idempotent`;
  - `cancel-no-live-check`: the race check never reached a stale cancel;
  - `stop-not-stopping`, `start-no-raise`, `cancel-no-wakeup` and `stop-no-wakeup`;
  - `owner-three-only`: only three wrappers' thread checks were ever watched failing.
  
  It also found `wakeup-unchecked`.
- **A way to lose a token.** `take-out!` deleted the transfer from the table before freeing it,
  so a raise in the free left the token in no table, never completed.

## The second sweep, on the engine as it stands

| Mutant | Change | Failed |
|---|---|---|
| `wait-wound` | the first engine's wait: the mutex held through a critical `dynamic-wind`, across a timed wait | four caller threads awaiting together; twenty awaits in a row |
| `wait-in-critical` | the polling wait inside `critical-section` | first: a hang of the whole suite. Now, with every await in the suite bounded: the collection bound beside an awaiting caller, four awaiters together, and Ctrl-C |
| `wait-spin` | no sleep between reads | the child's CPU check: the process spent the whole wait on the CPU |
| `wait-long-sleep` | a fixed sleep of 100 ms | four awaiters together; twenty awaits in a row |
| `poll-plain` | `curl_multi_poll` plain | the collection bound beside an idle engine |
| `no-owner-raise` | no `&curl-wrong-thread` | the engine's multi handle used from the main thread |
| `owner-three-only` (test-native) | the raise kept for perform, poll and info-read alone | every wrapper on another thread's handle |
| `wakeup-unchecked` (test-native) | `curl-multi-wakeup` checks no handle | wakeup of an easy handle and of a freed multi |
| `cancel-queued-as-message` | a queued cancel sent as a message | the queued cancel; cancelled-then-stopped |
| `cancel-no-wakeup`, `stop-no-wakeup` | no wakeup after the message | a cancel and a stop beside a drip idle 2 s between bytes |
| `stop-not-stopping` | a stop does not mark the engine stopping | a submit while stopping |
| `submit-after-stop-queued` | a submit to a stopping or stopped engine queued | the same, and after a stop |
| `complete-not-idempotent` | a done token's outcome overwritten | cancelled-then-stopped |
| `cancel-no-live-check` | a cancel takes out a token with no live transfer | a live drip cancelled twice while held, and 13 more |
| `stop-sets-up-batch`, `stop-leaves-live` | as in the first sweep | the stop's checks |
| `one-at-a-time` | one transfer at a time | eight checks, the overlap among them |
| `cancel-without-take-out` | a live cancel leaves its transfer in | 14 checks |
| `table-first` | the table lets a transfer go before it is freed | the fault at `free`, and four more |
| `fault-never` | no planted fault raises | 12 checks |
| `fail-skips-batch`, `fail-skips-queue` | a failure skips the batch, or the queue | the fault at setup; the fault at take |
| `start-no-raise` | a failed start returns its engine | the fault at start |
| `stop-at-failing`, `slot-kept` | as in the first sweep | the stop beside thirty live transfers; 16 checks |
| `url-checked-late`, `log-thread-zero` | as in the first sweep | the submit refusals; the chunk threads |

New checks, each with its mutant above:
- four caller threads awaiting together, in a child;
- twenty awaits in a row, and the CPU check, each moved into the same child, since every await
  in the suite itself is now bounded and polls `curl-token-done?`;
- a live drip cancelled twice, counted stale;
- cancelled-then-stopped;
- a submit while stopping;
- a cancel and a stop beside an idle drip, each within 300 ms;
- faults at `start` and at `free`, and `take` moved before the queue is taken;
- in test-native, every wrapper on another thread's handle, and `curl-multi-wakeup`'s checks.

## The scoped review of the fix round

A second read-only review, on Opus, found no deadlock left in `src/`, and these gaps, each
now closed:

| Mutant | Change | First | Now fails |
|---|---|---|---|
| `cap-200ms`, `fixed-50us` | the poll's sleep capped at 200 ms, or fixed at 50 µs | passed all 43 checks | five 500 ms drips each awaited within 30 ms of a watcher seeing them done; the CPU check, now 2% of the wait |
| `interrupts-unchecked` | a wait with interrupts off is not refused | an await in a critical section hung its process | an await, a stop and `make-curl-engine` in critical sections, each refused, in a child |
| `table-key-by-easy` | a failed engine deletes a table entry by the live record's easy field, cleared once freed | the table kept an entry after the stop | the fault at `free`, now planted after the transfer is freed |
| `await-no-wait` | an await reads the outcome once, never waiting | the four-awaiters child counted every return | that child counts 200s alone, and its collections |
| `stop-never-signals` | a stop never marks the engine stopped | the suite hung, naming nothing | every stop in the suite is bounded at 20 s, on a thread of its own |
| `slot-unchecked` (test-native) | a slot is not checked | passed | a slot of 0, -8 or a string refused |
| `take-fault-outside` | the take fault planted on a read before the take, in its own hold | a submit between the two could miss it | the fault is planted in the take's own hold |

It also found that the race check cannot show it reached a stale cancel: 1 in 300 tries did. The
stale branch is held by the double cancel, and the counter's doc no longer claims the race.
