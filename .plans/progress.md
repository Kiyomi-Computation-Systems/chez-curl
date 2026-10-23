# Progress ledger

Where chez-curl stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a
close-out under **Close-outs**, newest first.

## Now

- **Milestone:** M2, one blocking request, plaintext and TLS (brief §8), per the
  [M2 plan](2026-10-19-m2-plan.md).
  - **Slice 1 is built** on `m2/foundations` (§4), not yet merged, with its
    [mutation log](foundations-mutation-log.md). It binds no setopt or getinfo option:
    - the counters, as a gate, with every child that reaches native reporting its counts;
    - counted foreign blocks;
    - the checked copy and C strings;
    - the URL API: 70 cases as shared answers and version rows, and the scheme check against
      every protocol the libcurl lists;
    - the checks carried from M0: prototypes, `curlot-types` complete, and a whole layout's
      size.

    ADR-0001, ADR-0002, ADR-0007, ADR-0008, ADR-0013 and ADR-0014 are amended. Its close-out
    goes in on the next branch, once it merges.
  - **Slices 2 and 3,** the plaintext transfer and TLS, wait for the Apple arm64 run.

  M1 (brief §7) is built: PRs #10 and #11. M0 (brief §8) is built.
- **The Mac owes one run for M0 and M1, and it gates M2's slices 2 and 3:**
  - `make check-variadic` on Apple arm64, whose result ADR-0001 records;
  - its drift row for Apple's libcurl 8.7.1, since `make test` fails there until it is
    added. Once slice 1 merges, its URL row too, for the 10 cases that vary;
  - the prototype check reading Apple's SDK headers. It fails closed on what it can't read;
    the list is in the mutation log, §7.1;
  - Node 20.10.0 and the drip's own-arrival check, which have not run on macOS;
  - LibreSSL as the checker on the Mac itself. Docker ran it, built from its tarball, under
    Node 20.10.0 (M1 plan, §8.7).
- **Done:** slices 1 to 6 of the [harness plan](2026-10-04-harness-plan.md) (§6):
  - slice 1, the container and the Makefile skeleton;
  - slice 2, the test harness
    ([ADR-0015](decisions/0015-test-harness-and-scheme-dependencies.md));
  - slice 3, loading (ADR-0001, ADR-0002, ADR-0003, ADR-0007, all amended), with its
    [mutation log](loading-mutation-log.md);
  - slice 4, constants and layouts (ADR-0001, ADR-0007 and ADR-0013 amended, ADR-0016
    new), with its [mutation log](constants-mutation-log.md);
  - slice 5, the memory gate and CI (ADR-0014 amended), with its
    [mutation log](memory-ci-mutation-log.md);
  - slice 6, which closes M0: the variadic bindings, the binding-macro routes closed,
    `make dev` and `make clean` (ADR-0001, ADR-0007, ADR-0008 and ADR-0013 amended), with
    its [mutation log](variadic-mutation-log.md).
- **M0's one open item: the Apple arm64 run.** `make test` and `make check-variadic` on the
  maintainer's M1, the only ABI where a missing `(__varargs_after 2)` fails. The Mac was out
  of reach when slice 6 merged, so the maintainer made the run a gate: M2 binds no setopt or
  getinfo option until it passes and ADR-0001 records it. M1 binds no variadic entry point.
- **First macOS run,** 2026-10-16, on the maintainer's Mac: Apple silicon (M1, so arm64),
  Homebrew's Chez 10.4.1, Apple's libcurl 8.7.1. `make test` passes all 13 suites, after a
  fix: a bare `mktemp -d` ignored `TMPDIR` there (`traps.md`). So macOS has run on arm64;
  Linux on arm64 and macOS on amd64 have not. The two suites added since,
  `test-check-nothreads` and `test-variadic`, have not run there.
- **A flaky test in M1's `test-origin`:** `raw /raw/reset-mid-body` saw `eof` where it expects
  `reset`, once. That was in the Docker floor lane, run beside a mutation run and the main lane,
  on 2026-10-23. A rerun with nothing else running passed. How often it happens is not
  measured.
- **CI has never run.** Every job of PRs #8 to #12 was "not started because recent account payments
  have failed or your spending limit needs to be increased". GitHub parsed the workflow and
  listed all six jobs, so the file is valid. What only CI can show is still unshown: Chez
  built from its tarball on the runner, a real `--nothreads` Chez, the suites under Ubuntu's
  Valgrind 3.22, the floor lane at 7.85.0, and the jobs' times.
- **Decided for M2,** by the maintainer:
  - curl's URL verdicts vary by version, so the URL suite holds shared answers and a row
    per libcurl version (ADR-0008, amended 2026-10-19);
  - one checked wrapper owns every copy between a bytevector and foreign memory;
  - the counters become the leak gate, since Valgrind cannot see Chez's heap (ADR-0001,
    ADR-0014, amended).
- **Settled before slice 5:** the leak in the container. Loading libcurl there loses one
  block in Guix's glibc, and Ubuntu 24.04 loses nothing (`traps.md`). ADR-0014 now allows
  one suppression for it, passed in the container only.
- **Waiting on evidence:** ADR-0013 (`__collect_safe`) stays Proposed until spike E1
  at M3. Until then its rules bind as written.
- **Open for M3:** a first reference to `(curl)` from a second thread, made while the load
  runs, raises `cyclic dependency` (ADR-0002's amendment).

## Close-outs

### 2026-10-19 — M1 slice 2: TLS and HTTP/2 for the test origin (PR #11, `bd215d8`)

- **Per-run TLS material, `tests/make-test-pki.sh DIR`.** It makes ten files: two CAs, and
  four leaves, `good`, `expired`, `wrong-host` and `untrusted`. Each failing leaf has one
  fault the good one lacks. The same commands ran unchanged on OpenSSL 3.5.7, 3.0.13 and
  3.0.11, and on LibreSSL 3.3.6. Nothing is checked in (ADR-0005).
- **The TLS faces.** `h2c` is always on. `--pki DIR` adds:
  - `https`, `https-expired`, `https-wrong-host` and `https-untrusted`, each offering only
    `http/1.1` by ALPN;
  - `raw-tls`, the raw scripts over TLS;
  - `h2`, HTTP/2 by ALPN only.
- **The probe gains `--tls SERVERNAME` and `--alpn LIST`.**
- **`openssl` checks each face, portably,** as the maintainer chose. LibreSSL 3.3.6, the
  Mac's `openssl`, cannot check a hostname. So the checks are three facts (ADR-0005,
  amended):
  - `s_client`'s verify errors and code against the run CA;
  - the leaf it serves, against its file;
  - that leaf's SAN line.

  The code is the first `Verify return code` line, and each TLS 1.3 ticket's later line
  must agree with it.
- **`test-origin-tls`, 87 tests;** `test-origin` grew to 116 and `test-curl-testing` to 265.
- **The stop check holds that nothing but the stop explains an end.** It covers the states
  Node's `close()` never ends, and requires silence right up to the stop and an end within
  500 ms after it. It opens two sets of probes 700 ms apart, and stops twice. A 90-case
  sweep of idle-close mutants failed it on Node 24.18.0 and 20.10.0 alike.
- **Node 20.10.0 passed in Docker,** with OpenSSL 3.0.11 and with LibreSSL 3.3.6 as the
  checker.
- **Limits, measured:**
  - Node 20.10.0 leaves an HTTP/2 connection open after a protocol error the origin sent;
  - the stop check cannot tell a destroy from an exit.
- **Built with subagents,** four in all, about 1.81M tokens:

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | builder, then 4 fix rounds by SendMessage | Opus | 874k | about 4 h |
  | review | Opus | 348k | 30 min |
  | scoped review of rounds 1 and 2 | Opus | 317k | 28 min |
  | scoped review of round 3 | Opus | 272k | 38 min |

  The stop check took three reviews, and the cause was my plan. It never said what proves an
  end was the stop's, so each brief fixed the instances found. The check held once briefed
  by mechanism and checked by the sweep.
- **Evidence:** the [TLS mutation log](tls-mutation-log.md): 159 mutations, 150 caught, and
  the 9 left judged equivalent.
- **Carried forward:**
  - for M2 (M1 plan, §8.8): the good face accepted on each TLS backend, as the control, and
    a face offering both `h2` and `http/1.1`;
  - the Mac's run;
  - CI has still never run.

### 2026-10-18 — M1 slice 1: the test origin, the byte probe and the drift guard (PR #10, `79c6df1`)

- **The plaintext origin, `tests/origin.mjs`,** on Node's standard library only.
  - Two faces listen on `127.0.0.1`, port 0.
  - `http` serves `/status`, `/redirect`, `/chunked`, `/echo` and 404, with no `Date` and
    headers in a fixed order.
  - `raw` plays about 30 scripted byte streams: framings, drips, oversized heads and
    protocol errors.
  - It announces one flat JSON line and exits 0 when its stdin closes. A bad client ends
    only its own connection.
- **The byte probe, `tests/wire-probe.mjs`.** It has no HTTP code: it sends the bytes it is
  given and prints every byte it receives, with timings, as Scheme data. `--reset` resets
  through `resetAndDestroy()`, since `destroy()` sends a FIN (measured).
- **The helpers in `(curl-testing)`.** `call-with-origin` holds every origin to a clean stop:
  stdout ended, nothing on stderr, and exit status 0. An `sh` runner records the status,
  since Chez has no `wait`. The announcement reader, `read-within` and the probes are each
  strict.
- **`test-origin`, 110 tests.** Each scenario's whole bytes, in the suite's own copy, and the
  lifecycle:
  - loopback only, and OS-chosen ports;
  - a clean stop, with open connections destroyed;
  - a stated bound on outliving a killed suite, measured at 19.3 s after a SIGKILL
    mid-probe;
  - bad clients, drip timing, every range's edges, and the 64 KiB head limit.
- **The drift guard (ADR-0017).** `test-drift` passes only when the loaded libcurl's five
  fields equal one row of `tests/known-libcurls.sexp`. The rows are Guix's 8.20.0,
  Ubuntu 24.04's 8.5.0, and the 7.85.0 floor. The floor build now names every optional
  library and checks what it installed.
- **Node in CI.** The floor lane installs Node 20 through a pinned `setup-node`.
  `check-floors` holds every `node-version:` to a step's output, and fails closed on YAML
  it cannot read. Node 20.10.0 passed in Docker.
- **Measured first:**
  - Chez has no sockets;
  - Node 20.10.0 and 24.18.0 write the same bytes;
  - `openssl`'s portability, for slice 2.
- **Built with subagents,** four in all, about 1.58M tokens:

  | Agent | Model | Tokens | Time |
  |---|---|---|---|
  | drift builder, in a worktree | Sonnet | 270k | 20 min |
  | origin builder, 4 rounds by SendMessage | Opus | 714k | about 2.5 h |
  | review | Opus | 306k | 31 min |
  | scoped review | Opus | 287k | 25 min |

  The review's blocker was in my plan. `call-with-origin` took stdout's end as a clean
  stop, so an origin that crashed after answering passed. Slice 5's rule, "passes only on
  positive evidence", had not been applied to a process. The `sh` runner's exit status
  closed it.
- **Evidence:** the [mutation log](instrument-mutation-log.md).
- **Carried forward:**
  - slice 2, TLS and HTTP/2;
  - the Mac's run: its drift row, Node 20.10.0, the drip's own-arrival check, and how
    macOS orders data then a reset;
  - CI has still never run.

### 2026-10-17 — M0 slice 6: the variadic bindings, `make dev` and `make clean` (PR #9, `83b6835`)

- **Binds the variadic entry points once per value type.** `curl_easy_setopt` gets a `long`,
  a pointer and a `curl_off_t` binding, and `curl_easy_getinfo` a pointer one, each through
  `bind-variadic`, whose template carries `(__varargs_after 2)`. `curl-easy-option` reads an
  option's id and type from the loaded library.
- **`test-variadic` round-trips values through libcurl without a transfer:**
  - a pointer through `CURLOPT_PRIVATE`;
  - a `long` through `RTSP_CLIENT_CSEQ`;
  - -1 and other signs through `MAXFILESIZE` (`long`) and `MAXFILESIZE_LARGE` (`curl_off_t`).

  Each round trip gets its own sentinel, and every return code is asserted.
- **`make check-variadic`** plants five unannotated bindings. On every platform
  `test-collect-safe` must refuse each, by name. On Apple arm64, the only ABI where a
  missing annotation fails, `test-variadic` must fail too.
- **Closed the binding-macro routes.** The review found that a macro could change what the
  convention reader reads, a hole dating from slice 4. Now:
  - every macro `src/` defines is a row of `known-macros`;
  - plain macros may not take their input apart or be handed a head;
  - `check-seam` rules (h) and (i) hold each library to its path under `src/`.
- **`make dev` and `make clean`,** with `check-dev` and `check-clean`, which run in a fresh
  copy of the tree. That closes M0's Makefile.
- **Measured at the floor first,** in C, on 7.85.0, 8.5.0 and 8.20.0. 8.20.0 clamps
  `RTSP_CLIENT_CSEQ` and refuses a negative one, keeping the old value. That is why each
  round trip has its own sentinel.
- **Built with subagents,** four in all, about 1.77M tokens:
  - the builder on Opus, in a worktree;
  - an adversarial review on Opus;
  - an Opus fixer resumed for five rounds;
  - a scoped review of the fixes on Opus, which found one more route.

  I forecast one builder and one review. The reader's hole took five rounds, because each
  closed the shapes the last probe used. The design that held named the mechanism, and
  could have been the first brief.
- **Evidence:** the [mutation log](variadic-mutation-log.md). Every check has a red run, and
  every mutation fails its check by name. One known limit is recorded: a phantom binding
  from a quoted operand (PH1).
- **Carried forward:**
  - **The Apple arm64 run gates M2** (the maintainer's decision, 2026-10-17). M2 binds no
    setopt or getinfo option until `make test` and `make check-variadic` pass on the M1.
  - For M2:
    - a check of binding types against libcurl's prototypes;
    - `curlot-types` completeness;
    - `curl-easyoption`'s size;
    - `test-variadic`'s need for RTSP;
    - callables only as a define's whole right-hand side;
    - no nested-pattern helper macros;
    - a `__collect_safe` binder for `curl_easy_perform`.
  - Nothing checks that `src/` comes first in `LIBDIRS`.
  - CI has still never run.

### 2026-10-17 — M0 slice 5: the memory gate and CI (PR #8, `eda03a2`)

- **Valgrind is the memory gate** (ADR-0014). `make test-memory` runs every suite under
  exactly the gate's command, and a suite passes only on evidence from Valgrind's own log:
  its command, the Chez it read, and no errors. It refuses every `VALGRIND_*` variable and
  both `.valgrindrc` files, and holds each suite's options and suppressions to the gate's.
- **One suppression, in the container only.** Loading libcurl there loses one block in Guix's
  glibc. Ubuntu 24.04 loses nothing, so CI passes no suppression.
- **`make check-memory-gate` must see it fail:** a planted overrun, a planted leak, each
  hidden source of options, a forged log, and a run with no evidence.
- **CI's workflow:** the `main`, `floor`, `floor-disabled-api` (two lanes), `nothreads` and
  `memory` jobs. The gate runs on every pull request, push to `main` and tag, and actions are
  pinned to full SHAs. CI states no floor: its build scripts read `packaging/floors.sexp`
  (ADR-0016, amended), and `check-floors` holds every workflow file to that.
- **`make check-nothreads`** requires every public library to refuse, by name, a Chez built
  without threads. It fails on a threaded Chez by design, so CI runs it on a `--nothreads`
  build.
- **Valgrind cannot see Chez's heap.** An overrun into a bytevector passes, and so does a
  dropped block whose address an ftype pointer held. So `test-collect-safe` now holds every
  binding's types to an allowlist, and refuses a heap crossing without a reviewed mark. For
  M2, the maintainer decided on one checked wrapper for bytevector copies, and the counters
  as the leak gate.
- **Built with subagents,** nine in all, about 3.2M tokens, the most yet.
  - Each of three reviews found a class the last fix had left open: a deny list that
    `VALGRIND_LIB` walked round, passes taken from empty output, a pattern variable spelt
    like an allowed type, and a floor redefined in a job's `env:`.
  - The lesson: brief a check as "passes only on evidence", never as "refuses X".
- **Evidence:** the [mutation log](memory-ci-mutation-log.md), in eight parts. Every check
  has a red run, and every mutation fails its check by name.
- **Carried forward:**
  - CI's first run, once billing allows. Expect it to need fixes.
  - For M2: the checked bytevector wrapper, the counters as the leak gate, and `lock-object`
    for every callable C holds (ADR-0013).
  - Valgrind follows no child process, so the Chez processes `test-library-loading` spawns
    run unchecked.

### 2026-10-16 — M0 slice 4: constants and layouts, the convention suite and the floors (PR #7, `ba42f70`)

- **Checks constants and struct layouts against libcurl's own headers.** `test-constants`
  generates one C program from `constants.sls`'s exports and `layouts.sls`'s
  `define-ftype`s. It checks each constant's value, and each field's offset, size and kind.
  A C name follows from its Scheme name. The headers must be no newer than the library
  `(curl)` loads.
- **The structs live in `(curl private layouts)`,** held to struct `define-ftype` forms
  alone.
- **Checks every binding's conventions.** `test-collect-safe` holds every
  `foreign-procedure` and `foreign-callable` to a table, each row quoting the record
  sentence behind it. `curl_easy_perform` and `curl_multi_poll` already have
  `__collect_safe` rows (ADR-0013).
- **The floors have one source,** `packaging/floors.sexp` (ADR-0016). `make check-floors`
  holds the README to it, and the suites hold the code to it by behaviour.
- **`check-seam` rules (f) and (g)** keep `define-ftype` in layouts and stop any library
  re-exporting a Chez name. A function ftype would bind C that no other check sees.
- **The first macOS run,** on the maintainer's M1, passes all 13 suites. Two fixes got it
  there. A bare `mktemp -d` ignored `TMPDIR` on macOS, and Homebrew installs Chez as
  `chez`.
- **Built with subagents,** eight in all, about 2.1M tokens: the builders on Opus, Opus and
  Sonnet, two reviews on Opus, and two fix rounds.
  - The first review found that function ftypes could bind C unseen, and that nothing tied
    the headers to the library. Fields of the wrong kind passed, a test asserted message
    text, and a constant's C name was free text.
  - The review of the fixes walked round the `define-ftype` rule three ways: re-export, a
    macro argument, and an exported macro. That was a flaw in the fix brief, which named too
    narrow a class.
- **Evidence:** the [mutation log](constants-mutation-log.md), in six parts. Every check has
  a red run, and every mutation fails its check by name.
- **Carried forward:**
  - CI's floor lane must point both `C_INCLUDE_PATH` and `CHEZ_CURL_LIBCURL` at curl
    7.85.0, and CI's workflow joins what `check-floors` holds.
  - Known limits: the kind check can't tell a pointer from an aggregate of the same size,
    a name built at expansion is out of the convention suite's reach, and rule (g) sees
    bindings only.
  - Linux on arm64 and macOS on amd64 have not run.

### 2026-10-16 — M0 slice 3: loading libcurl, `(curl)` and the seam check (PR #6, `bfc3aa6`)

- **Loads libcurl as ADR-0002 says.** Discovery is a pure function of the environment: the
  override, or one candidate list per world. `native.sls` then loads once, reads
  `curl_version_info` first, checks the floor and SSL, calls `curl_global_init` once,
  binds every entry point after `foreign-entry?` finds it, and runs the two API probes.
- **Refusals stick.** Each is one of six reason symbols and carries the library's report
  once its version is read. `(curl private load-state)` records the first failure and raises
  it again at every later reference, so libcurl is never loaded twice.
- **`(curl)` reports what it loaded:** the path, its source, the version, the features and
  the TLS backend. `make build` is the preflight that prints it.
- **Refuses an unusable Chez by name:** one older than 10.4.0, a 10.4.0 pre-release, or one
  without threads, at expansion.
- **`check-seam` guards ADR-0007's boundary with allowlists,** and `make test` runs it.
  Every `src/` library is in one of the two families, and file endings Chez would load but
  the check can't read are refused by name.
- **Tests without the real thing:** decoy libcurls compiled at test time, a C oracle that
  reads the same library through `dlopen`, and an in-process suite for `native.sls`.
- **Built with subagents,** eight in all, about 2.8M tokens: the pure core and the native
  layer on Opus, `check-seam` on Sonnet in its own worktree, two reviews on Opus and three
  fix rounds.
  - The first review found a flaw in the brief itself: its import-order rule contradicted
    ADR-0007. It also found refusals that didn't stick, and tests that would fail on CI.
  - The second review found fixes that blocked only the reviewer's examples, a cleanup that
    could remove the wrong directory, and rules tested only in scratch.
- **Evidence:** the [mutation log](loading-mutation-log.md), in six parts. Every check has a
  red run, and every mutation fails its check by name.
- **Carried forward:**
  - Loading GnuTLS's libcurl leaks a block in p11-kit, which fails ADR-0014's gate. Decide
    before slice 5.
  - At M3, a first reference to `(curl)` from a second thread, while the load runs, raises
    `cyclic dependency`.
  - CI must run `make build`, which `make test` doesn't. The disabled-API lane should run the
    preflight and expect `missing-api`, rather than the full suite.
  - Nothing has run on macOS or arm64 yet.

### 2026-10-04 — M0 slice 2: the test harness (PR #5, `9bacc6d`)

- **Pinned SRFI-64.** `vendor/chez-srfi` is a submodule at `7879b52`, recorded in
  `Akku.lock`. `make deps` links it and never fetches. `make check-pins` holds the lock, the
  gitlink and the checkout equal, on the host.
- **Built the test loop.** `make test` runs every suite under GNU `timeout` (or `gtimeout`),
  names each as pass, FAIL or HUNG, and fails if any failed or hung, or if none exists.
- **Turned the suite rules into checks.**
  - `check-suites` requires the shared exit form last, and allows only `(exit 1)` before it.
  - `check-test-fails` plants eight bad cases, and `make test` must fail on each, by name.
- **Shared helpers** live in `tests/curl-testing.sls`. The exit verdict is 0 or 1, never a
  count, because exit statuses wrap at 256.
- **Took git out of the container again.** In a git worktree, the container's git could read
  nothing, so `make test` and `make check-guix` failed there. A `no-git` self-test assertion
  keeps it out (ADR-0006 amended).
- **Built with subagents.** Sonnet did the pins, Opus the harness core and an adversarial
  review, and Sonnet the review's fixes. The review found the worktree failure, a flaw in
  the brief itself.
- **Evidence:** the [mutation log](test-harness-mutation-log.md). Each check has a red run,
  and each mutation fails its check by name. The rewritten `check-suites` got fresh mutants
  after the fixes.
- **Carried forward:**
  - `capture-command` shares one counter across threads and writes predictable `/tmp`
    names. Fix it before the first threaded suite (M3).
  - `check-suites` refuses a suite that starts with a `#!` line.
  - The Node origin's helpers wait for the slice that adds `tests/origin.mjs`.

### 2026-10-04 — M0 slice 1: the pinned container and the Makefile skeleton (PR #4, `e8a2f63`)

- **Built ADR-0006's container, with Valgrind.** `scripts/guix-env` runs the pinned
  toolchain with no network. `make check-guix` tests the launcher on the host (60 checks),
  then checks the container from inside. A cached start takes about 1.5 s.
- **Checked the help.** `check-help` holds `make help`'s own listing equal to `.PHONY`,
  both ways.
- **Measured, and amended ADR-0006:**
  - the pinned toolchain has no `cc`, so the container exports `CC`;
  - `--emulate-fhs` does not let Guix's Chez load a library by bare name;
  - `LD_LIBRARY_PATH` does, so the self-test asserts that such a load fails.
- **Evidence:** the [mutation log](guix-env-mutation-log.md) records 50 mutations, each
  failing its check by name. The red run caught a launcher test that passed for the wrong
  reason.
- **Carried forward:** `GOAL`'s `MAKECMDGOALS` branch stays unexercised until a target
  reaches `require-tools` through a prerequisite, which is slice 2's `test`.

### 2026-10-04 — living brief, harness plan, memory and test records (PR #3, `ea56eb4`)

- **The brief is a living document,** accepted for M0. It cites the records and defers to
  them where they disagree.
- **Recorded how M0 checks itself:**
  - ADR-0014: Valgrind on Linux is the memory gate, and it must be seen to fail.
  - ADR-0015: SRFI-64 comes from a vendored chez-srfi pinned in `Akku.lock`, and the suite
    rules are checks.
- **Planned the harness.** The harness plan covers what M0 copies from chez-cmark-gfm and
  chez-libuv, seven improvements on them, CI's lanes, and five slices.
- **Corrected two records:**
  - ADR-0006 gained Valgrind. It had been lost by copying cl-commonmark-gfm's container
    rather than chez-cmark-gfm's.
  - ADR-0013's E5 figures are chez-http-server's, measured on macOS only.
- **Renamed** `CHANGELOG.org` to `CHANGELOG.md`.
- **Carried forward:** close-outs written after a merge still land one PR late, as this
  one does.

### 2026-10-04 — ledger, constraints and the engine records (PR #2, `9077e28`)

- **Moved the ledger to `.plans/`.** AGENTS.md names this file as the ledger and
  `global-constraints.md` as the hard rules every task brief must follow. `/.superpowers/`
  is git-ignored plugin scratch.
- **Recorded the brief's engine rules.** ADR-0012 (accepted): one engine thread owns every
  transfer handle. ADR-0013 (proposed until spike E1): blocking calls are `__collect_safe`,
  and so is every callback they can invoke.
- **Carried forward:** close-outs written after a merge land one PR late, as this one did.

### 2026-10-04 — open decisions settled (PR #1, `407a8c5`)

- **Settled:** D1 to D11, as ADR-0001 to ADR-0011. That is the brief's D1 to D5, plus
  D6 to D11 raised while checking the brief against this host.
- **What changed the brief:**
  - Chez 10's `(__varargs_after n)` removed the C shim (ADR-0001).
  - Guix Chez cannot load the host's libcurl, so discovery reads which world it runs in
    (ADR-0002).
  - The floor moved to 7.85.0 for `CURLOPT_PROTOCOLS_STR` (ADR-0003).
  - A container without `--network` keeps tests on loopback (ADR-0006).
- **Carried forward:** the probes run while deciding are M0's first tests in waiting:
  - varargs setopt;
  - the census of the options API;
  - world detection via `/proc/self/maps`;
  - `curl_url`'s verdicts;
  - the header-API probe;
  - the loopback-only container.

  They lived in session scratch and need writing as real tests.
