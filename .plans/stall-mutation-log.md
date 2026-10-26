# Stalled-lookup mutation log (M3 slice 3)

Each mutant of the first table was applied to fresh copies of `src/` and `tests/`, and its
suite ran from there in the container (Chez 10.4.0, libcurl 8.20.0). The driver was a
scratch script. A mutant passes only if its suite exits 0 on it. The stall checks' names
below drop their common opening, "under the stand-in getaddrinfo, each lookup stalled
3000 ms, on libcurl 8.20.0", and name the entry of 8.20.0's row: both settings, without the
transfer's `QUICK_EXIT`, or without `CURLMOPT_QUICK_EXIT`.

The two agents' sweeps follow, each in its own copy of the tree. I reran the final checks of
each, and two mutants of each, before taking their files.

## The engine, the transfer and the stall checks

| Mutant | Change | Failed |
|---|---|---|
| `multi-setopt-skipped` | the engine takes `CURLM_OK` for the multi setopt, and makes no call | both settings, and without the transfer's: the stop stalled |
| `multi-setopt-value-0` | `CURLMOPT_QUICK_EXIT` set to 0 | the same two |
| `verdict-any-set` | every other `CURLMcode` judged set | `multi-quick-exit-verdict`, over its domain |
| `verdict-unknown-refused` | `CURLM_UNKNOWN_OPTION` refuses the engine | the same. Only the floor's and 8.5.0's lanes would also refuse every engine |
| `multi-switch-ignored` | the engine sets the multi option whatever its switch says | without `CURLMOPT_QUICK_EXIT`: set, not off, and the stop prompt |
| `transfer-switch-ignored` | the engine asks every transfer for `QUICK_EXIT` | first: the timeout flake below, and nothing of its own. Then without the transfer's: four transfers set it, not none |
| `transfer-quick-never` | the engine asks no transfer for `QUICK_EXIT` | first: nothing. Then both settings, and without `CURLMOPT_QUICK_EXIT`: none set it, not four |
| `quick-count-dropped` | `set-pinned-options!` counts nothing | the same two |
| `without-unchecked` | `make-curl-engine-without-quick-exit` takes any list | its refusal, then 24 checks after it, as the engines it made ran on |
| `pin-dropped` | `pinned-settings` answers the pins alone | `pinned-settings`, written out and held whole |
| `set-pins-without-quick` | `set-pinned-options!` sets `pinned-options` | `set-pinned-options!`, held whole |
| `known-always` | `quick-exit-known?` answers #t | its definition, held whole. On the floor every transfer would fail, `unknown-option` |
| `owned-dropped` | `QUICK_EXIT` out of `owned-option-names` | the list written out, the seam's refusal of `QUICK_EXIT`, and where the names stand |
| `quick-pin-zero` | `quick-exit-pin` at 0 | `quick-exit-pin` and `pinned-settings`, written out |
| `setopt-owner-unchecked` | `curl-multi-setopt-long` checks no thread | the engine's multi handle used from this thread |
| `child-ignores-log` | the child never judges an event stalled | without `CURLMOPT_QUICK_EXIT`: the stop, `(slow ...)` |
| `child-no-wait` | the cancel is sent without waiting for the lookup | first: nothing, as a fixed 200 ms pause covered it. Then all three: the cancel found the token queued, and no lookup stalled |
| `child-stop-no-wait` | the stop is sent without waiting for the lookup | the same, by the stop |
| `no-preload` | no `LD_PRELOAD` | all three: every lookup failed at once |
| `short-stall` | a 300 ms stall | all three |
| `row-stop-prompt` | 8.20.0's control row says the stop is prompt | without `CURLMOPT_QUICK_EXIT`: the stop stalled |
| `row-renamed` | 8.20.0's row named 8.20.1 | the row for this libcurl; the suite printed the row it measured |
| `linux-false` | `linux?` answers #f | `linux?` against `uname -s` |
| `stand-in-no-stall` | the Linux half stalls nothing | all three |
| `stand-in-no-answer-log` | the stand-in logs no answer | without `CURLMOPT_QUICK_EXIT`: the stop, `(slow ...)` |

### What the sweep changed

- **Three mutants passed, and one failed for the wrong reason, the first time.**
  - The child reported whether transfers set `QUICK_EXIT` from its own arguments, not from what
    the engine did, so `transfer-quick-never` passed: on 8.20.0, a transfer's `QUICK_EXIT`
    changes no stall. Now `set-pinned-options!` counts each transfer once libcurl has taken
    the option, and the child prints how many of its four did.
  - The cancel and the stop waited for the stand-in's log and then for a fixed 200 ms, which
    alone covered the lookup's start, so removing the wait passed. Now each is sent the moment
    the log shows the lookup stalling.
  - `transfer-switch-ignored` failed on a timeout whose code 28 came 1,014 ms after it fell due,
    which the mutant does not explain. 160 timeouts since, on fresh engines and on one, came
    within 8 ms. The timeout's bound is now 2,000 ms (ADR-0019, amended 2026-10-25).
- **`test-engine` gained the thread check on `curl-multi-setopt-long`,** and `linux?` held to
  `uname -s`, before the sweep.

## After the slice's review

The review's mutants that passed, and the fixes' own, each rerun the same way. `verdict-ignores-before`
also ran in Docker, on the floor and Ubuntu's 8.5.0 with OpenSSL and with GnuTLS, twice each.

| Mutant | Change | Failed |
|---|---|---|
| `refusal-ignored` | an answer but 0 and 6 taken as unknown | first: nothing, as no libcurl gives one. Now the refusal of 1 and 10 |
| `answer-ignored` | the engine judges libcurl's answer, not the planted one | the refusal of 1 and 10 |
| `cancel-stop-unjudged` | the cancel engine's stop judged prompt, untimed | without `CURLMOPT_QUICK_EXIT`: that stop stalled |
| `timeout-stop-unjudged` | the timeout engine's stop judged prompt, untimed | the same, by that stop |
| `verdict-ignores-before` | an event judged stalled whenever the stand-in had answered by its end | 0 in the container: no stop there follows an event that waited. In Docker, the floor's row and 8.5.0's without `QUICK_EXIT`, 2 runs of 2 each: both stops stalled |
| `drip-gap-from-start` | the drips judged by when the second ended, not by the gap | the drips together, judged serial |
| `drip-gap-threshold-0` | the gap threshold at 0 | the suite's constants; the drips together |

The review also ran `test-variadic` with its two runs in the other order, under Valgrind and
54 busy loops: the drips together ended at 1,793 and 1,863 ms, and failed the 1,600 ms bound
then used, 2 runs of 2. Judged by their gap, the same order and load passed 2 runs of 2,
together 1,705 and 1,240 ms in all but 27 and 2 ms apart.

## The constants (the constants agent)

Each in a copy of `src/`, `tests/` and `packaging/`, run against the container's 8.20.0
headers and the floor's 7.85.0 headers, prepended to `C_INCLUDE_PATH` (`traps.md`). Exit 0 on
one lane is by design where the other lane catches it.

| Mutant | 8.20.0 headers | 7.85.0 headers |
|---|---|---|
| `curlmopt-quick-exit` 21 → 22 | its row | 0: unchecked there |
| `curlmopt-max-total-connections` 13 → 14 | its row | its row |
| the gate raised to 8.21.0 | the presence test, the gate's pin, `c-line` | the pin, `c-line` |
| the gate at the floor, 7.85.0 | not newer than the floor, the pin, `c-line` | the program fails to compile, by name |
| the probe misspelt | the presence test | 0: undeclared either way |
| the probe's program broken | the controls, the presence test | the same |
| the probe ignores its name | the controls, the presence test | the same |
| the `#if` inverted | the row: unchecked, not 21; `c-line` | the compile, the unchecked test, the presence test |
| the `#if` inverted, unchecked always | the unchecked test: the headers are not below the gate | the compile, the unchecked test |
| the `#else` makes up 21 | 0: not reached | the unchecked test: answered, not unchecked |
| `curl_multi_setopt`'s result `CURLcode` | the prototype compile, its spelling | the same |
| its variadic types `(uptr)` | its fit, the variadic pin | the same |
| its row removed | every binding has a row, its fit, the pin | the same |
| `CURLMoption` as `CURLoption` | the prototype compile, its spelling | the same |
| the floor set to 8.20.0 | not newer than the floor | the same |
| every constant gated | `c-line`, the gate holds one constant alone | the same |
| the gate's key misspelt | the key test, the pin, `c-line`, the gate alone | the compile, and the same |
| the gate's text and number disagree | the shape test, the floor test, the pin, `c-line`, the gate alone | the compile, and the same |

I reran the first two rows' mutants on 8.20.0's headers: each failed as the table says.

## The variadic checks (the variadic agent)

Each in a copy, `test-variadic` in the container on 8.20.0 unless a row says otherwise.

| Mutant | Failed |
|---|---|
| the wrapper passes 0 | the serial drips; -1, which answered 0 |
| the wrapper passes the value plus one | the serial drips; -1 |
| the binding typed `(uptr int int)` | -1, which answered 0; 2^40, which Chez refused for an `int` |
| serial and together swapped | both drip checks |
| the threshold 2,500 ms | the suite's constants; the serial drips |
| the threshold 1,000 ms | the suite's constants; the drips together |
| the settings swapped, 2 and 1 | the constants; both drip checks |
| 8.20.0's -1 row at 0 | -1, "as libcurl 8.20.0's row says" |
| 8.20.0's -1 row removed | the row for this version; -1. It printed `("8.20.0" 10)` |
| `test-collect-safe`'s via line without `curl_multi_setopt` | that test alone |
| the pointer wrapper passes the value plus one | both PRIVATE round trips; both drips, not run |
| the drips' deadline 500 ms | the constants; both drips, timed out, nothing left |
| `WRITEDATA` dropped | both drips: no bodies in the sink. With `/dev/null` as the sink this passed, so the sink is a file the suite reads |

`check-variadic`, each in a scratch tree:

| Tree | Result |
|---|---|
| the old `test-collect-safe` | all six static steps failed |
| `apple_arm64` forced on x86-64 | the multi use's arm64 step failed: no test through `curl-multi-setopt-long` failed |
| that, with the multi use typed `(uptr int int)` | the arm64 step passed: two tests through it failed by name |
| 8.20.0's -1 row removed | the control stopped, printing the row to add |
| `NODE` at a missing path | the control stopped at `test-variadic`'s drips |

I reran the first and third rows' mutants: each failed as the table says.

## The current lane (2026-10-26)

The lane on the current libcurl ([ADR-0020](decisions/0020-a-ci-lane-on-the-current-libcurl.md)).

| Mutant | Change | Failed |
|---|---|---|
| `pin-8.23` | `current_version` at 8.23.0, which has no sum | four of `test-check-floors`' `--current` rows: no sum is pinned for it |
| `ignored` | `--current` taken and dropped, so the floor is built | the same four: the floor's tarball, not the current one's |
| `reads-floors` | `--current` reads the floors file first | `--current` with no floors file |
| the wrong library | the job's step with `CHEZ_CURL_LIBCURL` at the runner's 8.5.0, in Docker | the step: "make build did not load the libcurl this lane built", exit 1, before `make test` |

The floor, rebuilt in Docker by the changed `build-curl.sh`, listed the same features and
protocols as spike E1's build of it, so its line's reordering changed nothing.

