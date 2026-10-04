# ADR-0006: Builds and tests run in a pinned, toolchain-only Guix container with no network

- **Status:** Accepted; amended 2026-10-04 to add Valgrind
  ([ADR-0014](0014-valgrind-memory-gate.md)), and again on 2026-10-04 with what M0 slice 1
  measured ([amendment](#amendment-2026-10-04-what-slice-1-measured))
- **Date:** 2026-10-04
- **Scope:** development tooling. No library change.
- **Settles:** D11. That decision was raised on 2026-10-04, after the brief was written.
- **Prior art:** cl-commonmark-gfm ADR-0004, whose launcher this copies, and chez-cmark-gfm
  ADR-0018 and ADR-0019
- **Related:** [ADR-0001](0001-bind-libcurl-directly.md) (a C compiler and libcurl's headers
  at test time) · [ADR-0002](0002-runtime-libcurl-discovery.md) (the override, and discovery
  in a Guix world) · [ADR-0005](0005-node-test-origin.md) (Node and the `openssl` command
  line) · brief §7 (no test touches the public internet)

## Context

The maintainer develops on Guix. Builds and tests need:

- Chez ≥ 10.4.0, threaded;
- libcurl ≥ 7.85.0 with its headers;
- a C compiler for the constants check;
- Node ≥ 20;
- the `openssl` command line;
- `make` and the usual shell tools.

Outside Guix, this host has no Node, and its libcurl is one Guix Chez cannot load
(ADR-0002). The pin both sibling repositories use, `b532aa7d…`, is also this host's current
Guix. At it, Guix provides chez-scheme 10.4.0, curl 8.20.0 (headers included) and node
24.18.0.

Two sibling repositories already settled how to do this. chez-cmark-gfm's ADR-0019 made the
container toolchain-only: agents edit and commit on the host. cl-commonmark-gfm's ADR-0004
refined it:

- `scripts/guix-env-enter` exports the library override from the profile;
- `scripts/require-tools` fails fast when a tool is missing;
- `GUIX_ENV_DRY_RUN` lets host-side tests check the launcher;
- `make check-guix` runs those tests and a self-test inside the container.

Both run their containers with `--network`. cl-commonmark-gfm needs it, because ocicl fetches
systems. chez-curl fetches nothing at build or test time. Measured at the pin: a
`guix shell --container` started without `--network` has one interface, `lo`. A loopback
connect and accept succeed, and connecting to 192.0.2.1 fails with "Network is unreachable".

## Decision

**Copy cl-commonmark-gfm's container, with the choices below for chez-curl.**

1. **The launcher.** `scripts/guix-env` runs
   `guix time-machine -C channels.scm -- shell -m manifest.scm --container -- sh scripts/guix-env-enter CMD…`.
   - It runs without `--network`.
   - The default command is `bash`.
   - It refuses to run inside a Guix environment.
   - It preserves only `TERM`, `COLORTERM` and `LANG`.
   - `GUIX_ENV_DRY_RUN=1` prints the command instead of running it, for the host-side
     launcher tests.
2. **The pin.** `channels.scm` pins Guix at `b532aa7d0bb345aafabf6b63cbfbda45abbec091`, the
   siblings' pin.
3. **The manifest.** `manifest.scm` holds:
   - `chez-scheme`, `curl` (library and headers) and `gcc-toolchain` (ADR-0001, ADR-0003);
   - `node` and `openssl` (ADR-0005);
   - `valgrind`, for the memory gate (ADR-0014, added 2026-10-04);
   - the shell tools the Makefile and scripts call, and nothing else.

   Each entry carries a comment naming the decision that needs it.
4. **What `scripts/guix-env-enter` sets inside the container:**
   - **`CHEZ`** is `$GUIX_ENVIRONMENT/bin/scheme`, the real binary. A `chez` symlink breaks
     boot-file lookup, and a wrapper script hides Chez from Valgrind (chez-cmark-gfm
     `traps.md`).
   - **`CC`** is `$GUIX_ENVIRONMENT/bin/gcc`. `gcc-toolchain` installs no `cc` at the pin,
     so make's default `CC` would find no compiler (amended 2026-10-04).
   - **`CHEZ_CURL_LIBCURL`** is `$GUIX_ENVIRONMENT/lib/libcurl.so.4`, the profile's own
     entry rather than the store file behind it. So the suites never depend on discovery
     (ADR-0002). The script refuses to start when this file, `bin/scheme` or `bin/gcc` is
     missing (amended 2026-10-04).
   - **No `LD_LIBRARY_PATH` and no `--emulate-fhs`.** Nothing here loads a library by bare
     name (ADR-0002). `LD_LIBRARY_PATH` would make a bare-name load succeed by accident,
     and the self-test checks that one fails. `--emulate-fhs` stays out because ADR-0002
     never searches standard directories in a Guix world. Measured, it does not make
     Guix's Chez load by bare name (amended 2026-10-04).
   - **No `.guix-env/` state directory and no `GUIX_ENV_MANIFEST`.** Nothing in this
     toolchain keeps state between runs, and there is no second manifest. Each can be added
     the way cl-commonmark-gfm has it, when something needs it.
5. **`scripts/require-tools GOAL TOOL…`** fails a target before it runs when a tool is
   missing. On a Guix host outside any environment, it points at `scripts/guix-env make GOAL`.
6. **`make check-guix`** runs the host-side launcher tests, then `make check-guix-inside` in
   the container. That self-test asserts:
   - the container's `HOME` is isolated;
   - Chez, curl, node, openssl, gcc, Valgrind and make resolve to the profile's own
     binaries, however a login shell finds them (gcc stands in for `cc`, which the
     toolchain lacks; amended 2026-10-04);
   - `CHEZ` lies under the profile and is an ELF binary;
   - `CC` lies under the profile, and compiles a program against `<curl/curl.h>` (added
     2026-10-04);
   - `CHEZ_CURL_LIBCURL` is exactly `$GUIX_ENVIRONMENT/lib/libcurl.so.4`, and exists
     (amended 2026-10-04);
   - no library loads by bare name: Chez's `load-shared-object` of `libcurl.so.4` is
     refused (added 2026-10-04);
   - the network is loopback only: a loopback connect succeeds and an outside address is
     unreachable;
   - Valgrind instruments `$CHEZ`: a run under it prints an `ERROR SUMMARY` line, as
     chez-cmark-gfm's self-test checks (added 2026-10-04, for ADR-0014);
   - the Makefile's own checks pass inside it (added 2026-10-04).

   Each assertion is watched failing under a targeted change before it counts.
7. **Agents and people edit, commit and push on the host.** Builds and tests go through
   `scripts/guix-env`. AGENTS.md gains a container section when the scripts land.

### Rejected

- **`--network`, as both siblings use.** Nothing here fetches at build or test time. Without
  it, brief §7's "no test touches the public internet" is a property of the environment,
  checked by the self-test, not a convention.
- **`--emulate-fhs`, from chez-cmark-gfm.** It existed there so discovery could search
  standard directories inside the container. ADR-0002 never searches them in a Guix world.
- **Plain `guix shell -m manifest.scm`.** It is unpinned, and the host leaks in: a login
  shell rebuilds `PATH` (chez-cmark-gfm `traps.md`).
- **Agents inside the container.** chez-cmark-gfm tried it in ADR-0018 and withdrew it in
  ADR-0019.

## Consequences

- **Anything that needs the network runs on the host.** That includes git, and fetching
  the floor lane's curl tarball (ADR-0003). Fetching can't happen in the container at all.
- **The container is for x86_64 Linux hosts like this one.** The Mac does not use it.
- **Each `scripts/guix-env` call pays the `time-machine` startup.** That was about one second
  here for a cached one-package profile. A first run downloads the manifest's packages.
  Batch commands: `scripts/guix-env sh -c 'make a && make b'`.
- **Discovery's three branches all get a real run.** ADR-0002's install check, run here with
  the override unset, takes the Guix branch. CI takes the standard-directory branch, and the
  Mac takes Apple's.
- **No CI job runs the container.** CI's toolchain comes from ADR-0001 (Chez built from the
  release tarball), the runner's libcurl (ADR-0002) and the runner's Node (ADR-0005). The
  pinned container and the unpinned runner can drift, which is why every run records the
  versions it used.
- **The container isolates the toolchain; it is not a sandbox.** The repository is shared
  read-write, and the host later runs what the container writes there.
- **Bumping the pin** means changing `channels.scm` and running `make check-guix`.

## Amendment, 2026-10-04: what slice 1 measured

M0 slice 1 built this container and watched each of its checks fail
([mutation log](../guix-env-mutation-log.md)). Three findings changed the text above:

- **`gcc-toolchain` installs `gcc` but no `cc` at the pin.** The container exports `CC`,
  as it exports `CHEZ`, and the self-test checks `gcc` and `$CC`.
- **`--emulate-fhs` does not let Guix's Chez load a library by bare name.** With the flag,
  `/lib/libcurl.so.4`, `/usr/lib/libcurl.so.4` and `/etc/ld.so.cache` all exist. Chez's
  `load-shared-object` of `libcurl.so.4` is still refused, while an absolute `/usr/lib`
  path loads. That Chez's loader is Guix's glibc, which searches none of them. The flag
  stays out for ADR-0002's reason. The launcher's test checks that it is absent; no
  self-test assertion can tell, and the property one would guard holds either way.
- **`LD_LIBRARY_PATH` does let it.** Set to the profile's `lib`, it makes that same
  bare-name load succeed. The self-test now asserts that the load fails.
