# AGENTS.md

## Project guidelines

### Architecture & portability

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Project is built for Chez Scheme
* Project should be portable across macos (darwin) and linux; windows is not
  supported (`.plans/decisions/0004-windows-not-supported.md`)
* Project should be portable across amd64 and arm64
* **DO NOT** setup macos CI runners: linux only!
* Exported functions should have a comment with a Typed Racket style type signature
* A Chez Scheme library binding the libcurl C library through the FFI;
  handle C *safely*. Portable across darwin, linux, on amd64 and arm64.

### Dependencies

* libcurl

### Guix development container

* **On a Guix host, run every build and test through `scripts/guix-env`**,
  e.g. `scripts/guix-env make test`. Batch commands with
  `scripts/guix-env sh -c 'make a && make b'`: each call takes a second or
  more to start.
* Edit, commit and push on the host. The container has no git identity,
  agents or tokens, and no network but loopback (ADR-0006).
* Verify it with `make check-guix`, run on the host.
* The container exports `CHEZ` (the real `scheme` binary), `CC` (gcc; the
  toolchain has no `cc`) and `CHEZ_CURL_LIBCURL` (the profile's
  `libcurl.so.4`, ADR-0002). It sets no `LD_LIBRARY_PATH`.
* Anything that needs the network or git runs on the host: fetches, pushes,
  downloads, `make check-pins`, and `git submodule update --init`, which a
  fresh clone needs once before `make deps`. The container has no git.

### Layout, process & libraries

* Plans live in `/.plans`, decision records in `/.plans/decisions`
* The ledger is `/.plans/progress.md`: where the project stands, the next
  slice, and a close-out for each merged slice. `/.plans/global-constraints.md`
  holds the decision records' hard rules and binds every task brief. Read both
  before starting slice work. `/.superpowers/` is git-ignored plugin scratch,
  not the ledger.
* Add entries to `CHANGELOG.md` for each release
* `/docs` is for user facing documentation only.
* Documentation should be very concise, focused, to the point, ELI5 style.
* `Makefile` should have a `help` command which lists all of its commands
* Libraries are R6RS `.sls`; libraries and programs contain their own code —
  no shared include bodies. R6RS forbids assigning an exported variable —
  reach mutable state through procedures.

### Testing & mutation discipline

* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
* A test is not finished when it passes. It is finished when you have watched
  it fail.
* Prefer a check to a comment.
* **Do not** write tests that rely on reading code comments
* `make test` runs every suite under GNU `timeout`. On macOS, run
  `brew install coreutils`, and make finds its `gtimeout`.

## Traps the family has already hit

Each shipped a green test or a working-looking build that was wrong, in
chez-cmark-gfm, chez-libuv or here. The incident behind each is in
`.plans/traps.md`; read it before working in that area.

**Tests**

* `guard` returns the body's value when nothing raises, and `0` is truthy.
  Assert *what was raised* against an expected value, with a distinct sentinel
  for the no-raise case.
* SRFI-64 turns an exception in the *actual* expression into `#f`. Never
  expect `#f` from something that can raise.
* Every `tests/test-*.sps` must end with `(exit (suite-exit-status runner))`:
  SRFI-64 sets no exit status. Anything after that line never runs, and
  `make check-suites` checks it is there.
* An exit status is taken modulo 256, so `(exit 256)` exits 0. Exit with 0 or
  1, never a count.
* A suite cannot vouch for the verdict it exits through. A suite that tests
  `suite-exit-status` must also exit 1 on its own failures, before the
  shared form.
* Chez evaluates arguments right to left in compiled library code, left to
  right when interpreted. No assertion may depend on argument order.
* An assertion passes whenever *another* rule can produce its expected value.
  Assert whole outputs, not substrings, and build a test's base from
  non-default values.

**Chez and the FFI**

* `foreign-procedure` resolves its entry point when evaluated, so every
  binding must follow the library's load. Mistakes fail at *import*.
* A library body runs only when one of its bindings is *referenced*. A test of
  load-time behaviour must call into the library.

**Checks and environment**

* Deleting a subsystem disarms the checks built around it, and they stay
  green. On any deletion, ask of every surviving check "what would make this
  fail now?"; "nothing" is a defect.
* Point `CHEZ` at the real binary: a symlink breaks boot-file lookup, and a
  wrapper script hides Chez from Valgrind. `make check-guix` checks it.
* Put `timeout` outside Valgrind, never between it and Chez: Valgrind checks
  only the command it is handed.
* `guix shell --pure` does not stop a login shell from rebuilding `PATH`.
  `scripts/guix-env` uses `--container`, and `make check-guix` checks where a
  login shell finds each tool.
* `guix shell -m` reuses its cached profile while the manifest is no newer
  than the cache, so a copy that keeps old file times (`tar`, `cp -p`) runs
  the old toolchain. `touch` a manifest that a mutation changes.
* In an empty submodule directory, `git -C` answers for the superproject.
  Compare `git -C <dir> rev-parse --show-toplevel` with the directory itself
  before trusting anything else it says.
* In a git worktree, `.git` points outside the working directory, so a
  container that shares only the working directory sees no repository. Keep
  git on the host.

## Closing ritual

We run this when we're done and ready to merge the PR.

**Important**: ALWAYS ask before running this.

1. Squash merge the PR.
2. Catch up local `main`.
3. Clean up branches. Delete the merged branch locally and on the remote.
4. Reflect.
