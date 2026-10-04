# ADR-0014: The memory gate is Valgrind on Linux, and it must be seen to fail

- **Status:** Accepted
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
