# Guix development container mutation log

Evidence that the checks M0 slice 1 added fail through the property each claims to guard
([harness plan](2026-10-04-harness-plan.md) §6, [ADR-0006](decisions/0006-pinned-guix-container.md)).
Every mutation was applied to a fresh copy of the working tree, made without `.git` in the
session scratchpad. The working tree was never edited. A driver applied each mutation,
recorded its diff, flagged any that changed nothing, and kept the failures verbatim.

`/bin/sh` is dash on the host these ran on, so the scripts and the host-side tests ran under
a strict POSIX shell. Inside the container, `sh` is bash.

Each mutation ran in its own copy, so the clean rerun after each one is the baseline itself.
A last run of the working tree, after every fix below, gave both baselines again.

## Host side (`tests/guix-env-launcher.sh`)

**Red run, before any script or the Makefile existed:** `24 passed, 36 failed`, exit 1. The
first failure was `FAIL T1 no-args exits 0`. The 24 that passed were:

- **The absence checks** (`lacks`, `! -s`, `! -e`), which a missing script satisfies.
- **R2, R4, R5 and R6's "exit 2".** dash exits 2 when it cannot open a script. Each also
  asserts its exact stderr, and that assertion failed.
- **`M1 … fails`.** make fails without a Makefile too.
- **`T6 enter on host: points at scripts/guix-env`.** This was a false pass, not an
  absence check. dash's own error, `cannot open …/scripts/guix-env-enter`, contains that
  string. T6 now compares the whole of stderr.

Each check that passed in the red run has a mutation below that fails it.

**Baseline:** `60 passed, 0 failed`, exit 0, on `ea56eb4` plus this slice.

### L1. No network

**Guards:** the container gets no `--network` (ADR-0006 §1).
**Mutation:** `--network` added after `--container`.
**Result:** `58 passed, 2 failed`: `FAIL T1 no network flag`, `FAIL T1 the whole command`.

### L2. No FHS emulation

**Guards:** no `--emulate-fhs` (ADR-0006 §4).
**Mutation:** `--emulate-fhs` added after `--container`.
**Result:** `58 passed, 2 failed`: `FAIL T1 no emulate-fhs flag`, `FAIL T1 the whole command`.

### L3a. Only three variables are let in

**Guards:** `--preserve` names only `TERM`, `COLORTERM` and `LANG` (ADR-0006 §1).
**Mutation:** `SSH_AUTH_SOCK` added to the pattern.
**Result:** `56 passed, 4 failed`: `FAIL T1 preserves only TERM, COLORTERM and LANG`,
`FAIL T1 the whole command`, `FAIL T3 [make check-guix-inside] no agent socket`,
`FAIL T3 [no-args] no agent socket`.

### L3b. One `--preserve` flag

**Mutation:** a second flag, `'--preserve=^HOME$'`.
**Result:** `58 passed, 2 failed`: `FAIL T1 preserves only TERM, COLORTERM and LANG`,
`FAIL T1 the whole command`.

### L4a. Nothing of HOME is shared

**Guards:** the container receives nothing from HOME.
**Mutation:** `"--share=$HOME/.ssh"` added.
**Result:** `55 passed, 5 failed`: `FAIL T1 the whole command`, and for both T3 cases
`no --share` and `nothing from HOME`.

### L4b. Nothing of HOME is exposed

**Mutation:** `"--expose=$HOME/.gitconfig"` added.
**Result:** `55 passed, 5 failed`: `FAIL T1 the whole command`, and for both T3 cases
`no --expose` and `nothing from HOME`.

### L5. Nesting is refused

**Mutation:** the `GUIX_ENVIRONMENT` refusal block deleted.
**Result:** `57 passed, 3 failed`: `FAIL T4 nested: exit 2`,
`FAIL T4 nested: names GUIX_ENVIRONMENT`, `FAIL T4 nested: prints no command`.

### L6. The container gets the repo root from any directory

**Mutation:** `cd "$root"` deleted.
**Result:** `59 passed, 1 failed`: `FAIL T5 subdirectory: runs from the repo root`. The dry
run prints `$PWD`, not `$root`; printing `$root` would have let this pass with the `cd` gone.

### L7. Arguments pass through verbatim

**Mutation:** `"$@"` unquoted in the guix command.
**Result:** `59 passed, 1 failed`: `FAIL T2 args pass through verbatim`.

### L8. No arguments means bash

**Mutation:** `set -- bash` changed to `set -- sh`.
**Result:** `58 passed, 2 failed`: `FAIL T1 enters through guix-env-enter`,
`FAIL T1 the whole command`.

### L9. Guix is pinned

**Mutation:** `-C channels.scm` dropped.
**Result:** `57 passed, 3 failed`: `FAIL T1 pins guix via channels.scm`,
`FAIL T1 uses manifest.scm`, `FAIL T1 the whole command`. `uses manifest.scm` reads line 9,
so it failed because the lines shifted, not through its own property (see Not covered).

### L10. The container flag

**Mutation:** `--container` dropped.
**Result:** `58 passed, 2 failed`: `FAIL T1 container flag`, `FAIL T1 the whole command`.

### E1. The entry script refuses to run on the host

**Mutation:** its `GUIX_ENVIRONMENT` refusal block deleted.
**Result:** `58 passed, 2 failed`: `FAIL T6 enter on host: exit 2`,
`FAIL T6 enter on host: says why, and what to use`. `T6 … runs nothing` still passed: with
the refusal gone, `set -u` stops the script at the first `need`. E10 fails it.

### E2. No `LD_LIBRARY_PATH`

**Guards:** ADR-0006 §4.
**Mutation:** `export LD_LIBRARY_PATH="$GUIX_ENVIRONMENT/lib"` before the `exec`.
**Result:** `59 passed, 1 failed`: `FAIL T7a no LD_LIBRARY_PATH`.

### E3. The override names the profile's entry

**Guards:** the self-test needs the name `libcurl.so.4`, not the store file's.
**Mutation:** `CHEZ_CURL_LIBCURL` set to `$(readlink -f …)`.
**Result:** `59 passed, 1 failed`: `FAIL T7a CHEZ_CURL_LIBCURL is the profile's libcurl.so.4`.

### E4. A profile without libcurl is refused

**Mutation:** `need "$GUIX_ENVIRONMENT/lib/libcurl.so.4"` deleted.
**Result:** `54 passed, 6 failed`: `exit 2`, `names …/lib/libcurl.so.4` and `runs nothing`,
for both T7b (no file) and T7c (a dangling symlink).

### E5. A dangling symlink is not a library

**Mutation:** `need` widened to `{ [ -f "$1" ] || [ -L "$1" ]; }`.
**Result:** `57 passed, 3 failed`: T7c's `exit 2`, `names …/lib/libcurl.so.4` and
`runs nothing`.

### E6. A profile without Chez or gcc is refused

**Mutation:** E6a deleted `need …/bin/scheme`; E6b deleted `need …/bin/gcc`.
**Result:** `57 passed, 3 failed` each: T7d's, then T7e's `exit 2`, `names …` and
`runs nothing`.

### E7. No state directory

**Guards:** ADR-0006 §4.
**Mutation:** `mkdir -p "$PWD/.guix-env"` before the `exec`.
**Result:** `59 passed, 1 failed`: `FAIL T7a no state directory`.

### E8. The command runs verbatim

**Mutation:** `exec "$@"` unquoted.
**Result:** `54 passed, 6 failed`: T7a's five checks, since its command is one
`sh -c '…'` argument that splits, and `FAIL T8 enter passes args verbatim`.

### E9. Exports are the profile's paths, not bare names

**Mutation:** E9a set `CC=gcc`; E9b set `CHEZ=scheme`.
**Result:** `59 passed, 1 failed` each: `FAIL T7a CC is the profile's gcc`, then
`FAIL T7a CHEZ is the profile's scheme`.

### E10. Nothing runs before the checks

**Mutation:** `exec "$@"` inserted right after `set -eu`.
**Result:** `42 passed, 18 failed`, including `FAIL T6 enter on host: runs nothing` and the
`runs nothing` check of T7b, T7c, T7d and T7e.

### Q1. Inside an environment, the hint is not the container

**Mutation:** `&& [ -z "${GUIX_ENVIRONMENT:-}" ]` dropped from the hint's condition.
**Result:** `59 passed, 1 failed`: `FAIL R4 inside an environment: install hint`.

### Q2. Every missing tool is named

**Mutation:** `break` after the first missing tool.
**Result:** `59 passed, 1 failed`: `FAIL R3 two missing: both named, then one hint`.

### Q3. A goal with no tools is a usage error

**Mutation:** the usage test `-lt 2` changed to `-lt 1`.
**Result:** `58 passed, 2 failed`: `FAIL R6 no tools: exit 2`, `FAIL R6 no tools: usage`.

### Q4. Silent when every tool is found

**Mutation:** `echo "all found"` before the success exit.
**Result:** `59 passed, 1 failed`: `FAIL R1 all found: silent`.

### Q5. require-tools can fail

**Mutation:** `exit 0` right after `set -eu`.
**Result:** `49 passed, 11 failed`: every `exit 2` and stderr check of R2 to R6, and
`FAIL M1 … names the goal`, `FAIL M1 … runs no test`.

### Q6. `check-guix` requires guix

**Mutation:** the recipe's `@scripts/require-tools "$(GOAL)" guix` line deleted.
**Result:** `58 passed, 2 failed`: `FAIL M1 make check-guix without guix: names the goal`,
`FAIL M1 make check-guix without guix: runs no test`. The stub `sh` ran.

### Q7. The hint names the goal

**Mutation:** `$goal` dropped from the container hint.
**Result:** `58 passed, 2 failed`: R2's and R3's stderr checks.

### Q8. `check-guix` fails when its recipe does

**Mutation:** each recipe line prefixed with `-`, so make ignores its errors.
**Result:** `58 passed, 2 failed`: `FAIL M1 make check-guix without guix: fails`,
`FAIL M1 make check-guix without guix: runs no test`.

## `make check-help`

**Baseline:** exit 0, silent.

### H1. A target without a description

**Mutation:** `## ` removed from `check-guix`'s line.
**Result:** exit 2: `check-help: make help does not list .PHONY target 'check-guix'; …`.

### H2. A described target outside `.PHONY`

**Mutation:** `check-guix-inside` removed from `.PHONY`.
**Result:** exit 2: `check-help: make help lists 'check-guix-inside', which is not in .PHONY`.

### H3. `.PHONY` on one line

**Mutation:** `.PHONY` continued over two lines with a backslash.
**Result:** exit 2. `the .PHONY line ends in a backslash; keep it on one line`, plus
`check-guix` and `check-guix-inside` reported as listed but not in `.PHONY`.

### H4. The listing is what is checked

**Guards:** `check-help` reads `make help`'s output, not the Makefile's text.
**Mutation:** `help`'s awk pattern narrowed to `/^[a-z]+:.*?## /`.
**Result:** exit 2: `check-help`, `check-guix` and `check-guix-inside` reported as not listed.

### H5. Finding: a broken `make help` was misreported

**Mutation:** `## ` removed from `help`'s own line. make then reads the description's words
as prerequisites, and `make help` fails on `No rule to make target 'Show'`.
**First result:** all four targets reported as not listed. That was true, but it named the
wrong cause.
**Fix:** `check-help` now stops with `check-help: make help failed` when `make help` exits
non-zero.
**Result after the fix:** exit 2: `check-help: make help failed`.

## Container (`make check-guix-inside`)

**Red run, before `scripts/guix-env-enter` exported anything:** the self-test was run in the
bare pinned container,
`guix time-machine -C channels.scm -- shell -m manifest.scm --container -- sh scripts/guix-env-selftest`.
It exited 1, with seven assertions failing:

- `chez-variable`, `chez-is-elf`, `valgrind-instruments-chez`;
- `cc-variable`, `curl-headers`;
- `libcurl-override`;
- `no-bare-name-load` (`'unset' exited 127, expected 3`).

`isolated-home`, the fourteen `tool-path` checks and `loopback-only` passed. They test the
container, not the entry script, and each has a mutation below.

**Baseline:** `check-guix: ALL CHECKS PASSED`, exit 0. `make check-guix` ran end to end in
1.4 s.

### S1. No container at all

**Mutation:** `--container` dropped, so plain `guix shell` runs in the host's environment.
**Result:** exit 2. Forty-seven `FAILED isolated-home: … is visible inside the container`
lines, among them `.ssh`, `.gnupg` and `.gitconfig`, and
`FAILED loopback-only: loopback accepted; 192.0.2.1 silent for 5s`. `tool-path` passed:
this host's login files put no other copy of the tools first. S12 fails it.

### S2. No network but loopback

**Mutation:** `--network` added.
**Result:** exit 2: `FAILED loopback-only: loopback accepted; 192.0.2.1 silent for 5s`.

### S3. FHS emulation (survived)

**Mutation:** `--emulate-fhs` added.
**Result:** exit 0, every assertion passed. A probe in that container found
`/lib/libcurl.so.4`, `/usr/lib/libcurl.so.4` and `/etc/ld.so.cache` all present. Chez's
bare-name `load-shared-object` was still refused (exit 3), and an absolute `/usr/lib` path
loaded (exit 4). Chez's loader is Guix's glibc 2.41, which searches none of them. So
`no-bare-name-load` does not guard this flag, and nothing in the self-test can: the property
it would protect holds either way. L2 guards the flag. ADR-0006's amendment records this.

### S4. No bare-name load

**Mutation:** `export LD_LIBRARY_PATH="$GUIX_ENVIRONMENT/lib"` in the entry script.
**Result:** exit 2: `FAILED no-bare-name-load: Chez loaded libcurl.so.4 by bare name
(LD_LIBRARY_PATH=/gnu/store/…-profile/lib)`.

### S5a. `CHEZ` is a wrapper that execs Chez

**Mutation:** `CHEZ` pointed at a script that `exec`s the profile's `scheme`.
**Result:** exit 2: `FAILED chez-variable`, `FAILED chez-is-elf: … starts with '23212f67',
not an ELF header`, and `FAILED valgrind-instruments-chez: … printed no ERROR SUMMARY`.

### S5b. `CHEZ` is a wrapper that runs Chez without `exec`

**Mutation:** the same script, without `exec`.
**Result:** exit 2: `FAILED chez-variable`, `FAILED chez-is-elf`. `valgrind-instruments-chez`
passed: Valgrind reported on the shell and printed its `ERROR SUMMARY`, as chez-cmark-gfm
found. `chez-is-elf` is the assertion that catches this one.

### S6. `CHEZ` is a symlink named `chez`

**Mutation:** `CHEZ` pointed at a `chez` symlink to the profile's `scheme`.
**Result:** exit 2: `FAILED chez-variable`, and
`FAILED no-bare-name-load: … exited 134, expected 3`: Chez aborted looking for `chez.boot`.
`chez-is-elf` and `valgrind-instruments-chez` passed, since both follow the symlink.

### S7. The override is the profile's own file

**Mutation:** `libcurl.so.4` copied out of the store, and `CHEZ_CURL_LIBCURL` pointed at the
copy.
**Result:** exit 2: `FAILED libcurl-override: CHEZ_CURL_LIBCURL is '…/.mut/libcurl.so.4',
expected /gnu/store/…-profile/lib/libcurl.so.4`.

### S8. The compiler finds libcurl's headers

**Mutation:** `unset C_INCLUDE_PATH` in the entry script. gcc still finds `stdio.h` without
it; a probe confirmed that first.
**Result:** exit 2: `FAILED curl-headers: … could not compile against <curl/curl.h>: …
fatal error: curl/curl.h: No such file or directory`.

### S9. `CC` is the profile's gcc

**Mutation:** `export CC=gcc`.
**Result:** exit 2: `FAILED cc-variable: CC is 'gcc', expected under /gnu/store/…-profile`.
`curl-headers` passed: gcc is on PATH.

### S10. The Makefile's checks run inside

**Mutation:** `## ` removed from `help`'s line.
**Result:** exit 2: `check-help: make help failed`, then `FAILED check-help`.

### S11. Nothing of HOME is visible

**Mutation:** `--expose=$HOME/.gitconfig` added.
**Result:** exit 2: `FAILED isolated-home: /home/…/.gitconfig is visible inside the container`
and nothing else.

### S12. A login shell runs the profile's tools

**Mutation:** a stub `curl` put ahead of the profile on `PATH`.
**Result:** exit 2: `FAILED tool-path[-lc]` and `FAILED tool-path[-lic]` for `curl`, each
naming the stub and the expected store path.

## Not covered

- **`GOAL`'s `MAKECMDGOALS` branch.** No target in this slice reaches `require-tools`
  through a prerequisite, so `GOAL`, `$@` and `MAKECMDGOALS` agree in every run. A mutation
  replacing `$(GOAL)` with `$@` would survive. Slice 2's `test` is the first case that can
  tell them apart.
- **`isolated-home` allows the directories that lead to the repository.** Sharing one of
  them whole, such as `--share=$HOME/src`, would pass. This is inherited from both
  siblings.
- **`loopback-only` probes one outside IPv4 address,** and no IPv6.
- **`--emulate-fhs` inside the container** (S3). Only L2 catches it.
- **`T1 uses manifest.scm` is positional.** L9 failed it because the lines shifted. `T1 the
  whole command` is the check that pins the manifest's place.
