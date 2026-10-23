# ADR-0014: The memory gate is Valgrind on Linux, and it must be seen to fail

- **Status:** Accepted; amended 2026-10-16: one suppression, for Guix's glibc, in the
  container only ([amendment](#amendment-2026-10-16-one-suppression-for-guixs-glibc-in-the-container-only)),
  what slice 5 built ([amendment](#amendment-2026-10-16-what-slice-5-built)), and the gate on
  every pull request ([amendment](#amendment-2026-10-16-the-gate-runs-on-every-pull-request-and-cannot-see-chezs-heap)),
  and the counters ([amendment](#amendment-2026-10-23-the-counters-are-built-m2-slice-1))
- **Date:** 2026-10-04
- **Scope:** chez-curl: every suite that touches native memory, locally and in CI
- **Related:**
  - chez-libuv ADR-0003 (Valgrind is the sole gate) and its `check-memory-gate`;
  - chez-cmark-gfm ADR-0003, and its open PR #23;
  - [ADR-0006](0006-pinned-guix-container.md), amended here to carry Valgrind;
  - [ADR-0012](0012-engine-thread-owns-every-handle.md) (per-engine state);
  - [the harness plan](../2026-10-04-harness-plan.md).

## Context

AGENTS.md asks for C handled *safely*. chez-curl binds libcurl directly (ADR-0001), so every
free is Scheme's job: `curl_free`, `curl_easy_cleanup`, `curl_slist_free_all`,
`foreign-free`.

Both siblings make Valgrind on Linux their gate. chez-libuv's ADR-0003 records what made
its gate trustworthy:

| Amendment | What it records |
|---|---|
| 2026-08-18 | It adds `--undef-value-errors=no`. Real CI output showed hundreds of undefined-value reports inside `S_call_help`, Chez's own entry point for C calling back into Scheme. A suppression file keyed on that function was rejected as whack-a-mole. |
| 2026-09-27 | It records that both arms "were vacuous". `timeout 900` sat between `valgrind` and Chez, so Valgrind checked `timeout` and Chez ran natively. The cap now wraps Valgrind, and `make check-memory-gate` plants defects that the gate must fail on. CI runs that check before `test-memory`. |
| 2026-09-28 | It adds `--errors-for-leak-kinds=definite`, so a "possibly lost" block no longer fails the run without a loss record. |

chez-cmark-gfm's main still lacks those fixes. Its macOS ASan arm sets
`DYLD_INSERT_LIBRARIES` around `sh -c`, which drops it, so ASan never loads. The fix is its
open PR #23. chez-cmark-gfm calls no callbacks, so it never met `S_call_help`'s reports.

Valgrind runs 10 to 50 times slower than native. chez-cmark-gfm runs it in CI on `main`, on
tags and on request, to save CI time. LeakSanitizer does not exist on macOS arm64
(chez-cmark-gfm's Makefile says so), and chez-curl has no macOS CI (AGENTS.md).
ADR-0006's container had no Valgrind.

## Decision

1. **Valgrind on Linux is the memory gate.** Each suite runs as
   `timeout N valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite $CHEZ --program …`.
   A run fails on any error Valgrind reports and on definite leaks. `timeout` wraps Valgrind
   and never sits between it and Chez.
2. **`make check-memory-gate` proves the gate can fail.**
   - Planted defects (a heap overrun and a definite leak) must make `make test-memory` fail
     with Valgrind's own marker in the log.
   - A plain run of each planted program must exit 0 and say what it planted.
   - CI runs this check before `test-memory`.
3. **The gate carries no suppressions, and starts without `--undef-value-errors=no`.**
   chez-libuv's `S_call_help` reports are expected once chez-curl has callbacks, at M2.
   The flag is added only when a run shows reports from Chez's own code, and that run is
   recorded in the mutation log.
4. **`make test-memory` runs every suite and fails if any failed.** It does not stop at the
   first failure. It uses a longer per-suite timeout than `make test`.
5. **CI runs the gate on pushes to `main`, on tags and on request** (a workflow input). A run
   that skips it says so in a notice, as chez-cmark-gfm's does. Locally it runs in the
   container, whose manifest gains `valgrind` (ADR-0006 amendment).
6. **ASan on the Mac is a supplementary local check.** It is loaded into Chez itself, using
   chez-libuv's recipe rather than chez-cmark-gfm's. It makes no leak claim.
7. **Counters give per-test granularity, which Valgrind lacks.** Every native object
   chez-curl allocates is counted, always on, per engine (ADR-0012). Suites assert that the
   counts move and return to zero.

### Rejected

- **chez-cmark-gfm's recipe as its `main` has it.** Nothing proves that gate can fail, and
  its macOS arm never loads ASan.
- **The gate on every pull request.** It is too slow for every PR; a PR that needs leak
  evidence asks for it.
- **ASan as the gate.** It cannot detect leaks on arm64 macOS, and there is no macOS CI.
- **Suppression files.** chez-libuv rejected them as whack-a-mole against Chez's own
  internals.

## Consequences

- **Tags always carry fresh leak evidence. Ordinary PRs carry none unless they ask.**
- **M2's first callback is when to measure whether the undefined-value flag is needed.**
- **The container grows by Valgrind,** and its self-test checks that Valgrind instruments
  `$CHEZ` (ADR-0006).

## Amendment, 2026-10-16: one suppression, for Guix's glibc, in the container only

Settled by the maintainer before slice 5 built the gate.

- **The leak.** In the container, loading libcurl loses one block, every time.
  - It is 171 bytes with the container's `GUIX_LOCPATH`, and 103 without it. It is one
    block under every locale setting tried: `LC_ALL=C`, and no locale variables at all.
  - p11-kit's constructor calls `newlocale`, and the block is lost in
    `compute_locale_search_path`. Guix's glibc patch, `glibc-versioned-locpath.patch`,
    adds that function to honour `GUIX_LOCPATH`, and upstream glibc has none.
  - A C program that only `dlopen`s the library loses the same block. So does one that
    loads `libp11-kit` alone, and one that loads `libnghttp2` loses nothing. An empty Chez
    program loses nothing.
- **Ubuntu 24.04 loses nothing.** This was measured in Docker on 2026-10-16, with Ubuntu
  24.04.5 and Valgrind 3.22.0.
  - Both of its libcurls (8.5.0) load p11-kit 0.25.3: the OpenSSL one through `libldap` and
    GnuTLS, and the GnuTLS one directly.
  - Each load loses 0 bytes, as does `libp11-kit` loaded alone.
- **Decision 3 is amended: the gate carries one suppression, used in the container only.**
  - The file holds one entry, for a definite leak allocated under
    `compute_locale_search_path`, with no frame from Chez or chez-curl.
  - It is passed whenever `GUIX_ENVIRONMENT` is set, which the container sets. CI runs
    Ubuntu's glibc and passes no suppression.
  - `make check-memory-gate` holds it honest:
    - the file holds exactly that one entry;
    - in the container, a run that loads libcurl reports the entry used, so a stale entry
      fails;
    - the planted leak still fails with the suppression on.
- **Why this is not what decision 3 rejected.** chez-libuv rejected suppressions as
  whack-a-mole against Chez's own internals, which move with every Chez. This is one fixed
  block in a Guix-only glibc patch, outside both Chez and chez-curl. And CI, the gate of
  record for `main` and tags, never passes the suppression.
- **Rejected:**
  - **tolerating a baseline of one block,** because the byte count moves with the
    environment, and a new one-block leak could take its place;
  - **gating only on a libcurl without GnuTLS,** because the container has none, and the
    gate must run locally;
  - **exempting the suites that load libcurl,** because from M1 that is nearly all of them.

## Amendment, 2026-10-16: what slice 5 built

Built, then reviewed twice. Each review's fixes closed a class the first build left open.

- **The command.** Every suite runs as
  `timeout --foreground N valgrind -v --command-line-only=yes --log-file=build/memory/SUITE.valgrind`,
  then decision 1's four flags, then the suppression in a Guix environment, then
  `$CHEZ --libdirs … --program SUITE`.
  - `--foreground` matches `make test`, so Ctrl-C at a terminal reaches Valgrind at once.
  - Valgrind writes to its own log, and the suite's own output goes to `SUITE.log`. A suite
    shares Valgrind's PID, so it could print lines that look like Valgrind's: measured, a
    forged `==7== ERROR SUMMARY: 0 errors` line carried the same PID as the real one. All
    evidence is read from `SUITE.valgrind` alone.
- **Nothing outside the command line may change what Valgrind checks.**
  - `--command-line-only=yes` stops `VALGRIND_OPTS`, `~/.valgrindrc` and `./.valgrindrc`.
    It does not stop `VALGRIND_LIB`, which moves Valgrind's `default.supp`. Measured: with
    it pointed at a copy whose `default.supp` hid everything, the planted leak passed.
  - So `make test-memory` refuses every `VALGRIND_*` variable and both `.valgrindrc` files,
    naming each, before any suite runs.
  - Each suite's `Valgrind options:` block must equal the gate's list exactly, in order. An
    option added through the `VALGRIND` make variable fails. Since a later option overrides
    an earlier one, only an option the gate leaves unset could weaken it, such as
    `--undef-value-errors=no`. The block rule catches that too.
  - The `Reading suppressions file:` lines must be exactly Valgrind's own `default.supp`,
    and in Guix our file too. The gate learns `default.supp`'s path from Valgrind, with
    `VALGRIND_LIB` unset.
  - The suppression file's path is fixed with `override`. A make command line that named
    another fed both the command and its allowlist, and the planted overrun passed.
- **A pass needs evidence that Valgrind checked Chez.** A suite that exits 0 passes only when
  its Valgrind log shows all of these:
  - `Command:` naming `$CHEZ` and the suite;
  - the first program Valgrind read symbols from is the file `$CHEZ` names, so a wrapper
    script, which runs a shell, fails;
  - `ERROR SUMMARY: 0 errors from 0 contexts`;
  - the allowlisted suppressions;
  - in Guix, exactly one suppressed block when `libp11-kit` was read, and none otherwise.

  The lower bound of that last rule fails closed, and no plant can fail it, since Guix
  always loses the block. The awk that checks this evidence must exit 0 and print exactly
  `ok`. An earlier version took empty output as a pass, so an awk that failed passed the
  wrapper plant.
- **The entry is four glibc frames:** `realloc`, `argz_add_sep`,
  `compute_locale_search_path`, `newlocale`. It has no p11-kit frame, because only an object
  path holding a store hash could name one, and that path changes with every pin.
- **Two suites sharing a name** would share logs, so they are refused.
- **`make check-memory-gate`** holds every rule above with a standing case, each planted in a
  copy so it keeps running: 39 cases in a Guix environment, and 33 outside, where the
  suppression cases are skipped and say so.
  - The plants: an overrun of a `foreign-alloc` block, and a definite leak, each failed by
    Valgrind's own marker. A clean program that exits 1 must fail, and a hang must be
    HUNG. With no suite to run, the gate fails.
  - Each option source, and each forged or stale log, has its own case.
- **Measured.** In the container, every suite passes in about 110 seconds, and
  `check-memory-gate` takes about 110. On Ubuntu 24.04's Valgrind 3.22, in Docker with C
  stand-ins for Chez, the recipe behaved the same: the options block has the same shape,
  and every refusal and every evidence rule held.
- **Not covered:**
  - Valgrind follows no child process, since `--trace-children` is off. So the Chez
    processes `test-library-loading` spawns run unchecked.
  - The gate trusts the programs `VALGRIND` and `TIMEOUT` name.

## Amendment, 2026-10-16: the gate runs on every pull request, and cannot see Chez's heap

Both were settled by the maintainer.

- **Decision 5 is amended: CI runs the gate on every run.** That means every pull request,
  every push to `main`, and every `v*` tag. Slice 5 measured the whole gate at a few
  minutes, against the "too slow for every PR" reason the option was rejected for. If the
  memory job comes to take longer than 20 minutes, a decision moves it back to `main` and
  tags. Ordinary pull requests now carry leak evidence.
- **Valgrind cannot see into Chez's heap.** Measured under the gate, both of these passed
  with 0 errors:
  - a `memcpy` of 24 bytes into a 23-byte bytevector;
  - a 777-byte `foreign-alloc` block, wrapped in an ftype pointer and dropped, which
    Valgrind called "still reachable", even after a full collection.

  Chez's heap is one live block to Valgrind, and a raw address any object held there is a
  reference. The plants pass only because they use shapes Valgrind can see.
- **So the gate is two checks.**
  - Valgrind covers `malloc`'d memory and the C side.
  - Overruns into the heap are stopped by construction. One checked wrapper owns every
    copy between a bytevector and foreign memory. `test-collect-safe` reads every binding's
    types as an allowlist. A type that hands C a pointer into the heap needs a reviewed mark
    on its row: a bytevector's data, or a string whose callee keeps no pointer.
    `scheme-object` is never allowed (ADR-0001 and ADR-0013, amended).
  - Leaks of foreign memory that a Chez object held are caught by decision 7's counters,
    now a gate: a suite fails if any count is not zero at its end. The counters arrive
    with M2's engine, with a plant that proves they fail: an ftype-wrapped block, dropped.

## Amendment, 2026-10-23: the counters are built (M2 slice 1)

- **Decision 7 is built,** per process until M3 brings engines.
  - `(curl private counters)` counts six kinds: `block`, `easy`, `url`, `slist`, `curl-string`
    and `transfer`. It sits behind a mutex, has no reset, and never loads libcurl. A count-down
    below zero raises, as a double free.
  - `(curl private memory)` makes and frees every foreign block, counted, with a table of the
    live ones. Freeing an address that is not live raises before anything reaches `free`.
  - native counts every easy handle, `CURLU` handle and `curl_url_get` string.
- **`suite-exit-status` fails any suite whose counts are not all zero at its end,** naming each.
  `check-test-fails` plants a suite whose tests all pass, but which drops a counted block in an
  ftype pointer, as decision 7 asked. It fails through the counters' line.
- **The gate counts per process.** A counted block leaked on a refused load passed every suite,
  since the decoys' refusals run in child probes (the review's mutant). So every child a suite
  spawns that reaches native prints its counts, and the suite asserts them zero. The
  preflight's output is its own contract and stays whole. Each refusal path it reaches is also
  run through `refusal-probe`, which reports counts.
- **Valgrind, under the slice's mutants:** skipping `curl_free` was `definitely lost: 1,973 bytes
  in 62 blocks`, and leaving the NUL terminator out an uninitialised read. `make test-memory`
  passed all 20 suites in the container, and in the Docker stand-in of CI's memory lane, under
  Valgrind 3.22.
